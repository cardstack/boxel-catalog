// Reconciling built proportions against the measured plan.
//
// The analysis measured each part's bounding box in the reference image; the
// spec then authored dimensions from scratch. Where the two disagree this
// scales the built part toward the measurement — but only along the axes the
// camera could actually see, and only within a band, because a correction
// applied on top of a correction is how a part ends up at 0.4^5 of its size.

// Measured proportion reconciliation — the heart of "LLM names structure,
// math writes numbers". The draft build is measured in the viewer (real
// world-space boxes, transforms and all), each partRef group is compared
// against its analysis bbox target, and size/placement corrections are
// written back into the spec deterministically. Zero vision calls.
export interface MeasuredBox {
  name: string;
  min: number[];
  max: number[];
}

export interface MeasuredModel {
  whole: { min: number[]; max: number[] };
  parts: MeasuredBox[];
}

export interface ReconcileResult {
  logs: string[];
  // mean deviation of every measured part group from its analysis target
  // (0 = perfect match) — the machine metric the auto-verify loop gates on
  residual: number | null;
}

export function reconcileProportions(
  parsed: any,
  analysis: any,
  measured: MeasuredModel,
  // part names already embodied by a traced silhouette — their geometry is
  // ground truth, rescaling them piecewise would tear the outline apart
  skipRefs: string[] = [],
): ReconcileResult {
  let logs: string[] = [];
  let deviations: number[] = [];
  // how far this pass may ever stretch or squash a part, measured on the part's
  // FINAL scale rather than on one pass's factor — see the cumulative clamp
  // below. A part outside the band was authored that way deliberately and is
  // left alone; only reconcile's own contribution is bounded.
  const SCALE_FLOOR = 0.4;
  const SCALE_CEILING = 2.5;
  let clamped: string[] = [];
  let result = (): ReconcileResult => ({
    logs,
    residual: deviations.length
      ? deviations.reduce((s, d) => s + d, 0) / deviations.length
      : null,
  });
  let plan: any[] = analysis?.partPlan ?? [];
  let components: any[] = parsed?.components ?? [];
  if (!plan.length || !components.length || !measured?.parts?.length) {
    return result();
  }
  let norm = (s: any) =>
    String(s ?? '')
      .trim()
      .toLowerCase();
  let skip = new Set(skipRefs.map(norm));
  let nums = (raw: any, fallback: number[]): number[] => {
    if (Array.isArray(raw)) return raw;
    try {
      let v = JSON.parse(raw ?? 'null');
      return Array.isArray(v) ? v : fallback;
    } catch {
      return fallback;
    }
  };

  // ---- target side: analysis bboxes, normalized to the OBJECT's bounds
  // (the union of all part bboxes), not to the whole photo
  let boxes = plan.filter((p) => p?.bbox?.width > 0 && p?.bbox?.height > 0);
  if (!boxes.length) return result();
  let uL = Math.min(...boxes.map((p) => p.bbox.left));
  let uT = Math.min(...boxes.map((p) => p.bbox.top));
  let uR = Math.max(...boxes.map((p) => p.bbox.left + p.bbox.width));
  let uB = Math.max(...boxes.map((p) => p.bbox.top + p.bbox.height));
  let uW = uR - uL;
  let uH = uB - uT;
  if (!(uW > 0) || !(uH > 0)) return result();
  let targets = new Map<
    string,
    { w: number; h: number; cx: number; cyFromTop: number }
  >();
  for (let p of boxes) {
    targets.set(norm(p.part), {
      w: p.bbox.width / uW,
      h: p.bbox.height / uH,
      cx: (p.bbox.left + p.bbox.width / 2 - uL) / uW,
      cyFromTop: (p.bbox.top + p.bbox.height / 2 - uT) / uH,
    });
  }

  // frontal-view assumption: image x ↔ world x only holds near the front
  let az = Math.abs(analysis?.camera?.azimuthDeg ?? 0);
  let xTrustworthy = az <= 30;
  if (!xTrustworthy) {
    logs.push(`camera ${az}° off-front — not reconciling widths`);
  }
  // ...and image y ↔ world y only holds near eye level. Raise the camera and
  // the image's vertical axis starts carrying DEPTH: a part further back simply
  // appears higher up, which is the same warning the spec prompt gives the
  // model about ground placement. Recentering a part vertically from an aerial
  // bbox therefore pushes it up by however far back it sits — on a 40°
  // elevation house reference that spread the storeys, fence and hedges into a
  // stack of floating slabs. Sizes stay reconcilable (a bbox's extent survives
  // the tilt far better than its position), so only the vertical MOVE is
  // withheld; the declared joints and the ground drop own placement instead.
  let el = Math.abs(analysis?.camera?.elevationDeg ?? 0);
  let yPlacementTrustworthy = el <= 25;
  if (!yPlacementTrustworthy) {
    logs.push(
      `camera ${el}° above eye level — sizing only, vertical placement left to the declared joints`,
    );
  }

  // ---- built side: world boxes grouped by the owning component's partRef.
  // Repeat clones are named '<id>-<i>' — fold them back onto their original.
  let byId = new Map(components.map((c: any) => [c.nodeId, c]));
  let componentFor = (name: string): any => {
    if (byId.has(name)) return byId.get(name);
    let base = name.replace(/-\d+$/, '');
    return byId.get(base);
  };
  interface Group {
    minX: number;
    maxX: number;
    minY: number;
    maxY: number;
    comps: Set<any>;
    boxes: { min: number[]; max: number[] }[];
  }
  let groups = new Map<string, Group>();
  for (let part of measured.parts) {
    let comp = componentFor(part.name);
    let ref = norm(comp?.partRef);
    if (!comp || !ref || !targets.has(ref) || skip.has(ref)) continue;
    let g = groups.get(ref) ?? {
      minX: Infinity,
      maxX: -Infinity,
      minY: Infinity,
      maxY: -Infinity,
      comps: new Set(),
      boxes: [],
    };
    g.minX = Math.min(g.minX, part.min[0]);
    g.maxX = Math.max(g.maxX, part.max[0]);
    g.minY = Math.min(g.minY, part.min[1]);
    g.maxY = Math.max(g.maxY, part.max[1]);
    g.boxes.push({ min: part.min, max: part.max });
    g.comps.add(comp);
    groups.set(ref, g);
  }
  if (!groups.size) return result();
  let whole = measured.whole;
  let wholeW = whole.max[0] - whole.min[0];
  let wholeH = whole.max[1] - whole.min[1];
  if (!(wholeW > 0) || !(wholeH > 0)) return result();

  for (let [ref, g] of groups) {
    let target = targets.get(ref)!;
    let builtW = (g.maxX - g.minX) / wholeW;
    let builtH = (g.maxY - g.minY) / wholeH;
    if (!(builtW > 0) || !(builtH > 0)) continue;
    let wS = xTrustworthy
      ? Math.min(SCALE_CEILING, Math.max(SCALE_FLOOR, target.w / builtW))
      : 1;
    let hS = Math.min(SCALE_CEILING, Math.max(SCALE_FLOOR, target.h / builtH));
    // world-space target centers (image top ↔ world +Y top)
    let builtCx = (g.minX + g.maxX) / 2;
    let builtCy = (g.minY + g.maxY) / 2;
    let targetCx = whole.min[0] + target.cx * wholeW;
    let targetCy = whole.max[1] - target.cyFromTop * wholeH;
    // A SPLIT GROUP cannot be positioned from one image bbox. "ground floor
    // windows" is one plan part but two components on two different faces of the
    // house; their union has a centre that corresponds to nothing in the photo,
    // and moving both by that union's error drags them onto the same spot — a
    // front window and a side window ended up at identical coordinates, sunk to
    // y 0 and half underground. Sizes still mean something (a window is that
    // fraction of the object either way), so only the MOVE is withheld.
    let connected = (() => {
      if (g.boxes.length < 2) return true;
      let joined = [0];
      let touches = (a: any, b: any) =>
        [0, 1, 2].every(
          (ax) =>
            a.min[ax] <= b.max[ax] + 0.05 && b.min[ax] <= a.max[ax] + 0.05,
        );
      let grew = true;
      while (grew) {
        grew = false;
        for (let i = 0; i < g.boxes.length; i++) {
          if (joined.includes(i)) continue;
          if (joined.some((j) => touches(g.boxes[i], g.boxes[j]))) {
            joined.push(i);
            grew = true;
          }
        }
      }
      return joined.length === g.boxes.length;
    })();
    if (!connected) {
      logs.push(
        `'${ref}' is built as ${g.boxes.length} separate pieces — sizing only, they cannot share one image position`,
      );
    }
    let dx = xTrustworthy && connected ? targetCx - builtCx : 0;
    let dy = yPlacementTrustworthy && connected ? targetCy - builtCy : 0;
    // decal-only groups are placement-corrected but never resized here, so
    // their size mismatch must not drive the auto-verify metric — the loop
    // would chase a number this pass refuses to change
    let decalOnly = [...g.comps].every(
      (c: any) =>
        c.primitive === 'curvedDecal' ||
        c.primitive === 'textDecal' ||
        c.primitive === 'glow',
    );
    deviations.push(
      decalOnly
        ? Math.max(Math.abs(dx) / wholeW, Math.abs(dy) / wholeH)
        : Math.max(
            Math.abs(wS - 1),
            Math.abs(hS - 1),
            Math.abs(dx) / wholeW,
            Math.abs(dy) / wholeH,
          ),
    );
    let sizeOff = Math.abs(wS - 1) > 0.03 || Math.abs(hS - 1) > 0.03;
    let posOff = Math.abs(dx) > wholeW * 0.02 || Math.abs(dy) > wholeH * 0.02;
    if (!sizeOff && !posOff) continue;

    let applied = 0;
    for (let comp of g.comps) {
      // decal fitting owns wrap-around geometry (radius/arc) — decals get
      // their PLACEMENT corrected here (a label must ride its own bbox
      // band even when its host body was rescaled), never their size
      let isDecal =
        comp.primitive === 'curvedDecal' ||
        comp.primitive === 'textDecal' ||
        comp.primitive === 'glow';
      // A tube's dimensions ARE its curve, in coordinates that already say
      // where the part runs, so its node transform is not its placement:
      // writing a position onto it slides the curve off the body, and scaling
      // it moves the curve away from a node origin that sits at 0,0,0 while the
      // geometry is metres away. This pass kept re-offsetting a truck's exhaust
      // run every round (y -1.26, then 0.09, then -0.50) no matter how often it
      // was zeroed upstream, which is the brown arc floating across the hull.
      if (comp.primitive === 'tube') continue;
      let rotation = nums(comp.rotation, [0, 0, 0]);
      let rotated = rotation.some((r) => Math.abs(r) > 0.01);
      let parent = comp.parentId ? byId.get(comp.parentId) : undefined;
      let parentNeutral =
        !parent ||
        (nums(parent.position, [0, 0, 0]).every((n) => Math.abs(n) < 0.001) &&
          nums(parent.scale, [1, 1, 1]).every((n) => Math.abs(n - 1) < 0.001) &&
          nums(parent.rotation, [0, 0, 0]).every((n) => Math.abs(n) < 0.001));
      if (!parentNeutral) continue; // local ≠ world — leave for refine
      let pos = nums(comp.position, [0, 0, 0]);
      let sxApply = rotated || comp.repeat || isDecal ? 1 : wS;
      let syApply = rotated || comp.repeat || isDecal ? 1 : hS;
      // The clamp on wS/hS bounds ONE pass, but the passes MULTIPLY: three
      // rounds pinned at the 0.4 floor land at 0.064. That is how a balcony
      // railing arrived at scale 0.1137 — a wafer 0.045 units tall, buried
      // inside its own platform, which had itself been stretched to 2.7989. So
      // bound the scale the part ENDS UP with, not the per-pass factor: the
      // factor actually applied is whatever brings the part to the edge of the
      // allowed band, which still lets a pass correct a proportion but can
      // never drive a part degenerate no matter how many rounds run.
      let currentScale = nums(comp.scale, [1, 1, 1]);
      let limited = (factor: number, axis: number) => {
        if (factor === 1) return 1;
        let at = Math.abs(currentScale[axis] ?? 1) || 1;
        return Math.min(SCALE_CEILING, Math.max(SCALE_FLOOR, at * factor)) / at;
      };
      let sxLimited = limited(sxApply, 0);
      let syLimited = limited(syApply, 1);
      let szLimited = limited(sxApply, 2);
      if (
        (Math.abs(sxLimited - sxApply) > 0.001 ||
          Math.abs(syLimited - syApply) > 0.001) &&
        clamped.length < 5
      ) {
        clamped.push(comp.nodeId);
      }
      sxApply = sxLimited;
      syApply = syLimited;
      if (sizeOff && (sxApply !== 1 || syApply !== 1 || szLimited !== 1)) {
        let scl = currentScale;
        scl[0] = Number((scl[0] * sxApply).toFixed(4));
        scl[2] = Number((scl[2] * szLimited).toFixed(4));
        scl[1] = Number((scl[1] * syApply).toFixed(4));
        comp.scale = scl;
      }
      // node scaling happens about the node's own origin — place the origin
      // so the group's center lands on the target center
      pos[0] = Number(
        (pos[0] + dx + (builtCx - pos[0]) * (1 - sxApply)).toFixed(4),
      );
      pos[1] = Number(
        (pos[1] + dy + (builtCy - pos[1]) * (1 - syApply)).toFixed(4),
      );
      comp.position = pos;
      applied++;
    }
    if (applied) {
      let facts: string[] = [];
      if (sizeOff) {
        facts.push(`size ×${wS.toFixed(2)}/${hS.toFixed(2)}`);
      }
      if (posOff) facts.push('recentered');
      logs.push(`reconciled '${ref}' (${facts.join(', ')})`);
    }
  }
  if (clamped.length) {
    logs.push(
      `held ${clamped.join(', ')} at the ${SCALE_FLOOR}–${SCALE_CEILING}× limit (rounds were compounding)`,
    );
  }
  return result();
}
