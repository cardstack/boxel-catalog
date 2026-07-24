import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import enumField from 'https://cardstack.com/base/enum';
import {
  codeRef,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { restartableTask } from 'ember-concurrency';

import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import WriteTextFileCommand from '@cardstack/boxel-host/tools/write-text-file';
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';

import { fetchAsDataUrl, slugify, writeRealmImage } from './util/realm-image';
import { generateModelJs, generateViewerHtml } from './util/code-export';
import {
  VISION_MODEL,
  AUTO_REFINE_ROUNDS,
  REFINE_TARGET_SCORE,
  SPEC_SYSTEM_PROMPT,
  REFINE_SYSTEM_PROMPT,
  composeComparison,
  serializeSpecForPrompt,
  requestSpec,
  parseDiffJson,
  applySpecDiff,
  specFieldFromParsed,
} from './util/generation';

import { AnalyzeReferenceCommand } from './commands/analyze-reference';
import { SculptSpecField } from './fields/sculpt-spec';
import { SculptedModel } from './sculpted-model';
import ModelViewer, { type ViewerApi } from './components/model-viewer';

/* @ts-expect-error import.meta is valid ESM */
const here: string = import.meta.url;
const sculptedModelRef = codeRef(here, './sculpted-model', 'SculptedModel');
const studioRef = codeRef(here, './img-to-3d-studio', 'ImgTo3dStudio');

export class ImgTo3dStudio extends CardDef {
  static displayName = 'Img-to-3D Generator';
  static prefersWideFormat = true;

  // all reference photos in one multi-image field: the first image is the
  // primary view, the rest are side / back / detail shots — every view feeds
  // the initial generation; thickness and hidden sides come from exactly these
  @field references = contains(MultiImageSourceField);
  @field currentSpec = contains(SculptSpecField);
  // stage-1 analysis JSON (object type, camera estimate, per-part measured
  // bboxes, attachment constraints) — persisted so refine rounds and later
  // sessions keep the measured targets, not just the built result
  @field analysis = contains(StringField);
  // every generation is saved as its own SculptedModel card; the studio only
  // links the LATEST one — older rounds hang off parentCreation links and
  // load on demand, keeping this card light no matter how long the history
  @field latestCreation = linksTo(() => SculptedModel);
  @field llmModel = contains(
    enumField(StringField, {
      options: [
        'anthropic/claude-sonnet-5',
        'anthropic/claude-sonnet-4.6',
        'anthropic/claude-opus-4.8',
        'google/gemini-3.5-flash',
        'google/gemini-3.6-flash',
      ],
      displayName: 'Vision Model',
    }),
  );
  @field title = contains(StringField, {
    computeVia: function (this: ImgTo3dStudio) {
      return this.currentSpec?.objectName || 'Img-to-3D Studio';
    },
  });

  static isolated = class Isolated extends Component<typeof ImgTo3dStudio> {
    @tracked phase: 'idle' | 'analyzing' | 'building' | 'done' | 'error' =
      'idle';
    @tracked errorMessage: string | null = null;
    @tracked logLines: string[] = [];

    viewerApi: ViewerApi | undefined;

    get hasLinkedTheme() {
      return Boolean(this.args.model?.cardInfo?.theme);
    }

    get hasSpec() {
      return (this.args.model?.currentSpec?.components?.length ?? 0) > 0;
    }

    get hasReference() {
      return Boolean(this.args.model?.references?.primaryUrl);
    }

    get latestCreation() {
      return this.args.model?.latestCreation;
    }

    // every round is its own SculptedModel card scoped by sourceStudioId, so
    // history renders from prerendered search entries — no card is loaded
    // until a tile is actually clicked
    get historyQuery(): SearchEntryWireQuery | undefined {
      let model = this.args.model;
      let id = model?.id;
      let realm = model?.[realmURL]?.href;
      if (!id || !realm) return undefined;
      return {
        ...searchEntryWireQueryFromQuery({
          filter: { on: sculptedModelRef, eq: { sourceStudioId: id } },
          // oldest first (leftmost tile), newest appended at the right —
          // matches the order rounds appear in during a live refine run, so
          // a reload never flips the strip. round is a strictly increasing
          // integer per studio; createdAt breaks ties so the order is
          // stable even when rounds collide or are missing
          sort: [
            { by: 'round', on: sculptedModelRef, direction: 'asc' },
            { by: 'createdAt', on: sculptedModelRef, direction: 'asc' },
          ],
        }),
        realms: [realm],
      };
    }

    // which round the viewport is showing — defaults to the latest; set by
    // clicking a history tile so the strip can mark the current one
    @tracked shownRoundId: string | undefined;

    get currentRoundId() {
      return this.shownRoundId ?? this.latestCreation?.id;
    }

    // restore an archived round into the viewport; the SculptedModel is
    // hydrated only when its tile is picked
    showRound = async (id: string) => {
      let model = this.args.model;
      if (!model || !id) return;
      let creation: any = await (this.args as any).context?.store?.get(id);
      if (!creation?.spec) return;
      model.currentSpec = creation.spec;
      this.shownRoundId = id;
      await this.viewerApi?.rebuild();
    };

    get isRunning() {
      return this.phase === 'analyzing' || this.phase === 'building';
    }

    get viewportHint() {
      if (this.hasSpec || this.isRunning) return undefined;
      return this.hasReference
        ? 'ready — hit generate'
        : 'add a reference photo';
    }

    onViewerReady = (api: ViewerApi) => {
      this.viewerApi = api;
    };

    lastBuildWarnings: string[] = [];

    onViewerWarnings = (warnings: string[]) => {
      this.lastBuildWarnings = warnings;
      for (let w of warnings.slice(0, 3)) {
        this.log(`> warning: ${w}`);
      }
    };

    startGenerate = () => {
      this.stopRequested = false;
      this.generate.perform();
    };

    // graceful stop: the current vision round finishes (its result is kept
    // and archived), then the refine loop exits instead of starting another
    @tracked stopRequested = false;

    stopRefinement = () => {
      this.stopRequested = true;
      this.log('> stopping after this round…');
    };

    // every sculpture is its own studio card — starting a new one opens a
    // fresh instance in the stack instead of resetting this card's project
    newSculpture = () => {
      let realm = (this.args.model as any)?.[realmURL];
      this.args.createCard?.(studioRef, undefined, {
        realmURL: realm,
        // keep studio projects out of the workspace root grid, alongside
        // their round archives
        localDir: 'sculptures',
        cardModeAfterCreation: 'isolated',
      });
    };

    // Editable Output: the round on screen materializes as real code in the
    // realm — a standalone .js module (buildSculpture(THREE)) plus a
    // self-contained .html viewer whose URL works directly as an iframe src
    // anywhere on the web (the realm serves raw .html publicly).
    @tracked isExportingCode = false;

    exportCode = async () => {
      let model = this.args.model;
      let commandContext = this.args.context?.commandContext;
      let spec = model?.currentSpec;
      if (!model || !commandContext || !spec?.components?.length) return;
      this.isExportingCode = true;
      try {
        let showingLatest = this.currentRoundId === this.latestCreation?.id;
        let meta = showingLatest
          ? {
              round: this.latestCreation?.round ?? null,
              score: this.latestCreation?.score ?? null,
            }
          : {};
        let slug = slugify(spec.objectName || 'model', 'model');
        let realm = (model as any)[realmURL]?.href;
        let write = async (extension: string, content: string) => {
          let result = await new WriteTextFileCommand(commandContext).execute({
            path: `img-to-3d-generator/exports/${slug}.${extension}`,
            content,
            realm,
            useNonConflictingFilename: true,
          } as any);
          return (result as any)?.fileIdentifier as string;
        };
        await write('js', generateModelJs(spec, meta));
        let htmlUrl = await write('html', generateViewerHtml(spec, meta));
        let snippet = `<iframe src="${htmlUrl}" width="720" height="480" style="border:0"></iframe>`;
        try {
          await navigator.clipboard.writeText(snippet);
          this.log('> code exported ✓ iframe snippet copied');
        } catch {
          this.log('> code exported ✓');
        }
        this.log(`> viewer: ${htmlUrl}`);
      } catch (e) {
        this.errorMessage = `code export failed: ${(e as Error).message}`;
      } finally {
        this.isExportingCode = false;
      }
    };

    // Editable Output: alongside the always-editable spec/scene graph, the
    // build exports as a standard binary glTF for any DCC tool or engine
    downloadGlb = async () => {
      try {
        let buffer = await this.viewerApi?.exportGlb();
        if (!buffer) return;
        let name = slugify(
          this.args.model?.currentSpec?.objectName || 'model',
          'model',
        );
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
        let imageParts = allViews.map((url) => ({
          type: 'image_url',
          image_url: { url },
        }));

        // stage 1 — the AnalyzeReferenceCommand studies the object and
        // writes the build recipe. Running it as a command makes the plan
        // an inspectable, separately re-runnable artifact (and an AI tool).
        this.log('> analyzing object & planning parts…');
        let analysisResult = await new AnalyzeReferenceCommand(
          this.args.context!.commandContext!,
        ).execute({
          imageUrls: (model.references?.resolvedUrls ?? []).filter(Boolean),
          model: model.llmModel || VISION_MODEL,
        } as any);
        let analysis = JSON.parse(analysisResult.analysisJson);
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
        // persist the measured targets — refine rounds and later sessions
        // compare against these, not against memory
        model.analysis = JSON.stringify(analysis);

        // stage 2 — build the spec, honoring the stage-1 plan
        this.log('> authoring sculpt spec…');
        let parsed = await this.visionRequest(SPEC_SYSTEM_PROMPT, [
          {
            type: 'text',
            text:
              (allViews.length > 1
                ? `Rebuild the object shown in these ${allViews.length} views of the SAME object as a procedural sculpt spec. Reconcile all views — side/orthographic views define thickness and depth.`
                : 'Rebuild the object in this photo as a procedural sculpt spec.') +
              `\n\nANALYSIS (follow this plan):\n${JSON.stringify(analysis)}`,
          },
          ...imageParts,
        ]);
        // the analysis owns identity — its features gate the refine rounds
        if (analysis.identityFeatures.length) {
          parsed.identityFeatures = analysis.identityFeatures;
        }
        let outcome = await this.applyParsedSpec(parsed);
        let best = {
          score: outcome.score ?? -1,
          spec: this.args.model!.currentSpec,
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
              spec: this.args.model!.currentSpec,
            };
          }
        }

        // refine rounds can regress — end on the best-scoring round, not
        // merely the last one
        if (
          best.spec &&
          typeof outcome.score === 'number' &&
          best.score > outcome.score
        ) {
          this.args.model!.currentSpec = best.spec;
          await this.viewerApi?.rebuild();
          this.log(`> restored best round (score ${best.score})`);
        }

        this.phase = 'done';
        this.log('> rebuilt in code ✓');
      } catch (e: any) {
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
      let flat = this.args.model?.currentSpec?.inputKind === 'flat-graphic';
      let analysis: any;
      try {
        analysis = JSON.parse(this.args.model?.analysis || 'null');
      } catch {
        analysis = undefined;
      }
      let renders = flat
        ? [this.viewerApi?.captureScreenshot({ frontView: true })].filter(
            Boolean,
          )
        : (this.viewerApi?.captureViews(analysis?.camera) ?? []);
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
        serializeSpecForPrompt(this.args.model?.currentSpec),
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
        diff.changed.length === 0 &&
        diff.removedNodeIds.length === 0 &&
        diff.materialsChanged.length === 0;
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
        `> applying ${diff.changed.length} change(s), ${diff.removedNodeIds.length} removal(s)…`,
      );
      let merged = applySpecDiff(this.args.model?.currentSpec, diff);
      return await this.applyParsedSpec(merged);
    }

    async encodeReference(): Promise<string> {
      return fetchAsDataUrl(this.args.model?.references?.primaryUrl);
    }

    async encodeAllReferences(): Promise<string[]> {
      let urls = (this.args.model?.references?.resolvedUrls ?? []).filter(
        Boolean,
      );
      return Promise.all(
        urls.slice(0, 6).map((u: string) => fetchAsDataUrl(u)),
      );
    }

    async visionRequest(
      systemPrompt: string,
      userContent: any[],
      parser?: (raw: string) => any,
    ) {
      return requestSpec(
        this.args.context!.commandContext!,
        this.args.model?.llmModel || VISION_MODEL,
        systemPrompt,
        userContent,
        (line) => this.log(line),
        parser,
      );
    }

    async applyParsedSpec(
      parsed: any,
    ): Promise<{ score: number | undefined; featuresOk: boolean }> {
      let model = this.args.model!;
      let commandContext = this.args.context!.commandContext!;
      this.phase = 'building';
      this.log(`> building ${parsed.components.length} components…`);

      let spec = specFieldFromParsed(parsed);
      model.currentSpec = spec;
      // rebuild BEFORE archiving so the saved screenshot shows this round
      await this.viewerApi?.rebuild();

      // persist this round as its own SculptedModel card and link it,
      // carrying the same primary reference (ImageDef link for linked files,
      // url otherwise)
      let primary = model.references?.images?.[0];
      let referenceCopy =
        primary?.sourceMode === 'file' && primary?.file
          ? new ImageSourceField({
              file: primary.file,
              sourceMode: 'file',
            })
          : new ImageSourceField({
              url: primary?.resolvedUrl,
              sourceMode: 'url',
            });
      let previous = model.latestCreation;
      let round = (previous?.round ?? 0) + 1;
      let creation = new SculptedModel({
        referenceImage: referenceCopy,
        spec,
        critique: String(parsed.critique ?? ''),
        score: typeof parsed.score === 'number' ? parsed.score : null,
        renderScreenshot: await this.persistRenderScreenshot(
          parsed.objectName || 'model',
          round,
          parsed.inputKind === 'flat-graphic',
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
        // keep round archives out of the workspace root grid
        localDir: 'sculptures',
      } as any)) as SculptedModel;
      // SaveCard returns a detached, GC-eligible instance — re-resolve a
      // store-tracked one before linking it as latestCreation
      let store = (this.args.context as any)?.store;
      let tracked =
        saved?.id && store?.get ? await store.get(saved.id) : undefined;
      let creationCard =
        tracked && !(tracked as any).isCardError ? tracked : saved;
      model.latestCreation = creationCard;
      // a fresh save is always the round on screen
      this.shownRoundId = undefined;

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
    async persistRenderScreenshot(
      name: string,
      round: number,
      frontView: boolean,
    ): Promise<any> {
      try {
        let dataUrl = this.viewerApi?.captureScreenshot({ frontView });
        let base64 = dataUrl?.split(',')[1];
        if (!base64) return undefined;
        return await writeRealmImage(this.args.context!.commandContext!, {
          realm: (this.args.model as any)?.[realmURL]?.href,
          path: `img-to-3d-generator/renders/${slugify(name, 'model')}-round-${round}.webp`,
          base64,
          contentType: 'image/webp',
        });
      } catch {
        // archiving the screenshot is best-effort; the spec is still kept
        return undefined;
      }
    }

    <template>
      <article
        class='studio {{unless this.hasLinkedTheme "i3d-default-theme"}}'
      >
        <header class='studio-header'>
          <h1 class='studio-title'>◇ img-to-3d generator</h1>
          <div class='studio-header-right'>
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
              {{else if this.hasSpec}}
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
            </section>

            <button
              type='button'
              class='generate-btn'
              disabled={{this.isRunning}}
              {{on 'click' this.startGenerate}}
            >
              {{#if this.isRunning}}
                Working…
              {{else if this.hasSpec}}
                ⚡ Regenerate
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
                {{if this.stopRequested 'Stopping…' '⏹ Stop Refinement'}}
              </button>
            {{/if}}

            {{#if this.hasSpec}}
              <button
                type='button'
                class='export-btn'
                disabled={{this.isRunning}}
                {{on 'click' this.downloadGlb}}
              >
                ⬇ Export .glb
              </button>
              <button
                type='button'
                class='export-btn'
                disabled={{this.isExportingCode}}
                {{on 'click' this.exportCode}}
                title='Write this round as a three.js module + iframe-embeddable viewer page into the realm'
              >
                {{if this.isExportingCode 'Exporting…' '</> Export Code'}}
              </button>
            {{/if}}

            {{#if this.errorMessage}}
              <p class='error' role='alert'>{{this.errorMessage}}</p>
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
            <ModelViewer
              @spec={{@model.currentSpec}}
              @hint={{this.viewportHint}}
              @onReady={{this.onViewerReady}}
              @onWarnings={{this.onViewerWarnings}}
            />
          </main>
        </div>

        {{#if this.latestCreation}}
          {{#if this.historyQuery}}
            {{#if @context.searchResultsComponent}}
              <footer class='timeline' aria-label='Generation history'>
                <h2 class='timeline-label'>history</h2>
                {{! prerendered search entries — no SculptedModel is loaded
                    until a tile is clicked (showRound hydrates it) }}
                <@context.searchResultsComponent
                  @query={{this.historyQuery}}
                  @mode='none'
                  @overlays={{false}}
                  as |results|
                >
                  <ul class='history-strip'>
                    {{#each results.entries key='id' as |entry|}}
                      <li
                        class='history-tile
                          {{if (eq entry.id this.currentRoundId) "is-current"}}'
                      >
                        <button
                          type='button'
                          class='history-pick'
                          aria-label='Restore this round into the viewport'
                          {{on 'click' (fn this.showRound entry.id)}}
                        >
                          <entry.component />
                        </button>
                      </li>
                    {{/each}}
                  </ul>
                </@context.searchResultsComponent>
              </footer>
            {{/if}}
          {{/if}}
        {{/if}}

      </article>

      <style scoped>
        /* three-scope resolution: --i3d-* component knob → semantic theme
           token → deep-space literal. The --_* names are private aliases so
           the semantic --border token can flow through without a cycle. */
        .studio {
          --_bg: var(--i3d-bg, var(--background, #0a0b10));
          --_surface: var(--i3d-surface, var(--card, #14161e));
          --_glass: var(
            --i3d-glass,
            color-mix(in srgb, var(--card, #14161e) 75%, transparent)
          );
          --_border: var(--i3d-border, var(--border, #232838));
          --_text: var(--i3d-text, var(--foreground, #eef0f6));
          --_dim: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
          --_accent: var(--i3d-accent, var(--accent, #38e8ff));
          --_accent-fg: var(--i3d-accent-fg, var(--accent-foreground, #0a0b10));
          --_primary: var(--i3d-primary, var(--primary, #b98bff));
          --_primary-fg: var(
            --i3d-primary-fg,
            var(--primary-foreground, #0a0b10)
          );
          --_ring: var(--i3d-ring, var(--ring, #7c9fff));
          --_gold: var(--i3d-gold, #ffd76a);
          --_radius: var(--i3d-radius, var(--radius, 1rem));
          --_mono: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, 'SFMono-Regular', Menlo, monospace)
          );
          --_sans: var(
            --i3d-font-sans,
            var(
              --font-sans,
              -apple-system,
              BlinkMacSystemFont,
              'Segoe UI',
              Roboto,
              sans-serif
            )
          );

          display: flex;
          flex-direction: column;
          height: 100dvh;
          max-height: 100%;
          min-height: 0;
          background: var(--_bg);
          background-image:
            radial-gradient(
              1100px 500px at 85% -10%,
              color-mix(in srgb, var(--_accent) 7%, transparent),
              transparent 60%
            ),
            radial-gradient(
              900px 500px at 0% 0%,
              color-mix(in srgb, var(--_primary) 9%, transparent),
              transparent 55%
            );
          color: var(--_text);
          font-family: var(--_sans);
        }
        /* themeless default: pin the deep-space palette on the SEMANTIC
           tokens so app-level defaults can't leak in; a linked theme removes
           this class and takes over the same tokens */
        .i3d-default-theme {
          --background: #0a0b10;
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
          --font-mono:
            ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
          --font-sans:
            -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        .studio-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0.75rem 1.25rem;
          border-bottom: 1px solid var(--_border);
        }
        .studio-header-right {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }
        .new-sculpture-btn {
          padding: 0.25rem 0.625rem;
          border: 1px solid var(--_border);
          border-radius: 999px;
          background: var(--_surface);
          color: var(--_text);
          font-family: var(--_mono);
          font-size: 0.6875rem;
          cursor: pointer;
        }
        .new-sculpture-btn:hover {
          border-color: var(--_accent);
          color: var(--_accent);
        }
        .studio-title {
          margin: 0;
          font-family: var(--_mono);
          font-size: 0.875rem;
          font-weight: 600;
          letter-spacing: 0.06em;
        }
        .studio-status {
          margin: 0;
          font-family: var(--_mono);
          font-size: 0.6875rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--_accent);
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
          border: 1px solid var(--_border);
          border-radius: 1rem;
          background: var(--_glass);
          backdrop-filter: blur(10px);
          overflow-y: auto;
          z-index: 1;
        }
        .timeline-label {
          margin-top: 0.375rem;
          font-family: var(--_mono);
          font-size: 0.625rem;
          letter-spacing: 0.16em;
          text-transform: uppercase;
          color: var(--_dim);
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
          --img-source-bg: var(--_surface);
          --img-source-text: var(--_text);
          --img-source-text-dim: var(--_dim);
          --img-source-border: var(--_border);
          --img-source-accent: var(--_accent);
          --img-source-accent-fg: var(--_accent-fg);
          --boxel-light: var(--_surface);
          --boxel-100: color-mix(in srgb, var(--_surface) 92%, white);
          --boxel-400: var(--_dim);
          --boxel-500: var(--_dim);
          --boxel-700: var(--_text);
          --boxel-dark: var(--_text);
          --boxel-border-color: var(--_border);
          --boxel-purple: var(--_accent);
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
          background: linear-gradient(120deg, var(--_primary), var(--_accent));
          color: var(--_primary-fg);
          font-family: var(--_mono);
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
          border: 1px solid var(--_border);
          border-radius: 0.625rem;
          background: transparent;
          color: var(--_text);
          font-family: var(--_mono);
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
          font-family: var(--_mono);
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
        .export-btn:hover {
          border-color: var(--_accent);
          color: var(--_accent);
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
        .log {
          display: flex;
          flex-direction: column;
          gap: 0.2rem;
          font-family: var(--_mono);
          font-size: 0.6875rem;
          color: var(--_dim);
        }
        .log-line:last-child {
          color: var(--_accent);
        }
        .viewport {
          position: relative;
          min-height: 0;
          min-width: 0;
        }
        .timeline {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.5rem 1.25rem;
          border-top: 1px solid var(--_border);
        }
        .timeline-label {
          margin: 0;
        }
        /* prerendered round tiles — horizontal scroll, oldest → newest */
        .history-strip {
          display: flex;
          gap: 0.5rem;
          margin: 0;
          padding: 0;
          list-style: none;
          overflow-x: auto;
          min-width: 0;
          flex: 1;
        }
        .history-tile {
          flex: 0 0 auto;
          width: 8.5rem;
          height: 5rem;
        }
        .history-pick {
          display: block;
          width: 100%;
          height: 100%;
          padding: 0;
          border: 1px solid var(--_border);
          border-radius: 0.5rem;
          background: var(--_surface);
          overflow: hidden;
          cursor: pointer;
          container-name: fitted-card;
          container-type: size;
        }
        .history-pick:hover {
          border-color: var(--_accent);
        }
        /* the round currently in the viewport */
        .history-tile.is-current .history-pick {
          border-color: var(--_accent);
          box-shadow:
            0 0 0 2px var(--_accent),
            0 0 12px color-mix(in srgb, var(--_accent) 45%, transparent);
        }
        .history-pick > :deep(*) {
          width: 100%;
          height: 100%;
          pointer-events: none;
        }
        @container (max-width: 640px) {
          .studio-body {
            grid-template-columns: 1fr;
            grid-template-rows: auto 1fr;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof ImgTo3dStudio> {
    get componentCount() {
      return this.args.model?.currentSpec?.components?.length ?? 0;
    }
    get hasLinkedTheme() {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    <template>
      <article class='tile {{unless this.hasLinkedTheme "i3d-default-theme"}}'>
        <header class='tile-header'>
          <h3 class='tile-title'>{{@model.title}}</h3>
          <p class='tile-tag'>rebuilt in code</p>
        </header>
        {{#if @model.references.primaryUrl}}
          <img
            class='tile-image'
            src={{@model.references.primaryUrl}}
            alt='Reference for {{@model.title}}'
          />
        {{/if}}
        <p class='tile-meta'>{{this.componentCount}}
          parts ·
          {{@model.currentSpec.objectClass}}</p>
      </article>
      <style scoped>
        .tile {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          height: 100%;
          padding: 0.875rem;
          background: var(--i3d-bg, var(--background, #0a0b10));
          color: var(--i3d-text, var(--foreground, #eef0f6));
          font-family: var(
            --i3d-font-sans,
            var(
              --font-sans,
              -apple-system,
              BlinkMacSystemFont,
              'Segoe UI',
              Roboto,
              sans-serif
            )
          );
        }
        .tile-header {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 0.5rem;
        }
        .tile-title {
          margin: 0;
          font-size: 0.9375rem;
        }
        .tile-tag {
          margin: 0;
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.625rem;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: var(--i3d-accent, var(--accent, #38e8ff));
          white-space: nowrap;
        }
        .tile-image {
          flex: 1;
          min-height: 0;
          width: 100%;
          object-fit: cover;
          border-radius: 0.5rem;
          border: 1px solid var(--i3d-border, var(--border, #232838));
        }
        .tile-meta {
          margin: 0;
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.6875rem;
          color: var(--i3d-text-dim, var(--muted-foreground, #9aa0b2));
        }
        .i3d-default-theme {
          --background: #0a0b10;
          --foreground: #eef0f6;
          --muted-foreground: #9aa0b2;
          --accent: #38e8ff;
          --border: #232838;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof ImgTo3dStudio> {
    get hasLinkedTheme() {
      return Boolean(this.args.model?.cardInfo?.theme);
    }
    <template>
      <article class='fit {{unless this.hasLinkedTheme "i3d-default-theme"}}'>
        {{#if @model.references.primaryUrl}}
          <img class='fit-image' src={{@model.references.primaryUrl}} alt='' />
        {{/if}}
        <div class='fit-info'>
          <h3 class='fit-title'>{{@model.title}}</h3>
          <p class='fit-tag'>img → 3d</p>
        </div>
      </article>
      <style scoped>
        .fit {
          display: flex;
          align-items: flex-start;
          gap: 0.625rem;
          height: 100%;
          padding: 0.625rem;
          overflow: hidden;
          background: var(--i3d-bg, var(--background, #0a0b10));
          color: var(--i3d-text, var(--foreground, #eef0f6));
          font-family: var(
            --i3d-font-sans,
            var(
              --font-sans,
              -apple-system,
              BlinkMacSystemFont,
              'Segoe UI',
              Roboto,
              sans-serif
            )
          );
        }
        .fit-image {
          width: 3rem;
          height: 3rem;
          flex-shrink: 0;
          object-fit: cover;
          border-radius: 0.375rem;
          border: 1px solid var(--i3d-border, var(--border, #232838));
        }
        .fit-info {
          min-width: 0;
        }
        .fit-title {
          margin: 0;
          font-size: 0.8125rem;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-tag {
          margin: 0.125rem 0 0;
          font-family: var(
            --i3d-font-mono,
            var(--font-mono, ui-monospace, Menlo, monospace)
          );
          font-size: 0.625rem;
          letter-spacing: 0.12em;
          text-transform: uppercase;
          color: var(--i3d-accent, var(--accent, #38e8ff));
        }
        .i3d-default-theme {
          --background: #0a0b10;
          --foreground: #eef0f6;
          --accent: #38e8ff;
          --border: #232838;
        }
        @container fitted-card (height <= 80px) {
          .fit {
            align-items: center;
          }
          .fit-image {
            width: 2rem;
            height: 2rem;
          }
        }
      </style>
    </template>
  };
}
