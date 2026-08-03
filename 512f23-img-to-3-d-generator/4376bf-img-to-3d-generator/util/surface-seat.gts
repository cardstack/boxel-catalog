// Seating surface features on the mass they are mounted on.
//
// The declared-joint solver next door closes GAPS: if a part's box does not
// reach its support's box it translates the part until they overlap by a
// hair. That is the only placement error it can see, and it is the less
// common one. A feature mounted on a rounded mass fails two other ways the
// box test calls correct:
//
//   · BURIED — the eye's box sits well inside the muzzle's box, so contact is
//     satisfied while nothing of the eye is visible from any angle.
//   · DETACHED-BUT-TOUCHING — the muzzle's centre sits outside the skull and
//     only its back rim grazes it, so contact is satisfied while the face
//     reads as a separate lump floating in front of the head.
//
// Both are the same error measured against the right surface: a feature is
// seated when its centre sits just INSIDE its host's surface, along the
// direction it was authored to face. Boxes cannot express that for a rounded
// host — an ellipsoid can, and every mass this matters for (skull, muzzle,
// eyeball, cushion, fruit) is an ellipsoid to within the accuracy this pass
// needs.
//
// Deliberately narrow. It acts only on the two unambiguous failures above:
// a feature already straddling its host's surface is left exactly where the
// spec put it, because that is what a correct part looks like and any nudge
// would be this pass inventing a placement of its own.
//
// Written as a hoisting function DECLARATION with no module-level references
// and no `?.` / `??`, for the same reason as expandRepeatInstances: the code
// exporter emits its source verbatim via `Function.prototype.toString()`, so
// the studio viewport and a standalone exported model seat parts identically.
export function seatSurfaceParts(
  THREE: any,
  objects: any,
  joints: any[],
): string[] {
  let logs: string[] = [];
  if (!joints || !joints.length) return logs;

  // ellipsoid radius along a unit direction, from the half extents of a box
  function radiusAlong(half: any, unit: any): number {
    let hx = Math.max(half.x, 1e-6);
    let hy = Math.max(half.y, 1e-6);
    let hz = Math.max(half.z, 1e-6);
    let q =
      (unit.x / hx) * (unit.x / hx) +
      (unit.y / hy) * (unit.y / hy) +
      (unit.z / hz) * (unit.z / hz);
    if (!(q > 0)) return 0;
    return 1 / Math.sqrt(q);
  }

  function measure(obj: any): any {
    let box = new THREE.Box3().setFromObject(obj);
    if (box.isEmpty()) return undefined;
    let size = box.getSize(new THREE.Vector3());
    return {
      center: box.getCenter(new THREE.Vector3()),
      half: size.multiplyScalar(0.5),
      mean: (size.x + size.y + size.z) / 3,
    };
  }

  let hostOf = new Map();
  for (let i = 0; i < joints.length; i++) {
    let joint = joints[i];
    if (joint && joint.id && joint.to) hostOf.set(joint.id, joint.to);
  }

  // Hosts settle before the features on them: a pupil is seated on an eyeball
  // that may itself be moving onto the muzzle this same pass, and reading a
  // stale eyeball position would seat the pupil against a surface that is no
  // longer there. Depth in the joint chain is that order.
  function depthOf(id: string): number {
    let depth = 0;
    let at = id;
    let seen: any = {};
    while (hostOf.has(at) && !seen[at]) {
      seen[at] = true;
      at = hostOf.get(at);
      depth++;
      if (depth > 32) break;
    }
    return depth;
  }
  let ordered = joints.slice().sort(function (a: any, b: any) {
    return depthOf(a.id) - depthOf(b.id);
  });

  // What this pass has already moved, so a feature declared on a moved host
  // travels with it. A pupil is authored against its eyeball's position; once
  // the eyeball slides round to the front of the face, the pupil's offset is
  // stale rather than wrong, and re-seating it from where it was left would
  // read the wrong direction and then reject the correction as too large.
  let carried = new Map();

  for (let n = 0; n < ordered.length; n++) {
    let joint = ordered[n];
    let obj = objects.get(joint.id);
    let host = objects.get(joint.to);
    if (!obj || !host || obj === host) continue;
    let inherited = carried.get(joint.to);
    if (inherited) {
      let world = obj.getWorldPosition(new THREE.Vector3()).add(inherited);
      obj.position.copy(obj.parent ? obj.parent.worldToLocal(world) : world);
      obj.updateWorldMatrix(true, true);
      carried.set(joint.id, inherited.clone());
    }
    // a nested part's box lives inside its parent's by construction, so
    // "buried" is what it is supposed to be
    let ancestor = obj.parent;
    let nested = false;
    while (ancestor) {
      if (ancestor === host) {
        nested = true;
        break;
      }
      ancestor = ancestor.parent;
    }
    if (nested) continue;

    let c = measure(obj);
    let h = measure(host);
    if (!c || !h || !(h.mean > 0) || !(c.mean > 0)) continue;
    // Only a FEATURE gets seated. Two parts of comparable size are a
    // structural stack (torso on shorts, roof on storey) whose placement the
    // declared joint already owns, and pulling one to the other's surface
    // would be this pass overruling the assembly graph.
    if (c.mean > 0.85 * h.mean) continue;
    // ...and only a COMPACT one. An ellipsoid centred on the part is a fair
    // model of an eye, a nose or a wheel hub, and a useless model of an arm:
    // a limb's centre is half its length away from the joint it hangs off, so
    // seating that centre on the shoulder buries the whole arm in the torso.
    // The elongated parts are exactly the ones whose placement the declared
    // joint already handles well, so requiring roundness costs nothing.
    let cH = [c.half.x, c.half.y, c.half.z];
    let cMin = Math.min(cH[0], cH[1], cH[2]);
    let cMax = Math.max(cH[0], cH[1], cH[2]);
    if (!(cMin > 0) || cMax > 2 * cMin) continue;

    let dir = c.center.clone().sub(h.center);
    if (dir.lengthSq() < 1e-8) continue;
    let dist = dir.length();
    let unit = dir.clone().divideScalar(dist);
    let hostR = radiusAlong(h.half, unit);
    let childR = radiusAlong(c.half, unit);
    if (!(hostR > 0) || !(childR > 0)) continue;

    // WHICH WAY IS OUT — the error that survives every other check, because
    // depth alone cannot see it. For a feature on a free-standing mass, "out"
    // is simply away from that mass's centre. But when the host is ITSELF a
    // feature bolted to something bigger — a muzzle on a skull — the exposed
    // side of the muzzle is the side pointing away from the skull, and a
    // feature whose authored offset points the other way is behind the face.
    // It can be perfectly seated on the muzzle's surface and still be inside
    // the head, visible from nowhere: this Mickey's eyes sat 0.24 behind the
    // muzzle's centre and every box test called them attached.
    //
    // The offset's tangential part carries the feature's left/right and
    // up/down placement on the face and is kept as authored; only the
    // through-the-face component is rebuilt, positive by construction.
    let flipped = false;
    let grandId = hostOf.get(joint.to);
    let grand = grandId ? objects.get(grandId) : undefined;
    let g = grand && grand !== host ? measure(grand) : undefined;
    if (g && h.mean <= 0.8 * g.mean) {
      let outward = h.center.clone().sub(g.center);
      if (outward.lengthSq() > 1e-8) {
        outward.normalize();
        let along = dir.dot(outward);
        if (along < 0.15 * dist) {
          let rebuilt = dir
            .clone()
            .addScaledVector(outward, -along)
            .addScaledVector(outward, 0.6 * dist);
          if (rebuilt.lengthSq() > 1e-8) {
            dir = rebuilt;
            dist = dir.length();
            unit = dir.clone().divideScalar(dist);
            hostR = radiusAlong(h.half, unit);
            childR = radiusAlong(c.half, unit);
            flipped = true;
          }
        }
      }
    }
    if (!(hostR > 0) || !(childR > 0)) continue;

    // Depth. A seated feature bites into its host by about a quarter of its
    // own radius: enough that the join reads as one form, little enough that
    // the feature is still mostly proud of the surface.
    let seated = hostR + 0.75 * childR;
    // Only the two errors the box solver next door CANNOT see. A part merely
    // sitting in mid-air short of its host is that solver's case and it
    // handles it well; this pass reaching for it too meant an upper arm being
    // "seated" 0.34 into the torso, because an ellipsoid centred on a limb is
    // nowhere near the shoulder the limb actually hangs from.
    let buried = dist + childR <= hostR;
    if (!flipped && !buried) continue;
    let move = seated - dist;
    if (Math.abs(move) < 1e-4) continue;
    // never relocate a part across the model: a correction larger than the
    // host itself means the spec is wrong somewhere this pass cannot see
    if (Math.abs(move) > 1.2 * hostR) {
      logs.push(
        `'${joint.id}' sits more than its own host's radius out of place on '${joint.to}' — left for refine`,
      );
      continue;
    }
    let why = flipped ? 'was on the hidden side' : 'was buried';

    let shift = h.center.clone().addScaledVector(unit, seated).sub(c.center);
    let previous = carried.get(joint.id);
    carried.set(
      joint.id,
      previous ? previous.add(shift.clone()) : shift.clone(),
    );
    let worldPos = obj.getWorldPosition(new THREE.Vector3()).add(shift);
    obj.position.copy(
      obj.parent ? obj.parent.worldToLocal(worldPos) : worldPos,
    );
    obj.updateWorldMatrix(true, true);
    logs.push(
      `seated '${joint.id}' on '${joint.to}' (${why}, moved ${Math.abs(move).toFixed(2)})`,
    );
  }
  return logs;
}
