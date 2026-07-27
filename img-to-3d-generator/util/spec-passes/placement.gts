// Putting parts WHERE they belong.
//
// These passes move things: a part buried inside its neighbour, a wheel
// floating above the hull it should carry, a model hovering over or sunk
// through the ground plane, a part outside the envelope its plan measured.
// They read boxes through spec-geometry so they all agree about where a part
// currently is — two movers disagreeing about that is how a part gets pushed
// twice in opposite directions.

import { hasNeutralAncestry, halfExtents, specBox } from '../spec-geometry';

// The last line of defence, for when the plan and the spec are wrong the SAME
// way. An analysis wrote "wheels rests-on main hull body" — inverting which part
// carries which — the spec obeyed it, and every check passed: the wheels touched
// their host, sat inside the silhouette, were planned, were not hairline, were
// not buried. The truck simply had its tyres on the roof.
//
// What no plan can overrule is that a thing stands on its supports. A wheel, a
// track, a foot or a leg above the body's own midline is never a stylistic
// choice, so this is the one place where the parts' NAMES are worth reading:
// naming is exactly what the plan exists to carry, and the geometry alone cannot
// tell a wheel from a barrel.
//
// The repair mirrors the support to the other side of its host rather than
// dropping it to some invented height: the spec placed it the right DISTANCE
// from the body and only got the side wrong, so reflecting preserves the overlap
// the model intended (a wheel half-sunk into the flank stays half-sunk, just
// underneath).
export const SUPPORT_NAME =
  /\b(wheel|wheels|tyre|tire|track|tracks|caster|roller|foot|feet|leg|legs|skid|outrigger|castor)\b/i;

export function groundSupports(parsed: any): string[] {
  let logs: string[] = [];
  let all: any[] = parsed?.components ?? [];
  let byId = new Map<string, any>(all.map((c: any) => [c?.nodeId, c]));
  let components = all.filter(
    (c: any) =>
      c?.nodeId && c.primitive !== 'group' && hasNeutralAncestry(c, byId),
  );
  if (components.length < 2) return logs;
  let boxed = components
    .map((c) => {
      let h = halfExtents(c);
      let box = specBox(c);
      if (!h || !box) return undefined;
      return { c, min: box.min, max: box.max, vol: 8 * h[0] * h[1] * h[2] };
    })
    .filter(Boolean) as {
    c: any;
    min: number[];
    max: number[];
    vol: number;
  }[];
  if (boxed.length < 2) return logs;
  let isSupport = (c: any) =>
    SUPPORT_NAME.test(String(c.partRef ?? '')) ||
    SUPPORT_NAME.test(String(c.nodeId ?? ''));
  let supports = boxed.filter(
    (b) => isSupport(b.c) && !/glow/i.test(b.c.nodeId),
  );
  if (!supports.length) return logs;
  // the body is the biggest non-support volume — what the supports carry
  let body = boxed
    .filter((b) => !isSupport(b.c) && !/shadow/i.test(b.c.nodeId))
    .sort((a, b) => b.vol - a.vol)[0];
  if (!body) return logs;
  let bodyCenterY = (body.min[1] + body.max[1]) / 2;

  for (let s of supports) {
    let sCenterY = (s.min[1] + s.max[1]) / 2;
    if (sCenterY <= bodyCenterY) continue;
    let mirrored = bodyCenterY - (sCenterY - bodyCenterY);
    let dy = mirrored - sCenterY;
    let p = Array.isArray(s.c.position) ? s.c.position.map(Number) : [0, 0, 0];
    p[1] = Number(((p[1] || 0) + dy).toFixed(4));
    s.c.position = p;
    s.min[1] += dy;
    s.max[1] += dy;
    logs.push(
      `mirrored '${s.c.nodeId}' below '${body.c.nodeId}' (Δ ${dy.toFixed(2)} on y) — a support cannot sit above the body it carries`,
    );
  }

  // whatever the supports ended up as, they should be what the object stands on
  let lowestSupport = Math.min(...supports.map((s) => s.min[1]));
  for (let b of boxed) {
    if (isSupport(b.c) || /shadow/i.test(b.c.nodeId)) continue;
    if (b.min[1] < lowestSupport - 0.02) {
      logs.push(
        `'${b.c.nodeId}' hangs ${(lowestSupport - b.min[1]).toFixed(2)} below the supports — it will scrape the ground`,
      );
    }
  }
  return logs;
}

// A part can be perfectly assembled and still be invisible: swallowed whole by
// the part next to it. That is what happened to a house's lower hip roof, where
// the analysis said both "lower hipped roof centered-above ground floor block"
// AND "second floor block centered-above ground floor block", so the two were
// seated at the same height and the roof ended up 90% inside the storey box —
// the render simply had no lower roof on it. Nothing caught this: the part
// touches its support, sits inside the silhouette, is planned, is not hairline.
//
// Being inside another part is not always wrong, so this only looks at parts
// that have real volume. A window, door, badge or decal is MEANT to sit flush in
// its wall, and a plate is exactly what those are — so plate-like parts and
// decals are exempt. What remains is the case worth reporting: one solid mass
// hidden inside another.
//
// Repaired where the correction is unambiguous. The buried part is the smaller
// one, and the direction to move it is the one that costs least: push it out
// through the nearest face of its host until it protrudes, keeping the ~0.03
// overlap the assembly rules want so it stays attached. That turns an invisible
// part into a visible mounted one, which is what a louvre panel sunk into a
// superstructure or a headlight sunk into a ram plate should have been.
//
// The move is capped at 15% of the object's size, the same limit the contact
// solvers use. A part deeper in than that is not a mounting mistake — it was
// modelled in the wrong place entirely, and shoving it across the object would
// invent a shape nobody asked for. Those stay reported.
export function resolveBuriedParts(parsed: any): string[] {
  let logs: string[] = [];
  let all: any[] = parsed?.components ?? [];
  let byId = new Map<string, any>(all.map((c: any) => [c?.nodeId, c]));
  let components: any[] = all.filter(
    (c: any) =>
      c?.nodeId &&
      c.primitive !== 'group' &&
      c.primitive !== 'curvedDecal' &&
      c.primitive !== 'textDecal' &&
      c.primitive !== 'glow' &&
      !/shadow/i.test(String(c.nodeId)) &&
      hasNeutralAncestry(c, byId),
  );
  if (components.length < 2) return logs;
  // the overlap the assembly rules want a mounted part to keep with its host
  const OVERLAP_KEPT = 0.03;
  // a move this small changes nothing anyone can see, and reporting it as a fix
  // would be a lie — a baluster sharing a face with its platform produced a
  // "pushed by -0.00" line before this
  const MIN_MOVE = 0.005;
  let measure = () => {
    let out: { c: any; min: number[]; max: number[]; vol: number }[] = [];
    for (let c of components) {
      let h = halfExtents(c);
      let box = specBox(c);
      if (!h || !box) continue;
      // a plate is a surface feature — being inset in its host is the point
      let sorted = [...h].sort((a, b) => a - b);
      if (sorted[0] < 0.3 * sorted[1]) continue;
      let vol = h[0] * h[1] * h[2] * 8;
      if (vol <= 0) continue;
      out.push({ c, min: box.min, max: box.max, vol });
    }
    return out;
  };
  let boxes = measure();
  if (boxes.length < 2) return logs;
  // the same ceiling the contact solvers use: a solver closes a gap, it does not
  // relocate a part across the object
  let extent = [0, 1, 2].map(
    (ax) =>
      Math.max(...boxes.map((x) => x.max[ax])) -
      Math.min(...boxes.map((x) => x.min[ax])),
  );
  let maxMove = 0.15 * Math.max(...extent, 0.001);
  // freeing one part can bury another — lifting a balcony platform out of a wall
  // pushed its own balusters inside the platform — so re-measure and settle,
  // with a hard pass limit because two parts can always be in each other's way
  let unresolved = new Map<string, string>();
  // one move per part, ever: a part buried in TWO hosts otherwise ping-pongs
  // between their exits (a storey was shoved +0.96 out of the lower roof, then
  // -0.90 out of the upper roof, then back again)
  let movedOnce = new Set<string>();
  for (let pass = 0; pass < 3; pass++) {
    let moved = resolvePass();
    if (!moved) break;
    boxes = measure();
  }
  for (let line of unresolved.values()) logs.push(line);
  return logs;

  function resolvePass(): number {
    let moved = 0;
    for (let i = 0; i < boxes.length; i++) {
      for (let j = 0; j < boxes.length; j++) {
        if (i === j) continue;
        let a = boxes[i];
        let b = boxes[j];
        if (a.vol > b.vol) continue; // only report the smaller as the buried one
        // The assembly rules REQUIRE every part to overlap its support by about
        // 0.03, and for a thin part — a railing bar, a trim strip — that mandated
        // overlap is already most of its own volume. Volume share alone therefore
        // condemns correctly seated details. A part is only buried if its CENTRE
        // has gone inside the other part: a bar resting on a platform keeps its
        // centre above the platform's top face, while a roof swallowed by a
        // storey does not.
        let center = [0, 1, 2].map((ax) => (a.min[ax] + a.max[ax]) / 2);
        let centerInside = [0, 1, 2].every(
          (ax) =>
            center[ax] > b.min[ax] + 0.001 && center[ax] < b.max[ax] - 0.001,
        );
        if (!centerInside) continue;
        let overlap = [0, 1, 2].reduce(
          (acc, ax) =>
            acc *
            Math.max(
              0,
              Math.min(a.max[ax], b.max[ax]) - Math.max(a.min[ax], b.min[ax]),
            ),
          1,
        );
        let share = overlap / a.vol;
        if (share <= 0.5) continue;

        // a repeat prototype sits ON its host's surface by design — its clones
        // ring the host after expansion, and nudging the prototype breaks the
        // whole ring (a cap's knurl ridges were shoved 0.02 INTO the cap here)
        if (a.c.repeat) continue;
        // two revolved bodies sharing an axis are concentric shells — a cap
        // skirt around a cap body, a collar around a neck. Their AABBs nest
        // completely, but the geometry is a ring AROUND the host; shoving one
        // sideways only breaks its symmetry.
        let revolved = (p: string) => p === 'cylinder' || p === 'lathe';
        if (
          revolved(a.c.primitive) &&
          revolved(b.c.primitive) &&
          Math.abs((a.min[0] + a.max[0]) / 2 - (b.min[0] + b.max[0]) / 2) <
            0.05 &&
          Math.abs((a.min[2] + a.max[2]) / 2 - (b.min[2] + b.max[2]) / 2) < 0.05
        ) {
          continue;
        }
        // and a part comparable in size to its host is not a mounted detail in
        // the wrong place — it is major structure whose interpenetration is
        // either deliberate (a storey rising through its skirt roof) or a
        // modelling error no translation can fix. Only a genuine detail (a
        // fraction of its host's bulk) is safe to relocate.
        if (a.vol > 0.25 * b.vol || movedOnce.has(a.c.nodeId)) {
          unresolved.set(
            a.c.nodeId,
            `'${a.c.nodeId}' is ${Math.round(share * 100)}% inside '${b.c.nodeId}' — not moved (${
              movedOnce.has(a.c.nodeId)
                ? 'already moved once'
                : 'the parts are comparable in size'
            })`,
          );
          break;
        }

        // cheapest way out: through whichever face of the host is nearest, in
        // whichever direction moves the part least
        let best: { axis: number; delta: number } | undefined;
        for (let ax = 0; ax < 3; ax++) {
          for (let delta of [
            b.max[ax] - OVERLAP_KEPT - a.min[ax], // out through the + face
            b.min[ax] + OVERLAP_KEPT - a.max[ax], // out through the - face
          ]) {
            if (!best || Math.abs(delta) < Math.abs(best.delta)) {
              best = { axis: ax, delta };
            }
          }
        }
        if (
          !best ||
          Math.abs(best.delta) > maxMove ||
          Math.abs(best.delta) < MIN_MOVE
        ) {
          unresolved.set(
            a.c.nodeId,
            `'${a.c.nodeId}' is ${Math.round(share * 100)}% inside '${b.c.nodeId}' — too deep in to move automatically`,
          );
          break;
        }
        let p = Array.isArray(a.c.position)
          ? a.c.position.map(Number)
          : [0, 0, 0];
        p[best.axis] = Number(((p[best.axis] || 0) + best.delta).toFixed(4));
        a.c.position = p;
        // keep the local boxes in step so a later pair is judged on the new
        // position rather than the old one
        a.min[best.axis] += best.delta;
        a.max[best.axis] += best.delta;
        unresolved.delete(a.c.nodeId);
        movedOnce.add(a.c.nodeId);
        moved++;
        logs.push(
          `pushed '${a.c.nodeId}' out of '${b.c.nodeId}' by ${best.delta.toFixed(2)} on ${'xyz'[best.axis]} (it was ${Math.round(share * 100)}% inside)`,
        );
        break;
      }
    }
    return moved;
  }
}

// The traced silhouette is the object's true outer boundary. Every solid part
// must reconcile WITHIN it: a capsule / gold ring / collar wider than the neck,
// or a part that slid off-axis, pokes past the outline and reads as floating.
// Given the world-space envelope (half-width per height Y, from the traced
// lathe profile), pull each solid back inside — scale an on-axis part down to
// the local half-width, or slide an off-axis part toward the axis. Front-plane
// only: clamps X always, and Z too for a revolved body (its silhouette is
// symmetric about the axis). Decals are left to fitCurvedDecals. Positions are
// treated as world-ish — valid for the centered, shallow hierarchies revolved
// objects use. Mutates parsed; returns log lines.
export function clampToEnvelope(
  parsed: any,
  envelope: { y: number; half: number }[],
  revolved: boolean,
): string[] {
  let logs: string[] = [];
  let components: any[] = parsed?.components ?? [];
  if (!envelope?.length || !components.length) return logs;
  let pts = [...envelope].sort((a, b) => a.y - b.y);
  let loY = pts[0].y;
  let hiY = pts[pts.length - 1].y;
  // widest half-width across the neck (top quarter of the profile) — caps and
  // foils that sit at or above the lip clamp to THIS, not to zero, so they are
  // pulled onto the neck instead of left floating past the outline
  let neckHalf = Math.max(
    ...pts.slice(Math.floor(pts.length * 0.75)).map((p) => p.half),
    0,
  );
  // half-width of the silhouette at world height y
  let envAt = (y: number): number => {
    if (y <= loY) return pts[0].half;
    if (y >= hiY) return neckHalf;
    for (let i = 0; i + 1 < pts.length; i++) {
      let a = pts[i];
      let b = pts[i + 1];
      if (y >= a.y && y <= b.y) {
        let t = b.y === a.y ? 0 : (y - a.y) / (b.y - a.y);
        return a.half + (b.half - a.half) * t;
      }
    }
    return pts[pts.length - 1].half;
  };
  let nums = (raw: any, fb: number[]): number[] =>
    Array.isArray(raw) ? raw : fb;
  // lathe/tube/extrusions/mesh have footprints we can't bound from
  // dimensions[0], so leave them alone entirely. Decals ARE processed — their
  // radius is fitted elsewhere (fitCurvedDecals), but a decal floating above
  // the silhouette still needs the vertical pull-down, or a cap band left
  // hovering at the old height stays detached after its host cap is pulled in.
  let skip = new Set([
    'group',
    'glow',
    'lathe',
    'meshAsset',
    'tube',
    'extrudedPolygon',
    'extrudedSpline',
  ]);
  let isDecal = (p: string) => p === 'curvedDecal' || p === 'textDecal';
  let halfExtentX = (c: any): number => {
    let d = nums(c.dimensions, []);
    let sx = Math.abs(nums(c.scale, [1, 1, 1])[0] ?? 1);
    switch (c.primitive) {
      case 'cylinder':
        return Math.max(Math.abs(d[0] ?? 0), Math.abs(d[1] ?? 0)) * sx;
      case 'torus':
        return (Math.abs(d[0] ?? 0) + Math.abs(d[1] ?? 0)) * sx;
      case 'box':
      case 'roundedBox':
      case 'plane':
      case 'roundedPlate':
        return (Math.abs(d[0] ?? 0) / 2) * sx;
      default:
        // disc/sphere/hemisphere/cone/capsule/rock/blob/flatRing/arch: radius
        return Math.abs(d[0] ?? 0) * sx;
    }
  };
  let skinFactor = 1.06; // a hair of overhang is fine (foil lips sit just proud)
  for (let c of components) {
    if (!c?.primitive || skip.has(c.primitive) || c.parentId == null) continue;
    let pos = nums(c.position, [0, 0, 0]).slice();
    let cx = pos[0] ?? 0;
    let cy = pos[1] ?? 0;
    let posChanged = false;
    // vertical: a part whose center floats ABOVE the silhouette top is outside
    // the outline entirely — drop it onto the top edge so a cap sits on the
    // neck instead of hovering above it
    if (cy > hiY) {
      pos[1] = Number(hiY.toFixed(4));
      cy = pos[1];
      posChanged = true;
      logs.push(`lowered '${c.nodeId}' onto the silhouette top`);
    }
    // lateral: keep the part's front-plane extent inside the outline half-width
    // (solids only — a decal's radius is owned by fitCurvedDecals)
    let ext = isDecal(c.primitive) ? 0 : halfExtentX(c);
    let limit = envAt(cy);
    if (ext > 0 && limit > 0 && Math.abs(cx) + ext > limit * skinFactor) {
      if (Math.abs(cx) < 1e-3) {
        // on-axis and too wide: scale it down to the local half-width
        let f = (limit * skinFactor) / ext;
        let sc = nums(c.scale, [1, 1, 1]).slice();
        sc[0] = Number(((sc[0] ?? 1) * f).toFixed(4));
        if (revolved) sc[2] = Number(((sc[2] ?? 1) * f).toFixed(4));
        c.scale = sc;
        logs.push(
          `clamped '${c.nodeId}' into the traced silhouette (×${f.toFixed(2)})`,
        );
      } else {
        // off-axis: slide toward the axis until the outer edge fits
        pos[0] = Number(
          (Math.sign(cx) * Math.max(0, limit * skinFactor - ext)).toFixed(4),
        );
        posChanged = true;
        logs.push(`pulled '${c.nodeId}' inside the traced silhouette`);
      }
    }
    if (posChanged) c.position = pos;
  }
  return logs;
}
