// Two parts trying to occupy one volume.
//
// Interpenetration and coplanarity look similar in the spec and completely
// different on screen: solids that overlap render as one lump, while flat
// parts sharing a plane z-fight and flicker as the camera moves. They are
// separated here because the fix differs — one is a placement error, the
// other needs a depth stagger the spec never thought to author.

import { hasNeutralAncestry, halfExtents, specBox } from '../spec-geometry';

// Copies of one feature that overlap each other fuse into a single lump, and
// because the overlapping faces are coincident they z-fight into a dark smear.
// A six-wheeled truck came out with a black streak where its wheels should be:
// each wheel was 1.10 across on an 0.85 axle spacing, so every neighbour ate a
// quarter of the one beside it.
//
// Two ways that happens, both measured off the part's own extents so no naming
// convention is involved:
//   1. a linear repeat whose step is shorter than the part it is repeating
//   2. copies authored INDIVIDUALLY (front / mid / rear wheel as three separate
//      components), which no repeat check would ever see — they are recognised
//      by having the same primitive and the same dimensions
// A linear repeat whose step is too short is REPAIRED (widen the step — copies
// must not overlap, unambiguous), while the individually-authored case is
// report-only, since collapsing three hand-placed wheels is not this pass's call.
export function flagInstanceCollisions(parsed: any): string[] {
  let logs: string[] = [];
  let all: any[] = parsed?.components ?? [];
  let byId = new Map<string, any>(all.map((c: any) => [c?.nodeId, c]));
  let components: any[] = all.filter(
    (c: any) => c?.nodeId && c.primitive !== 'group',
  );
  if (!components.length) return logs;
  // a repeat step is a LOCAL offset, so that half of the check is valid under
  // any parent; only the sibling-overlap half compares world boxes
  let worldOk = (c: any) => hasNeutralAncestry(c, byId);
  // parts are told to overlap their support by ~0.03, so a little contact
  // between copies is normal; a fifth of the part is not
  const TOLERATED = 0.2;

  // ---- 1. repeat steps shorter than the part
  for (let c of components) {
    let rep = c.repeat;
    if (typeof rep === 'string') {
      try {
        rep = JSON.parse(rep);
      } catch {
        continue;
      }
    }
    let count = Math.round(rep?.count ?? 0);
    if (!rep || count < 2) continue;
    let h = halfExtents(c);
    if (!h) continue;
    if (rep.mode === 'radial') {
      let radius = Math.abs(Number(rep.radius) || 0);
      let axis = rep.axis === 'x' ? 0 : rep.axis === 'z' ? 2 : 1;
      let inPlane = [0, 1, 2].filter((a) => a !== axis);
      // adjacent clones sit a chord apart; compare against the part's smaller
      // in-plane width, which is the one facing its neighbour
      let chord = 2 * radius * Math.sin(Math.PI / count);
      let width = 2 * Math.min(h[inPlane[0]], h[inPlane[1]]);
      if (width > 0 && chord < width * (1 - TOLERATED)) {
        logs.push(
          `'${c.nodeId}' repeats ${count}× around radius ${radius} but each is ${width.toFixed(2)} wide and only ${chord.toFixed(2)} apart — the ring will fuse`,
        );
      }
      continue;
    }
    let offset = Array.isArray(rep.offset) ? rep.offset.map(Number) : [];
    if (!offset.length) continue;
    let axis = offset.reduce(
      (best: number, v: number, i: number) =>
        Math.abs(v) > Math.abs(offset[best]) ? i : best,
      0,
    );
    let step = Math.abs(offset[axis] ?? 0);
    let extent = 2 * h[axis];
    if (extent <= 0) continue;
    if (step < 0.001) {
      logs.push(
        `'${c.nodeId}' repeats ${count}× with no offset — every copy lands on the same spot`,
      );
    } else if (step < extent * (1 - TOLERATED)) {
      // widen the step to the part's own size along the repeat axis, so the
      // copies stop fusing into a continuous band — a truck's 8 tires melting
      // into one tank track is the classic case. Direction is kept; only the
      // length grows. Repairable because the fix is unambiguous: copies must
      // not overlap.
      let sign = (offset[axis] ?? 0) < 0 ? -1 : 1;
      offset[axis] = Number((sign * extent).toFixed(4));
      rep.offset = offset;
      c.repeat = rep;
      logs.push(
        `widened '${c.nodeId}' repeat step ${step.toFixed(2)} → ${extent.toFixed(2)} so its ${count} copies stop fusing`,
      );
    }
  }

  // ---- 2. individually authored copies of the same feature
  let sig = (c: any) => {
    let h = halfExtents(c);
    if (!h) return undefined;
    return `${c.primitive}|${h.map((n) => n.toFixed(3)).join(',')}`;
  };
  let families = new Map<string, any[]>();
  for (let c of components) {
    if (!worldOk(c)) continue; // its position is local to a transformed parent
    let s = sig(c);
    if (!s) continue;
    if (!families.has(s)) families.set(s, []);
    families.get(s)!.push(c);
  }
  for (let family of families.values()) {
    if (family.length < 2) continue;
    let boxes = family.map((c) => {
      let h = halfExtents(c)!;
      let box = specBox(c)!;
      return { c, min: box.min, max: box.max, vol: 8 * h[0] * h[1] * h[2] };
    });
    let reported = 0;
    for (let i = 0; i < boxes.length && reported < 2; i++) {
      for (let j = i + 1; j < boxes.length && reported < 2; j++) {
        let a = boxes[i];
        let b = boxes[j];
        let overlap = [0, 1, 2].map((ax) =>
          Math.max(
            0,
            Math.min(a.max[ax], b.max[ax]) - Math.max(a.min[ax], b.min[ax]),
          ),
        );
        let volume = overlap[0] * overlap[1] * overlap[2];
        let share = volume / Math.max(0.000001, Math.min(a.vol, b.vol));
        if (share > TOLERATED / 2) {
          let axis = overlap.indexOf(Math.min(...overlap.filter((v) => v > 0)));
          logs.push(
            `'${a.c.nodeId}' and '${b.c.nodeId}' are the same part overlapping by ${overlap[axis].toFixed(2)} (${Math.round(share * 100)}%) — they will read as one lump`,
          );
          reported++;
        }
      }
    }
  }
  return logs;
}

// Coplanar overlapping faces have no depth order, so the renderer picks a winner
// per pixel from floating-point noise and the choice changes as the camera moves
// — the surface strobes. A starburst icon put all twelve rays at exactly
// z = 0.105; they converge at the hub, so the middle of the icon flickered in a
// checkerboard while everything else looked fine.
//
// Separating them by a hair gives the depth buffer something to sort by. The step
// is far below anything visible at these scales, so this cannot change how the
// object reads — it only removes the ambiguity. Flat artwork is where this bites,
// because that is where shapes deliberately share a plane; a solid assembly
// rarely has two faces at an identical depth by accident.
export function separateCoplanarLayers(parsed: any): string[] {
  let logs: string[] = [];
  let components: any[] = parsed?.components ?? [];
  if (components.length < 3) return logs;
  const STEP = 0.0005;
  // group by the z they sit at, to 4dp — parts an author placed on "the same
  // layer" rather than parts that merely happen to be close
  let layers = new Map<string, any[]>();
  for (let c of components) {
    if (!c?.nodeId || c.primitive === 'group') continue;
    // Only genuinely FLAT parts can be coplanar. A bottle's lathe body, its cap
    // and its shadow disc all sit at z = 0 because they are solids of revolution
    // centred on the axis — they share a centre, not a plane, and nudging them
    // apart would be meaningless. Require the part to be thin in z against its
    // own face: that is what a layer of artwork is and a stacked solid is not.
    let h = halfExtents(c);
    if (!h) continue;
    let face = Math.min(h[0], h[1]);
    if (!(face > 0) || h[2] > face * 0.25) continue;
    let p = Array.isArray(c.position) ? c.position.map(Number) : [0, 0, 0];
    let key = (p[2] || 0).toFixed(4);
    if (!layers.has(key)) layers.set(key, []);
    layers.get(key)!.push(c);
  }
  for (let [, members] of layers) {
    if (members.length < 2) continue;
    // only worth doing when they actually overlap in the plane; a row of
    // separate icons sharing a z is not fighting with anything
    let boxes = members.map((c) => specBox(c));
    let overlaps = false;
    for (let i = 0; i < boxes.length && !overlaps; i++) {
      for (let j = i + 1; j < boxes.length && !overlaps; j++) {
        let a = boxes[i];
        let b = boxes[j];
        if (!a || !b) continue;
        overlaps = [0, 1].every(
          (ax) => a.min[ax] < b.max[ax] && b.min[ax] < a.max[ax],
        );
      }
    }
    if (!overlaps) continue;
    members.forEach((c, i) => {
      if (i === 0) return;
      let p = Array.isArray(c.position) ? c.position.map(Number) : [0, 0, 0];
      c.position = [
        p[0] || 0,
        p[1] || 0,
        Number(((p[2] || 0) + STEP * i).toFixed(5)),
      ];
    });
    logs.push(
      `separated ${members.length} overlapping parts sharing one depth — they would have flickered against each other`,
    );
  }
  return logs;
}
