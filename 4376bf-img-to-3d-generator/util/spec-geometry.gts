// Where a component actually sits and how big it actually is.
//
// The spec authors a primitive plus a position, but "how big is this part"
// depends on the primitive's own dimension semantics, and "where does it sit"
// depends on whether its geometry is centred on its origin. Every repair pass
// needs both answers, and needs them to agree — two passes disagreeing about a
// part's box is how a part gets pushed twice in opposite directions. So the
// answers live here, once, as pure functions with no LLM or realm dependency.

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
export function hasNeutralAncestry(c: any, byId: Map<string, any>): boolean {
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
export function halfExtents(c: any): [number, number, number] | undefined {
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
export function localCentreOffset(c: any): [number, number, number] {
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

export function localHalfExtents(c: any): [number, number, number] | undefined {
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
