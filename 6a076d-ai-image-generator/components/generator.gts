import { Component, realmURL } from '@cardstack/base/card-api';
import { BoxelInput, Button, Pill } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { task } from 'ember-concurrency';
import { modifier } from 'ember-modifier';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import SunIcon from '@cardstack/boxel-icons/sun';
import MoonIcon from '@cardstack/boxel-icons/moon';
import CopyIcon from '@cardstack/boxel-icons/copy';
import CopyCheckIcon from '@cardstack/boxel-icons/copy-check';
import CornerDownRightIcon from '@cardstack/boxel-icons/corner-down-right';
import LockIcon from '@cardstack/boxel-icons/lock';
import { GenerateAiImageCommand } from '../commands/generate-ai-image';
import GeneratingOverlay from './generating-overlay';
import type { AiImage } from '../ai-image';
import { modeLabel, formatTime, type AiImageMode } from '../ai-image';
import type { AiImageGenerator } from '../ai-image-generator';

// 1-based version label for a history entry, used as a template helper.
function versionLabel(index: number): number {
  return index + 1;
}

// Rewrite raw command/API failures into copy that owns the failure and gives
// the person one clear next step.
function friendlyError(raw: string | null | undefined): string {
  let msg = raw ?? '';
  if (/credit|payment|402/i.test(msg)) {
    return "You're out of AI credits — top up to keep creating.";
  }
  if (
    /\b404\b|no endpoints|not a valid model|no allowed providers/i.test(msg)
  ) {
    return "That model isn't available right now — switch to Nano Banana and try again.";
  }
  if (/forbidden|permission|403/i.test(msg)) {
    return "You don't have permission to save images here — open this generator in a workspace you can write to.";
  }
  if (/network|fetch|timeout/i.test(msg)) {
    return "We couldn't reach the image service. Check your connection and try again.";
  }
  return msg || "That one didn't come through — try generating again.";
}

// ---------------------------------------------------------------------------
// Isolated: a ChatGPT-style image chat. Each generation persists its result as
// its own AI Image card and links it into this generator's history. Any image
// can be reprompted or inpainted, producing a new card that links back to the
// one it was derived from.
// ---------------------------------------------------------------------------
export class AiImageGeneratorIsolated extends Component<
  typeof AiImageGenerator
> {
  // Pre-fill the composer with the recommended defaults so a fresh generator
  // shows the default model and a square 1:1 framing already selected instead
  // of an empty "Choose…"; existing cards keep whatever they already have.
  // Runs as a modifier (after the render pass) rather than in the constructor,
  // so we never mutate model state while the component is being rendered — an
  // in-render mutation trips Glimmer's tracked-value-reentered-computation
  // assertion.
  seedDefaults = modifier(() => {
    let model = this.args.model;
    if (!model) return;
    if (!model.llmModel) {
      model.llmModel = 'google/gemini-2.5-flash-image';
    }
    if (!model.aspectRatio) {
      model.aspectRatio = '1:1';
    }
  });

  // Main composer. Like ChatGPT, follow-up prompts continue from the latest
  // image by default; "New image" switches to generating from scratch.
  @tracked promptText = '';
  @tracked continueFromLatest = true;
  @tracked errorMessage: string | null = null;
  // The prompt of the generation in flight from the bottom composer. Set when
  // a generation starts (and the input is cleared), so the prompt shows only
  // once — on the skeleton — not doubled in the composer too.
  @tracked pendingPrompt = '';

  // In-card light/dark control. Stamped as `data-theme` on the card root; since
  // `--boxel-color-scheme` is an inherited signal and the theme tokens are
  // scoped, flipping it re-themes ONLY this card (a linked Theme's `.dark`
  // block responds too via the CardContainer pipeline). Defaults to the
  // studio-dark brand look.
  @tracked colorScheme: 'light' | 'dark' = 'dark';

  @action toggleColorScheme() {
    this.colorScheme = this.colorScheme === 'dark' ? 'light' : 'dark';
  }

  // Focused editing session: opened by clicking Refine on a history image. It
  // targets one existing image and iterates on it via Reprompt or Paint.
  @tracked editTarget: AiImage | null = null;
  @tracked editMode: 'reprompt' | 'paint' = 'reprompt';
  @tracked editPrompt = '';
  @tracked maskDataUrl: string | null = null;

  private maskCanvas: HTMLCanvasElement | null = null;

  // The history cards themselves. Returning the linked cards (without reading
  // into their fields here) keeps this getter cheap and side-effect free — the
  // template dereferences each card's fields reactively.
  get items(): AiImage[] {
    return (this.args.model?.history ?? []) as AiImage[];
  }

  get realmUrl(): string {
    let url = (this.args.model as any)?.[realmURL];
    return url ? url.href : '';
  }

  // With no linked theme, pin the studio-dark default palette; a linked theme
  // takes over the semantic tokens entirely.
  get hasLinkedTheme(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  get commandContext() {
    return (this.args as any).context?.commandContext;
  }

  get isBusy(): boolean {
    return this.generate.isRunning || this.editGenerate.isRunning;
  }

  get isEditing(): boolean {
    return this.editTarget != null;
  }

  // Prompt driving whatever generation is currently in flight, shown on the
  // skeleton placeholder while the image is being produced.
  get activePrompt(): string {
    return (this.isEditing ? this.editPrompt : this.pendingPrompt).trim();
  }

  get lastIndex(): number {
    return this.items.length - 1;
  }

  // Lineage caption for a refined turn, naming the actual parent version
  // (e.g. "refined from v3") so the relationship is explicit in words, with the
  // version tree carrying the visual story.
  parentLineage = (entry: AiImage): string => {
    let pid = (entry as any)?.parent?.id;
    let idx = pid ? this.items.findIndex((it) => (it as any)?.id === pid) : -1;
    return idx >= 0
      ? `refined from v${idx + 1}`
      : 'refined from an earlier version';
  };

  // The image a bottom-composer prompt will iterate on (GPT-style memory).
  get continueTarget(): AiImage | undefined {
    if (!this.continueFromLatest) return undefined;
    let latest = this.items[this.items.length - 1];
    return latest?.image?.url ? latest : undefined;
  }

  @action setContinue(value: boolean) {
    this.continueFromLatest = value;
  }

  // Stop an in-flight generation, ChatGPT-style. Cancelling the ember-concurrency
  // task abandons the awaited command, so its result is dropped (never appended
  // to history) and the UI returns to idle.
  @action stopGenerating() {
    this.generate.cancelAll();
    this.editGenerate.cancelAll();
    if (this.pendingPrompt) {
      this.promptText = this.pendingPrompt;
      this.pendingPrompt = '';
    }
  }

  // ----- version-tree hover preview -----------------------------------------
  // Hovering (or tapping/focusing) a version node opens a floating preview with
  // the full image and a Refine button, instead of a click jumping straight
  // into the editor. The popover is position:fixed so it escapes the sidebar's
  // scroll clip; a short close delay lets the pointer travel into it.
  @tracked previewNode: { entry: AiImage; version: number } | null = null;
  @tracked previewStyle: ReturnType<typeof htmlSafe> = htmlSafe('');
  private previewHideTimer: ReturnType<typeof setTimeout> | null = null;

  @action showVersionPreview(
    node: { entry: AiImage; version: number },
    event: Event,
  ) {
    if (this.previewHideTimer) {
      clearTimeout(this.previewHideTimer);
      this.previewHideTimer = null;
    }
    let el = event.currentTarget as HTMLElement;
    // The popover is `position: absolute` inside the card root (which is
    // `position: relative`), so we compute coordinates relative to that root
    // rather than the viewport. This keeps the popover inside the card's
    // bounding box while still escaping the sidebar's overflow clip.
    let card = el.closest('.ai-image') as HTMLElement | null;
    let cardRect = card?.getBoundingClientRect();
    let r = el.getBoundingClientRect();
    let width = 232;
    // Convert viewport coords → card-relative coords.
    let cardLeft = cardRect?.left ?? 0;
    let cardTop = cardRect?.top ?? 0;
    let cardWidth = cardRect?.width ?? window.innerWidth;
    let cardHeight = cardRect?.height ?? window.innerHeight;
    // Prefer the right of the row; flip left if it would overflow the card.
    let left = r.right - cardLeft + 8;
    if (left + width > cardWidth - 8) {
      left = Math.max(8, r.left - cardLeft - width - 8);
    }
    let top = Math.min(r.top - cardTop, cardHeight - 260);
    this.previewStyle = htmlSafe(
      `top: ${Math.max(8, top)}px; left: ${left}px; width: ${width}px;`,
    );
    this.previewNode = { entry: node.entry, version: node.version };
  }

  @action keepPreview() {
    if (this.previewHideTimer) {
      clearTimeout(this.previewHideTimer);
      this.previewHideTimer = null;
    }
  }

  @action scheduleHidePreview() {
    if (this.previewHideTimer) clearTimeout(this.previewHideTimer);
    this.previewHideTimer = setTimeout(() => {
      this.previewNode = null;
      this.previewHideTimer = null;
    }, 160);
  }

  @action refineFromPreview(img: AiImage) {
    this.keepPreview();
    this.previewNode = null;
    this.openEdit(img);
  }

  // Scroll the main thread to a version's turn and close the preview.
  @action jumpToVersion(version: number) {
    let el = document.querySelector(`[data-ai-turn='${version}']`);
    if (el) {
      let reduce = window.matchMedia?.(
        '(prefers-reduced-motion: reduce)',
      )?.matches;
      el.scrollIntoView({
        behavior: reduce ? 'auto' : 'smooth',
        block: 'center',
      });
    }
    this.previewNode = null;
  }

  @tracked copiedVersion: number | null = null;
  private copiedTimer: ReturnType<typeof setTimeout> | null = null;

  @action async copyPrompt(version: number, prompt: string) {
    try {
      await navigator.clipboard.writeText(prompt ?? '');
      if (this.copiedTimer) clearTimeout(this.copiedTimer);
      this.copiedVersion = version;
      this.copiedTimer = setTimeout(() => {
        this.copiedVersion = null;
        this.copiedTimer = null;
      }, 1500);
    } catch {
      // clipboard unavailable — nothing to recover, the prompt is still shown
    }
  }

  // A rigorous GitHub-network-style version graph. Nodes are laid out in
  // depth-first pre-order (so each branch's subtree is contiguous), a node's
  // lane is its depth, and edges are continuous orthogonal rails drawn from
  // each node down to its ACTUAL parent's lane — not merely implied by indent.
  // DFS ordering guarantees a branch only occupies its lane within its own
  // contiguous block, so lanes never collide. Reading `.id` / the already-
  // loaded `parent` link mirrors the thread template's dereference, staying
  // clear of the linksTo-in-getter backtracking hazard.
  get versionGraph(): {
    nodes: Array<{
      entry: AiImage;
      version: number;
      lane: number;
      isLatest: boolean;
      isRoot: boolean;
      isBranchPoint: boolean;
      rowStyle: ReturnType<typeof htmlSafe>;
      dotStyle: ReturnType<typeof htmlSafe>;
    }>;
    edges: Array<{ d: string; branch: boolean }>;
    style: ReturnType<typeof htmlSafe>;
    width: number;
    height: number;
  } {
    const ROW = 46; // px per row
    const LANE = 14; // px per lane
    const PAD = 12; // px left inset to first dot
    // Cap the graph gutter to a few lanes (GitLens-style): deep branches reuse
    // the last lane visually so the gutter stays narrow and the thumbnail +
    // label after it are always visible, never pushed off-screen.
    const MAX_LANE = 3;
    let items = this.items;

    let indexById = new Map<string, number>();
    items.forEach((it, i) => {
      let id = (it as any)?.id;
      if (id) indexById.set(id, i);
    });
    let parentIndex = items.map((it) => {
      let pid = (it as any)?.parent?.id;
      let pi = pid != null ? indexById.get(pid) : undefined;
      return pi === undefined ? -1 : pi;
    });
    let children: number[][] = items.map(() => []);
    parentIndex.forEach((pi, i) => {
      if (pi >= 0) children[pi].push(i);
    });

    // Rows follow creation order (same as the thread) so version numbers read
    // v1→vN straight down — never reshuffled.
    let order = items.map((_, i) => i);
    let rowOf = new Array(items.length).fill(0);
    order.forEach((idx, row) => (rowOf[idx] = row));

    // Git-graph lane allocation (GitLens-style): each independent lineage owns
    // its own column. A NEW image (no parent = a fresh root) claims a new lane,
    // a parent's FIRST child continues its lane, and any additional child
    // branches into a new lane. So a new image reads as its own vertical track
    // rather than glued onto the previous trunk. `laneTip[l]` = the node id that
    // currently occupies lane l (its next inheriting child extends it).
    let lane = new Array(items.length).fill(0);
    let laneTip: (number | null)[] = [];
    let claimLane = (i: number) => {
      let l = laneTip.indexOf(null);
      if (l < 0) {
        l = laneTip.length;
        laneTip.push(null);
      }
      laneTip[l] = i;
      return l;
    };
    for (let i = 0; i < items.length; i++) {
      let pi = parentIndex[i];
      if (pi < 0) {
        lane[i] = claimLane(i); // new image → its own lane
      } else if (laneTip[lane[pi]] === pi) {
        lane[i] = lane[pi]; // first child continues the parent's lane
        laneTip[lane[pi]] = i;
      } else {
        lane[i] = claimLane(i); // later child → branches into a new lane
      }
    }

    let laneOf = (i: number) => Math.min(lane[i], MAX_LANE);
    let dotX = (i: number) => PAD + laneOf(i) * LANE;
    let dotY = (i: number) => rowOf[i] * ROW + ROW / 2;
    let maxLane = Math.min(laneTip.length - 1, MAX_LANE);
    let railW = PAD + maxLane * LANE + PAD;

    let edges = items
      .map((_, i) => {
        let pi = parentIndex[i];
        if (pi < 0) return null;
        let px = dotX(pi),
          py = dotY(pi),
          cx = dotX(i),
          cy = dotY(i);
        let branch = children[pi].length > 1;
        let d =
          px === cx
            ? `M ${px} ${py} L ${cx} ${cy}`
            : // down the parent's lane, round the corner, into the child's lane
              `M ${px} ${py} L ${px} ${cy - 8} Q ${px} ${cy} ${px + 8} ${cy} L ${cx} ${cy}`;
        return { d, branch };
      })
      .filter(Boolean) as Array<{ d: string; branch: boolean }>;

    let nodes = order.map((idx, row) => ({
      entry: items[idx],
      version: idx + 1,
      lane: lane[idx],
      isLatest: idx === items.length - 1,
      isRoot: parentIndex[idx] < 0,
      isBranchPoint: children[idx].length > 1,
      rowStyle: htmlSafe(`top: ${row * ROW}px; height: ${ROW}px;`),
      dotStyle: htmlSafe(`left: ${dotX(idx) - 5}px;`),
    }));

    return {
      nodes,
      edges,
      style: htmlSafe(`--rail-w: ${railW}px; height: ${order.length * ROW}px;`),
      width: railW,
      height: order.length * ROW,
    };
  }

  // The in-flight skeleton takes the shape of the image being made, so the
  // wait sets the right expectation instead of shifting layout on arrival.
  get skeletonAspect(): ReturnType<typeof htmlSafe> {
    let ratio = this.args.model?.aspectRatio || '1:1';
    let [w, h] = ratio.split(':').map(Number);
    if (!w || !h) [w, h] = [16, 9];
    return htmlSafe(`aspect-ratio: ${w} / ${h};`);
  }

  // The refine modal's stage takes the shape of the image on screen, so the
  // generating overlay and the result share one height — no jump between the
  // wait and the arrival.
  get editStageAspect(): ReturnType<typeof htmlSafe> {
    let ratio = this.editTarget?.aspectRatio || '1:1';
    let [w, h] = ratio.split(':').map(Number);
    if (!w || !h) [w, h] = [1, 1];
    return htmlSafe(`aspect-ratio: ${w} / ${h};`);
  }

  // Keep the newest turn (or the in-flight skeleton) in view as the thread
  // grows, like a chat following its own conversation.
  scrollToLatest = modifier((el: HTMLElement, [isLatest]: [boolean]) => {
    if (isLatest) {
      let reduceMotion = window.matchMedia?.(
        '(prefers-reduced-motion: reduce)',
      )?.matches;
      el.scrollIntoView({
        behavior: reduceMotion ? 'auto' : 'smooth',
        block: 'end',
      });
    }
  });

  examplePrompts = [
    'a watercolor fox in a misty forest',
    'isometric cozy coffee shop, soft pastel lighting',
    'a retro-futuristic city skyline at golden hour',
    'minimal line-art logo of a mountain, single color',
  ];

  @action updatePrompt(value: string) {
    this.promptText = value;
  }

  @action useExample(prompt: string) {
    this.promptText = prompt;
  }

  @action onPromptKeydown(event: Event) {
    let e = event as KeyboardEvent;
    // Cmd/Ctrl+Enter submits, matching common chat composers.
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      e.preventDefault();
      if (!this.isBusy) this.generate.perform();
    }
  }

  // ----- focused editing session --------------------------------------------
  @action openEdit(img: AiImage) {
    if (!img.image?.url) return;
    this.editTarget = img;
    this.editMode = 'reprompt';
    this.editPrompt = '';
    this.maskDataUrl = null;
    this.maskCanvas = null;
    this.errorMessage = null;
  }

  @action closeEdit() {
    this.editTarget = null;
    this.editPrompt = '';
    this.maskDataUrl = null;
    this.maskCanvas = null;
  }

  @action setEditMode(mode: 'reprompt' | 'paint') {
    this.editMode = mode;
    if (mode === 'reprompt') {
      this.maskDataUrl = null;
      this.maskCanvas = null;
    }
  }

  @action updateEditPrompt(value: string) {
    this.editPrompt = value;
  }

  @action onEditPromptKeydown(event: Event) {
    let e = event as KeyboardEvent;
    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      e.preventDefault();
      if (!this.isBusy) this.editGenerate.perform();
    }
  }

  // Wire up a brush-mask canvas: the source image is drawn for reference and an
  // offscreen mask (black = keep, white = repaint) tracks the painted strokes.
  setupCanvas = modifier((el: HTMLCanvasElement) => {
    let display = el;
    let src = this.editTarget?.image?.url ?? null;
    if (!src) return;

    let img = new Image();
    img.crossOrigin = 'anonymous';
    let mask = document.createElement('canvas');
    this.maskCanvas = mask;

    let painting = false;

    let paint = (ev: PointerEvent) => {
      if (!painting) return;
      let rect = display.getBoundingClientRect();
      let sx = display.width / rect.width;
      let sy = display.height / rect.height;
      let x = (ev.clientX - rect.left) * sx;
      let y = (ev.clientY - rect.top) * sy;
      let r = Math.max(12, display.width * 0.04);

      let dctx = display.getContext('2d');
      if (dctx) {
        dctx.fillStyle = 'rgba(255,80,80,0.55)';
        dctx.beginPath();
        dctx.arc(x, y, r, 0, Math.PI * 2);
        dctx.fill();
      }
      let mctx = mask.getContext('2d');
      if (mctx) {
        mctx.fillStyle = '#ffffff';
        mctx.beginPath();
        mctx.arc(x, y, r, 0, Math.PI * 2);
        mctx.fill();
      }
    };

    let down = (ev: PointerEvent) => {
      painting = true;
      paint(ev);
    };
    let up = () => {
      painting = false;
    };

    img.onload = () => {
      let w = img.naturalWidth || 512;
      let h = img.naturalHeight || 512;
      display.width = w;
      display.height = h;
      mask.width = w;
      mask.height = h;
      let dctx = display.getContext('2d');
      if (dctx) dctx.drawImage(img, 0, 0, w, h);
      let mctx = mask.getContext('2d');
      if (mctx) {
        mctx.fillStyle = '#000000';
        mctx.fillRect(0, 0, w, h);
      }
    };
    img.src = src;

    display.addEventListener('pointerdown', down);
    display.addEventListener('pointermove', paint);
    window.addEventListener('pointerup', up);

    return () => {
      display.removeEventListener('pointerdown', down);
      display.removeEventListener('pointermove', paint);
      window.removeEventListener('pointerup', up);
    };
  });

  // Shared pipeline for every generation mode. GenerateAiImageCommand owns the
  // whole record: it runs the engine, persists the mask, and saves the result
  // as its own AI Image card with full provenance — this component only links
  // the returned card into the history. Returns the saved card, or null.
  private async runGeneration(opts: {
    prompt: string;
    mode: AiImageMode;
    maskDataUrl: string;
    parent?: AiImage;
    failureMessage?: string;
  }): Promise<AiImage | null> {
    let commandContext = this.commandContext;
    if (!commandContext) {
      this.errorMessage = 'No command context available.';
      return null;
    }
    if (!this.realmUrl) {
      this.errorMessage = 'Save the generator to a realm first.';
      return null;
    }
    this.errorMessage = null;

    try {
      let result = await new GenerateAiImageCommand(commandContext).execute({
        prompt: opts.prompt,
        mode: opts.mode,
        parent: opts.parent,
        maskDataUrl: opts.maskDataUrl,
        targetRealmIdentifier: this.realmUrl,
        targetPath: 'generated',
        model: this.args.model?.llmModel ?? '',
        // Inpaint must keep the source image's exact framing or the repaint
        // won't line up with the mask, so it inherits the parent's ratio. A
        // reprompt (or a brand-new image) regenerates freely, so it honours the
        // picked ratio. Falls back to a square 1:1.
        aspectRatio:
          opts.mode === 'inpaint'
            ? opts.parent?.aspectRatio || '1:1'
            : this.args.model?.aspectRatio || '1:1',
      } as any);

      let saved = result?.aiImage as AiImage | undefined;
      if (!saved) throw new Error('No image returned.');

      this.args.model.history = [...this.items, saved];
      return saved;
    } catch (e: any) {
      this.errorMessage = friendlyError(e?.message ?? opts.failureMessage);
      return null;
    }
  }

  // ----- generation (bottom composer) ----------------------------------------
  // Continues from the latest image when "Continue" mode is on, so the thread
  // remembers its own history the way a ChatGPT conversation does.
  generate = task(async () => {
    let prompt = this.promptText.trim();
    if (!prompt) return;
    let parent = this.continueTarget;
    // Clear the input immediately (chat-style) so the prompt shows only on the
    // skeleton; restore it if the generation fails so nothing is lost.
    this.pendingPrompt = prompt;
    this.promptText = '';
    let saved = await this.runGeneration({
      prompt,
      mode: parent ? 'edit' : 'generate',
      maskDataUrl: '',
      parent,
    });
    if (!saved) this.promptText = prompt;
    this.pendingPrompt = '';
  });

  // ----- edit (reprompt / paint an existing image) --------------------------
  editGenerate = task(async () => {
    let target = this.editTarget;
    let prompt = this.editPrompt.trim();
    if (!target || !target.image?.url || !prompt) return;

    // In paint mode, snapshot the offscreen mask (black = keep, white = repaint).
    let mask = '';
    if (this.editMode === 'paint') {
      if (!this.maskCanvas) {
        this.errorMessage = 'Paint a region to change first.';
        return;
      }
      mask = this.maskCanvas.toDataURL('image/png');
      this.maskDataUrl = mask;
    }

    let mode: AiImageMode = this.editMode === 'paint' ? 'inpaint' : 'edit';

    // The parent's image is the edit source — the command derives the
    // engine's source list from it.
    let saved = await this.runGeneration({
      prompt,
      mode,
      maskDataUrl: mask,
      parent: target,
      failureMessage: 'Edit failed.',
    });
    // Stay in the editor showing the new result, so the person can compare
    // and keep refining without reopening the popover.
    if (saved) {
      this.editTarget = saved;
      this.editPrompt = '';
      this.maskDataUrl = null;
      this.maskCanvas = null;
    }
  });

  <template>
    <div
      class='ai-image {{unless this.hasLinkedTheme "ai-image-default-theme"}}'
      data-theme={{this.colorScheme}}
      {{this.seedDefaults}}
    >
      <header class='header'>
        <SparklesIcon class='header-icon' />
        <h1>{{if @model.cardTitle @model.cardTitle 'AI Image Generator'}}</h1>
        <button
          type='button'
          class='scheme-toggle'
          {{on 'click' this.toggleColorScheme}}
          aria-label={{if
            (eq this.colorScheme 'dark')
            'Switch to light mode'
            'Switch to dark mode'
          }}
          title={{if
            (eq this.colorScheme 'dark')
            'Switch to light mode'
            'Switch to dark mode'
          }}
        >
          {{#if (eq this.colorScheme 'dark')}}
            <SunIcon />
          {{else}}
            <MoonIcon />
          {{/if}}
        </button>
      </header>

      <div class='body'>
        <aside class='sidebar'>
          <label class='setting'>
            <span class='setting-label'>Model</span>
            <@fields.llmModel @format='edit' />
          </label>
          <label class='setting'>
            <span class='setting-label'>Aspect ratio</span>
            <@fields.aspectRatio @format='edit' />
          </label>

          {{#if this.versionGraph.nodes.length}}
            <div class='versions'>
              <span class='setting-label'>Versions</span>
              <div class='version-graph'>
                <div class='version-canvas' style={{this.versionGraph.style}}>
                  <svg
                    class='version-rails'
                    width={{this.versionGraph.width}}
                    height={{this.versionGraph.height}}
                    aria-hidden='true'
                  >
                    {{#each this.versionGraph.edges as |edge|}}
                      <path
                        class='rail {{if edge.branch "rail-branch"}}'
                        d={{edge.d}}
                        fill='none'
                      />
                    {{/each}}
                  </svg>
                  {{#each this.versionGraph.nodes as |node|}}
                    <button
                      type='button'
                      class='version-btn
                        {{if node.isLatest "current"}}
                        {{if node.isRoot "root"}}
                        {{if node.isBranchPoint "branch"}}'
                      style={{node.rowStyle}}
                      title={{node.entry.prompt}}
                      {{on 'mouseenter' (fn this.showVersionPreview node)}}
                      {{on 'focus' (fn this.showVersionPreview node)}}
                      {{on 'click' (fn this.showVersionPreview node)}}
                      {{on 'mouseleave' this.scheduleHidePreview}}
                      {{on 'blur' this.scheduleHidePreview}}
                      data-test-ai-image-version={{node.version}}
                    >
                      <span class='version-dot' style={{node.dotStyle}}></span>
                      {{#if node.entry.image.url}}
                        <img
                          class='version-thumb'
                          src={{node.entry.image.url}}
                          alt=''
                          loading='lazy'
                        />
                      {{/if}}
                      <span class='version-info'>
                        <span class='version-tag'>v{{node.version}}</span>
                        <span
                          class='version-prompt'
                        >{{node.entry.prompt}}</span>
                      </span>
                    </button>
                  {{/each}}
                </div>
              </div>
            </div>
          {{/if}}
        </aside>

        <section class='main'>
          <div class='thread'>
            {{#each @model.history as |entry index|}}
              <article
                class='turn'
                data-ai-turn={{versionLabel index}}
                {{this.scrollToLatest (eq index this.lastIndex)}}
              >
                <div class='turn-meta'>
                  <span class='version'>v{{versionLabel index}}</span>
                  {{#unless (eq entry.mode 'generate')}}
                    <span class='badge badge-{{entry.mode}}'>{{modeLabel
                        entry.mode
                      }}</span>
                  {{/unless}}
                  {{#if entry.parent}}
                    <span class='lineage'>{{this.parentLineage entry}}</span>
                  {{/if}}
                  {{#if entry.createdAt}}
                    <time class='when'>{{formatTime entry.createdAt}}</time>
                  {{/if}}
                </div>
                <div class='turn-prompt-row'>
                  <p class='turn-prompt'>{{entry.prompt}}</p>
                  {{#if entry.prompt}}
                    <button
                      type='button'
                      class='pop-icon turn-copy'
                      aria-label='Copy prompt'
                      title={{if
                        (eq this.copiedVersion (versionLabel index))
                        'Copied'
                        'Copy prompt'
                      }}
                      {{on
                        'click'
                        (fn this.copyPrompt (versionLabel index) entry.prompt)
                      }}
                    >
                      {{#if (eq this.copiedVersion (versionLabel index))}}
                        <CopyCheckIcon />
                      {{else}}
                        <CopyIcon />
                      {{/if}}
                    </button>
                  {{/if}}
                </div>
                {{#if entry.image.url}}
                  <div class='turn-media'>
                    <img
                      class='turn-image'
                      src={{entry.image.url}}
                      alt={{entry.prompt}}
                      loading='lazy'
                      data-test-ai-image-turn={{index}}
                    />
                    <div class='turn-actions'>
                      <Button
                        @kind='primary'
                        @size='small'
                        {{on 'click' (fn this.openEdit entry)}}
                        data-test-ai-image-edit={{index}}
                      >Refine</Button>
                      <a
                        class='download'
                        href={{entry.image.url}}
                        download
                        target='_blank'
                        rel='noopener noreferrer'
                      >Download</a>
                    </div>
                  </div>
                {{/if}}
              </article>
            {{else}}
              {{#unless this.isBusy}}
                <div class='empty'>
                  <div class='empty-badge'><SparklesIcon /></div>
                  <h2>Create your first image</h2>
                  <p>Describe what you want to see, pick a model and aspect
                    ratio, then generate. Try one of these:</p>
                  <div class='examples'>
                    {{#each this.examplePrompts as |example|}}
                      <Pill
                        @kind='button'
                        class='example-chip'
                        {{on 'click' (fn this.useExample example)}}
                      >{{example}}</Pill>
                    {{/each}}
                  </div>
                </div>
              {{/unless}}
            {{/each}}

            {{#if this.isBusy}}
              <article
                class='turn'
                data-test-ai-image-generating
                {{this.scrollToLatest true}}
              >
                {{#if this.activePrompt}}
                  <p class='turn-prompt'>{{this.activePrompt}}</p>
                {{/if}}
                <div class='turn-skeleton' style={{this.skeletonAspect}}>
                  <GeneratingOverlay>
                    <div class='gen-center'>
                      <div class='gen-badge'><SparklesIcon /></div>
                      <span class='gen-title'>Generating your image</span>
                      <span class='gen-sub'>Painting pixels — this usually takes
                        a few seconds</span>
                      <div class='gen-dots' aria-hidden='true'>
                        <span></span><span></span><span></span>
                      </div>
                    </div>
                  </GeneratingOverlay>
                </div>
              </article>
            {{/if}}
          </div>

          <div class='composer-dock' data-test-ai-image-composer>
            {{#unless this.isEditing}}
              {{#if this.errorMessage}}
                <p
                  class='error'
                  data-test-ai-image-error
                >{{this.errorMessage}}</p>
              {{/if}}
            {{/unless}}
            <div class='composer-card'>
              {{#if this.items.length}}
                <div class='composer-mode'>
                  <button
                    type='button'
                    class='mode-chip {{if this.continueFromLatest "active"}}'
                    {{on 'click' (fn this.setContinue true)}}
                    data-test-ai-image-mode-continue
                  >Continue from v{{this.items.length}}</button>
                  <button
                    type='button'
                    class='mode-chip
                      {{unless this.continueFromLatest "active"}}'
                    {{on 'click' (fn this.setContinue false)}}
                    data-test-ai-image-mode-new
                  >New image</button>
                </div>
              {{/if}}
              <div class='composer-main'>
                <BoxelInput
                  @type='textarea'
                  @value={{this.promptText}}
                  @onInput={{this.updatePrompt}}
                  @placeholder={{if
                    this.continueTarget
                    'Describe the change to make… (⌘/Ctrl + Enter)'
                    'Describe an image… (⌘/Ctrl + Enter to generate)'
                  }}
                  class='prompt-input'
                  aria-label='Image prompt'
                  data-test-ai-image-prompt
                  {{on 'keydown' this.onPromptKeydown}}
                />
                {{#if this.isBusy}}
                  <button
                    type='button'
                    class='stop-btn'
                    aria-label='Stop generating'
                    {{on 'click' this.stopGenerating}}
                    data-test-ai-image-stop
                  >
                    <span class='stop-glyph' aria-hidden='true'></span>
                  </button>
                {{else}}
                  <Button
                    @kind='primary'
                    {{on 'click' this.generate.perform}}
                    data-test-ai-image-generate
                  >
                    Generate
                  </Button>
                {{/if}}
              </div>
            </div>
          </div>
        </section>
      </div>

      {{#if this.isEditing}}
        <div class='edit-overlay'>
          <div
            class='edit-modal'
            role='dialog'
            aria-modal='true'
            aria-labelledby='ai-image-refine-title'
          >
            <header class='edit-head'>
              <h2 id='ai-image-refine-title'>Refine image</h2>
              <button
                type='button'
                class='chip-close'
                aria-label='Close editor'
                {{on 'click' this.closeEdit}}
              >×</button>
            </header>

            <section class='edit-body'>
              <div class='edit-tabs' role='tablist'>
                <button
                  type='button'
                  class='tab {{if (eq this.editMode "reprompt") "active"}}'
                  {{on 'click' (fn this.setEditMode 'reprompt')}}
                  data-test-ai-image-edit-reprompt
                >Reprompt</button>
                <button
                  type='button'
                  class='tab {{if (eq this.editMode "paint") "active"}}'
                  {{on 'click' (fn this.setEditMode 'paint')}}
                  data-test-ai-image-edit-paint
                >Paint area</button>
              </div>

              {{! Reprompt can reframe (it regenerates); inpaint is locked to the
              source framing so the repaint aligns with the mask. }}
              <div class='edit-setting'>
                <span class='setting-label'>Aspect ratio</span>
                {{#if (eq this.editMode 'reprompt')}}
                  <@fields.aspectRatio @format='edit' />
                {{else}}
                  <div
                    class='aspect-locked'
                    title='Inpaint keeps the source image’s framing so the repaint lines up with your mask. Switch to Reprompt to change the aspect ratio.'
                    data-test-ai-image-aspect-locked
                  >
                    <span class='aspect-locked-value'>{{if
                        this.editTarget.aspectRatio
                        this.editTarget.aspectRatio
                        '1:1'
                      }}</span>
                    <LockIcon class='aspect-locked-icon' />
                  </div>
                {{/if}}
              </div>

              <div class='edit-stage' style={{this.editStageAspect}}>
                {{#if this.editGenerate.isRunning}}
                  <div class='edit-generating'>
                    <GeneratingOverlay>
                      <div class='gen-center'>
                        <div class='gen-badge'><SparklesIcon /></div>
                        <span class='gen-title'>Refining your image</span>
                        <span class='gen-sub'>Applying your changes — this
                          usually takes a few seconds</span>
                        <div class='gen-dots' aria-hidden='true'>
                          <span></span><span></span><span></span>
                        </div>
                      </div>
                    </GeneratingOverlay>
                  </div>
                {{else if (eq this.editMode 'paint')}}
                  <canvas class='mask-canvas' {{this.setupCanvas}}></canvas>
                {{else}}
                  <img
                    class='edit-image'
                    src={{this.editTarget.image.url}}
                    alt='editing'
                  />
                {{/if}}
              </div>

              {{! Provenance of the image being refined, for reference. }}
              <dl class='edit-record'>
                <div class='rec'>
                  <dt>Prompt</dt>
                  <dd>{{if
                      this.editTarget.prompt
                      this.editTarget.prompt
                      '—'
                    }}</dd>
                </div>
                <div class='rec'>
                  <dt>Mode</dt>
                  <dd>{{modeLabel this.editTarget.mode}}</dd>
                </div>
                <div class='rec'>
                  <dt>Model</dt>
                  <dd>{{if
                      this.editTarget.llmModel
                      this.editTarget.llmModel
                      '—'
                    }}</dd>
                </div>
                <div class='rec'>
                  <dt>Aspect</dt>
                  <dd>{{if
                      this.editTarget.aspectRatio
                      this.editTarget.aspectRatio
                      '—'
                    }}</dd>
                </div>
                {{#if this.editTarget.createdAt}}
                  <div class='rec'>
                    <dt>Created</dt>
                    <dd>{{formatTime this.editTarget.createdAt}}</dd>
                  </div>
                {{/if}}
              </dl>

              {{#if (eq this.editMode 'paint')}}
                <p class='edit-hint'>Brush over the area you want to change,
                  then describe what should appear there.</p>
              {{/if}}
            </section>

            <footer class='edit-footer'>
              {{#if this.errorMessage}}
                <p
                  class='error'
                  data-test-ai-image-error
                >{{this.errorMessage}}</p>
              {{/if}}

              <div class='edit-controls'>
                <BoxelInput
                  @type='textarea'
                  @value={{this.editPrompt}}
                  @onInput={{this.updateEditPrompt}}
                  @placeholder={{if
                    (eq this.editMode 'paint')
                    'Describe what should appear in the painted area…'
                    'Describe the change to make…'
                  }}
                  class='prompt-input'
                  aria-label='Edit instruction'
                  data-test-ai-image-edit-prompt
                  {{on 'keydown' this.onEditPromptKeydown}}
                />
                <div class='edit-actions'>
                  <Button
                    @kind='secondary'
                    class='ghost-btn'
                    {{on 'click' this.closeEdit}}
                  >
                    Cancel
                  </Button>
                  {{#if this.isBusy}}
                    <button
                      type='button'
                      class='stop-btn'
                      aria-label='Stop generating'
                      {{on 'click' this.stopGenerating}}
                      data-test-ai-image-edit-stop
                    >
                      <span class='stop-glyph' aria-hidden='true'></span>
                    </button>
                  {{else}}
                    <Button
                      @kind='primary'
                      {{on 'click' this.editGenerate.perform}}
                      data-test-ai-image-edit-generate
                    >
                      {{if (eq this.editMode 'paint') 'Repaint area' 'Refine'}}
                    </Button>
                  {{/if}}
                </div>
              </div>
            </footer>
          </div>
        </div>
      {{/if}}

      {{#if this.previewNode}}
        <div
          class='version-popover'
          style={{this.previewStyle}}
          {{on 'mouseenter' this.keepPreview}}
          {{on 'mouseleave' this.scheduleHidePreview}}
        >
          {{#if this.previewNode.entry.image.url}}
            <img
              class='version-popover-img'
              src={{this.previewNode.entry.image.url}}
              alt={{this.previewNode.entry.prompt}}
            />
          {{/if}}
          <div class='version-popover-body'>
            <div class='version-popover-head'>
              <span
                class='version-popover-tag'
              >v{{this.previewNode.version}}</span>
              <button
                type='button'
                class='pop-icon'
                aria-label='Scroll to this version in the thread'
                title='View in thread'
                {{on 'click' (fn this.jumpToVersion this.previewNode.version)}}
              >
                <CornerDownRightIcon />
              </button>
            </div>
            <div class='version-popover-prompt-row'>
              <p
                class='version-popover-prompt'
              >{{this.previewNode.entry.prompt}}</p>
              <button
                type='button'
                class='pop-icon'
                aria-label='Copy prompt'
                title={{if
                  (eq this.copiedVersion this.previewNode.version)
                  'Copied'
                  'Copy prompt'
                }}
                {{on
                  'click'
                  (fn
                    this.copyPrompt
                    this.previewNode.version
                    this.previewNode.entry.prompt
                  )
                }}
              >
                {{#if (eq this.copiedVersion this.previewNode.version)}}
                  <CopyCheckIcon />
                {{else}}
                  <CopyIcon />
                {{/if}}
              </button>
            </div>
            <Button
              @kind='primary'
              @size='small'
              {{on 'click' (fn this.refineFromPreview this.previewNode.entry)}}
              data-test-ai-image-version-refine={{this.previewNode.version}}
            >Refine image</Button>
          </div>
        </div>
      {{/if}}
    </div>

    <style scoped>
      .ai-image {
        --c-bg: var(--ai-image-bg, var(--background, #ffffff));
        --c-fg: var(--ai-image-ink, var(--foreground, #1a1a1a));
        --c-surface: var(--ai-image-surface, var(--card, #f7f7f7));
        --c-muted: var(--ai-image-muted, var(--muted-foreground, #919191));
        --c-accent: var(--ai-image-accent, var(--primary, #00b389));
        --c-accent-fg: var(
          --ai-image-accent-fg,
          var(--primary-foreground, #ffffff)
        );
        --c-border: var(--ai-image-border, var(--border, #e8e8e8));
        --c-edit: var(--ai-image-edit, var(--primary, #2f6fd0));
        --c-inpaint: var(--ai-image-inpaint, #c2410c);
        --c-danger: var(--ai-image-danger, var(--destructive, #d32f2f));
        --c-radius: var(--ai-image-radius, var(--radius, 10px));
        position: relative;
        display: flex;
        flex-direction: column;
        height: 100%;
        background: var(--c-bg);
        color: var(--c-fg);
        font: var(--boxel-font-sm);
        font-family: var(--ai-image-font, var(--font-sans, inherit));
        container-type: inline-size;
      }
      /* Default palette, pinned only when no theme is linked. Ships both a
         light and a studio-dark variant keyed off the card's own data-theme,
         so the in-card toggle re-themes just this card. A linked theme supplies
         these semantic tokens itself and this block is absent. */
      .ai-image-default-theme {
        --background: #ffffff;
        --foreground: #1a1a1a;
        --card: #f6f6f8;
        --card-foreground: #1a1a1a;
        --muted-foreground: #6b6b76;
        --border: rgba(0, 0, 0, 0.1);
        --primary: #00b389;
        --primary-foreground: #08100d;
        --destructive: #d32f2f;
        --radius: 14px;
      }
      .ai-image-default-theme[data-theme='dark'] {
        --background: #101014;
        --foreground: #ececf1;
        --card: #18181e;
        --card-foreground: #ececf1;
        --muted-foreground: #8e8ea0;
        --border: rgba(255, 255, 255, 0.09);
        --destructive: #f87171;
      }
      .body {
        flex: 1 1 auto;
        min-height: 0;
        display: flex;
        flex-direction: row;
      }
      .sidebar {
        flex: 0 0 17rem;
        min-height: 0;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp);
        border-right: 1px solid var(--c-border);
        background: var(--c-surface);
        /* Model + Aspect stay put at the top; only the version list scrolls. */
        overflow: hidden;
      }
      @container (max-width: 40rem) {
        .body {
          flex-direction: column;
        }
        .sidebar {
          flex: 0 0 auto;
          /* Stacked layout scrolls as a whole; version list uses its cap. */
          overflow-y: auto;
          border-right: none;
          border-bottom: 1px solid var(--c-border);
        }
      }
      .main {
        position: relative;
        flex: 1 1 auto;
        min-width: 0;
        min-height: 0;
        display: flex;
        flex-direction: column;
        overflow: hidden;
        /* Subtle dot-grid so the canvas reads as a work surface, not a flat
           void. Tinted from --foreground so it's faint in both light and
           dark; fixed 22px cell keeps it pixel-consistent as the thread
           scrolls. */
        background-image: radial-gradient(
          color-mix(in srgb, var(--c-fg) 7%, transparent) 1px,
          transparent 1px
        );
        background-size: 22px 22px;
        background-position: center top;
      }
      .header {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        border-bottom: 1px solid var(--c-border);
      }
      .scheme-toggle {
        margin-left: auto;
        flex-shrink: 0;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 2rem;
        height: 2rem;
        border: 1px solid var(--c-border);
        border-radius: 50%;
        background: transparent;
        color: var(--c-fg);
        cursor: pointer;
        transition:
          border-color 0.15s ease,
          color 0.15s ease;
      }
      .scheme-toggle:hover {
        border-color: var(--c-accent);
        color: var(--c-accent);
      }
      .scheme-toggle > :deep(svg) {
        width: 1.05rem;
        height: 1.05rem;
      }
      .header h1 {
        margin: 0;
        font-size: var(--boxel-font-size);
        font-weight: 700;
      }
      .header-icon {
        flex-shrink: 0;
        width: 2rem;
        height: 2rem;
        padding: 0.375rem;
        border-radius: 50%;
        color: var(--c-accent);
        background: color-mix(in srgb, var(--c-accent) 12%, transparent);
      }
      .thread {
        flex: 1;
        overflow-y: auto;
        /* Bottom padding clears the floating composer. */
        padding: var(--boxel-sp) var(--boxel-sp-lg) 10rem;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--boxel-sp-xl);
      }
      .turn {
        width: 100%;
        max-width: 42rem;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        animation: turn-in 0.35s ease-out;
      }
      @keyframes turn-in {
        from {
          opacity: 0;
          transform: translateY(0.5rem);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .turn {
          animation: none;
        }
      }
      .turn-meta {
        display: flex;
        align-items: baseline;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xxs);
      }
      .version {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        color: var(--c-fg);
        background: var(--c-surface);
        border: 1px solid var(--c-border);
        border-radius: var(--boxel-border-radius-sm);
        padding: 2px var(--boxel-sp-xxs);
      }
      .lineage {
        font-size: var(--boxel-font-size-xs);
        color: var(--c-muted);
        font-style: italic;
      }
      .when {
        margin-left: auto;
        font-size: var(--boxel-font-size-xs);
        color: var(--c-muted);
      }
      .turn-prompt-row {
        display: flex;
        align-items: flex-start;
        gap: var(--boxel-sp-4xs);
      }
      .turn-prompt {
        flex: 1 1 auto;
        min-width: 0;
        margin: 0;
        color: var(--c-fg);
      }
      /* Copy-prompt button on a thread turn: always visible, brightens on hover. */
      .turn-copy {
        opacity: 0.7;
        transition: opacity 0.15s ease;
      }
      .turn-copy:hover,
      .turn-copy:focus-visible {
        opacity: 1;
      }
      .badge {
        flex-shrink: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        border-radius: var(--boxel-border-radius-sm);
        padding: 2px var(--boxel-sp-xxs);
        background: color-mix(in srgb, var(--c-fg) 10%, transparent);
        color: var(--c-fg);
      }
      .badge-inpaint {
        background: color-mix(in srgb, var(--c-inpaint) 16%, transparent);
        color: color-mix(in srgb, var(--c-inpaint), var(--c-fg) 40%);
      }
      .badge-edit {
        background: color-mix(in srgb, var(--c-edit) 14%, transparent);
        color: color-mix(in srgb, var(--c-edit), var(--c-fg) 40%);
      }
      /* Every turn renders at the SAME width so the transcript is a clean
         column; height follows each image's aspect ratio (ChatGPT-style),
         instead of the width varying with the ratio. */
      .turn-image {
        display: block;
        width: 100%;
        height: auto;
        border-radius: var(--c-radius);
        border: 1px solid var(--c-border);
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.28);
      }
      .turn-skeleton {
        width: 100%;
        aspect-ratio: 16 / 9;
        border-radius: var(--c-radius);
        overflow: hidden;
        border: 1px solid var(--c-border);
      }
      .gen-center {
        position: relative;
        z-index: 1;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
        text-align: center;
      }
      .gen-badge {
        display: grid;
        place-items: center;
        width: 3rem;
        height: 3rem;
        border-radius: 50%;
        color: var(--c-accent);
        background: color-mix(in srgb, var(--c-accent) 14%, transparent);
        animation: gen-pulse 1.8s ease-in-out infinite;
      }
      .gen-badge > :deep(svg) {
        width: 1.5rem;
        height: 1.5rem;
      }
      /* The generating overlay is a fixed light material (see
         generating-overlay.gts) that does not invert with the theme, so its
         text uses fixed dark ink rather than the theme's --c-fg. */
      .gen-title {
        font-size: var(--boxel-font-size);
        font-weight: 700;
        color: #1a1a1a;
      }
      .gen-sub {
        max-width: 20rem;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.4;
        color: #6b6b76;
      }
      .gen-dots {
        display: flex;
        gap: 0.375rem;
        margin-top: var(--boxel-sp-4xs);
      }
      .gen-dots span {
        width: 0.4rem;
        height: 0.4rem;
        border-radius: 50%;
        background: var(--c-accent);
        animation: gen-bounce 1.2s ease-in-out infinite;
      }
      .gen-dots span:nth-child(2) {
        animation-delay: 0.15s;
      }
      .gen-dots span:nth-child(3) {
        animation-delay: 0.3s;
      }
      @keyframes gen-pulse {
        0%,
        100% {
          transform: scale(1);
          opacity: 1;
        }
        50% {
          transform: scale(1.08);
          opacity: 0.75;
        }
      }
      @keyframes gen-bounce {
        0%,
        100% {
          transform: translateY(0);
          opacity: 0.4;
        }
        50% {
          transform: translateY(-0.3rem);
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .gen-badge,
        .gen-dots span {
          animation-duration: 4s;
        }
      }
      .turn-media {
        position: relative;
        /* Fixed display width for every turn so v1, v2, … line up as a column
           regardless of aspect ratio; the hover actions anchor to this box. */
        width: 100%;
        max-width: 380px;
      }
      /* Actions live on the image itself, revealed on hover/focus, so they
         read as tools for THIS image rather than competing with Generate. */
      .turn-actions {
        position: absolute;
        top: var(--boxel-sp-xs);
        right: var(--boxel-sp-xs);
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        opacity: 0;
        transition: opacity 0.15s ease;
      }
      .turn-media:hover .turn-actions,
      .turn-media:focus-within .turn-actions {
        opacity: 1;
      }
      @media (hover: none), (prefers-reduced-motion: reduce) {
        .turn-actions {
          opacity: 1;
          transition: none;
        }
      }
      /* Quiet secondary action: Refine is the one accented action per image.
         Backed by a blurred scrim so it stays legible over any artwork. */
      .download {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
        border-radius: var(--boxel-border-radius-sm, 6px);
        border: 1px solid var(--c-border);
        background: color-mix(in srgb, var(--c-surface) 82%, transparent);
        backdrop-filter: blur(8px);
        color: var(--c-fg);
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        line-height: 1.6;
        text-decoration: none;
        transition:
          border-color 0.15s ease,
          color 0.15s ease;
      }
      .download:hover {
        border-color: var(--c-accent);
        color: var(--c-accent);
      }
      .download:active {
        opacity: 0.8;
      }
      .empty {
        display: flex;
        flex-direction: column;
        align-items: center;
        text-align: center;
        gap: var(--boxel-sp-xs);
        margin: auto;
        max-width: 32rem;
        padding: var(--boxel-sp-xl) var(--boxel-sp);
        color: var(--c-muted);
      }
      .empty-badge {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 48px;
        height: 48px;
        border-radius: 50%;
        background: color-mix(in srgb, var(--c-accent) 18%, transparent);
        color: var(--c-accent);
        margin-bottom: var(--boxel-sp-xs);
      }
      .empty-badge > :deep(svg) {
        width: 24px;
        height: 24px;
      }
      .empty h2 {
        margin: 0;
        font-size: var(--boxel-font-size);
        font-weight: 700;
        color: var(--c-fg);
      }
      .empty p {
        margin: 0;
      }
      .examples {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: var(--boxel-sp-xxs);
        margin-top: var(--boxel-sp-xs);
      }
      .example-chip {
        --boxel-pill-padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-xs);
        cursor: pointer;
        background: transparent;
        border-color: var(--c-border);
        color: var(--c-fg);
      }
      .example-chip:hover {
        border-color: var(--c-accent);
        color: var(--c-accent);
      }
      /* Floating pill composer over the canvas, Midjourney-style. */
      .composer-dock {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        /* Above the thread (incl. the generating skeleton) so nothing bleeds
           through; below the version preview popover (z-index 20). */
        z-index: 10;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xl) var(--boxel-sp-lg) var(--boxel-sp);
        background: linear-gradient(transparent, var(--c-bg) 55%);
        pointer-events: none;
      }
      .composer-dock > * {
        pointer-events: auto;
      }
      .composer-card {
        width: 100%;
        max-width: 42rem;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--c-border);
        border-radius: 1.5rem;
        /* Opaque so a tall generating skeleton behind it never ghosts through. */
        background: var(--c-surface);
        box-shadow: 0 12px 40px rgba(0, 0, 0, 0.3);
      }
      /* GPT-style memory toggle: follow-up prompts continue the latest image
         unless the person opts into a fresh one. */
      .composer-mode {
        display: flex;
        gap: var(--boxel-sp-xxs);
      }
      .mode-chip {
        border: 1px solid var(--c-border);
        border-radius: 999px;
        padding: 2px var(--boxel-sp-xs);
        background: transparent;
        color: var(--c-muted);
        font: inherit;
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        cursor: pointer;
        transition:
          border-color 0.15s ease,
          color 0.15s ease;
      }
      .mode-chip.active {
        border-color: var(--c-accent);
        color: var(--c-fg);
        background: color-mix(in srgb, var(--c-accent) 12%, transparent);
      }
      .composer-main {
        display: flex;
        align-items: flex-end;
        gap: var(--boxel-sp-xs);
      }
      .composer-main > :deep(.prompt-input) {
        flex: 1 1 auto;
      }
      .chip-close {
        border: none;
        background: none;
        cursor: pointer;
        font-size: 1rem;
        color: var(--c-muted);
        line-height: 1;
      }
      .prompt-input {
        min-height: 3.25rem;
        max-height: 10rem;
        resize: none;
        color: var(--c-fg);
      }
      .prompt-input::placeholder {
        color: var(--c-muted);
      }
      /* Bottom composer: borderless, blends into the pill card. */
      .composer-main .prompt-input {
        border: none;
        background: transparent;
        box-shadow: none;
      }
      .composer-main .prompt-input:focus,
      .composer-main .prompt-input:focus-visible {
        outline: none;
        box-shadow: none;
        border: none;
      }
      /* Refine modal: a visible bordered field on the dark modal surface. */
      .edit-controls .prompt-input {
        border: 1px solid var(--c-border);
        border-radius: var(--boxel-border-radius-sm);
        background: color-mix(in srgb, var(--c-fg) 4%, transparent);
      }
      .edit-controls .prompt-input:focus,
      .edit-controls .prompt-input:focus-visible {
        border-color: var(--c-accent);
        outline: none;
      }
      .setting {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        /* Theme the in-place BoxelSelect dropdown through the card's tokens so
           its options (esp. the hover/highlight state) stay legible in dark and
           light — custom properties inherit into the rendered-in-place menu. */
        --dropdown-background-color: var(--c-surface);
        --dropdown-text-color: var(--c-fg);
        --dropdown-hover-color: color-mix(
          in srgb,
          var(--c-accent) 18%,
          transparent
        );
        --dropdown-highlight-color: color-mix(
          in srgb,
          var(--c-accent) 24%,
          transparent
        );
        --dropdown-highlight-hover-color: color-mix(
          in srgb,
          var(--c-accent) 32%,
          transparent
        );
        --dropdown-selected-text-color: var(--c-fg);
      }
      /* ember-power-select marks the current value with
         `--selected`/`--highlighted` (not aria-*). Its default solid-accent fill
         leaves white-on-green borderline, so re-skin those states as a faint
         accent tint with full-contrast ink. */
      .setting :deep(.ember-power-select-option--selected),
      .setting :deep(.ember-power-select-option--highlighted) {
        background-color: color-mix(
          in srgb,
          var(--c-accent) 22%,
          transparent
        ) !important;
        color: var(--c-fg) !important;
      }
      .setting-label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--c-muted);
      }
      /* Aspect ratio locked to the source image during a refine / continue. */
      .aspect-locked {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-xs);
        border: 1px solid var(--c-border);
        border-radius: var(--boxel-border-radius-sm);
        background: color-mix(in srgb, var(--c-fg) 5%, transparent);
        color: var(--c-muted);
        cursor: not-allowed;
      }
      .aspect-locked-value {
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        color: var(--c-fg);
      }
      .aspect-locked-icon {
        width: 0.9rem;
        height: 0.9rem;
        flex-shrink: 0;
      }
      /* Version tree: a GitHub-network-style map of the parent chain. Depth is
         applied inline per node; a rail dot + elbow draws the branch lines. */
      .versions {
        flex: 1 1 auto;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xxs);
        min-height: 0;
      }
      /* Floating version preview — position:absolute inside the card root
         (which is position:relative) so it stays within the card's bounds
         while still escaping the sidebar's scroll clip. Coordinates are set
         inline, computed relative to the card root in showVersionPreview. */
      .version-popover {
        position: absolute;
        z-index: 20;
        display: flex;
        flex-direction: column;
        overflow: hidden;
        border: 1px solid var(--c-border);
        border-radius: var(--c-radius);
        background: var(--c-surface);
        box-shadow: 0 12px 40px rgba(0, 0, 0, 0.3);
        animation: turn-in 0.12s ease-out;
      }
      .version-popover-img {
        width: 100%;
        aspect-ratio: 16 / 9;
        object-fit: cover;
        display: block;
      }
      .version-popover-body {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-xs);
      }
      .version-popover-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xxs);
      }
      .version-popover-tag {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        color: var(--c-fg);
      }
      .version-popover-prompt-row {
        display: flex;
        align-items: flex-start;
        gap: var(--boxel-sp-4xs);
      }
      .version-popover-prompt {
        flex: 1 1 auto;
        min-width: 0;
        margin: 0 0 var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.35;
        color: var(--c-muted);
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      /* Small ghost icon buttons inside the preview popover. */
      .pop-icon {
        flex-shrink: 0;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 1.5rem;
        height: 1.5rem;
        padding: 0;
        border: none;
        border-radius: var(--boxel-border-radius-sm);
        background: transparent;
        color: var(--c-muted);
        cursor: pointer;
        transition:
          color 0.15s ease,
          background 0.15s ease;
      }
      .pop-icon:hover {
        color: var(--c-fg);
        background: color-mix(in srgb, var(--c-fg) 8%, transparent);
      }
      .pop-icon > :deep(svg) {
        width: 0.9rem;
        height: 0.9rem;
      }
      /* Scroll viewport: bounded by the sidebar's flex height so a long tree
         scrolls inside the panel instead of pushing the whole card. */
      .version-graph {
        flex: 1 1 auto;
        min-height: 0;
        overflow-y: auto;
        overflow-x: hidden;
      }
      /* The positioned canvas holds the SVG rails + absolute node rows; both
         share the same px grid (ROW / LANE / PAD) computed in versionGraph. Its
         height (inline) is the full content height, so it scrolls within the
         viewport above. */
      .version-canvas {
        position: relative;
      }
      .version-rails {
        position: absolute;
        top: 0;
        left: 0;
        pointer-events: none;
      }
      .rail {
        stroke: var(--c-border);
        stroke-width: 1.5;
      }
      .rail-branch {
        stroke: color-mix(in srgb, var(--c-accent) 55%, var(--c-border));
      }
      .version-btn {
        position: absolute;
        left: 0;
        right: 0;
        min-width: 0;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        padding: 0 var(--boxel-sp-5xs) 0 var(--rail-w, 2.5rem);
        border: 1px solid transparent;
        border-radius: var(--boxel-border-radius-sm);
        background: transparent;
        color: var(--c-fg);
        font: inherit;
        text-align: left;
        cursor: pointer;
        transition:
          border-color 0.15s ease,
          background 0.15s ease;
      }
      .version-btn:hover {
        border-color: var(--c-border);
        background: color-mix(in srgb, var(--c-fg) 6%, transparent);
      }
      .version-btn.current {
        border-color: var(--c-accent);
        background: color-mix(in srgb, var(--c-accent) 12%, transparent);
      }
      /* Node dot, positioned over its lane on the SVG grid. */
      .version-dot {
        position: absolute;
        top: 50%;
        width: 10px;
        height: 10px;
        transform: translateY(-50%);
        border-radius: 50%;
        background: var(--c-muted);
        border: 2px solid var(--c-surface);
      }
      .version-btn.current .version-dot {
        background: var(--c-accent);
      }
      /* A root = a NEW image (no parent): a hollow ring, so it reads as the
         start of a fresh lineage rather than a point on the trunk. */
      .version-btn.root .version-dot {
        background: var(--c-surface);
        border-color: var(--c-muted);
        box-shadow: inset 0 0 0 2px var(--c-muted);
      }
      .version-btn.root.current .version-dot {
        border-color: var(--c-accent);
        box-shadow: inset 0 0 0 2px var(--c-accent);
      }
      .version-btn.branch .version-dot {
        box-shadow: 0 0 0 3px
          color-mix(in srgb, var(--c-accent) 30%, transparent);
      }
      .version-thumb {
        flex-shrink: 0;
        width: 1.75rem;
        height: 1.75rem;
        object-fit: cover;
        border-radius: var(--boxel-border-radius-sm);
        border: 1px solid var(--c-border);
      }
      .version-info {
        min-width: 0;
        display: flex;
        flex-direction: column;
        line-height: 1.2;
      }
      .version-tag {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .version-prompt {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: var(--boxel-font-size-xs);
        color: var(--c-muted);
      }
      /* Re-point the aspect tiles' literal boxel grays at the theme chain so
         they read correctly on the studio-dark (or any themed) surface. The
         refine modal reuses the very same field, so it shares these rules and
         needs full width for the 4-column grid to lay out like the sidebar. */
      .setting :deep(.ar-tile),
      .edit-setting :deep(.ar-tile) {
        border-color: var(--c-border);
        color: var(--c-muted);
      }
      .setting :deep(.ar-tile.selected),
      .edit-setting :deep(.ar-tile.selected) {
        color: var(--c-fg);
      }
      .edit-setting :deep(.ar-grid) {
        width: 100%;
      }
      /* Stop button: icon-only circle with a filled square, ChatGPT-style. */
      .stop-btn {
        flex-shrink: 0;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 2.5rem;
        height: 2.5rem;
        padding: 0;
        border: none;
        border-radius: 50%;
        background: var(--c-accent);
        color: var(--c-accent-fg);
        cursor: pointer;
        transition: background 0.15s ease;
      }
      .stop-btn:hover {
        background: color-mix(in srgb, var(--c-accent) 88%, #000000);
      }
      .stop-glyph {
        width: 0.7rem;
        height: 0.7rem;
        border-radius: 2px;
        background: currentColor;
      }
      .error {
        width: 100%;
        max-width: 42rem;
        color: var(--c-danger);
        font-size: var(--boxel-font-size-xs);
        margin: 0;
      }
      /* ----- focused editing session ----- */
      .edit-overlay {
        position: absolute;
        inset: 0;
        background: rgba(0, 0, 0, 0.65);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: var(--boxel-sp);
        z-index: 10;
      }
      .edit-modal {
        background: var(--c-bg);
        border-radius: var(--boxel-border-radius);
        padding: var(--boxel-sp);
        width: min(560px, 100%);
        max-height: 92%;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        box-shadow: 0 12px 40px rgba(0, 0, 0, 0.35);
        overflow: hidden;
      }
      /* Header (title) and footer (prompt + actions) stay fixed; only the
         middle body scrolls, so the image preview can be large without pushing
         the controls off-screen. */
      .edit-head {
        flex: 0 0 auto;
        display: flex;
        align-items: center;
        justify-content: space-between;
      }
      .edit-body {
        flex: 1 1 auto;
        min-height: 0;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .edit-footer {
        flex: 0 0 auto;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .edit-head h2 {
        margin: 0;
        font-size: var(--boxel-font-size);
        font-weight: 700;
      }
      .edit-tabs {
        display: inline-flex;
        gap: 2px;
        padding: 2px;
        background: color-mix(in srgb, var(--c-fg) 10%, transparent);
        border-radius: var(--boxel-border-radius);
        align-self: flex-start;
      }
      .tab {
        border: none;
        background: none;
        cursor: pointer;
        font: inherit;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        color: var(--c-muted);
        padding: var(--boxel-sp-xxs) var(--boxel-sp-sm);
        border-radius: calc(var(--boxel-border-radius) - 2px);
      }
      .tab.active {
        background: var(--c-bg);
        color: var(--c-fg);
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.12);
      }
      .edit-setting {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xxs);
        width: 100%;
      }
      .edit-setting .aspect-locked {
        align-self: flex-start;
        min-width: 6rem;
      }
      .edit-stage {
        /* One box for both the overlay and the result: its shape follows the
           image's aspect ratio (set inline), capped by max-height, so the
           height never jumps between generating and the arrived image. */
        flex: 0 0 auto;
        width: 100%;
        max-height: 70vh;
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
        background: var(--c-surface);
        border: 1px solid var(--c-border);
        border-radius: var(--boxel-border-radius-sm);
        padding: var(--boxel-sp-xxs);
      }
      .edit-generating {
        width: 100%;
        height: 100%;
      }
      .edit-image {
        display: block;
        max-width: 100%;
        max-height: 100%;
        width: auto;
        height: auto;
        object-fit: contain;
        border-radius: var(--boxel-border-radius-sm);
      }
      .mask-canvas {
        display: block;
        max-width: 100%;
        max-height: 100%;
        width: auto;
        height: auto;
        object-fit: contain;
        cursor: crosshair;
        touch-action: none;
        border-radius: var(--boxel-border-radius-sm);
      }
      .edit-hint {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--c-muted);
      }
      /* Provenance record of the image being refined. */
      .edit-record {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
        gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        margin: 0;
        padding: var(--boxel-sp-xs);
        border: 1px solid var(--c-border);
        border-radius: var(--boxel-border-radius-sm);
        background: color-mix(in srgb, var(--c-fg) 4%, transparent);
      }
      .edit-record .rec {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 1px;
      }
      .edit-record dt {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--c-muted);
      }
      .edit-record dd {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--c-fg);
        overflow-wrap: anywhere;
        /* A long prompt must not balloon the record; clamp to a few lines. */
        display: -webkit-box;
        -webkit-line-clamp: 4;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .edit-controls {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
      }
      .edit-actions {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: var(--boxel-sp-xs);
      }
      /* Re-skin the secondary Button through the semantic pair so its text
         stays readable on the themed (incl. studio-dark) modal surface. */
      .ghost-btn {
        --boxel-button-color: transparent;
        --boxel-button-border-color: var(--c-border);
        --boxel-button-text-color: var(--c-fg);
        background: transparent;
        border-color: var(--c-border);
        color: var(--c-fg);
      }
      .ghost-btn:hover:not(:disabled) {
        border-color: var(--c-accent);
        color: var(--c-accent);
        background: transparent;
      }
    </style>
  </template>
}

// ---------------------------------------------------------------------------
// Embedded / Fitted: show the most recent image and title.
// ---------------------------------------------------------------------------
export class AiImageGeneratorEmbedded extends Component<
  typeof AiImageGenerator
> {
  // The most recent history card. Returns the card itself (no field reads) so
  // the template can dereference its image reactively.
  get latest(): AiImage | undefined {
    let items = (this.args.model?.history ?? []) as AiImage[];
    return items[items.length - 1];
  }
  <template>
    <div class='embedded'>
      {{#if this.latest.image.url}}
        <img
          src={{this.latest.image.url}}
          alt={{@model.cardTitle}}
          loading='lazy'
        />
      {{else}}
        <div class='placeholder'><SparklesIcon /></div>
      {{/if}}
      <div class='caption'>
        <SparklesIcon class='cap-icon' />
        <span>{{if
            @model.cardTitle
            @model.cardTitle
            'AI Image Generator'
          }}</span>
      </div>
    </div>
    <style scoped>
      .embedded {
        --c-muted: var(--ai-image-muted, var(--muted-foreground, #919191));
        --c-border: var(--ai-image-border, var(--border, #e8e8e8));
        position: relative;
        height: 100%;
        min-height: 120px;
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
        background: var(--c-border);
      }
      .embedded img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .placeholder {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 100%;
        color: var(--c-muted);
      }
      .caption {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        padding: var(--boxel-sp-xs);
        /* Sits on a fixed dark scrim over the image, so always light. */
        color: #ffffff;
        font-size: var(--boxel-font-size-sm);
        background: linear-gradient(transparent, rgba(0, 0, 0, 0.7));
      }
      .cap-icon {
        width: 14px;
        height: 14px;
      }
    </style>
  </template>
}
