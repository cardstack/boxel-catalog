// Repetition systems: one declared part becomes N placed copies.
//
// This is the ONE implementation. The studio interpreter imports it directly
// and the code exporter emits its own source via `Function.prototype.toString()`
// (the same trick the finish painters use), so a standalone exported model
// arrays its parts exactly the way the viewport does. Both used to carry a
// hand-copied twin of this logic and they drifted: a fix to the interpreter's
// copy left every exported model still wrong, which is the only copy the
// viewport actually renders.
//
// Written as a hoisting function DECLARATION with no module-level references —
// emitted into `buildSculpture`, it has to stand alone. It also sticks to
// syntax that survives compilation untouched (no `?.` / `??`), so the emitted
// text can never reach for a transpiler helper that is not there.
export function expandRepeatInstances(
  THREE: any,
  original: any,
  rep: any,
  host: any,
  root: any,
  onClone: (clone: any) => void,
): void {
  if (!rep || typeof rep !== 'object') return;
  let count = Math.min(48, Math.max(0, Math.round(rep.count || 0)));
  if (count < 2) return;
  let parent = original.parent || root;
  let axis = rep.axis === 'x' ? 'x' : rep.axis === 'z' ? 'z' : 'y';
  let basePos = original.position.clone();
  let baseQuat = original.quaternion.clone();
  // RING CENTER for a radial array. The part's own in-plane position is
  // already a point ON the intended circle, so adding the radius to it put
  // every clone at twice the radius — 20 knurl ridges orbited at 0.29 around a
  // 0.16 cap, reading as a spiked collar floating off the cap. The circle
  // belongs to the part this array wraps around, so its axis supplies the
  // in-plane center; the position ALONG the axis stays where the part was
  // authored. With no declared host there is nothing to centre on, so the
  // part's own position is kept as the centre.
  let center = basePos.clone();
  if (rep.mode === 'radial' && host && host !== original) {
    let hostBox = new THREE.Box3().setFromObject(host);
    if (!hostBox.isEmpty()) {
      let hostCenter = hostBox.getCenter(new THREE.Vector3());
      parent.worldToLocal(hostCenter);
      if (axis === 'y') {
        center.x = hostCenter.x;
        center.z = hostCenter.z;
      } else if (axis === 'x') {
        center.y = hostCenter.y;
        center.z = hostCenter.z;
      } else {
        center.x = hostCenter.x;
        center.y = hostCenter.y;
      }
    }
  }
  // place instance i — index 0 is the original itself, so a radial array is one
  // coherent ring instead of the original sitting off the circle its own clones
  // orbit on
  let place = (obj: any, i: number) => {
    if (rep.mode === 'radial') {
      let radius = rep.radius != null ? rep.radius : 0.5;
      let angle = (i / count) * Math.PI * 2;
      let ca = Math.cos(angle) * radius;
      let sa = Math.sin(angle) * radius;
      // The instance is carried around the ring RIGIDLY: the orbital angle
      // composes OUTSIDE the part's own orientation, so a part already aimed
      // along the ring axis keeps that aim. Adding the angle to the matching
      // Euler component instead composes it inside that orientation, and since
      // Euler order is XYZ that tilts every clone by its own angle — six
      // minigun barrels laid along z came out crossed like an asterisk rather
      // than parallel. Positions sweep +x→+z about y, which is a rotation
      // about −y, so that one axis spins the opposite way to stay in step.
      let spin = new THREE.Quaternion().setFromAxisAngle(
        new THREE.Vector3(
          axis === 'x' ? 1 : 0,
          axis === 'y' ? 1 : 0,
          axis === 'z' ? 1 : 0,
        ),
        axis === 'y' ? -angle : angle,
      );
      obj.quaternion.copy(baseQuat).premultiply(spin);
      if (axis === 'y') {
        obj.position.set(center.x + ca, center.y, center.z + sa);
      } else if (axis === 'x') {
        obj.position.set(center.x, center.y + ca, center.z + sa);
      } else {
        obj.position.set(center.x + ca, center.y + sa, center.z);
      }
    } else {
      let offset = Array.isArray(rep.offset) ? rep.offset : [0.2, 0, 0];
      obj.position.set(
        basePos.x + offset[0] * i,
        basePos.y + offset[1] * i,
        basePos.z + offset[2] * i,
      );
    }
  };
  place(original, 0);
  for (let i = 1; i < count; i++) {
    let clone = original.clone(true);
    clone.name = `${original.name || 'part'}-${i}`;
    place(clone, i);
    parent.add(clone);
    onClone(clone);
  }
}
