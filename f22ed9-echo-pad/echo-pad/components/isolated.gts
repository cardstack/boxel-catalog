import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe, type SafeString } from '@ember/template';
import { modifier } from 'ember-modifier';
import { restartableTask, timeout } from 'ember-concurrency';

import EraserIcon from '@cardstack/boxel-icons/eraser';
import HandIcon from '@cardstack/boxel-icons/hand';
import LassoIcon from '@cardstack/boxel-icons/lasso';
import PencilIcon from '@cardstack/boxel-icons/pencil';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Component } from '@cardstack/base/card-api';

import {
  RecognizeInkCommand,
  RecognizeInkInput,
} from '../commands/recognize-ink-command';
import { EchoScenePlayer } from './scene-player';
import { mapStrokesToManim } from '../utils/scene';
import { EchoNoteField } from '../fields/echo-note';
import {
  asEchoMode,
  clamp,
  ECHO_MODES,
  INK_COLOR,
  mapLabelsToWorld,
  mapPolylinesToWorld,
  parseSketchJson,
  type EchoLabel,
  parseInk,
  polylinesBBox,
  polylinesToPaths,
  serializeInk,
  strokeBBox,
  strokeInLasso,
  strokeNearPoint,
  unionBBox,
  ZOOM_MAX,
  ZOOM_MIN,
  type BBox,
  type EchoModeKey,
  type InkStroke,
} from '../utils/index';
import type { EchoPad } from '../echo-pad';

type Tool = 'pen' | 'eraser' | 'lasso' | 'pan';

type Draft = {
  content: string;
  mode: EchoModeKey;
  sketchWorld: number[][] | null; // world-space polylines, ready to ink onto the board
  labelsWorld: EchoLabel[] | null; // world-space write-backs, rendered in the red hand
  sceneJson: string; // validated manim scene spec ('' when none)
  x: number;
  y: number;
  width: number;
};

type EchoErrorSlip = {
  message: string;
  mode: EchoModeKey;
  x: number;
  y: number;
};

const ERASER_RADIUS = 10; // world units
const DRAFT_WIDTH = 340;
const TITLE_BLOCK_SCREEN = { w: 320, h: 96 }; // docked bottom-right, screen space
const DRAFT_MIN_SCREEN_H = 150;
const CROP_MARGIN = 48;
const CROP_MAX_DIM = 1024;
const UNDO_DEPTH = 30;
const AUTO_IDLE_MS = 3000;
const AUTO_MIN_STROKES = 3;
const AUTO_MIN_AREA = 900; // world px² — ignore tiny scribbles
const AUTO_GRACE_MS = 1800; // dot lingers, then fires by itself (Esc cancels)

export class EchoPadIsolated extends Component<typeof EchoPad> {
  @tracked tool: Tool = 'pen';
  @tracked zoom = 1;
  @tracked panX = 0;
  @tracked panY = 0;
  @tracked strokeCount = 0;
  @tracked lassoPts: number[] | null = null; // world coords, closed on pointer-up
  @tracked lassoBBox: BBox | null = null;
  @tracked thinkingLabel: string | null = null;
  @tracked draft: Draft | null = null;
  @tracked echoError: EchoErrorSlip | null = null;
  @tracked clearArmed = false;
  @tracked toast: { message: string; undo: () => void } | null = null;
  @tracked spaceHeld = false;
  @tracked noteDrag: { index: number; x: number; y: number } | null = null;
  @tracked autoEnabled = true;
  @tracked autoDot: { x: number; y: number; box: BBox } | null = null;

  strokes: InkStroke[] = [];
  undoStack: string[] = [];
  canvas: HTMLCanvasElement | null = null;
  boardEl: HTMLElement | null = null;
  resizeObserver: ResizeObserver | null = null;
  activePointer: {
    kind: 'draw' | 'erase' | 'lasso' | 'pan' | 'drag-draft' | 'drag-note';
    id: number;
    lastX: number;
    lastY: number;
    noteIndex?: number;
  } | null = null;
  currentStroke: InkStroke | null = null;
  lastEchoBBox: BBox | null = null;
  echoBaselineCount = 0; // strokes already covered by a previous echo
  autoSuppressedBelow = 0; // ignore auto until this many strokes exist
  clearArmTimer: number | undefined;
  toastTimer: number | undefined;
  keydownHandler = (e: KeyboardEvent) => this.onKeyDown(e);
  keyupHandler = (e: KeyboardEvent) => this.onKeyUp(e);

  inkLoaded = false;

  setupBoard = modifier((el: HTMLElement) => {
    this.boardEl = el;
    let canvas = el.querySelector('canvas.ink-layer') as HTMLCanvasElement;
    this.canvas = canvas;
    // one-shot: our own debounced save mutates inkJson, which re-runs this
    // modifier — re-seeding from the model then would clobber live state
    // (and reset the ambient-scan baseline before the scan can fire)
    if (!this.inkLoaded) {
      this.inkLoaded = true;
      this.strokes = parseInk(this.args.model?.inkJson).strokes;
      this.strokeCount = this.strokes.length;
      this.echoBaselineCount = this.strokes.length;
      this.restoreViewport();
    }
    this.resizeObserver = new ResizeObserver(() => this.fitCanvas());
    this.resizeObserver.observe(el);
    this.fitCanvas();
    window.addEventListener('keydown', this.keydownHandler);
    window.addEventListener('keyup', this.keyupHandler);
    return () => {
      this.resizeObserver?.disconnect();
      this.resizeObserver = null;
      window.removeEventListener('keydown', this.keydownHandler);
      window.removeEventListener('keyup', this.keyupHandler);
    };
  });

  willDestroy(): void {
    super.willDestroy();
    window.removeEventListener('keydown', this.keydownHandler);
    window.removeEventListener('keyup', this.keyupHandler);
    window.clearTimeout(this.clearArmTimer);
    window.clearTimeout(this.toastTimer);
  }

  // ---- camera ----

  restoreViewport() {
    try {
      let v = JSON.parse(this.args.model?.viewportJson ?? '');
      if (v && typeof v === 'object') {
        this.zoom = clamp(Number(v.zoom) || 1, ZOOM_MIN, ZOOM_MAX);
        this.panX = Number(v.x) || 0;
        this.panY = Number(v.y) || 0;
      }
    } catch {
      // fresh board: defaults stand
    }
  }

  get worldTransform(): SafeString {
    return htmlSafe(
      `transform: translate(${this.panX}px, ${this.panY}px) scale(${this.zoom})`,
    );
  }

  get zoomPercent() {
    return Math.round(this.zoom * 100);
  }

  toWorld(clientX: number, clientY: number): [number, number] {
    let rect = this.boardEl?.getBoundingClientRect();
    let sx = clientX - (rect?.left ?? 0);
    let sy = clientY - (rect?.top ?? 0);
    return [(sx - this.panX) / this.zoom, (sy - this.panY) / this.zoom];
  }

  zoomBy(factor: number) {
    let el = this.boardEl;
    if (!el) {
      return;
    }
    let cx = el.clientWidth / 2;
    let cy = el.clientHeight / 2;
    let next = clamp(this.zoom * factor, ZOOM_MIN, ZOOM_MAX);
    this.panX = cx - ((cx - this.panX) / this.zoom) * next;
    this.panY = cy - ((cy - this.panY) / this.zoom) * next;
    this.zoom = next;
    this.redraw();
    this.scheduleSave();
  }

  zoomIn = () => this.zoomBy(1.25);
  zoomOut = () => this.zoomBy(0.8);
  zoomReset = () => this.zoomBy(1 / this.zoom);

  onWheel = (event: Event) => {
    let e = event as WheelEvent;
    e.preventDefault();
    let rect = this.boardEl?.getBoundingClientRect();
    let sx = e.clientX - (rect?.left ?? 0);
    let sy = e.clientY - (rect?.top ?? 0);
    let factor = Math.exp(-e.deltaY * 0.0015);
    let next = clamp(this.zoom * factor, ZOOM_MIN, ZOOM_MAX);
    // keep the world point under the cursor fixed while zooming
    this.panX = sx - ((sx - this.panX) / this.zoom) * next;
    this.panY = sy - ((sy - this.panY) / this.zoom) * next;
    this.zoom = next;
    this.redraw();
    this.scheduleSave();
  };

  // ---- pointer interaction ----

  onPointerDown = (event: Event) => {
    let e = event as PointerEvent;
    if (e.button !== 0 && e.button !== 1) {
      return;
    }
    let el = e.currentTarget as HTMLElement;
    try {
      el.setPointerCapture(e.pointerId);
    } catch {
      // synthetic events have no active pointer to capture
    }
    let panning = this.tool === 'pan' || this.spaceHeld || e.button === 1;
    let [wx, wy] = this.toWorld(e.clientX, e.clientY);

    if (panning) {
      this.activePointer = {
        kind: 'pan',
        id: e.pointerId,
        lastX: e.clientX,
        lastY: e.clientY,
      };
      return;
    }
    if (this.tool === 'pen') {
      this.pushUndo();
      this.autoDot = null;
      this.currentStroke = { w: 2.5, pts: [wx, wy] };
      this.activePointer = {
        kind: 'draw',
        id: e.pointerId,
        lastX: wx,
        lastY: wy,
      };
      return;
    }
    if (this.tool === 'eraser') {
      this.pushUndo();
      this.eraseAt(wx, wy);
      this.activePointer = {
        kind: 'erase',
        id: e.pointerId,
        lastX: wx,
        lastY: wy,
      };
      return;
    }
    if (this.tool === 'lasso') {
      this.dismissLasso();
      this.lassoPts = [wx, wy];
      this.activePointer = {
        kind: 'lasso',
        id: e.pointerId,
        lastX: wx,
        lastY: wy,
      };
    }
  };

  onPointerMove = (event: Event) => {
    let e = event as PointerEvent;
    let ap = this.activePointer;
    if (!ap || ap.id !== e.pointerId) {
      return;
    }
    if (ap.kind === 'pan') {
      this.panX += e.clientX - ap.lastX;
      this.panY += e.clientY - ap.lastY;
      ap.lastX = e.clientX;
      ap.lastY = e.clientY;
      this.redraw();
      return;
    }
    let [wx, wy] = this.toWorld(e.clientX, e.clientY);
    if (ap.kind === 'draw' && this.currentStroke) {
      let dx = wx - ap.lastX;
      let dy = wy - ap.lastY;
      if (dx * dx + dy * dy < 1) {
        return; // drop sub-pixel jitter
      }
      this.currentStroke.pts.push(wx, wy);
      ap.lastX = wx;
      ap.lastY = wy;
      this.drawSegment(this.currentStroke);
      return;
    }
    if (ap.kind === 'erase') {
      this.eraseAt(wx, wy);
      return;
    }
    if (ap.kind === 'lasso' && this.lassoPts) {
      this.lassoPts = [...this.lassoPts, wx, wy];
      return;
    }
    if (ap.kind === 'drag-draft' && this.draft) {
      this.draft = { ...this.draft, x: wx - 20, y: wy - 12 };
      return;
    }
    if (ap.kind === 'drag-note' && ap.noteIndex !== undefined) {
      this.noteDrag = { index: ap.noteIndex, x: wx - 20, y: wy - 12 };
    }
  };

  onPointerUp = (event: Event) => {
    let e = event as PointerEvent;
    let ap = this.activePointer;
    if (!ap || ap.id !== e.pointerId) {
      return;
    }
    this.activePointer = null;
    if (ap.kind === 'draw' && this.currentStroke) {
      if (this.currentStroke.pts.length >= 4) {
        this.strokes.push(this.currentStroke);
        this.strokeCount = this.strokes.length;
      }
      this.currentStroke = null;
      this.redraw();
      this.scheduleSave();
      this.autoScanTask.perform();
      return;
    }
    if (ap.kind === 'erase') {
      this.scheduleSave();
      return;
    }
    if (ap.kind === 'lasso') {
      this.closeLasso();
      return;
    }
    if (ap.kind === 'drag-note' && this.noteDrag) {
      this.commitNotePosition(this.noteDrag);
      this.noteDrag = null;
    }
  };

  onKeyDown(e: KeyboardEvent) {
    if (
      e.target instanceof HTMLInputElement ||
      e.target instanceof HTMLTextAreaElement
    ) {
      return;
    }
    if (e.code === 'Space') {
      this.spaceHeld = true;
      e.preventDefault();
      return;
    }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') {
      e.preventDefault();
      this.undo();
      return;
    }
    let key = e.key.toLowerCase();
    if (key === 'p') this.tool = 'pen';
    if (key === 'e') this.tool = 'eraser';
    if (key === 'l' || key === 's') this.tool = 'lasso';
    if (key === 'v' || key === 'h') this.tool = 'pan';
    if (key === 'escape') {
      if (this.echoTask.isRunning) {
        this.cancelEcho();
      } else if (this.draft) {
        this.dismissDraft();
      } else if (this.autoDot) {
        this.dismissAutoDot();
      } else {
        this.dismissLasso();
      }
    }
  }

  onKeyUp(e: KeyboardEvent) {
    if (e.code === 'Space') {
      this.spaceHeld = false;
    }
  }

  pickTool = (tool: Tool) => {
    this.tool = tool;
  };

  // ---- ink ----

  fitCanvas() {
    let canvas = this.canvas;
    let el = this.boardEl;
    if (!canvas || !el) {
      return;
    }
    let dpr = window.devicePixelRatio || 1;
    canvas.width = Math.max(1, Math.round(el.clientWidth * dpr));
    canvas.height = Math.max(1, Math.round(el.clientHeight * dpr));
    this.redraw();
  }

  redraw() {
    let canvas = this.canvas;
    let ctx = canvas?.getContext('2d');
    if (!canvas || !ctx) {
      return;
    }
    let dpr = window.devicePixelRatio || 1;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(
      dpr * this.zoom,
      0,
      0,
      dpr * this.zoom,
      dpr * this.panX,
      dpr * this.panY,
    );
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = INK_COLOR;
    for (let s of this.strokes) {
      this.strokePath(ctx, s);
    }
    if (this.currentStroke) {
      this.strokePath(ctx, this.currentStroke);
    }
  }

  strokePath(ctx: CanvasRenderingContext2D, s: InkStroke) {
    // ink feel: quadratic-through-midpoints smoothing, per-slice width driven
    // by point spacing (a velocity proxy) — slow strokes run thick, fast thin
    let p = s.pts;
    let n = p.length / 2;
    if (n < 2) {
      return;
    }
    if (n === 2) {
      ctx.beginPath();
      ctx.lineWidth = s.w;
      ctx.moveTo(p[0], p[1]);
      ctx.lineTo(p[2], p[3]);
      ctx.stroke();
      return;
    }
    let ax = p[0];
    let ay = p[1];
    let prevW = s.w;
    for (let i = 1; i < n - 1; i++) {
      let cx = p[i * 2];
      let cy = p[i * 2 + 1];
      let mx = (cx + p[i * 2 + 2]) / 2;
      let my = (cy + p[i * 2 + 3]) / 2;
      let w = (prevW + velocityWidth(s.w, Math.hypot(mx - ax, my - ay))) / 2;
      ctx.beginPath();
      ctx.lineWidth = w;
      ctx.moveTo(ax, ay);
      ctx.quadraticCurveTo(cx, cy, mx, my);
      ctx.stroke();
      prevW = w;
      ax = mx;
      ay = my;
    }
    ctx.beginPath();
    ctx.lineWidth = prevW;
    ctx.moveTo(ax, ay);
    ctx.lineTo(p[n * 2 - 2], p[n * 2 - 1]);
    ctx.stroke();
  }

  drawSegment(s: InkStroke) {
    // incremental draw of the live stroke's newest segment; the pointer-up
    // redraw replaces it with the smoothed rendering
    let ctx = this.canvas?.getContext('2d');
    let n = s.pts.length;
    if (!ctx || n < 4) {
      return;
    }
    let d = Math.hypot(
      s.pts[n - 2] - s.pts[n - 4],
      s.pts[n - 1] - s.pts[n - 3],
    );
    ctx.lineCap = 'round';
    ctx.strokeStyle = INK_COLOR;
    ctx.lineWidth = velocityWidth(s.w, d);
    ctx.beginPath();
    ctx.moveTo(s.pts[n - 4], s.pts[n - 3]);
    ctx.lineTo(s.pts[n - 2], s.pts[n - 1]);
    ctx.stroke();
  }

  eraseAt(wx: number, wy: number) {
    let before = this.strokes.length;
    this.strokes = this.strokes.filter(
      (s) => !strokeNearPoint(s, wx, wy, ERASER_RADIUS / this.zoom + 4),
    );
    if (this.strokes.length !== before) {
      this.strokeCount = this.strokes.length;
      this.redraw();
    }
  }

  pushUndo() {
    this.undoStack.push(serializeInk({ v: 1, strokes: this.strokes }));
    if (this.undoStack.length > UNDO_DEPTH) {
      this.undoStack.shift();
    }
  }

  undo = () => {
    let prev = this.undoStack.pop();
    if (prev === undefined) {
      return;
    }
    this.strokes = parseInk(prev).strokes;
    this.strokeCount = this.strokes.length;
    this.redraw();
    this.scheduleSave();
  };

  armClear = () => {
    if (!this.clearArmed) {
      this.clearArmed = true;
      window.clearTimeout(this.clearArmTimer);
      this.clearArmTimer = window.setTimeout(() => {
        this.clearArmed = false;
      }, 3000);
      return;
    }
    window.clearTimeout(this.clearArmTimer);
    this.clearArmed = false;
    this.pushUndo();
    // "erase everything" means everything: ink, draft, AND accepted echoes
    let model = this.args.model;
    let prevInk = serializeInk({ v: 1, strokes: this.strokes });
    let prevEchoes = (model?.echoes ?? []).filter(Boolean);
    this.strokes = [];
    this.strokeCount = 0;
    this.draft = null;
    this.autoDot = null;
    this.echoBaselineCount = 0;
    this.autoSuppressedBelow = 0;
    if (model && prevEchoes.length) {
      model.echoes = [];
    }
    this.dismissLasso();
    this.redraw();
    this.commitBoardState();
    this.toast = {
      message: 'Board cleared',
      undo: () => {
        this.strokes = parseInk(prevInk).strokes;
        this.strokeCount = this.strokes.length;
        this.echoBaselineCount = this.strokes.length;
        if (model && prevEchoes.length) {
          model.echoes = [...prevEchoes];
        }
        this.redraw();
        this.commitBoardState();
        this.toast = null;
        window.clearTimeout(this.toastTimer);
      },
    };
    window.clearTimeout(this.toastTimer);
    this.toastTimer = window.setTimeout(() => {
      this.toast = null;
    }, 8000);
  };

  // ---- persistence (debounced; never per-point) ----

  saveTask = restartableTask(async () => {
    await timeout(1500);
    let model = this.args.model;
    if (!model) {
      return;
    }
    model.inkJson = serializeInk({ v: 1, strokes: this.strokes });
    model.viewportJson = JSON.stringify({
      x: Math.round(this.panX),
      y: Math.round(this.panY),
      zoom: Math.round(this.zoom * 100) / 100,
    });
  });

  scheduleSave() {
    this.saveTask.perform();
  }

  // model writes that matter (accept/remove/move/clear) carry the FULL board
  // state in one commit — a save-triggered card reload must be able to
  // reconstitute everything, including ink still inside the debounce window
  commitBoardState() {
    let model = this.args.model;
    if (!model) {
      return;
    }
    this.saveTask.cancelAll();
    model.inkJson = serializeInk({ v: 1, strokes: this.strokes });
    model.viewportJson = JSON.stringify({
      x: Math.round(this.panX),
      y: Math.round(this.panY),
      zoom: Math.round(this.zoom * 100) / 100,
    });
  }

  // ---- lasso + echo ----

  closeLasso() {
    let pts = this.lassoPts;
    if (!pts || pts.length < 6) {
      this.lassoPts = null;
      return;
    }
    let captured = this.strokes.filter((s) => strokeInLasso(s, pts));
    let box = unionBBox(captured.map(strokeBBox));
    if (!box) {
      // nothing inside — treat as a miss, quietly reset
      this.lassoPts = null;
      this.lassoBBox = null;
      return;
    }
    this.lassoBBox = box;
  }

  dismissLasso = () => {
    this.lassoPts = null;
    this.lassoBBox = null;
    this.echoError = null;
  };

  get lassoPath(): string {
    let pts = this.lassoPts;
    if (!pts || pts.length < 4) {
      return '';
    }
    // the svg sits at (-4000, -4000) so ink at negative world coords still renders
    let d = `M ${pts[0] + 4000} ${pts[1] + 4000}`;
    for (let i = 2; i < pts.length; i += 2) {
      d += ` L ${pts[i] + 4000} ${pts[i + 1] + 4000}`;
    }
    if (this.lassoBBox) {
      d += ' Z';
    }
    return d;
  }

  get puckStyle(): SafeString {
    let box = this.lassoBBox;
    if (!box) {
      return htmlSafe('display: none');
    }
    return htmlSafe(`left: ${box.minX}px; top: ${box.maxY + 18}px`);
  }

  get scanStyle(): SafeString {
    let box = this.lassoBBox;
    if (!box) {
      return htmlSafe('display: none');
    }
    return htmlSafe(
      `left: ${box.minX - 8}px; top: ${box.minY - 8}px; width: ${
        box.maxX - box.minX + 16
      }px; height: ${box.maxY - box.minY + 16}px`,
    );
  }

  // ambient scanning: after a pause in writing, quietly offer an echo on the
  // fresh ink — the dot costs nothing; the request is only sent on click
  autoScanTask = restartableTask(async () => {
    await timeout(AUTO_IDLE_MS);
    if (
      !this.autoEnabled ||
      this.draft ||
      this.echoError ||
      this.lassoBBox ||
      this.echoTask.isRunning ||
      this.strokes.length < this.autoSuppressedBelow
    ) {
      return;
    }
    let fresh = this.freshStrokes();
    if (fresh.length < AUTO_MIN_STROKES) {
      return;
    }
    let box = unionBBox(fresh.map(strokeBBox));
    if (!box || (box.maxX - box.minX) * (box.maxY - box.minY) < AUTO_MIN_AREA) {
      return;
    }
    this.autoDot = { x: box.maxX + 18, y: box.minY - 6, box };
    // grace window: help arrives on its own unless dismissed (or clicked sooner)
    await timeout(AUTO_GRACE_MS);
    if (
      this.autoDot &&
      this.autoEnabled &&
      !this.draft &&
      !this.echoError &&
      !this.echoTask.isRunning
    ) {
      this.expandAutoDot();
    }
  });

  freshStrokes(): InkStroke[] {
    let base = Math.min(this.echoBaselineCount, this.strokes.length);
    return this.strokes.slice(base);
  }

  get autoDotStyle(): SafeString {
    let d = this.autoDot;
    if (!d) {
      return htmlSafe('display: none');
    }
    return htmlSafe(`left: ${d.x}px; top: ${d.y}px`);
  }

  toggleAuto = () => {
    this.autoEnabled = !this.autoEnabled;
    if (!this.autoEnabled) {
      this.autoDot = null;
    }
  };

  dismissAutoDot = () => {
    this.autoDot = null;
    // stay quiet until a few more strokes of genuinely new ink arrive
    this.autoSuppressedBelow = this.strokes.length + AUTO_MIN_STROKES;
  };

  expandAutoDot = () => {
    let dot = this.autoDot;
    if (!dot) {
      return;
    }
    let b = dot.box;
    this.lassoBBox = b;
    this.lassoPts = [
      b.minX,
      b.minY,
      b.maxX,
      b.minY,
      b.maxX,
      b.maxY,
      b.minX,
      b.maxY,
    ];
    this.autoDot = null;
    this.echoTask.perform('auto');
  };

  echoTask = restartableTask(async (mode: EchoModeKey) => {
    let box = this.lassoBBox;
    let lasso = this.lassoPts;
    let commandContext = this.args.context?.commandContext;
    if (!box || !lasso || !commandContext) {
      return;
    }
    this.echoError = null;
    this.draft = null;
    this.autoDot = null;
    this.lastEchoBBox = box;
    try {
      this.thinkingLabel = 'Reading your ink…';
      let capture = this.captureRegion(box, lasso);
      await timeout(350); // let the scan-line register before the request settles
      this.thinkingLabel = 'Thinking…';
      let input = new RecognizeInkInput();
      input.instructions = await this.loadMarkerInstructions();
      input.imageDataUrl = capture.dataUrl;
      input.mode = mode;
      input.boardName = this.args.model?.title ?? '';
      let result = await new RecognizeInkCommand(commandContext).execute(input);
      let sketchWorld: number[][] | null = null;
      let labelsWorld: EchoLabel[] | null = null;
      if (result.sketchJson) {
        let parsed = parseSketchJson(result.sketchJson);
        // basis detection must see every coordinate the model emitted
        let allCoords = [
          ...parsed.polylines.flat(),
          ...parsed.labels.flatMap((l) => [l.x, l.y]),
        ];
        if (parsed.polylines.length) {
          sketchWorld = mapPolylinesToWorld(
            parsed.polylines,
            box,
            CROP_MARGIN,
            capture.width,
            capture.height,
            allCoords,
          );
        }
        if (parsed.labels.length) {
          labelsWorld = mapLabelsToWorld(
            parsed.labels,
            allCoords,
            box,
            CROP_MARGIN,
            capture.width,
            capture.height,
          );
        }
      }
      let sceneJson = result.sceneJson ?? '';
      if (sceneJson) {
        try {
          let spec = JSON.parse(sceneJson);
          if (
            Array.isArray(spec?.steps) &&
            spec.steps.some((st: any) => st?.add === 'ink')
          ) {
            let captured = this.strokes.filter((st) =>
              strokeInLasso(st, lasso),
            );
            spec.ink = mapStrokesToManim(captured, box);
            sceneJson = JSON.stringify(spec);
          }
        } catch {
          // a malformed spec just plays without the ink object
        }
      }
      let place = this.draftPlacement(box);
      this.draft = {
        content: result.content ?? '',
        mode,
        sketchWorld,
        labelsWorld,
        sceneJson,
        x: place.x,
        y: place.y,
        width: DRAFT_WIDTH,
      };
      this.echoBaselineCount = this.strokes.length;
      this.lassoPts = null;
      this.lassoBBox = null;
    } catch (err: any) {
      let empty = /empty annotation/i.test(
        err instanceof Error ? err.message : String(err),
      );
      if (empty) {
        // the marker looked and had nothing to add — ambient silence, not an error
        this.dismissLasso();
        this.autoSuppressedBelow = this.strokes.length + AUTO_MIN_STROKES;
      } else {
        let place = this.draftPlacement(box);
        this.echoError = {
          message: friendlyEchoError(err),
          mode,
          x: place.x,
          y: place.y,
        };
      }
    } finally {
      this.thinkingLabel = null;
    }
  });

  startEcho = (mode: string) => {
    this.echoTask.perform(asEchoMode(mode));
  };

  cancelEcho = () => {
    this.echoTask.cancelAll();
    this.thinkingLabel = null;
  };

  retryEcho = () => {
    let err = this.echoError;
    if (!err || !this.lastEchoBBox) {
      return;
    }
    // restore the capture region so the retry has a lasso to read
    this.lassoBBox = this.lastEchoBBox;
    if (!this.lassoPts) {
      let b = this.lastEchoBBox;
      this.lassoPts = [
        b.minX,
        b.minY,
        b.maxX,
        b.minY,
        b.maxX,
        b.maxY,
        b.minX,
        b.maxY,
      ];
    }
    this.echoError = null;
    this.echoTask.perform(err.mode);
  };

  // The title block is docked bottom-right in SCREEN space; a slip placed in
  // world space can slide under it. Place to the right of the ink by default,
  // flip left when that would overflow, and lift clear of the docked block.
  draftPlacement(box: BBox): { x: number; y: number } {
    let el = this.boardEl;
    let x = box.maxX + 30;
    let y = box.minY;
    if (!el) {
      return { x, y };
    }
    let toScreenX = (wx: number) => wx * this.zoom + this.panX;
    let toScreenY = (wy: number) => wy * this.zoom + this.panY;
    let widthOnScreen = DRAFT_WIDTH * this.zoom;
    if (toScreenX(x) + widthOnScreen > el.clientWidth - 16) {
      x = box.minX - DRAFT_WIDTH - 30; // flip to the ink's left
    }
    let blockTop = el.clientHeight - TITLE_BLOCK_SCREEN.h;
    let blockLeft = el.clientWidth - TITLE_BLOCK_SCREEN.w;
    let overlapsBlock =
      toScreenY(y) + DRAFT_MIN_SCREEN_H > blockTop &&
      toScreenX(x) + widthOnScreen > blockLeft;
    if (overlapsBlock) {
      y = (blockTop - DRAFT_MIN_SCREEN_H - 12 - this.panY) / this.zoom;
    }
    return { x, y };
  }

  captureRegion(
    box: BBox,
    lasso: number[],
  ): { dataUrl: string; width: number; height: number } {
    let margin = CROP_MARGIN;
    let w = box.maxX - box.minX + margin * 2;
    let h = box.maxY - box.minY + margin * 2;
    let scale = Math.min(1, CROP_MAX_DIM / Math.max(w, h)) * 2;
    let off = document.createElement('canvas');
    off.width = Math.max(1, Math.round(w * scale));
    off.height = Math.max(1, Math.round(h * scale));
    let ctx = off.getContext('2d');
    if (!ctx) {
      throw new Error('Could not capture the board region.');
    }
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, off.width, off.height);
    ctx.setTransform(
      scale,
      0,
      0,
      scale,
      -(box.minX - margin) * scale,
      -(box.minY - margin) * scale,
    );
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = '#1a1a3a';
    let padded = expandBBox(box, margin);
    for (let s of this.strokes) {
      let sb = strokeBBox(s);
      let overlaps =
        sb.maxX >= padded.minX &&
        sb.minX <= padded.maxX &&
        sb.maxY >= padded.minY &&
        sb.minY <= padded.maxY;
      // include everything the user circled, plus nearby context inside the margin
      if (overlaps || strokeInLasso(s, lasso)) {
        this.strokePath(ctx, s);
      }
    }
    return {
      dataUrl: off.toDataURL('image/png'),
      width: off.width,
      height: off.height,
    };
  }

  // ---- draft / accepted echoes ----

  get echoNotes() {
    let list = this.args.model?.echoes ?? [];
    return list.filter(Boolean).map((note, index) => {
      let override =
        this.noteDrag && this.noteDrag.index === index ? this.noteDrag : null;
      let parsed = parseSketchJson(note.sketchJson);
      return {
        note,
        index,
        sketchOverlay: sketchOverlay(
          parsed.polylines.length ? parsed.polylines : null,
          parsed.labels,
        ),
        style: htmlSafe(
          `left: ${override?.x ?? note.x ?? 0}px; top: ${
            override?.y ?? note.y ?? 0
          }px; width: ${note.width ?? DRAFT_WIDTH}px`,
        ),
      };
    });
  }

  get draftStyle(): SafeString {
    let d = this.draft;
    if (!d) {
      return htmlSafe('display: none');
    }
    return htmlSafe(`left: ${d.x}px; top: ${d.y}px; width: ${d.width}px`);
  }

  get errorStyle(): SafeString {
    let s = this.echoError;
    if (!s) {
      return htmlSafe('display: none');
    }
    return htmlSafe(`left: ${s.x}px; top: ${s.y}px; width: ${DRAFT_WIDTH}px`);
  }

  get draftSketchOverlay(): {
    style: SafeString;
    viewBox: string;
    paths: string[];
    texts: EchoLabel[];
  } | null {
    return sketchOverlay(
      this.draft?.sketchWorld ?? null,
      this.draft?.labelsWorld ?? [],
    );
  }

  get isEmpty(): boolean {
    return (
      this.strokeCount === 0 &&
      (this.args.model?.echoes ?? []).length === 0 &&
      !this.draft
    );
  }

  markerInstructions: string | null | undefined;

  // The marker's prose lives in the bundled Skill card so it can be read and
  // remixed as data. Only the component can reach the store (a plain realm
  // Command cannot), so the board resolves it and passes it to the command.
  async loadMarkerInstructions(): Promise<string> {
    if (this.markerInstructions !== undefined) {
      return this.markerInstructions ?? '';
    }
    this.markerInstructions = null;
    try {
      // @ts-expect-error import.meta is valid ESM but TS reads .gts as CJS
      let here: string = import.meta.url;
      let url = new URL('../Skill/echo-marker', here).href;
      let skill: any = await this.args.context?.store?.get?.(url);
      let text = skill?.instructions;
      if (typeof text === 'string' && text.trim().length > 40) {
        this.markerInstructions = text.trim();
      }
    } catch {
      // unreachable skill (remixed realm, offline) — the local grammar stands in
    }
    return this.markerInstructions ?? '';
  }

  // a linked Theme card means the host has injected semantic tokens into this
  // card's scope; only then may our tokens defer to them (otherwise the host's
  // default palette would erase the board's own identity)
  get themed(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
  }

  get lastInkLabel(): string {
    let notes = (this.args.model?.echoes ?? []).filter(Boolean);
    let latest = notes[notes.length - 1]?.acceptedAt;
    if (!latest) {
      return '—';
    }
    try {
      return new Date(latest as unknown as string).toLocaleDateString(
        undefined,
        {
          month: 'short',
          day: 'numeric',
        },
      );
    } catch {
      return '—';
    }
  }

  get boardLabel(): string {
    let echoes = (this.args.model?.echoes ?? []).length;
    return `Whiteboard with ${this.strokeCount} ink strokes and ${echoes} AI notes`;
  }

  acceptDraft = () => {
    let d = this.draft;
    let model = this.args.model;
    if (!d || !model) {
      return;
    }
    this.commitBoardState();
    let existing = (model.echoes ?? []).filter(Boolean);
    let note = new EchoNoteField({
      label: `Echo № ${existing.length + 1}`,
      mode: d.mode,
      content: d.content,
      sketchJson:
        d.sketchWorld || d.labelsWorld?.length
          ? JSON.stringify({
              polylines: d.sketchWorld ?? [],
              labels: d.labelsWorld ?? [],
            })
          : undefined,
      sceneJson: d.sceneJson || undefined,
      x: Math.round(d.x),
      y: Math.round(d.y),
      width: d.width,
      acceptedAt: new Date(),
    });
    model.echoes = [...existing, note];
    this.draft = null;
  };

  dismissDraft = () => {
    this.draft = null;
  };

  startDraftDrag = (event: Event) => {
    let e = event as PointerEvent;
    e.stopPropagation();
    let el = e.currentTarget as HTMLElement;
    try {
      el.setPointerCapture(e.pointerId);
    } catch {
      // see onPointerDown
    }
    this.activePointer = {
      kind: 'drag-draft',
      id: e.pointerId,
      lastX: e.clientX,
      lastY: e.clientY,
    };
  };

  startNoteDrag = (index: number, event: Event) => {
    let e = event as PointerEvent;
    e.stopPropagation();
    let el = e.currentTarget as HTMLElement;
    try {
      el.setPointerCapture(e.pointerId);
    } catch {
      // see onPointerDown
    }
    this.activePointer = {
      kind: 'drag-note',
      id: e.pointerId,
      lastX: e.clientX,
      lastY: e.clientY,
      noteIndex: index,
    };
  };

  commitNotePosition(drag: { index: number; x: number; y: number }) {
    let model = this.args.model;
    if (!model) {
      return;
    }
    let notes = (model.echoes ?? []).filter(Boolean);
    let target = notes[drag.index];
    if (!target) {
      return;
    }
    this.commitBoardState();
    target.x = Math.round(drag.x);
    target.y = Math.round(drag.y);
    model.echoes = [...notes];
  }

  removeNote = (index: number) => {
    let model = this.args.model;
    if (!model) {
      return;
    }
    let notes = (model.echoes ?? []).filter(Boolean);
    let removed = notes[index];
    if (!removed) {
      return;
    }
    this.commitBoardState();
    model.echoes = notes.filter((_, i) => i !== index);
    let label = removed.label ?? 'Echo';
    this.toast = {
      message: `${label} removed`,
      undo: () => {
        let current = (model.echoes ?? []).filter(Boolean);
        let restored = [...current];
        restored.splice(Math.min(index, restored.length), 0, removed);
        model.echoes = restored;
        this.toast = null;
        window.clearTimeout(this.toastTimer);
      },
    };
    window.clearTimeout(this.toastTimer);
    this.toastTimer = window.setTimeout(() => {
      this.toast = null;
    }, 6000);
  };

  undoToast = () => {
    this.toast?.undo();
  };

  stopEvent = (e: Event) => {
    e.stopPropagation();
  };

  echoModes = ECHO_MODES;

  <template>
    {{! a drawing surface: strokes start on pointerdown, overlays absorb it }}
    {{! template-lint-disable no-pointer-down-event-binding }}
    <section
      class='echo-pad {{if this.themed "themed"}}'
      aria-label='Echo Pad whiteboard'
    >

      {{! ruler toolbar }}
      <header class='ruler'>
        <div class='tools' role='radiogroup' aria-label='Drawing tools'>
          <button
            type='button'
            class='tool {{if (eq this.tool "pen") "active"}}'
            aria-pressed='{{if (eq this.tool "pen") "true" "false"}}'
            aria-label='Pen'
            title='Pen (P)'
            {{on 'click' (fn this.pickTool 'pen')}}
          ><PencilIcon class='tool-icon' /><span
              class='tool-name'
            >Pen</span></button>
          <button
            type='button'
            class='tool {{if (eq this.tool "eraser") "active"}}'
            aria-pressed='{{if (eq this.tool "eraser") "true" "false"}}'
            aria-label='Eraser'
            title='Eraser (E)'
            {{on 'click' (fn this.pickTool 'eraser')}}
          ><EraserIcon class='tool-icon' /><span
              class='tool-name'
            >Eraser</span></button>
          <button
            type='button'
            class='tool {{if (eq this.tool "lasso") "active"}}'
            aria-pressed='{{if (eq this.tool "lasso") "true" "false"}}'
            aria-label='Select'
            title='Select (S)'
            {{on 'click' (fn this.pickTool 'lasso')}}
          ><LassoIcon class='tool-icon' /><span
              class='tool-name'
            >Select</span></button>
          <button
            type='button'
            class='tool {{if (eq this.tool "pan") "active"}}'
            aria-pressed='{{if (eq this.tool "pan") "true" "false"}}'
            aria-label='Pan'
            title='Pan (H, or hold Space)'
            {{on 'click' (fn this.pickTool 'pan')}}
          ><HandIcon class='tool-icon' /><span
              class='tool-name'
            >Pan</span></button>
        </div>

        <div class='brand'>
          <button
            type='button'
            class='auto-toggle {{if this.autoEnabled "on"}}'
            aria-pressed='{{if this.autoEnabled "true" "false"}}'
            title='Ambient echo: after you pause writing, a dot offers help'
            {{on 'click' this.toggleAuto}}
          >
            {{if this.autoEnabled 'Auto ●' 'Auto ○'}}
          </button>
          <button
            type='button'
            class='clear-btn {{if this.clearArmed "armed"}}'
            {{on 'click' this.armClear}}
          >
            {{if
              this.clearArmed
              'Tap again to erase everything'
              '⌫ Clear board'
            }}
          </button>
          <span class='zoom-controls'>
            <button
              type='button'
              class='zoom-btn'
              aria-label='Zoom out'
              {{on 'click' this.zoomOut}}
            >−</button>
            <button
              type='button'
              class='zoom-btn zoom-pct'
              aria-label='Reset zoom to 100%'
              title='Reset zoom'
              {{on 'click' this.zoomReset}}
            >{{this.zoomPercent}}%</button>
            <button
              type='button'
              class='zoom-btn'
              aria-label='Zoom in'
              {{on 'click' this.zoomIn}}
            >+</button>
          </span>
          <span class='zoom'>undo ⌘Z</span>
          <span class='brand-name'>Echo Pad</span>
        </div>
      </header>

      {{! board }}
      <div
        class='board tool-{{this.tool}} {{if this.spaceHeld "space-pan"}}'
        {{this.setupBoard}}
        {{on 'pointerdown' this.onPointerDown}}
        {{on 'pointermove' this.onPointerMove}}
        {{on 'pointerup' this.onPointerUp}}
        {{on 'pointercancel' this.onPointerUp}}
        {{on 'wheel' this.onWheel}}
      >
        <canvas
          class='ink-layer'
          role='img'
          aria-label={{this.boardLabel}}
        ></canvas>

        {{! world-space overlays share the camera transform }}
        <div class='world' style={{this.worldTransform}}>

          <svg class='lasso-svg' width='8000' height='8000' aria-hidden='true'>
            <path d={{this.lassoPath}} class='lasso-path' />
          </svg>

          {{#if this.thinkingLabel}}
            <div class='scan' style={{this.scanStyle}}><i></i></div>
          {{/if}}

          {{! action puck at the lasso }}
          <div class='puck' style={{this.puckStyle}}>
            {{#if this.thinkingLabel}}
              <span class='puck-dot'></span>
              <span class='puck-thinking'>{{this.thinkingLabel}}</span>
              <button
                type='button'
                class='puck-x'
                aria-label='Cancel'
                {{on 'click' this.cancelEcho}}
                {{on 'pointerdown' this.stopEvent}}
              >✕ Cancel</button>
            {{else}}
              {{#each this.echoModes as |m|}}
                <button
                  type='button'
                  class='puck-mode'
                  {{on 'click' (fn this.startEcho m.key)}}
                  {{on 'pointerdown' this.stopEvent}}
                >{{m.label}}</button>
              {{/each}}
              <button
                type='button'
                class='puck-x'
                aria-label='Dismiss selection'
                {{on 'click' this.dismissLasso}}
                {{on 'pointerdown' this.stopEvent}}
              >✕</button>
            {{/if}}
          </div>

          {{! ambient auto-echo: the marker noticed — costs nothing until clicked }}
          {{#if this.autoDot}}
            <button
              type='button'
              class='auto-dot'
              style={{this.autoDotStyle}}
              aria-label='The marker noticed this — echo incoming'
              title='Echo incoming — click to run now, Esc to dismiss'
              {{on 'click' this.expandAutoDot}}
              {{on 'pointerdown' this.stopEvent}}
            ><i></i></button>
          {{/if}}

          {{! AI sketches ink directly onto the board, anchored to the region they answer }}
          {{#each this.echoNotes as |entry|}}
            {{#if entry.sketchOverlay}}
              <svg
                class='sketch-overlay'
                style={{entry.sketchOverlay.style}}
                viewBox={{entry.sketchOverlay.viewBox}}
                aria-hidden='true'
              >
                {{#each entry.sketchOverlay.paths as |d|}}
                  <path d={{d}} />
                {{/each}}
                {{#each entry.sketchOverlay.texts as |t|}}
                  <text
                    x={{t.x}}
                    y={{t.y}}
                    font-size={{t.size}}
                  >{{t.text}}</text>
                {{/each}}
              </svg>
            {{/if}}
          {{/each}}
          {{#if this.draftSketchOverlay}}
            <svg
              class='sketch-overlay ghost-sketch'
              style={{this.draftSketchOverlay.style}}
              viewBox={{this.draftSketchOverlay.viewBox}}
              aria-hidden='true'
            >
              {{#each this.draftSketchOverlay.paths as |d|}}
                <path d={{d}} />
              {{/each}}
              {{#each this.draftSketchOverlay.texts as |t|}}
                <text x={{t.x}} y={{t.y}} font-size={{t.size}}>{{t.text}}</text>
              {{/each}}
            </svg>
          {{/if}}

          {{! accepted echoes: red ink directly on the vellum }}
          {{#each this.echoNotes as |entry|}}
            <div
              class='echo-accepted'
              style={{entry.style}}
              {{on 'pointerdown' (fn this.startNoteDrag entry.index)}}
            >
              <div class='echo-stamp'>
                <span>{{if entry.note.label entry.note.label 'Echo'}}
                  ·
                  {{if entry.note.mode entry.note.mode 'solve'}}</span>
                <button
                  type='button'
                  class='echo-remove'
                  aria-label='Remove {{entry.note.label}}'
                  {{on 'click' (fn this.removeNote entry.index)}}
                  {{on 'pointerdown' this.stopEvent}}
                >✕</button>
              </div>
              {{#if entry.note.sceneJson}}
                <div class='scene-slip'>
                  <EchoScenePlayer @sceneJson={{entry.note.sceneJson}} />
                </div>
              {{/if}}
              <div class='echo-text'>{{entry.note.content}}</div>
            </div>
          {{/each}}

          {{! draft slip: taped on, not yet ink }}
          {{#if this.draft}}
            <div class='draft' style={{this.draftStyle}}>
              <div class='draft-tape' aria-hidden='true'></div>
              <div
                class='draft-grip'
                title='Drag to move'
                {{on 'pointerdown' this.startDraftDrag}}
              >⠿</div>
              <div class='draft-tag'>Echo draft · {{this.draft.mode}}</div>
              {{#if this.draft.sceneJson}}
                <div class='scene-slip'>
                  <EchoScenePlayer @sceneJson={{this.draft.sceneJson}} />
                </div>
              {{/if}}
              <div class='draft-text'>{{this.draft.content}}</div>
              <div class='draft-actions'>
                <button
                  type='button'
                  class='accept'
                  {{on 'click' this.acceptDraft}}
                  {{on 'pointerdown' this.stopEvent}}
                >✓ Accept</button>
                <button
                  type='button'
                  {{on 'click' this.dismissDraft}}
                  {{on 'pointerdown' this.stopEvent}}
                >✕ Dismiss</button>
              </div>
            </div>
          {{/if}}

          {{! error slip }}
          {{#if this.echoError}}
            <div class='draft error-slip' style={{this.errorStyle}}>
              <div class='draft-tag muted'>Echo · could not read</div>
              <div class='draft-text'>{{this.echoError.message}}</div>
              <div class='draft-actions'>
                <button
                  type='button'
                  class='accept'
                  {{on 'click' this.retryEcho}}
                  {{on 'pointerdown' this.stopEvent}}
                >↻ Retry</button>
                <button
                  type='button'
                  {{on 'click' this.dismissLasso}}
                  {{on 'pointerdown' this.stopEvent}}
                >✕ Dismiss</button>
              </div>
            </div>
          {{/if}}
        </div>

        {{! screen-space: empty-state ghost }}
        {{#if this.isEmpty}}
          <div class='ghost' aria-hidden='true'>
            <div class='ghost-line1'>Write a problem.</div>
            <div class='ghost-line2'>Circle it. Tap Solve.</div>
            <svg width='90' height='70' viewBox='0 0 90 70' class='ghost-lasso'>
              <path
                d='M8 35 C 18 10, 66 8, 76 30 C 84 48, 52 62, 26 54 C 12 50, 6 44, 8 35 Z'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
                stroke-dasharray='7 6'
                stroke-linecap='round'
              />
            </svg>
          </div>
        {{/if}}

        {{! title block }}
        <div class='titleblock'>
          <div class='tb-row'>
            <div class='tb-cell tb-wide'>
              <span class='tb-k'>Board</span>
              <span class='tb-v tb-hand'>{{if
                  @model.title
                  @model.title
                  'Untitled board'
                }}</span>
            </div>
            <div class='tb-cell'>
              <span class='tb-k'>Last ink</span>
              <span class='tb-v'>{{this.lastInkLabel}}</span>
            </div>
          </div>
          <div class='tb-row'>
            <div class='tb-cell'>
              <span class='tb-k'>Strokes</span>
              <span class='tb-v'>{{this.strokeCount}}</span>
            </div>
            <div class='tb-cell'>
              <span class='tb-k'>Echoes</span>
              <span class='tb-v tb-red'>{{this.echoNotes.length}}</span>
            </div>
            <div class='tb-cell'>
              <span class='tb-k'>Zoom</span>
              <span class='tb-v'>{{this.zoomPercent}}%</span>
            </div>
          </div>
        </div>

        {{! toast + undo }}
        {{#if this.toast}}
          <div class='toast' role='status'>
            {{this.toast.message}}
            <button type='button' {{on 'click' this.undoToast}}>Undo</button>
          </div>
        {{/if}}
      </div>

    </section>
    <style scoped>
      @import url('https://fonts.googleapis.com/css2?family=Caveat:wght@400;600&family=IBM+Plex+Mono:wght@400;500;600&display=swap');

      .echo-pad {
        --paper: var(--ep-paper, #f7f4ec);
        --paper-raised: var(--ep-paper-raised, #fffdf5);
        --grid: var(--ep-grid, rgba(90, 120, 160, 0.14));
        --grid-major: var(--ep-grid-major, rgba(90, 120, 160, 0.28));
        --ink: var(--ep-ink, #2b3f8c);
        --echo: var(--ep-echo, #c33d2e);
        --chrome: var(--ep-chrome, #3a3527);
        --chrome-soft: var(--ep-chrome-soft, #6d6753);
        --edge: var(--ep-edge, #56503f);
        --tape: var(--ep-tape, rgba(226, 215, 178, 0.85));
        --font-hand: var(--ep-font-hand, 'Caveat', cursive);
        --font-chrome: var(--ep-font-chrome, 'IBM Plex Mono', monospace);
        height: 100%;
        display: flex;
        flex-direction: column;
        background: var(--paper);
        font-family: var(--font-chrome);
        color: var(--chrome);
      }

      /* the semantic tier engages ONLY when a Theme card is linked — otherwise
         the host's default palette would overwrite the board's own identity */
      .echo-pad.themed {
        --paper: var(--ep-paper, var(--background, #f7f4ec));
        --paper-raised: var(--ep-paper-raised, var(--card, #fffdf5));
        --ink: var(--ep-ink, var(--primary, #2b3f8c));
        --echo: var(--ep-echo, var(--accent, #c33d2e));
        --chrome: var(--ep-chrome, var(--foreground, #3a3527));
        --chrome-soft: var(--ep-chrome-soft, var(--muted-foreground, #6d6753));
        --edge: var(--ep-edge, var(--border, #56503f));
        --font-chrome: var(
          --ep-font-chrome,
          var(--font-mono, 'IBM Plex Mono', monospace)
        );
      }

      /* ---- ruler toolbar ---- */
      .ruler {
        position: relative;
        z-index: 4;
        flex: none;
        height: 52px;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 0 18px;
        background: linear-gradient(
          color-mix(in srgb, var(--paper) 88%, var(--chrome)),
          color-mix(in srgb, var(--paper) 72%, var(--chrome))
        );
        border-bottom: 1.5px solid var(--edge);
      }
      .tools {
        display: flex;
        gap: 8px;
      }
      .tool {
        height: 34px;
        padding: 0 12px;
        display: inline-flex;
        align-items: center;
        gap: 7px;
        border: 1.5px solid var(--edge);
        background: var(--paper);
        color: var(--chrome);
        font: 500 10.5px/1 var(--font-chrome);
        letter-spacing: 0.18em;
        text-transform: uppercase;
        cursor: pointer;
      }
      .tool.active {
        background: var(--ink);
        border-color: var(--ink);
        color: var(--paper);
      }
      .tool:focus-visible {
        outline: 2px solid var(--ink);
        outline-offset: 2px;
      }
      .tool-icon {
        width: 15px;
        height: 15px;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: 14px;
        margin-left: auto;
      }
      .auto-toggle {
        border: 1.5px solid var(--edge);
        background: var(--paper);
        color: var(--chrome-soft);
        font: 600 9.5px/1 var(--font-chrome);
        letter-spacing: 0.16em;
        text-transform: uppercase;
        padding: 9px 12px;
        cursor: pointer;
      }
      .auto-toggle.on {
        color: var(--echo);
        border-color: var(--echo);
      }
      .clear-btn {
        border: 1.5px solid var(--edge);
        background: var(--paper);
        color: var(--chrome);
        font: 600 9.5px/1 var(--font-chrome);
        letter-spacing: 0.16em;
        text-transform: uppercase;
        padding: 9px 12px;
        cursor: pointer;
      }
      .clear-btn.armed {
        background: var(--echo);
        border-color: var(--echo);
        color: var(--paper-raised);
      }
      .zoom {
        font: 400 10.5px/1 var(--font-chrome);
        color: var(--chrome-soft);
        letter-spacing: 0.1em;
      }
      .zoom-controls {
        display: inline-flex;
        align-items: stretch;
        border: 1.5px solid var(--edge);
        background: var(--paper);
      }
      .zoom-btn {
        border: none;
        background: none;
        color: var(--chrome);
        font: 600 11px/1 var(--font-chrome);
        padding: 9px 10px;
        cursor: pointer;
      }
      .zoom-btn + .zoom-btn {
        border-left: 1.5px solid var(--edge);
      }
      .zoom-pct {
        min-width: 52px;
        letter-spacing: 0.08em;
        color: var(--chrome-soft);
      }
      .brand-name {
        font: 600 12px/1 var(--font-chrome);
        letter-spacing: 0.3em;
        text-transform: uppercase;
      }

      /* ---- board ---- */
      .board {
        position: relative;
        flex: 1;
        min-height: 0;
        overflow: hidden;
        touch-action: none;
        background-color: var(--paper);
        background-image:
          linear-gradient(var(--grid) 1px, transparent 1px),
          linear-gradient(90deg, var(--grid) 1px, transparent 1px),
          linear-gradient(var(--grid-major) 1px, transparent 1px),
          linear-gradient(90deg, var(--grid-major) 1px, transparent 1px);
        background-size:
          16px 16px,
          16px 16px,
          80px 80px,
          80px 80px;
        cursor: crosshair;
      }
      .board.tool-pan,
      .board.space-pan {
        cursor: grab;
      }
      .board.tool-eraser {
        cursor: cell;
      }
      .ink-layer {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
      }
      .world {
        position: absolute;
        left: 0;
        top: 0;
        width: 0;
        height: 0;
        transform-origin: 0 0;
        z-index: 2;
      }
      .lasso-svg {
        position: absolute;
        left: -4000px;
        top: -4000px;
        width: 8000px;
        height: 8000px;
        max-width: none;
        overflow: visible;
        pointer-events: none;
      }
      .lasso-path {
        fill: rgba(195, 61, 46, 0.03);
        stroke: var(--echo);
        stroke-width: 2;
        stroke-dasharray: 9 8;
        stroke-linecap: round;
        vector-effect: non-scaling-stroke;
      }

      .scan {
        position: absolute;
        overflow: hidden;
        pointer-events: none;
      }
      .scan i {
        position: absolute;
        top: 0;
        bottom: 0;
        width: 1.5px;
        background: rgba(195, 61, 46, 0.75);
        box-shadow:
          -14px 0 18px rgba(195, 61, 46, 0.12),
          -3px 0 6px rgba(195, 61, 46, 0.25);
        animation: ep-scan 2.2s ease-in-out infinite;
      }
      @keyframes ep-scan {
        from {
          left: 3%;
        }
        to {
          left: 97%;
        }
      }

      /* ---- puck ---- */
      .puck {
        position: absolute;
        display: flex;
        align-items: stretch;
        border: 1.5px solid var(--edge);
        background: var(--paper);
        box-shadow: 4px 4px 0 rgba(60, 55, 40, 0.25);
        white-space: nowrap;
      }
      .puck button {
        border: none;
        background: none;
        cursor: pointer;
        font: 600 11px/1 var(--font-chrome);
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: var(--chrome);
        padding: 11px 14px;
        border-left: 1.5px solid var(--edge);
      }
      .puck button:first-child {
        border-left: none;
      }
      .puck .puck-mode:hover,
      .puck .puck-mode:focus-visible {
        background: var(--echo);
        color: var(--paper-raised);
        outline: none;
      }
      .puck .puck-x {
        color: var(--chrome-soft);
      }
      .puck-dot {
        align-self: center;
        width: 8px;
        height: 8px;
        margin-left: 12px;
        border-radius: 50%;
        background: var(--echo);
        box-shadow: 0 0 0 3px rgba(195, 61, 46, 0.18);
        animation: ep-pulse 1.2s ease-in-out infinite;
      }
      @keyframes ep-pulse {
        50% {
          opacity: 0.4;
        }
      }
      .puck-thinking {
        align-self: center;
        padding: 0 4px 0 10px;
        font: 600 10px/1 var(--font-chrome);
        letter-spacing: 0.18em;
        text-transform: uppercase;
      }

      /* ---- the noticing dot ---- */
      .auto-dot {
        position: absolute;
        width: 26px;
        height: 26px;
        border: none;
        background: none;
        padding: 0;
        cursor: pointer;
      }
      .auto-dot i {
        position: absolute;
        inset: 6px;
        border-radius: 50%;
        background: var(--echo);
        box-shadow: 0 0 0 0 rgba(195, 61, 46, 0.35);
        animation: ep-notice 1.6s ease-out infinite;
      }
      @keyframes ep-notice {
        0% {
          box-shadow: 0 0 0 0 rgba(195, 61, 46, 0.35);
        }
        70% {
          box-shadow: 0 0 0 10px rgba(195, 61, 46, 0);
        }
        100% {
          box-shadow: 0 0 0 0 rgba(195, 61, 46, 0);
        }
      }
      .auto-dot:focus-visible i {
        outline: 2px solid var(--echo);
        outline-offset: 3px;
      }

      .scene-slip {
        width: 100%;
        aspect-ratio: 16 / 10;
        margin: 4px 0 10px;
        border: 1.5px solid var(--edge);
        box-shadow: 4px 4px 0 rgba(60, 55, 40, 0.25);
        overflow: hidden;
      }
      .sketch-overlay {
        position: absolute;
        max-width: none;
        overflow: visible;
        pointer-events: none;
      }
      .sketch-overlay path {
        fill: none;
        stroke: var(--echo);
        stroke-width: 2.4;
        stroke-linecap: round;
        stroke-linejoin: round;
      }
      .sketch-overlay text {
        font-family: var(--font-hand);
        font-weight: 600;
        fill: var(--echo);
        dominant-baseline: hanging;
      }
      .ghost-sketch text {
        opacity: 0.55;
      }
      .ghost-sketch path {
        opacity: 0.55;
        stroke-dasharray: 7 5;
      }

      /* ---- accepted echoes ---- */
      .echo-accepted {
        position: absolute;
        cursor: grab;
      }
      .echo-stamp {
        display: flex;
        align-items: center;
        gap: 8px;
        font: 600 9px/1 var(--font-chrome);
        letter-spacing: 0.24em;
        text-transform: uppercase;
        color: rgba(195, 61, 46, 0.65);
        margin-bottom: 5px;
      }
      .echo-remove {
        border: none;
        background: none;
        color: rgba(195, 61, 46, 0.45);
        font: 500 10px/1 var(--font-chrome);
        cursor: pointer;
        padding: 2px 4px;
        opacity: 0;
      }
      .echo-accepted:hover .echo-remove,
      .echo-remove:focus-visible {
        opacity: 1;
      }
      .echo-text {
        font-family: var(--font-hand);
        font-size: 24px;
        line-height: 1.25;
        color: var(--echo);
        white-space: pre-wrap;
      }

      /* ---- draft / error slips ---- */
      .draft {
        position: absolute;
        background: var(--paper-raised);
        border: 1px solid #eae4d2;
        padding: 20px 22px 16px;
        transform: rotate(1.2deg);
        box-shadow:
          0 14px 30px rgba(50, 40, 20, 0.28),
          0 2px 6px rgba(50, 40, 20, 0.18);
        animation: ep-slip-in 0.35s ease-out;
      }
      @keyframes ep-slip-in {
        from {
          opacity: 0;
          transform: rotate(1.2deg) translateY(-8px);
        }
      }
      .draft-tape {
        position: absolute;
        top: -11px;
        left: 50%;
        width: 96px;
        height: 22px;
        transform: translateX(-50%) rotate(-2deg);
        background: var(--tape);
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.12);
      }
      .draft-grip {
        position: absolute;
        top: 8px;
        right: 10px;
        color: rgba(60, 55, 40, 0.4);
        cursor: grab;
        font-size: 13px;
        letter-spacing: 2px;
        padding: 2px 4px;
      }
      .draft-tag {
        display: flex;
        align-items: center;
        gap: 10px;
        font: 600 9.5px/1 var(--font-chrome);
        letter-spacing: 0.26em;
        text-transform: uppercase;
        color: var(--echo);
        margin-bottom: 10px;
      }
      .draft-tag::after {
        content: '';
        flex: 1;
        height: 1px;
        background: rgba(195, 61, 46, 0.35);
      }
      .draft-tag.muted {
        color: var(--chrome-soft);
      }
      .draft-tag.muted::after {
        background: rgba(109, 103, 83, 0.35);
      }
      .draft-text {
        font-family: var(--font-hand);
        font-size: 24px;
        line-height: 1.25;
        color: var(--echo);
        white-space: pre-wrap;
      }
      .error-slip .draft-text {
        color: var(--chrome);
        font-size: 22px;
      }
      .draft-actions {
        display: flex;
        gap: 10px;
        margin-top: 16px;
      }
      .draft-actions button {
        font: 600 10px/1 var(--font-chrome);
        letter-spacing: 0.2em;
        text-transform: uppercase;
        padding: 9px 14px;
        border: 1.5px solid var(--echo);
        background: none;
        color: var(--echo);
        cursor: pointer;
      }
      .draft-actions button.accept {
        background: var(--echo);
        color: var(--paper-raised);
      }

      /* ---- ghost empty state ---- */
      .ghost {
        position: absolute;
        left: 14%;
        top: 30%;
        z-index: 1;
        color: rgba(43, 63, 140, 0.32);
        pointer-events: none;
      }
      .ghost-line1 {
        font-family: var(--font-hand);
        font-size: 32px;
        transform: rotate(-1deg);
      }
      .ghost-line2 {
        font-family: var(--font-hand);
        font-size: 22px;
        margin-top: 4px;
        transform: rotate(-0.4deg);
      }
      .ghost-lasso {
        position: absolute;
        right: -96px;
        top: 2px;
        color: rgba(195, 61, 46, 0.3);
      }

      /* ---- title block ---- */
      .titleblock {
        position: absolute;
        right: 0;
        bottom: 0;
        z-index: 3;
        min-width: 300px;
        border: 1.5px solid var(--ink);
        border-right: 0;
        border-bottom: 0;
        background: var(--paper);
        color: var(--ink);
      }
      .tb-row {
        display: flex;
        border-top: 1px solid rgba(43, 63, 140, 0.5);
      }
      .tb-row:first-child {
        border-top: 0;
      }
      .tb-cell {
        flex: 1;
        padding: 6px 12px 5px;
        border-left: 1px solid rgba(43, 63, 140, 0.5);
      }
      .tb-cell:first-child {
        border-left: 0;
      }
      .tb-wide {
        flex: 1.8;
      }
      .tb-k {
        display: block;
        font-size: 7.5px;
        letter-spacing: 0.22em;
        text-transform: uppercase;
        opacity: 0.65;
        margin-bottom: 2px;
      }
      .tb-v {
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.04em;
      }
      .tb-v.tb-hand {
        font-family: var(--font-hand);
        font-size: 17px;
      }
      .tb-v.tb-red {
        color: var(--echo);
      }

      /* ---- toast ---- */
      .toast {
        position: absolute;
        left: 18px;
        bottom: 16px;
        z-index: 4;
        display: flex;
        align-items: center;
        gap: 14px;
        background: var(--chrome);
        color: var(--paper);
        padding: 10px 14px;
        font: 500 10px/1 var(--font-chrome);
        letter-spacing: 0.12em;
        box-shadow: 0 8px 18px rgba(0, 0, 0, 0.3);
      }
      .toast button {
        border: none;
        background: none;
        color: #f0c775;
        font: 700 10px/1 var(--font-chrome);
        letter-spacing: 0.2em;
        text-transform: uppercase;
        cursor: pointer;
      }

      @media (prefers-reduced-motion: reduce) {
        .scan i,
        .puck-dot,
        .auto-dot i {
          animation: none;
        }
        .draft {
          animation: none;
        }
      }
    </style>
  </template>
}

function sketchOverlay(
  polylines: number[][] | null,
  labels: EchoLabel[] = [],
): {
  style: SafeString;
  viewBox: string;
  paths: string[];
  texts: EchoLabel[];
} | null {
  let lineBox = polylines?.length ? polylinesBBox(polylines) : null;
  let boxes: BBox[] = lineBox ? [lineBox] : [];
  for (let l of labels) {
    boxes.push({
      minX: l.x,
      minY: l.y,
      maxX: l.x + l.size * Math.max(1, l.text.length) * 0.62,
      maxY: l.y + l.size * 1.25,
    });
  }
  let box = unionBBox(boxes);
  if (!box) {
    return null;
  }
  let pad = 6;
  let w = Math.max(1, box.maxX - box.minX + pad * 2);
  let h = Math.max(1, box.maxY - box.minY + pad * 2);
  return {
    style: htmlSafe(
      `left: ${box.minX - pad}px; top: ${box.minY - pad}px; width: ${w}px; height: ${h}px`,
    ),
    viewBox: `${box.minX - pad} ${box.minY - pad} ${w} ${h}`,
    paths: polylines?.length ? polylinesToPaths(JSON.stringify(polylines)) : [],
    texts: labels,
  };
}

function expandBBox(box: BBox, margin: number): BBox {
  return {
    minX: box.minX - margin,
    minY: box.minY - margin,
    maxX: box.maxX + margin,
    maxY: box.maxY + margin,
  };
}

function velocityWidth(base: number, dist: number): number {
  return base * clamp(1.45 - dist / 28, 0.6, 1.35);
}

function friendlyEchoError(err: unknown): string {
  let raw = err instanceof Error ? err.message : String(err);
  if (/402|credit/i.test(raw)) {
    return "You're out of AI credits.";
  }
  if (/timeout|network|fetch/i.test(raw)) {
    return 'The request did not make it through — check your connection and retry.';
  }
  if (/empty annotation|could not read/i.test(raw)) {
    return "I couldn't read that — try circling a little more context.";
  }
  return "I couldn't read that — try circling a little more context.";
}
