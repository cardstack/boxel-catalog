// Whether each part is the shape it claims to be.
//
// Some primitives carry conventions the spec routinely gets wrong — a tube
// positions itself from its point list, a four-segment cone is a pyramid at
// 45 degrees. And a silhouette with a notch bitten out of it is the signature
// of a body modelled as several blocks that failed to meet.

import { hasNeutralAncestry, specBox } from '../spec-geometry';

// A few primitives carry their own geometry in "dimensions" rather than being
// placed by "position", and mixing the two double-offsets them. A tube's
// dimensions ARE its curve — [radius, x0,y0,z0, x1,y1,z1, …] in the node's own
// frame — so a tube given both a curve and a position lands nowhere near where
// its points say: a truck's exhaust run was authored along the hull's flank and
// then offset to y -1.26, ending up as a brown hook floating across the body.
// Repaired rather than reported, because the points are unambiguous about where
// the part goes.
export function repairPrimitiveConventions(parsed: any): string[] {
  let logs: string[] = [];
  for (let c of parsed?.components ?? []) {
    if (c?.primitive !== 'tube') continue;
    let p = Array.isArray(c.position) ? c.position.map(Number) : [];
    if (!p.length || p.every((n: number) => Math.abs(n || 0) < 0.001)) continue;
    logs.push(
      `zeroed the position of '${c.nodeId}' — a tube's points already place it`,
    );
    c.position = [0, 0, 0];
  }
  return logs;
}

// A part that was never built leaves a NOTCH: the object's height profile along
// its own length reads tower, valley, tower. A truck came back with a 1.03-tall
// cab at the front, a 0.95-tall engine at the back, and 1.1 units of nothing but
// 0.53-tall chassis between them, because the plan split one continuous body into
// three parts and the traced outline only covered the lowest of them.
//
// This is the shape-level counterpart of the buried-part check: there, a part
// exists but cannot be seen; here, the silhouette says a part should exist and
// none does. Real objects are full of steps and slopes, so a dip alone proves
// nothing — what does not happen by design is a LONG dip with taller structure on
// BOTH sides, which is why the test needs flanks rather than just a low spot.
//
// Report only. Which part is missing is a question about the photograph.
export function flagSilhouetteNotch(parsed: any): string[] {
  let logs: string[] = [];
  let all: any[] = parsed?.components ?? [];
  let byId = new Map<string, any>(all.map((c: any) => [c?.nodeId, c]));
  let boxes: { min: number[]; max: number[] }[] = [];
  for (let c of all) {
    if (!c?.nodeId || c.primitive === 'group') continue;
    if (/shadow/i.test(String(c.nodeId))) continue;
    if (
      c.primitive === 'glow' ||
      c.primitive === 'textDecal' ||
      c.primitive === 'curvedDecal'
    ) {
      continue;
    }
    if (!hasNeutralAncestry(c, byId)) continue;
    let box = specBox(c);
    if (!box) return logs; // an unmeasurable part means the profile is incomplete
    boxes.push(box);
  }
  if (boxes.length < 4) return logs;
  let lo = [0, 1, 2].map((a) => Math.min(...boxes.map((b) => b.min[a])));
  let hi = [0, 1, 2].map((a) => Math.max(...boxes.map((b) => b.max[a])));
  // walk the LONGEST horizontal axis — a vehicle's length, a building's frontage
  let axis = hi[0] - lo[0] >= hi[2] - lo[2] ? 0 : 2;
  let span = hi[axis] - lo[axis];
  if (!(span > 0.5)) return logs;
  // thin side parts (fenders, skirts, railings) run the whole length and would
  // paper over the gap, so only the central slab of the object is sampled
  let cross = axis === 0 ? 2 : 0;
  let mid = (lo[cross] + hi[cross]) / 2;
  let halfWidth = (hi[cross] - lo[cross]) / 2;
  const STEPS = 24;
  let profile: number[] = [];
  for (let i = 0; i < STEPS; i++) {
    let at = lo[axis] + (span * (i + 0.5)) / STEPS;
    let top = lo[1];
    for (let b of boxes) {
      if (at < b.min[axis] || at > b.max[axis]) continue;
      if (b.max[cross] < mid - halfWidth * 0.5) continue;
      if (b.min[cross] > mid + halfWidth * 0.5) continue;
      if (b.max[1] > top) top = b.max[1];
    }
    profile.push(top - lo[1]);
  }
  let tallest = Math.max(...profile);
  if (!(tallest > 0)) return logs;
  // the longest run that sits well under full height, with taller ground on both
  // sides — a dip at either END is a nose or a tail, not a hole
  const LOW = 0.65;
  let best: { from: number; to: number } | undefined;
  let i = 0;
  while (i < STEPS) {
    if (profile[i] >= tallest * LOW) {
      i++;
      continue;
    }
    let j = i;
    while (j < STEPS && profile[j] < tallest * LOW) j++;
    let flankedBefore = i > 0 && profile[i - 1] >= tallest * LOW;
    let flankedAfter = j < STEPS && profile[j] >= tallest * LOW;
    if (
      flankedBefore &&
      flankedAfter &&
      (!best || j - i > best.to - best.from)
    ) {
      best = { from: i, to: j };
    }
    i = j;
  }
  if (!best) return logs;
  let runLength = ((best.to - best.from) / STEPS) * span;
  // a short dip is a styling step between two masses; a long one is a hole
  if (runLength < span * 0.15) return logs;
  let dipHeight = Math.min(...profile.slice(best.from, best.to));
  logs.push(
    `the silhouette dips to ${dipHeight.toFixed(2)} for ${runLength.toFixed(2)} of its ${span.toFixed(2)} length, with ${tallest.toFixed(2)}-tall structure on both sides — that stretch of the body looks like a part nobody built`,
  );
  return logs;
}
