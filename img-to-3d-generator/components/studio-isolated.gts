// The studio's working view — the whole instrument panel: the reference
// strip, the viewport with its draft renders, the generate/refine pipeline,
// the lasso/instruction editor, and the history popover. It lives apart from
// the card definition for the same reason the pipeline utils do: the card
// file declares what a studio IS (fields, embedded/fitted tiles), while this
// class is the several-thousand-line answer to what the isolated view DOES.

import {
  Component,
  realmURL,
  FileDef,
} from 'https://cardstack.com/base/card-api';
import { codeRef } from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { restartableTask } from 'ember-concurrency';

import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import WriteTextFileCommand from '@cardstack/boxel-host/tools/write-text-file';
import UseAiAssistantCommand from '@cardstack/boxel-host/commands/ai-assistant';
import ImgTo3dPopover from './i3d-popover';

import { fetchAsDataUrl, slugify, writeRealmImage } from '../util/realm-image';
import {
  cropWithBackgroundRemoved,
  revolvedSilhouetteBbox,
  traceLatheProfile,
  traceSilhouetteSvg,
  type TracedOutline,
} from '../util/silhouette';
import {
  generateModelJs,
  generateViewerSrcdoc,
  generateViewerSrcdocInline,
  specFromModelJs,
} from '../util/code-export';
import {
  VISION_MODEL,
  ASSISTANT_MODEL,
  ANALYSIS_MODEL,
  requestSpec,
  seedFromStrings,
} from '../util/llm-request';
import {
  AUTO_REFINE_ROUNDS,
  AUTO_VERIFY_ROUNDS,
  REFINE_TARGET_SCORE,
} from '../util/pipeline-config';
import { composeComparison } from '../util/comparison-sheet';
import { serializeSpecForPrompt, parseDiffJson } from '../util/spec-io';
import {
  applySpecDiff,
  isRemovalInstruction,
  narrowRemovalTargets,
} from '../util/spec-diff';
import {
  fitCurvedDecals,
  stripRedundantLabelParts,
  dropUnplannedParts,
  dropHairlineParts,
  flagUnrealizedParts,
  clampToEnvelope,
  reconcileProportions,
} from '../util/spec-passes/index';
import { runStructurePasses } from '../util/spec-passes/run-all';
import { buildSpecSystemPrompt } from '../prompts/spec';
import { selectRecipeNames } from '../prompts/recipes';
import { REFINE_SYSTEM_PROMPT } from '../prompts/refine';
import { TARGETED_EDIT_PROMPT } from '../prompts/targeted-edit';
import { COMPLETENESS_CRITIC_PROMPT } from '../prompts/completeness';

import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';
import GeneratingOverlay from '../../components/generating-overlay';

import { AnalyzeReferenceCommand } from '../commands/analyze-reference';
import { SculptedModel } from '../sculpted-model';
import type { ImgTo3dStudio } from '../img-to-3d-studio';

/* @ts-expect-error import.meta is valid ESM */
const here: string = import.meta.url;
const studioRef = codeRef(here, '../img-to-3d-studio', 'ImgTo3dStudio');
const sculptedModelRef = codeRef(here, '../sculpted-model', 'SculptedModel');

type StudioPhase = 'idle' | 'analyzing' | 'building' | 'done' | 'error';

// Glint does not accept decorators on members of the class expression used by
// CardDef's inline isolated component. Keep those reactive values in a regular
// top-level class and proxy them from the component instead.
// one past generation, flattened for the history popover so the strip renders
// without holding live card instances
interface HistoryEntry {
  id: string;
  codeFileUrl: string;
  objectName: string;
  round: number | undefined;
  screenshotUrl: string | undefined;
  srcdoc: string;
}

class StudioViewState {
  @tracked phase: StudioPhase = 'idle';
  @tracked errorMessage: string | null = null;
  @tracked logLines: string[] = [];
  @tracked draftViewerSrcdoc: string | undefined;
  @tracked tracedOutline: TracedOutline | undefined;
  @tracked stopRequested = false;
  @tracked historyOpen = false;
  @tracked historyItems: HistoryEntry[] = [];
  @tracked historyLoading = false;
  @tracked openMenuId: string | null = null;
  // lasso inpaint: mode toggle, whether a polygon has been drawn+resolved,
  // the instruction text, how many parts fell under the lasso, and busy flag
  @tracked inpaintMode = false;
  @tracked lassoDrawn = false;
  @tracked inpaintInstruction = '';
  @tracked inpaintTargetCount = 0;
  @tracked inpaintBusy = false;
  // after a lasso edit, the pre-edit spec is remembered so one click can
  // revert (lasso edits overwrite the CURRENT round in place — no new instance)
  @tracked inpaintUndoAvailable = false;
  // bumped to force the viewport iframe to re-fetch the same (overwritten)
  // file URL after an in-place edit — the srcdoc gets a fresh cache-bust key
  @tracked inPlaceReloadKey = 0;
  // the .js URL shown in the viewport DURING a build — the brief window after
  // the file is written but before its SculptedModel is saved & linked as
  // latestCreation. Once linked, this clears and the viewport reads the
  // creation. It is the only place the studio holds a code URL of its own.
  @tracked pendingViewportUrl: string | undefined;
  // escape hatch for a BAD cached analysis. Reusing the analysis on an
  // unchanged reference is what keeps re-generates stable, but when the plan
  // itself is wrong (parts missing, budget wasted) that stability just
  // reproduces the mistake forever — the only exit used to be swapping the
  // reference photos. Set by the sidebar button; the next Generate re-runs the
  // analysis stage AND skips the structure lock (which would otherwise freeze
  // the old plan's part graph anyway), then clears the flag.
  @tracked reanalyzeRequested = false;
}

export class StudioIsolated extends Component<typeof ImgTo3dStudio> {
  private state = new StudioViewState();

  get phase() {
    return this.state.phase;
  }

  set phase(value: StudioPhase) {
    this.state.phase = value;
  }

  get errorMessage() {
    return this.state.errorMessage;
  }

  set errorMessage(value: string | null) {
    this.state.errorMessage = value;
  }

  get logLines() {
    return this.state.logLines;
  }

  set logLines(value: string[]) {
    this.state.logLines = value;
  }

  // the source spec of the model in the viewport, held in memory for the
  // duration of a generate/refine run — it persists inside the generated
  // .js file (SCULPT_SPEC), never on the card instance
  workingSpec: any = null;

  // world-space traced silhouette envelope ({y, half}[]) for the current
  // build — set when a revolved body's outline is traced, consumed by
  // clampToEnvelope to keep every solid part inside the outline. Cleared when
  // the trace fails so nothing clamps against a bad LLM profile.
  tracedEnvelope: { y: number; half: number }[] | null = null;

  // During the deterministic measurement pass the same iframe renders an
  // in-memory candidate before any realm file is written. Once accepted,
  // this is cleared and the iframe switches to the persisted model URL.
  get draftViewerSrcdoc() {
    return this.state.draftViewerSrcdoc;
  }

  set draftViewerSrcdoc(value: string | undefined) {
    this.state.draftViewerSrcdoc = value;
  }

  // the segmented outline the tracer extracted from the reference, shown in
  // the sidebar so the user can judge it against the photo
  get tracedOutline() {
    return this.state.tracedOutline;
  }

  set tracedOutline(value: TracedOutline | undefined) {
    this.state.tracedOutline = value;
  }

  private draftSequence = 0;

  // the viewport is the shared exports/viewer.html harness in an iframe —
  // the SAME page any external site embeds; same-origin, so the studio can
  // call the window API it exposes (screenshot / views / glb)
  frameEl: HTMLIFrameElement | undefined;

  onFrameLoad = (event: Event) => {
    this.frameEl = event.target as HTMLIFrameElement;
  };

  get frameWindow(): any {
    return this.frameEl?.contentWindow as any;
  }

  get realmHref(): string | undefined {
    return (this.args.model as any)?.[realmURL]?.href;
  }

  // one folder per studio card for this run's RUNTIME artifacts — the model
  // .js, its render screenshots, and any cropped textures all live under
  // img-to-3d/<studio-id>/ instead of filling the realm root. Lets a studio's
  // whole output be found (and deleted) in one place, and avoids cross-studio
  // filename clashes. These files are never part of a listing push (they are
  // referenced by URL at runtime, not imported), so this is dev-realm tidiness
  // only. Uses the id's last path segment; falls back when the card is unsaved.
  get studioAssetDir(): string {
    let id = (this.args.model as any)?.id as string | undefined;
    let seg = id ? (id.split('/').filter(Boolean).pop() ?? '') : '';
    return `img-to-3d/${slugify(seg, 'studio')}`;
  }

  // the studio viewport embeds the harness via srcdoc (no .html request to
  // the realm, so no dependency on how text/html navigations route); the
  // URL form of the SAME page — viewer.html?model=… — is what Copy iframe
  // hands to external sites
  get inPlaceReloadKey() {
    return this.state.inPlaceReloadKey;
  }
  set inPlaceReloadKey(v: number) {
    this.state.inPlaceReloadKey = v;
  }

  get viewerSrcdoc(): string | undefined {
    if (this.draftViewerSrcdoc) return this.draftViewerSrcdoc;
    let url = this.currentCodeFileUrl;
    if (!url) return undefined;
    // An in-place edit overwrites the SAME url, so the iframe must be told to
    // re-fetch instead of serving the cached file. Two triggers, both folded
    // into one cache-bust key: inPlaceReloadKey (the studio's OWN lasso edits)
    // and the current creation's `revision`, which the AI Refine command bumps
    // when it edits the round externally — reading it here makes the viewport
    // reload reactively the moment that round's card updates.
    if (!this.pendingViewportUrl) {
      let rev = Number((this.currentCreation as any)?.revision ?? 0);
      if (this.inPlaceReloadKey > 0 || rev > 0) {
        url +=
          (url.includes('?') ? '&' : '?') +
          'rk=' +
          this.inPlaceReloadKey +
          '-' +
          rev;
      }
    }
    return generateViewerSrcdoc(url);
  }

  // ---- current selection (all detail is read from the linked creation) ----
  // the creation shown in the viewport: the explicitly selected one, else
  // the newest saved round
  get currentCreation() {
    return this.args.model?.selectedCreation ?? this.args.model?.latestCreation;
  }

  // the .js in the viewport: the just-built file mid-run (pendingViewportUrl),
  // otherwise the selected creation's file
  get currentCodeFileUrl(): string | undefined {
    return this.pendingViewportUrl ?? this.currentCreation?.codeFileUrl;
  }

  get currentObjectName(): string | undefined {
    return this.currentCreation?.objectName;
  }

  get pendingViewportUrl() {
    return this.state.pendingViewportUrl;
  }

  set pendingViewportUrl(value: string | undefined) {
    this.state.pendingViewportUrl = value;
  }

  // the analysis in play for the current run — held transiently during a
  // build (the run owns it before any creation exists), else read back from
  // the selected creation. This replaces the old studio.analysis field.
  activeAnalysis: any = null;

  get currentAnalysis(): any {
    if (this.activeAnalysis) return this.activeAnalysis;
    try {
      return JSON.parse(this.currentCreation?.analysis || 'null');
    } catch {
      return null;
    }
  }

  // resolves when the iframe has loaded THIS model file and built the scene
  async waitForViewer(codeFileUrl: string, timeoutMs = 30000) {
    let started = Date.now();
    while (Date.now() - started < timeoutMs) {
      let win = this.frameWindow;
      try {
        if (win?.sculptViewerReady && win?.SCULPT_MODEL_URL === codeFileUrl) {
          return true;
        }
      } catch {
        // transiently unreadable during navigation
      }
      await new Promise((r) => setTimeout(r, 200));
    }
    return false;
  }

  get hasLinkedTheme() {
    return Boolean(this.args.model?.cardInfo?.theme);
  }

  get hasModel() {
    return Boolean(this.currentCodeFileUrl);
  }

  get hasReference() {
    return Boolean(this.args.model?.references?.primaryUrl);
  }

  // the fingerprint of the current reference set — the same signature the
  // generate task stamps onto the cached analysis (_refSig). Comparing the
  // two tells us whether the photos changed since the last analysis.
  get currentRefSig(): string {
    let urls = (this.args.model?.references?.resolvedUrls ?? []).filter(
      Boolean,
    );
    return urls.join('|');
  }

  // true when the reference photos were added / removed / swapped since the
  // analysis that's currently cached on the card. Drives the sidebar hint
  // and lets Generate know the gate must be re-run.
  get referencesChanged(): boolean {
    let prev = this.currentAnalysis;
    if (!prev) return false;
    return prev._refSig != null && prev._refSig !== this.currentRefSig;
  }

  get latestCreation() {
    return this.args.model?.latestCreation;
  }

  get isRunning() {
    return this.phase === 'analyzing' || this.phase === 'building';
  }

  get latestLogLine() {
    return this.logLines[this.logLines.length - 1];
  }

  get viewportHint() {
    if (this.hasModel || this.isRunning) return undefined;
    return this.hasReference ? 'ready — hit generate' : 'add a reference photo';
  }

  lastBuildWarnings: string[] = [];

  // The round's own report card, persisted on the creation. Warnings are
  // bucketed by their leading phrase rather than kept verbatim: the text
  // carries part names, so counting raw strings compares two objects' names
  // instead of their failure modes.
  buildMetrics(parsed: any) {
    let kinds: Record<string, number> = {};
    for (let warning of this.lastBuildWarnings) {
      let kind = String(warning).split(/[':(]/)[0].trim().toLowerCase();
      kinds[kind] = (kinds[kind] ?? 0) + 1;
    }
    let featureCheck = parsed?.featureCheck ?? {};
    return {
      residual: this.lastCalibrationResidual,
      score: typeof parsed?.score === 'number' ? parsed.score : null,
      warningCount: this.lastBuildWarnings.length,
      warningKinds: kinds,
      featuresPassed: Object.values(featureCheck).filter((v) => v === true)
        .length,
      featuresFailed: Object.values(featureCheck).filter((v) => v !== true)
        .length,
      plannedParts: this.activeAnalysis?.partPlan?.length ?? null,
      builtParts: Array.isArray(parsed?.components)
        ? parsed.components.filter((c: any) => c?.primitive !== 'group').length
        : null,
      objectClass: this.activeAnalysis?.objectClass ?? null,
      approaches: [
        ...new Set(
          (this.activeAnalysis?.partPlan ?? [])
            .map((p: any) => p?.approach)
            .filter(Boolean),
        ),
      ],
    };
  }

  // Mean deviation of the latest calibrated build from the analysis
  // targets. The automatic verification loop only spends another vision
  // pass while deterministic measurement still shows a material mismatch.
  lastCalibrationResidual: number | null = null;

  startGenerate = () => {
    this.stopRequested = false;
    this.inpaintUndoAvailable = false;
    this.inpaintUndoSpec = null;
    this.generate.perform();
  };

  // one on-demand correction round over the model on screen — surgical
  // (diff-based) edits, never a from-scratch regenerate. The source spec
  // comes from memory or is read back out of the model file's embedded
  // SCULPT_SPEC, so refine works even after a reload or on a restored
  // history round.
  startRefine = () => {
    this.stopRequested = false;
    this.refineOnce.perform();
  };

  refineOnce = restartableTask(async () => {
    let model = this.args.model;
    let currentUrl = this.currentCodeFileUrl;
    if (!currentUrl || !this.args.context?.commandContext) return;
    try {
      this.errorMessage = null;
      this.phase = 'analyzing';
      // the run needs the selected creation's analysis as its measured target
      this.activeAnalysis = this.currentAnalysis;
      if (!this.workingSpec) {
        this.log('> reading spec back from the model file…');
        // ask for the SOURCE bytes — the default .js response is the
        // realm's transpiled form, which reformats the single-line
        // SCULPT_SPEC constant beyond what specFromModelJs can read
        let response = await fetch(currentUrl, {
          headers: { Accept: 'application/vnd.card+source' },
        });
        if (!response.ok) {
          throw new Error(`could not load model file (${response.status})`);
        }
        this.workingSpec = specFromModelJs(await response.text());
        if (!this.workingSpec) {
          throw new Error('model file carries no readable SCULPT_SPEC');
        }
      }
      let previousCreation = model?.latestCreation;
      let previousCodeFileUrl = currentUrl;
      let previousSpec = JSON.parse(JSON.stringify(this.workingSpec));
      let previousScore = previousCreation?.score;
      let referenceDataUrl = await this.encodeReference();
      let round = (this.latestCreation?.round ?? 0) + 1;
      let started = Date.now();
      let outcome = await this.runRefinePass(referenceDataUrl, round);
      if (
        !outcome.featuresOk ||
        (typeof previousScore === 'number' &&
          typeof outcome.score === 'number' &&
          outcome.score < previousScore)
      ) {
        if (model) model.latestCreation = previousCreation;
        this.pendingViewportUrl = undefined;
        this.workingSpec = previousSpec;
        this.log(
          !outcome.featuresOk
            ? '> refinement failed an identity feature; restored previous round'
            : `> refinement regressed ${previousScore} → ${outcome.score}; restored previous round`,
        );
        if (previousCodeFileUrl) {
          await this.waitForViewer(previousCodeFileUrl);
        }
      }
      this.log(`> refine done (${Math.round((Date.now() - started) / 1000)}s)`);
      this.phase = 'done';
    } catch (e: any) {
      this.draftViewerSrcdoc = undefined;
      if (this.stopRequested) {
        this.phase = 'idle';
        this.log('> stopped');
        return;
      }
      this.phase = 'error';
      this.errorMessage = e?.message ?? 'refine failed';
    }
  });

  // graceful stop: the current vision round finishes (its result is kept
  // and archived), then the refine loop exits instead of starting another
  get stopRequested() {
    return this.state.stopRequested;
  }

  set stopRequested(value: boolean) {
    this.state.stopRequested = value;
  }

  get reanalyzeRequested() {
    return this.state.reanalyzeRequested;
  }

  set reanalyzeRequested(value: boolean) {
    this.state.reanalyzeRequested = value;
  }

  // the escape hatch for a bad plan — visible only when there IS a cached
  // plan the next Generate would otherwise silently reuse
  get canRequestReanalyze(): boolean {
    let prev = this.currentAnalysis;
    return Boolean(
      prev &&
      Array.isArray(prev.partPlan) &&
      prev.partPlan.length &&
      !this.referencesChanged,
    );
  }

  toggleReanalyze = () => {
    this.reanalyzeRequested = !this.reanalyzeRequested;
    this.log(
      this.reanalyzeRequested
        ? '> next Generate will discard the cached plan and re-analyze'
        : '> re-analyze cancelled — the cached plan will be reused',
    );
  };

  // hard stop: flag every cooperative boundary AND cancel the running
  // tasks so an in-flight generate/refine unwinds at its next await instead
  // of finishing the whole chain. The catch blocks see stopRequested and end
  // quietly (phase idle) rather than reporting an error.
  stopRefinement = () => {
    this.stopRequested = true;
    this.log('> stopping all steps…');
    this.generate.cancelAll();
    this.refineOnce.cancelAll();
    // drop any half-built in-memory draft so the viewport falls back to the
    // last persisted model (viewerSrcdoc uses codeFileUrl when no draft) and
    // release the working spec/envelope so a stale build can't leak forward
    this.draftViewerSrcdoc = undefined;
    this.pendingViewportUrl = undefined;
    this.tracedEnvelope = null;
    this.tracedOutline = undefined;
    this.phase = 'idle';
  };

  // ---- generation history (popover) -------------------------------------
  get historyOpen() {
    return this.state.historyOpen;
  }

  set historyOpen(value: boolean) {
    this.state.historyOpen = value;
  }

  get historyItems(): HistoryEntry[] {
    return this.state.historyItems;
  }

  set historyItems(value: HistoryEntry[]) {
    this.state.historyItems = value;
  }

  get historyLoading() {
    return this.state.historyLoading;
  }

  set historyLoading(value: boolean) {
    this.state.historyLoading = value;
  }

  // wrap a generated .js URL as an openable FileDef link (the .js file
  // already exists in the realm — this is just its clickable reference)
  makeCodeFileDef(url: string) {
    let name = decodeURIComponent(url.split('/').pop() || 'model.js');
    // linksTo(FileDef) requires an id — for a realm file that IS its URL
    // (same pattern as writeRealmImage's ImageDef), so a FileDef built by
    // createFileDef (no id) is rejected on save. Construct it with id.
    return new FileDef({
      id: url,
      url,
      sourceUrl: url,
      name,
      contentType: 'text/javascript',
    } as any);
  }

  isCurrentEntry = (entry: HistoryEntry) => {
    return entry.codeFileUrl === this.currentCodeFileUrl;
  };

  // the picked round, cloned to the top of the popover as a "current" strip
  get currentHistoryEntry(): HistoryEntry | undefined {
    let url = this.currentCodeFileUrl;
    if (!url) return undefined;
    return this.historyItems.find((e) => e.codeFileUrl === url);
  }

  get openMenuId() {
    return this.state.openMenuId;
  }

  set openMenuId(value: string | null) {
    this.state.openMenuId = value;
  }

  isMenuOpen = (entry: HistoryEntry) => {
    return this.openMenuId === entry.id;
  };

  // each history tile renders its own live viewer iframe — track those
  // windows so the per-tile menu can export THAT version's .glb without
  // switching the main viewport
  historyFrames = new Map<string, HTMLIFrameElement>();

  onHistoryFrameLoad = (id: string, event: Event) => {
    this.historyFrames.set(id, event.target as HTMLIFrameElement);
  };

  toggleEntryMenu = (id: string) => {
    this.openMenuId = this.openMenuId === id ? null : id;
  };

  // the top strip shares the menu-open slot under a fixed sentinel key so it
  // toggles independently of the grid cards
  get stripMenuOpen() {
    return this.openMenuId === '__strip__';
  }

  toggleStripMenu = () => {
    this.openMenuId = this.stripMenuOpen ? null : '__strip__';
  };

  // per-version menu: export that round as .glb from its own live iframe
  exportHistoryGlb = async (entry: HistoryEntry) => {
    this.openMenuId = null;
    try {
      let win = this.historyFrames.get(entry.id)?.contentWindow as any;
      let buffer = await win?.exportGlb?.();
      if (!buffer) {
        this.log('> that version’s viewer isn’t ready yet — try again');
        return;
      }
      let name = slugify(entry.objectName || 'model', 'model');
      let url = URL.createObjectURL(
        new Blob([buffer], { type: 'model/gltf-binary' }),
      );
      let a = document.createElement('a');
      a.href = url;
      a.download = `${name}-round-${entry.round ?? 1}.glb`;
      a.click();
      URL.revokeObjectURL(url);
      this.log(`> exported round ${entry.round ?? '?'} .glb ✓`);
    } catch (e) {
      this.errorMessage = `glb export failed: ${(e as Error).message}`;
    }
  };

  // per-version menu: copy an embeddable iframe for that exact round
  copyHistoryEmbed = async (entry: HistoryEntry) => {
    this.openMenuId = null;
    let escaped = entry.srcdoc.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
    let snippet = `<iframe width="720" height="480" style="border:0" srcdoc="${escaped}"></iframe>`;
    try {
      await navigator.clipboard.writeText(snippet);
      this.log(`> round ${entry.round ?? '?'} iframe copied ✓`);
    } catch {
      this.log('> could not access clipboard');
    }
  };

  // per-version menu: open that round’s SculptedModel card in a side stack.
  // viewCard wants the CARD INSTANCE (realm cards pass the object, not a URL),
  // so resolve it from the store first.
  openHistoryCard = async (entry: HistoryEntry) => {
    this.openMenuId = null;
    if (!this.args.viewCard) {
      this.log('> open unavailable in this context');
      return;
    }
    try {
      let store = (this.args.context as any)?.store;
      let card = store?.get && entry.id ? await store.get(entry.id) : undefined;
      if (!card || (card as any).isCardError) {
        this.log('> could not load that creation');
        return;
      }
      this.args.viewCard(card as any, 'isolated', {
        openCardInRightMostStack: true,
      });
    } catch (e) {
      this.log(`> could not open creation: ${(e as Error).message}`);
    }
  };

  toggleHistory = () => {
    this.historyOpen = !this.historyOpen;
    this.openMenuId = null;
    if (this.historyOpen) {
      this.historyFrames.clear();
      this.loadHistory.perform();
    }
  };

  // catalog Popover fires this on Esc / outside-click
  closeHistory = () => {
    this.historyOpen = false;
    this.openMenuId = null;
  };

  // ---- lasso inpaint (targeted edit) ------------------------------------
  get inpaintMode() {
    return this.state.inpaintMode;
  }
  set inpaintMode(v: boolean) {
    this.state.inpaintMode = v;
  }
  get lassoDrawn() {
    return this.state.lassoDrawn;
  }
  set lassoDrawn(v: boolean) {
    this.state.lassoDrawn = v;
  }
  get inpaintInstruction() {
    return this.state.inpaintInstruction;
  }
  set inpaintInstruction(v: string) {
    this.state.inpaintInstruction = v;
  }
  get inpaintTargetCount() {
    return this.state.inpaintTargetCount;
  }
  set inpaintTargetCount(v: number) {
    this.state.inpaintTargetCount = v;
  }
  get inpaintBusy() {
    return this.state.inpaintBusy;
  }
  set inpaintBusy(v: boolean) {
    this.state.inpaintBusy = v;
  }
  get inpaintUndoAvailable() {
    return this.state.inpaintUndoAvailable;
  }
  set inpaintUndoAvailable(v: boolean) {
    this.state.inpaintUndoAvailable = v;
  }
  // the pre-edit spec to write back on undo (not tracked)
  inpaintUndoSpec: any = null;

  revertInpaint = restartableTask(async () => {
    let spec = this.inpaintUndoSpec;
    if (!spec || !this.args.context?.commandContext) return;
    this.inpaintBusy = true;
    try {
      this.errorMessage = null;
      this.activeAnalysis = this.currentAnalysis;
      // rewrite the current round's file back to the pre-edit spec in place
      await this.applyParsedSpec(JSON.parse(JSON.stringify(spec)), {
        inPlace: true,
      });
      this.inpaintUndoAvailable = false;
      this.inpaintUndoSpec = null;
      this.phase = 'done';
      this.log('> reverted lasso edit');
    } catch (e: any) {
      this.phase = 'error';
      this.errorMessage = e?.message ?? 'revert failed';
    } finally {
      this.inpaintBusy = false;
    }
  });

  startRevertInpaint = () => {
    this.revertInpaint.perform();
  };

  // lasso polygon in viewport CSS pixels, the overlay canvas, drawing flag,
  // and the raw mesh names the lasso covered (normalized to nodeIds on apply)
  lassoPixels: { x: number; y: number }[] = [];
  inpaintCanvas: HTMLCanvasElement | undefined;
  drawing = false;
  inpaintTargets: string[] = [];

  toggleInpaint = () => {
    this.inpaintMode = !this.inpaintMode;
    this.resetLasso();
  };

  resetLasso = () => {
    this.lassoPixels = [];
    this.drawing = false;
    this.lassoDrawn = false;
    this.inpaintTargetCount = 0;
    this.inpaintTargets = [];
    this.inpaintInstruction = '';
    this.clearCanvas();
  };

  clearCanvas = () => {
    let c = this.inpaintCanvas;
    let ctx = c?.getContext('2d');
    if (c && ctx) ctx.clearRect(0, 0, c.width, c.height);
  };

  drawLasso = (close = false) => {
    let c = this.inpaintCanvas;
    let ctx = c?.getContext('2d');
    if (!c || !ctx) return;
    ctx.clearRect(0, 0, c.width, c.height);
    if (this.lassoPixels.length < 2) return;
    ctx.beginPath();
    ctx.moveTo(this.lassoPixels[0].x, this.lassoPixels[0].y);
    for (let p of this.lassoPixels.slice(1)) ctx.lineTo(p.x, p.y);
    if (close) ctx.closePath();
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#38e8ff';
    if (close) {
      ctx.fillStyle = 'rgba(56, 232, 255, 0.12)';
      ctx.fill();
    }
    ctx.stroke();
  };

  // `{{on}}` types its handler as (event: Event), so these take the base
  // type and narrow — the canvas only ever receives pointer events.
  lassoDown = (event: Event) => {
    let e = event as PointerEvent;
    if (!this.inpaintMode || this.inpaintBusy) return;
    let canvas = e.currentTarget as HTMLCanvasElement;
    this.inpaintCanvas = canvas;
    canvas.width = canvas.clientWidth;
    canvas.height = canvas.clientHeight;
    this.drawing = true;
    this.lassoDrawn = false;
    this.lassoPixels = [{ x: e.offsetX, y: e.offsetY }];
    try {
      canvas.setPointerCapture(e.pointerId);
    } catch {
      // capture is best-effort
    }
    this.drawLasso();
  };

  lassoMove = (event: Event) => {
    let e = event as PointerEvent;
    if (!this.drawing) return;
    this.lassoPixels.push({ x: e.offsetX, y: e.offsetY });
    this.drawLasso();
  };

  lassoUp = () => {
    if (!this.drawing) return;
    this.drawing = false;
    if (this.lassoPixels.length < 3) {
      this.resetLasso();
      return;
    }
    this.lassoDrawn = true;
    this.drawLasso(true);
    // raw mesh names under the lasso — normalized to real nodeIds on apply
    let names: string[] =
      this.frameWindow?.pickInRegion?.(this.lassoPixels) ?? [];
    this.inpaintTargets = names;
    this.inpaintTargetCount = names.length;
    this.log(`> lasso covered ${names.length} part(s)`);
  };

  setInstruction = (e: Event) => {
    this.inpaintInstruction = (e.target as HTMLInputElement).value;
  };

  startInpaint = () => {
    this.applyInpaint.perform();
  };

  applyInpaint = restartableTask(async () => {
    if (this.inpaintBusy) return;
    let model = this.args.model;
    let commandContext = this.args.context?.commandContext;
    if (!model || !commandContext) return;
    let instruction = this.inpaintInstruction.trim();
    if (!instruction) {
      this.log('> type an edit instruction first');
      return;
    }
    // no lasso is a valid edit: the instruction names the part instead. The
    // request already says "No parts were pre-selected — resolve the targets
    // from the instruction", TARGETED_EDIT_PROMPT has a section for it, and
    // the bar reads "all parts" when nothing is drawn. This guard was the one
    // layer that disagreed, and it made naming a part impossible — the quicker
    // route of the two.
    this.inpaintBusy = true;
    try {
      this.errorMessage = null;
      // make sure the source spec is in memory (read it back like refine does)
      if (!this.workingSpec?.components?.length) {
        let url = this.currentCodeFileUrl;
        if (url) {
          let resp = await fetch(url, {
            headers: { Accept: 'application/vnd.card+source' },
          });
          if (resp.ok) this.workingSpec = specFromModelJs(await resp.text());
        }
      }
      if (!this.workingSpec?.components?.length) {
        this.log('> could not load the model spec');
        return;
      }
      // snapshot the pre-edit spec so the in-place edit can be reverted
      let undoSpec = JSON.parse(JSON.stringify(this.workingSpec));
      // the run needs the selected creation's analysis as its measured target
      this.activeAnalysis = this.currentAnalysis;
      // normalize lasso mesh names to real spec nodeIds (repeat clones carry
      // a '-<n>' suffix — fold them back to their base component)
      let ids = new Set(
        this.workingSpec.components.map((c: any) => String(c.nodeId)),
      );
      let targets: string[] = [];
      for (let n of this.inpaintTargets) {
        let s = String(n);
        if (ids.has(s)) targets.push(s);
        else {
          let base = s.replace(/-\d+$/, '');
          if (ids.has(base)) targets.push(base);
        }
      }
      targets = [...new Set(targets)];
      // An empty selection is a legitimate way to work: describing the part is
      // often easier than orbiting until it is visible and lassoing it, and the
      // spec's ids are semantic enough for the model to resolve them. Only a
      // lasso that WAS drawn and matched nothing is a real miss.
      if (!targets.length && this.lassoDrawn) {
        this.log('> selection did not map to any part');
        return;
      }
      this.log(
        targets.length
          ? `> edit: ${targets.length} selected part(s) — “${instruction}”`
          : `> edit by description — “${instruction}”`,
      );

      // the deterministic delete needs to know WHAT to delete, so it only
      // applies to an explicit selection; described removals go to the model
      if (targets.length && isRemovalInstruction(instruction)) {
        // the lasso reports every mesh under it, so a sticker selection also
        // catches the blade behind it. When the instruction names what to
        // remove, that noun narrows the selection so "remove sticker" cannot
        // take the blade with it.
        let removeTargets = narrowRemovalTargets(
          this.workingSpec.components,
          targets,
          instruction,
        );
        if (removeTargets.length < targets.length) {
          this.log(
            `> narrowed removal to ${removeTargets.length} part(s) the instruction names`,
          );
        }
        // deterministic removal — no LLM needed
        let spec = JSON.parse(JSON.stringify(this.workingSpec));
        let dead = new Set(removeTargets.map(String));
        let changed = true;
        while (changed) {
          changed = false;
          for (let c of spec.components) {
            if (
              c.parentId != null &&
              dead.has(String(c.parentId)) &&
              !dead.has(String(c.nodeId))
            ) {
              dead.add(String(c.nodeId));
              changed = true;
            }
          }
        }
        spec.components = spec.components.filter(
          (c: any) => !dead.has(String(c.nodeId)),
        );
        this.phase = 'building';
        await this.applyParsedSpec(spec, { inPlace: true });
        this.log(`> removed ${dead.size} part(s) ✓`);
      } else {
        this.phase = 'analyzing';
        this.log(
          targets.length
            ? '> comparing selected part(s) against the reference…'
            : '> resolving which parts the instruction means…',
        );
        let promptText =
          `SELECTED nodeIds: ${JSON.stringify(targets)}\n` +
          (targets.length
            ? ''
            : 'No parts were pre-selected — resolve the targets from the instruction and the spec below.\n') +
          `INSTRUCTION: ${instruction}\n\nCURRENT SPEC:\n${JSON.stringify(
            serializeSpecForPrompt(this.workingSpec),
          )}`;
        let content: any[] = [{ type: 'text', text: promptText }];
        // build the reference-vs-render comparison sheet so the model can
        // diagnose the selected parts visually (placement / proportion /
        // material / color) exactly like the refine pass does
        let flat = this.workingSpec?.inputKind === 'flat-graphic';
        let renders = flat
          ? [this.frameWindow?.captureScreenshot?.()].filter(Boolean)
          : (
              this.frameWindow?.captureViews?.(this.activeAnalysis?.camera) ??
              []
            ).map((v: any) => v?.dataUrl ?? v);
        let referenceDataUrl = await this.encodeReference();
        if (referenceDataUrl && renders.length) {
          let comparison = await composeComparison(
            referenceDataUrl,
            renders as string[],
            {
              firstIsReferenceAngle:
                Boolean(this.activeAnalysis?.camera) && !flat,
            },
          );
          content.push({ type: 'image_url', image_url: { url: comparison } });
        }
        let diff = await this.visionRequest(
          TARGETED_EDIT_PROMPT,
          content,
          parseDiffJson,
        );
        // a person looking at the result and asking for a change outranks the
        // plan: they may resize a part and add one the build left out. The
        // automatic refine pass gets none of these — see applySpecDiff.
        let merged = applySpecDiff(this.workingSpec, diff, {
          allowRemoval: true,
          allowReshape: true,
          allowAdditions: true,
        });
        let addedCount = (diff.added ?? []).length;
        if (addedCount) {
          this.log(`> added ${addedCount} new part(s)`);
        }
        await this.applyParsedSpec(merged, { inPlace: true });
        this.log('> inpaint applied ✓');
      }
      this.phase = 'done';
      // enable one-click revert (re-apply the pre-edit spec in place)
      this.inpaintUndoSpec = undoSpec;
      this.inpaintUndoAvailable = true;
      this.inpaintMode = false;
      this.resetLasso();
    } catch (e: any) {
      this.phase = 'error';
      this.errorMessage = e?.message ?? 'inpaint failed';
    } finally {
      this.inpaintBusy = false;
    }
  });

  // walk the parentCreation chain back from the latest saved round so the
  // popover lists every generation newest-first, without a search query
  // EVERY round this studio produced, not just the chain hanging off
  // latestCreation. Each SculptedModel is stamped with sourceStudioId when it
  // is saved — the field exists for exactly this — so a query finds rounds the
  // backwards walk cannot: anything newer than a stale latestCreation pointer,
  // and any branch created by generating again from an older round.
  get historyQuery() {
    let id = this.args.model?.id;
    if (!id) return undefined;
    return {
      filter: {
        on: sculptedModelRef,
        eq: { sourceStudioId: id },
      },
      sort: [{ on: sculptedModelRef, by: 'createdAt', direction: 'desc' }],
    };
  }

  get historyRealms() {
    let href = (this.args.model as any)?.[realmURL]?.href;
    return href ? [href] : [];
  }

  historyCards = (this.args.context as any)?.getCards?.(
    this,
    () => this.historyQuery,
    () => this.historyRealms,
    { isLive: true },
  );

  loadHistory = restartableTask(async () => {
    this.historyLoading = true;
    try {
      let store = (this.args.context as any)?.store;

      // the live getCards query resolves asynchronously; on a fresh page load
      // it is still running when the popover first opens. Reading `.instances`
      // now would see an empty set and fall through to the (possibly stale)
      // parentCreation walk — so wait for the query to settle first, bounded
      // by a timeout in case the realm can't answer it.
      let started = Date.now();
      while (this.historyCards?.isLoading && Date.now() - started < 10000) {
        await new Promise((r) => setTimeout(r, 150));
      }

      // preferred: the studio-scoped query
      // MERGE both sources rather than one-or-the-other: the live index query
      // can lag (a just-generated round is not indexed yet) or miss rounds that
      // predate sourceStudioId, while the in-memory parentCreation walk catches
      // exactly those but not branches the walk can't reach. Union + dedup so a
      // round shows if EITHER source knows about it.
      let byKey = new Map<string, HistoryEntry>();
      let add = (card: any) => {
        if (!card?.codeFileUrl) return;
        let key = card.id || card.codeFileUrl;
        if (byKey.has(key)) return;
        byKey.set(key, {
          id: card.id,
          codeFileUrl: card.codeFileUrl,
          objectName: card.objectName || 'model',
          round: card.round ?? undefined,
          screenshotUrl: card.renderScreenshot?.url,
          srcdoc: generateViewerSrcdoc(card.codeFileUrl),
        });
      };

      // source 1: the studio-scoped index query
      for (let card of this.historyCards?.instances ?? []) add(card);

      // source 2: walk parentCreation back from the newest in-memory rounds
      // (latest AND the currently selected), which are present before the index
      // catches up — this is what makes a freshly-made round appear immediately
      for (let seed of [
        this.args.model?.latestCreation,
        this.args.model?.selectedCreation,
      ]) {
        let node: any = seed;
        let guard = 0;
        while (node && guard++ < 100) {
          let card: any = node;
          if (store?.get && card.id) {
            let got = await store.get(card.id);
            if (got && !(got as any).isCardError) card = got;
          }
          add(card);
          node = card?.parentCreation;
        }
      }

      // newest first by ROUND — createdAt is only minute-granular, so
      // same-minute rounds would shuffle if sorted by time
      this.historyItems = [...byKey.values()].sort(
        (a, b) => (b.round ?? 0) - (a.round ?? 0),
      );
    } finally {
      this.historyLoading = false;
    }
  });

  // persist-select: point selectedCreation at the picked round's Sculpted
  // model card. Everything shown in the studio (viewport, name, analysis,
  // file link) is read from selectedCreation, so this one assignment
  // re-attaches that round's details wholesale. latestCreation is untouched,
  // so the history list still walks from the newest round.
  selectHistoryEntry = async (entry: HistoryEntry) => {
    let model = this.args.model;
    if (!model) return;
    this.draftViewerSrcdoc = undefined;
    // ALWAYS switch the viewport to the picked round's file first, from the
    // entry's own codeFileUrl — so the click is never a silent no-op even when
    // the store can't resolve the card yet (a just-made / not-yet-indexed
    // round). Resolving selectedCreation below then re-attaches its full detail.
    this.pendingViewportUrl = entry.codeFileUrl;
    this.workingSpec = null;
    this.activeAnalysis = null;
    this.inpaintUndoAvailable = false;
    this.inpaintUndoSpec = null;
    this.inPlaceReloadKey = 0;
    this.historyOpen = false;
    this.log(`> selected round ${entry.round ?? '?'} as current`);

    let store = (this.args.context as any)?.store;
    let card = store?.get && entry.id ? await store.get(entry.id) : undefined;
    if (card && !(card as any).isCardError) {
      model.selectedCreation = card as SculptedModel;
      // the creation now drives the viewport; retire the transient pointer
      this.pendingViewportUrl = undefined;
    }
    await this.waitForViewer(entry.codeFileUrl);
  };

  // every sculpture is its own studio card — starting a new one opens a
  // fresh instance in the stack instead of resetting this card's project
  newSculpture = () => {
    let realm = (this.args.model as any)?.[realmURL];
    this.args.createCard?.(studioRef, undefined, {
      realmURL: realm,
      cardModeAfterCreation: 'isolated',
    });
  };

  aiRefineLaunching = false;

  // open the AI Assistant on the current round with the refine skill attached,
  // so the assistant can SEE this model's reference + render, diagnose the
  // differences conversationally, and (on approval) call the Refine Model
  // command to apply each change as a new round. One room per studio.
  startRefineWithAi = async () => {
    let commandContext = this.args.context?.commandContext;
    let creation = this.currentCreation;
    if (this.aiRefineLaunching || !commandContext || !creation?.id) return;
    this.aiRefineLaunching = true;
    try {
      let skillCardId = new URL('../Skill/refine-sculpt-skill', here).href;
      await new UseAiAssistantCommand(commandContext).execute({
        roomName: `Refine ${this.currentObjectName || 'model'}`,
        // force a FRESH room each time — without this the command reuses
        // whatever assistant room is currently open, carrying over unrelated
        // context; 'new' makes it always create one
        roomId: 'new',
        openRoom: true,
        // non-Anthropic on purpose — an Anthropic model here trips the ai-bot's
        // inline-system-message ordering against the tightened Anthropic API
        llmModel: ASSISTANT_MODEL,
        // 'ask' so the assistant PROPOSES each Refine Model command and the
        // user approves it before the model changes (paired with the command's
        // requiresApproval: true in the skill).
        llmMode: 'ask',
        skillCardIds: [skillCardId],
        attachedCardIds: [creation.id],
        openCardIds: [creation.id],
        // a natural opener shown as the user's own message — the diagnostic
        // behaviour lives in the skill instructions, not here
        prompt: `Let's refine this model against its reference — what looks off?`,
      } as any);
    } catch (e: any) {
      this.errorMessage = e?.message ?? 'could not open the AI assistant';
    } finally {
      this.aiRefineLaunching = false;
    }
  };

  // embedding the model anywhere = an iframe whose srcdoc carries the
  // viewer harness with this model's .js URL baked in. srcdoc (instead of
  // a viewer-page URL) keeps the whole feature realm-content-only — no
  // special text/html routing on the realm server is involved.
  copyEmbed = async () => {
    let srcdoc = this.viewerSrcdoc;
    if (!srcdoc) return;
    let escaped = srcdoc.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
    let snippet = `<iframe width="720" height="480" style="border:0" srcdoc="${escaped}"></iframe>`;
    try {
      await navigator.clipboard.writeText(snippet);
      this.log('> iframe embed copied ✓');
    } catch {
      this.log('> could not access clipboard');
    }
  };

  // Editable Output: alongside the always-editable model code, the build
  // exports as a standard binary glTF for any DCC tool or engine
  downloadGlb = async () => {
    try {
      let buffer = await this.frameWindow?.exportGlb?.();
      if (!buffer) return;
      let name = slugify(this.currentObjectName || 'model', 'model');
      let url = URL.createObjectURL(
        new Blob([buffer], { type: 'model/gltf-binary' }),
      );
      let a = document.createElement('a');
      a.href = url;
      a.download = `${name}.glb`;
      a.click();
      URL.revokeObjectURL(url);
      this.log('> exported .glb ✓');
    } catch (e) {
      this.errorMessage = `glb export failed: ${(e as Error).message}`;
    }
  };

  log(line: string) {
    this.logLines = [...this.logLines.slice(-5), line];
  }

  // Compact the previous build to its STRUCTURAL identity — the fields that
  // define the part graph (ids, parentage, primitive, attachment, anchor,
  // grounding, repeat) — and wrap it in an instruction that forbids adding,
  // removing, renaming, reparenting or retyping any component. Sizes,
  // positions, scale and materials stay free so the re-roll still corrects
  // proportions against the photo. This is what stops the same-image
  // regenerate from decomposing into a different part set.
  buildStructureLock(spec: any): string {
    let skeleton = (spec.components ?? []).map((c: any) => ({
      nodeId: c.nodeId,
      parentId: c.parentId ?? null,
      primitive: c.primitive,
      ...(c.attachTo !== undefined ? { attachTo: c.attachTo } : {}),
      ...(c.anchor !== undefined ? { anchor: c.anchor } : {}),
      ...(c.grounded !== undefined ? { grounded: c.grounded } : {}),
      ...(c.repeat !== undefined ? { repeat: c.repeat } : {}),
      ...(c.materialId !== undefined ? { materialId: c.materialId } : {}),
      ...(c.textureRef !== undefined ? { textureRef: c.textureRef } : {}),
    }));
    return (
      `\n\nSTRUCTURE LOCK (this is a re-generation of the SAME object — a ` +
      `previous build already exists). Reuse EXACTLY this component graph: ` +
      `keep every nodeId, parentId, primitive type, attachTo, anchor, ` +
      `grounded and repeat unchanged, and keep the SAME number of ` +
      `components. Do NOT add, remove, rename, reparent, or change the ` +
      `primitive of any component. Only adjust dimensions, position, ` +
      `rotation, scale and material colors to match the photo more ` +
      `closely.\nEXISTING STRUCTURE:\n${JSON.stringify(skeleton)}`
    );
  }

  generate = restartableTask(async () => {
    let model = this.args.model;
    if (!model || !this.args.context?.commandContext) return;
    if (!model.references?.primaryUrl) {
      this.phase = 'error';
      this.errorMessage = 'Add a reference photo first.';
      return;
    }
    try {
      this.errorMessage = null;
      this.logLines = [];
      this.phase = 'analyzing';
      this.log('> probing reference image…');
      let referenceDataUrl = await this.encodeReference();

      let allViews = await this.encodeAllReferences();
      if (allViews.length > 1) {
        this.log(`> using ${allViews.length} reference views…`);
      }
      // the payload is the request's exposure to a dropped connection, so it
      // is worth seeing: base64 carries a third more than the bytes it encodes
      let payloadMb =
        allViews.reduce((sum, url) => sum + url.length, 0) / 1024 / 1024;
      this.log(`> reference payload ${payloadMb.toFixed(1)} MB`);
      let imageParts = allViews.map((url) => ({
        type: 'image_url',
        image_url: { url },
      }));

      // stage 1 — analysis. It is the GATE (classification, per-part bboxes,
      // camera, revolved flags) that everything downstream keys off, so
      // re-rolling it every Generate makes the whole result swing. Reuse the
      // cached analysis when the reference set is unchanged: clicking Generate
      // again then only re-rolls the BUILD (spec), keeping results stable. A
      // changed reference (different signature) forces a fresh analysis.
      let refUrls = (model.references?.resolvedUrls ?? []).filter(Boolean);
      let refSig = refUrls.join('|');
      let analysis: any = null;
      let sameReference = false;
      // the cached analysis now lives on the selected creation, not the
      // studio — read it back from there when the reference is unchanged.
      // A pending Re-analyze request overrides the cache entirely: the user
      // has judged the PLAN wrong, and a wrong plan reproduces its mistakes
      // through every re-generate no matter how the build re-rolls.
      let prev = this.currentAnalysis;
      if (
        !this.reanalyzeRequested &&
        prev &&
        prev._refSig === refSig &&
        Array.isArray(prev.partPlan) &&
        prev.partPlan.length
      ) {
        analysis = prev;
        sameReference = true;
      }
      if (analysis) {
        this.log(
          '> reusing cached analysis (same reference) — re-rolling the build only',
        );
      } else {
        if (this.reanalyzeRequested) {
          this.log('> re-analyze requested — discarding the cached plan');
        }
        this.log('> analyzing object & planning parts…');
        let analysisResult = await new AnalyzeReferenceCommand(
          this.args.context!.commandContext!,
        ).execute({
          imageUrls: refUrls,
          model: ANALYSIS_MODEL,
        } as any);
        analysis = JSON.parse(analysisResult.analysisJson);
        // stamp the reference signature so a later Generate can tell the
        // analysis still matches the current photo(s). It is persisted onto
        // the SculptedModel this run produces (not the studio card).
        analysis._refSig = refSig;
      }
      // the request is consumed either way: the fresh analysis is now the
      // cache, and sameReference stayed false so no structure lock will
      // resurrect the old plan's part graph
      this.reanalyzeRequested = false;
      // the run owns this analysis until it is stamped onto the saved
      // creation; applyParsedSpec / the save block read it from here
      this.activeAnalysis = analysis;
      this.log(
        `> plan: ${analysis.objectType ?? 'object'} · ${
          analysis.partPlan.length
        } parts · ${analysis.buildRecipe.length} recipe notes`,
      );
      if (analysis.camera) {
        this.log(
          `> camera: ${analysis.camera.azimuthDeg}° az / ${analysis.camera.elevationDeg}° el`,
        );
      }

      // a stop request lands at the next stage boundary — the in-flight
      // vision call cannot be recalled, but the NEXT one can be skipped
      if (this.stopRequested) {
        this.log('> stopped before building');
        this.phase = 'idle';
        return;
      }

      // structure lock: on a same-reference re-generation, hand the LLM the
      // PREVIOUS build's component graph and forbid structural changes, so
      // the re-roll only varies sizes/materials instead of inventing a
      // different (often decomposed) part set each time
      let structureLock = '';
      if (sameReference) {
        let prevSpec = this.workingSpec;
        let prevUrl = this.currentCodeFileUrl;
        if (!prevSpec?.components?.length && prevUrl) {
          try {
            let response = await fetch(prevUrl, {
              headers: { Accept: 'application/vnd.card+source' },
            });
            if (response.ok) {
              prevSpec = specFromModelJs(await response.text());
            }
          } catch {
            prevSpec = null;
          }
        }
        if (prevSpec?.components?.length) {
          // the lock freezes the previous graph, so any part that graph should
          // never have contained would be reproduced forever — a re-generate
          // would keep handing back the same mould seams no matter what the
          // rules now say. Clean the graph BEFORE locking to it, so the lock
          // preserves the structure that survived review rather than the
          // structure that happened to be authored first.
          for (let line of dropHairlineParts(prevSpec)) {
            this.log(`> structure lock: ${line}`);
          }
          for (let line of dropUnplannedParts(prevSpec, analysis)) {
            this.log(`> structure lock: ${line}`);
          }
          structureLock = this.buildStructureLock(prevSpec);
          this.log(
            `> structure lock: reusing ${prevSpec.components.length}-part graph (only sizes/materials re-roll)`,
          );
        }
      }

      // stage 2 — build the spec, honoring the stage-1 plan
      this.log('> authoring sculpt spec…');
      // the plan's own length IS the part budget. The system prompt can only
      // say "follow the plan" in the abstract; stating the number here — plus
      // the fact that unplanned parts are deleted rather than rendered —
      // removes any incentive to pad the spec toward a quota.
      let plannedCount = analysis.partPlan.length;
      let partBudget = `\n\nPART BUDGET: the plan lists ${plannedCount} part${
        plannedCount === 1 ? '' : 's'
      }, so author roughly ${plannedCount}-${
        plannedCount * 2
      } components (groups and the one ground shadow do not count). Every planned part must appear. Nothing else may: a component whose partRef is not one of the ${plannedCount} planned names is DELETED before the model is built, so inventing extra parts only throws away your own work.`;
      // the invariant contract, plus only the build directives this object's
      // own plan calls for
      let specSystemPrompt = buildSpecSystemPrompt(analysis);
      if (specSystemPrompt.length > 1) {
        this.log(
          `> directives: ${selectRecipeNames(analysis).join(', ') || 'none'}`,
        );
      }
      let parsed = await this.visionRequest(
        specSystemPrompt,
        [
          {
            type: 'text',
            text:
              (allViews.length > 1
                ? `Rebuild the object shown in these ${allViews.length} views of the SAME object as a procedural sculpt spec. Reconcile all views — side/orthographic views define thickness and depth.`
                : 'Rebuild the object in this photo as a procedural sculpt spec.') +
              `\n\nANALYSIS (follow this plan):\n${JSON.stringify(analysis)}` +
              partBudget +
              structureLock,
          },
          ...imageParts,
        ],
        undefined,
        // a reply that leaves out a planned part is re-asked for once, naming the
        // parts it skipped. This is the difference between logging that a bottle's
        // label is missing and actually getting the label.
        (candidate: any) => {
          let missing = flagUnrealizedParts(candidate, analysis).filter(
            (line) => line.includes('NO component realizes'),
          );
          if (!missing.length) return null;
          let names = missing
            .map((line) => line.match(/^'([^']+)'/)?.[1])
            .filter(Boolean);
          return (
            `Your previous reply left these planned parts out of "components" entirely: ${names.join(', ')}. ` +
            `Every partPlan entry must be realized by at least one component whose "partRef" is that part's exact name. ` +
            `Send the WHOLE JSON object again with those parts included, built the way their "approach" says.`
          );
        },
      );
      // the analysis owns identity — its features gate the refine rounds
      if (analysis.identityFeatures.length) {
        parsed.identityFeatures = analysis.identityFeatures;
      }
      // the analysis also owns the part INVENTORY: anything the build stage
      // invented on top of the plan goes now, before tracing / clamping /
      // texturing spend work on it. Only the generate path is gated — a lasso
      // edit is allowed to add parts the plan never mentioned, because there
      // the user asked for them.
      // the full deterministic structure/geometry repair chain, in its one
      // documented order (see util/spec-passes/run-all.gts) — drop unplanned
      // parts, enforce joints, guarantee + place the face, unbury, flag the
      // rest. Kept as one call so the ordering lives (and is tested) in one place.
      for (let line of runStructurePasses(parsed, analysis)) {
        this.log(`> ${line}`);
      }
      let outcome = await this.applyParsedSpec(parsed);

      // completeness audit: one vision pass that ADDS whatever the reference
      // shows and this build lacks (a missing eye, wheel, handle, limb). This
      // is the general, category-agnostic guard against an under-built model —
      // it replaces reasoning that would otherwise have to be hardcoded per
      // object type. Skipped only when the user already asked to stop.
      if (!this.stopRequested) {
        let completed = await this.runCompletenessPass(referenceDataUrl);
        if (completed) outcome = completed;
      }

      let best = {
        score: outcome.score ?? -1,
        spec: this.workingSpec,
        codeFileUrl: this.currentCodeFileUrl,
        creation: this.currentCreation,
      };

      for (let round = 0; round < AUTO_REFINE_ROUNDS; round++) {
        // user asked to stop — keep what the finished rounds produced
        if (this.stopRequested) {
          this.log('> refinement stopped');
          break;
        }
        // per-feature gate: early stop needs a good score AND every
        // identity feature passing
        if (
          typeof outcome.score === 'number' &&
          outcome.score >= REFINE_TARGET_SCORE &&
          outcome.featuresOk
        ) {
          break;
        }
        let started = Date.now();
        outcome = await this.runRefinePass(referenceDataUrl, round + 1);
        this.log(
          `> refine ${round + 1} done (${Math.round(
            (Date.now() - started) / 1000,
          )}s)`,
        );
        if (
          typeof outcome.score === 'number' &&
          outcome.score > best.score &&
          outcome.featuresOk
        ) {
          best = {
            score: outcome.score,
            spec: this.workingSpec,
            codeFileUrl: this.currentCodeFileUrl,
            creation: this.currentCreation,
          };
        }
      }

      // If deterministic calibration still cannot meet the measured target,
      // let the vision pass correct placement/color, then measure again.
      // The best-round restoration below prevents a lower-scoring result
      // from replacing the stronger saved model.
      let autoVerifyRounds = 0;
      while (
        !this.stopRequested &&
        autoVerifyRounds < AUTO_VERIFY_ROUNDS &&
        typeof this.lastCalibrationResidual === 'number' &&
        this.lastCalibrationResidual > 0.12
      ) {
        autoVerifyRounds++;
        this.log(
          `> auto-verify: residual ${(this.lastCalibrationResidual * 100).toFixed(0)}% — refining (${autoVerifyRounds}/${AUTO_VERIFY_ROUNDS})…`,
        );
        outcome = await this.runRefinePass(referenceDataUrl, autoVerifyRounds);
        if (
          typeof outcome.score === 'number' &&
          outcome.score > best.score &&
          outcome.featuresOk
        ) {
          best = {
            score: outcome.score,
            spec: this.workingSpec,
            codeFileUrl: this.currentCodeFileUrl,
            creation: this.currentCreation,
          };
        }
      }

      // refine rounds can regress — end on the best-scoring round, not
      // merely the last one (its model file already exists; just point the
      // viewport back at it)
      if (
        best.codeFileUrl &&
        (!outcome.featuresOk ||
          (typeof outcome.score === 'number' && best.score > outcome.score))
      ) {
        this.pendingViewportUrl = undefined;
        if (best.creation) {
          this.args.model!.selectedCreation = best.creation;
          this.args.model!.latestCreation = best.creation;
        }
        this.workingSpec = best.spec;
        this.log(`> restored best round (score ${best.score})`);
      }

      this.phase = 'done';
      this.log('> rebuilt in code ✓');
    } catch (e: any) {
      this.draftViewerSrcdoc = undefined;
      if (this.stopRequested) {
        this.phase = 'idle';
        this.log('> stopped');
        return;
      }
      this.phase = 'error';
      this.errorMessage = e?.message ?? 'generation failed';
    }
  });

  // one render-vs-reference correction round: screenshot the current build,
  // pack it beside the reference, and ask the model for a corrected spec
  async runRefinePass(
    referenceDataUrl: string,
    round: number,
  ): Promise<{ score: number | undefined; featuresOk: boolean }> {
    let flat = this.workingSpec?.inputKind === 'flat-graphic';
    let analysis: any = this.currentAnalysis;
    let renders = flat
      ? [this.frameWindow?.captureScreenshot?.()].filter(Boolean)
      : (this.frameWindow?.captureViews?.(analysis?.camera) ?? []).map(
          (v: any) => v?.dataUrl ?? v,
        );
    if (!renders.length) return { score: undefined, featuresOk: true };
    this.phase = 'analyzing';
    this.log(
      `> refine ${round}: comparing ${renders.length} view(s) vs reference…`,
    );
    let comparison = await composeComparison(
      referenceDataUrl,
      renders as string[],
      { firstIsReferenceAngle: Boolean(analysis?.camera) && !flat },
    );
    let currentSpecJson = JSON.stringify(
      serializeSpecForPrompt(this.workingSpec),
    );
    let assemblyFacts = this.lastBuildWarnings.length
      ? `\n\nMachine-checked assembly problems in the current build (fix these FIRST — move parts so they overlap their neighbours by 0.02-0.05):\n- ${this.lastBuildWarnings.join('\n- ')}`
      : '';
    // measured targets from stage-1: per-part reference bboxes +
    // attachment constraints the render must satisfy numerically
    let measuredTargets =
      analysis?.partPlan?.length || analysis?.attachments?.length
        ? `\n\nMEASURED TARGETS (from the reference analysis — check proportions and joints against these):\n${JSON.stringify(
            {
              parts: (analysis.partPlan ?? []).map((p: any) => ({
                part: p.part,
                bbox: p.bbox,
              })),
              attachments: analysis.attachments ?? [],
            },
          )}`
        : '';
    let firstPaneNote = analysis?.camera
      ? ' The first render pane is captured from the estimated reference camera angle — compare it to the reference pane like-for-like.'
      : '';
    let diff = await this.visionRequest(
      REFINE_SYSTEM_PROMPT,
      [
        {
          type: 'text',
          text: `Current spec JSON:\n${currentSpecJson}\n\nLEFT = reference photo, RIGHT = current render.${firstPaneNote}${assemblyFacts}${measuredTargets}\n\nOutput the minimal change set.`,
        },
        { type: 'image_url', image_url: { url: comparison } },
      ],
      parseDiffJson,
    );

    // nothing to change and every feature passing → keep this round free
    let noChanges =
      diff.changed.length === 0 && diff.materialsChanged.length === 0;
    let failed = Object.entries(diff.featureCheck ?? {}).filter(
      ([, v]) => String(v).toLowerCase() === 'fail',
    );
    if (noChanges && failed.length === 0) {
      this.log('> no changes needed');
      return {
        score: typeof diff.score === 'number' ? diff.score : undefined,
        featuresOk: true,
      };
    }
    this.log(
      `> applying ${diff.changed.length} placement change(s), ${diff.materialsChanged.length} material change(s)…`,
    );
    let merged = applySpecDiff(this.workingSpec, diff);
    return await this.applyParsedSpec(merged);
  }

  // one completeness audit: compare the render to the reference and ADD the
  // parts the build left out. This is the category-agnostic counterpart to the
  // hardcoded face backstop — it catches a missing eye, wheel, handle or limb
  // by looking at the two images, not by knowing what the object is. Unlike
  // runRefinePass it allows additions (but never reshape/removal), so an
  // omitted part can come back. Returns the build outcome, or the unchanged
  // one when nothing was missing.
  async runCompletenessPass(
    referenceDataUrl: string,
  ): Promise<{ score: number | undefined; featuresOk: boolean } | undefined> {
    let flat = this.workingSpec?.inputKind === 'flat-graphic';
    let analysis: any = this.currentAnalysis;
    let renders = flat
      ? [this.frameWindow?.captureScreenshot?.()].filter(Boolean)
      : (this.frameWindow?.captureViews?.(analysis?.camera) ?? []).map(
          (v: any) => v?.dataUrl ?? v,
        );
    if (!renders.length) return undefined;
    this.phase = 'analyzing';
    this.log(
      '> completeness check: what does the reference show that this build lacks?',
    );
    let comparison = await composeComparison(
      referenceDataUrl,
      renders as string[],
      {
        firstIsReferenceAngle: Boolean(analysis?.camera) && !flat,
      },
    );
    let currentSpecJson = JSON.stringify(
      serializeSpecForPrompt(this.workingSpec),
    );
    let diff = await this.visionRequest(
      COMPLETENESS_CRITIC_PROMPT,
      [
        {
          type: 'text',
          text: `Current spec JSON:\n${currentSpecJson}\n\nLEFT = reference photo, RIGHT = current render. Add every part the reference shows that the render is missing.`,
        },
        { type: 'image_url', image_url: { url: comparison } },
      ],
      parseDiffJson,
    );
    let addedCount = (diff.added ?? []).length;
    let changedCount = (diff.changed ?? []).length;
    if (!addedCount && !changedCount) {
      this.log('> completeness check: nothing missing');
      return undefined;
    }
    this.log(
      `> completeness: added ${addedCount} missing part(s), nudged ${changedCount}`,
    );
    // additions + placement only — the critic must not delete or reshape the
    // build it is completing
    let merged = applySpecDiff(this.workingSpec, diff, {
      allowAdditions: true,
    });
    return await this.applyParsedSpec(merged);
  }

  async encodeReference(): Promise<string> {
    let url = this.args.model?.references?.primaryUrl;
    if (!url) throw new Error('reference image is missing');
    return fetchAsDataUrl(url, {
      commandContext: this.args.context?.commandContext,
    });
  }

  async encodeAllReferences(): Promise<string[]> {
    let urls = (this.args.model?.references?.resolvedUrls ?? []).filter(
      Boolean,
    );
    return Promise.all(
      urls.slice(0, 6).map((u: string) =>
        fetchAsDataUrl(u, {
          commandContext: this.args.context?.commandContext,
        }),
      ),
    );
  }

  // one seed per reference set, shared by every vision stage this studio
  // runs (spec build, refine diff, targeted edit). A new photo set gets a
  // new seed; the same photos re-run the same sampling path.
  get referenceSeed(): number {
    return seedFromStrings(
      (this.args.model?.references?.resolvedUrls ?? []).filter(Boolean),
    );
  }

  async visionRequest(
    systemPrompt: string | string[],
    userContent: any[],
    parser?: (raw: string) => any,
    validate?: (parsed: any) => string | null,
  ) {
    return requestSpec(
      this.args.context!.commandContext!,
      this.args.model?.llmModel || VISION_MODEL,
      systemPrompt,
      userContent,
      (line) => this.log(line),
      parser,
      { seed: this.referenceSeed, validate },
    );
  }

  parsedAnalysis(): any {
    return this.currentAnalysis ?? undefined;
  }

  async renderDraftAndMeasure(parsed: any, round: number) {
    let token = `img-to-3d-draft-${round}-${++this.draftSequence}`;
    this.draftViewerSrcdoc = generateViewerSrcdocInline(
      generateModelJs(parsed, {
        round,
        score: typeof parsed.score === 'number' ? parsed.score : null,
      }),
      token,
    );
    if (!(await this.waitForViewer(token))) {
      this.log('> draft viewer timed out — skipped measured reconciliation');
      return undefined;
    }
    return this.frameWindow?.measureParts?.();
  }

  // The vision model supplies semantic part names; the iframe supplies the
  // actual post-transform world-space boxes. Reconcile those before writing
  // the model file so reference bboxes constrain real geometry instead of
  // remaining prompt-only advice.
  async reconcileDraftProportions(
    parsed: any,
    round: number,
    skipRefs: string[],
  ) {
    this.lastCalibrationResidual = null;
    let analysis = this.parsedAnalysis();
    if (!analysis?.partPlan?.length) return;
    let mappedParts = (parsed.components ?? []).filter(
      (component: any) => component?.partRef,
    ).length;
    if (!mappedParts) {
      this.log('> no partRef mappings — skipped measured reconciliation');
      return;
    }

    // Each pass costs a full draft render: write the srcdoc, wait for the
    // iframe to load three.js and build the scene, read the world boxes back.
    // A second pass only pays for itself if it actually reaches the target, and
    // observed residuals ran 8-27% — never close to the 4% target — so the
    // second render was bought and thrown away every time. One pass it is;
    // raise this if a future change makes the correction converge.
    const MAX_PASSES = 1;
    const TARGET_RESIDUAL = 0.04;
    for (let pass = 0; pass < MAX_PASSES; pass++) {
      let measured = await this.renderDraftAndMeasure(parsed, round);
      if (!measured) return;
      let result = reconcileProportions(parsed, analysis, measured, skipRefs);
      this.lastCalibrationResidual = result.residual;
      if (result.residual !== null) {
        this.log(
          `> measured proportion residual ${result.residual.toFixed(3)}`,
        );
      }
      for (let line of result.logs) {
        this.log(`> ${line}`);
      }
      if (result.logs.length) {
        for (let line of fitCurvedDecals(parsed)) {
          this.log(`> ${line}`);
        }
      }
      if (
        !result.logs.length ||
        (result.residual !== null && result.residual <= TARGET_RESIDUAL)
      ) {
        break;
      }
    }
    if (typeof this.lastCalibrationResidual === 'number') {
      this.log(
        `> calibration residual ${(this.lastCalibrationResidual * 100).toFixed(0)}%`,
      );
    }
  }

  async loadReferenceImage(): Promise<HTMLImageElement | undefined> {
    try {
      let dataUrl = await this.encodeReference();
      return await new Promise((resolve, reject) => {
        let img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => reject(new Error('reference image unreadable'));
        img.src = dataUrl;
      });
    } catch {
      return undefined;
    }
  }

  // silhouette tracing: revolved bodies (bottles, vases, cans) get their
  // lathe profile measured straight from the reference pixels — the traced
  // outline replaces whatever profile the model invented, so cone-shaped
  // bottles cannot happen. Analysis usually splits ONE revolved silhouette
  // into stacked parts (body / shoulder / neck / base); those share an
  // axis, so they are traced as a single union outline. Objects whose
  // revolved parts are NOT one stacked silhouette are left alone — see the
  // guards below. Returns the part names the trace now embodies —
  // reconciliation must not rescale them individually (that is what turned a
  // bottle into a spinning top).
  async applyTracedProfiles(parsed: any): Promise<string[]> {
    // stale envelope from a prior build must not clamp this one, and its
    // outline must not stay on screen claiming to be this build's — every
    // path out of here below is a path that never reaches the trace
    this.tracedEnvelope = null;
    this.tracedOutline = undefined;
    let plan: any[] = this.parsedAnalysis()?.partPlan ?? [];
    let revolved = plan.filter(
      (p: any) => p?.approach === 'revolved' && p?.bbox?.width > 0,
    );
    if (!revolved.length) return [];
    let lathes = (parsed.components ?? []).filter(
      (c: any) => c?.primitive === 'lathe',
    );
    if (!lathes.length) return [];
    let image = await this.loadReferenceImage();
    if (!image) return [];

    // only trace when the revolved parts really are ONE stacked silhouette
    // and that silhouette is the object itself — a round component inside a
    // machine is neither, and tracing it hands the whole build a wrong
    // envelope
    let { bbox: cropBbox, skipped } = revolvedSilhouetteBbox(plan);
    if (!cropBbox) {
      this.log(`> ${skipped} — skipped silhouette trace`);
      return [];
    }
    // capture the segmented outline for the sidebar preview — this is the
    // exact contour the tracer sees, so a mismatch with the reference is
    // visible instead of hidden inside a failed build
    this.tracedOutline = traceSilhouetteSvg(image, cropBbox) ?? undefined;
    let traceDiag: string[] = [];
    let traced = traceLatheProfile(image, cropBbox, 16, traceDiag);
    if (!traced) {
      this.log(
        `> silhouette trace failed (${traceDiag[0] ?? 'unknown'}) — kept authored profiles`,
      );
      return [];
    }

    // the tallest lathe is the object's revolved silhouette — replace its
    // profile; its authored height stays as the world-size anchor
    let span = (lathe: any): { minY: number; maxY: number } => {
      let d: number[] = Array.isArray(lathe.dimensions)
        ? lathe.dimensions
        : JSON.parse(lathe.dimensions || '[]');
      let ys: number[] = [];
      for (let i = 1; i < d.length; i += 2) ys.push(d[i]);
      return {
        minY: ys.length ? Math.min(...ys) : -0.5,
        maxY: ys.length ? Math.max(...ys) : 0.5,
      };
    };
    let primary = lathes.reduce((a: any, b: any) => {
      let sa = span(a);
      let sb = span(b);
      return sb.maxY - sb.minY > sa.maxY - sa.minY ? b : a;
    });
    let { minY, maxY } = span(primary);
    let height = maxY - minY || 1;
    let scaled: number[] = [];
    for (let i = 0; i + 1 < traced.length; i += 2) {
      scaled.push(
        Number((traced[i] * height).toFixed(4)),
        Number((minY + traced[i + 1] * height).toFixed(4)),
      );
    }
    primary.dimensions = scaled;
    // the world-space profile IS the reconcile envelope — every solid part
    // gets clamped inside it (clampToEnvelope) so nothing floats wider than
    // the traced outline at its height. The lathe's own position offsets its
    // local geometry into world space, and the other parts are authored in
    // world coords, so the envelope MUST carry that offset — otherwise a body
    // shifted down (e.g. pos.y -1.35) leaves the cap comparing against a
    // phantom top and floating far above.
    let lathePos = Array.isArray(primary.position)
      ? primary.position
      : [0, 0, 0];
    let latheY = lathePos[1] ?? 0;
    let envelope: { y: number; half: number }[] = [];
    for (let i = 0; i + 1 < scaled.length; i += 2) {
      envelope.push({ half: scaled[i], y: scaled[i + 1] + latheY });
    }
    this.tracedEnvelope = envelope;

    // the traced lathe IS the entire glass body (silhouette includes the
    // neck + lip). Any OTHER on-axis cylinder/lathe of the same glass
    // material the model stacked on is a duplicate neck/shoulder that just
    // floats — drop it. Non-cylinder glass features (a punt sphere) and parts
    // of other materials (cap, foil, band) are kept.
    let glassMat = primary.materialId;
    let axial = (c: any) => {
      let p = Array.isArray(c.position) ? c.position : [0, 0, 0];
      return Math.abs(p[0] ?? 0) < 0.08 && Math.abs(p[2] ?? 0) < 0.08;
    };
    let before = parsed.components.length;
    parsed.components = parsed.components.filter(
      (c: any) =>
        c === primary ||
        !(c.primitive === 'cylinder' || c.primitive === 'lathe') ||
        c.materialId !== glassMat ||
        !axial(c),
    );
    let removed = before - parsed.components.length;
    if (removed > 0) {
      this.log(
        `> removed ${removed} duplicate glass body part(s) the lathe already covers`,
      );
    }

    // surface any mask-repair note (white-label gap fill) alongside success
    for (let line of traceDiag) this.log(`> ${line}`);
    this.log(
      `> traced '${primary.nodeId}' silhouette from reference (${scaled.length / 2} points)`,
    );
    return revolved.map((p: any) => String(p.part));
  }

  // superimpose real artwork: for every decal that names an analysis part
  // (textureRef), crop that part's bbox out of the reference photo, write
  // it into the realm as a webp, and point the decal's textureUrl at it —
  // the model wears its OWN label instead of a canvas-painted stand-in
  async applyTextures(parsed: any) {
    let decals = (parsed.components ?? []).filter(
      (c: any) =>
        c?.textureRef &&
        (c.primitive === 'textDecal' || c.primitive === 'curvedDecal') &&
        !c.textureUrl,
    );
    if (!decals.length) return;
    let plan: any[] = this.parsedAnalysis()?.partPlan ?? [];
    if (!plan.length) return;
    let image = await this.loadReferenceImage();
    if (!image) return; // decals fall back to painted text
    for (let decal of decals) {
      let wanted = String(decal.textureRef).trim().toLowerCase();
      let part = plan.find(
        (p: any) =>
          String(p?.part ?? '')
            .trim()
            .toLowerCase() === wanted,
      );
      // prefer the plan's "artwork" region over the part's own bbox: the part
      // bbox covers the whole component, while artwork points at just the
      // printed graphic on it. Cropping the whole part drags in the
      // surrounding paint and shading, which is why a label crop can arrive
      // with a band of bottle glass down its edge.
      let bbox = part?.artwork ?? part?.bbox;
      if (
        !bbox ||
        !(bbox.width > 0) ||
        !(bbox.height > 0) ||
        bbox.left < 0 ||
        bbox.top < 0
      ) {
        continue;
      }
      if (part?.artwork) {
        this.log(`> cropping '${decal.textureRef}' from its artwork region`);
      }
      // Knock the photo's backdrop out of the crop first. A bbox is a
      // rectangle and the artwork inside it usually is not, so an opaque crop
      // carries a band of the backdrop onto the model — a foil capsule arrived
      // as the capsule plus two white wings. Segmentation returns null when
      // there is no background to remove (a label on glass, a placard on
      // painted metal), and the plain opaque crop is right in that case.
      let cut = cropWithBackgroundRemoved(image, bbox);
      if (cut) this.log(`> cut background out of '${decal.textureRef}' crop`);
      let canvas = cut;
      if (!canvas) {
        let sx = Math.round(bbox.left * image.width);
        let sy = Math.round(bbox.top * image.height);
        let sw = Math.max(1, Math.round(bbox.width * image.width));
        let sh = Math.max(1, Math.round(bbox.height * image.height));
        canvas = document.createElement('canvas');
        canvas.width = sw;
        canvas.height = sh;
        canvas.getContext('2d')!.drawImage(image, sx, sy, sw, sh, 0, 0, sw, sh);
      }
      let base64 = canvas.toDataURL('image/webp', 0.92).split(',')[1];
      if (!base64) continue;
      let written = await writeRealmImage(this.args.context!.commandContext!, {
        realm: this.realmHref,
        path: `${this.studioAssetDir}/textures/${slugify(decal.textureRef, 'artwork')}.webp`,
        base64,
        contentType: 'image/webp',
      });
      if (written?.url) {
        decal.textureUrl = written.url;
        this.log(`> cropped '${decal.textureRef}' artwork from reference`);
      }
    }
  }

  async applyParsedSpec(
    parsed: any,
    opts: { inPlace?: boolean } = {},
  ): Promise<{ score: number | undefined; featuresOk: boolean }> {
    let model = this.args.model!;
    let commandContext = this.args.context!.commandContext!;
    this.phase = 'building';
    this.log(`> building ${parsed.components.length} components…`);
    let tracedPartRefs = await this.applyTracedProfiles(parsed);
    await this.applyTextures(parsed);
    // reconcile every solid part inside the traced silhouette envelope (only
    // when the trace succeeded — a bad LLM profile is not a boundary)
    if (this.tracedEnvelope) {
      for (let line of clampToEnvelope(parsed, this.tracedEnvelope, true)) {
        this.log(`> ${line}`);
      }
    }
    for (let line of stripRedundantLabelParts(parsed)) {
      this.log(`> ${line}`);
    }
    for (let line of fitCurvedDecals(parsed)) {
      this.log(`> ${line}`);
    }

    let current = this.currentCreation;
    // in-place mode (lasso edits): overwrite the CURRENT round's file + card
    // instead of spawning a new instance. Falls back to a new round if there
    // is no current creation to overwrite.
    let inPlace = Boolean(opts.inPlace && current?.codeFileUrl);
    let previous = model.latestCreation;
    let round = inPlace ? (current!.round ?? 1) : (previous?.round ?? 0) + 1;
    let meta = {
      round,
      score: typeof parsed.score === 'number' ? parsed.score : null,
    };
    // A LASSO EDIT IS THE USER OVERRULING THE PLAN, so the plan must not
    // overrule it back. Measured reconciliation resizes and re-centres every
    // partRef group toward the analysis bbox — which is exactly the number the
    // user just rejected by hand. Left running, a "this label covers too much
    // of the bottle" edit was shrunk by the model and then dragged back toward
    // the planned label bbox by this pass, and what survived was a thin band at
    // the shoulder with the artwork gone.
    if (inPlace) {
      this.log('> hand edit: skipping measured reconciliation');
    } else {
      await this.reconcileDraftProportions(parsed, round, tracedPartRefs);
    }
    this.workingSpec = parsed;

    let slug = slugify(parsed.objectName || 'model', 'model');

    if (inPlace) {
      // rewrite the current round's exact file, keep the same card
      let curUrl = current!.codeFileUrl!;
      let rel =
        this.realmHref && curUrl.startsWith(this.realmHref)
          ? curUrl.slice(this.realmHref.length)
          : `${this.studioAssetDir}/exports/${slug}-round-${round}.js`;
      await new WriteTextFileCommand(commandContext).execute({
        path: rel,
        content: generateModelJs(parsed, meta),
        realm: this.realmHref,
        overwrite: true,
      } as any);
      // force the iframe to re-fetch the same (now overwritten) URL
      this.inPlaceReloadKey = this.inPlaceReloadKey + 1;
      this.draftViewerSrcdoc = undefined;
      this.pendingViewportUrl = undefined;
      let viewUrl =
        curUrl +
        (curUrl.includes('?') ? '&' : '?') +
        'rk=' +
        this.inPlaceReloadKey;
      if (!(await this.waitForViewer(viewUrl))) {
        this.log('> viewer reload timed out — render may be stale');
      }
      // update the SAME SculptedModel in place (no new card)
      current!.critique = String(parsed.critique ?? '');
      if (typeof parsed.score === 'number') current!.score = parsed.score;
      let shot = await this.persistRenderScreenshot(
        parsed.objectName || 'model',
        round,
      );
      if (shot) current!.renderScreenshot = shot;
      await new SaveCardCommand(commandContext).execute({
        card: current as any,
        realm: (model as any)[realmURL]?.href,
      } as any);
      let failedInPlace = Object.entries(parsed.featureCheck ?? {})
        .filter(([, v]) => String(v).toLowerCase() === 'fail')
        .map(([k]) => k);
      for (let f of failedInPlace) this.log(`> feature FAIL: ${f}`);
      return {
        score: typeof parsed.score === 'number' ? parsed.score : undefined,
        featuresOk: failedInPlace.length === 0,
      };
    }

    // the model's stored form: a real three.js module in the realm, with
    // the source spec riding inside it as SCULPT_SPEC
    let written = await new WriteTextFileCommand(commandContext).execute({
      path: `${this.studioAssetDir}/exports/${slug}-round-${round}.js`,
      content: generateModelJs(parsed, meta),
      realm: this.realmHref,
      useNonConflictingFilename: true,
    } as any);
    let codeFileUrl = (written as any)?.fileIdentifier as string;
    // switch the viewport to the just-written file for the screenshot — the
    // studio holds no code URL of its own, so this transient pointer bridges
    // the gap until the SculptedModel below is saved and linked
    this.pendingViewportUrl = codeFileUrl;
    this.draftViewerSrcdoc = undefined;
    // a fresh round supersedes any in-place reload key
    this.inPlaceReloadKey = 0;
    // the viewport iframe reloads on the src change; wait for the scene so
    // the archived screenshot shows THIS round
    if (!(await this.waitForViewer(codeFileUrl))) {
      this.log('> persisted viewer timed out — render archive may be missing');
    }

    // persist this round as its own SculptedModel card and link it, carrying
    // EVERY reference view it was built from (not just the primary) — each
    // image copied in its own mode (ImageDef link for linked files, url
    // otherwise) so the saved round holds the same multi-image set the studio does
    let sourceImages = model.references?.images ?? [];
    let referencesCopy = new MultiImageSourceField({
      images: sourceImages.map((img: any) =>
        img?.sourceMode === 'file' && img?.file
          ? new ImageSourceField({ file: img.file, sourceMode: 'file' })
          : new ImageSourceField({ url: img?.resolvedUrl, sourceMode: 'url' }),
      ),
    });
    let creation = new SculptedModel({
      references: referencesCopy,
      codeFileUrl,
      codeFile: this.makeCodeFileDef(codeFileUrl),
      objectName: parsed.objectName || 'model',
      // the analysis this build followed rides on the creation itself, so
      // selecting this version later re-attaches its measured targets
      analysis: this.activeAnalysis
        ? JSON.stringify(this.activeAnalysis)
        : undefined,
      critique: String(parsed.critique ?? ''),
      score: typeof parsed.score === 'number' ? parsed.score : null,
      buildMetrics: JSON.stringify(this.buildMetrics(parsed)),
      renderScreenshot: await this.persistRenderScreenshot(
        parsed.objectName || 'model',
        round,
      ),
      parentCreation: previous ?? undefined,
      round,
      modelUsed: model.llmModel || VISION_MODEL,
      createdAt: new Date(),
      // scopes the prerendered history search to this studio card
      sourceStudioId: model.id,
    });
    let saved = (await new SaveCardCommand(commandContext).execute({
      card: creation,
      realm: (model as any)[realmURL]?.href,
      // keep each round's card beside this studio's own assets, under
      // img-to-3d/<studio-id>/rounds/, instead of the realm root
      localDir: `${this.studioAssetDir}/rounds`,
    } as any)) as SculptedModel;
    // SaveCard returns a detached, GC-eligible instance — re-resolve a
    // store-tracked one before linking it as latestCreation
    let store = (this.args.context as any)?.store;
    let tracked =
      saved?.id && store?.get ? await store.get(saved.id) : undefined;
    let creationCard =
      tracked && !(tracked as any).isCardError ? tracked : saved;
    // this round is now both the newest (latestCreation) and what's shown
    // (selectedCreation); the transient viewport pointer can retire — the
    // viewport now reads the creation's own codeFileUrl
    model.latestCreation = creationCard;
    model.selectedCreation = creationCard;
    this.pendingViewportUrl = undefined;
    // persist the studio card itself so these links survive a page reload —
    // the parentCreation history walk roots at latestCreation, and relying on
    // host auto-save alone left the pointer unsaved (empty history on refresh)
    try {
      await new SaveCardCommand(commandContext).execute({
        card: model,
      } as any);
    } catch (e) {
      this.log(`> could not persist studio link: ${(e as Error).message}`);
    }

    // per-feature gate (img2threejs rule): a good global score cannot
    // excuse a failing identity feature
    let failed = Object.entries(parsed.featureCheck ?? {})
      .filter(([, v]) => String(v).toLowerCase() === 'fail')
      .map(([k]) => k);
    for (let f of failed) {
      this.log(`> feature FAIL: ${f}`);
    }
    return {
      score: typeof parsed.score === 'number' ? parsed.score : undefined,
      featuresOk: failed.length === 0,
    };
  }

  // captures the current viewport and writes it into the realm as a WebP,
  // returning a file-backed ImageDef to archive on the creation
  async persistRenderScreenshot(name: string, round: number): Promise<any> {
    try {
      let dataUrl = this.frameWindow?.captureScreenshot?.();
      let base64 = dataUrl?.split(',')[1];
      if (!base64) return undefined;
      return await writeRealmImage(this.args.context!.commandContext!, {
        realm: (this.args.model as any)?.[realmURL]?.href,
        path: `${this.studioAssetDir}/renders/${slugify(name, 'model')}-round-${round}.webp`,
        base64,
        contentType: 'image/webp',
      });
    } catch {
      // archiving the screenshot is best-effort; the spec is still kept
      return undefined;
    }
  }

  <template>
    <article class='studio {{unless this.hasLinkedTheme "i3d-default-theme"}}'>
      <header class='studio-header'>
        <h1 class='studio-title'>◇ img-to-3d generator</h1>
        <div class='studio-header-right'>
          {{#if this.hasModel}}
            <button
              type='button'
              data-i3d-history-anchor
              class='history-btn {{if this.historyOpen "is-open"}}'
              {{on 'click' this.toggleHistory}}
            >
              🕘 History
            </button>
            <ImgTo3dPopover
              @anchor='[data-i3d-history-anchor]'
              @open={{this.historyOpen}}
              @title='generations'
              @kicker='click a version to make it current'
              @placement='bottom-end'
              @label='Generation history'
              @onClose={{this.closeHistory}}
            >
              <:body>
                <div class='history-body'>
                  {{#if this.historyLoading}}
                    <p class='history-empty'>loading…</p>
                  {{else if this.historyItems.length}}
                    {{! current pick, cloned to the top as a wide strip }}
                    {{#if this.currentHistoryEntry}}
                      <div class='history-strip'>
                        <span class='history-strip-frame'>
                          <iframe
                            class='history-iframe'
                            title='current pick preview'
                            srcdoc={{this.currentHistoryEntry.srcdoc}}
                            loading='lazy'
                            tabindex='-1'
                          ></iframe>
                        </span>
                        <div class='history-strip-info'>
                          <span class='history-strip-title'>current pick</span>
                          <span class='history-strip-sub'>
                            {{#if this.currentHistoryEntry.round}}round
                              {{this.currentHistoryEntry.round}}
                              ·
                            {{/if}}{{this.currentHistoryEntry.objectName}}
                          </span>
                        </div>
                        <div class='history-menu-wrap'>
                          <button
                            type='button'
                            class='history-menu-btn'
                            {{on 'click' this.toggleStripMenu}}
                            aria-label='More actions for current pick'
                          >⋮</button>
                          {{#if this.stripMenuOpen}}
                            <div class='history-menu' role='menu'>
                              <button
                                type='button'
                                class='history-menu-item'
                                {{on
                                  'click'
                                  (fn
                                    this.exportHistoryGlb
                                    this.currentHistoryEntry
                                  )
                                }}
                              >⬇ Export .glb</button>
                              <button
                                type='button'
                                class='history-menu-item'
                                {{on
                                  'click'
                                  (fn
                                    this.copyHistoryEmbed
                                    this.currentHistoryEntry
                                  )
                                }}
                              >⧉ Copy iframe</button>
                              <button
                                type='button'
                                class='history-menu-item'
                                {{on
                                  'click'
                                  (fn
                                    this.openHistoryCard
                                    this.currentHistoryEntry
                                  )
                                }}
                              >↗ Open 3D creation</button>
                            </div>
                          {{/if}}
                        </div>
                      </div>
                    {{/if}}
                    <div class='history-grid'>
                      {{#each this.historyItems as |entry|}}
                        <div
                          class='history-card
                            {{if (this.isCurrentEntry entry) "is-current"}}'
                        >
                          <span class='history-frame'>
                            <iframe
                              class='history-iframe'
                              title='round {{entry.round}} preview'
                              srcdoc={{entry.srcdoc}}
                              loading='lazy'
                              tabindex='-1'
                              {{on
                                'load'
                                (fn this.onHistoryFrameLoad entry.id)
                              }}
                            ></iframe>
                          </span>
                          <span class='history-meta'>
                            <span class='history-round'>
                              {{#if entry.round}}round
                                {{entry.round}}{{else}}model{{/if}}
                            </span>
                            {{#if (this.isCurrentEntry entry)}}
                              <span class='history-current-badge'>current</span>
                            {{/if}}
                          </span>
                          {{! transparent full-card overlay is the click
                              target — a real button, sibling of the iframe
                              (never its parent) so it stays valid }}
                          <button
                            type='button'
                            class='history-select'
                            {{on 'click' (fn this.selectHistoryEntry entry)}}
                            aria-label='Select round {{entry.round}}'
                          ></button>
                          <div class='history-menu-wrap'>
                            <button
                              type='button'
                              class='history-menu-btn'
                              {{on 'click' (fn this.toggleEntryMenu entry.id)}}
                              aria-label='More actions'
                            >⋮</button>
                            {{#if (this.isMenuOpen entry)}}
                              <div class='history-menu' role='menu'>
                                <button
                                  type='button'
                                  class='history-menu-item'
                                  {{on
                                    'click'
                                    (fn this.exportHistoryGlb entry)
                                  }}
                                >⬇ Export .glb</button>
                                <button
                                  type='button'
                                  class='history-menu-item'
                                  {{on
                                    'click'
                                    (fn this.copyHistoryEmbed entry)
                                  }}
                                >⧉ Copy iframe</button>
                                <button
                                  type='button'
                                  class='history-menu-item'
                                  {{on 'click' (fn this.openHistoryCard entry)}}
                                >↗ Open 3D creation</button>
                              </div>
                            {{/if}}
                          </div>
                        </div>
                      {{/each}}
                    </div>
                  {{else}}
                    <p class='history-empty'>no generations yet</p>
                  {{/if}}
                </div>
              </:body>
            </ImgTo3dPopover>
          {{/if}}
          <button
            type='button'
            class='new-sculpture-btn'
            {{on 'click' this.newSculpture}}
          >
            + New Sculpture
          </button>
          <p class='studio-status' role='status'>
            {{#if this.isRunning}}
              ●
              {{this.phase}}…
            {{else if this.hasModel}}
              rebuilt in code
            {{else if this.hasReference}}
              photo ready
            {{else}}
              awaiting photo
            {{/if}}
          </p>
        </div>
      </header>

      <div class='studio-body'>
        <aside class='panel' aria-label='Reference photos and controls'>
          {{! the multi-image editor owns the whole photo experience —
              hero preview, thumbnail strip with per-image remove, and
              Link/URL adding all live inside the field's own edit UI
              (re-skinned via the --img-source-* knobs) }}
          <section class='add-photos' aria-label='Reference photos'>
            <div class='source-editor'>
              <@fields.references @format='edit' />
            </div>
            {{#if this.referencesChanged}}
              <p class='reanalyze-hint' role='status'>
                ↻ references changed — Generate will re-analyze the object from
                the new photos before building.
              </p>
            {{/if}}
            {{#if this.canRequestReanalyze}}
              <button
                type='button'
                class='reanalyze-btn {{if this.reanalyzeRequested "is-on"}}'
                disabled={{this.isRunning}}
                title='Discard the cached part plan — use when the plan itself is wrong (missing parts, wrong decomposition), since re-generating alone will keep reusing it'
                {{on 'click' this.toggleReanalyze}}
              >
                {{if
                  this.reanalyzeRequested
                  '↻ will re-analyze on next Generate — click to cancel'
                  '↻ Re-analyze plan'
                }}
              </button>
            {{/if}}
          </section>

          <button
            type='button'
            class='generate-btn'
            disabled={{this.isRunning}}
            {{on 'click' this.startGenerate}}
          >
            {{#if this.isRunning}}
              Working…
            {{else}}
              ⚡ Generate Model
            {{/if}}
          </button>

          {{#if this.isRunning}}
            <button
              type='button'
              class='stop-btn'
              disabled={{this.stopRequested}}
              {{on 'click' this.stopRefinement}}
            >
              {{if this.stopRequested 'Stopping…' '⏹ Stop'}}
            </button>
          {{/if}}

          {{#if this.hasModel}}
            <button
              type='button'
              class='refine-ai-btn'
              disabled={{this.isRunning}}
              {{on 'click' this.startRefineWithAi}}
            >
              ✨ Refine with AI
            </button>
          {{/if}}

          {{! TEMPORARILY HIDDEN: the "Edit a part" (lasso/inpaint) feature and
               its Undo companion — wrapped in an always-false conditional to
               hide the UI while keeping the code intact. Restore by switching
               the first guard back to this.hasModel and the second to
               this.inpaintUndoAvailable. }}
          {{#if false}}
            <button
              type='button'
              class='lasso-btn {{if this.inpaintMode "is-on"}}'
              disabled={{this.isRunning}}
              {{on 'click' this.toggleInpaint}}
            >
              {{! named for the instruction box, not the lasso: describing the
                  edit is the main route and drawing round a part is the
                  fallback for when it is hard to name }}
              {{if this.inpaintMode '✕ Done editing' '✏️ Edit a part'}}
            </button>
          {{/if}}

          {{#if false}}
            <button
              type='button'
              class='lasso-btn'
              disabled={{this.isRunning}}
              {{on 'click' this.startRevertInpaint}}
            >
              ↶ Undo lasso edit
            </button>
          {{/if}}

          {{! Export .glb / Copy iframe now live in each version’s History
              menu (⋮), so the sidebar stays focused on generate/stop }}

          {{#if this.errorMessage}}
            <p class='error' role='alert'>{{this.errorMessage}}</p>
          {{/if}}

          {{#if this.tracedOutline}}
            <figure class='traced-outline' aria-label='Traced silhouette'>
              <figcaption class='traced-outline-label'>traced outline</figcaption>
              <svg
                class='traced-outline-svg'
                viewBox='0 0 {{this.tracedOutline.width}}
                  {{this.tracedOutline.height}}'
                preserveAspectRatio='xMidYMid meet'
              >
                <path d={{this.tracedOutline.path}} />
              </svg>
            </figure>
          {{/if}}

          {{#if this.logLines.length}}
            <output class='log' aria-live='polite'>
              {{#each this.logLines as |line|}}
                <span class='log-line'>{{line}}</span>
              {{/each}}
            </output>
          {{/if}}
        </aside>

        <main class='viewport' aria-label='3D model viewport'>
          {{#if this.viewerSrcdoc}}
            {{! the same harness external sites embed by URL, inlined via
                srcdoc so the viewport needs no .html round-trip }}
            <iframe
              class='viewport-frame'
              title='3D model viewer'
              srcdoc={{this.viewerSrcdoc}}
              {{on 'load' this.onFrameLoad}}
            ></iframe>
            {{#if this.currentCreation}}
              <div class='viewport-badge'>
                {{#if this.currentCreation.round}}
                  <span class='viewport-badge-round'>round
                    {{this.currentCreation.round}}</span>
                {{/if}}
                {{#if this.currentObjectName}}
                  <span
                    class='viewport-badge-name'
                  >{{this.currentObjectName}}</span>
                {{/if}}
              </div>
            {{/if}}
            {{#if this.inpaintMode}}
              {{! transparent draw surface over the iframe; only active in
                  lasso mode so normal orbit works otherwise. pointerdown is
                  required to begin a freehand lasso stroke. }}
              {{! template-lint-disable no-pointer-down-event-binding }}
              <canvas
                class='inpaint-overlay'
                {{on 'pointerdown' this.lassoDown}}
                {{on 'pointermove' this.lassoMove}}
                {{on 'pointerup' this.lassoUp}}
              ></canvas>
              {{! the instruction box is always available: naming a part is
                  usually quicker than orbiting to it and drawing round it.
                  A lasso is optional, for when the part is hard to name. }}
              <div class='inpaint-bar'>
                {{#if this.lassoDrawn}}
                  <span class='inpaint-count'>{{this.inpaintTargetCount}}
                    selected</span>
                {{else}}
                  {{! not "all parts" — with no lasso the target is resolved
                      FROM the instruction, so an unselected edit still touches
                      only the part it names }}
                  <span class='inpaint-count is-hint'>named below</span>
                {{/if}}
                <input
                  class='inpaint-input'
                  type='text'
                  aria-label='Describe the edit'
                  placeholder='name a part — e.g. make the label 60% as tall'
                  value={{this.inpaintInstruction}}
                  disabled={{this.inpaintBusy}}
                  {{on 'input' this.setInstruction}}
                />
                <button
                  type='button'
                  class='inpaint-apply'
                  disabled={{this.inpaintBusy}}
                  {{on 'click' this.startInpaint}}
                >{{if this.inpaintBusy 'Working…' 'Apply'}}</button>
                {{#if this.lassoDrawn}}
                  <button
                    type='button'
                    class='inpaint-clear'
                    disabled={{this.inpaintBusy}}
                    {{on 'click' this.resetLasso}}
                  >Clear</button>
                {{/if}}
              </div>
            {{/if}}
          {{else}}
            <div class='viewport-empty'>
              {{#if this.viewportHint}}
                <p class='viewport-hint'>{{this.viewportHint}}</p>
              {{/if}}
            </div>
          {{/if}}
          {{#if this.isRunning}}
            {{! sweeps the viewport edge while a round is in flight. The wrapper
                carries the knobs (a component invocation can't take this
                template's scoped styles) and stays click-through so the model
                underneath is still orbitable. }}
            <div class='viewport-generating'>
              <GeneratingOverlay @label={{this.phase}}>
                {{#if this.latestLogLine}}
                  <span class='viewport-generating-detail'>
                    {{this.latestLogLine}}
                  </span>
                {{/if}}
              </GeneratingOverlay>
            </div>
          {{/if}}
        </main>
      </div>
    </article>

    <style scoped>
      /* The studio's palette, named once here and referenced by name
         everywhere below. Each token resolves the semantic theme token if
         the realm supplies one, and falls back to a deep-space literal if
         it does not — so the card looks intentional with no theme linked
         and inherits the theme's palette when there is one. Set any
         --i3d-* on a descendant to override it locally. */
      .studio {
        --i3d-bg: var(--background, #0a0b10);
        --i3d-surface: var(--card, #14161e);
        --i3d-glass: color-mix(in srgb, var(--card, #14161e) 75%, transparent);
        --i3d-border: var(--border, #232838);
        --i3d-text: var(--foreground, #eef0f6);
        --i3d-text-dim: var(--muted-foreground, #9aa0b2);
        --i3d-accent: var(--accent, #38e8ff);
        --i3d-accent-fg: var(--accent-foreground, #0a0b10);
        --i3d-primary: var(--primary, #b98bff);
        --i3d-primary-fg: var(--primary-foreground, #0a0b10);
        --i3d-ring: var(--ring, #7c9fff);
        --i3d-gold: #ffd76a;
        --i3d-radius: var(--radius, 1rem);
        --i3d-font-mono: var(
          --font-mono,
          ui-monospace,
          'SFMono-Regular',
          Menlo,
          monospace
        );
        --i3d-font-sans: var(
          --font-sans,
          -apple-system,
          BlinkMacSystemFont,
          'Segoe UI',
          Roboto,
          sans-serif
        );

        display: flex;
        flex-direction: column;
        height: 100dvh;
        max-height: 100%;
        min-height: 0;
        background: var(--i3d-bg);
        background-image:
          radial-gradient(
            1100px 500px at 85% -10%,
            color-mix(in srgb, var(--i3d-accent) 7%, transparent),
            transparent 60%
          ),
          radial-gradient(
            900px 500px at 0% 0%,
            color-mix(in srgb, var(--i3d-primary) 9%, transparent),
            transparent 55%
          );
        color: var(--i3d-text);
        font-family: var(--i3d-font-sans);
      }
      /* themeless default: pin the deep-space palette on the SEMANTIC
         tokens so app-level defaults can't leak in; a linked theme removes
         this class and takes over the same tokens */
      .i3d-default-theme {
        --background: #2b303d;
        --card: #14161e;
        --border: #232838;
        --foreground: #eef0f6;
        --muted-foreground: #9aa0b2;
        --accent: #38e8ff;
        --accent-foreground: #06161a;
        --primary: #b98bff;
        --primary-foreground: #140620;
        --ring: #7c9fff;
        --radius: 1rem;
        --font-mono: ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
        --font-sans:
          -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      }
      .studio-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0.75rem 1.25rem;
        border-bottom: 1px solid var(--i3d-border);
      }
      .studio-header-right {
        display: flex;
        align-items: center;
        gap: 0.75rem;
      }
      .new-sculpture-btn {
        padding: 0.25rem 0.625rem;
        border: 1px solid var(--i3d-border);
        border-radius: 999px;
        background: var(--i3d-surface);
        color: var(--i3d-text);
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        cursor: pointer;
      }
      .new-sculpture-btn:hover {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
      }
      .history-btn {
        padding: 0.25rem 0.625rem;
        border: 1px solid var(--i3d-border);
        border-radius: 999px;
        background: var(--i3d-surface);
        color: var(--i3d-text);
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        cursor: pointer;
      }
      .history-btn:hover,
      .history-btn.is-open {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
      }
      /* the ImgTo3dPopover shell owns the dark surface, scroll, width and
         the --i3d-* token block; this is just the content flow container */
      .history-body {
        /* a definite width, not max-content: the grid below sizes its columns
           from the container, and a max-content container sized itself from
           the columns instead — the two resolved to one card per row at full
           popover width */
        width: min(34rem, 78vw);
        max-width: 100%;
      }
      .history-popover-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 0.5rem;
        margin-bottom: 0.625rem;
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--i3d-text-dim);
      }
      .history-hint {
        text-transform: none;
        letter-spacing: 0;
        font-size: 0.625rem;
      }
      .history-empty {
        margin: 0;
        padding: 0.75rem 0;
        text-align: center;
        font-family: var(--i3d-font-mono);
        font-size: 0.75rem;
        color: var(--i3d-text-dim);
      }
      .history-grid {
        display: grid;
        /* three per row, minmax(0,…) so a wide iframe can't push a track past
           its share */
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 0.5rem;
      }
      @media (max-width: 32rem) {
        .history-grid {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
      .history-card {
        position: relative;
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
        padding: 0.375rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.25rem;
        background: var(--i3d-bg);
        text-align: left;
      }
      .history-select {
        position: absolute;
        inset: 0;
        border: 0;
        border-radius: 0.25rem;
        background: transparent;
        cursor: pointer;
      }
      .history-card:hover {
        border-color: var(--i3d-accent);
      }
      .history-card.is-current {
        border-color: var(--i3d-accent);
        box-shadow: 0 0 0 1px var(--i3d-accent);
      }
      .history-frame {
        position: relative;
        display: block;
        width: 100%;
        aspect-ratio: 4 / 3;
        border-radius: 0.1875rem;
        overflow: hidden;
        background: var(--i3d-bg);
      }
      .history-iframe {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        border: 0;
        /* the tile is a picker, not an interactive viewport */
        pointer-events: none;
      }
      .history-meta {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.375rem;
        font-family: var(--i3d-font-mono);
        font-size: 0.625rem;
        color: var(--i3d-text-dim);
      }
      .history-round {
        letter-spacing: 0.1em;
        text-transform: uppercase;
      }
      .history-current-badge {
        padding: 0.05rem 0.35rem;
        border-radius: 999px;
        background: color-mix(in srgb, var(--i3d-accent) 20%, transparent);
        color: var(--i3d-accent);
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      /* current-pick strip cloned to the top of the popover */
      .history-strip {
        position: relative;
        display: flex;
        align-items: center;
        gap: 0.4375rem;
        margin-bottom: 0.4375rem;
        padding: 0.3125rem;
        border: 1px solid var(--i3d-accent);
        border-radius: 0.25rem;
        background: color-mix(in srgb, var(--i3d-accent) 8%, transparent);
      }
      .history-strip-frame {
        position: relative;
        flex-shrink: 0;
        width: 4.25rem;
        aspect-ratio: 4 / 3;
        border-radius: 0.1875rem;
        overflow: hidden;
        background: var(--i3d-bg);
      }
      .history-strip-info {
        display: flex;
        flex-direction: column;
        gap: 0.15rem;
        min-width: 0;
        flex: 1;
      }
      .history-strip-title {
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--i3d-accent);
      }
      .history-strip-sub {
        font-size: 0.75rem;
        color: var(--i3d-text-dim);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      /* per-tile ⋮ menu */
      .history-menu-wrap {
        position: absolute;
        top: 0.25rem;
        right: 0.25rem;
        z-index: 3;
      }
      .history-strip .history-menu-wrap {
        position: static;
      }
      .history-menu-btn {
        display: grid;
        place-items: center;
        width: 1.4rem;
        height: 1.4rem;
        padding: 0;
        border: 1px solid var(--i3d-border);
        border-radius: 0.1875rem;
        background: var(--i3d-surface);
        color: var(--i3d-text);
        font-size: 0.9rem;
        line-height: 1;
        cursor: pointer;
      }
      .history-menu-btn:hover {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
      }
      .history-menu {
        position: absolute;
        top: calc(100% + 0.25rem);
        right: 0;
        z-index: 5;
        display: flex;
        flex-direction: column;
        min-width: 9.5rem;
        padding: 0.1875rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.25rem;
        background: var(--i3d-surface);
        box-shadow: 0 8px 22px rgb(0 0 0 / 45%);
      }
      .history-menu-item {
        padding: 0.4rem 0.55rem;
        border: 0;
        border-radius: 0.1875rem;
        background: transparent;
        color: var(--i3d-text);
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        text-align: left;
        white-space: nowrap;
        cursor: pointer;
      }
      .history-menu-item:hover {
        background: color-mix(in srgb, var(--i3d-accent) 14%, transparent);
        color: var(--i3d-accent);
      }
      .studio-title {
        margin: 0;
        font-family: var(--i3d-font-mono);
        font-size: 0.875rem;
        font-weight: 600;
        letter-spacing: 0.06em;
      }
      .studio-status {
        margin: 0;
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--i3d-accent);
      }
      .studio-body {
        display: grid;
        grid-template-columns: 300px 1fr;
        flex: 1;
        min-height: 0;
      }
      .panel {
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        margin: 1rem;
        padding: 1rem;
        border: 1px solid var(--i3d-border);
        border-radius: 1rem;
        background: var(--i3d-glass);
        backdrop-filter: blur(10px);
        overflow-y: auto;
        z-index: 1;
      }
      /* no chrome of its own — the field editor is the only box here */
      .add-photos {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      /* the MultiImageSource edit UI, re-skinned via its component knobs
         (--img-source-*, scope ① of its three-scope chains); the --boxel-*
         overrides below reach the BoxelInputGroup internals it embeds */
      .source-editor {
        --img-source-bg: var(--i3d-surface);
        --img-source-text: var(--i3d-text);
        --img-source-text-dim: var(--i3d-text-dim);
        --img-source-border: var(--i3d-border);
        --img-source-accent: var(--i3d-accent);
        --img-source-accent-fg: var(--i3d-accent-fg);
        --boxel-light: var(--i3d-surface);
        --boxel-100: color-mix(in srgb, var(--i3d-surface) 92%, white);
        --boxel-400: var(--i3d-text-dim);
        --boxel-500: var(--i3d-text-dim);
        --boxel-700: var(--i3d-text);
        --boxel-dark: var(--i3d-text);
        --boxel-border-color: var(--i3d-border);
        --boxel-purple: var(--i3d-accent);
        --boxel-font-family: inherit;
      }
      /* drop the editor's header — the sidebar context already says
         what this is */
      .source-editor :deep(.header) {
        display: none;
      }
      .generate-btn {
        padding: 0.625rem 1rem;
        border: none;
        border-radius: 0.625rem;
        background: linear-gradient(
          120deg,
          var(--i3d-primary),
          var(--i3d-accent)
        );
        color: var(--i3d-primary-fg);
        font-family: var(--i3d-font-mono);
        font-size: 0.8125rem;
        font-weight: 700;
        cursor: pointer;
      }
      .generate-btn:disabled {
        opacity: 0.55;
        cursor: default;
      }
      .export-btn {
        padding: 0.5rem 1rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.625rem;
        background: transparent;
        color: var(--i3d-text);
        font-family: var(--i3d-font-mono);
        font-size: 0.75rem;
        cursor: pointer;
      }
      /* danger pairing: destructive fill hint stays subtle until hover */
      .stop-btn {
        padding: 0.5rem 1rem;
        border: 1px solid
          color-mix(
            in srgb,
            var(--i3d-destructive, var(--destructive, #ff6b6b)) 50%,
            transparent
          );
        border-radius: 0.625rem;
        background: transparent;
        color: var(--i3d-destructive, var(--destructive, #ff9b9b));
        font-family: var(--i3d-font-mono);
        font-size: 0.75rem;
        cursor: pointer;
      }
      .stop-btn:hover:not(:disabled) {
        border-color: var(--i3d-destructive, var(--destructive, #ff6b6b));
      }
      .stop-btn:disabled {
        opacity: 0.55;
        cursor: default;
      }
      .lasso-btn {
        padding: 0.5rem 1rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.625rem;
        background: transparent;
        color: var(--i3d-text);
        font-family: var(--i3d-font-mono);
        font-size: 0.75rem;
        cursor: pointer;
      }
      .lasso-btn:hover:not(:disabled) {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
      }
      .lasso-btn.is-on {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
        background: color-mix(in srgb, var(--i3d-accent) 10%, transparent);
      }
      .lasso-btn:disabled {
        opacity: 0.55;
        cursor: default;
      }
      /* Refine with AI: same outline family, tinted with the accent so it
         reads as the model's "improve this" action */
      .refine-ai-btn {
        padding: 0.5rem 1rem;
        border: 1px solid
          color-mix(in srgb, var(--i3d-accent) 45%, var(--i3d-border));
        border-radius: 0.625rem;
        background: color-mix(in srgb, var(--i3d-accent) 8%, transparent);
        color: var(--i3d-accent);
        font-family: var(--i3d-font-mono);
        font-size: 0.75rem;
        cursor: pointer;
      }
      .refine-ai-btn:hover:not(:disabled) {
        border-color: var(--i3d-accent);
        background: color-mix(in srgb, var(--i3d-accent) 16%, transparent);
      }
      .refine-ai-btn:disabled {
        opacity: 0.55;
        cursor: default;
      }
      /* same visual family as lasso-btn, but it lives inside the photos
         section so it needs its own top spacing */
      .reanalyze-btn {
        width: 100%;
        margin-top: 0.5rem;
        padding: 0.45rem 0.75rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.625rem;
        background: transparent;
        color: var(--i3d-text-dim);
        font-family: var(--i3d-font-mono);
        font-size: 0.7rem;
        cursor: pointer;
      }
      .reanalyze-btn:hover:not(:disabled) {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
      }
      .reanalyze-btn.is-on {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
        background: color-mix(in srgb, var(--i3d-accent) 10%, transparent);
      }
      .reanalyze-btn:disabled {
        opacity: 0.55;
        cursor: default;
      }
      .export-btn:hover {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
      }
      .export-btn:disabled {
        opacity: 0.55;
        cursor: default;
      }
      .error {
        margin: 0;
        padding: 0.5rem 0.75rem;
        border: 1px solid
          color-mix(
            in srgb,
            var(--i3d-destructive, var(--destructive, #ff6b6b)) 40%,
            transparent
          );
        border-radius: 0.5rem;
        font-size: 0.75rem;
        color: var(--i3d-destructive, var(--destructive, #ff9b9b));
      }
      .reanalyze-hint {
        margin: 0.5rem 0 0;
        padding: 0.5rem 0.75rem;
        border: 1px solid
          color-mix(
            in srgb,
            var(--i3d-accent, var(--accent, #38e8ff)) 35%,
            transparent
          );
        border-radius: 0.5rem;
        background: color-mix(
          in srgb,
          var(--i3d-accent, var(--accent, #38e8ff)) 8%,
          transparent
        );
        font-size: 0.75rem;
        line-height: 1.35;
        color: var(--i3d-accent, var(--accent, #38e8ff));
      }
      .log {
        display: flex;
        flex-direction: column;
        gap: 0.2rem;
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        color: var(--i3d-text-dim);
      }
      .log-line:last-child {
        color: var(--i3d-accent);
      }
      .traced-outline {
        margin: 0;
        padding: 0.5rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.5rem;
        background: var(--i3d-surface);
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
      }
      .traced-outline-label {
        font-family: var(--i3d-font-mono);
        font-size: 0.625rem;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        color: var(--i3d-text-dim);
      }
      .traced-outline-svg {
        display: block;
        width: 100%;
        height: 8rem;
      }
      .traced-outline-svg path {
        fill: color-mix(in srgb, var(--i3d-accent) 22%, transparent);
        stroke: var(--i3d-accent);
        stroke-width: 1.25;
        vector-effect: non-scaling-stroke;
      }
      .viewport {
        position: relative;
        min-height: 0;
        min-width: 0;
      }
      .viewport-frame {
        display: block;
        width: 100%;
        height: 100%;
        border: 0;
        background: var(--i3d-bg);
      }
      /* read-only badge over the iframe: which version is on screen */
      .viewport-badge {
        position: absolute;
        top: 0.75rem;
        right: 0.75rem;
        display: flex;
        align-items: center;
        gap: 0.4rem;
        max-width: 60%;
        padding: 0.3rem 0.6rem;
        border: 1px solid var(--i3d-border);
        border-radius: 999px;
        background: color-mix(in srgb, var(--i3d-surface) 85%, transparent);
        backdrop-filter: blur(6px);
        pointer-events: none;
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
      }
      .viewport-badge-round {
        flex-shrink: 0;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--i3d-accent);
      }
      .viewport-badge-name {
        min-width: 0;
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        color: var(--i3d-text-dim);
      }
      .inpaint-overlay {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        z-index: 5;
        cursor: crosshair;
        touch-action: none;
      }
      .inpaint-bar {
        position: absolute;
        left: 50%;
        bottom: 1rem;
        transform: translateX(-50%);
        z-index: 6;
        display: flex;
        align-items: center;
        gap: 0.5rem;
        max-width: calc(100% - 2rem);
        padding: 0.4rem 0.5rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.25rem;
        background: color-mix(in srgb, var(--i3d-surface) 92%, transparent);
        backdrop-filter: blur(8px);
        box-shadow: 0 10px 28px rgb(0 0 0 / 45%);
      }
      .inpaint-count {
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        color: var(--i3d-accent);
        white-space: nowrap;
      }
      /* no lasso drawn: the scope is 'whatever you name', so this is a
         neutral status rather than an accented selection count */
      .inpaint-count.is-hint {
        color: var(--i3d-text-dim);
      }
      .inpaint-input {
        width: min(22rem, 40vw);
        padding: 0.35rem 0.55rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.5rem;
        background: var(--i3d-bg);
        color: var(--i3d-text);
        font-family: var(--i3d-font-sans);
        font-size: 0.8125rem;
      }
      .inpaint-input:focus {
        outline: none;
        border-color: var(--i3d-accent);
      }
      .inpaint-apply,
      .inpaint-clear {
        padding: 0.35rem 0.7rem;
        border: 1px solid var(--i3d-border);
        border-radius: 0.5rem;
        background: var(--i3d-surface);
        color: var(--i3d-text);
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        cursor: pointer;
      }
      .inpaint-apply {
        border-color: var(--i3d-accent);
        color: var(--i3d-accent);
      }
      .inpaint-apply:disabled,
      .inpaint-clear:disabled {
        opacity: 0.5;
        cursor: default;
      }
      /* click-through frame around the live render while a round builds */
      .viewport-generating {
        --generating-surface: transparent;
        --generating-accent: var(--i3d-accent);
        --generating-label-color: var(--i3d-text-dim);
        position: absolute;
        inset: 0;
        pointer-events: none;
      }
      .viewport-generating-detail {
        position: relative;
        z-index: 1;
        max-width: 70%;
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
        font-family: var(--i3d-font-mono);
        font-size: 0.6875rem;
        color: var(--i3d-text-dim);
      }
      .viewport-empty {
        display: grid;
        place-items: center;
        height: 100%;
      }
      .viewport-hint {
        margin: 0;
        font-family: var(--i3d-font-mono);
        font-size: 0.75rem;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--i3d-text-dim);
      }
      @container (max-width: 640px) {
        .studio-body {
          grid-template-columns: 1fr;
          grid-template-rows: auto 1fr;
        }
      }
    </style>
  </template>
}
