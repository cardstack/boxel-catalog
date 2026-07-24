// The spec-generation engine: prompts, the OpenRouter vision call, response
// parsing, comparison-sheet packing, and SculptSpecField construction. The
// card component only orchestrates; everything here is a pure function so
// the pipeline is testable and reusable.

import SendRequestViaProxyCommand from '@cardstack/boxel-host/tools/send-request-via-proxy';

import {
  SculptSpecField,
  MaterialSpecField,
  ComponentNodeField,
  PRIMITIVES,
} from '../fields/sculpt-spec';

export const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
export const VISION_MODEL = 'anthropic/claude-sonnet-5';

// auto refine passes after the initial generation (each costs one vision
// call). The showcase reference builds converge in 5-8 review cycles; we run
// up to 3 automatically and stop early once the model scores itself >= 85.
export const AUTO_REFINE_ROUNDS = 3;
export const REFINE_TARGET_SCORE = 85;

const SPEC_JSON_SHAPE = `JSON shape:
{
  "objectName": "short name",
  "inputKind": "object" | "flat-graphic",
  "objectClass": "hard-surface" | "organic" | "hybrid",
  "complexity": "simple" | "moderate" | "complex",
  "critique": "1-2 sentences: what the rebuild captures and what it approximates",
  "score": 0-100 (honest fidelity estimate of THIS spec, never above 90),
  "identityFeatures": ["3-5 short phrases naming the features that make this object recognizable, e.g. 'black plastic handle loops', 'bright steel blades'"],
  "featureCheck": { "<each identityFeature>": "pass" | "fail" } (refine rounds only: judge each feature against the RENDER),
  "materials": [
    { "materialId": "m-body", "baseColor": "#rrggbb", "roughness": 0..1,
      "metalness": 0..1, "opacity": 0..1, "emissive": "#rrggbb", "emissiveIntensity": 0..2 (optional; 1.5-2 for LEDs/lamps, 0.05-0.3 for faint warmth),
      "clearcoat": 0..1 (optional, glossy coated surfaces),
      "sheen": 0..1 (optional, fabric/silicone),
      "transmission": 0..1 (optional, REAL see-through glass — window panes, bottles, lenses; pair with roughness 0.02-0.15 and metalness 0; the engine renders it with refraction, so prefer this over low opacity for glass),
      "finish": "worn" | "brushed" | "hazard" | "tread" | "camo" | "louver" | "patina" | "knurl" (optional procedural
        surface texture: "worn" = grime/soot/scratches for weathered metal or
        used machines; "brushed" = brushed metal; "hazard" = yellow/black
        caution stripes; "tread" = tire/track blocks; "camo" = organic
        camouflage blotches in tones derived from baseColor (military
        vehicles, patterned panels); "louver" = dark ribbed vent slats
        (grilles, radiators); "patina" = teal-green oxidation blooming from
        the TOP of the surface (aged brass/copper); "knurl" = cross-hatch grip
        relief (knife handles, tool grips). Use on machines, tools,
        vehicles, industrial parts — it is what makes surfaces look real instead of
        plastic) }
  ],
  "components": [
    { "nodeId": "unique-kebab-id", "parentId": "" or an EARLIER nodeId,
      "primitive": "${PRIMITIVES.join('" | "')}",
      "dimensions": [numbers, see semantics],
      "position": [x, y, z], "rotation": [x, y, z] (radians),
      "scale": [x, y, z], "materialId": "m-...",
      "text": "textDecal only: the label text to render",
      "repeat": {"count": N, "mode": "linear", "offset": [x,y,z]} or {"count": N, "mode": "radial", "radius": r, "axis": "x"|"y"|"z"} (optional — expands this part into N placed clones),
      "attachTo": "nodeId of the part this one physically mounts on — REQUIRED for every non-group part except the single base volume. The engine pulls the part into contact with its attachTo if your coordinates leave a gap, so pick the true structural support (baluster → its railing/floor, canopy → its posts, window → its wall)",
      "note": "which identity feature of the photo this represents" }
  ]
}

dimensions semantics: box [w,h,d] · roundedBox [w,h,d,cornerRadius,bevel] (rounded-corner slab lying flat, face up — device bodies, cases) · roundedPlate [w,h,depth,cornerRadius] (rounded-rect plate in the XY plane FACING +Z / the camera — logo backgrounds, signs, screens; needs NO rotation) · cylinder [radiusTop,radiusBottom,height,segments?] · capsule [radius,cylinderLength] · sphere [radius] · hemisphere [radius] (dome, opens downward) · cone [radius,height,segments?] (segments=4 → square PYRAMID for hip roofs/spires, already axis-aligned — use rotation [0,0,0] and shape the footprint with non-uniform scale) · torus [radius,tube] · plane [w,h] · disc [radius] (flat circle facing +Z — dials, hole covers) · flatRing [outerRx,outerRy,ringWidth,depth] (flat elliptical ring with a REAL hole, XY plane facing +Z — scissor handle loops, grab rings, bracelets; NEVER fake these with a squashed torus) · arch [outerR,ringWidth,depth,sweepDeg?] (partial flat ring spanning the top — wheel arches/fenders, bridge handles) · prism [lengthAlongRidge,span,height] (triangular prism, ridge along X — gable roofs, ramps, wedges; no rotation needed) · tube [radius, x0,y0,z0, x1,y1,z1, ...] (smooth tube swept along a 3D curve through the points — USE for laces, cables, hoses, curved handles, piping; 3-6 points give a natural curve) · rock [radius, detail?] (faceted low-poly blob) · blob [radius, bumpiness 0-0.5, seed?, detail?] (smooth freeform mass — a dense sphere mesh displaced by seeded noise; the go-to for soft/organic volumes: cushions, plush bodies, bread, fruit, boulders. Non-uniform scale shapes it; vary seed per part so blobs differ) · glow [size] (camera-facing additive light glow in the material's baseColor — reactor lights, lamps, LEDs) · lathe [x0,y0,x1,y1,...] profile bottom→top (x>=0) · extrudedPolygon [depth, x0,y0, x1,y1, ...] straight-edged polygon outline in the XY plane facing +Z, centered · extrudedSpline [depth, x0,y0, x1,y1, ...] same but the outline is a SMOOTH curve through the points (organic silhouettes: shoe soles, leaves, curved panels — prefer this over extrudedPolygon whenever the reference shape has curved edges) · meshAsset [] (mounts a pre-existing .glb via its "assetUrl" field — ONLY reference asset URLs given to you in the request; NEVER invent one) · textDecal [w,h] (transparent plane rendering the "text" field in the material's baseColor — USE for wordmarks on FLAT surfaces; sits ~0.01 in front; also renders SYMBOL characters — '★' '▲' '●') · curvedDecal [radius, height, arcDeg?] (label/sticker WRAPPED around a cylindrical body — wine labels, can labels, mug prints; radius = the host body's radius + 0.01, arc defaults 120°, material baseColor = the label ground color, "text" = the label's main wordmark, attachTo = the host body; NEVER fake a label on a bottle/can with a flat plate) · group [].

CLASSIFY FIRST — objectClass drives the build strategy (do not default to hard-surface):
- "hard-surface": rigid manufactured forms — electronics, tools, furniture, machines. Strategy: boxes/roundedBoxes/cylinders with crisp bevels.
- "organic": soft or curved natural forms — plants, food, plush toys, clothing, fabric, bodies. Strategy: overlapping sphere/capsule chains, high roughness, sheen for fabric; NO large boxes.
- "hybrid": mixed — footwear (curved leather upper + rigid sole/heel), bags, headphones with pads, upholstered furniture. Strategy: sphere/capsule chains for the soft/curved portions, boxes/cylinders ONLY for the genuinely rigid parts. A leather dress shoe is "hybrid", never "hard-surface".

Material families (set PBR from what the surface IS): polished leather ≈ roughness 0.3-0.45 + clearcoat 0.2; matte leather/rubber ≈ roughness 0.7-0.9, metalness 0; cloth/knit ≈ roughness 0.9 + sheen 0.4-0.7; plastic ≈ roughness 0.4-0.6; metal ≈ metalness 0.9+ with roughness by finish; skin-like ≈ roughness 0.6 + sheen 0.3; glazed ceramic ≈ roughness 0.05-0.15, metalness 0, clearcoat 1.0 (the engine boosts reflections for this combo — a bottle without it reads as matte paint); window/bottle glass ≈ transmission 0.9-1.0 + roughness 0.05 + metalness 0 (see-through with refraction — use for every pane the analysis marks as glass).

ORIENTATION CHEAT SHEET (compute rotations, never guess signs):
- cone / capsule / cylinder point along +Y (tip/length UP) by default.
- tip forward (-Z): rotation [-1.5708, 0, 0] · tip backward (+Z): [1.5708, 0, 0]
- tip right (+X): rotation [0, 0, -1.5708] · tip left (-X): [0, 0, 1.5708]
- A spike/blade array raking FORWARD from a front plate (like a breach plow) = cones with rotation [-1.5708, 0, 0], tips pointing -Z, bases touching the plate.
- After rotating, re-check the part still overlaps its mount — rotation moves the tip, not the base.

Rules:
- Y is up. Size the whole object to roughly 2-3 units. A child's position/rotation is RELATIVE to its parent node — if you are not fully sure of the accumulated transform, parent the component directly to the root group and give it absolute coordinates instead.
- ASSEMBLY IS A GRAPH: every non-group part must physically OVERLAP at least one neighbour by 0.02-0.05 units — compute it, don't eyeball it. In each part's "note", name what it attaches to (e.g. "finger loop — overlaps shank-top's rear end"). Work joint by joint: blade → bolster → shank → loop must form one connected chain; if you move a part, re-check both of its joints. A machine check will list any floating part back to you — a spec with floating parts is a failed spec.
- "lathe" is ONLY for rotationally symmetric parts (vase, bottle, bowl, lamp base). NEVER use lathe for shoes, clothing, animals, or any non-symmetric form.
- HYBRID GENERATION: regular geometric parts (cases, wheels, walls, frames) stay procedural — boxes/cylinders/roundedBoxes with crisp dimensions. Freeform/organic parts (cushions, plush bodies, food, natural masses) use "blob" (non-uniformly scaled, unique seed per part) or a chain of 4-8 OVERLAPPING spheres/capsules laid along the part's centerline, each non-uniformly scaled and overlapping ~40% with the next. NEVER use a box for a curved body — boxes read as bricks; boxes are ONLY for genuinely rectangular parts.
- FLAT-GRAPHIC strategy (logos, icons, symbols, drawings): set inputKind "flat-graphic". Use roundedPlate for the background (it already faces the camera — rotation MUST stay [0,0,0]) and extrudedPolygon (shallow depth ~0.06) for every artwork shape, positioned just in front of the plate (z = plateDepth/2 + 0.03). Everything lives in the XY plane; use ZERO rotations anywhere. Trace the actual silhouette of the artwork with polygon points (12-40 points per shape). Sample baseColor values from the exact pixels of the reference — do not invent or "tastefully adjust" colors. NEVER approximate flat artwork with spheres or tilted boxes.
- FOLLOW THE ANALYSIS: the user message includes an ANALYSIS block (object type, semantic part plan, build recipe) produced by a prior analysis pass over the same photos. Treat its buildRecipe as your own expert construction notes — every partPlan entry must map to components (thin details like railings included — a missing part is a failed build), and every recipe instruction must be visibly honored in the spec. Honor each part's "material" (glass parts get a transmission material, metal gets metalness, etc.), its "surface" note, and its "depthRatio" — depth = bboxWidth × depthRatio is that part's thickness target; do not guess thickness the analysis already measured.
- PROPORTIONS ARE MEASURED, NEVER ASSUMED: for every pair of related parts (stacked, nested, capping, side-by-side) the size ratio between them comes from their analysis bboxes — never from what this kind of object "usually" looks like. A part that caps or shelters another is at least as wide as what it covers, with the overhang read from the bbox comparison (rarely more than 20%). A part's steepness or flatness comes from its own bbox aspect (height ÷ width) — do not substitute a canonical shape for the measured one.
- APPROACH DIRECTIVES (each partPlan approach is an ORDER, not a suggestion — build that part with the named primitive family):
  · revolved → ONE lathe profile traced from the silhouette (bottle, can, vase, lamp base) — not stacked cylinders unless the silhouette truly steps.
  · wrap-decal → curvedDecal wrapped at the host body's radius, attachTo the host — never a flat plate.
  · boxy → roundedBox/box family with crisp bevels.
  · rounded-shell → hemisphere/blob shells.
  · curved-chain → 4-8 overlapping non-uniformly scaled spheres/capsules along the centerline.
  · flat-cutout → extrudedPolygon/extrudedSpline silhouettes.
  · freeform-mesh → blob fallback (unique seed), non-uniformly scaled.
- GEOMETRIC RECONSTRUCTION (semantic recognition is not enough — reconstruct measured geometry): the ANALYSIS gives each part a normalized image bbox. DERIVE dimensions and positions from those numbers, do not eyeball: for parts at similar depth, widthA/widthB = bboxA.width/bboxB.width and heightA/heightB = bboxA.height/bboxB.height; a part's horizontal center ≈ (bbox.left + bbox.width/2) mapped across the object's total width; its vertical placement comes from bbox.top/height mapped down the object's total height (image top = model top). Cross-check every major part's computed size against its bbox ratio before answering.
- ENFORCE THE ATTACHMENTS LIST: each "A <constraint> B" line is a hard joint — centered-above means A's center xz = B's center xz and A's bottom overlaps B's top; attached-right means A's left face overlaps B's right face; inset-into means A sits flush INSIDE B's face (protrude ≤ 0.02); rests-on means A's bottom overlaps B's top. Every attachment must be numerically true in the final coordinates.
- SUPPORT RULE: every component must physically rest on or attach to another — overlap its support by 0.02-0.05 and NAME that support in "attachTo". Nothing hovers: a chair touches the floor, a wheel touches the hull, a sign bolts to its wall. The engine pulls small gaps closed along attachTo joints and drops unattached floaters to the ground; both are flagged as failures.
- COMPOSITION CHECK: before answering, re-verify placement NUMERICALLY for every part — a window lies within its wall's face rectangle, a roof apex sits directly above its volume's center, a railing's ends land on its balcony edges, nothing pokes through a surface it should sit on. Compare each part's position ± half its size against its neighbour's bounds.
- Build a real hierarchy: one root group, then logical sub-groups (body, handle, lid...).
- Minimum component counts: simple >= 8, moderate >= 18, complex >= 30 (a "repeat" part counts as ONE declared component but adds N visual parts — use it generously).
- DETAIL DENSITY: repeated micro-details are what make an object read as real — rivet rows, bolt circles, vent slats, panel studs, tread lugs, wheel sets. Declare each ONCE with a "repeat": rivets along an edge = small sphere + linear repeat; bolts around a hub = cylinder + radial repeat; 6 wheels = one wheel + linear repeat. A vehicle or machine should carry at least 4 such repeat systems. Every identity-defining feature in the photo (bevels, buttons, seams, feet, trim) must map to a component with a note.
- Reuse materials via materialId; 3-8 materials typical. Estimate PBR values from the photo's shading.
- Keep every "note" under 8 words — long notes bloat the reply and get it truncated.
- Numbers only in arrays — no strings, no null.`;

export const SPEC_SYSTEM_PROMPT = `You are a 3D reconstruction engine. You receive one or MORE reference views of the same object and rebuild it as a procedural Three.js primitive tree. Respond with ONLY a JSON object — no markdown fences, no prose.

${SPEC_JSON_SHAPE}`;

// v2 pipeline stage 1: instead of shipping hand-written per-category recipes
// (vehicles, buildings, ...) in the system prompt, the model analyzes THIS
// object and writes its own build recipe — the recipe becomes per-generation
// data that stage 2 (the spec build) is instructed to honor.
export const ANALYZE_SYSTEM_PROMPT = `You are the analysis stage of an image-to-3D pipeline. You receive one or MORE reference views of one object. Do NOT build geometry yet — study the object and write the expert construction plan a procedural modeler will follow. Respond with ONLY a JSON object — no markdown fences, no prose.

COLLAGE / CHARACTER-SHEET REFERENCES: a reference may be a multi-panel sheet (orthographic views, detail crops, a beauty render, text labels, UI chrome). Treat every panel as a view of ONE object. Ignore text bars, borders, logos and background scenery entirely. Sample colors from the OBJECT'S OWN pixels in the flattest-lit panel (usually the orthographic views) — NEVER from scene lighting, rim glow, or a stylized beauty shot; a dark olive machine under warm gold studio light is still dark olive, not gold.

The modeler's vocabulary (its only primitives): ${PRIMITIVES.join(', ')}. It supports per-part "repeat" systems (linear rows, radial circles), procedural finishes (worn/brushed/hazard/tread/camo/louver/patina/knurl), textDecal labels, and glow sprites.

JSON shape:
{
  "objectType": "1-3 words naming what this is (delivery truck, two-story house, running shoe...)",
  "objectClass": "hard-surface" | "organic" | "hybrid",
  "complexity": "simple" | "moderate" | "complex",
  "identityFeatures": ["3-8 short phrases naming what makes this object recognizable — MUST include detail-level features (railings, trims, antennas, fence pickets, grilles), not only the big volumes"],
  "camera": { "azimuthDeg": -180..180 (0 = the FIRST image looks straight at the object's front; positive = camera moved to the object's right), "elevationDeg": 0..60 (0 = eye level), "note": "1 short line, e.g. 'slightly right of front, near eye level'" },
  "partPlan": [
    { "part": "semantic part name (cab, roof, left handle loop...)",
      "approach": "boxy" | "rounded-shell" | "curved-chain" | "revolved" | "flat-cutout" | "wrap-decal" | "freeform-mesh" (revolved = rotationally symmetric bodies: bottles, cans, vases, lamp bases; wrap-decal = labels/stickers/prints on a curved body; freeform-mesh = draped fabric, complex character bodies — routed to a mesh service when available, else blob/curved-chain),
      "bbox": { "left": 0..1, "top": 0..1, "width": 0..1, "height": 0..1 } (this part's bounding box in the FIRST image, normalized to image size — MEASURE it, this drives all proportions),
      "primitives": "which vocabulary primitives fit this part and why (1 sentence)",
      "material": "category + sampled color, e.g. 'painted metal #c23b2e', 'window glass #a8c8d8', 'wood #8a6142' (categories: metal, painted, plastic, wood, glass, fabric, rubber, concrete, ceramic, foliage)",
      "depthRatio": 0.02..2 (this part's DEPTH divided by its bbox width — 0.05 = thin panel/railing, 0.5 = half as deep as wide, 1 = as deep as wide; estimate from side/three-quarter views, this is the thickness target the builder must hit),
      "surface": "matte | satin | gloss | transparent, plus any texture note (1 short phrase) — describe what the REFERENCE shows: a flat-shaded / cartoon reference has clean untextured surfaces, a photo may show wear",
      "details": "repeats / finishes / decals worth adding (1 sentence)" }
  ],
  "attachments": ["one line per structural joint: '<part> <constraint> <part>' using constraints centered-above | flush-top | attached-left | attached-right | attached-front | attached-back | inset-into | rests-on — e.g. 'roof centered-above upper-floor', 'carport attached-right lower-floor', 'windows inset-into front-wall'"],
  "buildRecipe": ["5-12 imperative, object-SPECIFIC construction notes — proportions to respect, orientation pitfalls, what repeats how many times, which surfaces get which finish, where labels go. Write what an expert would pin above the workbench for THIS object."]
}

Rules:
- DECOMPOSE FULLY: break the object down the way a human would describe it piece by piece — every distinct volume, every attachment, every surface detail gets its own partPlan entry with its own material, depth and surface. Whatever the object is, the reader of your plan should be able to rebuild it without ever looking at the photo.
- Part budget scales with complexity: simple = 4-6 parts, moderate = 6-12, complex = up to 16. Use what the object needs — never pad a simple object, never truncate a complex one.
- THIN STRUCTURAL DETAILS ARE PARTS TOO: railings, balusters, handrails, fence pickets, antennas, roof trims, window grilles. Never drop them to save budget — each is ONE part built as a thin cylinder/box with a linear repeat, so it costs one partPlan entry no matter how many pieces repeat.
- MEASURE, don't guess: every bbox comes from actually reading the part's extent in the image. Relative bbox widths/heights become the model's proportions, so a sloppy bbox is a wrong model.
- List an attachment line for EVERY part except the root volume — a part with no attachment will float.
- Recipe notes must be concrete and measurable ("six wheels in two rows of three", "roof overhangs walls by ~15%"), never generic advice.
- objectClass drives strategy: hard-surface = crisp boxes/cylinders; organic = overlapping sphere/capsule chains; hybrid = mix per part.`;

export const REFINE_SYSTEM_PROMPT = `You are a 3D reconstruction engine reviewing your own work. You receive a comparison sheet: the LEFTMOST panel is the reference photo; the remaining labeled panels show the current render (when a "RENDER @ REF ANGLE" pane is present it is captured from the estimated reference camera — judge proportions and placement against the reference there, like-for-like) plus FRONT, SIDE, and THREE-QUARTER angles (flat artwork gets a single head-on render). Use the side view to judge thickness and depth. You also receive the current spec JSON. Find what is visibly wrong and output a MINIMAL CHANGE SET — never the whole spec.

Respond with ONLY this JSON object:
{
  "critique": "1-2 sentences: what you fixed this round",
  "score": 0-100 (honest fidelity estimate AFTER your changes, never above 90),
  "featureCheck": { "<each identityFeature>": "pass" | "fail" },
  "changed": [ COMPLETE component objects (same shape as the spec's components — nodeId, parentId, primitive, dimensions, position, rotation, scale, materialId, text?, repeat?, attachTo?, note) for every component you are adding or modifying — matched by nodeId ],
  "removedNodeIds": [ "node-ids to delete" ],
  "materialsChanged": [ COMPLETE material objects for every material you are adding or modifying — matched by materialId ]
}

Refine conservatively:
- MEASURED TARGETS: the request may include the analysis part list with normalized reference bboxes. Check each part's rendered proportion and position against its bbox ratios (width/height relative to the other parts, horizontal center, vertical band) and fix numeric deviations FIRST — a component with the right shape but the wrong size or placement is still wrong. Pay special attention to related pairs: a covering part must be at least as wide as the volume under it, with the overhang matching the reference — a cap narrower than its base, or one ballooned far wider than the reference shows, is always a fix-first error.
- Touch ONLY what is visibly wrong in the render. Components you do not mention stay exactly as they are — that is the point of the change set.
- Machine-checked assembly problems (floating parts) get fixed FIRST: move the part so it overlaps its neighbour by 0.02-0.05.
- Colors must be sampled from the reference pixels. A brightness difference caused by scene lighting is NOT a color error — if a baseColor hex already matches the reference pixel, do not touch that material.
- For flat-graphic inputs the render is captured head-on: keep the roundedPlate background at rotation [0,0,0]; invisible artwork is behind the plate — fix its z, do not delete it.
- Per-feature gate: judge EVERY identityFeature against the render in "featureCheck". A high global score cannot excuse a failing feature — a failing feature is this round's first priority.
- If nothing needs changing, return empty "changed"/"removedNodeIds"/"materialsChanged" arrays.`;

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    let img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('could not load comparison image'));
    img.src = src;
  });
}

// packs the reference beside one or more labeled render angles into a
// single sheet — the model reviews exactly one image per round, but sees the
// build from every side (3D errors hide from single angles)
export async function composeComparison(
  referenceDataUrl: string,
  renderDataUrls: string | string[],
  opts?: { firstIsReferenceAngle?: boolean },
): Promise<string> {
  let renders = Array.isArray(renderDataUrls)
    ? renderDataUrls
    : [renderDataUrls];
  let images = await Promise.all([referenceDataUrl, ...renders].map(loadImage));
  const H = renders.length > 1 ? 384 : 512;
  const LABEL = 22;
  const GAP = 6;
  let angleLabels = opts?.firstIsReferenceAngle
    ? ['RENDER @ REF ANGLE', 'RENDER FRONT', 'RENDER SIDE', 'RENDER 3/4']
    : ['RENDER FRONT', 'RENDER SIDE', 'RENDER 3/4'];
  let labels = [
    'REFERENCE',
    ...(renders.length > 1 ? angleLabels.slice(0, renders.length) : ['RENDER']),
  ];
  let widths = images.map((img) =>
    Math.max(1, Math.round((img.width / img.height) * H)),
  );
  let canvas = document.createElement('canvas');
  canvas.width = widths.reduce((a, b) => a + b, 0) + GAP * (images.length - 1);
  canvas.height = H + LABEL;
  let ctx = canvas.getContext('2d')!;
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  let x = 0;
  for (let i = 0; i < images.length; i++) {
    ctx.fillStyle = '#111111';
    ctx.font = '700 13px Arial';
    ctx.textBaseline = 'top';
    ctx.fillText(labels[i] ?? '', x + 4, 4);
    ctx.drawImage(images[i], x, LABEL, widths[i], H);
    x += widths[i] + GAP;
  }
  return canvas.toDataURL('image/jpeg', 0.85);
}

// compact plain-JSON view of the current spec for the refine prompt
export function serializeSpecForPrompt(spec: any) {
  if (!spec) return {};
  let arr = (s: string | null | undefined) => {
    try {
      return JSON.parse(s ?? '[]');
    } catch {
      return s;
    }
  };
  return {
    objectName: spec.objectName,
    inputKind: spec.inputKind,
    identityFeatures: spec.identityFeatures ?? [],
    objectClass: spec.objectClass,
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
      ...(c.repeat ? { repeat: arr(c.repeat) } : {}),
      ...(c.assetUrl ? { assetUrl: c.assetUrl } : {}),
      ...(c.attachTo ? { attachTo: c.attachTo } : {}),
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
  return parsed;
}

// merges a change set over the current spec, returning the same plain shape
// specFieldFromParsed consumes — refine rounds rebuild only what changed
export function applySpecDiff(currentSpec: any, diff: any) {
  let base = serializeSpecForPrompt(currentSpec) as any;
  let components = new Map<string, any>(
    (base.components ?? []).map((c: any) => [c.nodeId, c]),
  );
  for (let c of diff.changed) {
    if (c?.nodeId) components.set(String(c.nodeId), c);
  }
  for (let id of diff.removedNodeIds) {
    components.delete(String(id));
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

// one vision round-trip through the Boxel proxy, returning the parsed spec.
// Retries transient failures (rate limit / upstream error / dropped
// connection / invalid JSON / truncation) with backoff, appending a
// corrective nudge on content failures. Network drops get extra attempts:
// the browser kills every in-flight fetch when the machine's network
// changes (ERR_NETWORK_CHANGED — Wi-Fi hop, VPN reconnect), and these
// vision calls run for minutes, so a single flap mid-request is common.
export async function requestSpec(
  commandContext: any,
  llmModel: string,
  systemPrompt: string,
  userContent: any[],
  onLog?: (line: string) => void,
  parser: (raw: string) => any = parseSpecJson,
) {
  let attempt = async (extraNudge?: string) => {
    let content = extraNudge
      ? [...userContent, { type: 'text', text: extraNudge }]
      : userContent;
    let proxy = new SendRequestViaProxyCommand(commandContext);
    let result = await proxy.execute({
      url: OPENROUTER_URL,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      requestBody: JSON.stringify({
        model: llmModel,
        max_tokens: 24000,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content },
        ],
      }),
    });
    let response = result?.response;
    if (!response) {
      throw new Error('proxy returned no response');
    }
    if (response.status === 403) {
      throw new Error(
        'AI request rejected (403) — you may be out of AI credits.',
      );
    }
    if (response.status >= 400) {
      let body = '';
      try {
        body = (await response.text()).slice(0, 120);
      } catch {
        // body unavailable
      }
      let err: any = new Error(
        `vision request failed: ${response.status}${body ? ` — ${body}` : ''}`,
      );
      err.status = response.status;
      throw err;
    }
    let payload = await response.json();
    let choice = payload?.choices?.[0];
    if (choice?.finish_reason === 'length') {
      let err: any = new Error(
        'the spec got too long and was truncated — retrying with shorter notes',
      );
      err.truncated = true;
      throw err;
    }
    return parser(choice?.message?.content ?? '');
  };

  const MAX_ATTEMPTS = 4;
  const RETRY_DELAYS_MS = [2000, 5000, 10000];
  let lastError: any;
  for (let i = 0; i < MAX_ATTEMPTS; i++) {
    let nudge: string | undefined;
    if (lastError?.truncated) {
      nudge =
        'Your previous reply was truncated. Reply with ONLY the JSON object and keep every "note" under 8 words.';
    } else if (lastError?.contentFailure) {
      nudge =
        'Your previous reply was not valid JSON. Reply with ONLY the JSON object — no prose, no markdown fences.';
    }
    try {
      return await attempt(nudge);
    } catch (e: any) {
      let transientHttp =
        e?.status === 429 || (typeof e?.status === 'number' && e.status >= 500);
      let networkDrop = /Failed to fetch|NetworkError|network changed/i.test(
        e?.message ?? '',
      );
      let contentFailure =
        e?.truncated ||
        /did not return JSON|no components/i.test(e?.message ?? '');
      if (!transientHttp && !networkDrop && !contentFailure) throw e;
      e.contentFailure = contentFailure;
      lastError = e;
      if (i === MAX_ATTEMPTS - 1) break;
      onLog?.(
        `> retrying ${i + 1}/${MAX_ATTEMPTS - 1} (${
          networkDrop ? 'connection dropped' : (e?.status ?? 'invalid response')
        })…`,
      );
      await new Promise((r) => setTimeout(r, RETRY_DELAYS_MS[i] ?? 10000));
    }
  }
  throw lastError;
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
