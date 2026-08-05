// Pure scene-spec machinery: the whitelisted grammar the model writes,
// the validator that normalizes/rejects specs, and a safe math-expression
// parser for function graphs. The model NEVER supplies executable code —
// everything here is data, deterministically interpreted.

import { clamp, type BBox, type InkStroke } from './index';

export const SCENE_MAX_STEPS = 16;
export const SCENE_MAX_DURATION = 4;

export type SceneAddStep = {
  add: string;
  id: string;
  [key: string]: unknown;
};

export type ScenePlayStep = {
  play: string;
  target?: string;
  [key: string]: unknown;
};

export type SceneStep = SceneAddStep | ScenePlayStep;

export type SceneSpec = {
  title: string;
  steps: SceneStep[];
  background: 'paper' | 'screen';
  ink?: number[][]; // the user's circled strokes in manim coords — injected by the board, never by the model
};

// ---- safe math expressions (recursive descent, no eval) ----

type Tok =
  | { kind: 'num'; value: number }
  | { kind: 'name'; value: string }
  | { kind: 'op'; value: string };

const FN_NAMES = ['sin', 'cos', 'tan', 'exp', 'log', 'sqrt', 'abs'] as const;
const FNS: Record<string, (n: number) => number> = {
  sin: Math.sin,
  cos: Math.cos,
  tan: Math.tan,
  exp: Math.exp,
  log: Math.log,
  sqrt: Math.sqrt,
  abs: Math.abs,
};

function tokenize(src: string): Tok[] | null {
  let toks: Tok[] = [];
  let i = 0;
  while (i < src.length) {
    let c = src[i];
    if (c === ' ' || c === '\t') {
      i++;
      continue;
    }
    if (/[0-9.]/.test(c)) {
      let j = i;
      while (j < src.length && /[0-9.]/.test(src[j])) j++;
      let n = Number(src.slice(i, j));
      if (!isFinite(n)) return null;
      toks.push({ kind: 'num', value: n });
      i = j;
      continue;
    }
    if (/[a-zA-Z]/.test(c)) {
      let j = i;
      while (j < src.length && /[a-zA-Z]/.test(src[j])) j++;
      toks.push({ kind: 'name', value: src.slice(i, j).toLowerCase() });
      i = j;
      continue;
    }
    if ('+-*/^()'.includes(c)) {
      toks.push({ kind: 'op', value: c });
      i++;
      continue;
    }
    return null; // anything else is rejected outright
  }
  return toks;
}

type Evaluator = (x: number) => number;

// grammar: expr → term ((+|-) term)* ; term → unary ((*|/|implicit) unary)* ;
// unary → -unary | power ; power → primary (^ unary)? ;
// primary → num | x | pi | e | fn(expr) | (expr)
export function compileExpression(src: string): Evaluator | null {
  let toks = tokenize(src ?? '');
  if (!toks || !toks.length || toks.length > 64) {
    return null;
  }
  let pos = 0;
  let peek = () => toks![pos];
  let take = () => toks![pos++];
  let failed = false;

  function primary(): Evaluator {
    let t = take();
    if (!t) {
      failed = true;
      return () => 0;
    }
    if (t.kind === 'num') {
      let v = t.value;
      return () => v;
    }
    if (t.kind === 'name') {
      if (t.value === 'x') return (x) => x;
      if (t.value === 'pi') return () => Math.PI;
      if (t.value === 'e') return () => Math.E;
      if ((FN_NAMES as readonly string[]).includes(t.value)) {
        let fn = FNS[t.value];
        let open = take();
        if (!open || open.kind !== 'op' || open.value !== '(') {
          failed = true;
          return () => 0;
        }
        let inner = expr();
        let close = take();
        if (!close || close.kind !== 'op' || close.value !== ')') {
          failed = true;
          return () => 0;
        }
        return (x) => fn(inner(x));
      }
      failed = true;
      return () => 0;
    }
    if (t.kind === 'op' && t.value === '(') {
      let inner = expr();
      let close = take();
      if (!close || close.kind !== 'op' || close.value !== ')') {
        failed = true;
        return () => 0;
      }
      return inner;
    }
    failed = true;
    return () => 0;
  }

  function unary(): Evaluator {
    let t = peek();
    if (t && t.kind === 'op' && t.value === '-') {
      take();
      let inner = unary();
      return (x) => -inner(x);
    }
    return power();
  }

  function power(): Evaluator {
    let base = primary();
    let t = peek();
    if (t && t.kind === 'op' && t.value === '^') {
      take();
      let exp = unary();
      return (x) => Math.pow(base(x), exp(x));
    }
    return base;
  }

  function startsPrimary(t: Tok | undefined): boolean {
    return (
      !!t &&
      (t.kind === 'num' ||
        t.kind === 'name' ||
        (t.kind === 'op' && t.value === '('))
    );
  }

  function term(): Evaluator {
    let left = unary();
    for (;;) {
      let t = peek();
      if (t && t.kind === 'op' && (t.value === '*' || t.value === '/')) {
        take();
        let right = unary();
        let op = t.value;
        let l = left;
        left = op === '*' ? (x) => l(x) * right(x) : (x) => l(x) / right(x);
        continue;
      }
      if (startsPrimary(t)) {
        // implicit multiplication: 2x, 2sin(x), x(x+1)
        let right = unary();
        let l = left;
        left = (x) => l(x) * right(x);
        continue;
      }
      return left;
    }
  }

  function expr(): Evaluator {
    let left = term();
    for (;;) {
      let t = peek();
      if (t && t.kind === 'op' && (t.value === '+' || t.value === '-')) {
        take();
        let right = term();
        let op = t.value;
        let l = left;
        left = op === '+' ? (x) => l(x) + right(x) : (x) => l(x) - right(x);
        continue;
      }
      return left;
    }
  }

  let compiled = expr();
  if (failed || pos !== toks.length) {
    return null;
  }
  let probe = compiled(0.5);
  if (typeof probe !== 'number') {
    return null;
  }
  return (x: number) => {
    let v = compiled(x);
    return isFinite(v) ? v : 0;
  };
}

// ---- spec validation ----

const ADD_TYPES = [
  'ink',
  'axes',
  'plane',
  'graph',
  'circle',
  'square',
  'rect',
  'line',
  'arrow',
  'vector',
  'dot',
  'text',
  'mathtex',
];
const PLAY_TYPES = [
  'create',
  'write',
  'fadeIn',
  'fadeOut',
  'transform',
  'rotate',
  'scale',
  'wave',
  'orbit',
  'indicate',
  'shear',
  'wait',
];

function asNum(v: unknown, min: number, max: number, dflt: number): number {
  let n = Number(v);
  return isFinite(n) ? clamp(n, min, max) : dflt;
}

function asRange(v: unknown, fallback: [number, number]): [number, number] {
  if (Array.isArray(v) && v.length >= 2) {
    let a = asNum(v[0], -20, 20, fallback[0]);
    let b = asNum(v[1], -20, 20, fallback[1]);
    return a < b ? [a, b] : fallback;
  }
  return fallback;
}

function asPoint(v: unknown): [number, number] | null {
  if (Array.isArray(v) && v.length >= 2) {
    let x = Number(v[0]);
    let y = Number(v[1]);
    if (isFinite(x) && isFinite(y)) {
      return [clamp(x, -20, 20), clamp(y, -20, 20)];
    }
  }
  return null;
}

function asColor(v: unknown): string | null {
  if (typeof v === 'string' && /^#[0-9a-fA-F]{3,8}$/.test(v)) {
    return v;
  }
  if (v === 'accent') {
    return 'accent';
  }
  return null;
}

export function validateSceneSpec(raw: unknown): SceneSpec | null {
  if (!raw || typeof raw !== 'object') {
    return null;
  }
  let title = String((raw as any).title ?? 'Scene').slice(0, 80);
  let steps = (raw as any).steps;
  if (!Array.isArray(steps) || !steps.length) {
    return null;
  }
  let out: SceneStep[] = [];
  let ids = new Set<string>();

  for (let step of steps.slice(0, SCENE_MAX_STEPS)) {
    if (!step || typeof step !== 'object') {
      continue;
    }
    if (typeof step.add === 'string' && ADD_TYPES.includes(step.add)) {
      let id = String(step.id ?? '').slice(0, 24);
      if (!id || ids.has(id)) {
        continue;
      }
      let s: SceneAddStep = { add: step.add, id };
      let at = asPoint(step.at);
      if (at) s.at = at;
      let color = asColor(step.color);
      if (color) s.color = color;
      switch (step.add) {
        case 'axes':
        case 'plane':
          s.xRange = asRange(step.xRange, [-5, 5]);
          s.yRange = asRange(step.yRange, [-3, 3]);
          break;
        case 'graph': {
          let fn = String(step.fn ?? '');
          if (!compileExpression(fn)) {
            continue; // unparseable function: drop the step
          }
          s.fn = fn.slice(0, 120);
          s.xRange = asRange(step.xRange, [-5, 5]);
          if (typeof step.axes === 'string') {
            s.axes = String(step.axes).slice(0, 24);
          }
          break;
        }
        case 'circle':
          s.radius = asNum(step.radius, 0.1, 12, 1.5);
          break;
        case 'square':
          s.side = asNum(step.side ?? step.sideLength, 0.1, 12, 2);
          break;
        case 'rect':
          s.w = asNum(step.w ?? step.width, 0.1, 14, 3);
          s.h = asNum(step.h ?? step.height, 0.1, 10, 2);
          break;
        case 'line':
        case 'arrow': {
          let from = asPoint(step.from);
          let to = asPoint(step.to);
          if (!from || !to) {
            continue;
          }
          s.from = from;
          s.to = to;
          break;
        }
        case 'vector': {
          let to = asPoint(step.to);
          if (!to) {
            continue;
          }
          s.to = to;
          break;
        }
        case 'dot':
          s.at = asPoint(step.at) ?? [0, 0];
          s.radius = asNum(step.radius, 0.04, 1, 0.12);
          break;
        case 'ink':
          break; // geometry arrives via spec.ink, injected by the board
        case 'text':
        case 'mathtex': {
          let value = String(step.value ?? '').slice(0, 120);
          if (!value.trim()) {
            continue;
          }
          s.value = value;
          break;
        }
      }
      ids.add(id);
      out.push(s);
      continue;
    }
    if (typeof step.play === 'string' && PLAY_TYPES.includes(step.play)) {
      let p: ScenePlayStep = { play: step.play };
      p.duration = asNum(step.duration, 0.2, SCENE_MAX_DURATION, 1);
      if (step.play === 'wait') {
        out.push(p);
        continue;
      }
      let target = String(step.target ?? '').slice(0, 24);
      if (!target || !ids.has(target)) {
        continue; // plays must reference something already added
      }
      p.target = target;
      switch (step.play) {
        case 'transform': {
          let to = String(step.to ?? '').slice(0, 24);
          if (!to || !ids.has(to)) {
            continue;
          }
          p.to = to;
          break;
        }
        case 'rotate':
          p.angle = asNum(step.angle, -6.4, 6.4, Math.PI);
          break;
        case 'scale':
          p.factor = asNum(step.factor ?? step.scaleFactor, 0.1, 6, 1.5);
          break;
        case 'wave':
          p.amplitude = asNum(step.amplitude, 0.05, 2, 0.4);
          break;
        case 'orbit': {
          let path = String(step.path ?? '').slice(0, 24);
          if (!path || !ids.has(path)) {
            continue;
          }
          p.path = path;
          break;
        }
        case 'shear': {
          let m = step.matrix;
          if (
            !Array.isArray(m) ||
            m.length !== 2 ||
            !m.every(
              (row: unknown) =>
                Array.isArray(row) &&
                row.length === 2 &&
                row.every((n: unknown) => isFinite(Number(n))),
            )
          ) {
            continue;
          }
          p.matrix = m.map((row: number[]) =>
            row.map((n) => clamp(Number(n), -10, 10)),
          );
          break;
        }
      }
      out.push(p);
    }
  }

  if (!out.some((s) => 'play' in s && s.play !== 'wait')) {
    return null; // a scene with nothing animated isn't a scene
  }
  let hasInk = out.some((s) => 'add' in s && (s as SceneAddStep).add === 'ink');
  let bg = (raw as any).background;
  let background: 'paper' | 'screen' =
    bg === 'paper' || bg === 'screen' ? bg : hasInk ? 'paper' : 'screen';
  let spec: SceneSpec = { title, steps: out, background };
  // pass through board-injected ink geometry, revalidated on every parse
  let rawInk = (raw as any).ink;
  if (hasInk && Array.isArray(rawInk)) {
    let ink = rawInk
      .filter((l: unknown) => Array.isArray(l) && (l as number[]).length >= 4)
      .slice(0, 24)
      .map((l: number[]) =>
        l.slice(0, 400).map((n) => clamp(Number(n) || 0, -8, 8)),
      );
    if (ink.length) {
      spec.ink = ink;
    }
  }
  return spec;
}

export function mapStrokesToManim(strokes: InkStroke[], box: BBox): number[][] {
  // fit the lassoed region into a 10×6 patch of manim units, y flipped
  let w = Math.max(1, box.maxX - box.minX);
  let h = Math.max(1, box.maxY - box.minY);
  let scale = Math.min(10 / w, 6 / h);
  let cx = (box.minX + box.maxX) / 2;
  let cy = (box.minY + box.maxY) / 2;
  return strokes.slice(0, 24).map((s) => {
    let out: number[] = [];
    for (let i = 0; i + 1 < s.pts.length && out.length < 400; i += 2) {
      out.push((s.pts[i] - cx) * scale, -(s.pts[i + 1] - cy) * scale);
    }
    return out;
  });
}

export function extractSceneBlock(raw: string): {
  rest: string;
  spec: SceneSpec | null;
} {
  let m = raw.match(/```scene\s*([\s\S]*?)```/);
  if (!m) {
    return { rest: raw, spec: null };
  }
  let rest = raw.replace(m[0], '').trim();
  try {
    return { rest, spec: validateSceneSpec(JSON.parse(m[1])) };
  } catch {
    return { rest, spec: null };
  }
}

// the grammar the model writes against — proven verbatim in the v3 spike
export const SCENE_GRAMMAR = [
  'If motion would explain the idea better than words, append ONE fenced block exactly like ```scene {"title":"...","steps":[...]}``` after your text.',
  ' Each step is one JSON object. Object steps: {"add":TYPE,"id":"unique",...props}. TYPE choices:',
  ' Prefer composing your own clean, precise graphs and diagrams — that is what makes the animation valuable. ink{} — the user\'s circled strokes as one object — should ONLY be used as the starting shape of a transform into the ideal form you draw (rough sketch morphs into the true curve); never animate the raw ink for its own sake · axes{xRange:[a,b],yRange:[a,b]} · plane{xRange,yRange} · graph{fn:"expr in x",axes:"axesId",xRange:[a,b]} · circle{radius} · square{side} · rect{w,h} · line{from:[x,y],to:[x,y]} · arrow{from,to} · vector{to:[x,y]} · dot{at:[x,y]} · text{value,at} · mathtex{value:"LaTeX",at}.',
  ' Optional props: color (hex), at:[x,y]. Coordinates are manim world units, roughly x -6..6, y -3.5..3.5, origin center.',
  ' Animation steps: {"play":KIND,"target":"id",...}: create · write · fadeIn · fadeOut · transform{to:"otherId"} · rotate{angle:radians} · scale{factor} · wave{amplitude} · orbit{path:"idOfCircleOrLine"} · indicate · shear{matrix:[[a,b],[c,d]]} · wait{duration}.',
  ' Every play may set duration in seconds (max 4). Max 16 steps. fn expressions may use x, sin, cos, tan, exp, log, sqrt, abs, pi — nothing else.',
  ' Example: ```scene {"title":"sine forms","steps":[{"add":"axes","id":"ax","xRange":[-5,5],"yRange":[-2,2]},{"add":"graph","id":"g","fn":"sin(x)","axes":"ax"},{"play":"create","target":"g","duration":2},{"play":"wave","target":"g","amplitude":0.4,"duration":2}]}```',
].join('');
