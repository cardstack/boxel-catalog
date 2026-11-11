// Table geometry: where every visible copy sits, as percentages of the table.
// Layout data is in table units: x and w across a 100-unit width; y and h
// down a height of 100 / aspect. Narrow containers use each zone's `narrow`
// rect and the layout's narrowAspect instead.

import type { CompDef, Copy, GameData, Rect, State, ZoneSpec } from './engine';
import { defMap, effectiveDef, inZone, isVisible } from './engine';

export interface Placed {
  copy: Copy;
  def: CompDef | undefined; // undefined when hidden from the viewer
  kind: string;
  x: number; // % of table width (centre)
  y: number; // % of table height (centre)
  w: number; // % of table width
  rot: number;
  z: number;
  faceUp: boolean;
  zone: ZoneSpec;
}

export interface ZoneBox {
  zone: ZoneSpec;
  x: number;
  y: number;
  w: number;
  h: number; // all in % of the table box
}

export function aspectOf(game: GameData, narrow: boolean) {
  let l = game.layout;
  return narrow ? (l.narrowAspect ?? l.aspect ?? 1.5) : (l.aspect ?? 1.5);
}

export function rectOf(z: ZoneSpec, narrow: boolean): Rect {
  let r = narrow && z.narrow ? z.narrow : z;
  return { x: r.x ?? 0, y: r.y ?? 0, w: r.w ?? 10, h: r.h ?? 10 };
}

export function zoneBoxes(game: GameData, narrow: boolean): ZoneBox[] {
  let a = aspectOf(game, narrow);
  return game.layout.zones
    .filter((z) => !z.hidden)
    .map((zone) => {
      let r = rectOf(zone, narrow);
      return { zone, x: r.x, y: r.y * a, w: r.w, h: r.h * a };
    });
}

// Centre of a track square (1-based) inside the zone rect, in table units.
export function trackXY(z: ZoneSpec, r: Rect, sq: number) {
  let cols = z.cols ?? 10;
  let rows = Math.ceil((z.length ?? 100) / cols);
  let i = sq - 1;
  let row = Math.floor(i / cols);
  let col =
    z.path === 'row' || row % 2 === 0 ? i % cols : cols - 1 - (i % cols);
  let cw = r.w / cols;
  let ch = r.h / rows;
  return { x: r.x + (col + 0.5) * cw, y: r.y + r.h - (row + 0.5) * ch, cw, ch };
}

export function gridXY(z: ZoneSpec, r: Rect, pos: number, flip = false) {
  let cols = z.cols ?? 8;
  let rows = z.rows ?? 8;
  let file = pos % cols;
  let rank = Math.floor(pos / cols);
  if (flip) {
    file = cols - 1 - file;
    rank = rows - 1 - rank;
  }
  let cw = r.w / cols;
  let ch = r.h / rows;
  return {
    x: r.x + (file + 0.5) * cw,
    y: r.y + r.h - (rank + 0.5) * ch,
    cw,
    ch,
  };
}

// Little deterministic jitter so piles look hand-placed, not machine-stacked.
function hash(s: string) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++)
    h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return ((h >>> 0) % 1000) / 1000;
}

const STACK_SHOWN = 6;

export function placeCopies(
  game: GameData,
  state: State,
  viewer: string | null,
  narrow: boolean,
  opts: { flip?: boolean } = {},
): Placed[] {
  let a = aspectOf(game, narrow);
  let defs = defMap(game);
  let out: Placed[] = [];
  for (let z of game.layout.zones) {
    if (z.hidden) continue;
    let r = rectOf(z, narrow);
    let list = inZone(state, z.id).filter(
      (c) => defs.get(c.defId)?.kind !== 'board',
    );
    let pw = (narrow && z.narrow?.partW) || z.partW || 8;
    const push = (
      c: Copy,
      x: number,
      y: number,
      rot: number,
      zi: number,
      w = pw,
    ) => {
      let d = defs.get(effectiveDef(c));
      let seen = isVisible(c, viewer) && c.facing === 'up';
      out.push({
        copy: c,
        def: seen || d?.kind !== 'card' ? d : undefined,
        kind: d?.kind ?? 'card',
        x,
        y: y * a,
        w,
        rot: rot + (c.orientation ?? 0),
        z: zi,
        faceUp: seen,
        zone: z,
      });
    };
    let cx = r.x + r.w / 2;
    let cy = r.y + r.h / 2;
    switch (z.kind) {
      case 'stack': {
        let shown = list.slice(-STACK_SHOWN);
        shown.forEach((c, i) =>
          push(
            c,
            cx + i * 0.22,
            cy - i * 0.32,
            (hash(c.copyId) - 0.5) * 3,
            10 + i,
          ),
        );
        break;
      }
      case 'spread':
      case 'fan': {
        let n = list.length;
        let step = n > 1 ? Math.min(pw * 0.72, (r.w - pw) / (n - 1)) : 0;
        list.forEach((c, i) => {
          let off = i - (n - 1) / 2;
          let rot = z.kind === 'fan' ? off * 6 : (hash(c.copyId) - 0.5) * 2.5;
          let lift = z.kind === 'fan' ? Math.abs(off) * 0.6 : 0;
          push(c, cx + off * step, cy + lift, rot, 20 + i);
        });
        break;
      }
      case 'grid': {
        list.forEach((c) => {
          let g = gridXY(z, r, c.position, opts.flip);
          push(
            c,
            g.x,
            g.y,
            0,
            30 + (z.rows ?? 8) - Math.floor(c.position / (z.cols ?? 8)),
          );
        });
        break;
      }
      case 'track': {
        let bySquare = new Map<number, Copy[]>();
        for (let c of list)
          bySquare.set(c.position, [...(bySquare.get(c.position) ?? []), c]);
        for (let [sq, cs] of bySquare) {
          let t = trackXY(z, r, sq);
          cs.forEach((c, i) => {
            let n = cs.length;
            let dx = n > 1 ? (i - (n - 1) / 2) * t.cw * 0.28 : 0;
            let dy = n > 1 ? (i % 2 ? 1 : -1) * t.ch * 0.12 : 0;
            push(c, t.x + dx, t.y + dy, 0, 40 + i);
          });
        }
        break;
      }
      case 'pot': {
        let cell = pw * 1.15;
        let cols = Math.max(1, Math.floor(r.w / cell));
        list.forEach((c, i) => {
          let col = i % cols;
          let row = Math.floor(i / cols);
          let x =
            r.x + cell / 2 + col * cell + (hash(c.copyId) - 0.5) * pw * 0.15;
          let y = r.y + cell / 2 + row * cell * 0.9 + 1.5;
          push(
            c,
            cols === 1 ? cx : x,
            Math.min(y, r.y + r.h),
            (hash(c.copyId + 'r') - 0.5) * 14,
            20 + i,
          );
        });
        break;
      }
    }
  }
  return out;
}

// Table-relative point (0–100 % of width / height) → square under it.
export function squareAt(
  game: GameData,
  zoneId: string,
  narrow: boolean,
  px: number,
  py: number,
  flip = false,
) {
  let z = game.layout.zones.find((x) => x.id === zoneId);
  if (!z) return -1;
  let a = aspectOf(game, narrow);
  let r = rectOf(z, narrow);
  let x = px;
  let y = py / a;
  if (x < r.x || x > r.x + r.w || y < r.y || y > r.y + r.h) return -1;
  let cols = z.cols ?? 8;
  let rows = z.rows ?? 8;
  let file = Math.floor(((x - r.x) / r.w) * cols);
  let rank = rows - 1 - Math.floor(((y - r.y) / r.h) * rows);
  if (flip) {
    file = cols - 1 - file;
    rank = rows - 1 - rank;
  }
  return rank * cols + file;
}

export function squareCentre(
  game: GameData,
  zoneId: string,
  narrow: boolean,
  pos: number,
  flip = false,
) {
  let z = game.layout.zones.find((x) => x.id === zoneId)!;
  let a = aspectOf(game, narrow);
  let r = rectOf(z, narrow);
  let g = gridXY(z, r, pos, flip);
  return { x: g.x, y: g.y * a, w: g.cw, h: g.ch * a };
}

// Track squares as % points, for walking a token along its path.
export function trackPoint(
  game: GameData,
  zoneId: string,
  narrow: boolean,
  sq: number,
) {
  let z = game.layout.zones.find((x) => x.id === zoneId)!;
  let a = aspectOf(game, narrow);
  let r = rectOf(z, narrow);
  let t = trackXY(z, r, sq);
  return { x: t.x, y: t.y * a };
}

// Split a chip amount into denominations for drawing stacks.
export const DENOMS: [number, string][] = [
  [100, '#26221f'],
  [25, '#2f7a4f'],
  [10, '#2f5d8a'],
  [5, '#a8402f'],
  [1, '#ece4d4'],
];
export function chipStacks(amount: number) {
  let out: { value: number; colour: string; count: number }[] = [];
  let left = Math.max(0, Math.floor(amount));
  for (let [v, col] of DENOMS) {
    let n = Math.floor(left / v);
    if (n) out.push({ value: v, colour: col, count: Math.min(n, 12) });
    left -= n * v;
  }
  return out;
}
