// The boundary between a model's text and the spec the builders consume:
// parsing each stage's JSON reply, serializing an existing spec back into
// something a model can read, and materializing a parsed reply into a
// SculptSpecField.

import {
  SculptSpecField,
  MaterialSpecField,
  ComponentNodeField,
} from '../fields/sculpt-spec';

// compact plain-JSON view of the current spec for the refine prompt
export function serializeSpecForPrompt(spec: any) {
  if (!spec) return {};
  let arr = (value: unknown) => {
    if (Array.isArray(value)) return [...value];
    try {
      return JSON.parse(typeof value === 'string' ? value : '[]');
    } catch {
      return value;
    }
  };
  return {
    objectName: spec.objectName,
    inputKind: spec.inputKind,
    identityFeatures: spec.identityFeatures ?? [],
    objectClass: spec.objectClass,
    buildBackend: spec.buildBackend,
    complexity: spec.complexity,
    materials: (spec.materials ?? []).map((m: any) => ({
      materialId: m.materialId,
      baseColor: m.baseColor,
      roughness: m.roughness,
      metalness: m.metalness,
      opacity: m.opacity,
      emissive: m.emissive,
      ...(typeof m.emissiveIntensity === 'number'
        ? { emissiveIntensity: m.emissiveIntensity }
        : {}),
      ...(typeof m.clearcoat === 'number' ? { clearcoat: m.clearcoat } : {}),
      ...(typeof m.sheen === 'number' ? { sheen: m.sheen } : {}),
      ...(typeof m.transmission === 'number'
        ? { transmission: m.transmission }
        : {}),
      ...(m.finish ? { finish: m.finish } : {}),
    })),
    components: (spec.components ?? []).map((c: any) => ({
      nodeId: c.nodeId,
      parentId: c.parentId,
      primitive: c.primitive,
      dimensions: arr(c.dimensions),
      position: arr(c.position),
      rotation: arr(c.rotation),
      scale: arr(c.scale),
      materialId: c.materialId,
      ...(c.text ? { text: c.text } : {}),
      ...(c.partRef ? { partRef: c.partRef } : {}),
      ...(c.textureRef ? { textureRef: c.textureRef } : {}),
      ...(c.textureUrl ? { textureUrl: c.textureUrl } : {}),
      // repeat is a {count, mode, offset|radius, axis} OBJECT — pass it
      // through verbatim. Running it through arr() (a coordinate-array
      // normalizer) coerced the object to [], silently destroying every
      // repeat/mirror system on each refine round (applySpecDiff serializes
      // through here), collapsing 6 wheels to one, blade rows to one, etc.
      ...(c.repeat ? { repeat: c.repeat } : {}),
      ...(c.assetUrl ? { assetUrl: c.assetUrl } : {}),
      ...(c.attachTo ? { attachTo: c.attachTo } : {}),
      ...(c.anchor && typeof c.anchor === 'object' ? { anchor: c.anchor } : {}),
      ...(c.grounded === true ? { grounded: true } : {}),
      note: c.note,
    })),
  };
}

// extracts and parses the spec JSON out of a model response, tolerating
// markdown fences and trailing commas
export function parseSpecJson(raw: string) {
  let text = raw.trim();
  let fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) text = fence[1].trim();
  let start = text.indexOf('{');
  let end = text.lastIndexOf('}');
  if (start === -1 || end <= start) {
    throw new Error('the model did not return JSON — try again');
  }
  let body = text.slice(start, end + 1);
  let parsed;
  try {
    parsed = JSON.parse(body);
  } catch {
    // second chance: strip trailing commas, a common LLM slip
    parsed = JSON.parse(body.replace(/,\s*([}\]])/g, '$1'));
  }
  if (!Array.isArray(parsed.components) || parsed.components.length === 0) {
    throw new Error('spec has no components — try again');
  }
  parsed.materials = Array.isArray(parsed.materials) ? parsed.materials : [];
  return parsed;
}

// parses the analysis-stage reply (objectType/partPlan/buildRecipe) — stage 1
// of the v2 pipeline; its recipe is injected into the build request
export function parseAnalysisJson(raw: string) {
  let text = raw.trim();
  let fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) text = fence[1].trim();
  let start = text.indexOf('{');
  let end = text.lastIndexOf('}');
  if (start === -1 || end <= start) {
    throw new Error('the model did not return JSON — try again');
  }
  let body = text.slice(start, end + 1);
  let parsed;
  try {
    parsed = JSON.parse(body);
  } catch {
    parsed = JSON.parse(body.replace(/,\s*([}\]])/g, '$1'));
  }
  if (!Array.isArray(parsed.partPlan) || parsed.partPlan.length === 0) {
    throw new Error('analysis has no part plan — try again');
  }
  parsed.buildRecipe = Array.isArray(parsed.buildRecipe)
    ? parsed.buildRecipe
    : [];
  parsed.identityFeatures = Array.isArray(parsed.identityFeatures)
    ? parsed.identityFeatures
    : [];
  parsed.attachments = Array.isArray(parsed.attachments)
    ? parsed.attachments
    : [];
  // the build directives stage 1 nominates; absent on analyses cached before
  // the field existed, where the plan's own structure supplies them instead
  parsed.directives = Array.isArray(parsed.directives) ? parsed.directives : [];
  if (
    typeof parsed.camera?.azimuthDeg !== 'number' ||
    typeof parsed.camera?.elevationDeg !== 'number'
  ) {
    parsed.camera = undefined;
  }
  return parsed;
}

// parses a refine change-set reply (critique/score/featureCheck + changed/
// removed arrays; all arrays may legitimately be empty)
export function parseDiffJson(raw: string) {
  let text = raw.trim();
  let fence = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) text = fence[1].trim();
  let start = text.indexOf('{');
  let end = text.lastIndexOf('}');
  if (start === -1 || end <= start) {
    throw new Error('the model did not return JSON — try again');
  }
  let body = text.slice(start, end + 1);
  let parsed;
  try {
    parsed = JSON.parse(body);
  } catch {
    parsed = JSON.parse(body.replace(/,\s*([}\]])/g, '$1'));
  }
  parsed.changed = Array.isArray(parsed.changed) ? parsed.changed : [];
  parsed.removedNodeIds = Array.isArray(parsed.removedNodeIds)
    ? parsed.removedNodeIds
    : [];
  parsed.materialsChanged = Array.isArray(parsed.materialsChanged)
    ? parsed.materialsChanged
    : [];
  parsed.added = Array.isArray(parsed.added) ? parsed.added : [];
  return parsed;
}

// materializes a parsed response into a SculptSpecField
export function specFieldFromParsed(parsed: any): SculptSpecField {
  return new SculptSpecField({
    objectName: parsed.objectName || 'Untitled object',
    inputKind: parsed.inputKind === 'flat-graphic' ? 'flat-graphic' : 'object',
    identityFeatures: Array.isArray(parsed.identityFeatures)
      ? parsed.identityFeatures.map((f: any) => String(f)).slice(0, 6)
      : [],
    objectClass: parsed.objectClass,
    buildBackend: parsed.buildBackend,
    complexity: parsed.complexity,
    materials: parsed.materials.map(
      (m: any) =>
        new MaterialSpecField({
          materialId: String(m.materialId ?? ''),
          baseColor: m.baseColor,
          roughness: m.roughness,
          metalness: m.metalness,
          opacity: m.opacity,
          emissive: m.emissive,
          emissiveIntensity:
            typeof m.emissiveIntensity === 'number'
              ? m.emissiveIntensity
              : null,
          clearcoat: typeof m.clearcoat === 'number' ? m.clearcoat : null,
          sheen: typeof m.sheen === 'number' ? m.sheen : null,
          transmission:
            typeof m.transmission === 'number' ? m.transmission : null,
          finish: m.finish ? String(m.finish) : null,
        }),
    ),
    components: parsed.components.map(
      (c: any) =>
        new ComponentNodeField({
          nodeId: String(c.nodeId ?? ''),
          parentId: String(c.parentId ?? ''),
          primitive: c.primitive,
          dimensions: JSON.stringify(c.dimensions ?? []),
          position: JSON.stringify(c.position ?? [0, 0, 0]),
          rotation: JSON.stringify(c.rotation ?? [0, 0, 0]),
          scale: JSON.stringify(c.scale ?? [1, 1, 1]),
          materialId: String(c.materialId ?? ''),
          text: c.text ? String(c.text) : null,
          partRef: c.partRef ? String(c.partRef) : null,
          textureRef: c.textureRef ? String(c.textureRef) : null,
          textureUrl: c.textureUrl ? String(c.textureUrl) : null,
          repeat:
            c.repeat && typeof c.repeat === 'object'
              ? JSON.stringify(c.repeat)
              : typeof c.repeat === 'string'
                ? c.repeat
                : null,
          assetUrl: c.assetUrl ? String(c.assetUrl) : null,
          attachTo: c.attachTo ? String(c.attachTo) : null,
          note: String(c.note ?? ''),
        }),
    ),
  });
}
