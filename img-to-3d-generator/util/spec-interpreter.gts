import { makeFinishTexture, mulberry32 } from './finishes';
import { loadGltfLoader } from './three-loader';

// Deterministic SculptSpec → THREE.Group interpreter.
//
// The vision LLM only ever authors declarative spec data (primitives,
// transforms, PBR params); this module is the sole place geometry gets
// built, so no LLM output is ever executed as code.

export interface SculptNodeData {
  nodeId: string;
  parentId?: string | null;
  primitive?: string | null;
  dimensions?: string | null;
  position?: string | null;
  rotation?: string | null;
  scale?: string | null;
  materialId?: string | null;
  text?: string | null;
  repeat?: string | null;
  assetUrl?: string | null;
  attachTo?: string | null;
  note?: string | null;
}

export interface SculptMaterialData {
  materialId: string;
  baseColor?: string | null;
  roughness?: number | null;
  metalness?: number | null;
  opacity?: number | null;
  emissive?: string | null;
  emissiveIntensity?: number | null;
  clearcoat?: number | null;
  sheen?: number | null;
  finish?: string | null;
}

export interface BuiltModel {
  group: any;
  meshes: any[];
  nodeCount: number;
  // non-fatal problems encountered while building (e.g. a component that
  // referenced an undefined material) — surfaced to the card's log so
  // failures are never silent
  warnings: string[];
  dispose: () => void;
}

function nums(raw: string | null | undefined, fallback: number[]): number[] {
  if (!raw) return fallback;
  try {
    let parsed = JSON.parse(raw);
    if (
      Array.isArray(parsed) &&
      parsed.every((n) => typeof n === 'number' && isFinite(n))
    ) {
      return parsed;
    }
  } catch {
    // fall through to fallback
  }
  return fallback;
}

function clamp01(n: number | null | undefined, fallback: number): number {
  if (typeof n !== 'number' || !isFinite(n)) return fallback;
  return Math.min(1, Math.max(0, n));
}

// canvas-drawn text on a transparent plane (Sony showcase decal technique) —
// wordmarks and labels are identity features primitives can't fake
function buildTextDecal(
  THREE: any,
  d: number[],
  text: string,
  color: string,
): any {
  let w = d[0] ?? 0.8;
  let h = d[1] ?? 0.25;
  let canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = Math.max(64, Math.round((512 * h) / Math.max(w, 0.001)));
  let ctx = canvas.getContext('2d')!;
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = color;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  let fontSize = Math.floor(canvas.height * 0.62);
  ctx.font = `700 ${fontSize}px Arial, sans-serif`;
  while (fontSize > 8 && ctx.measureText(text).width > canvas.width * 0.94) {
    fontSize -= 4;
    ctx.font = `700 ${fontSize}px Arial, sans-serif`;
  }
  ctx.fillText(text, canvas.width / 2, canvas.height / 2);
  let texture = new THREE.CanvasTexture(canvas);
  texture.encoding = THREE.sRGBEncoding;
  texture.anisotropy = 8;
  let material = new THREE.MeshBasicMaterial({
    map: texture,
    transparent: true,
    depthWrite: false,
    polygonOffset: true,
    polygonOffsetFactor: -4,
    toneMapped: false,
  });
  return new THREE.Mesh(new THREE.PlaneGeometry(w, h), material);
}

// label wrapped around a cylindrical body (wine bottles, cans, jars, mugs) —
// an open cylinder-segment shell carrying a painted label texture. Flat
// planes read as stickers floating beside the bottle; this hugs the radius.
function buildCurvedDecal(
  THREE: any,
  d: number[],
  text: string,
  baseColor: string,
): any {
  let radius = Math.abs(d[0] ?? 0.5);
  let height = Math.abs(d[1] ?? 0.6);
  let arc = ((Math.min(Math.max(d[2] ?? 120, 20), 350) * Math.PI) /
    180) as number;
  let canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = Math.max(
    64,
    Math.round((512 * height) / Math.max(radius * arc, 0.001)),
  );
  let ctx = canvas.getContext('2d')!;
  ctx.fillStyle = baseColor || '#f4f1e8';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  if (text) {
    // contrast ink from the label ground's luminance
    let hex = (baseColor || '#f4f1e8').replace('#', '');
    let lum =
      hex.length >= 6
        ? (parseInt(hex.slice(0, 2), 16) * 0.299 +
            parseInt(hex.slice(2, 4), 16) * 0.587 +
            parseInt(hex.slice(4, 6), 16) * 0.114) /
          255
        : 0.9;
    ctx.fillStyle = lum > 0.5 ? '#20242c' : '#f2f2f2';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    let fontSize = Math.floor(canvas.height * 0.28);
    ctx.font = `700 ${fontSize}px Georgia, 'Times New Roman', serif`;
    while (fontSize > 8 && ctx.measureText(text).width > canvas.width * 0.82) {
      fontSize -= 4;
      ctx.font = `700 ${fontSize}px Georgia, 'Times New Roman', serif`;
    }
    ctx.fillText(text, canvas.width / 2, canvas.height / 2);
  }
  let texture = new THREE.CanvasTexture(canvas);
  texture.encoding = THREE.sRGBEncoding;
  texture.anisotropy = 8;
  // lit standard material so the label shades with the body it wraps
  let material = new THREE.MeshStandardMaterial({
    map: texture,
    roughness: 0.6,
    metalness: 0,
    side: THREE.DoubleSide,
    polygonOffset: true,
    polygonOffsetFactor: -2,
  });
  // arc centered on +Z (cylinder verts: x = r·sin θ, z = r·cos θ)
  let geometry = new THREE.CylinderGeometry(
    radius,
    radius,
    height,
    48,
    1,
    true,
    -arc / 2,
    arc,
  );
  return new THREE.Mesh(geometry, material);
}

// camera-facing glow sprite (War-Hauler reactor-glow technique): a radial
// gradient on a canvas, additively blended, always facing the viewer
function buildGlowSprite(THREE: any, d: number[], color: string): any {
  let size = d[0] ?? 0.3;
  let cv = document.createElement('canvas');
  cv.width = 128;
  cv.height = 128;
  let ctx = cv.getContext('2d')!;
  let g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.35, 'rgba(255,255,255,0.55)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 128, 128);
  let tex = new THREE.CanvasTexture(cv);
  let material = new THREE.SpriteMaterial({
    map: tex,
    color: new THREE.Color(color),
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    toneMapped: false,
  });
  let sprite = new THREE.Sprite(material);
  sprite.scale.set(size, size, 1);
  return sprite;
}

// rounded-rect outline in the XZ plane (Sony showcase "stadium" technique)
function roundedRectShape(
  THREE: any,
  len: number,
  depth: number,
  r: number,
): any {
  let s = new THREE.Shape();
  let hx = Math.max(len / 2 - r, 0.001);
  let hz = Math.max(depth / 2 - r, 0.001);
  s.absarc(-hx, -hz, r, Math.PI, Math.PI * 1.5);
  s.absarc(hx, -hz, r, Math.PI * 1.5, 0);
  s.absarc(hx, hz, r, 0, Math.PI * 0.5);
  s.absarc(-hx, hz, r, Math.PI * 0.5, Math.PI);
  return s;
}

// fetches a .glb and mounts its scene under the given group — the meshAsset
// half of the hybrid pipeline. Shadows enabled to match procedural parts.
async function loadGlbInto(
  url: string,
  mount: any,
  loadedAssets: any[],
): Promise<void> {
  let ns = await loadGltfLoader();
  let gltf: any = await new Promise((resolve, reject) => {
    new ns.GLTFLoader().load(url, resolve, undefined, reject);
  });
  let scene = gltf?.scene;
  if (!scene) throw new Error('glb has no scene');
  scene.traverse((child: any) => {
    if (child.isMesh) {
      child.castShadow = true;
      child.receiveShadow = true;
    }
  });
  loadedAssets.push(scene);
  mount.add(scene);
}

function buildGeometry(THREE: any, primitive: string, d: number[]): any {
  switch (primitive) {
    case 'box':
      return new THREE.BoxGeometry(d[0] ?? 1, d[1] ?? 1, d[2] ?? 1);
    case 'roundedBox': {
      // [w, h, d, cornerRadius?, bevel?] — box rounded on ALL edges when the
      // RoundedBoxGeometry add-on is available (the War-Hauler armor look);
      // otherwise an extruded rounded-rect slab (rounded in plan view only)
      let w = d[0] ?? 1;
      let h = d[1] ?? 0.3;
      let dep = d[2] ?? 1;
      let r = Math.min(Math.abs(d[3] ?? 0.1), Math.min(w, dep) / 2 - 0.001);
      if (THREE.RoundedBoxGeometry) {
        let radius = Math.min(r, Math.min(w, h, dep) / 2 - 0.001);
        return new THREE.RoundedBoxGeometry(
          w,
          h,
          dep,
          3,
          Math.max(0.01, radius),
        );
      }
      let bevel = Math.min(Math.abs(d[4] ?? 0.02), h / 3);
      let geo = new THREE.ExtrudeGeometry(roundedRectShape(THREE, w, dep, r), {
        depth: Math.max(h - bevel * 2, 0.001),
        bevelEnabled: bevel > 0,
        bevelThickness: bevel,
        bevelSize: bevel,
        bevelSegments: 3,
        curveSegments: 24,
      });
      geo.rotateX(-Math.PI / 2);
      geo.translate(0, bevel - h / 2, 0);
      return geo;
    }
    case 'roundedPlate': {
      // [w, h, depth, cornerRadius?] — rounded-rect plate in the XY plane
      // facing +Z (no rotation needed for camera-facing artwork), centered
      let w = d[0] ?? 2;
      let h = d[1] ?? 2;
      let dep = Math.abs(d[2] ?? 0.1);
      let r = Math.min(Math.abs(d[3] ?? 0.2), Math.min(w, h) / 2 - 0.001);
      let geo = new THREE.ExtrudeGeometry(roundedRectShape(THREE, w, h, r), {
        depth: dep,
        bevelEnabled: false,
        curveSegments: 24,
      });
      geo.translate(0, 0, -dep / 2);
      return geo;
    }
    case 'flatRing': {
      // [outerRx, outerRy, ringWidth, depth] — flat elliptical ring with a
      // real hole (scissor handle loops, bracelets, grab rings), XY plane
      // facing +Z, centered. Same Shape.holes technique as the Sony deck.
      let orx = Math.abs(d[0] ?? 0.5);
      let ory = Math.abs(d[1] ?? orx);
      let width = Math.min(Math.abs(d[2] ?? 0.12), Math.min(orx, ory) - 0.01);
      let depth = Math.abs(d[3] ?? 0.08);
      let shape = new THREE.Shape();
      shape.absellipse(0, 0, orx, ory, 0, Math.PI * 2, false, 0);
      let hole = new THREE.Path();
      hole.absellipse(0, 0, orx - width, ory - width, 0, Math.PI * 2, true, 0);
      shape.holes.push(hole);
      let geo = new THREE.ExtrudeGeometry(shape, {
        depth,
        bevelEnabled: false,
        curveSegments: 32,
      });
      geo.translate(0, 0, -depth / 2);
      return geo;
    }
    case 'arch': {
      // [outerR, ringWidth, depth, sweepDeg?] — partial flat ring spanning
      // the top (wheel arches, fenders, handles' bridges), XY facing +Z
      let outer = Math.abs(d[0] ?? 0.6);
      let width = Math.min(Math.abs(d[1] ?? 0.15), outer - 0.01);
      let depth = Math.abs(d[2] ?? 0.3);
      let sweep = (Math.min(340, Math.max(20, d[3] ?? 180)) * Math.PI) / 180;
      let start = Math.PI / 2 + sweep / 2;
      let end = Math.PI / 2 - sweep / 2;
      let inner = outer - width;
      let shape = new THREE.Shape();
      shape.absarc(0, 0, outer, start, end, true);
      shape.lineTo(Math.cos(end) * inner, Math.sin(end) * inner);
      shape.absarc(0, 0, inner, end, start, false);
      shape.closePath();
      let geo = new THREE.ExtrudeGeometry(shape, {
        depth,
        bevelEnabled: false,
        curveSegments: 32,
      });
      geo.translate(0, 0, -depth / 2);
      return geo;
    }
    case 'prism': {
      // [lengthAlongRidge, span, height] — triangular prism with the ridge
      // running along X (gable roofs, ramps, wedges) — the Doraemon-house
      // technique, pre-oriented so no rotation math is needed
      let length = Math.abs(d[0] ?? 1.5);
      let span = Math.abs(d[1] ?? 1);
      let height = Math.abs(d[2] ?? 0.6);
      let shape = new THREE.Shape();
      shape.moveTo(-span / 2, 0);
      shape.lineTo(span / 2, 0);
      shape.lineTo(0, height);
      shape.closePath();
      let geo = new THREE.ExtrudeGeometry(shape, {
        depth: length,
        bevelEnabled: false,
      });
      geo.translate(0, -height / 2, -length / 2);
      geo.rotateY(Math.PI / 2);
      return geo;
    }
    case 'extrudedSpline': {
      // [depth, x0,y0, x1,y1, ...] — like extrudedPolygon but the outline is
      // a smooth spline THROUGH the points instead of straight segments
      // (organic silhouettes: soles, leaves, curved panels)
      let depth = Math.abs(d[0] ?? 0.1);
      let pts: any[] = [];
      let flat = d.slice(1);
      for (let i = 0; i + 1 < flat.length; i += 2) {
        pts.push(new THREE.Vector2(flat[i], flat[i + 1]));
      }
      if (pts.length < 3) {
        pts = [
          new THREE.Vector2(0, 0.5),
          new THREE.Vector2(-0.45, -0.35),
          new THREE.Vector2(0.45, -0.35),
        ];
      }
      let shape = new THREE.Shape();
      shape.moveTo(pts[0].x, pts[0].y);
      shape.splineThru(pts.slice(1).concat([pts[0]]));
      let geo = new THREE.ExtrudeGeometry(shape, {
        depth,
        bevelEnabled: false,
        curveSegments: 24,
      });
      geo.translate(0, 0, -depth / 2);
      return geo;
    }
    case 'extrudedPolygon': {
      // [depth, x0,y0, x1,y1, ...] — polygon in the XY plane (faces +Z), centered
      let depth = Math.abs(d[0] ?? 0.1);
      let shape = new THREE.Shape();
      let pts = d.slice(1);
      if (pts.length >= 6) {
        shape.moveTo(pts[0], pts[1]);
        for (let i = 2; i + 1 < pts.length; i += 2) {
          shape.lineTo(pts[i], pts[i + 1]);
        }
      } else {
        shape.moveTo(0, 0.5);
        shape.lineTo(-0.45, -0.35);
        shape.lineTo(0.45, -0.35);
      }
      let geo = new THREE.ExtrudeGeometry(shape, {
        depth,
        bevelEnabled: false,
        curveSegments: 12,
      });
      geo.translate(0, 0, -depth / 2);
      return geo;
    }
    case 'capsule':
      // [radius, cylinderLength]
      return new THREE.CapsuleGeometry(
        d[0] ?? 0.3,
        d[1] ?? 0.6,
        12,
        Math.max(6, Math.round(d[2] ?? 32)),
      );
    case 'hemisphere':
      // [radius] — dome opening downward
      return new THREE.SphereGeometry(
        d[0] ?? 0.5,
        Math.max(3, Math.round(d[1] ?? 32)),
        Math.max(2, Math.round(d[2] ?? 16)),
        0,
        Math.PI * 2,
        0,
        Math.PI / 2,
      );
    case 'cylinder':
      return new THREE.CylinderGeometry(
        d[0] ?? 0.5,
        d[1] ?? d[0] ?? 0.5,
        d[2] ?? 1,
        Math.max(3, Math.round(d[3] ?? 48)),
      );
    case 'sphere':
      return new THREE.SphereGeometry(
        d[0] ?? 0.5,
        Math.max(3, Math.round(d[1] ?? 48)),
        Math.max(2, Math.round(d[2] ?? 32)),
      );
    case 'cone': {
      let segments = Math.max(3, Math.round(d[2] ?? 24));
      let geo = new THREE.ConeGeometry(d[0] ?? 0.5, d[1] ?? 1, segments);
      // a 4-segment cone is the hip-roof/spire pyramid. Bake the 45°
      // square-up into the GEOMETRY so its edges are axis-aligned out of the
      // box: node-level non-uniform scale (roof footprints) then works
      // without the scale-before-rotation skew (three.js composes T·R·S, so
      // scaling a node that is also rotated shears the pyramid).
      if (segments === 4) {
        geo.rotateY(Math.PI / 4);
      }
      return geo;
    }
    case 'torus':
      return new THREE.TorusGeometry(
        d[0] ?? 0.5,
        d[1] ?? 0.15,
        Math.max(3, Math.round(d[2] ?? 16)),
        Math.max(3, Math.round(d[3] ?? 48)),
      );
    case 'plane':
      return new THREE.PlaneGeometry(d[0] ?? 1, d[1] ?? 1);
    case 'disc':
      // [radius] — flat circle facing +Z
      return new THREE.CircleGeometry(d[0] ?? 0.5, 48);
    case 'rock':
      // [radius, detail?] — faceted low-poly blob
      return new THREE.IcosahedronGeometry(
        d[0] ?? 0.5,
        Math.min(2, Math.max(0, Math.round(d[1] ?? 1))),
      );
    case 'blob': {
      // [radius, bumpiness, seed?, detail?] — smooth freeform mass: a sphere
      // displaced along its normals by seeded low-frequency noise. The
      // "mesh generation" half of the hybrid pipeline: organic parts
      // (cushions, plush bodies, bread, stones) get a sculptable dense mesh
      // instead of a primitive union, while staying pure spec data.
      let r = Math.abs(d[0] ?? 0.5);
      let amp = Math.min(Math.abs(d[1] ?? 0.15) * r, r * 0.6);
      let seed = Math.max(1, Math.round(Math.abs(d[2] ?? 1)));
      let detail = Math.min(96, Math.max(16, Math.round(d[3] ?? 48)));
      let geo = new THREE.SphereGeometry(r, detail, detail);
      let rand = mulberry32(seed);
      // a small bank of random 3D sinusoids sums into smooth, seed-stable
      // pseudo-noise — no external noise lib needed
      let waves = Array.from({ length: 6 }, () => ({
        fx: (0.8 + rand() * 2.2) / r,
        fy: (0.8 + rand() * 2.2) / r,
        fz: (0.8 + rand() * 2.2) / r,
        px: rand() * Math.PI * 2,
        py: rand() * Math.PI * 2,
        pz: rand() * Math.PI * 2,
        w: 0.4 + rand() * 0.6,
      }));
      let totalW = waves.reduce((s, v) => s + v.w, 0);
      let pos = geo.attributes.position;
      for (let i = 0; i < pos.count; i++) {
        let x = pos.getX(i);
        let y = pos.getY(i);
        let z = pos.getZ(i);
        let n = 0;
        for (let v of waves) {
          n +=
            v.w *
            Math.sin(v.fx * x + v.px) *
            Math.sin(v.fy * y + v.py) *
            Math.sin(v.fz * z + v.pz);
        }
        // displace along the radial direction (= the sphere normal, but
        // position-derived so seam/pole duplicate vertices stay welded)
        let len = Math.sqrt(x * x + y * y + z * z) || 1;
        let disp = (n / totalW) * amp;
        pos.setXYZ(
          i,
          x + (x / len) * disp,
          y + (y / len) * disp,
          z + (z / len) * disp,
        );
      }
      geo.computeVertexNormals();
      return geo;
    }
    case 'tube': {
      // [radius, x0,y0,z0, x1,y1,z1, ...] — smooth tube swept along a 3D
      // curve through the points (laces, cables, hoses, curved handles)
      let radius = Math.abs(d[0] ?? 0.05);
      let pts: any[] = [];
      for (let i = 1; i + 2 < d.length + 1 && i + 2 <= d.length; i += 3) {
        pts.push(new THREE.Vector3(d[i], d[i + 1], d[i + 2]));
      }
      if (pts.length < 2) {
        pts = [new THREE.Vector3(-0.5, 0, 0), new THREE.Vector3(0.5, 0, 0)];
      }
      let curve = new THREE.CatmullRomCurve3(pts);
      return new THREE.TubeGeometry(curve, 64, radius, 12, false);
    }
    case 'lathe': {
      // dimensions is a flat [x0,y0, x1,y1, ...] profile polyline
      let points: any[] = [];
      for (let i = 0; i + 1 < d.length; i += 2) {
        points.push(new THREE.Vector2(Math.max(0, d[i]), d[i + 1]));
      }
      if (points.length < 2) {
        points = [
          new THREE.Vector2(0, -0.5),
          new THREE.Vector2(0.5, 0),
          new THREE.Vector2(0, 0.5),
        ];
      }
      return new THREE.LatheGeometry(points, 64);
    }
    default:
      return null; // 'group' and unknown kinds carry no geometry
  }
}

export interface BuildOptions {
  // unlit: exact-color MeshBasicMaterial rendering with tone mapping bypassed.
  // Used for flat-graphic inputs (logos, signs) where graphic fidelity beats
  // PBR shading — lit rendering washes saturated artwork colors out, which
  // also poisons the render-vs-reference refine loop into "fixing" colors
  // that were already correct.
  unlit?: boolean;
}

export function buildModel(
  THREE: any,
  nodes: SculptNodeData[],
  materials: SculptMaterialData[],
  options?: BuildOptions,
): BuiltModel {
  let root = new THREE.Group();
  root.name = 'sculpt-root';
  let unlit = options?.unlit ?? false;

  let materialCache = new Map<string, any>();
  let defaultMaterial = unlit
    ? new THREE.MeshBasicMaterial({ color: 0x8a8f9c, toneMapped: false })
    : new THREE.MeshStandardMaterial({
        color: 0x8a8f9c,
        roughness: 0.55,
        metalness: 0.25,
      });
  for (let m of materials ?? []) {
    if (!m?.materialId) continue;
    let opacity = clamp01(m.opacity, 1);
    if (unlit) {
      materialCache.set(
        m.materialId,
        new THREE.MeshBasicMaterial({
          color: new THREE.Color(m.baseColor || '#8a8f9c'),
          transparent: opacity < 1,
          opacity,
          toneMapped: false,
        }),
      );
      continue;
    }
    let params: any = {
      color: new THREE.Color(m.baseColor || '#8a8f9c'),
      roughness: clamp01(m.roughness, 0.55),
      metalness: clamp01(m.metalness, 0.25),
      emissive: new THREE.Color(m.emissive || '#000000'),
      emissiveIntensity:
        typeof m.emissiveIntensity === 'number'
          ? Math.min(2, Math.max(0, m.emissiveIntensity))
          : 1,
      transparent: opacity < 1,
      opacity,
      // keep environment reflections subtle so dark/saturated albedos stay
      // faithful — full-strength IBL washes them toward the room color
      envMapIntensity: 0.35,
    };
    // procedural surface finish (War-Hauler technique): the painted canvas
    // doubles as color map AND roughnessMap so weathering reads as texture
    if (m.finish) {
      let tex = makeFinishTexture(
        THREE,
        m.finish,
        m.materialId,
        m.baseColor || undefined,
      );
      if (tex && (m.finish === 'tread' || m.finish === 'knurl')) {
        // tread reads as RELIEF, not paint: bump the surface and keep the
        // tire's own color (the War-Hauler makeRubber technique)
        params.bumpMap = tex;
        params.bumpScale = 0.02;
      } else if (tex) {
        params.map = tex;
        params.roughnessMap = tex;
        // hazard/camo carry their colors in the map itself; tread and the
        // weathering finishes multiply with the material's own baseColor
        if (
          m.finish === 'hazard' ||
          m.finish === 'camo' ||
          m.finish === 'louver'
        ) {
          params.color = new THREE.Color('#ffffff');
        }
      }
    }
    let usePhysical =
      typeof m.clearcoat === 'number' || typeof m.sheen === 'number';
    if (usePhysical) {
      if (typeof m.clearcoat === 'number') {
        params.clearcoat = clamp01(m.clearcoat, 0);
        // glass-like surfaces (high clearcoat + low roughness) live on
        // their specular highlights: a tight coat and a strong env
        // reflection — the default 0.35 env intensity reads as matte paint
        let glassy = params.clearcoat >= 0.8 && (params.roughness ?? 1) <= 0.2;
        params.clearcoatRoughness = glassy ? 0.08 : 0.3;
        if (glassy) params.envMapIntensity = 1.2;
      }
      if (typeof m.sheen === 'number') {
        params.sheen = clamp01(m.sheen, 0);
      }
    }
    materialCache.set(
      m.materialId,
      usePhysical
        ? new THREE.MeshPhysicalMaterial(params)
        : new THREE.MeshStandardMaterial(params),
    );
  }

  let objects = new Map<string, any>();
  let meshes: any[] = [];
  let geometries: any[] = [];
  let decalMaterials: any[] = [];
  let repeatRequests: { nodeId: string; raw: string }[] = [];
  let warnings: string[] = [];
  // async-mounted .glb scenes (meshAsset nodes) — tracked for disposal
  let loadedAssets: any[] = [];

  // resilient material resolution: exact id → normalized id → first defined
  // material → gray default. Every downgrade is recorded so a wrong-looking
  // render always says WHY in the card log instead of failing silently.
  let normalizedCache = new Map<string, any>();
  for (let [id, mat] of materialCache) {
    normalizedCache.set(id.trim().toLowerCase(), mat);
  }
  let firstMaterial = materialCache.values().next().value;
  let warnedIds = new Set<string>();
  let resolveMaterial = (id: string | null | undefined) => {
    if (id) {
      let exact = materialCache.get(id);
      if (exact) return exact;
      let relaxed = normalizedCache.get(id.trim().toLowerCase());
      if (relaxed) {
        if (!warnedIds.has(id)) {
          warnedIds.add(id);
          warnings.push(`material '${id}' matched only case-insensitively`);
        }
        return relaxed;
      }
    }
    if (!warnedIds.has(id ?? '(none)')) {
      warnedIds.add(id ?? '(none)');
      warnings.push(
        `material '${id ?? '(none)'}' is not defined — used ${
          firstMaterial ? 'first material' : 'gray default'
        }`,
      );
    }
    return firstMaterial ?? defaultMaterial;
  };

  let materialColor = (id: string | null | undefined) => {
    let m = (materials ?? []).find((x) => x.materialId === id);
    return m?.baseColor || '#eeeeee';
  };

  for (let node of nodes ?? []) {
    if (!node?.nodeId || objects.has(node.nodeId)) continue;
    let primitive = node.primitive || 'group';
    let obj: any;
    if (primitive === 'glow') {
      obj = buildGlowSprite(
        THREE,
        nums(node.dimensions, []),
        materialColor(node.materialId),
      );
      decalMaterials.push(obj.material);
      obj.name = node.nodeId;
      obj.userData.note = node.note ?? '';
      let [gx, gy, gz] = nums(node.position, [0, 0, 0]);
      obj.position.set(gx ?? 0, gy ?? 0, gz ?? 0);
      objects.set(node.nodeId, obj);
      continue;
    }
    if (primitive === 'curvedDecal') {
      obj = buildCurvedDecal(
        THREE,
        nums(node.dimensions, []),
        node.text || '',
        materialColor(node.materialId),
      );
      decalMaterials.push(obj.material);
      geometries.push(obj.geometry);
      meshes.push(obj);
      obj.name = node.nodeId;
      obj.userData.note = node.note ?? '';
      let [cx, cy, cz] = nums(node.position, [0, 0, 0]);
      let [crx, cry, crz] = nums(node.rotation, [0, 0, 0]);
      let [csx, csy, csz] = nums(node.scale, [1, 1, 1]);
      obj.position.set(cx ?? 0, cy ?? 0, cz ?? 0);
      obj.rotation.set(crx ?? 0, cry ?? 0, crz ?? 0);
      obj.scale.set(csx || 1, csy || 1, csz || 1);
      objects.set(node.nodeId, obj);
      continue;
    }
    if (primitive === 'textDecal') {
      obj = buildTextDecal(
        THREE,
        nums(node.dimensions, []),
        node.text || node.note || '',
        materialColor(node.materialId),
      );
      decalMaterials.push(obj.material);
      geometries.push(obj.geometry);
      meshes.push(obj);
      obj.name = node.nodeId;
      obj.userData.note = node.note ?? '';
      let [tx, ty, tz] = nums(node.position, [0, 0, 0]);
      let [trx, tryy, trz] = nums(node.rotation, [0, 0, 0]);
      obj.position.set(tx ?? 0, ty ?? 0, tz ?? 0);
      obj.rotation.set(trx ?? 0, tryy ?? 0, trz ?? 0);
      objects.set(node.nodeId, obj);
      continue;
    }
    if (primitive === 'meshAsset') {
      // hybrid pipeline: a service-generated (or exported) .glb placed inside
      // the procedural graph. The group mounts instantly; the mesh streams in
      // asynchronously (the viewer renders continuously, so it pops in).
      obj = new THREE.Group();
      obj.name = node.nodeId;
      obj.userData.note = node.note ?? '';
      let [mx, my, mz] = nums(node.position, [0, 0, 0]);
      let [mrx, mry, mrz] = nums(node.rotation, [0, 0, 0]);
      let [msx, msy, msz] = nums(node.scale, [1, 1, 1]);
      obj.position.set(mx ?? 0, my ?? 0, mz ?? 0);
      obj.rotation.set(mrx ?? 0, mry ?? 0, mrz ?? 0);
      obj.scale.set(msx || 1, msy || 1, msz || 1);
      if (node.assetUrl) {
        loadGlbInto(node.assetUrl, obj, loadedAssets).catch(() => {
          warnings.push(`meshAsset '${node.nodeId}' failed to load its .glb`);
        });
      } else {
        warnings.push(`meshAsset '${node.nodeId}' has no assetUrl`);
      }
      objects.set(node.nodeId, obj);
      continue;
    }
    let geometry = buildGeometry(THREE, primitive, nums(node.dimensions, []));
    if (geometry) {
      geometries.push(geometry);
      obj = new THREE.Mesh(geometry, resolveMaterial(node.materialId));
      obj.castShadow = true;
      obj.receiveShadow = true;
      meshes.push(obj);
    } else {
      obj = new THREE.Group();
    }
    obj.name = node.nodeId;
    obj.userData.note = node.note ?? '';
    let [px, py, pz] = nums(node.position, [0, 0, 0]);
    let [rx, ry, rz] = nums(node.rotation, [0, 0, 0]);
    let [sx, sy, sz] = nums(node.scale, [1, 1, 1]);
    obj.position.set(px ?? 0, py ?? 0, pz ?? 0);
    obj.rotation.set(rx ?? 0, ry ?? 0, rz ?? 0);
    obj.scale.set(sx || 1, sy || 1, sz || 1);

    // repetition is expanded AFTER parent linking so group assemblies
    // (e.g. a full wheel) clone with all their children attached
    if (node.repeat) {
      repeatRequests.push({ nodeId: node.nodeId, raw: node.repeat });
    }
    objects.set(node.nodeId, obj);
  }

  // Second pass: parent linkage. Unknown/missing/self parents attach to root.
  for (let node of nodes ?? []) {
    let obj = objects.get(node?.nodeId);
    if (!obj) continue;
    let parent =
      node.parentId && node.parentId !== node.nodeId
        ? objects.get(node.parentId)
        : undefined;
    (parent ?? root).add(obj);
  }

  // Guard against parentId cycles that orphan whole subtrees: anything that
  // did not end up under root gets reattached to root.
  for (let obj of objects.values()) {
    let ancestor = obj.parent;
    while (ancestor && ancestor !== root) ancestor = ancestor.parent;
    if (ancestor !== root) {
      obj.removeFromParent?.();
      root.add(obj);
    }
  }

  // constraint solver (declared joints): each node's attachTo names its
  // structural support. If the authored coordinates leave a gap in ANY
  // direction, translate the part by the minimal vector that brings it into
  // ~0.03 overlap with its support — the lateral cousin of gravity snap
  // (which only ever drops straight down). Runs BEFORE repeat expansion so
  // clones inherit the corrected position.
  {
    root.updateWorldMatrix(true, true);
    let pulled: string[] = [];
    for (let node of nodes ?? []) {
      if (!node?.attachTo) continue;
      let obj = objects.get(node.nodeId);
      let target = objects.get(node.attachTo);
      if (!obj || !target || obj === target) continue;
      // skip supports that are the part's own ancestor group — the bboxes
      // nest, so contact is already guaranteed
      let ancestor = obj.parent;
      let nested = false;
      while (ancestor) {
        if (ancestor === target) {
          nested = true;
          break;
        }
        ancestor = ancestor.parent;
      }
      if (nested) continue;
      let a = new THREE.Box3().setFromObject(obj);
      let b = new THREE.Box3().setFromObject(target);
      if (a.isEmpty() || b.isEmpty()) continue;
      let margin = 0.03;
      let delta = new THREE.Vector3();
      for (let axis of ['x', 'y', 'z'] as const) {
        if (a.min[axis] > b.max[axis]) {
          delta[axis] = b.max[axis] - a.min[axis] + margin;
        } else if (a.max[axis] < b.min[axis]) {
          delta[axis] = b.min[axis] - a.max[axis] + margin;
        }
      }
      if (delta.lengthSq() === 0) continue;
      if (delta.length() > 1.5) {
        // a pull this large means the spec is wrong, not merely loose —
        // leave it for the refine round to fix semantically
        warnings.push(
          `part '${node.nodeId}' is far from its support '${node.attachTo}'`,
        );
        continue;
      }
      let worldPos = obj.getWorldPosition(new THREE.Vector3());
      worldPos.add(delta);
      obj.position.copy(
        obj.parent ? obj.parent.worldToLocal(worldPos) : worldPos,
      );
      obj.updateWorldMatrix(true, true);
      pulled.push(node.nodeId);
    }
    for (let name of pulled.slice(0, 5)) {
      warnings.push(`pulled '${name}' into contact with its support`);
    }
  }

  // expand repetition systems — works for meshes AND group assemblies (a
  // cloned group carries its full subtree, so one wheel becomes an axle set)
  for (let req of repeatRequests) {
    let original = objects.get(req.nodeId);
    if (!original) continue;
    try {
      let rep = JSON.parse(req.raw);
      let count = Math.min(48, Math.max(0, Math.round(rep?.count ?? 0)));
      if (count < 2) continue;
      let parent = original.parent ?? root;
      for (let i = 1; i < count; i++) {
        let clone = original.clone(true);
        clone.name = `${req.nodeId}-${i}`;
        if (rep.mode === 'radial') {
          let radius = rep.radius ?? 0.5;
          let axis = rep.axis === 'x' ? 'x' : rep.axis === 'z' ? 'z' : 'y';
          let angle = (i / count) * Math.PI * 2;
          let ca = Math.cos(angle) * radius;
          let sa = Math.sin(angle) * radius;
          if (axis === 'y') {
            clone.position.set(
              original.position.x + ca,
              original.position.y,
              original.position.z + sa,
            );
            clone.rotation.y = original.rotation.y + angle;
          } else if (axis === 'x') {
            clone.position.set(
              original.position.x,
              original.position.y + ca,
              original.position.z + sa,
            );
            clone.rotation.x = original.rotation.x + angle;
          } else {
            clone.position.set(
              original.position.x + ca,
              original.position.y + sa,
              original.position.z,
            );
            clone.rotation.z = original.rotation.z + angle;
          }
        } else {
          let [ox, oy, oz] = Array.isArray(rep.offset)
            ? rep.offset
            : [0.2, 0, 0];
          clone.position.set(
            original.position.x + ox * i,
            original.position.y + oy * i,
            original.position.z + oz * i,
          );
        }
        parent.add(clone);
        clone.traverse((child: any) => {
          if (child.isMesh) meshes.push(child);
        });
      }
    } catch {
      warnings.push(`repeat on '${req.nodeId}' is not valid JSON`);
    }
  }

  let dispose = () => {
    for (let g of geometries) g.dispose?.();
    for (let m of materialCache.values()) {
      m.map?.dispose?.();
      m.dispose?.();
    }
    for (let m of decalMaterials) {
      m.map?.dispose?.();
      m.dispose?.();
    }
    for (let assetScene of loadedAssets) {
      assetScene.traverse?.((child: any) => {
        child.geometry?.dispose?.();
        if (child.material) {
          for (let mat of Array.isArray(child.material)
            ? child.material
            : [child.material]) {
            mat.map?.dispose?.();
            mat.dispose?.();
          }
        }
      });
    }
    defaultMaterial.dispose();
  };

  // deterministic assembly check: parts whose (slightly expanded) world
  // bounding box touches no other part are floating — exactly the "spare
  // parts" look. The list feeds the refine loop so the model gets machine
  // facts about connectivity instead of having to eyeball it.
  if (meshes.length > 1) {
    root.updateWorldMatrix(true, true);
    let boxes = meshes.map((mesh) => {
      let b = new THREE.Box3().setFromObject(mesh);
      b.expandByScalar(0.03);
      return b;
    });
    let floating: number[] = [];
    for (let i = 0; i < meshes.length; i++) {
      let touches = false;
      for (let j = 0; j < meshes.length; j++) {
        if (i !== j && boxes[i].intersectsBox(boxes[j])) {
          touches = true;
          break;
        }
      }
      if (!touches) floating.push(i);
    }
    // gravity snap: a truly floating part (touches nothing at all) drops
    // straight down onto the nearest surface below it — the highest top face
    // among parts it overlaps in plan (XZ) view — or onto the model's ground
    // level when nothing sits underneath. Parts with any contact are never
    // moved, so overlap-attached details (antennas, handles) stay put.
    let snapped: string[] = [];
    let stillFloating: string[] = [];
    for (let i of floating) {
      let name = meshes[i].name || `part ${i}`;
      let supportTop: number | undefined;
      let groundY: number | undefined;
      for (let j = 0; j < meshes.length; j++) {
        if (j === i || floating.includes(j)) continue;
        groundY =
          groundY === undefined
            ? boxes[j].min.y
            : Math.min(groundY, boxes[j].min.y);
        let overlapsPlan =
          boxes[i].min.x <= boxes[j].max.x &&
          boxes[i].max.x >= boxes[j].min.x &&
          boxes[i].min.z <= boxes[j].max.z &&
          boxes[i].max.z >= boxes[j].min.z;
        if (overlapsPlan && boxes[j].max.y <= boxes[i].min.y) {
          supportTop =
            supportTop === undefined
              ? boxes[j].max.y
              : Math.max(supportTop, boxes[j].max.y);
        }
      }
      let targetY = supportTop ?? groundY;
      let dy = targetY === undefined ? 0 : boxes[i].min.y - targetY;
      // only close a SMALL gap — a part hovering just above its support is
      // an unintended float; a large drop would teleport intentionally
      // elevated parts (balcony rails, signs) onto whatever lies below,
      // which reads far worse than the float. Big gaps stay warnings so the
      // refine round fixes them semantically.
      if (dy > 0 && dy <= 0.35) {
        let worldPos = meshes[i].getWorldPosition(new THREE.Vector3());
        worldPos.y -= dy;
        meshes[i].position.copy(
          meshes[i].parent ? meshes[i].parent.worldToLocal(worldPos) : worldPos,
        );
        boxes[i].translate(new THREE.Vector3(0, -dy, 0));
        snapped.push(name);
      } else {
        stillFloating.push(name);
      }
    }
    root.updateWorldMatrix(true, true);
    for (let name of snapped.slice(0, 5)) {
      warnings.push(`snapped floating part '${name}' down onto its support`);
    }
    for (let name of stillFloating.slice(0, 5)) {
      warnings.push(`part '${name}' is floating — it touches nothing`);
    }
  }

  return { group: root, meshes, nodeCount: objects.size, warnings, dispose };
}

// Normalizes card field data (ComponentNodeField/MaterialSpecField
// instances) into the plain shapes buildModel consumes.
export function nodesFromSpec(spec: any): SculptNodeData[] {
  return (spec?.components ?? []).map((c: any) => ({
    nodeId: c?.nodeId ?? '',
    parentId: c?.parentId,
    primitive: c?.primitive,
    dimensions: c?.dimensions,
    position: c?.position,
    rotation: c?.rotation,
    scale: c?.scale,
    materialId: c?.materialId,
    text: c?.text,
    repeat: c?.repeat,
    assetUrl: c?.assetUrl,
    attachTo: c?.attachTo,
    note: c?.note,
  }));
}

export function materialsFromSpec(spec: any): SculptMaterialData[] {
  return (spec?.materials ?? []).map((m: any) => ({
    materialId: m?.materialId ?? '',
    baseColor: m?.baseColor,
    roughness: m?.roughness,
    metalness: m?.metalness,
    opacity: m?.opacity,
    emissive: m?.emissive,
    emissiveIntensity: m?.emissiveIntensity,
    clearcoat: m?.clearcoat,
    sheen: m?.sheen,
    finish: m?.finish,
  }));
}
