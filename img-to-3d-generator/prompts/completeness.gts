// The completeness critic: a category-AGNOSTIC pass that compares the render
// against the reference and, unlike the conservative refine pass, is allowed to
// ADD the parts the build left out.
//
// This is the general answer to "the model is missing a part" — instead of
// hardcoding per-category checklists in the analysis prompt (a face has eyes, a
// car has wheels, a chair has legs …), we look at what the reference actually
// shows and add whatever the render is missing, whatever the object is.

export const COMPLETENESS_CRITIC_PROMPT = `You are a 3D reconstruction engine auditing your own build for COMPLETENESS against the reference. You receive a comparison sheet — the LEFTMOST panel is the REFERENCE photo, the remaining panels are the CURRENT render (front / side / three-quarter) — plus the current spec JSON.

YOUR ONE JOB: find every part the REFERENCE clearly shows that the render is MISSING, or that is so grossly misplaced it reads as absent, and fix it. Make NO assumptions about what kind of object this is — do not reason from "this is a face / car / chair"; reason ONLY from what the two images show. Walk the reference feature by feature and ask, for each: is there a matching part in the render? If not, ADD it. This is the opposite of the refine pass — here, ADDING what is missing is the whole point.

What counts as missing:
- a distinct volume visible in the reference with no counterpart in the render (a wheel, an eye, a handle, a fin, a button, a limb, a label);
- a feature the render collapsed into its neighbour (two eyes drawn as one blob, four fingers as one mitten) — split it out;
- a part hidden inside another because its position is wrong — pull it out to where the reference shows it.
- GLAZING AND OPENINGS ARE THE MOST-MISSED PARTS, so check for them deliberately: windows, a windshield, side/rear glass, a sunroof, a screen, a lens, a vent or grille opening. They are flat and low-contrast (clear glass on a light body barely registers), so the earlier stages routinely drop them — but the reference almost always shows them on a vehicle, cab, building or device. If the reference shows a window the render lacks, ADD it as a thin glass pane ("inset": true, a transmission material, near-clear tint) recessed into the body.
Do NOT invent detail the reference does not show, and do NOT re-model parts that are already present and roughly right — a build that is already complete gets an empty answer.

Author each ADDED part exactly like a spec component: pick a primitive from the vocabulary the spec already uses, size it against the parts around it (their dimensions are in the spec), give it a "partRef" naming what it is, an "attachTo" naming the part it mounts on, and read the reference for its position, relative size and colour. If it needs a colour no existing material has, add that material in "materialsChanged" and reference its id. Mirror bilateral features (left/right eye, both wheels) as two parts with x negated. The object frame is fixed: -Z FORWARD, +Y UP, +X RIGHT.

Respond with ONLY this JSON object:
{
  "critique": "1 sentence: what was missing and what you added",
  "score": 0-100 (honest completeness estimate AFTER your additions, never above 90),
  "changed": [ { "nodeId": "<existing id>", "position": [x,y,z]?, "rotation": [x,y,z]?, "scale": [x,y,z]? } — ONLY for a present part that is so misplaced it reads as missing; include only the fields you change ],
  "added": [ { "nodeId": "new-kebab-id", "parentId": "<an existing id or the root group>", "primitive": "<from the spec's vocabulary>", "dimensions": [numbers], "position": [x,y,z], "rotation": [x,y,z], "scale": [x,y,z], "materialId": "m-...", "partRef": "what this part is", "attachTo": "<the id it mounts on>", "note": "short" } — the parts the reference shows and the render lacks ],
  "materialsChanged": [ COMPLETE material objects for any new colour an added part needs ]
}

- Do NOT change an existing part's "primitive" or "dimensions", and do NOT remove parts — this pass only ADDS what is missing and nudges a badly-hidden part into view.
- If the build already shows everything the reference shows, return empty "added" and "changed" arrays.`;
