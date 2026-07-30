// Taking parts OUT of a reply.
//
// The spec stage over-produces in predictable ways: it invents parts the plan
// never asked for, splits one part into a dozen slivers, and models surface
// marks as hairline geometry that renders as wire hanging in space. Removing a
// part is the one repair that cannot be undone later, so each pass here has to
// be sure — and each removal cascades, because a dropped parent would
// otherwise leave its children floating.

// The analysis partPlan is the agreed inventory of what the photo actually
// contains, and every visible component is told to name the plan entry it
// realizes in "partRef". Nothing enforced that, so the spec stage could invent
// parts the reference has none of — glass mould seams, extra cap ribs, neck
// collars — and the assembly solver would then glue each unsupported orphan
// onto its nearest neighbour rather than question it, which is what produced
// the clump of spare parts around a bottle neck. This is the gate: a component
// whose partRef names no planned part is deleted, along with anything parented
// to it. It only fires when there IS a plan to check against, so a
// plan-less spec passes through untouched.
// Delete a set of nodeIds and everything parented to them. A surviving child of
// a deleted parent inherits root coordinates and flies off on its own, so the
// cascade is not optional.
function pruneComponents(parsed: any, dead: Set<string>, logs: string[]): void {
  if (!dead.size) return;
  let components: any[] = parsed?.components ?? [];
  let changed = true;
  while (changed) {
    changed = false;
    for (let c of components) {
      let id = String(c?.nodeId ?? '');
      if (!id || dead.has(id)) continue;
      if (c.parentId != null && dead.has(String(c.parentId))) {
        dead.add(id);
        logs.push(`dropped '${id}' — its parent was dropped`);
        changed = true;
      }
    }
  }
  parsed.components = components.filter(
    (c: any) => !dead.has(String(c?.nodeId ?? '')),
  );
}

// Hairline solids: geometry so thin it can only render as a wire hanging in
// space. A mould seam, panel gap, perforation line or printed hairline is a mark
// ON a surface, and the moment it is modelled as a 0.008-radius tube it becomes
// the most visually obtrusive thing in the picture — a long dark line crossing
// the object it was meant to decorate.
//
// This gate is deliberately NAME-BLIND. The partRef gate can be evaded by
// relabelling: the same two mould-seam tubes were rejected in one round as
// partRef 'mold seam' and accepted in the next as partRef 'bottle body'. A
// measurement cannot be argued with, so the test is purely dimensional.
export function dropHairlineParts(parsed: any): string[] {
  let logs: string[] = [];
  let components: any[] = parsed?.components ?? [];
  if (!components.length) return logs;
  let nums = (raw: any): number[] => {
    if (Array.isArray(raw)) return raw.map(Number).filter((n) => !isNaN(n));
    try {
      let v = JSON.parse(String(raw ?? '[]'));
      return Array.isArray(v) ? v.map(Number).filter((n) => !isNaN(n)) : [];
    } catch {
      return [];
    }
  };
  // thresholds are in world units against the standard 2-3 unit object, where
  // 0.02 is about a millimetre of real bottle — below that there is no shape
  // left to read, only a line
  const MIN_TUBE_RADIUS = 0.02;
  const MIN_TORUS_TUBE = 0.008;
  const MIN_SOLID_EXTENT = 0.015;
  let dead = new Set<string>();
  for (let c of components) {
    if (!c?.nodeId || c.primitive === 'group') continue;
    let d = nums(c.dimensions);
    let reason = '';
    if (c.primitive === 'tube' && d.length && d[0] < MIN_TUBE_RADIUS) {
      reason = `tube radius ${d[0]}`;
    } else if (
      c.primitive === 'torus' &&
      d.length > 1 &&
      d[1] < MIN_TORUS_TUBE
    ) {
      reason = `torus tube ${d[1]}`;
    } else if (
      (c.primitive === 'box' ||
        c.primitive === 'roundedBox' ||
        c.primitive === 'cylinder') &&
      d.slice(0, 3).filter((v) => v > 0 && v < MIN_SOLID_EXTENT).length >= 2
    ) {
      reason = `two extents under ${MIN_SOLID_EXTENT}`;
    }
    if (!reason) continue;
    dead.add(String(c.nodeId));
    logs.push(
      `dropped '${c.nodeId}' — ${reason}: a surface mark, not geometry (${c.note ?? c.primitive})`,
    );
  }
  pruneComponents(parsed, dead, logs);
  return logs;
}

export function dropUnplannedParts(parsed: any, analysis: any): string[] {
  let logs: string[] = [];
  let plan: any[] = analysis?.partPlan ?? [];
  let components: any[] = parsed?.components ?? [];
  if (!plan.length || !components.length) return logs;
  // compare on alphanumerics only: the plan says 'screwcap' and the spec may
  // say 'screw cap' or 'screw-cap' for the same part, and dropping a REAL part
  // over punctuation would be worse than keeping a fake one
  let key = (s: any) =>
    String(s ?? '')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '');
  let plannedKeys = plan.map((p: any) => key(p?.part)).filter(Boolean);
  if (!plannedKeys.length) return logs;
  // a containment match still counts ('left handle loop' realizes 'handle
  // loop'), but only for stems long enough to be meaningful
  let planned = (ref: string) =>
    plannedKeys.some(
      (p) =>
        p === ref ||
        (ref.length >= 4 && p.includes(ref)) ||
        (p.length >= 4 && ref.includes(p)),
    );

  let dead = new Set<string>();
  for (let c of components) {
    if (!c?.nodeId) continue;
    // groups carry hierarchy rather than geometry, and the prompt explicitly
    // allows one ground shadow disc that no plan entry covers
    if (c.primitive === 'group') continue;
    if (/shadow/i.test(String(c.nodeId))) continue;
    let ref = key(c.partRef);
    if (ref && planned(ref)) continue;
    dead.add(String(c.nodeId));
    logs.push(
      ref
        ? `dropped '${c.nodeId}' — partRef '${c.partRef}' is not a planned part`
        : `dropped '${c.nodeId}' — no partRef, so no planned part backs it`,
    );
  }
  pruneComponents(parsed, dead, logs);
  return logs;
}

// The mirror of dropUnplannedParts, and the more common failure. That gate
// catches a component the plan never asked for; nothing caught a plan entry that
// no component realizes — so a part the reference plainly has just quietly is not
// there.
//
// The case that exposed it: a Cloudy Bay bottle whose plan listed "front label"
// with approach wrap-decal AND an artwork bbox pointing at the label's pixels,
// whose identityFeatures named the label twice, and whose spec even declared an
// m-label material — and then authored four components: body, cap, shadow, root.
// No label. Every existing check passed, because they all ask "is this component
// allowed?" and none asks "is every planned part present?".
//
// A declared material that no component uses is the same story from the other
// end: the model planned the part, gave it paint, and never built it. Worth
// saying out loud because it is often the only trace left.
//
// Report only — geometry cannot be invented from a part name.
export function flagUnrealizedParts(parsed: any, analysis: any): string[] {
  let logs: string[] = [];
  let plan: any[] = analysis?.partPlan ?? [];
  let components: any[] = parsed?.components ?? [];
  if (!plan.length || !components.length) return logs;
  let key = (s: any) =>
    String(s ?? '')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '');
  let built = new Set(
    components
      .filter((c: any) => c?.nodeId && c.primitive !== 'group')
      .map((c: any) => key(c.partRef))
      .filter(Boolean),
  );
  // a spec that names no parts at all cannot be compared against a plan — every
  // entry would look missing. In the live pipeline dropUnplannedParts has already
  // deleted anything without a valid partRef by this point, so this only guards
  // against older specs written before partRef was required.
  if (!built.size) return logs;
  // the same tolerant match dropUnplannedParts uses, so 'screwcap' and
  // 'screw cap' are not reported as two different things
  let realized = (planned: string) =>
    [...built].some(
      (b) =>
        b === planned ||
        (planned.length >= 4 && b.includes(planned)) ||
        (b.length >= 4 && planned.includes(b)),
    );
  // A "revolved" part is SUPPOSED to disappear into someone else's profile: the
  // approach directives tell the model to trace body, shoulder, neck and lip as
  // ONE lathe and explicitly forbid adding separate stacked pieces for them. So a
  // bottle's planned "neck" with no component of its own is the rule being obeyed,
  // not a part going missing — as long as a lathe exists to have absorbed it.
  let hasLathe = components.some((c: any) => c?.primitive === 'lathe');
  let missing = plan
    .map((p: any) => ({
      name: p?.part,
      k: key(p?.part),
      absorbable: hasLathe && String(p?.approach ?? '') === 'revolved',
    }))
    .filter((p) => p.k && !p.absorbable && !realized(p.k));
  for (let part of missing) {
    logs.push(
      `'${part.name}' is in the plan but NO component realizes it — that part of the reference will simply be absent`,
    );
  }

  let usedMaterials = new Set(
    components.map((c: any) => key(c?.materialId)).filter(Boolean),
  );
  for (let m of parsed?.materials ?? []) {
    let k = key(m?.materialId);
    if (k && !usedMaterials.has(k)) {
      logs.push(
        `material '${m.materialId}' is declared but no component uses it — usually the paint for a part that was never built`,
      );
    }
  }
  return logs;
}

// The partRef gate above catches parts the plan never mentions, but not the
// other half of padding: burying many invented components under ONE legitimate
// part name. A screwcap the plan calls a single part, realized as a body + top
// + skirt + perforation ring + rib band + 20 radial knurl blocks, passes every
// name check while producing the pile of spare geometry around the cap.
//
// How many components a part honestly needs depends on how it is built, and the
// plan already says: a curved-chain or freeform part IS a chain of overlapping
// volumes, while a boxy / revolved / decal part is one or two pieces. So the
// allowance comes from the part's own approach. This only reports — which of a
// part's components are the invented ones cannot be known from counting, and
// deleting the wrong one would break the part. The log makes the padding
// visible so the refine round or a human can act on it.
export function flagOverbuiltParts(parsed: any, analysis: any): string[] {
  let logs: string[] = [];
  let plan: any[] = analysis?.partPlan ?? [];
  let components: any[] = parsed?.components ?? [];
  if (!plan.length || !components.length) return logs;
  let key = (s: any) =>
    String(s ?? '')
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '');
  // chains and freeform masses are MADE of many overlapping volumes; the rest
  // of the approaches describe one shape, so a handful of pieces is the ceiling
  let allowance = (approach: string): number =>
    approach === 'curved-chain' || approach === 'freeform-mesh' ? 10 : 4;
  let allowanceByPart = new Map<string, number>();
  for (let p of plan) {
    let k = key(p?.part);
    if (k) allowanceByPart.set(k, allowance(String(p?.approach ?? '')));
  }
  let counts = new Map<string, number>();
  for (let c of components) {
    if (!c?.nodeId || c.primitive === 'group') continue;
    if (/shadow/i.test(String(c.nodeId))) continue;
    let k = key(c.partRef);
    if (!k || !allowanceByPart.has(k)) continue;
    counts.set(k, (counts.get(k) ?? 0) + 1);
  }
  for (let [k, count] of counts) {
    let limit = allowanceByPart.get(k) ?? 4;
    if (count <= limit) continue;
    let name = plan.find((p: any) => key(p?.part) === k)?.part ?? k;
    logs.push(
      `'${name}' is one planned part but was built from ${count} components (about ${limit} expected) — likely padded`,
    );
  }
  return logs;
}

// merges a change set over the current spec, returning the same plain shape
// A part that carries a real cropped-artwork image (textureRef) IS the whole
// printed label — a photo of an inkjet sticker with its text, wordmarks,
// crests, borders and illustrations already baked in. When the model ALSO
// stacks re-typed textDecals, a crest disc, or border boxes ON TOP of it, they
// double-print the same content (blurred, offset) and opaque shapes cover the
// real artwork. Drop every flat-graphic part whose attachTo chain leads to a
// textured decal — the image already contains it. Mutates parsed; returns logs.
export function stripRedundantLabelParts(parsed: any): string[] {
  let logs: string[] = [];
  let components: any[] = parsed?.components ?? [];
  let byId = new Map(components.map((c: any) => [c.nodeId, c]));
  // decals that carry a real photo crop — the self-contained printed graphics
  let textured = new Set(
    components.filter((c: any) => c?.textureRef).map((c: any) => c.nodeId),
  );
  if (!textured.size) return logs;
  // flat-graphic primitives are the only ones that re-create printed content;
  // never drop a genuine solid part that happens to touch the label
  let flatGraphic = new Set([
    'textDecal',
    'curvedDecal',
    'disc',
    'plane',
    'roundedPlate',
    'box',
    'extrudedPolygon',
    'extrudedSpline',
  ]);
  let onTextured = (c: any): boolean => {
    let seen = new Set<string>();
    let cur: any = c;
    while (cur?.attachTo && !seen.has(cur.attachTo)) {
      if (textured.has(cur.attachTo)) return true;
      seen.add(cur.attachTo);
      cur = byId.get(cur.attachTo);
    }
    return false;
  };
  let kept: any[] = [];
  for (let c of components) {
    if (
      c?.nodeId &&
      c.textureRef == null &&
      flatGraphic.has(c.primitive) &&
      onTextured(c)
    ) {
      logs.push(
        `dropped '${c.nodeId}' — already printed in the '${c.attachTo}' label image`,
      );
      continue;
    }
    kept.push(c);
  }
  parsed.components = kept;
  return logs;
}
