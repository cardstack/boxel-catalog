// Craft rules that only some objects need, and the selector that picks them.
//
// The universal contract lives in spec-shape.gts and ships with every request.
// What is here is different: rules nothing in the pipeline can check, that only
// matter for a minority of objects, and that cost a couple of thousand tokens
// each of a model's attention when they don't apply. A bottle should not be
// reading about roof skirts.
//
// These are NOT per-category recipes keyed off an object taxonomy — stage 1
// deliberately replaced those with a per-object buildRecipe it writes itself
// (see analyze.gts). Selection here keys off signals that plan ALREADY emits:
// each part's declared "approach" (a required enum), whether a part carries an
// "artwork" bbox, the objectClass, and the semantic part names. A block is sent
// when the object's own plan says it is relevant, and a novel object simply
// receives the ones its plan triggers.

export const RECIPES: Record<string, string> = {
  revolved: `REVOLVED BODIES (this object has rotationally symmetric parts):
- "lathe" is ONLY for rotationally symmetric parts (vase, bottle, bowl, lamp base). NEVER use lathe for shoes, clothing, animals, or any non-symmetric form.
- ONE lathe profile traces the ENTIRE silhouette top-to-bottom (for a bottle: body, shoulder, neck AND lip all in the same profile). Do NOT also add separate stacked cylinders/cones for the neck, lip, or any part the lathe already covers — that duplicates geometry and the extra pieces end up floating above the profile. The only additional parts on a revolved body are decals (labels, foil wraps) and genuinely non-symmetric attachments.
- LATHE PROFILES ARE TRACED, NOT INVENTED: read the silhouette's half-width at 5-8 heights in the reference and write those (x,y) pairs bottom→top. A straight vertical wall = the SAME x repeated at two heights (a container body is a straight wall over most of its height — if your profile's x changes steadily with y you have drawn a CONE, which is almost always wrong). Shoulders are a short curve near the top, not a taper from the base.
- MEASURE WHERE THE WIDTH CHANGES, DON'T GUESS: every transition (where the wall starts narrowing, where the neck begins) sits at a specific FRACTION of the object's total silhouette height in the reference — measure that fraction from the photo and place the (x,y) pair there. Do not compress the main body or stretch the neck to a "typical" shape; a label or band that later floats off the wall is the symptom of a transition placed at the wrong height. Trace the FULL silhouette from the base all the way to the very top so the profile alone reproduces the whole outline.`,

  organic: `SOFT AND CURVED MASSES (this object has organic or hybrid parts):
- HYBRID GENERATION: regular geometric parts (cases, wheels, walls, frames) stay procedural — boxes/cylinders/roundedBoxes with crisp dimensions. Freeform/organic parts (cushions, plush bodies, food, natural masses) use "blob" (non-uniformly scaled, unique seed per part) or a chain of 4-8 OVERLAPPING spheres/capsules laid along the part's centerline, each non-uniformly scaled and overlapping ~40% with the next. NEVER use a box for a curved body — boxes read as bricks; boxes are ONLY for genuinely rectangular parts.
- curved-chain approach → 4-8 overlapping non-uniformly scaled spheres/capsules along the centerline.
- freeform-mesh approach → blob fallback (unique seed), non-uniformly scaled.`,

  character: `CHARACTERS, MASCOTS AND FACES:
- A FACE IS A STACK, AND THE ORDER NEVER VARIES: eyes highest, nose below the eyes, mouth below the nose. Author the three y values in that order and check them against each other before answering — a nose above the eyes is the single most recognisable way for a character to come out wrong, and it survives every downstream repair pass because each part is individually where the plan put it.
- THE MUZZLE / TAN FACE IS A CLUSTER THAT BITES INTO THE SKULL: build it from 2-3 OVERLAPPING lobes (cheeks + lower jaw), each a scaled sphere whose CENTRE sits inside the skull (about half its radius in) so face and head read as one mass. A single flat disc reads as a sticker and collapses to a wafer in profile; a lobe whose centre sits outside the skull floats in front of the face.
- FEATURES SIT ON THE HOST THEY NAME, ON ITS OUTWARD SIDE: eyes, pupils, nose and mouth attachTo the MUZZLE (or the skull when there is no muzzle), never the torso, and they sit on the side of it facing AWAY from the skull. Each is mostly proud of that surface — an eyeball whose centre is deeper than its own radius is invisible from every camera angle, which is the same as not building it.
- PUPILS RIDE THE EYE, and sit a hair further out along the same direction the eye faces.
- EARS BITE IN TOO: an ear overlaps the skull by 15-30% of its own radius. A tangent ear looks glued on and detaches the moment any solver touches it.
- MIRROR, DON'T RE-AUTHOR: eyes, ears, arms, hands, legs, feet, shoes and paired clothing details are bilaterally symmetric. Author the +X side, then give the -X twin the SAME y, the SAME z and the SAME dimensions with x negated. Two hand-authored halves drift, and asymmetry the reference does not show is read as damage.
- LIMBS AND FINGERS ARE BONES, NOT ROTATED CAPSULES: build every arm, leg and finger with the "bone" primitive — give the two joint positions [radius, x0,y0,z0, x1,y1,z1] and the engine orients it, so a limb can never point the wrong way. A BENT limb is TWO bones sharing the joint: an arm is shoulder→elbow then elbow→wrist; a leg is hip→knee then knee→ankle. Never author a limb as a single capsule with a hand-guessed rotation.
- A HAND OR A FOOT IS NOT ONE BALL: a glove is at least FOUR lobes — a palm mass, a thumb, and a grouped finger lobe (author individual fingers as short "bone" segments off the palm when the reference shows them), plus a cuff; a shoe is an elongated toe volume plus a heel plus a sole. Collapsing either to a single sphere is what makes a character read as a mannequin. Keep them simple, but keep the silhouette.
- SILHOUETTE IS THE IDENTITY: for a mascot the head-to-body ratio, the ear shape and the hand/foot silhouette carry recognition — spend parts there before spending them on surface detail.`,

  flatGraphic: `FLAT ARTWORK (this object is a logo / icon / symbol / drawing):
- Set inputKind "flat-graphic". Use roundedPlate for the background (it already faces the camera — rotation MUST stay [0,0,0]), positioned so each artwork shape sits just in front of the plate (z = plateDepth/2 + 0.03), depth ~0.06. Everything lives in the XY plane; use ZERO rotations anywhere. Sample baseColor values from the exact pixels of the reference — do not invent or "tastefully adjust" colors. NEVER approximate flat artwork with spheres or tilted boxes.
- CHOOSE THE OUTLINE PRIMITIVE BY THE SHAPE, not by habit: "extrudedSpline" curves smoothly through its points, "extrudedPolygon" joins them with straight lines. A brush stroke, a petal, a leaf, a rounded ray, a droplet, a hand-drawn mark — anything whose edges curve or whose tip is rounded — is extrudedSpline. Only genuinely straight-edged artwork (a chevron, a triangle, a rectangular bar) is extrudedPolygon. Four points joined by straight lines can only ever be a sharp kite: a starburst of soft rounded strokes came out as hard triangular spikes because each ray was authored as a 4-point polygon.
- POINT COUNT IS THE RESOLUTION OF THE SHAPE: 12-40 points per outline. A rounded tip alone needs 5-6 points to read as round. Fewer points is not simpler, it is a different shape.
- SEPARATE THE DEPTHS of shapes that overlap: give each one its own z, a hair apart (0.105, 0.1055, 0.106 …). Coplanar overlapping faces at an identical z have no depth order, so the renderer flickers between them as the camera moves — twelve rays meeting at a hub all sharing one z made the middle of an icon strobe.`,

  wrapDecal: `WRAPPED LABELS (this object has a label/print on a curved body):
- wrap-decal approach → curvedDecal wrapped at the host body's radius, attachTo the host — never a flat plate.`,

  boxy: `BOXY PARTS:
- boxy approach → roundedBox/box family with crisp bevels.`,

  grip: `CONTOURED HANDLES, GRIPS AND SCALES (a knife/tool handle, haft, hilt, scale or grip):
- A HANDLE IS ITS SIDE PROFILE, NOT A BRICK: even when the part reads as "boxy", author its lengthwise SIDE silhouette as an "extrudedSpline" — the curved outline (bellied edge, finger contour, tapered neck, rounded butt) as 10-20 [x,y] points in the XY plane (x along the handle's length, y its height), with "depth" = the handle's thickness. A plain roundedBox renders as a flat slab and throws away the shape that identifies the tool, so this OVERRIDES the boxy default for the handle part itself.
- MEASURE THE CURVE FROM THE REFERENCE: read the top and bottom edge heights at 5-8 stations along the length — a straight edge repeats the same y, a belly dips it, a taper ramps it. Do not substitute a "typical" handle taper for the measured outline.
- KEEP IT ONE PIECE: the whole scale/handle is ONE extrudedSpline; pivot pins, liner, bolster and pocket clip stay separate parts mounted on it.`,

  roundedShell: `SHELL PARTS:
- rounded-shell approach → hemisphere/blob shells.`,

  artwork: `PRINTED GRAPHICS (the plan marked artwork regions in the reference):
- REAL ARTWORK BEATS LETTERING: whenever a part carries printed graphics the reference shows — a label, stencil, placard, badge, screen, painted marking — set "textureRef" to that part's plan name so the engine crops the actual pixels out of the reference and applies them. A part whose plan entry has an "artwork" bbox is telling you exactly that. Spelling the words out with "text" instead produces flat lettering in the wrong font, and stacking two text decals to imitate a panel is strictly worse than one crop of the panel itself.`,

  architectural: `BUILDINGS AND SURFACE-MOUNTED DETAIL:
- ANCHOR SURFACE-MOUNTED PARTS, DON'T EYEBALL THEM: for anything that sits ON a face at a spot — windows, doors, balconies, railings, awnings, wall vents, trims, badges — use the "anchor" field ({targetId, face, uv, normalOffset}) instead of hand-computing world coords. The engine places it exactly on that wall/roof face at the (u,v) you give, so it can never float off or sink into the wall. This is the reliable way to position architectural detail — reach for it before authoring raw positions.
- WHY GROUND HEIGHT IS A FLAG HERE: in a tilted/isometric view you cannot read an object's ground depth from how high it sits in the image — a farther prop just looks higher. Set "grounded": true and author only horizontal (x,z) placement and size; the height is solved for you.
- A ROOF PIERCED BY AN UPPER STOREY IS A SKIRT, NOT A PYRAMID: on a two-storey house the lower roof surrounds the upper storey — it is the roof over the single-storey portion, with a hole where the upper floor rises through. A single pyramid cannot have that hole, so a full lower pyramid ends up entirely INSIDE the upper storey box and vanishes from the render. Build it as 4 separate sloped panels (prism, or thin rotated boxes) skirting the four sides of the upper storey, each sitting on the lower storey's top edge and sloping down and outward to the eaves. Only the topmost roof — the one nothing rises through — is a single pyramid.`,

  vehicle: `VEHICLE BODYWORK:
- A SKIRT, FLANK PANEL OR SIDE ARMOUR IS AN UPRIGHT PANEL, NOT A FLOOR: it stands along the vehicle's side, thin in X, tall in Y, long in Z — so it is TWO panels, one at each flank. A single slab that is wide in X and thin in Y is a floor plate lying under the vehicle, where nothing can see it.
- THE CAB IS A HOLLOW SHELL, NOT A TALL BOX: keep its height close to its width (not a narrow tower), give it a RAKED windshield (the front glass tilts back from a lower cowl, not a vertical face), and set its windows as recessed GLASS panes (transmission, near-clear) with a dark interior box behind them so the cab reads as a cabin you can see into — never a solid block with dark stickers.
- GRILLE, LIGHTS AND EMBLEM ARE INSET SOLIDS, NOT STICKERS: a grille is a thin recessed box with a dark metal / louver finish; headlights are small glass or faintly-emissive lenses set into the front; a badge/emblem is chrome (high metalness). A flat plane laid on the front reads as a decal, not a part.
- WHEELS ARE ROUND AND SEPARATE: space a wheel repeat by AT LEAST the tire diameter or the tires fuse into one tank-track band; the tire is dark matte rubber and the rim/hub is a metal disc RECESSED into the tire's outer face, never a cylinder poking out past it.`,

  machineDetail: `REPEATED MACHINE DETAIL:
- Repeated micro-details are what make a MACHINE read as real, so when the photo visibly carries rivet rows, bolt circles, vent slats, tread lugs or wheel sets, declare each ONCE with a "repeat" (rivets along an edge = small sphere + linear repeat; bolts around a hub = cylinder + radial repeat; 6 wheels = one wheel + linear repeat) — a truck or industrial machine usually earns several. Do NOT manufacture repeats for an object that has none.`,

  finishes: `PROCEDURAL FINISHES:
- A FINISH COVERS THE WHOLE PART, SO ONLY USE ONE THE WHOLE PART HAS. Two ways this goes wrong:
  · "camo" paints camouflage blotches over everything the material touches. Use it ONLY when the reference visibly shows a camouflage PATTERN. A military vehicle painted in one flat colour is not camouflaged — putting camo on it smears blotches across a clean painted hull and is the most obviously wrong thing in the render.
  · a LOCALISED pattern is a separate thin PANEL, not the host's material. Reference hazard striping is a narrow warning band along one edge; a vent grille is a panel on the rear. Setting "hazard" on the whole nose plate, or "louver" on the whole engine block, stripes or ribs the entire volume. Author a thin box laid on that surface and give the FINISH to that panel, leaving the host its own paint.`,
};

// Which blocks this object's own plan asks for, from two independent sources
// unioned together:
//
//   1. What stage 1 NOMINATED. It has looked at the photographs and knows what
//      the object is; asked to name the hazards it faces, it can reach a block
//      no keyword list would have matched. This is the path that carries a
//      genuinely new kind of object.
//   2. What the plan's own STRUCTURE implies — the declared approaches, an
//      artwork bbox, the semantic part names. Deterministic, and it holds when
//      stage 1 omits the field entirely (an older cached analysis, a model that
//      ignored it, a hand-edited plan).
//
// Neither is trusted alone. (1) without (2) would make the directives a matter
// of one model's mood; (2) without (1) is the category taxonomy stage 1
// deliberately abandoned. A union costs at most a block that did not apply.
//
// Pure — analysis in, recipe names out — so it is cheap to unit-test.
export function selectRecipeNames(analysis: any): string[] {
  let parts: any[] = Array.isArray(analysis?.partPlan) ? analysis.partPlan : [];
  let approaches = new Set(
    parts.map((p) => String(p?.approach ?? '').trim()).filter(Boolean),
  );
  let text = (pick: (p: any) => unknown) =>
    parts
      .map((p) => String(pick(p) ?? ''))
      .join(' ')
      .toLowerCase();
  // objectType rides along with the part names: "delivery truck" earns the
  // vehicle block even when every part is named generically (body, cab, panel)
  let names = `${String(analysis?.objectType ?? '')} ${text((p) => p?.part)}`;
  let primitives = text((p) => p?.primitives);
  let surfaces = `${text((p) => p?.details)} ${text((p) => p?.surface)} ${text(
    (p) => p?.material,
  )}`;
  let objectClass = String(analysis?.objectClass ?? '');

  // stage 1's nominations, filtered to names that actually exist — a
  // hallucinated directive name is dropped, never sent as an empty block
  let selected: string[] = (
    Array.isArray(analysis?.directives) ? analysis.directives : []
  )
    .map((name: any) => String(name).trim())
    .filter((name: string) => name in RECIPES);
  let take = (name: string, when: boolean) => {
    if (when && !selected.includes(name)) selected.push(name);
  };

  take('revolved', approaches.has('revolved') || /\blathe\b/.test(primitives));
  take('flatGraphic', approaches.has('flat-cutout'));
  take(
    'organic',
    objectClass === 'organic' ||
      objectClass === 'hybrid' ||
      approaches.has('curved-chain') ||
      approaches.has('freeform-mesh'),
  );
  // A face is the one structure whose parts are all correct individually and
  // wrong together, so it is named by its FEATURES rather than by an object
  // taxonomy: whatever the thing is — mascot, doll, animal, robot bust — a
  // plan listing eyes and a muzzle is describing a face and needs these rules.
  take(
    'character',
    /\b(muzzle|snout|face|facial|eye|eyes|eyeball|pupil|iris|eyelid|brow|nose|nostril|mouth|lip|tongue|tooth|teeth|jaw|chin|cheek|ear|ears|skull|head|torso|glove|hand|paw|finger|thumb|hoof|tail|whisker|mascot|character)s?\b/.test(
      names,
    ) && /\b(eye|pupil|nose|mouth|muzzle|snout|face|ear)s?\b/.test(names),
  );
  take('wrapDecal', approaches.has('wrap-decal'));
  take('boxy', approaches.has('boxy'));
  take('roundedShell', approaches.has('rounded-shell'));
  // a contoured handle/grip is the shape that identifies a tool, and it is the
  // one boxy default gets wrong — trigger the extrudedSpline guidance whenever
  // the plan names a handle-family part
  take('grip', /\b(handle|grip|grips|scale|scales|haft|hilt)\b/.test(names));
  take(
    'artwork',
    parts.some((p) => p?.artwork),
  );
  take(
    'architectural',
    /\b(roof|storey|story|floor|wall|balcony|window|eave|gable|facade|porch|carport|door)\b/.test(
      names,
    ),
  );
  take(
    'vehicle',
    /\b(hull|chassis|skirt|flank|track|wheel|axle|fender|bumper|cab|tyre|tire)\b/.test(
      names,
    ),
  );
  // the rule names wheel sets alongside rivet rows, so the repeated-feature
  // nouns count too — a truck whose plan says "six wheels in two rows" is
  // exactly the case the rule was written for
  take(
    'machineDetail',
    /\b(rivet|bolt|vent|slat|louver|louvre|tread|grille|grill|lug|fastener|wheel|axle|spoke|barrel|picket|baluster|fin|tooth|teeth|stud)s?\b/.test(
      `${names} ${surfaces}`,
    ),
  );
  take(
    'finishes',
    /\b(worn|weathered|rust|rusty|patina|camo|camouflage|brushed|knurl|knurled|hazard|tread|grime|scratched|oxidi)\w*/.test(
      surfaces,
    ),
  );
  return selected;
}

export function selectRecipes(analysis: any): string {
  return selectRecipeNames(analysis)
    .map((name) => RECIPES[name])
    .filter(Boolean)
    .join('\n\n');
}
