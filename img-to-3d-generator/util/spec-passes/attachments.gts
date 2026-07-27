// Making the assembly graph true.
//
// The analysis states which part mounts on which, and that list is the only
// thing standing between a model and a pile of parts floating near each other.
// These passes enforce it numerically rather than trusting the spec to have
// honoured it, repair joints that point at the wrong sibling, and seat decals
// against the curved surfaces they are printed on.

import { hasNeutralAncestry, halfExtents, specBox } from '../spec-geometry';
import { SUPPORT_NAME } from './placement';

// The analysis writes an explicit attachments list — "lower hipped roof
// centered-above ground floor block", "balcony railing rests-on balcony
// platform" — and the spec prompt calls each line a hard joint that "must be
// numerically true in the final coordinates". Nothing checked that. The
// interpreter pulls declared attachTo joints into CONTACT, but contact is not
// the constraint: a roof touching the corner of the storey below satisfies
// contact while sitting nowhere near centred above it, which is how a house
// arrives as a stack of offset slabs.
//
// This is the projection-free half of that problem, and the important half for
// a tilted reference: it needs no camera model at all, only the spec's own
// coordinates. Two constraints are REPAIRED because their correction is
// unambiguous — centered-above (align horizontally, sit on top) and rests-on
// (sit on top). The rest are reported only: "attached-right" and "inset-into"
// depend on which way the object faces, and a wrong guess there moves a part
// further from the truth than leaving it.
export function enforceAttachments(parsed: any, analysis: any): string[] {
  let logs: string[] = [];
  let lines: any[] = analysis?.attachments ?? [];
  let components: any[] = parsed?.components ?? [];
  if (!lines.length || !components.length) return logs;
  const CONSTRAINTS = [
    'centered-above',
    'flush-top',
    'attached-left',
    'attached-right',
    'attached-front',
    'attached-back',
    'inset-into',
    'rests-on',
  ];
  let key = (s: any) =>
    String(s ?? '')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '');
  // every component realizing a given plan part, so a multi-piece part moves
  // together and keeps its internal arrangement
  let byRef = new Map<string, any[]>();
  for (let c of components) {
    if (!c?.nodeId || c.primitive === 'group') continue;
    let k = key(c.partRef);
    if (!k) continue;
    if (!byRef.has(k)) byRef.set(k, []);
    byRef.get(k)!.push(c);
  }
  // world-ish AABB of a part group. Like clampToEnvelope, this reads authored
  // positions as world coordinates — true for the flat hierarchies these specs
  // use, and any part under a transformed parent is skipped below.
  let boxOf = (group: any[]) => {
    let min = [Infinity, Infinity, Infinity];
    let max = [-Infinity, -Infinity, -Infinity];
    for (let c of group) {
      let box = specBox(c);
      if (!box) return undefined;
      for (let a = 0; a < 3; a++) {
        min[a] = Math.min(min[a], box.min[a]);
        max[a] = Math.max(max[a], box.max[a]);
      }
    }
    return min[0] === Infinity ? undefined : { min, max };
  };
  let byId = new Map(components.map((c: any) => [c.nodeId, c]));
  let parentIsNeutral = (group: any[]) =>
    group.every((c) => hasNeutralAncestry(c, byId));
  const OVERLAP = 0.03;

  for (let raw of lines) {
    let line = String(raw ?? '').trim();
    let constraint = CONSTRAINTS.find((c) => line.includes(c));
    if (!constraint) continue;
    let [subjectName, targetName] = line.split(constraint).map((s) => s.trim());
    let subject = byRef.get(key(subjectName));
    let target = byRef.get(key(targetName));
    if (!subject?.length || !target?.length || subject === target) continue;
    let sBox = boxOf(subject);
    let tBox = boxOf(target);
    if (!sBox || !tBox) continue;

    if (constraint !== 'centered-above' && constraint !== 'rests-on') {
      // report-only, and the test has to match the constraint: an inset window
      // is SUPPOSED to sit inside its wall, so measuring its vertical gap would
      // report every correct window as broken. Noise here would bury the real
      // findings, so each constraint is judged on its own terms.
      if (constraint === 'inset-into') {
        let protrusion = Math.max(
          ...[0, 1, 2].map((a) =>
            Math.max(tBox.min[a] - sBox.min[a], sBox.max[a] - tBox.max[a]),
          ),
        );
        if (protrusion > 0.02) {
          logs.push(
            `'${subjectName}' should be inset-into '${targetName}' but protrudes ${protrusion.toFixed(2)} out of it`,
          );
        }
      } else if (constraint === 'flush-top') {
        let off = Math.abs(sBox.max[1] - tBox.max[1]);
        if (off > 0.05) {
          logs.push(
            `'${subjectName}' should be flush-top with '${targetName}' but their tops differ by ${off.toFixed(2)}`,
          );
        }
      } else {
        // attached-left/right/front/back: the two must at least touch
        let separation = Math.max(
          ...[0, 1, 2].map((a) =>
            Math.max(sBox.min[a] - tBox.max[a], tBox.min[a] - sBox.max[a]),
          ),
        );
        if (separation > 0.05) {
          logs.push(
            `'${subjectName}' should be ${constraint} '${targetName}' but they are ${separation.toFixed(2)} apart`,
          );
        }
      }
      continue;
    }
    if (!parentIsNeutral(subject)) continue;

    // DIRECTION SANITY. "rests-on" and "centered-above" both mean the subject
    // sits on TOP of the target, so enforcing one on a part the spec placed
    // BELOW its target does not correct a gap — it turns the object upside
    // down. The analysis wrote "wheels rests-on main hull body" for a truck,
    // inverting the real relationship (a hull rests on its wheels), and the
    // wheels were duly lifted onto the roof.
    //
    // When the plan's direction and the authored coordinates disagree, the
    // coordinates win: they were derived from measured bboxes, while the
    // attachment line is prose about which part holds which. Report the
    // conflict instead of acting on it.
    // A SUPPORT never rests on the thing it carries. "wheels rests-on main hull
    // body" is the inversion of the truth, and seating the wheels on the hull's
    // roof is a far bigger error than leaving the line unenforced — so when the
    // subject is a wheel/track/foot and the target is the larger body, the line
    // is refused outright. groundSupports then puts the supports underneath
    // from the coordinates the spec actually authored, which is why this must
    // not "correct" them first.
    let subjectVol = subject.reduce((sum, c) => {
      let h = halfExtents(c);
      return sum + (h ? 8 * h[0] * h[1] * h[2] : 0);
    }, 0);
    let targetVol = target.reduce((sum, c) => {
      let h = halfExtents(c);
      return sum + (h ? 8 * h[0] * h[1] * h[2] : 0);
    }, 0);
    let subjectIsSupport = subject.some(
      (c) =>
        SUPPORT_NAME.test(String(c.partRef ?? '')) ||
        SUPPORT_NAME.test(String(c.nodeId ?? '')),
    );
    if (subjectIsSupport && targetVol > subjectVol) {
      logs.push(
        `refused '${subjectName}' ${constraint} '${targetName}' — a support does not sit on the body it carries`,
      );
      continue;
    }

    let sCenterY = (sBox.min[1] + sBox.max[1]) / 2;
    let tCenterY = (tBox.min[1] + tBox.max[1]) / 2;
    if (sCenterY < tCenterY) {
      logs.push(
        `'${subjectName}' is ${constraint} '${targetName}' in the plan but sits BELOW it in the spec — left alone (the plan line looks inverted)`,
      );
      continue;
    }

    // sit on top of the target with a small overlap
    let dy = tBox.max[1] - OVERLAP - sBox.min[1];
    let span = Math.max(
      tBox.max[0] - tBox.min[0],
      tBox.max[1] - tBox.min[1],
      tBox.max[2] - tBox.min[2],
      0.001,
    );
    // and, for centered-above, share its horizontal centre — but only when the
    // part is ALREADY roughly centred. "centered-above" is the analysis'
    // shorthand for "this storey stands on that one", and plenty of real houses
    // set the upper floor back over an L-shaped plan. Snapping a deliberately
    // offset wing to dead centre would enforce the plan's wording against the
    // photograph's shape, so a large existing offset is taken as intentional
    // and only the seating is corrected.
    let dx = 0;
    let dz = 0;
    if (constraint === 'centered-above') {
      let offX =
        (tBox.min[0] + tBox.max[0]) / 2 - (sBox.min[0] + sBox.max[0]) / 2;
      let offZ =
        (tBox.min[2] + tBox.max[2]) / 2 - (sBox.min[2] + sBox.max[2]) / 2;
      if (Math.hypot(offX, offZ) <= span * 0.25) {
        dx = offX;
        dz = offZ;
      } else {
        logs.push(
          `kept '${subjectName}' off-centre over '${targetName}' (offset ${Math.hypot(offX, offZ).toFixed(2)} looks deliberate) — seated it only`,
        );
      }
    }
    // a correction larger than the target itself means the two parts were never
    // the pair the line describes — leave it and say so
    if (Math.hypot(dx, dy, dz) > span) {
      logs.push(
        `'${subjectName}' is too far from '${targetName}' to be ${constraint} it — left in place`,
      );
      continue;
    }
    if (Math.hypot(dx, dy, dz) < 0.005) continue;
    for (let c of subject) {
      let p = Array.isArray(c.position) ? c.position.map(Number) : [0, 0, 0];
      c.position = [
        Number((p[0] + dx).toFixed(4)),
        Number((p[1] + dy).toFixed(4)),
        Number((p[2] + dz).toFixed(4)),
      ];
    }
    logs.push(
      `${constraint}: moved '${subjectName}' onto '${targetName}' ` +
        `(Δ ${dx.toFixed(2)}, ${dy.toFixed(2)}, ${dz.toFixed(2)})`,
    );
  }
  return logs;
}

// `attachTo` names the part that HOLDS this one up, and the builder's joint
// solver takes it literally: it pulls the subject until it overlaps that target
// by ~0.03. So a wrong attachTo does not merely fail to help, it actively drags
// geometry across the model.
//
// The failure that made this necessary: a spec set `wheel-right attachTo
// wheel-left`. Those are the two flanks of a six-wheeler, 1.30 apart in X, and
// the solver dutifully hauled the entire right-hand row over to touch the left —
// all six wheels ended up on one flank, at x -0.65 and -0.32, with the hull
// spanning -0.52 to 0.52 above them. The prompt is partly to blame: it requires
// every non-group part to declare an attachTo, so a model that has made one wheel
// the first part hangs everything off it, the opposite wheel row included.
//
// Two mirrored instances of one feature do not support each other — the body
// between them does. Recognising them needs no naming convention: they have the
// same primitive and the same dimensions (the family test the collision check
// already uses) and they sit on opposite sides of the object's centre. Where the
// target itself declares a support, the attachment is re-pointed at that instead
// of just dropped, so the part keeps a joint to hold on to.
export function repairMirroredAttachments(parsed: any): string[] {
  let logs: string[] = [];
  let components: any[] = (parsed?.components ?? []).filter(
    (c: any) => c?.nodeId && c.primitive !== 'group',
  );
  if (components.length < 2) return logs;
  let byId = new Map<string, any>(components.map((c: any) => [c.nodeId, c]));
  let sig = (c: any) => {
    let h = halfExtents(c);
    return h ? `${c.primitive}|${h.map((n) => n.toFixed(3)).join(',')}` : '';
  };
  let boxes = new Map<string, { min: number[]; max: number[] }>();
  for (let c of components) {
    let b = specBox(c);
    if (b) boxes.set(c.nodeId, b);
  }
  if (!boxes.size) return logs;
  let centre = [0, 1, 2].map((a) => {
    let lo = Math.min(...[...boxes.values()].map((b) => b.min[a]));
    let hi = Math.max(...[...boxes.values()].map((b) => b.max[a]));
    return (lo + hi) / 2;
  });

  for (let c of components) {
    if (!c.attachTo) continue;
    let target = byId.get(String(c.attachTo));
    if (!target) continue;
    let mySig = sig(c);
    if (!mySig || mySig !== sig(target)) continue; // not the same feature
    let mine = boxes.get(c.nodeId);
    let theirs = boxes.get(target.nodeId);
    if (!mine || !theirs) continue;
    // opposite sides of the object on some axis, and not touching: a mirrored
    // pair. Two copies that already touch (a stacked rib, a chain link) are a
    // real joint and must be left alone.
    let opposed = [0, 1, 2].some((a) => {
      let mc = (mine.min[a] + mine.max[a]) / 2;
      let tc = (theirs.min[a] + theirs.max[a]) / 2;
      let apart = mine.min[a] > theirs.max[a] || theirs.min[a] > mine.max[a];
      return apart && (mc - centre[a]) * (tc - centre[a]) < 0;
    });
    if (!opposed) continue;
    let inherited = target.attachTo ? String(target.attachTo) : null;
    if (inherited && inherited !== c.nodeId) {
      c.attachTo = inherited;
      logs.push(
        `re-pointed '${c.nodeId}' from its mirror '${target.nodeId}' to '${inherited}' — opposite instances of one part do not hold each other up`,
      );
    } else {
      delete c.attachTo;
      logs.push(
        `dropped '${c.nodeId}' attachTo '${target.nodeId}' — they are the same part on opposite sides, and the joint solver would drag one across to the other`,
      );
    }
  }
  return logs;
}

// specFieldFromParsed consumes — refine rounds rebuild only what changed
// deterministic decal fitting (the lateral cousin of gravity snap): a
// curvedDecal must hug the body it attaches to, but the model's authored
// radius is only probabilistically right — a too-large radius reads as a
// label floating beside the bottle. Snap each curvedDecal's radius to its
// attachTo host's real radius (+0.01 skin gap) and keep its height inside
// the host. Mutates the parsed spec; returns log lines for the studio.
export function fitCurvedDecals(parsed: any): string[] {
  let logs: string[] = [];
  let components: any[] = parsed?.components ?? [];
  let byId = new Map(components.map((c: any) => [c.nodeId, c]));
  let nums = (raw: any): number[] =>
    Array.isArray(raw) ? raw : typeof raw === 'string' ? JSON.parse(raw) : [];
  for (let decal of components) {
    if (decal?.primitive !== 'curvedDecal' || !decal.attachTo) continue;
    let host: any = byId.get(decal.attachTo);
    // a decal may attachTo ANOTHER decal (e.g. an illustration wrapped on a
    // label) — walk up the attachTo chain to the first solid body so the wrap
    // is fitted against real geometry instead of a zero-thickness decal that
    // has no radius of its own (which leaves it floating at its authored size)
    let hostGuard = 0;
    while (
      host &&
      (host.primitive === 'curvedDecal' || host.primitive === 'textDecal') &&
      host.attachTo &&
      hostGuard++ < 8
    ) {
      host = byId.get(host.attachTo);
    }
    if (!host) continue;
    let d: number[];
    let hostDims: number[];
    let hostScale: number[];
    let decalPos: number[];
    let hostPos: number[];
    try {
      d = nums(decal.dimensions);
      hostDims = nums(host.dimensions);
      hostScale = nums(host.scale);
      decalPos = nums(decal.position);
      hostPos = nums(host.position);
    } catch {
      continue;
    }
    let sx = Math.abs(hostScale?.[0] || 1);
    let sz = Math.abs(hostScale?.[2] || 1);
    let sy = Math.abs(hostScale?.[1] || 1);

    // a wrap-around label lives ON the body's axis — models often author it
    // offset forward like a flat sticker, which floats the whole shell in
    // front of the bottle. Snap the decal's x/z onto the host axis.
    let hx = hostPos[0] ?? 0;
    let hz = hostPos[2] ?? 0;
    if (
      Math.abs((decalPos[0] ?? 0) - hx) > 0.001 ||
      Math.abs((decalPos[2] ?? 0) - hz) > 0.001
    ) {
      decalPos[0] = hx;
      decalPos[2] = hz;
      decal.position = decalPos;
      logs.push(`centered '${decal.nodeId}' on its body axis`);
    }

    // radius at the DECAL'S OWN HEIGHT — a bottle is thinner at the label
    // band than at its widest bulge, so a global max over-sizes the wrap
    let decalH = Math.abs(d[1] ?? 0.6);
    let localY = ((decalPos[1] ?? 0) - (hostPos[1] ?? 0)) / (sy || 1);
    let bandLo = localY - decalH / 2 / (sy || 1);
    let bandHi = localY + decalH / 2 / (sy || 1);
    let radius: number | undefined;
    let height: number | undefined;
    switch (host.primitive) {
      case 'cylinder': {
        let rTop = Math.abs(hostDims[0] ?? 0.5);
        let rBottom = Math.abs(hostDims[1] ?? hostDims[0] ?? 0.5);
        radius = Math.max(rTop, rBottom);
        height = Math.abs(hostDims[2] ?? 1) * sy;
        break;
      }
      case 'capsule':
        radius = Math.abs(hostDims[0] ?? 0.3);
        height = (Math.abs(hostDims[1] ?? 0.6) + 2 * radius) * sy;
        break;
      case 'sphere':
      case 'hemisphere':
      case 'blob':
        radius = Math.abs(hostDims[0] ?? 0.5);
        break;
      case 'lathe': {
        // profile is [x0,y0, x1,y1, ...] — sample the wall's half-width
        // where the decal actually sits, interpolating along each segment
        let pts: { x: number; y: number }[] = [];
        for (let i = 0; i + 1 < hostDims.length; i += 2) {
          pts.push({ x: Math.max(0, hostDims[i]), y: hostDims[i + 1] });
        }
        if (pts.length >= 2) {
          let bandMax = 0;
          for (let i = 0; i + 1 < pts.length; i++) {
            let a = pts[i];
            let b = pts[i + 1];
            let lo = Math.min(a.y, b.y);
            let hi = Math.max(a.y, b.y);
            if (hi < bandLo || lo > bandHi) continue;
            let xAt = (y: number) =>
              hi === lo
                ? Math.max(a.x, b.x)
                : a.x + ((b.x - a.x) * (y - a.y)) / (b.y - a.y);
            let edgeLo = Math.max(lo, bandLo);
            let edgeHi = Math.min(hi, bandHi);
            bandMax = Math.max(bandMax, xAt(edgeLo), xAt(edgeHi));
            for (let p of [a, b]) {
              if (p.y >= bandLo && p.y <= bandHi)
                bandMax = Math.max(bandMax, p.x);
            }
          }
          // decal band outside the profile → fall back to the global max
          radius = bandMax > 0 ? bandMax : Math.max(...pts.map((p) => p.x));
          let ys = pts.map((p) => p.y);
          height = (Math.max(...ys) - Math.min(...ys)) * sy;
        }
        break;
      }
      default:
        continue; // box-like hosts: a curved label on a flat body is the
      // model's own mistake — leave it visible so refine reports it
    }
    if (!radius || !isFinite(radius)) continue;
    let fitted = radius * Math.max(sx, sz) + 0.01;
    let authored = Math.abs(d[0] ?? 0.5);
    if (Math.abs(authored - fitted) > 0.005) {
      d[0] = Number(fitted.toFixed(4));
      logs.push(
        `fitted '${decal.nodeId}' radius to its ${host.primitive} body (${authored} → ${d[0]})`,
      );
    }
    if (height && isFinite(height)) {
      let maxH = height * 0.85;
      if (Math.abs(d[1] ?? 0.6) > maxH) {
        d[1] = Number(maxH.toFixed(4));
        logs.push(`clamped '${decal.nodeId}' height inside its body`);
      }
      // a wrap label centered beyond its host's vertical span floats above
      // or below the body — clamp its center into the host band
      let hostLoY = (hostPos[1] ?? 0) - height / 2;
      let hostHiY = (hostPos[1] ?? 0) + height / 2;
      if (host.primitive === 'lathe') {
        let ys: number[] = [];
        for (let i = 1; i < hostDims.length; i += 2) ys.push(hostDims[i]);
        if (ys.length) {
          hostLoY = (hostPos[1] ?? 0) + Math.min(...ys) * sy;
          hostHiY = (hostPos[1] ?? 0) + Math.max(...ys) * sy;
        }
      }
      let half = Math.abs(d[1] ?? 0.6) / 2;
      let minC = hostLoY + half;
      let maxC = hostHiY - half;
      if (minC <= maxC) {
        let clamped = Math.min(maxC, Math.max(minC, decalPos[1] ?? 0));
        if (Math.abs(clamped - (decalPos[1] ?? 0)) > 0.005) {
          decalPos[1] = Number(clamped.toFixed(4));
          decal.position = decalPos;
          logs.push(`pulled '${decal.nodeId}' into its body's band`);
        }
      }
    }
    decal.dimensions = d;
  }

  // cylinders riding a lathe body (foil capsules, caps, collars) must stay
  // proportionate to the wall they sit on — analysis bboxes overestimate
  // them, which grows a monster cap on a slender neck
  for (let part of components) {
    if (part?.primitive !== 'cylinder' || !part.attachTo) continue;
    let host: any = byId.get(part.attachTo);
    // follow one hop: capsule → lower capsule → lathe
    if (host?.primitive === 'cylinder' && host.attachTo) {
      host = byId.get(host.attachTo) ?? host;
    }
    if (host?.primitive !== 'lathe') continue;
    let d: number[];
    let hostDims: number[];
    let partPos: number[];
    let hostPos: number[];
    try {
      d = nums(part.dimensions);
      hostDims = nums(host.dimensions);
      partPos = nums(part.position);
      hostPos = nums(host.position);
    } catch {
      continue;
    }
    let pts: { x: number; y: number }[] = [];
    for (let i = 0; i + 1 < hostDims.length; i += 2) {
      pts.push({ x: Math.max(0, hostDims[i]), y: hostDims[i + 1] });
    }
    if (pts.length < 2) continue;
    let cylH = Math.abs(d[2] ?? 1);
    let localY = (partPos[1] ?? 0) - (hostPos[1] ?? 0);
    let bandLo = localY - cylH / 2;
    let bandHi = localY + cylH / 2;
    let wallR = 0;
    for (let i = 0; i + 1 < pts.length; i++) {
      let a = pts[i];
      let b = pts[i + 1];
      let lo = Math.min(a.y, b.y);
      let hi = Math.max(a.y, b.y);
      if (hi < bandLo || lo > bandHi) continue;
      wallR = Math.max(wallR, a.x, b.x);
    }
    // band above the profile top (a cap ON the mouth): size to the topmost
    // profile radius instead
    if (!(wallR > 0)) wallR = pts[pts.length - 1].x || pts[pts.length - 2].x;
    if (!(wallR > 0)) continue;
    let maxR = wallR * 1.3;
    let r0 = Math.abs(d[0] ?? 0.5);
    let r1 = Math.abs(d[1] ?? d[0] ?? 0.5);
    let biggest = Math.max(r0, r1);
    if (biggest > maxR) {
      let shrink = maxR / biggest;
      d[0] = Number((r0 * shrink).toFixed(4));
      d[1] = Number((r1 * shrink).toFixed(4));
      part.dimensions = d;
      logs.push(
        `slimmed '${part.nodeId}' to its neck wall (×${shrink.toFixed(2)})`,
      );
    }
  }
  return logs;
}
