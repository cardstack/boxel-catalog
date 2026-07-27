// The user-directed edit pass: apply one instruction to a named set of parts.

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
