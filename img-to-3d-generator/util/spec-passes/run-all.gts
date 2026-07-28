// The one ordered run of the deterministic structure passes.
//
// Every pass here is pure — (parsed[, analysis]) => string[] log lines, mutating
// the spec in place — and the ORDER between them is load-bearing: passes read
// each other's output, and two in the wrong order fight (a burial push undoing a
// face seat, a ground snap overruling an inverted attachment). That ordering
// used to live inline in the studio's generate() as a dozen separate loops,
// where it was invisible and untested. Centralising it here makes the sequence
// explicit, keeps the "why this order" notes next to the calls, and lets a test
// run the WHOLE chain over a spec instead of only each pass in isolation.

import {
  dropHairlineParts,
  dropUnplannedParts,
  flagUnrealizedParts,
  flagOverbuiltParts,
  repairMirroredAttachments,
  enforceAttachments,
  groundSupports,
  ensureFaceParts,
  alignFaceFeatures,
  seatRingCollars,
  resolveBuriedParts,
  clampInteriorCavities,
  seatRecesses,
  flagInstanceCollisions,
  flagFlatPalette,
  flagSilhouetteNotch,
  repairPrimitiveConventions,
  separateCoplanarLayers,
} from './index';

// Runs the full deterministic structure/geometry repair chain over a freshly
// built spec and returns every log line, in order. Used by the studio's
// generate() (which prefixes each line with "> " for its console) and by the
// integration test.
export function runStructurePasses(parsed: any, analysis: any): string[] {
  let logs: string[] = [];
  let run = (lines: string[]) => {
    for (let line of lines) logs.push(line);
  };

  // The analysis owns the part INVENTORY: a hairline solid is a surface mark
  // whatever it is called, and anything the build invented on top of the plan
  // goes now, before later passes spend work on it.
  run(dropHairlineParts(parsed));
  run(dropUnplannedParts(parsed, analysis));
  // the other direction: a planned part that nothing realized (report only)
  run(flagUnrealizedParts(parsed, analysis));
  run(flagOverbuiltParts(parsed, analysis));

  // Attachments are hard joints, sanity-checked and enforced in the spec's own
  // coordinates before anything camera-derived reasons about them.
  run(repairMirroredAttachments(parsed));
  run(enforceAttachments(parsed, analysis));
  // runs AFTER the attachment lines — those can be inverted (a plan once said
  // the wheels rest on the hull), and grounding is the check no plan overrules.
  run(groundSupports(parsed));

  // Faces: FIRST guarantee the core features exist (the build routinely omits
  // eyes/mouth, and dropUnplannedParts above removed anything unplanned), THEN
  // align them onto the front and bite the muzzle in. Both run BEFORE
  // resolveBuriedParts, which would otherwise surface an embedded muzzle out the
  // skull's back face (its cheapest exit) and undo the bite.
  run(ensureFaceParts(parsed, analysis));
  run(alignFaceFeatures(parsed, analysis));

  // a ring that wraps a barrel (muzzle collar, clamp, ferrule) is seated on the
  // barrel's axis before burial resolution, so it is not read as a floating part.
  run(seatRingCollars(parsed));

  // seating two parts on the same support can bury one inside the other — check
  // after the joints are enforced and the face is placed, not before.
  run(resolveBuriedParts(parsed));

  // a hollow body's dark interior box must stay inside its shell — runs after
  // burial (which is told to leave interiors alone) so the shell is already
  // placed when the cavity is fitted to it.
  run(clampInteriorCavities(parsed));
  // and the other direction from protrusion: a recessed feature (window well,
  // grille cavity, sunken panel) is sunk INTO the host surface rather than
  // ejected — the mirror of resolveBuriedParts.
  run(seatRecesses(parsed));

  run(flagInstanceCollisions(parsed));
  run(flagFlatPalette(parsed));
  run(flagSilhouetteNotch(parsed));
  run(repairPrimitiveConventions(parsed));
  run(separateCoplanarLayers(parsed));

  return logs;
}
