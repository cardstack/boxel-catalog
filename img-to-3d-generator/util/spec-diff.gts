// Applying a model-authored change set to an existing spec.
//
// The refine and targeted-edit stages reply with a diff, not a whole spec,
// which is the only reason a scoped edit stays scoped. What may change is
// deliberately narrow — a part's primitive is frozen on both paths, because
// turning a box into a sphere is never what an edit meant.

import { serializeSpecForPrompt } from './spec-io';

export function applySpecDiff(
  currentSpec: any,
  diff: any,
  opts: {
    allowRemoval?: boolean;
    // A user-directed edit may RESIZE a part and ADD new ones; the automatic
    // refine pass may not. Refine judges a render against a photo and re-places
    // what it sees, and letting it resize or invent parts turns a correction
    // loop into an unsupervised rebuild. A person asking for a taller label or
    // a missing one restored is a different situation: they are looking at the
    // result and they asked.
    allowReshape?: boolean;
    allowAdditions?: boolean;
  } = {},
) {
  let base = serializeSpecForPrompt(currentSpec) as any;
  let components = new Map<string, any>(
    (base.components ?? []).map((c: any) => [c.nodeId, c]),
  );
  // `primitive` stays frozen on BOTH paths. Dimensions and placement describe a
  // shape's size and where it sits; the primitive is what kind of thing it is,
  // and silently turning a box into a blob is never what an edit instruction
  // meant. Unknown nodeIds are ignored.
  for (let c of diff.changed) {
    if (!c?.nodeId) continue;
    let existing = components.get(String(c.nodeId));
    if (!existing) continue;
    components.set(String(c.nodeId), {
      ...existing,
      ...(c.position !== undefined ? { position: c.position } : {}),
      ...(c.rotation !== undefined ? { rotation: c.rotation } : {}),
      ...(c.scale !== undefined ? { scale: c.scale } : {}),
      ...(opts.allowReshape && c.dimensions !== undefined
        ? { dimensions: c.dimensions }
        : {}),
      ...(c.grounded !== undefined ? { grounded: c.grounded } : {}),
      ...(c.materialId !== undefined
        ? { materialId: String(c.materialId) }
        : {}),
    });
  }
  // new parts, for restoring something the build left out. A duplicate nodeId
  // would silently replace an existing part, and a component with no primitive
  // cannot be built, so both are refused rather than merged.
  if (opts.allowAdditions && Array.isArray(diff.added)) {
    for (let c of diff.added) {
      let id = c?.nodeId ? String(c.nodeId) : '';
      if (!id || !c?.primitive || components.has(id)) continue;
      components.set(id, {
        nodeId: id,
        parentId: c.parentId ?? null,
        primitive: String(c.primitive),
        dimensions: c.dimensions ?? [],
        position: c.position ?? [0, 0, 0],
        rotation: c.rotation ?? [0, 0, 0],
        scale: c.scale ?? [1, 1, 1],
        materialId: c.materialId ?? null,
        text: c.text ?? null,
        partRef: c.partRef ?? null,
        textureRef: c.textureRef ?? null,
        textureUrl: c.textureUrl ?? null,
        repeat: c.repeat ?? null,
        attachTo: c.attachTo ?? null,
        grounded: c.grounded ?? null,
        note: c.note ?? null,
      });
    }
  }
  // lasso targeted edit only: drop removed parts AND anything parented to them
  if (opts.allowRemoval && Array.isArray(diff.removedNodeIds)) {
    let dead = new Set<string>(diff.removedNodeIds.map((x: any) => String(x)));
    let changed = true;
    while (changed) {
      changed = false;
      for (let c of components.values()) {
        if (
          c.parentId != null &&
          dead.has(String(c.parentId)) &&
          !dead.has(String(c.nodeId))
        ) {
          dead.add(String(c.nodeId));
          changed = true;
        }
      }
    }
    for (let id of dead) components.delete(id);
  }
  let materials = new Map<string, any>(
    (base.materials ?? []).map((m: any) => [m.materialId, m]),
  );
  for (let m of diff.materialsChanged) {
    if (m?.materialId) materials.set(String(m.materialId), m);
  }
  return {
    objectName: diff.objectName ?? base.objectName,
    inputKind: diff.inputKind ?? base.inputKind,
    objectClass: diff.objectClass ?? base.objectClass,
    complexity: diff.complexity ?? base.complexity,
    identityFeatures: Array.isArray(diff.identityFeatures)
      ? diff.identityFeatures
      : (base.identityFeatures ?? []),
    critique: diff.critique,
    score: diff.score,
    featureCheck: diff.featureCheck,
    materials: [...materials.values()],
    components: [...components.values()],
  };
}
