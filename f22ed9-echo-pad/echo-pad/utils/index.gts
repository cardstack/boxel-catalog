// Pure ink-model, geometry, and echo-validation helpers. No card imports —
// keeps the module testable and lets the command's validation core run as
// plain functions.

import { extractSceneBlock, SCENE_GRAMMAR, type SceneSpec } from './scene';

export type InkStroke = {
  w: number; // base stroke width in world units
  pts: number[]; // flat [x0, y0, x1, y1, ...] in world coordinates
};

export type InkDoc = {
  v: 1;
  strokes: InkStroke[];
};

export type BBox = {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
};

export type EchoModeKey =
  | 'solve'
  | 'check'
  | 'complete'
  | 'explain'
  | 'animate'
  | 'auto';

export const ECHO_MODES: { key: EchoModeKey; label: string; ask: string }[] = [
  {
    key: 'solve',
    label: 'Solve',
    ask: 'Solve the problem shown in the handwriting. Show the key steps briefly, then the final answer.',
  },
  {
    key: 'check',
    label: 'Check',
    ask: "The handwriting contains the user's own worked solution or claim. Mark it like a kind but precise grader: if it is correct, reply with a short confirmation ending in ✓; if it is wrong, name the first incorrect step and give the corrected result ending in ✗ → the right answer.",
  },
  {
    key: 'complete',
    label: 'Complete',
    ask: 'The sketch or working is unfinished. Infer the intent and supply the missing part.',
  },
  {
    key: 'explain',
    label: 'Explain',
    ask: 'Explain what the handwriting and sketch describe, concisely, as an annotation.',
  },
  {
    key: 'animate',
    label: 'Animate',
    ask: 'Compose a short animation that shows the idea in motion. Strongly prefer a scene block; keep the annotation text to at most 2 short lines.',
  },
];

// 'auto' has no ECHO_MODES picker entry — the board runs it ambiently.
export function asEchoMode(v: unknown): EchoModeKey {
  return typeof v === 'string' &&
    (v === 'auto' || ECHO_MODES.some((m) => m.key === v))
    ? (v as EchoModeKey)
    : 'solve';
}

export const INK_COLOR = '#2b3f8c';
export const ECHO_COLOR = '#c33d2e';
export const ZOOM_MIN = 0.25;
export const ZOOM_MAX = 4;
export const ECHO_MAX_CHARS = 1200;

export const EMPTY_INK: InkDoc = { v: 1, strokes: [] };

export function serializeInk(doc: InkDoc): string {
  return JSON.stringify({
    v: 1,
    strokes: doc.strokes.map((s) => ({
      w: round1(s.w),
      pts: s.pts.map(round1),
    })),
  });
}

export function parseInk(json: string | undefined | null): InkDoc {
  if (!json) {
    return { v: 1, strokes: [] };
  }
  try {
    let raw = JSON.parse(json);
    let strokes = Array.isArray(raw?.strokes) ? raw.strokes : [];
    return {
      v: 1,
      strokes: strokes
        .filter(
          (s: any) =>
            s &&
            Array.isArray(s.pts) &&
            s.pts.length >= 4 &&
            s.pts.length % 2 === 0,
        )
        .map((s: any) => ({
          w: clamp(Number(s.w) || 2.5, 0.5, 24),
          pts: s.pts.map((n: any) => Number(n) || 0),
        })),
    };
  } catch {
    return { v: 1, strokes: [] };
  }
}

export function strokeBBox(stroke: InkStroke): BBox {
  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity;
  for (let i = 0; i < stroke.pts.length; i += 2) {
    let x = stroke.pts[i],
      y = stroke.pts[i + 1];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  return { minX, minY, maxX, maxY };
}

export function unionBBox(boxes: BBox[]): BBox | null {
  if (!boxes.length) {
    return null;
  }
  return boxes.reduce((a, b) => ({
    minX: Math.min(a.minX, b.minX),
    minY: Math.min(a.minY, b.minY),
    maxX: Math.max(a.maxX, b.maxX),
    maxY: Math.max(a.maxY, b.maxY),
  }));
}

export function pointInPolygon(x: number, y: number, poly: number[]): boolean {
  // poly is a flat [x0, y0, x1, y1, ...] ring
  let inside = false;
  let n = poly.length / 2;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    let xi = poly[i * 2],
      yi = poly[i * 2 + 1];
    let xj = poly[j * 2],
      yj = poly[j * 2 + 1];
    let intersects =
      yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;
    if (intersects) {
      inside = !inside;
    }
  }
  return inside;
}

export function strokeInLasso(stroke: InkStroke, lasso: number[]): boolean {
  // A stroke counts as captured when most of its points fall inside the ring.
  let total = stroke.pts.length / 2;
  if (total === 0 || lasso.length < 6) {
    return false;
  }
  let inside = 0;
  for (let i = 0; i < stroke.pts.length; i += 2) {
    if (pointInPolygon(stroke.pts[i], stroke.pts[i + 1], lasso)) {
      inside++;
    }
  }
  return inside / total >= 0.5;
}

export function strokeNearPoint(
  stroke: InkStroke,
  x: number,
  y: number,
  radius: number,
): boolean {
  let r2 = radius * radius;
  for (let i = 0; i + 3 < stroke.pts.length; i += 2) {
    if (
      segmentDistSq(
        x,
        y,
        stroke.pts[i],
        stroke.pts[i + 1],
        stroke.pts[i + 2],
        stroke.pts[i + 3],
      ) <= r2
    ) {
      return true;
    }
  }
  return false;
}

function segmentDistSq(
  px: number,
  py: number,
  ax: number,
  ay: number,
  bx: number,
  by: number,
): number {
  let dx = bx - ax,
    dy = by - ay;
  let lenSq = dx * dx + dy * dy;
  let t = lenSq === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / lenSq;
  t = clamp(t, 0, 1);
  let cx = ax + t * dx,
    cy = ay + t * dy;
  return (px - cx) * (px - cx) + (py - cy) * (py - cy);
}

export function clamp(n: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, n));
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

const AUTO_ASK =
  'Respond helpfully to whatever the ink is reaching for: solve a problem, answer a question, complete a sketch or list, or briefly explain — whichever fits. If nothing clearly calls for a response, reply with exactly NOTHING.';

const DRAW_HINT =
  ' If a small sketch genuinely helps (completing a diagram, drawing the missing part, an arrow, a quick plot), append one fenced block exactly like ```draw {"polylines":[[x1,y1,x2,y2,...]]}``` — coordinates are PIXELS in the image you were shown (0,0 = its top-left), so your lines land exactly where you place them on the drawing. At most 6 polylines. NEVER form characters out of polylines — to write numbers, words or expressions on the paper, add "write" entries to the same block: {"polylines":[...],"write":[{"text":"14","at":[x,y],"size":44}]} — at is the top-left of the text in image pixels, size its height in pixels; the board renders it in red handwriting exactly there. Use polylines only for shapes, arrows and plots.';

export function buildEchoPrompt(mode: EchoModeKey, boardName?: string): string {
  let ask =
    mode === 'auto'
      ? AUTO_ASK
      : (ECHO_MODES.find((x) => x.key === mode) ?? ECHO_MODES[0]).ask;
  return [
    'You are a red pen annotating a handwritten board',
    boardName ? ` titled "${boardName}"` : '',
    '. The image shows handwriting and rough sketches — it could be math, a question in words, a diagram, a list, or a half-formed idea. ',
    ask,
    ' Reply with the annotation text ONLY — no preamble, no markdown fences, no headings.',
    ' If math is involved, write it in plain unicode (v₀, θ, ², ×, ÷, ≈, √), never LaTeX.',
    ' Keep it under 8 short lines, sized for a margin note.',
    DRAW_HINT,
    mode === 'animate' || mode === 'auto' ? ' ' + SCENE_GRAMMAR : '',
  ]
    .filter(Boolean)
    .join('');
}

export function parseEchoResponse(
  raw: string | undefined | null,
): string | null {
  if (!raw) {
    return null;
  }
  let text = String(raw).trim();
  // strip a wrapping code fence if the model ignored instructions
  let fence = text.match(/^```[a-zA-Z]*\n([\s\S]*?)\n?```$/);
  if (fence) {
    text = fence[1].trim();
  }
  // drop common chat preambles on the first line
  text = text.replace(/^(sure|certainly|here('|')s)[^\n]*\n+/i, '').trim();
  if (!text) {
    return null;
  }
  if (text.length > ECHO_MAX_CHARS) {
    text = text.slice(0, ECHO_MAX_CHARS).trimEnd() + '…';
  }
  return text;
}

export const MAX_SKETCH_POLYLINES = 6;
const MAX_SKETCH_POINTS = 64;
export const MAX_SKETCH_LABELS = 4;
const MAX_LABEL_CHARS = 32;

// Models cannot hand-write legible characters out of raw polylines, so text
// answers travel as write-labels: the model picks the words and the spot, the
// board renders them in its own red handwriting.
export type EchoLabel = {
  text: string;
  x: number;
  y: number;
  size: number; // text height, same coordinate space as x/y
};

export type EchoSplit = {
  text: string | null;
  polylines: number[][] | null; // image-space, flat [x, y, ...] per line
  labels: EchoLabel[] | null; // image-space write-backs
  scene: SceneSpec | null; // validated manim scene spec, if the model composed one
};

export function splitEchoResponse(raw: string | undefined | null): EchoSplit {
  if (!raw) {
    return { text: null, polylines: null, labels: null, scene: null };
  }
  let extracted = extractSceneBlock(String(raw));
  let text = extracted.rest;
  let scene = extracted.spec;
  let polylines: number[][] | null = null;
  let labels: EchoLabel[] | null = null;
  let m = text.match(/```draw\s*([\s\S]*?)```/);
  if (m) {
    text = text.replace(m[0], '').trim();
    try {
      let spec = JSON.parse(m[1]);
      let lines = Array.isArray(spec?.polylines) ? spec.polylines : [];
      let valid = lines
        .filter(
          (l: any) =>
            Array.isArray(l) &&
            l.length >= 4 &&
            l.length % 2 === 0 &&
            l.every((n: any) => typeof n === 'number' && isFinite(n)),
        )
        .slice(0, MAX_SKETCH_POLYLINES)
        .map((l: number[]) =>
          l.slice(0, MAX_SKETCH_POINTS * 2).map((n) => clamp(n, 0, 8192)),
        );
      if (valid.length) {
        polylines = valid;
      }
      let writes = Array.isArray(spec?.write) ? spec.write : [];
      let validLabels = writes
        .filter(
          (w: any) =>
            w &&
            typeof w.text === 'string' &&
            w.text.trim().length &&
            Array.isArray(w.at) &&
            w.at.length >= 2 &&
            isFinite(Number(w.at[0])) &&
            isFinite(Number(w.at[1])),
        )
        .slice(0, MAX_SKETCH_LABELS)
        .map((w: any) => ({
          text: w.text.replace(/\s+/g, ' ').trim().slice(0, MAX_LABEL_CHARS),
          x: clamp(Number(w.at[0]), 0, 8192),
          y: clamp(Number(w.at[1]), 0, 8192),
          size: clamp(Number(w.size) || 44, 10, 240),
        }));
      if (validLabels.length) {
        labels = validLabels;
      }
    } catch {
      // malformed draw block: keep the text, drop the sketch
    }
  }
  let cleaned = parseEchoResponse(text);
  if (cleaned && /^nothing[.!]?$/i.test(cleaned)) {
    cleaned = null; // the auto mode's explicit "no response needed" signal
  }
  return { text: cleaned, polylines, labels, scene };
}

// sketchJson carries either the legacy bare polylines array or the current
// { polylines, labels } object — readers accept both.
export function parseSketchJson(json: string | undefined | null): {
  polylines: number[][];
  labels: EchoLabel[];
} {
  if (!json) {
    return { polylines: [], labels: [] };
  }
  try {
    let raw = JSON.parse(json);
    if (Array.isArray(raw)) {
      return {
        polylines: raw.filter((l: any) => Array.isArray(l)),
        labels: [],
      };
    }
    return {
      polylines: Array.isArray(raw?.polylines)
        ? raw.polylines.filter((l: any) => Array.isArray(l))
        : [],
      labels: Array.isArray(raw?.labels)
        ? raw.labels.filter(
            (w: any) =>
              w && typeof w.text === 'string' && isFinite(w.x) && isFinite(w.y),
          )
        : [],
    };
  } catch {
    return { polylines: [], labels: [] };
  }
}

export function polylinesToPaths(json: string | undefined | null): string[] {
  return parseSketchJson(json)
    .polylines.filter((l) => l.length >= 4)
    .map((l) => {
      let d = `M ${l[0]} ${l[1]}`;
      for (let i = 2; i < l.length; i += 2) {
        d += ` L ${l[i]} ${l[i + 1]}`;
      }
      return d;
    });
}

export function labelsFromSketchJson(
  json: string | undefined | null,
): EchoLabel[] {
  return parseSketchJson(json).labels;
}

export function mapLabelsToWorld(
  labels: EchoLabel[],
  allCoords: number[],
  box: BBox,
  margin: number,
  imageW: number,
  imageH: number,
): EchoLabel[] {
  let x0 = box.minX - margin;
  let y0 = box.minY - margin;
  let w = box.maxX - box.minX + margin * 2;
  let h = box.maxY - box.minY + margin * 2;
  let maxCoord = Math.max(...allCoords, 0);
  let basisX = maxCoord <= 105 ? 100 : Math.max(1, imageW);
  let basisY = maxCoord <= 105 ? 100 : Math.max(1, imageH);
  return labels.map((l) => ({
    text: l.text,
    x: x0 + (l.x / basisX) * w,
    y: y0 + (l.y / basisY) * h,
    size: (l.size / basisY) * h,
  }));
}

export function mapPolylinesToWorld(
  polylines: number[][],
  box: BBox,
  margin: number,
  imageW: number,
  imageH: number,
  basisCoords?: number[],
): number[][] {
  // the capture image spans box ± margin in world units. Models are asked for
  // image-pixel coordinates, but some reply normalized 0–100 — detect which.
  let x0 = box.minX - margin;
  let y0 = box.minY - margin;
  let w = box.maxX - box.minX + margin * 2;
  let h = box.maxY - box.minY + margin * 2;
  let maxCoord = Math.max(...(basisCoords ?? polylines.flat()), 0);
  let basisX = maxCoord <= 105 ? 100 : Math.max(1, imageW);
  let basisY = maxCoord <= 105 ? 100 : Math.max(1, imageH);
  return polylines.map((l) =>
    l.map((n, i) =>
      i % 2 === 0 ? x0 + (n / basisX) * w : y0 + (n / basisY) * h,
    ),
  );
}

export function polylinesBBox(polylines: number[][]): BBox | null {
  let pts = polylines.flat();
  if (pts.length < 4) {
    return null;
  }
  let minX = Infinity,
    minY = Infinity,
    maxX = -Infinity,
    maxY = -Infinity;
  for (let i = 0; i < pts.length; i += 2) {
    if (pts[i] < minX) minX = pts[i];
    if (pts[i] > maxX) maxX = pts[i];
    if (pts[i + 1] < minY) minY = pts[i + 1];
    if (pts[i + 1] > maxY) maxY = pts[i + 1];
  }
  return { minX, minY, maxX, maxY };
}

// A cheap deterministic key over the capture + mode. Not cryptographic — it
// only needs to distinguish one circled region from another within a session.
export function echoCacheKey(
  imageDataUrl: string,
  mode: string,
  promptSource = '',
): string {
  let h1 = 0x811c9dc5;
  let h2 = 0x01000193;
  let src = imageDataUrl + '\u0000' + promptSource;
  for (let i = 0; i < src.length; i++) {
    let c = src.charCodeAt(i);
    h1 = ((h1 ^ c) * 0x01000193) >>> 0;
    h2 = ((h2 + c) * 0x85ebca6b) >>> 0;
  }
  return `${mode}:${src.length}:${h1.toString(36)}${h2.toString(36)}`;
}
