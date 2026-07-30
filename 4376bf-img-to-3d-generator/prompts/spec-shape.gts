// The response contract for the spec stage: the JSON shape the model must
// return, the primitive dimension semantics, and the modelling rules that
// apply to every object. Kept apart from the transport and the repair passes
// because it is prose — it changes for editorial reasons, on its own cadence,
// and a diff here is a diff in what the model is told, never in what the code
// does.
//
// What belongs HERE is what every object needs, in two kinds:
//   · CONTRACT — the interpreter mis-renders or the parser rejects the reply
//     without it (the JSON shape, the per-primitive dimension semantics, the
//     world frame, the response formatting). Never abbreviated.
//   · INVARIANTS the repair passes in util/spec-passes/ already enforce
//     (contact, grounding, burial, budget, hairlines). One imperative line
//     each: violating them is self-healing, so the long worked examples were
//     paying for a guarantee the code already gives.
// Craft rules that only SOME objects need — lathe tracing, roof skirts, flank
// panels, flat-graphic point counts, finish misuse — live in recipes.gts and
// ship only when the object's own analysis asks for them.

import { PRIMITIVES } from '../fields/sculpt-spec';

export const SPEC_JSON_SHAPE = `JSON shape:
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

dimensions semantics: box [w,h,d] · roundedBox [w,h,d,cornerRadius,bevel] (rounded-corner slab lying flat, face up — device bodies, cases) · roundedPlate [w,h,depth,cornerRadius] (rounded-rect plate in the XY plane FACING +Z / the camera — logo backgrounds, signs, screens; needs NO rotation) · cylinder [radiusTop,radiusBottom,height,segments?] · capsule [radius,cylinderLength] · sphere [radius] · hemisphere [radius] (dome, opens downward) · cone [radius,height,segments?] (segments=4 → square PYRAMID for hip roofs/spires. The ENGINE squares it up for you, so its edges already run along X and Z: its Y rotation MUST be 0. Do not "fix" its orientation with a 45° rotation the way plain three.js needs — that stacks with the engine's own correction into 90°, turning the roof back into a diamond whose corners stick out past the walls. Shape the footprint with non-uniform scale only. Footprint width = radius × 1.414, so for a roof that overhangs a wall of width w by ~15%, radius ≈ 0.81 × w/2) · torus [radius,tube] (ring standing UPRIGHT in the XY plane, hole facing the camera — this is three.js's own orientation and it is almost never what you want. A collar/band around an upright body (bottle lip ring, cap ribbing, barrel hoop) is rotation [-1.5708, 0, 0], which lays the hole face up. A wheel hub ring, facing sideways out of the vehicle's flank, is rotation [0, 1.5708, 0]. An unrotated torus is a hoop standing beside the object, which is a bug in every case I have seen) · plane [w,h] · disc [radius] (flat circle facing +Z — dials, hole covers) · flatRing [outerRx,outerRy,ringWidth,depth] (flat elliptical ring with a REAL hole, XY plane facing +Z — scissor handle loops, grab rings, bracelets; NEVER fake these with a squashed torus) · arch [outerR,ringWidth,depth,sweepDeg?] (partial flat ring spanning the top — wheel arches/fenders, bridge handles) · prism [lengthAlongRidge,span,height] (triangular prism, ridge along X — gable roofs, ramps, wedges; no rotation needed) · tube [radius, x0,y0,z0, x1,y1,z1, ...] (smooth tube swept along a 3D curve through the points — USE for laces, cables, hoses, curved handles, piping; 3-6 points give a natural curve) · bone [radius, x0,y0,z0, x1,y1,z1] (a capsule spanning the TWO endpoints, auto-oriented — the go-to for ARMS, LEGS and FINGERS: give the two joint positions and the engine handles the rotation, so you never compute a limb's angle. A bent limb is TWO bones sharing the elbow/knee point, e.g. shoulder→elbow then elbow→wrist. Leave position at [0,0,0] — the endpoints place it) · rock [radius, detail?] (faceted low-poly blob) · blob [radius, bumpiness 0-0.5, seed?, detail?] (smooth freeform mass — a dense sphere mesh displaced by seeded noise; the go-to for soft/organic volumes: cushions, plush bodies, bread, fruit, boulders. Non-uniform scale shapes it; vary seed per part so blobs differ) · glow [size] (camera-facing additive light glow in the material's baseColor — reactor lights, lamps, LEDs) · lathe [x0,y0,x1,y1,...] profile bottom→top (x>=0) · extrudedPolygon [depth, x0,y0, x1,y1, ...] straight-edged polygon outline in the XY plane facing +Z, centered · extrudedSpline [depth, x0,y0, x1,y1, ...] same but the outline is a SMOOTH curve through the points (organic silhouettes: shoe soles, leaves, curved panels — prefer this over extrudedPolygon whenever the reference shape has curved edges) · meshAsset [] (mounts a pre-existing .glb via its "assetUrl" field — ONLY reference asset URLs given to you in the request; NEVER invent one) · textDecal [w,h] (transparent plane rendering the "text" field in the material's baseColor — USE for wordmarks on FLAT surfaces; sits ~0.01 in front; also renders SYMBOL characters — '★' '▲' '●') · curvedDecal [radius, height, arcDeg?] (label/sticker WRAPPED around a cylindrical body — wine labels, can labels, mug prints; radius = the host body's radius + 0.01, arc defaults 120°, material baseColor = the label ground color, "text" = the label's main wordmark, attachTo = the host body; NEVER fake a label on a bottle/can with a flat plate) · group [].

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
- FOLLOW THE ANALYSIS: the user message includes an ANALYSIS block (object type, semantic part plan, build recipe) produced by a prior analysis pass over the same photos. Treat its buildRecipe as your own expert construction notes — every partPlan entry must map to components (thin details like railings included — a missing part is a failed build), and every recipe instruction must be visibly honored in the spec. Honor each part's "material" (glass parts get a transmission material, metal gets metalness, etc.), its "surface" note, and its "depthRatio" — depth = bboxWidth × depthRatio is that part's thickness target; do not guess thickness the analysis already measured.
- PROPORTIONS ARE MEASURED, NEVER ASSUMED: for every pair of related parts (stacked, nested, capping, side-by-side) the size ratio between them comes from their analysis bboxes — never from what this kind of object "usually" looks like. A part that caps or shelters another is at least as wide as what it covers, with the overhang read from the bbox comparison (rarely more than 20%). A part's steepness or flatness comes from its own bbox aspect (height ÷ width) — do not substitute a canonical shape for the measured one.
- GEOMETRIC RECONSTRUCTION (semantic recognition is not enough — reconstruct measured geometry): the ANALYSIS gives each part a normalized image bbox. DERIVE dimensions and positions from those numbers, do not eyeball: for parts at similar depth, widthA/widthB = bboxA.width/bboxB.width and heightA/heightB = bboxA.height/bboxB.height; a part's horizontal center ≈ (bbox.left + bbox.width/2) mapped across the object's total width; its vertical placement comes from bbox.top/height mapped down the object's total height (image top = model top). Cross-check every major part's computed size against its bbox ratio before answering.
- EACH partPlan "approach" IS AN ORDER, not a suggestion — build that part with the primitive family the directive for that approach names. The directives for the approaches this object actually uses are given below the rules.
- ENFORCE THE ATTACHMENTS LIST: each "A <constraint> B" line is a hard joint — centered-above means A's center xz = B's center xz and A's bottom overlaps B's top; attached-right means A's left face overlaps B's right face; inset-into means A sits flush INSIDE B's face (protrude ≤ 0.02); rests-on means A's bottom overlaps B's top. Every attachment must be numerically true in the final coordinates.
- ASSEMBLY IS A GRAPH: every non-group part must physically OVERLAP at least one neighbour by 0.02-0.05 units — compute it, don't eyeball it — and its "note" names what it attaches to. A machine check lists floating parts back to you; a spec with floating parts is a failed spec.
- SUPPORT RULE: every component rests on or attaches to another, and NAMES that support in "attachTo". Nothing hovers.
- GROUND PLACEMENT IS A FLAG, NOT A HEIGHT: set "grounded": true on each thing that rests on the ground rather than authoring its height, and the engine drops it onto the ground plane.
- COMPOSITION CHECK: before answering, re-verify placement NUMERICALLY for every part — compare each part's position ± half its size against its neighbour's bounds. Nothing pokes through a surface it should sit on, and no part's centre falls inside another part's box (only a flush surface feature, like a window in its wall, may sit inside another).
- COPIES MUST NOT OVERLAP EACH OTHER: when a feature repeats, the step between copies is at least as long as the copy itself — size the part from the spacing, or space it from the size.
- SURFACE MARKS ARE NOT GEOMETRY: a mould seam, panel gap, printed hairline, stitch line, scratch or grain is a mark ON a surface, never a part. If a feature has no real thickness, express it through the material's "finish" or leave it out.
- A WINDOW / WINDSHIELD / SCREEN IS GLASS WITH DEPTH, NOT A DARK PLANE: build it as a thin roundedBox INSET a little into the body (recessed below the surface), with a glass material — transmission 0.85-1.0, roughness 0.05-0.15, metalness 0, and a NEAR-CLEAR or lightly-tinted colour (never a dark grey — a dark, low-transmission "glass" renders as an opaque black patch). A zero-thickness "plane" with a dark material is the classic wrong answer: it reads as a painted hole, not a window.
- FEATURES PROTRUDE OR RECESS — BOTH ARE REAL: a bumper, mirror or badge sticks OUT; a window well, a grille cavity, a sunken door panel or an air intake goes IN. For a recessed feature, set "inset": true on the component and give it a slightly darker material — the engine sinks its outer face just below the surrounding surface, and the shadow in that dip is what reads as depth. Do not fake a recess with a flat dark plane, and do not build every detail proud of the surface; match what the reference shows going in vs sticking out.
- A HOLLOW BODY HAS INTERIOR SPACE: when the reference shows you can see INTO a body through its windows/openings (a vehicle cab, a cabin, a container mouth), it is a shell, not a solid — put a smaller DARK matte "interior" box just inside it, behind the glass, so looking through the transmissive panes reveals depth instead of a flat surface.
- Build a real hierarchy: one root group, then logical sub-groups (body, handle, lid...).
- THE PART BUDGET COMES FROM THE PLAN, NOT FROM A NUMBER: every partPlan entry must map to at least one component, and a single part may honestly need several. But NEVER add a component the reference does not show in order to look thorough — a bottle rebuilt from 5 correct parts is a success, and the same bottle padded to 18 with invented neck rings is a failure. The request states the plan's part count; author within reach of it.
- Reuse materials via materialId; 3-8 materials typical. Estimate PBR values from the photo's shading.
- NO FAKE OPTICS: never add a plane, box, or decal to simulate a highlight, reflection, glare, specular streak, or sheen on a PHOTOREAL surface. Shine and reflection come ONLY from the material (roughness / metalness / clearcoat) plus scene lighting — a "highlight" plane laid over a photographed body renders as a hard streak cutting through it. Build only geometry that is physically part of the object. The single always-allowed non-object part is one flat ground shadow disc under it. EXCEPTION for a flat-shaded / cartoon / illustrated reference (inputKind not a photo): the drawn white catchlight on an eye or the shine dot on a nose IS part of that art style, so a SMALL bright ellipsoid sitting just proud of the eye/nose is allowed and encouraged — it is drawn geometry, not a faked reflection.
- Keep every "note" under 8 words — long notes bloat the reply and get it truncated.
- Numbers only in arrays — no strings, no null.`;
