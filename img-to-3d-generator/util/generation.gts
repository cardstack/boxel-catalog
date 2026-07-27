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
// the analysis stage is the gate for the whole pipeline — it classifies the
// object, measures per-part bboxes, and decides which parts are 'revolved'
// (which drives deterministic silhouette tracing). It needs the strongest
// vision + spatial-measurement model regardless of which model the user picks
// for spec generation, so it is pinned rather than following llmModel.
export const ANALYSIS_MODEL = 'anthropic/claude-opus-4.8';
// the vision models offered anywhere a model can be picked (studio) or
// recorded (each SculptedModel round, the analyze command) — one shared list
// so every "model" field enumerates the same options. VISION_MODEL must stay
// a member so the programmatic default is always a valid enum value.
export const VISION_MODEL_OPTIONS = [
  'anthropic/claude-sonnet-5',
  'anthropic/claude-sonnet-4.6',
  'anthropic/claude-opus-4.8',
  'google/gemini-3.5-flash',
  'google/gemini-3.6-flash',
];

// auto refine passes after the initial generation (each costs one vision
// call and several minutes). Default 0: one generate = one model file; set
// >0 to re-enable the render-vs-reference correction loop.
export const AUTO_REFINE_ROUNDS = 0;
export const REFINE_TARGET_SCORE = 85;

// Every stage of this pipeline is a MEASUREMENT, not a creative act: the
// analysis reads bboxes off a photo, the spec derives coordinates from those
// bboxes, the refine pass corrects placement. Sampling has nothing to
// contribute to any of them — it only makes the same photo produce a
// different object type, a different part count and differently placed parts
// on every run. Left unset, the request inherits the provider's default
// (~1.0), which is why two Generates on one reference never matched. Pin it
// at 0 so a reference maps to one reconstruction.
export const SPEC_TEMPERATURE = 0;

// temperature 0 alone is not bit-reproducible — it picks the argmax token,
// and ties/batching still drift. `seed` closes the rest of the gap on
// providers that honour it (Gemini and OpenAI-family; Anthropic ignores it
// harmlessly), so both are sent. Derived from the reference URLs rather than
// random: same photos in, same seed, same model — while a new photo set gets
// its own seed instead of inheriting the previous object's sampling path.
export function seedFromStrings(parts: string[]): number {
  // FNV-1a, 32-bit — tiny, dependency-free, well distributed over short
  // strings. Kept below 2^31 because some providers reject larger seeds.
  let hash = 0x811c9dc5;
  for (let part of parts) {
    for (let i = 0; i < part.length; i++) {
      hash ^= part.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    // separator so ['ab','c'] and ['a','bc'] do not collide
    hash ^= 0x2f;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash % 0x7fffffff;
}

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
      "partRef": "REQUIRED: exact analysis partPlan 'part' name this component realizes; every visible non-group component must have one so measured proportions can be reconciled before export",
      "textureRef": "textDecal/curvedDecal only: the analysis partPlan 'part' name whose photo region carries this part's REAL artwork (labels, logos, printed graphics, screens). The engine crops that bbox out of the reference photo and applies it as the decal's texture — ALWAYS prefer this over 'text' when the reference shows actual artwork; use 'text' only for plain lettering",
      "repeat": {"count": N, "mode": "linear", "offset": [x,y,z]} or {"count": N, "mode": "radial", "radius": r, "axis": "x"|"y"|"z"} (optional — expands this part into N placed clones),
      "attachTo": "nodeId of the part this one physically mounts on — REQUIRED for every non-group part except the single base volume. The engine pulls the part into contact with its attachTo if your coordinates leave a gap, so pick the true structural support (baluster → its railing/floor, canopy → its posts, window → its wall)",
      "anchor": "optional PRECISE placement on a target's box FACE instead of world coords — {\\"targetId\\": nodeId, \\"face\\": \\"front|back|left|right|top|bottom\\", \\"uv\\": [u,v] 0..1 across that face, \\"normalOffset\\": small gap out from the face}. USE for every part that sits ON a surface at a specific spot: windows, doors, balconies, railings, awnings, trims, wall vents, signage. u=0 is the face's left/bottom edge, u=1 its right/top; the engine computes the exact world position, so you don't have to. When you set anchor you can leave position at [0,0,0].",
      "grounded": "optional true — set ONLY on parts that rest on the GROUND: the main building/vehicle body, trees, cars, fences, freestanding props. The engine drops them so their bottom sits on the ground plane. NEVER set it on roofs, windows, doors, balconies, railings, or anything mounted on another part.",
      "note": "which identity feature of the photo this represents" }
  ]
}

dimensions semantics: box [w,h,d] · roundedBox [w,h,d,cornerRadius,bevel] (rounded-corner slab lying flat, face up — device bodies, cases) · roundedPlate [w,h,depth,cornerRadius] (rounded-rect plate in the XY plane FACING +Z / the camera — logo backgrounds, signs, screens; needs NO rotation) · cylinder [radiusTop,radiusBottom,height,segments?] · capsule [radius,cylinderLength] · sphere [radius] · hemisphere [radius] (dome, opens downward) · cone [radius,height,segments?] (segments=4 → square PYRAMID for hip roofs/spires. The ENGINE squares it up for you, so its edges already run along X and Z: its Y rotation MUST be 0. Do not "fix" its orientation with a 45° rotation the way plain three.js needs — that stacks with the engine's own correction into 90°, turning the roof back into a diamond whose corners stick out past the walls. Shape the footprint with non-uniform scale only. Footprint width = radius × 1.414, so for a roof that overhangs a wall of width w by ~15%, radius ≈ 0.81 × w/2) · torus [radius,tube] (ring standing UPRIGHT in the XY plane, hole facing the camera — this is three.js's own orientation and it is almost never what you want. A collar/band around an upright body (bottle lip ring, cap ribbing, barrel hoop) is rotation [-1.5708, 0, 0], which lays the hole face up. A wheel hub ring, facing sideways out of the vehicle's flank, is rotation [0, 1.5708, 0]. An unrotated torus is a hoop standing beside the object, which is a bug in every case I have seen) · plane [w,h] · disc [radius] (flat circle facing +Z — dials, hole covers) · flatRing [outerRx,outerRy,ringWidth,depth] (flat elliptical ring with a REAL hole, XY plane facing +Z — scissor handle loops, grab rings, bracelets; NEVER fake these with a squashed torus) · arch [outerR,ringWidth,depth,sweepDeg?] (partial flat ring spanning the top — wheel arches/fenders, bridge handles) · prism [lengthAlongRidge,span,height] (triangular prism, ridge along X — gable roofs, ramps, wedges; no rotation needed) · tube [radius, x0,y0,z0, x1,y1,z1, ...] (smooth tube swept along a 3D curve through the points — USE for laces, cables, hoses, curved handles, piping; 3-6 points give a natural curve) · rock [radius, detail?] (faceted low-poly blob) · blob [radius, bumpiness 0-0.5, seed?, detail?] (smooth freeform mass — a dense sphere mesh displaced by seeded noise; the go-to for soft/organic volumes: cushions, plush bodies, bread, fruit, boulders. Non-uniform scale shapes it; vary seed per part so blobs differ) · glow [size] (camera-facing additive light glow in the material's baseColor — reactor lights, lamps, LEDs) · lathe [x0,y0,x1,y1,...] profile bottom→top (x>=0) · extrudedPolygon [depth, x0,y0, x1,y1, ...] straight-edged polygon outline in the XY plane facing +Z, centered · extrudedSpline [depth, x0,y0, x1,y1, ...] same but the outline is a SMOOTH curve through the points (organic silhouettes: shoe soles, leaves, curved panels — prefer this over extrudedPolygon whenever the reference shape has curved edges) · meshAsset [] (mounts a pre-existing .glb via its "assetUrl" field — ONLY reference asset URLs given to you in the request; NEVER invent one) · textDecal [w,h] (transparent plane rendering the "text" field in the material's baseColor — USE for wordmarks on FLAT surfaces; sits ~0.01 in front; also renders SYMBOL characters — '★' '▲' '●') · curvedDecal [radius, height, arcDeg?] (label/sticker WRAPPED around a cylindrical body — wine labels, can labels, mug prints; radius = the host body's radius + 0.01, arc defaults 120°, material baseColor = the label ground color, "text" = the label's main wordmark, attachTo = the host body; NEVER fake a label on a bottle/can with a flat plate) · group [].

CLASSIFY FIRST — objectClass drives the build strategy (do not default to hard-surface):
- "hard-surface": rigid manufactured forms — electronics, tools, furniture, machines. Strategy: boxes/roundedBoxes/cylinders with crisp bevels.
- "organic": soft or curved natural forms — plants, food, plush toys, clothing, fabric, bodies. Strategy: overlapping sphere/capsule chains, high roughness, sheen for fabric; NO large boxes.
- "hybrid": mixed — footwear (curved leather upper + rigid sole/heel), bags, headphones with pads, upholstered furniture. Strategy: sphere/capsule chains for the soft/curved portions, boxes/cylinders ONLY for the genuinely rigid parts. A leather dress shoe is "hybrid", never "hard-surface".

Material families (set PBR from what the surface IS): polished leather ≈ roughness 0.3-0.45 + clearcoat 0.2; matte leather/rubber ≈ roughness 0.7-0.9, metalness 0; cloth/knit ≈ roughness 0.9 + sheen 0.4-0.7; plastic ≈ roughness 0.4-0.6; metal ≈ metalness 0.9+ with roughness by finish; skin-like ≈ roughness 0.6 + sheen 0.3; glazed ceramic ≈ roughness 0.05-0.15, metalness 0, clearcoat 1.0 (the engine boosts reflections for this combo — a bottle without it reads as matte paint); window/bottle glass ≈ transmission 0.9-1.0 + roughness 0.05 + metalness 0 (see-through with refraction — use for every pane the analysis marks as glass).

CANONICAL WORLD FRAME (fixed for EVERY object — never rotate the whole body off these axes):
- +Y is UP. -Z is FORWARD (the front of a vehicle/machine/creature — the face shown in a front view). +X is the object's RIGHT.
- Lay a directional object's LENGTH along Z with its front at -Z, its WIDTH along X, its HEIGHT along Y. A truck's cab→tail runs along Z, NOT along X. Do NOT lay the body length along X — every rotation number below assumes this frame, so an off-axis body makes the wheels look flat and the spikes point sideways.
- WHEELS: the axle runs along X (left-right). Build one wheel as a cylinder rotated [0, 0, 1.5708] so its axle points along X and it rolls in Z. Place the axles with a linear repeat along Z (front-to-back), and mirror the left and right rows along X (two rows, one at +X width, one at -X). A 6-wheel truck = 3 axle positions × 2 sides.
- FRONT PLOW / RAM TINES: rake toward -Z (rotation [-1.5708, 0, 0]) and repeat ACROSS the width along X — never along Z.

ORIENTATION CHEAT SHEET (compute rotations, never guess signs — all relative to the CANONICAL WORLD FRAME above):
- cone / capsule / cylinder point along +Y (tip/length UP) by default.
- tip forward (-Z): rotation [-1.5708, 0, 0] · tip backward (+Z): [1.5708, 0, 0]
- tip right (+X): rotation [0, 0, -1.5708] · tip left (-X): [0, 0, 1.5708]
- a rolling wheel (axle along X): cylinder rotation [0, 0, 1.5708].
- torus stands UPRIGHT by default (ring in the XY plane, axis +Z). It ALWAYS needs a rotation: a flat collar/band round an upright body is [-1.5708, 0, 0]; a wheel hub facing out of the flank is [0, 1.5708, 0]. Leaving it at [0, 0, 0] leaves a hoop standing beside the object.
- A spike/blade array raking FORWARD from a front plate (like a breach plow) = cones with rotation [-1.5708, 0, 0], tips pointing -Z, bases touching the plate.
- After rotating, re-check the part still overlaps its mount — rotation moves the tip, not the base.

Rules:
- Y is up. Size the whole object to roughly 2-3 units. A child's position/rotation is RELATIVE to its parent node — if you are not fully sure of the accumulated transform, parent the component directly to the root group and give it absolute coordinates instead.
- ASSEMBLY IS A GRAPH: every non-group part must physically OVERLAP at least one neighbour by 0.02-0.05 units — compute it, don't eyeball it. In each part's "note", name what it attaches to (e.g. "finger loop — overlaps shank-top's rear end"). Work joint by joint: blade → bolster → shank → loop must form one connected chain; if you move a part, re-check both of its joints. A machine check will list any floating part back to you — a spec with floating parts is a failed spec.
- "lathe" is ONLY for rotationally symmetric parts (vase, bottle, bowl, lamp base). NEVER use lathe for shoes, clothing, animals, or any non-symmetric form.
- LATHE PROFILES ARE TRACED, NOT INVENTED: read the silhouette's half-width at 5-8 heights in the reference and write those (x,y) pairs bottom→top. A straight vertical wall = the SAME x repeated at two heights (a container body is a straight wall over most of its height — if your profile's x changes steadily with y you have drawn a CONE, which is almost always wrong). Shoulders are a short curve near the top, not a taper from the base.
- MEASURE WHERE THE WIDTH CHANGES, DON'T GUESS: every transition (where the wall starts narrowing, where the neck begins) sits at a specific FRACTION of the object's total silhouette height in the reference — measure that fraction from the photo and place the (x,y) pair there. Do not compress the main body or stretch the neck to a "typical" shape; a label or band that later floats off the wall is the symptom of a transition placed at the wrong height. Trace the FULL silhouette from the base all the way to the very top so the profile alone reproduces the whole outline.
- HYBRID GENERATION: regular geometric parts (cases, wheels, walls, frames) stay procedural — boxes/cylinders/roundedBoxes with crisp dimensions. Freeform/organic parts (cushions, plush bodies, food, natural masses) use "blob" (non-uniformly scaled, unique seed per part) or a chain of 4-8 OVERLAPPING spheres/capsules laid along the part's centerline, each non-uniformly scaled and overlapping ~40% with the next. NEVER use a box for a curved body — boxes read as bricks; boxes are ONLY for genuinely rectangular parts.
- FLAT-GRAPHIC strategy (logos, icons, symbols, drawings): set inputKind "flat-graphic". Use roundedPlate for the background (it already faces the camera — rotation MUST stay [0,0,0]), positioned so each artwork shape sits just in front of the plate (z = plateDepth/2 + 0.03), depth ~0.06. Everything lives in the XY plane; use ZERO rotations anywhere. Sample baseColor values from the exact pixels of the reference — do not invent or "tastefully adjust" colors. NEVER approximate flat artwork with spheres or tilted boxes.
  · CHOOSE THE OUTLINE PRIMITIVE BY THE SHAPE, not by habit: "extrudedSpline" curves smoothly through its points, "extrudedPolygon" joins them with straight lines. A brush stroke, a petal, a leaf, a rounded ray, a droplet, a hand-drawn mark — anything whose edges curve or whose tip is rounded — is extrudedSpline. Only genuinely straight-edged artwork (a chevron, a triangle, a rectangular bar) is extrudedPolygon. Four points joined by straight lines can only ever be a sharp kite: a starburst of soft rounded strokes came out as hard triangular spikes because each ray was authored as a 4-point polygon.
  · POINT COUNT IS THE RESOLUTION OF THE SHAPE: 12-40 points per outline. A rounded tip alone needs 5-6 points to read as round. Fewer points is not simpler, it is a different shape.
  · SEPARATE THE DEPTHS of shapes that overlap: give each one its own z, a hair apart (0.105, 0.1055, 0.106 …). Coplanar overlapping faces at an identical z have no depth order, so the renderer flickers between them as the camera moves — twelve rays meeting at a hub all sharing one z made the middle of an icon strobe.
- REAL ARTWORK BEATS LETTERING: whenever a part carries printed graphics the reference shows — a label, stencil, placard, badge, screen, painted marking — set "textureRef" to that part's plan name so the engine crops the actual pixels out of the reference and applies them. A part whose plan entry has an "artwork" bbox is telling you exactly that. Spelling the words out with "text" instead produces flat lettering in the wrong font, and stacking two text decals to imitate a panel is strictly worse than one crop of the panel itself.
- FOLLOW THE ANALYSIS: the user message includes an ANALYSIS block (object type, semantic part plan, build recipe) produced by a prior analysis pass over the same photos. Treat its buildRecipe as your own expert construction notes — every partPlan entry must map to components (thin details like railings included — a missing part is a failed build), and every recipe instruction must be visibly honored in the spec. Honor each part's "material" (glass parts get a transmission material, metal gets metalness, etc.), its "surface" note, and its "depthRatio" — depth = bboxWidth × depthRatio is that part's thickness target; do not guess thickness the analysis already measured.
- PROPORTIONS ARE MEASURED, NEVER ASSUMED: for every pair of related parts (stacked, nested, capping, side-by-side) the size ratio between them comes from their analysis bboxes — never from what this kind of object "usually" looks like. A part that caps or shelters another is at least as wide as what it covers, with the overhang read from the bbox comparison (rarely more than 20%). A part's steepness or flatness comes from its own bbox aspect (height ÷ width) — do not substitute a canonical shape for the measured one.
- APPROACH DIRECTIVES (each partPlan approach is an ORDER, not a suggestion — build that part with the named primitive family):
  · revolved → ONE lathe profile that traces the ENTIRE silhouette top-to-bottom (for a bottle: body, shoulder, neck AND lip all in the same profile). Do NOT also add separate stacked cylinders/cones for the neck, lip, or any part the lathe already covers — that duplicates geometry and the extra pieces end up floating above the profile. The only additional parts on a revolved body are decals (labels, foil wraps) and genuinely non-symmetric attachments.
  · wrap-decal → curvedDecal wrapped at the host body's radius, attachTo the host — never a flat plate.
  · boxy → roundedBox/box family with crisp bevels.
  · rounded-shell → hemisphere/blob shells.
  · curved-chain → 4-8 overlapping non-uniformly scaled spheres/capsules along the centerline.
  · flat-cutout → extrudedPolygon/extrudedSpline silhouettes.
  · freeform-mesh → blob fallback (unique seed), non-uniformly scaled.
- GEOMETRIC RECONSTRUCTION (semantic recognition is not enough — reconstruct measured geometry): the ANALYSIS gives each part a normalized image bbox. DERIVE dimensions and positions from those numbers, do not eyeball: for parts at similar depth, widthA/widthB = bboxA.width/bboxB.width and heightA/heightB = bboxA.height/bboxB.height; a part's horizontal center ≈ (bbox.left + bbox.width/2) mapped across the object's total width; its vertical placement comes from bbox.top/height mapped down the object's total height (image top = model top). Cross-check every major part's computed size against its bbox ratio before answering.
- ENFORCE THE ATTACHMENTS LIST: each "A <constraint> B" line is a hard joint — centered-above means A's center xz = B's center xz and A's bottom overlaps B's top; attached-right means A's left face overlaps B's right face; inset-into means A sits flush INSIDE B's face (protrude ≤ 0.02); rests-on means A's bottom overlaps B's top. Every attachment must be numerically true in the final coordinates.
- SUPPORT RULE: every component must physically rest on or attach to another — overlap its support by 0.02-0.05 and NAME that support in "attachTo". Nothing hovers: a chair touches the floor, a wheel touches the hull, a sign bolts to its wall. The engine pulls small gaps closed along attachTo joints and drops unattached floaters to the ground; both are flagged as failures.
- ANCHOR SURFACE-MOUNTED PARTS, DON'T EYEBALL THEM: for anything that sits ON a face at a spot — windows, doors, balconies, railings, awnings, wall vents, trims, badges — use the "anchor" field ({targetId, face, uv, normalOffset}) instead of hand-computing world coords. The engine places it exactly on that wall/roof face at the (u,v) you give, so it can never float off or sink into the wall. This is the reliable way to position architectural detail — reach for it before authoring raw positions.
- GROUND PLACEMENT IS A FLAG, NOT A HEIGHT: for a tilted/isometric view you cannot read an object's ground depth from how high it sits in the image (a farther prop just looks higher). So do NOT try to author ground-object heights — set "grounded": true on each thing that rests on the ground (building body, trees, cars, fences, props) and let the engine drop it onto the ground plane. Only their horizontal (x,z) placement and size come from you; their height is solved.
- COMPOSITION CHECK: before answering, re-verify placement NUMERICALLY for every part — a window lies within its wall's face rectangle, a roof apex sits directly above its volume's center, a railing's ends land on its balcony edges, nothing pokes through a surface it should sit on. Compare each part's position ± half its size against its neighbour's bounds.
- Build a real hierarchy: one root group, then logical sub-groups (body, handle, lid...).
- THE PART BUDGET COMES FROM THE PLAN, NOT FROM A NUMBER: every partPlan entry must map to at least one component, and a single part may honestly need several (a shoe's upper is a chain of spheres; a screwcap is a cylinder plus a top). But NEVER add a component the reference does not show in order to look thorough. There is no quota to fill: a bottle rebuilt from 5 correct parts is a success, and the same bottle padded to 18 with invented neck rings and mould seams is a failure. The request states the plan's part count — author within reach of it, and if you find yourself asking "what else could I add", stop.
- A FINISH COVERS THE WHOLE PART, SO ONLY USE ONE THE WHOLE PART HAS. Two ways this goes wrong:
  · "camo" paints camouflage blotches over everything the material touches. Use it ONLY when the reference visibly shows a camouflage PATTERN. A military vehicle painted in one flat colour is not camouflaged — putting camo on it smears blotches across a clean painted hull and is the most obviously wrong thing in the render.
  · a LOCALISED pattern is a separate thin PANEL, not the host's material. Reference hazard striping is a narrow warning band along one edge; a vent grille is a panel on the rear. Setting "hazard" on the whole nose plate, or "louver" on the whole engine block, stripes or ribs the entire volume. Author a thin box laid on that surface and give the FINISH to that panel, leaving the host its own paint.
- DETAIL DENSITY — ONLY WHAT THE REFERENCE ACTUALLY SHOWS: repeated micro-details are what make a MACHINE read as real, so when the photo visibly carries rivet rows, bolt circles, vent slats, tread lugs or wheel sets, declare each ONCE with a "repeat" (rivets along an edge = small sphere + linear repeat; bolts around a hub = cylinder + radial repeat; 6 wheels = one wheel + linear repeat) — a truck or industrial machine usually earns several. Do NOT manufacture repeats for an object that has none: a bottle, a mug or a phone carries no rivet rows, and its smooth surfaces must stay smooth.
- A ROOF PIERCED BY AN UPPER STOREY IS A SKIRT, NOT A PYRAMID: on a two-storey house the lower roof surrounds the upper storey — it is the roof over the single-storey portion, with a hole where the upper floor rises through. A single pyramid cannot have that hole, so a full lower pyramid ends up entirely INSIDE the upper storey box and vanishes from the render. Build it as 4 separate sloped panels (prism, or thin rotated boxes) skirting the four sides of the upper storey, each sitting on the lower storey's top edge and sloping down and outward to the eaves. Only the topmost roof — the one nothing rises through — is a single pyramid.
- COPIES MUST NOT OVERLAP EACH OTHER: when a feature repeats, the step between copies has to be at least as long as the copy itself. Wheels 1.1 across on an 0.85 axle spacing eat a quarter of each other and render as one dark smear, not as wheels — so size the part from the spacing, or space it from the size. This applies to a "repeat" offset and to copies you author individually.
- A SKIRT, FLANK PANEL OR SIDE ARMOUR IS AN UPRIGHT PANEL, NOT A FLOOR: it stands along the vehicle's side, thin in X, tall in Y, long in Z — so it is TWO panels, one at each flank. A single slab that is wide in X and thin in Y is a floor plate lying under the vehicle, where nothing can see it.
- NOTHING MAY BE BUILT INSIDE ANOTHER PART: two parts may not occupy the same volume. Before answering, check every pair that shares a support: if one part's centre falls inside another part's box, one of them is in the wrong place and the render will be missing it. A part is only allowed inside another when it is a flush surface feature — a window or door in its wall.
- SURFACE MARKS ARE NOT GEOMETRY: a mould seam, panel gap, printed hairline, stitch line, scratch or grain is a mark ON a surface — never a part. A 0.01-radius tube laid down a bottle renders as a wire hanging in space, not as a seam. If a feature has no real thickness, either express it through the material's "finish" or leave it out.
- Reuse materials via materialId; 3-8 materials typical. Estimate PBR values from the photo's shading.
- NO FAKE OPTICS: never add a plane, box, or decal to simulate a highlight, reflection, glare, specular streak, or sheen on a surface. Shine and reflection come ONLY from the material (roughness / metalness / clearcoat) plus scene lighting — a "highlight" plane laid over a body renders as a hard streak cutting through it. Build only geometry that is physically part of the object. The single allowed non-object part is one flat ground shadow disc under it.
- Keep every "note" under 8 words — long notes bloat the reply and get it truncated.
- Numbers only in arrays — no strings, no null.`;

export const SPEC_SYSTEM_PROMPT = `You are a 3D reconstruction engine. You receive one or MORE reference views of the same object and rebuild it as a procedural Three.js primitive tree. Respond with ONLY a JSON object — no markdown fences, no prose.

${SPEC_JSON_SHAPE}`;

// v2 pipeline stage 1: instead of shipping hand-written per-category recipes
// (vehicles, buildings, ...) in the system prompt, the model analyzes THIS
// object and writes its own build recipe — the recipe becomes per-generation
// data that stage 2 (the spec build) is instructed to honor.
export const ANALYZE_SYSTEM_PROMPT = `You are the analysis stage of an image-to-3D pipeline. You receive one or MORE reference views of one object. Do NOT build geometry yet — study the object and write the expert construction plan a procedural modeler will follow. Respond with ONLY a JSON object — no markdown fences, no prose.

PICK YOUR PRIMARY VIEW FIRST: when several views are given, find the most 3D-informative one — a perspective / three-quarter view showing TWO OR MORE faces of the object. Base the part inventory and depth reasoning on THAT view (a flat frontal view hides side details and makes parts look like one flat shape, so counting parts from it under-builds the model). Use flat/orthographic views only for measuring the face they show. If every view is flat, say so in the camera note and infer depth from shading and category knowledge.

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
      "details": "repeats / finishes / decals worth adding (1 sentence)",
      "artwork": "OPTIONAL — set this ONLY when this part carries printed artwork the reference actually shows: a label, wordmark, stencil, warning placard, screen, badge, painted marking. Give the normalized bbox of the region in the FIRST image whose pixels are that artwork, as {\\"left\\":0..1,\\"top\\":0..1,\\"width\\":0..1,\\"height\\":0..1}. The builder crops those exact pixels and applies them to the part, so the real graphic appears instead of an approximation — this is what makes a bottle's label read as that bottle. A reference SHEET usually has a detail row worth harvesting: cropped panels, placards, markings. Leave it out for plain painted surfaces." }
  ],
  "attachments": ["one line per structural joint: '<part> <constraint> <part>' using constraints centered-above | flush-top | attached-left | attached-right | attached-front | attached-back | inset-into | rests-on — e.g. 'roof centered-above upper-floor', 'carport attached-right lower-floor', 'windows inset-into front-wall'"],
  "buildRecipe": ["5-12 imperative, object-SPECIFIC construction notes — proportions to respect, orientation pitfalls, what repeats how many times, which surfaces get which finish, where labels go. Write what an expert would pin above the workbench for THIS object."]
}

Rules:
- DECOMPOSE FULLY: break the object down the way a human would describe it piece by piece — every distinct volume, every attachment, every surface detail gets its own partPlan entry with its own material, depth and surface. Whatever the object is, the reader of your plan should be able to rebuild it without ever looking at the photo.
- Part budget scales with complexity: simple = 4-6 parts, moderate = 6-12, complex = 12-20. Use what the object needs — never pad a simple object, never truncate a complex one.
- A BUILDING OR A SCENE gets up to 30: a house is not one object but a small inventory — each storey, each roof, the window band on EVERY visible face, the door, balcony, railing, carport, boundary wall, its coping, the hedges, the gate. Listing "windows" once for a house whose four faces are all glazed under-describes it by a factor of four. The modeler builds exactly the inventory you list and nothing more, so a part you leave out is a part the model will not have.
- If the reference gives you an ORTHOGRAPHIC side or front view, say so in the camera note — those views are the most reliable thing to measure proportions from.
- A REPEATED FEATURE IS **ONE** PART: six wheels are one "wheels" entry, not six. Same for rivet rows, vent slats, fence pickets, bolt circles — the modeler expands them with a repeat, so listing each copy separately spends your budget on nothing. A truck plan that spends 4 of its 13 entries naming individual wheels has no entries left for the hull panelling, the cab, the grille and the exhaust — and that is exactly what makes a heavily panelled vehicle come out as one smooth box.
- THIN STRUCTURAL DETAILS ARE PARTS TOO: railings, balusters, handrails, fence pickets, antennas, roof trims, window grilles. Never drop them to save budget — each is ONE part built as a thin cylinder/box with a linear repeat, so it costs one partPlan entry no matter how many pieces repeat.
- MEASURE, don't guess: every bbox comes from actually reading the part's extent in the image. Relative bbox widths/heights become the model's proportions, so a sloppy bbox is a wrong model.
- List an attachment line for EVERY part except the root volume — a part with no attachment will float.
- GET THE DIRECTION RIGHT: every line reads "<A> <constraint> <B>", and "rests-on" / "centered-above" both mean A sits ON TOP OF B. So write what holds what: a vehicle's HULL rests on its WHEELS, never "wheels rests-on hull" — that line turns the vehicle upside down and puts the tyres on the roof. Same trap for a chassis and its tracks, a table top and its legs, a lamp shade and its stem. If B holds A up, A rests-on B; if A hangs UNDER B, use "attached-back"/"attached-front"/"inset-into" or name B as the part that rests on A instead.
- Recipe notes must be concrete and measurable ("six wheels in two rows of three", "roof overhangs walls by ~15%"), never generic advice.
- objectClass drives strategy: hard-surface = crisp boxes/cylinders; organic = overlapping sphere/capsule chains; hybrid = mix per part.`;

export const REFINE_SYSTEM_PROMPT = `You are a 3D reconstruction engine reviewing your own work. You receive a comparison sheet: the LEFTMOST panel is the reference photo; the remaining labeled panels show the current render (when a "RENDER @ REF ANGLE" pane is present it is captured from the estimated reference camera — judge placement against the reference there, like-for-like) plus FRONT, SIDE, and THREE-QUARTER angles (flat artwork gets a single head-on render). Use the side view to judge depth placement. You also receive the current spec JSON. Find what is visibly MISPLACED or MIS-COLORED and output a MINIMAL CHANGE SET — never the whole spec.

SCOPE — this pass ONLY repositions parts and recolors materials. You may NOT change any part's SHAPE: never change a component's "primitive" or "dimensions", never add a new component, never delete one. The shapes are already correct; only their placement (position / rotation / scale) and their colors may be wrong. A box stays a box — do not "improve" a part by turning it into a sphere, blob, or any other primitive.

Respond with ONLY this JSON object:
{
  "critique": "1-2 sentences: what you repositioned/recolored this round",
  "score": 0-100 (honest fidelity estimate AFTER your changes, never above 90),
  "featureCheck": { "<each identityFeature>": "pass" | "fail" },
  "changed": [ { "nodeId": "<existing node id>", "position": [x,y,z], "rotation": [x,y,z] (radians), "scale": [x,y,z] } — one entry per part whose PLACEMENT is wrong; include only the fields you are changing (position/rotation/scale). nodeId MUST already exist in the spec. primitive and dimensions are ignored if sent. ],
  "materialsChanged": [ COMPLETE material objects (materialId + baseColor/roughness/metalness/opacity/emissive/…) for every material whose COLOR or finish is wrong — matched by materialId ]
}

Refine conservatively:
- ORIENTATION CHECK — FIRST PRIORITY: the object uses a fixed frame — -Z is FORWARD, +Y is UP, +X is RIGHT. A rolling wheel has its axle along X (rotation [0,0,1.5708]) and rolls in Z; front plow/ram tines point -Z (rotation [-1.5708,0,0]). If a wheel/tire appears to lie FLAT or face the sky, or a spike/tine/blade points sideways (along X) instead of forward (-Z), its rotation is wrong — fix the rotation before any position work. A whole repeated row sharing one bad rotation is fixed by correcting the ONE base nodeId (the clones inherit it).
- SMALL DETAILS ARE NOT EXEMPT: rivets, studs, bolts, window slits, decals, light pods, vent stacks and other small/repeated parts are the most likely to be mislocated — floating off the surface, on the wrong face, on only one side, or sunk inside the body. Check each against the exact face it belongs to and reposition it flush; do not skip a part just because it is small.
- PLACEMENT ONLY drives the "changed" array: fix parts that are floating, offset, mis-rotated, poking through a surface, or the wrong size (scale). Use the analysis MEASURED TARGETS (normalized reference bboxes + attachment constraints) to place each part — horizontal center, vertical band, and which part it sits on/inside.
- Machine-checked assembly problems (floating parts) get fixed FIRST: move the part (position) so it overlaps its support by 0.02-0.05, or sits inside it for an inset window/panel.
- Resize with "scale" only — never by editing dimensions. A part that is too big/small keeps its primitive and gets a scale factor.
- Touch ONLY what is visibly wrong. Parts you do not mention stay exactly as they are — that is the point of the change set.
- Colors must be sampled from the reference pixels. A brightness difference caused by scene lighting is NOT a color error — if a baseColor hex already matches the reference pixel, do not touch that material.
- For flat-graphic inputs the render is captured head-on: keep the roundedPlate background at rotation [0,0,0]; fix a hidden artwork part's z position (do not delete it).
- Per-feature gate: judge EVERY identityFeature against the render in "featureCheck". A high global score cannot excuse a failing feature — a failing feature is this round's first priority.
- If nothing needs changing, return empty "changed" and "materialsChanged" arrays.`;

// Lasso targeted edit: the user selected specific parts (by nodeId) on the
// viewport and typed an instruction for JUST those parts. Unlike the refine
// pass this is not a whole-render review — it is a scoped, user-directed edit.
export const TARGETED_EDIT_PROMPT = `You are a 3D reconstruction engine applying a USER-DIRECTED edit to a few specific parts of an existing model. The user lasso-selected some parts on the 3D viewport and typed an instruction for THOSE PARTS ONLY.

You receive: the current spec JSON, the list of SELECTED nodeIds, the instruction, AND a comparison-sheet image — the LEFTMOST panel is the REFERENCE photo, the remaining panels are the CURRENT render of this model (front / side / three-quarter). ALWAYS diagnose visually first: compare the SELECTED parts in the render against the same parts in the reference photo and decide what is wrong before you edit.

DIAGNOSE the selected parts against the reference for ALL of these:
- PLACEMENT / RECONCILE: is the part floating, offset, sunk into another part, on the wrong face, or at the wrong height? Move it into contact / to the right spot.
- PROPORTION: is it too big/small versus the reference? Fix with "scale".
- MATERIAL / FINISH: does the reference show metal, glass, or a glossy/matte surface that the render gets wrong (e.g. glass looking like flat plastic, metal with no shine)? Fix metalness / roughness / transmission / opacity in materialsChanged.
- COLOR: sample the reference pixels — fix a wrong baseColor.

WHEN THE SELECTION IS EMPTY: "SELECTED nodeIds" may be an empty list, because the user described the edit instead of pointing at it. Then YOU resolve the targets: read the instruction against the spec's nodeIds and notes and pick the parts it names. The ids are semantic ('front-label', 'wheel-left', 'cap-body'), so "the label is too tall" means front-label. Pick the smallest set that satisfies the instruction, name them in "changed" as usual, and if the instruction is genuinely ambiguous between several parts, edit none of them and say which ones you were torn between in "critique".

SCOPE — edit ONLY the parts in question (and, when the instruction clearly implies them, their descendants). Do not touch anything else. You may reposition (position), reorient (rotation), resize (scale OR dimensions — set dimensions when the instruction gives a real size, scale when it gives a proportion), recolor/refinish (materialsChanged), set "grounded": true to drop a part onto the ground, REMOVE parts the instruction asks to delete, and ADD parts that are missing. You may NOT change an existing part's "primitive" — turning a box into a sphere is never what an edit meant; delete it and add the right shape instead.

ADDING A MISSING PART — when the instruction says something is missing, absent, or should be there ("the window is missing", "add the label back", "there should be a handle"), FIRST check the spec: if no component matches it, build one in "added". A new part is authored exactly like a spec component: pick the primitive from the same vocabulary, size it against the parts around it (their dimensions are right there in the spec), give it a "partRef" naming what it is, and "attachTo" the part it mounts on. Read the reference photo for where it sits, how big it is relative to its host, and what colour it is — and if it needs a colour no existing material has, add that material in "materialsChanged" and reference it. A question phrased as a question ("why is the window missing?") is still a request to fix it: answer by building the part, and say what you added in "critique".

The instruction is the priority; if it is vague ("fix this", "reconcile this part"), let the reference comparison decide the fix. The object uses a fixed frame: -Z FORWARD, +Y UP, +X RIGHT. "bottom" = lower Y / grounded; "top" = higher Y.

Respond with ONLY this JSON object:
{
  "critique": "1 sentence: what was wrong vs the reference and what you changed",
  "changed": [ { "nodeId": "<selected id>", "position": [x,y,z]?, "rotation": [x,y,z]?, "scale": [x,y,z]?, "dimensions": [numbers]?, "grounded": true? } — include only the fields you are changing; nodeId MUST already exist in the spec ],
  "added": [ { "nodeId": "new-kebab-id", "parentId": "<an existing id or the root group>", "primitive": "<from the vocabulary>", "dimensions": [numbers], "position": [x,y,z], "rotation": [x,y,z], "scale": [x,y,z], "materialId": "m-...", "partRef": "what this part is", "attachTo": "<the id it mounts on>", "note": "short" } — ONLY parts the instruction asks for; a nodeId that already exists is ignored ],
  "removedNodeIds": [ "<selected id>", ... ] (only when the instruction asks to remove/delete parts; else empty),
  "materialsChanged": [ COMPLETE material objects (materialId + baseColor/roughness/metalness/opacity/transmission/emissive/…) for any material of a selected part whose color or finish is wrong vs the reference ]
}

- Act on EXACTLY the selected nodeIds unless the instruction names others. Parts not selected and not mentioned stay untouched.
- "move to bottom" / "reconcile to bottom" → set position.y so it rests on the ground, or set "grounded": true.
- "remove" / "delete" → list the nodeId(s) in "removedNodeIds".
- Resize with "scale" for a proportion ("60% as tall"), with "dimensions" for a real measurement ("0.6 tall").
- "why is X missing" / "X should be here" → build X in "added", do not just explain.`;

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

// Every spec-side geometry pass in this file reads a component's authored
// position as a WORLD coordinate. That holds for the flat hierarchies these
// specs use — almost everything hangs off the root — but not for a part under a
// transformed parent: a balcony baluster parented to a slab at y 0.35 has a
// local y of 0.15, and treating that as world puts it underground. Reading a
// wrong box is bad enough when a pass only reports; a pass that MOVES parts on
// that basis will drag a correctly-placed part somewhere wrong.
//
// So a component only qualifies if every ancestor up to the root is neutral.
// Anything under a real transform is skipped and left to the interpreter's own
// solvers, which work in true world space.
function hasNeutralAncestry(c: any, byId: Map<string, any>): boolean {
  let seen = new Set<string>();
  let cur = c;
  while (cur?.parentId != null) {
    let id = String(cur.parentId);
    if (seen.has(id)) return false; // parentId cycle — not analysable
    seen.add(id);
    let parent = byId.get(id);
    if (!parent) return true; // unknown parent resolves to root in the builder
    let pos = Array.isArray(parent.position) ? parent.position : [0, 0, 0];
    let scl = Array.isArray(parent.scale) ? parent.scale : [1, 1, 1];
    let rot = Array.isArray(parent.rotation) ? parent.rotation : [0, 0, 0];
    let neutral =
      pos.every((n: any) => Math.abs(Number(n) || 0) < 0.001) &&
      scl.every((n: any) => Math.abs((Number(n) || 1) - 1) < 0.001) &&
      rot.every((n: any) => Math.abs(Number(n) || 0) < 0.001);
    if (!neutral) return false;
    cur = parent;
  }
  return true;
}

// Half extents [hx, hy, hz] of one component from its authored dimensions,
// scale AND rotation — the spec-side equivalent of a Box3, used by the
// constraint checks below. Only the primitives whose extents are unambiguous
// are described; anything else returns undefined and is left alone rather than
// guessed at.
//
// Rotation matters more than it looks. A wheel is a cylinder turned 90° about Z
// so its axle runs across the vehicle, which swaps its height and its radius:
// measured unrotated it is 0.45 tall, measured properly it is 1.0. Reading the
// unrotated box made every check downstream wrong for rotated parts — the
// attachment solver "seated" a wheel using a box less than half its real height
// and pushed it 0.26 further up than it belonged.
function halfExtents(c: any): [number, number, number] | undefined {
  let local = localHalfExtents(c);
  if (!local) return undefined;
  let rot = Array.isArray(c?.rotation) ? c.rotation.map(Number) : [];
  if (!rot.length || rot.every((r: number) => Math.abs(r || 0) < 0.01)) {
    return local;
  }
  // rotate the box's eight corners and take the widest reach on each axis —
  // exact for any Euler triple, not just the axis-aligned quarter turns
  let [rx, ry, rz] = [rot[0] || 0, rot[1] || 0, rot[2] || 0];
  let cx = Math.cos(rx);
  let sx = Math.sin(rx);
  let cy = Math.cos(ry);
  let sy = Math.sin(ry);
  let cz = Math.cos(rz);
  let sz = Math.sin(rz);
  let out: [number, number, number] = [0, 0, 0];
  for (let ix of [-1, 1]) {
    for (let iy of [-1, 1]) {
      for (let iz of [-1, 1]) {
        let x = ix * local[0];
        let y = iy * local[1];
        let z = iz * local[2];
        // three.js default Euler order XYZ
        let y1 = y * cx - z * sx;
        let z1 = y * sx + z * cx;
        let x2 = x * cy + z1 * sy;
        let z2 = -x * sy + z1 * cy;
        let x3 = x2 * cz - y1 * sz;
        let y3 = x2 * sz + y1 * cz;
        out[0] = Math.max(out[0], Math.abs(x3));
        out[1] = Math.max(out[1], Math.abs(y3));
        out[2] = Math.max(out[2], Math.abs(z2));
      }
    }
  }
  return out;
}

// Where a primitive's geometry sits relative to its node origin. Almost
// everything is centred, but the extruded shapes are centred in Z only — their
// outline keeps whatever X/Y the author wrote — so a traced hull's box is offset
// from its position. Ignoring that made every check skip or mis-measure exactly
// the part that matters most on a traced vehicle: its body.
function localCentreOffset(c: any): [number, number, number] {
  if (c?.primitive !== 'extrudedPolygon' && c?.primitive !== 'extrudedSpline') {
    return [0, 0, 0];
  }
  let raw = Array.isArray(c.dimensions)
    ? c.dimensions
    : (() => {
        try {
          let v = JSON.parse(String(c.dimensions ?? '[]'));
          return Array.isArray(v) ? v : [];
        } catch {
          return [];
        }
      })();
  let pts = raw
    .slice(1)
    .map(Number)
    .filter((n: number) => !isNaN(n));
  if (pts.length < 6) return [0, 0, 0];
  let xs: number[] = [];
  let ys: number[] = [];
  for (let i = 0; i + 1 < pts.length; i += 2) {
    xs.push(pts[i]);
    ys.push(pts[i + 1]);
  }
  let s = Array.isArray(c.scale) ? c.scale.map(Number) : [1, 1, 1];
  return [
    ((Math.min(...xs) + Math.max(...xs)) / 2) * (s[0] || 1),
    ((Math.min(...ys) + Math.max(...ys)) / 2) * (s[1] || 1),
    0,
  ];
}

// The component's world-ish axis-aligned box: position, plus the geometry's own
// offset from its origin, plus its rotated half extents. Every pass that reasons
// about where a part IS should use this rather than position ± halfExtents.
export function specBox(c: any): { min: number[]; max: number[] } | undefined {
  let h = halfExtents(c);
  if (!h) return undefined;
  let p = Array.isArray(c?.position) ? c.position.map(Number) : [0, 0, 0];
  let o = localCentreOffset(c);
  // the offset is expressed in the node's own frame, so a rotated part carries it
  // round with the geometry
  let rot = Array.isArray(c?.rotation) ? c.rotation.map(Number) : [];
  if (rot.length && rot.some((r: number) => Math.abs(r || 0) > 0.01)) {
    let [rx, ry, rz] = [rot[0] || 0, rot[1] || 0, rot[2] || 0];
    let cx = Math.cos(rx);
    let sx = Math.sin(rx);
    let cy = Math.cos(ry);
    let sy = Math.sin(ry);
    let cz = Math.cos(rz);
    let sz = Math.sin(rz);
    let y1 = o[1] * cx - o[2] * sx;
    let z1 = o[1] * sx + o[2] * cx;
    let x2 = o[0] * cy + z1 * sy;
    let z2 = -o[0] * sy + z1 * cy;
    o = [x2 * cz - y1 * sz, x2 * sz + y1 * cz, z2];
  }
  let centre = [0, 1, 2].map((a) => (p[a] || 0) + o[a]);
  return {
    min: [0, 1, 2].map((a) => centre[a] - h[a]),
    max: [0, 1, 2].map((a) => centre[a] + h[a]),
  };
}

function localHalfExtents(c: any): [number, number, number] | undefined {
  let d = Array.isArray(c?.dimensions)
    ? c.dimensions.map(Number)
    : (() => {
        try {
          let v = JSON.parse(String(c?.dimensions ?? '[]'));
          return Array.isArray(v) ? v.map(Number) : [];
        } catch {
          return [];
        }
      })();
  let s = Array.isArray(c?.scale) ? c.scale.map(Number) : [1, 1, 1];
  let [sx, sy, sz] = [
    Math.abs(s[0] || 1),
    Math.abs(s[1] || 1),
    Math.abs(s[2] || 1),
  ];
  let abs = (n: any) => Math.abs(Number(n) || 0);
  switch (c?.primitive) {
    case 'box':
    case 'roundedBox':
      return [(abs(d[0]) / 2) * sx, (abs(d[1]) / 2) * sy, (abs(d[2]) / 2) * sz];
    case 'prism':
      // [lengthAlongRidge, span, height] — ridge along X
      return [(abs(d[0]) / 2) * sx, (abs(d[2]) / 2) * sy, (abs(d[1]) / 2) * sz];
    case 'cylinder':
      return [
        Math.max(abs(d[0]), abs(d[1])) * sx,
        (abs(d[2]) / 2) * sy,
        Math.max(abs(d[0]), abs(d[1])) * sz,
      ];
    case 'cone': {
      // the engine squares up a 4-segment cone, so its footprint is the
      // face-to-face width (radius x sqrt2), not the corner-to-corner radius
      let segments = Math.max(3, Math.round(abs(d[2]) || 24));
      let r = abs(d[0]) * (segments === 4 ? Math.SQRT1_2 * Math.SQRT2 : 1);
      let half = segments === 4 ? abs(d[0]) * Math.SQRT1_2 : r;
      return [half * sx, (abs(d[1]) / 2) * sy, half * sz];
    }
    case 'sphere':
    case 'rock':
    case 'blob':
      return [abs(d[0]) * sx, abs(d[0]) * sy, abs(d[0]) * sz];
    case 'capsule':
      // [radius, cylinderLength] — length along Y plus a cap at each end
      return [abs(d[0]) * sx, (abs(d[1]) / 2 + abs(d[0])) * sy, abs(d[0]) * sz];
    case 'torus':
      // [radius, tube] — lying flat, so the hole faces up
      return [
        (abs(d[0]) + abs(d[1])) * sx,
        abs(d[1]) * sy,
        (abs(d[0]) + abs(d[1])) * sz,
      ];
    case 'disc':
      return [abs(d[0]) * sx, abs(d[0]) * sy, 0];
    case 'plane':
      return [(abs(d[0]) / 2) * sx, (abs(d[1]) / 2) * sy, 0];
    case 'roundedPlate':
      return [(abs(d[0]) / 2) * sx, (abs(d[1]) / 2) * sy, (abs(d[2]) / 2) * sz];
    case 'flatRing':
      // [outerRx, outerRy, ringWidth, depth]
      return [abs(d[0]) * sx, abs(d[1]) * sy, (abs(d[3]) / 2) * sz];
    case 'extrudedPolygon':
    case 'extrudedSpline': {
      // [depth, x0,y0, x1,y1, …] — the interpreter centres these in Z only, so
      // the outline keeps the author's own X/Y coordinates and the geometry is
      // NOT centred on its origin. specBox() carries the offset; the half
      // extents here are the outline's own half width and height.
      let pts = d
        .slice(1)
        .map(Number)
        .filter((n: number) => !isNaN(n));
      if (pts.length < 6) return undefined;
      let xs: number[] = [];
      let ys: number[] = [];
      for (let i = 0; i + 1 < pts.length; i += 2) {
        xs.push(pts[i]);
        ys.push(pts[i + 1]);
      }
      return [
        ((Math.max(...xs) - Math.min(...xs)) / 2) * sx,
        ((Math.max(...ys) - Math.min(...ys)) / 2) * sy,
        (abs(d[0]) / 2) * sz,
      ];
    }
    default:
      // lathe / hemisphere / arch / tube / extruded* are NOT centred on their
      // origin — their geometry sits wherever their profile or point list puts
      // it — so a half-extent triple cannot describe them and callers must treat
      // them as unmeasurable rather than guess.
      return undefined;
  }
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
const SUPPORT_NAME =
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

// A reference of brass-gold plates, dark teal panels, black rubber, red hub
// lights and bare steel blades came back as twelve materials of which nine sat
// inside one 40° olive band — a uniformly muddy object. The cause is sampling:
// the analysis is told to take colours from the flattest-lit panel and instead
// read them off the warm-lit beauty render, where everything is the same colour
// of gold.
//
// Judging a palette by its hue spread would be wrong — plenty of objects really
// are monochrome, and a wine bottle's glass, paper and cap legitimately live near
// each other. What IS object-agnostic is near-duplicates: declaring two materials
// that nobody could tell apart means the spec spent two slots to describe one
// surface, and whatever distinction the reference drew between those parts has
// been lost. Report only — which of the two should change is a judgement about
// the photo, not the numbers.
export function flagFlatPalette(parsed: any): string[] {
  let logs: string[] = [];
  let materials: any[] = parsed?.materials ?? [];
  if (materials.length < 3) return logs;
  let rgb = (hex: any): [number, number, number] | undefined => {
    let s = String(hex ?? '').trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(s)) return undefined;
    return [
      parseInt(s.slice(1, 3), 16),
      parseInt(s.slice(3, 5), 16),
      parseInt(s.slice(5, 7), 16),
    ];
  };
  let entries = materials
    .map((m: any) => ({
      id: m?.materialId,
      c: rgb(m?.baseColor),
      finish: m?.finish,
    }))
    .filter((e) => e.id && e.c) as {
    id: string;
    c: [number, number, number];
    finish?: string;
  }[];
  if (entries.length < 3) return logs;
  // a rough perceptual distance: weight green most, blue least, the way the eye
  // does. ~12 is about where two swatches stop being distinguishable side by side
  const INDISTINGUISHABLE = 12;
  let distance = (a: [number, number, number], b: [number, number, number]) => {
    let dr = a[0] - b[0];
    let dg = a[1] - b[1];
    let db = a[2] - b[2];
    return Math.sqrt(2 * dr * dr + 4 * dg * dg + 3 * db * db) / 3;
  };
  // hazard, camo and louver carry their colours INSIDE the painted map — the
  // interpreter neutralises the material's own colour to white for them — so two
  // such materials say nothing about each other's baseColor. worn, brushed,
  // patina, tread and knurl only modulate the paint underneath, so their base
  // colours are still what you see and remain comparable.
  let colourReplaced = (f: any) =>
    f === 'hazard' || f === 'camo' || f === 'louver';
  let pairs: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    for (let j = i + 1; j < entries.length; j++) {
      if (
        colourReplaced(entries[i].finish) ||
        colourReplaced(entries[j].finish)
      ) {
        continue;
      }
      if (distance(entries[i].c, entries[j].c) < INDISTINGUISHABLE) {
        pairs.push(`'${entries[i].id}' and '${entries[j].id}'`);
      }
    }
  }
  if (pairs.length) {
    logs.push(
      `${pairs.length} material pair(s) are visually the same colour — ${pairs.slice(0, 3).join(', ')}${pairs.length > 3 ? ', …' : ''}: the reference likely draws a distinction here that the sampling lost`,
    );
  }

  // And the case a duplicate check structurally cannot catch: not two materials
  // being identical, but ALL of them living in one hue family. That is what turns
  // a brass-and-teal machine into uniform mud, and it comes from sampling a
  // warm-lit render instead of a flat panel. Whether it is WRONG depends on the
  // object — plenty of things really are monochrome — so this reports the
  // measurement and lets a human or the refine round judge it.
  let hue = ([r, g, b]: [number, number, number]) => {
    let max = Math.max(r, g, b);
    let min = Math.min(r, g, b);
    if (max === min) return undefined; // grey has no hue
    let d = max - min;
    let h =
      max === r
        ? ((g - b) / d) % 6
        : max === g
          ? (b - r) / d + 2
          : (r - g) / d + 4;
    return (((h * 60) % 360) + 360) % 360;
  };
  let hues = entries
    .filter((e) => !colourReplaced(e.finish))
    .map((e) => hue(e.c))
    .filter((h): h is number => h !== undefined);
  // below half a dozen hues the observation is not evidence of anything: a wine
  // bottle's olive glass, cream label, dark cap and gold band genuinely share the
  // warm band, and 3-of-4 would "prove" it was sampled badly when it was not
  if (hues.length >= 6) {
    // widest band containing the most hues, sliding a 40° window
    let best = 0;
    let bestAt = 0;
    for (let start = 0; start < 360; start += 5) {
      let inBand = hues.filter((h) => {
        let rel = (h - start + 360) % 360;
        return rel <= 40;
      }).length;
      if (inBand > best) {
        best = inBand;
        bestAt = start;
      }
    }
    if (best / hues.length >= 0.7) {
      logs.push(
        `${best} of ${hues.length} colours sit inside a single 40° hue band (${bestAt}°-${bestAt + 40}°) — if the reference is more varied than that, the palette was sampled from a lit render rather than a flat view`,
      );
    }
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
// Report only: the fix is either a wider spacing or a smaller part, and which
// one the reference calls for is not knowable from the coordinates.
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
      logs.push(
        `'${c.nodeId}' repeats ${count}× at a step of ${step.toFixed(2)} but is ${extent.toFixed(2)} across that axis — copies overlap by ${(extent - step).toFixed(2)}`,
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

// one vision round-trip through the Boxel proxy, returning the parsed spec.
// Retries transient failures (rate limit / upstream error / dropped
// connection / invalid JSON / truncation) with backoff, appending a
// corrective nudge on content failures. Network drops get extra attempts:
// the browser kills every in-flight fetch when the machine's network
// changes (ERR_NETWORK_CHANGED — Wi-Fi hop, VPN reconnect), and these
// vision calls run for minutes, so a single flap mid-request is common.
// This pipeline's calls are INPUT-heavy, not output-heavy: the spec stage sends
// roughly 7k tokens of system prompt, 1.7k of analysis and up to 11k of images to
// get back about 2.3k tokens of JSON. The system prompt is byte-identical on every
// single call, so marking it cacheable lets the provider skip re-processing it —
// cheaper and quicker to first token.
//
// Only Anthropic models are given the cache marker: the field is an Anthropic
// extension, and a provider that does not understand a structured system message
// is better off receiving the plain string it has always received.
function systemMessage(llmModel: string, systemPrompt: string): any {
  if (!/^anthropic\//.test(llmModel)) return systemPrompt;
  return [
    {
      type: 'text',
      text: systemPrompt,
      cache_control: { type: 'ephemeral' },
    },
  ];
}

export async function requestSpec(
  commandContext: any,
  llmModel: string,
  systemPrompt: string,
  userContent: any[],
  onLog?: (line: string) => void,
  parser: (raw: string) => any = parseSpecJson,
  // seed: pass seedFromStrings(referenceUrls) so one reference set always
  // takes the same sampling path. temperature defaults to SPEC_TEMPERATURE
  // (0) and should only be raised deliberately.
  //
  // validate: inspect a well-formed reply and return a correction to send back,
  // or null to accept it. The retry loop below already knows how to re-ask with a
  // nudge when a reply is truncated or is not JSON; a reply that PARSES but left
  // out half the object is the same kind of failure and deserves the same
  // treatment. Being told exactly which parts are missing is far more likely to
  // work than re-rolling and hoping.
  options?: {
    temperature?: number;
    seed?: number;
    validate?: (parsed: any) => string | null;
  },
) {
  let temperature = options?.temperature ?? SPEC_TEMPERATURE;
  let seed = options?.seed;
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
        temperature,
        ...(typeof seed === 'number' ? { seed } : {}),
        messages: [
          { role: 'system', content: systemMessage(llmModel, systemPrompt) },
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
    let parsed = parser(choice?.message?.content ?? '');
    let complaint = options?.validate?.(parsed) ?? null;
    if (complaint) {
      // a parseable but incomplete reply: throw so the loop retries, and carry
      // both the complaint (to send back) and the reply (so the last attempt can
      // still be used rather than failing the whole generation)
      let err: any = new Error(complaint);
      err.incomplete = true;
      err.correction = complaint;
      err.parsed = parsed;
      throw err;
    }
    return parsed;
  };

  // A dropped connection deserves more patience than a bad reply: nothing about
  // the request was wrong, it just never finished, and re-sending is free of the
  // risk that a retry makes things worse. A malformed or truncated reply is the
  // model's doing, so hammering it rarely helps — the corrective nudge does. The
  // comment here used to claim network drops already got extra attempts; they
  // did not, every failure shared one budget.
  const MAX_ATTEMPTS = 4;
  const MAX_NETWORK_ATTEMPTS = 7;
  const RETRY_DELAYS_MS = [2000, 5000, 10000];
  // longer, gentler backoff for a flapping connection — a Wi-Fi hop or a dev
  // server restart takes tens of seconds to settle, and retrying into it just
  // burns an attempt
  const NETWORK_DELAYS_MS = [2000, 5000, 10000, 20000, 30000, 30000];
  let attemptsAllowed = MAX_ATTEMPTS;
  let lastError: any;
  for (let i = 0; i < attemptsAllowed; i++) {
    let nudge: string | undefined;
    if (lastError?.truncated) {
      nudge =
        'Your previous reply was truncated. Reply with ONLY the JSON object and keep every "note" under 8 words.';
    } else if (lastError?.correction) {
      nudge = lastError.correction;
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
        e?.incomplete ||
        /did not return JSON|no components/i.test(e?.message ?? '');
      if (!transientHttp && !networkDrop && !contentFailure) throw e;
      e.contentFailure = contentFailure;
      lastError = e;
      if (networkDrop) attemptsAllowed = MAX_NETWORK_ATTEMPTS;
      // an incomplete reply is only worth ONE corrective re-ask: if naming the
      // missing parts did not produce them, a third identical request will not
      // either, and the reply we already hold is usable — better an object with a
      // part missing than no object at all
      if (e?.incomplete && i >= 1) {
        onLog?.(
          `> still incomplete after a correction — building anyway (${e.correction})`,
        );
        return e.parsed;
      }
      if (i === attemptsAllowed - 1) break;
      let delay = networkDrop
        ? (NETWORK_DELAYS_MS[i] ?? 30000)
        : (RETRY_DELAYS_MS[i] ?? 10000);
      onLog?.(
        `> retrying ${i + 1}/${attemptsAllowed - 1} in ${Math.round(delay / 1000)}s (${
          networkDrop ? 'connection dropped' : (e?.status ?? 'invalid response')
        })…`,
      );
      await new Promise((r) => setTimeout(r, delay));
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
