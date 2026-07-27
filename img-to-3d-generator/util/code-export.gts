// Spec → standalone three.js code generator. Translates a SculptSpecField
// into (a) a self-contained .js module defining buildSculpture(THREE) and
// (b) a self-contained .html viewer page (CDN three.js r147 + orbit harness)
// whose realm URL works directly as an iframe src.
//
// The emitted code mirrors util/spec-interpreter.gts construction-for-
// construction (same defaults, same clamps, same post-build passes) so the
// exported model matches what the studio viewport shows. Only the used
// primitives' geometry cases and only the needed helpers are emitted, so the
// file stays readable. Known deliberate gaps, marked with comments in the
// output: meshAsset nodes (dormant feature) are skipped.

import {
  FINISH_PAINTER_SOURCES,
  FINISH_RUNTIME_SOURCES,
  type EmittableFn,
} from './finishes';

// three.js UMD pins — keep in step with util/three-loader.gts
const THREE_CDN =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/build/three.min.js';
const ROUNDED_BOX_CDN =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/geometries/RoundedBoxGeometry.js';
const GLTF_EXPORTER_CDN =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/exporters/GLTFExporter.js';

interface ExportNode {
  nodeId: string;
  parentId?: string | null;
  primitive: string;
  dimensions: number[];
  position: number[];
  rotation: number[];
  scale: number[];
  materialId?: string | null;
  text?: string | null;
  // analysis partPlan name this component belongs to — drives the measured
  // proportion reconciliation (sizing), while textureRef drives artwork crops
  partRef?: string | null;
  // analysis partPlan name whose photo region carries this part's artwork
  textureRef?: string | null;
  // resolved crop URL (the studio crops the reference by the analysis bbox
  // and writes it into the realm before generating code)
  textureUrl?: string | null;
  repeat?: any;
  attachTo?: string | null;
  note?: string | null;
}

interface ExportMaterial {
  materialId: string;
  baseColor?: string | null;
  roughness?: number | null;
  metalness?: number | null;
  opacity?: number | null;
  emissive?: string | null;
  emissiveIntensity?: number | null;
  clearcoat?: number | null;
  sheen?: number | null;
  transmission?: number | null;
  finish?: string | null;
}

function parseNums(raw: any, fallback: number[]): number[] {
  if (Array.isArray(raw)) return raw;
  if (!raw || typeof raw !== 'string') return fallback;
  try {
    let parsed = JSON.parse(raw);
    if (
      Array.isArray(parsed) &&
      parsed.every((n) => typeof n === 'number' && isFinite(n))
    ) {
      return parsed;
    }
  } catch {
    // fall through
  }
  return fallback;
}

function specNodes(spec: any): ExportNode[] {
  return (spec?.components ?? [])
    .filter((c: any) => c?.nodeId)
    .map((c: any) => ({
      nodeId: String(c.nodeId),
      parentId: c.parentId ? String(c.parentId) : null,
      primitive: c.primitive || 'group',
      dimensions: parseNums(c.dimensions, []),
      position: parseNums(c.position, [0, 0, 0]),
      rotation: parseNums(c.rotation, [0, 0, 0]),
      scale: parseNums(c.scale, [1, 1, 1]),
      materialId: c.materialId || null,
      text: c.text || null,
      partRef: c.partRef || null,
      textureRef: c.textureRef || null,
      textureUrl: c.textureUrl || null,
      repeat: safeRepeat(c.repeat),
      attachTo: c.attachTo || null,
      anchor: c.anchor && typeof c.anchor === 'object' ? c.anchor : null,
      grounded: c.grounded === true ? true : null,
      note: c.note || null,
    }));
}

function safeRepeat(raw: any): any {
  if (!raw) return null;
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function specMaterials(spec: any): ExportMaterial[] {
  return (spec?.materials ?? [])
    .filter((m: any) => m?.materialId)
    .map((m: any) => ({
      materialId: String(m.materialId),
      baseColor: m.baseColor || null,
      roughness: numOrNull(m.roughness),
      metalness: numOrNull(m.metalness),
      opacity: numOrNull(m.opacity),
      emissive: m.emissive || null,
      emissiveIntensity: numOrNull(m.emissiveIntensity),
      clearcoat: numOrNull(m.clearcoat),
      sheen: numOrNull(m.sheen),
      transmission: numOrNull(m.transmission),
      finish: m.finish || null,
    }));
}

function numOrNull(n: any): number | null {
  return typeof n === 'number' && isFinite(n) ? n : null;
}

// compact, deterministic number literal (4 decimals, trimmed)
function fmt(n: number): string {
  if (!isFinite(n)) return '0';
  let s = Number(n.toFixed(4)).toString();
  return s === '-0' ? '0' : s;
}

function fmtArr(a: number[]): string {
  return '[' + a.map(fmt).join(', ') + ']';
}

// single-quoted JS string literal — newlines included (multi-line label
// text otherwise emits an unterminated string and breaks the whole file)
function q(s: string): string {
  return (
    "'" +
    String(s)
      .replace(/\\/g, '\\\\')
      .replace(/'/g, "\\'")
      .replace(/\r/g, '\\r')
      .replace(/\n/g, '\\n')
      .replace(/\u2028/g, '\\u2028')
      .replace(/\u2029/g, '\\u2029') +
    "'"
  );
}

function clamp01(n: number | null | undefined, fallback: number): number {
  if (typeof n !== 'number' || !isFinite(n)) return fallback;
  return Math.min(1, Math.max(0, n));
}

// ---------------------------------------------------------------------------
// material emission — same parameter derivation as the interpreter
// ---------------------------------------------------------------------------

function emitMaterials(materials: ExportMaterial[], unlit: boolean): string[] {
  let lines: string[] = ['  // ===== materials ====='];
  lines.push('  var MATERIALS = {};');
  for (let m of materials) {
    let opacity = clamp01(m.opacity, 1);
    if (unlit) {
      let params = [
        `color: new THREE.Color(${q(m.baseColor || '#8a8f9c')})`,
        ...(opacity < 1
          ? ['transparent: true', `opacity: ${fmt(opacity)}`]
          : []),
        'toneMapped: false',
      ];
      lines.push(
        `  MATERIALS[${q(m.materialId)}] = new THREE.MeshBasicMaterial({ ${params.join(', ')} });`,
      );
      continue;
    }
    let params: string[] = [
      `color: new THREE.Color(${q(m.baseColor || '#8a8f9c')})`,
      `roughness: ${fmt(clamp01(m.roughness, 0.55))}`,
      `metalness: ${fmt(clamp01(m.metalness, 0.25))}`,
    ];
    if (m.emissive && m.emissive !== '#000000') {
      params.push(`emissive: new THREE.Color(${q(m.emissive)})`);
      params.push(
        `emissiveIntensity: ${fmt(
          typeof m.emissiveIntensity === 'number'
            ? Math.min(2, Math.max(0, m.emissiveIntensity))
            : 1,
        )}`,
      );
    }
    if (opacity < 1) {
      params.push('transparent: true', `opacity: ${fmt(opacity)}`);
    }
    let envIntensity = 0.35;
    let usePhysical =
      typeof m.clearcoat === 'number' ||
      typeof m.sheen === 'number' ||
      typeof m.transmission === 'number';
    if (usePhysical) {
      if (typeof m.transmission === 'number') {
        params.push(
          `transmission: ${fmt(clamp01(m.transmission, 0))}`,
          'ior: 1.5',
          'thickness: 0.05',
        );
        envIntensity = Math.max(envIntensity, 1);
      }
      if (typeof m.clearcoat === 'number') {
        let clearcoat = clamp01(m.clearcoat, 0);
        let roughness = clamp01(m.roughness, 0.55);
        let glassy = clearcoat >= 0.8 && roughness <= 0.2;
        params.push(
          `clearcoat: ${fmt(clearcoat)}`,
          `clearcoatRoughness: ${glassy ? '0.08' : '0.3'}`,
        );
        if (glassy) envIntensity = 1.2;
      }
      if (typeof m.sheen === 'number') {
        params.push(`sheen: ${fmt(clamp01(m.sheen, 0))}`);
      }
    }
    params.push(`envMapIntensity: ${fmt(envIntensity)}`);
    let ctor = usePhysical ? 'MeshPhysicalMaterial' : 'MeshStandardMaterial';
    lines.push(
      `  MATERIALS[${q(m.materialId)}] = new THREE.${ctor}({ ${params.join(', ')} });`,
    );
    // procedural finish, mirroring the studio interpreter exactly: the painted
    // canvas serves as colour map AND roughnessMap, except for tread/knurl
    // which are RELIEF and go to bumpMap so the material keeps its own colour.
    // hazard/camo/louver carry their colours inside the map, so the material's
    // colour is neutralised to white and the map is not tinted by it.
    if (m.finish && FINISH_PAINTER_SOURCES[m.finish]) {
      let id = q(m.materialId);
      let finish = q(m.finish);
      let seedColor = m.baseColor ? q(m.baseColor) : "'#7a7f5a'";
      lines.push(
        `  (function () {`,
        `    var tex = makeFinishTexture(THREE, ${finish}, ${id}, ${seedColor});`,
        `    if (!tex) return;`,
        `    var mat = MATERIALS[${id}];`,
        m.finish === 'tread' || m.finish === 'knurl'
          ? `    mat.bumpMap = tex; mat.bumpScale = 0.02;`
          : `    mat.map = tex; mat.roughnessMap = tex;` +
              (m.finish === 'hazard' ||
              m.finish === 'camo' ||
              m.finish === 'louver'
                ? `\n    mat.color = new THREE.Color('#ffffff');`
                : ''),
        `    mat.needsUpdate = true;`,
        `  })();`,
      );
    }
  }
  lines.push(
    unlit
      ? '  var FALLBACK_MATERIAL = new THREE.MeshBasicMaterial({ color: 0x8a8f9c, toneMapped: false });'
      : '  var FALLBACK_MATERIAL = new THREE.MeshStandardMaterial({ color: 0x8a8f9c, roughness: 0.55, metalness: 0.25 });',
  );
  return lines;
}

// ---------------------------------------------------------------------------
// geometry cases — the interpreter's buildGeometry, emitted per used primitive
// ---------------------------------------------------------------------------

const GEOMETRY_CASES: Record<string, string> = {
  box: `    case 'box':
      return new THREE.BoxGeometry(d[0] ?? 1, d[1] ?? 1, d[2] ?? 1);`,
  roundedBox: `    case 'roundedBox': {
      // [w, h, d, cornerRadius?, bevel?] — needs the RoundedBoxGeometry
      // add-on; falls back to an extruded rounded-rect slab without it
      var w = d[0] ?? 1, h = d[1] ?? 0.3, dep = d[2] ?? 1;
      var r = Math.min(Math.abs(d[3] ?? 0.1), Math.min(w, dep) / 2 - 0.001);
      if (THREE.RoundedBoxGeometry) {
        var radius = Math.min(r, Math.min(w, h, dep) / 2 - 0.001);
        return new THREE.RoundedBoxGeometry(w, h, dep, 3, Math.max(0.01, radius));
      }
      var bevel = Math.min(Math.abs(d[4] ?? 0.02), h / 3);
      var geo = new THREE.ExtrudeGeometry(roundedRectShape(w, dep, r), {
        depth: Math.max(h - bevel * 2, 0.001), bevelEnabled: bevel > 0,
        bevelThickness: bevel, bevelSize: bevel, bevelSegments: 3, curveSegments: 24,
      });
      geo.rotateX(-Math.PI / 2);
      geo.translate(0, bevel - h / 2, 0);
      return geo;
    }`,
  roundedPlate: `    case 'roundedPlate': {
      // [w, h, depth, cornerRadius?] — rounded-rect plate facing +Z, centered
      var w = d[0] ?? 2, h = d[1] ?? 2, dep = Math.abs(d[2] ?? 0.1);
      var r = Math.min(Math.abs(d[3] ?? 0.2), Math.min(w, h) / 2 - 0.001);
      var geo = new THREE.ExtrudeGeometry(roundedRectShape(w, h, r), {
        depth: dep, bevelEnabled: false, curveSegments: 24,
      });
      geo.translate(0, 0, -dep / 2);
      return geo;
    }`,
  flatRing: `    case 'flatRing': {
      // [outerRx, outerRy, ringWidth, depth] — flat elliptical ring, facing +Z
      var orx = Math.abs(d[0] ?? 0.5), ory = Math.abs(d[1] ?? orx);
      var width = Math.min(Math.abs(d[2] ?? 0.12), Math.min(orx, ory) - 0.01);
      var depth = Math.abs(d[3] ?? 0.08);
      var shape = new THREE.Shape();
      shape.absellipse(0, 0, orx, ory, 0, Math.PI * 2, false, 0);
      var hole = new THREE.Path();
      hole.absellipse(0, 0, orx - width, ory - width, 0, Math.PI * 2, true, 0);
      shape.holes.push(hole);
      var geo = new THREE.ExtrudeGeometry(shape, { depth: depth, bevelEnabled: false, curveSegments: 32 });
      geo.translate(0, 0, -depth / 2);
      return geo;
    }`,
  arch: `    case 'arch': {
      // [outerR, ringWidth, depth, sweepDeg?] — partial ring spanning the top
      var outer = Math.abs(d[0] ?? 0.6);
      var width = Math.min(Math.abs(d[1] ?? 0.15), outer - 0.01);
      var depth = Math.abs(d[2] ?? 0.3);
      var sweep = (Math.min(340, Math.max(20, d[3] ?? 180)) * Math.PI) / 180;
      var start = Math.PI / 2 + sweep / 2, end = Math.PI / 2 - sweep / 2;
      var inner = outer - width;
      var shape = new THREE.Shape();
      shape.absarc(0, 0, outer, start, end, true);
      shape.lineTo(Math.cos(end) * inner, Math.sin(end) * inner);
      shape.absarc(0, 0, inner, end, start, false);
      shape.closePath();
      var geo = new THREE.ExtrudeGeometry(shape, { depth: depth, bevelEnabled: false, curveSegments: 32 });
      geo.translate(0, 0, -depth / 2);
      return geo;
    }`,
  prism: `    case 'prism': {
      // [lengthAlongRidge, span, height] — triangular prism, ridge along X
      var length = Math.abs(d[0] ?? 1.5), span = Math.abs(d[1] ?? 1), height = Math.abs(d[2] ?? 0.6);
      var shape = new THREE.Shape();
      shape.moveTo(-span / 2, 0);
      shape.lineTo(span / 2, 0);
      shape.lineTo(0, height);
      shape.closePath();
      var geo = new THREE.ExtrudeGeometry(shape, { depth: length, bevelEnabled: false });
      geo.translate(0, -height / 2, -length / 2);
      geo.rotateY(Math.PI / 2);
      return geo;
    }`,
  extrudedSpline: `    case 'extrudedSpline': {
      // [depth, x0,y0, x1,y1, ...] — smooth spline through the outline points
      var depth = Math.abs(d[0] ?? 0.1);
      var pts = [];
      var flat = d.slice(1);
      for (var i = 0; i + 1 < flat.length; i += 2) pts.push(new THREE.Vector2(flat[i], flat[i + 1]));
      if (pts.length < 3) pts = [new THREE.Vector2(0, 0.5), new THREE.Vector2(-0.45, -0.35), new THREE.Vector2(0.45, -0.35)];
      var shape = new THREE.Shape();
      shape.moveTo(pts[0].x, pts[0].y);
      shape.splineThru(pts.slice(1).concat([pts[0]]));
      var geo = new THREE.ExtrudeGeometry(shape, { depth: depth, bevelEnabled: false, curveSegments: 24 });
      geo.translate(0, 0, -depth / 2);
      return geo;
    }`,
  extrudedPolygon: `    case 'extrudedPolygon': {
      // [depth, x0,y0, x1,y1, ...] — polygon in the XY plane, facing +Z
      var depth = Math.abs(d[0] ?? 0.1);
      var shape = new THREE.Shape();
      var pts = d.slice(1);
      if (pts.length >= 6) {
        shape.moveTo(pts[0], pts[1]);
        for (var i = 2; i + 1 < pts.length; i += 2) shape.lineTo(pts[i], pts[i + 1]);
      } else {
        shape.moveTo(0, 0.5);
        shape.lineTo(-0.45, -0.35);
        shape.lineTo(0.45, -0.35);
      }
      var geo = new THREE.ExtrudeGeometry(shape, { depth: depth, bevelEnabled: false, curveSegments: 12 });
      geo.translate(0, 0, -depth / 2);
      return geo;
    }`,
  capsule: `    case 'capsule':
      // [radius, cylinderLength]
      return new THREE.CapsuleGeometry(d[0] ?? 0.3, d[1] ?? 0.6, 12, Math.max(6, Math.round(d[2] ?? 32)));`,
  hemisphere: `    case 'hemisphere':
      // [radius] — dome opening downward
      return new THREE.SphereGeometry(
        d[0] ?? 0.5, Math.max(3, Math.round(d[1] ?? 32)), Math.max(2, Math.round(d[2] ?? 16)),
        0, Math.PI * 2, 0, Math.PI / 2);`,
  cylinder: `    case 'cylinder':
      return new THREE.CylinderGeometry(
        d[0] ?? 0.5, d[1] ?? d[0] ?? 0.5, d[2] ?? 1, Math.max(3, Math.round(d[3] ?? 48)));`,
  sphere: `    case 'sphere':
      return new THREE.SphereGeometry(
        d[0] ?? 0.5, Math.max(3, Math.round(d[1] ?? 48)), Math.max(2, Math.round(d[2] ?? 32)));`,
  cone: `    case 'cone': {
      var segments = Math.max(3, Math.round(d[2] ?? 24));
      var geo = new THREE.ConeGeometry(d[0] ?? 0.5, d[1] ?? 1, segments);
      // 4 segments = hip-roof/spire pyramid: bake the 45° square-up into the
      // geometry so node-level non-uniform scale doesn't shear it
      if (segments === 4) geo.rotateY(Math.PI / 4);
      return geo;
    }`,
  torus: `    case 'torus':
      // [radius,tube] — NATIVE three.js orientation: the ring lies in the XY
      // plane, axis along +Z, standing upright. A collar around an upright body
      // is rotation [-1.5708, 0, 0]; a wheel hub facing sideways is [0, 1.5708, 0]
      return new THREE.TorusGeometry(
        d[0] ?? 0.5, d[1] ?? 0.15, Math.max(3, Math.round(d[2] ?? 16)), Math.max(3, Math.round(d[3] ?? 48)));`,
  plane: `    case 'plane':
      return new THREE.PlaneGeometry(d[0] ?? 1, d[1] ?? 1);`,
  disc: `    case 'disc':
      // [radius] — flat circle facing +Z
      return new THREE.CircleGeometry(d[0] ?? 0.5, 48);`,
  rock: `    case 'rock':
      // [radius, detail?] — faceted low-poly blob
      return new THREE.IcosahedronGeometry(d[0] ?? 0.5, Math.min(2, Math.max(0, Math.round(d[1] ?? 1))));`,
  blob: `    case 'blob': {
      // [radius, bumpiness, seed?, detail?] — sphere displaced radially by
      // seeded pseudo-noise (sum of random 3D sinusoids)
      var r = Math.abs(d[0] ?? 0.5);
      var amp = Math.min(Math.abs(d[1] ?? 0.15) * r, r * 0.6);
      var seed = Math.max(1, Math.round(Math.abs(d[2] ?? 1)));
      var detail = Math.min(96, Math.max(16, Math.round(d[3] ?? 48)));
      var geo = new THREE.SphereGeometry(r, detail, detail);
      var rand = mulberry32(seed);
      var waves = [];
      for (var wi = 0; wi < 6; wi++) {
        waves.push({
          fx: (0.8 + rand() * 2.2) / r, fy: (0.8 + rand() * 2.2) / r, fz: (0.8 + rand() * 2.2) / r,
          px: rand() * Math.PI * 2, py: rand() * Math.PI * 2, pz: rand() * Math.PI * 2,
          w: 0.4 + rand() * 0.6,
        });
      }
      var totalW = waves.reduce(function (s, v) { return s + v.w; }, 0);
      var pos = geo.attributes.position;
      for (var i = 0; i < pos.count; i++) {
        var x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
        var n = 0;
        for (var vi = 0; vi < waves.length; vi++) {
          var v = waves[vi];
          n += v.w * Math.sin(v.fx * x + v.px) * Math.sin(v.fy * y + v.py) * Math.sin(v.fz * z + v.pz);
        }
        var len = Math.sqrt(x * x + y * y + z * z) || 1;
        var disp = (n / totalW) * amp;
        pos.setXYZ(i, x + (x / len) * disp, y + (y / len) * disp, z + (z / len) * disp);
      }
      geo.computeVertexNormals();
      return geo;
    }`,
  tube: `    case 'tube': {
      // [radius, x0,y0,z0, x1,y1,z1, ...] — tube swept along a 3D curve
      var radius = Math.abs(d[0] ?? 0.05);
      var pts = [];
      for (var i = 1; i + 2 <= d.length; i += 3) pts.push(new THREE.Vector3(d[i], d[i + 1], d[i + 2]));
      if (pts.length < 2) pts = [new THREE.Vector3(-0.5, 0, 0), new THREE.Vector3(0.5, 0, 0)];
      return new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 64, radius, 12, false);
    }`,
  lathe: `    case 'lathe': {
      // dimensions is a flat [x0,y0, x1,y1, ...] profile polyline
      var points = [];
      for (var i = 0; i + 1 < d.length; i += 2) points.push(new THREE.Vector2(Math.max(0, d[i]), d[i + 1]));
      if (points.length < 2) points = [new THREE.Vector2(0, -0.5), new THREE.Vector2(0.5, 0), new THREE.Vector2(0, 0.5)];
      return new THREE.LatheGeometry(points, 64);
    }`,
};

// primitives whose geometry case relies on a shared helper
const NEEDS_ROUNDED_RECT = new Set(['roundedBox', 'roundedPlate']);
const NEEDS_MULBERRY = new Set(['blob']);

const HELPER_ROUNDED_RECT = `  // rounded-rect outline used by rounded slabs/plates
  function roundedRectShape(len, depth, r) {
    var s = new THREE.Shape();
    var hx = Math.max(len / 2 - r, 0.001), hz = Math.max(depth / 2 - r, 0.001);
    s.absarc(-hx, -hz, r, Math.PI, Math.PI * 1.5);
    s.absarc(hx, -hz, r, Math.PI * 1.5, 0);
    s.absarc(hx, hz, r, 0, Math.PI * 0.5);
    s.absarc(-hx, hz, r, Math.PI * 0.5, Math.PI);
    return s;
  }`;

const HELPER_MULBERRY = `  // deterministic PRNG — keeps blob shapes identical run to run
  function mulberry32(seed) {
    var a = seed >>> 0;
    return function () {
      a |= 0; a = (a + 0x6d2b79f5) | 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }`;

const HELPER_LOAD_TEXTURE = `  // loads a cropped-artwork texture (a realm-hosted webp of the reference's
  // own label/logo region) for decals that superimpose the REAL artwork
  function loadDecalTexture(url) {
    var loader = new THREE.TextureLoader();
    loader.setCrossOrigin('anonymous');
    var tex = loader.load(url);
    tex.encoding = THREE.sRGBEncoding;
    tex.anisotropy = 8;
    return tex;
  }`;

const HELPER_TEXT_DECAL = `  // flat label plane: superimposes the cropped reference artwork when a
  // texture is given, else canvas-paints the text
  function buildTextDecal(d, text, color, textureUrl) {
    var w = d[0] ?? 0.8, h = d[1] ?? 0.25;
    if (textureUrl) {
      var material = new THREE.MeshBasicMaterial({
        map: loadDecalTexture(textureUrl),
        polygonOffset: true, polygonOffsetFactor: -4, toneMapped: false,
      });
      return new THREE.Mesh(new THREE.PlaneGeometry(w, h), material);
    }
    var canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = Math.max(64, Math.round((512 * h) / Math.max(w, 0.001)));
    var ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = color;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    var fontSize = Math.floor(canvas.height * 0.62);
    ctx.font = '700 ' + fontSize + 'px Arial, sans-serif';
    while (fontSize > 8 && ctx.measureText(text).width > canvas.width * 0.94) {
      fontSize -= 4;
      ctx.font = '700 ' + fontSize + 'px Arial, sans-serif';
    }
    ctx.fillText(text, canvas.width / 2, canvas.height / 2);
    var texture = new THREE.CanvasTexture(canvas);
    texture.encoding = THREE.sRGBEncoding;
    texture.anisotropy = 8;
    var material = new THREE.MeshBasicMaterial({
      map: texture, transparent: true, depthWrite: false,
      polygonOffset: true, polygonOffsetFactor: -4, toneMapped: false,
    });
    return new THREE.Mesh(new THREE.PlaneGeometry(w, h), material);
  }`;

const HELPER_CURVED_DECAL = `  // label wrapped around a cylindrical body: superimposes the cropped
  // reference artwork when a texture is given, else canvas-paints the text
  function buildCurvedDecal(d, text, baseColor, textureUrl) {
    var radius = Math.abs(d[0] ?? 0.5), height = Math.abs(d[1] ?? 0.6);
    var arc = (Math.min(Math.max(d[2] ?? 120, 20), 350) * Math.PI) / 180;
    if (textureUrl) {
      var texMaterial = new THREE.MeshStandardMaterial({
        map: loadDecalTexture(textureUrl),
        roughness: 0.6, metalness: 0, side: THREE.DoubleSide,
        polygonOffset: true, polygonOffsetFactor: -2,
      });
      var texGeometry = new THREE.CylinderGeometry(radius, radius, height, 48, 1, true, -arc / 2, arc);
      return new THREE.Mesh(texGeometry, texMaterial);
    }
    var canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = Math.max(64, Math.round((512 * height) / Math.max(radius * arc, 0.001)));
    var ctx = canvas.getContext('2d');
    ctx.fillStyle = baseColor || '#f4f1e8';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    if (text) {
      var hex = (baseColor || '#f4f1e8').replace('#', '');
      var lum = hex.length >= 6
        ? (parseInt(hex.slice(0, 2), 16) * 0.299 + parseInt(hex.slice(2, 4), 16) * 0.587 + parseInt(hex.slice(4, 6), 16) * 0.114) / 255
        : 0.9;
      ctx.fillStyle = lum > 0.5 ? '#20242c' : '#f2f2f2';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      var fontSize = Math.floor(canvas.height * 0.28);
      ctx.font = '700 ' + fontSize + "px Georgia, 'Times New Roman', serif";
      while (fontSize > 8 && ctx.measureText(text).width > canvas.width * 0.82) {
        fontSize -= 4;
        ctx.font = '700 ' + fontSize + "px Georgia, 'Times New Roman', serif";
      }
      ctx.fillText(text, canvas.width / 2, canvas.height / 2);
    }
    var texture = new THREE.CanvasTexture(canvas);
    texture.encoding = THREE.sRGBEncoding;
    texture.anisotropy = 8;
    var material = new THREE.MeshStandardMaterial({
      map: texture, roughness: 0.6, metalness: 0, side: THREE.DoubleSide,
      polygonOffset: true, polygonOffsetFactor: -2,
    });
    var geometry = new THREE.CylinderGeometry(radius, radius, height, 48, 1, true, -arc / 2, arc);
    return new THREE.Mesh(geometry, material);
  }`;

// Procedural finish painters, emitted from their OWN source so the export
// paints the same weathering the studio does. `Function.prototype.toString()`
// hands back the real function text (TypeScript's annotations are already
// compiled away), which means there is no hand-copied duplicate here to drift
// out of sync — unlike the geometry and solver blocks in this file, which do
// mirror the interpreter by hand.
//
// Everything emitted is a function DECLARATION, so it hoists to the top of
// buildSculpture and is callable from the material block above it.
function emitFinishHelpers(finishes: Set<string>): string {
  let needed: EmittableFn[] = [];
  let add = (fn: EmittableFn) => {
    if (!needed.includes(fn)) needed.push(fn);
  };
  for (let fn of FINISH_RUNTIME_SOURCES) add(fn);
  for (let finish of finishes) {
    for (let fn of FINISH_PAINTER_SOURCES[finish] ?? []) add(fn);
  }
  let dispatch = [...finishes]
    .map((f) => {
      let painters = FINISH_PAINTER_SOURCES[f] ?? [];
      let painter = painters[painters.length - 1];
      let args =
        f === 'camo'
          ? "ctx, S, rand, baseColor || '#7a7f5a'"
          : f === 'hazard' || f === 'louver' || f === 'knurl'
            ? 'ctx, S'
            : 'ctx, S, rand';
      return `      case '${f}': ${painter.name}(${args}); break;`;
    })
    .join('\n');
  return [
    '  // procedural surface finishes — the painted canvas doubles as colour and',
    '  // roughness map, which is what makes a surface read as weathered metal',
    '  // instead of plastic. Painter sources are emitted from the studio module,',
    '  // so this is the same paint the studio viewport shows.',
    ...needed.map((fn) => indentSource(String(fn))),
    '  function makeFinishTexture(THREE, finish, seedText, baseColor) {',
    '    var S = 1024;',
    "    var cv = document.createElement('canvas');",
    '    cv.width = cv.height = S;',
    "    var ctx = cv.getContext('2d');",
    '    var rand = mulberry32(seedFrom(seedText));',
    '    switch (finish) {',
    dispatch,
    '      default: return undefined;',
    '    }',
    '    var tex = new THREE.CanvasTexture(cv);',
    '    tex.encoding = THREE.sRGBEncoding;',
    '    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;',
    '    tex.anisotropy = 8;',
    '    return tex;',
    '  }',
  ].join('\n');
}

// two-space indent so emitted sources sit inside buildSculpture like the rest
function indentSource(src: string): string {
  return src
    .split('\n')
    .map((line) => (line.trim() ? `  ${line}` : line))
    .join('\n');
}

const HELPER_GLOW = `  // camera-facing additive glow sprite
  function buildGlowSprite(d, color) {
    var size = d[0] ?? 0.3;
    var cv = document.createElement('canvas');
    cv.width = 128; cv.height = 128;
    var ctx = cv.getContext('2d');
    var g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64);
    g.addColorStop(0, 'rgba(255,255,255,1)');
    g.addColorStop(0.35, 'rgba(255,255,255,0.55)');
    g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 128, 128);
    var tex = new THREE.CanvasTexture(cv);
    var material = new THREE.SpriteMaterial({
      map: tex, color: new THREE.Color(color), transparent: true,
      depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false,
    });
    var sprite = new THREE.Sprite(material);
    sprite.scale.set(size, size, 1);
    return sprite;
  }`;

// assembly plumbing shared by every export: addPart, parent linking,
// attachTo pull, repeat expansion, contact backstop — the interpreter's
// post-build passes in the same order
const ASSEMBLY_RUNTIME = `  // ===== assembly plumbing (mirrors the studio interpreter) =====
  var objects = new Map();
  var meshes = [];
  var parentIds = new Map();
  var attachments = [];
  var repeats = [];
  // true when the spec drives its own heights via "grounded"; the final
  // stand-on-the-ground step defers to it
  var groundedDeclared = false;

  function material(id) {
    if (id && MATERIALS[id]) return MATERIALS[id];
    var first = Object.keys(MATERIALS)[0];
    return first ? MATERIALS[first] : FALLBACK_MATERIAL;
  }

  function addPart(p) {
    if (objects.has(p.id)) return;
    var obj;
    // decal/glow builders are emitted only when the spec uses them — the
    // typeof guards keep this shared runtime valid either way
    if (p.primitive === 'glow' && typeof buildGlowSprite === 'function') {
      obj = buildGlowSprite(p.d || [], p.color || '#eeeeee');
      obj.name = p.id;
      obj.position.set(p.pos[0] || 0, p.pos[1] || 0, p.pos[2] || 0);
      objects.set(p.id, obj);
      parentIds.set(p.id, p.parent || null);
      return;
    }
    if (p.primitive === 'textDecal' && typeof buildTextDecal === 'function') {
      obj = buildTextDecal(p.d || [], p.text || '', p.color || '#eeeeee', p.texture);
      meshes.push(obj);
    } else if (
      p.primitive === 'curvedDecal' &&
      typeof buildCurvedDecal === 'function'
    ) {
      obj = buildCurvedDecal(p.d || [], p.text || '', p.color || '#eeeeee', p.texture);
      meshes.push(obj);
    } else {
      var geometry = buildGeometry(p.primitive, p.d || []);
      if (geometry) {
        obj = new THREE.Mesh(geometry, material(p.mat));
        obj.castShadow = obj.receiveShadow = true;
        meshes.push(obj);
      } else {
        obj = new THREE.Group();
      }
    }
    obj.name = p.id;
    obj.position.set(p.pos[0] || 0, p.pos[1] || 0, p.pos[2] || 0);
    var rot = p.rot || [0, 0, 0];
    var ry = rot[1] || 0;
    // double-correction guard: buildGeometry already squares up a 4-segment
    // cone, so an author-supplied 45° Y rotation stacks to 90° and turns the
    // hip roof back into an overhanging diamond
    var coneSegs = p.primitive === 'cone' ? Math.max(3, Math.round((p.d || [])[2] != null ? (p.d || [])[2] : 24)) : 0;
    if (coneSegs === 4 && ry) {
      var quarter = Math.PI / 2;
      // subtract the spurious 45°, never snap: 45° is exactly halfway to 90°,
      // and resolving it upward would swap the roof's width and depth
      if (Math.abs((((ry % quarter) + quarter) % quarter) - Math.PI / 4) < 0.09) {
        ry -= Math.sign(ry) * (Math.PI / 4);
      }
    }
    obj.rotation.set(rot[0] || 0, ry, rot[2] || 0);
    var scl = p.scl || [1, 1, 1];
    obj.scale.set(scl[0] || 1, scl[1] || 1, scl[2] || 1);
    objects.set(p.id, obj);
    parentIds.set(p.id, p.parent || null);
    if (p.attachTo) attachments.push({ id: p.id, to: p.attachTo, prim: p.primitive });
    if (p.repeat) repeats.push({ id: p.id, rep: p.repeat, to: p.attachTo });
    if (p.grounded) groundedDeclared = true;
  }

  function assemble() {
    // parent linkage — unknown/missing/self parents attach to root
    objects.forEach(function (obj, id) {
      var pid = parentIds.get(id);
      var parent = pid && pid !== id ? objects.get(pid) : undefined;
      (parent || root).add(obj);
    });
    // cycle guard — anything orphaned by a parentId cycle reattaches to root
    objects.forEach(function (obj) {
      var ancestor = obj.parent;
      while (ancestor && ancestor !== root) ancestor = ancestor.parent;
      if (ancestor !== root) {
        if (obj.removeFromParent) obj.removeFromParent();
        root.add(obj);
      }
    });
    // declared joints — pull each part into ~0.03 overlap with its support
    root.updateWorldMatrix(true, true);
    attachments.forEach(function (att) {
      var obj = objects.get(att.id);
      var target = objects.get(att.to);
      if (!obj || !target || obj === target) return;
      var ancestor = obj.parent;
      while (ancestor) {
        if (ancestor === target) return; // nested — contact guaranteed
        ancestor = ancestor.parent;
      }
      var a = new THREE.Box3().setFromObject(obj);
      var b = new THREE.Box3().setFromObject(target);
      if (a.isEmpty() || b.isEmpty()) return;
      var margin = 0.03;
      var delta = new THREE.Vector3();
      ['x', 'y', 'z'].forEach(function (axis) {
        if (a.min[axis] > b.max[axis]) delta[axis] = b.max[axis] - a.min[axis] + margin;
        else if (a.max[axis] < b.min[axis]) delta[axis] = b.min[axis] - a.max[axis] + margin;
      });
      if (delta.lengthSq() === 0 || delta.length() > 1.5) return;
      var worldPos = obj.getWorldPosition(new THREE.Vector3());
      worldPos.add(delta);
      obj.position.copy(obj.parent ? obj.parent.worldToLocal(worldPos) : worldPos);
      obj.updateWorldMatrix(true, true);
    });
    // repeat expansion — one declared part clones into N placed copies
    repeats.forEach(function (req) {
      var original = objects.get(req.id);
      if (!original) return;
      var rep = req.rep;
      var count = Math.min(48, Math.max(0, Math.round(rep.count || 0)));
      if (count < 2) return;
      var parent = original.parent || root;
      var axis = rep.axis === 'x' ? 'x' : rep.axis === 'z' ? 'z' : 'y';
      var basePos = original.position.clone();
      var baseRot = original.rotation.clone();
      // RING CENTER for a radial array: the axis of the part it wraps around.
      // The original's own in-plane position is already a point ON the circle,
      // so adding the radius to it put every clone at twice the radius.
      var center = basePos.clone();
      var host = req.to ? objects.get(req.to) : undefined;
      if (rep.mode === 'radial' && host && host !== original) {
        var hostBox = new THREE.Box3().setFromObject(host);
        if (!hostBox.isEmpty()) {
          var hc = hostBox.getCenter(new THREE.Vector3());
          parent.worldToLocal(hc);
          if (axis === 'y') { center.x = hc.x; center.z = hc.z; }
          else if (axis === 'x') { center.y = hc.y; center.z = hc.z; }
          else { center.x = hc.x; center.y = hc.y; }
        }
      }
      // index 0 is the original itself, so the ring is coherent
      var place = function (obj, i) {
        if (rep.mode === 'radial') {
          var radius = rep.radius != null ? rep.radius : 0.5;
          var angle = (i / count) * Math.PI * 2;
          var ca = Math.cos(angle) * radius, sa = Math.sin(angle) * radius;
          if (axis === 'y') {
            obj.position.set(center.x + ca, center.y, center.z + sa);
            obj.rotation.y = baseRot.y + angle;
          } else if (axis === 'x') {
            obj.position.set(center.x, center.y + ca, center.z + sa);
            obj.rotation.x = baseRot.x + angle;
          } else {
            obj.position.set(center.x + ca, center.y + sa, center.z);
            obj.rotation.z = baseRot.z + angle;
          }
        } else {
          var off = Array.isArray(rep.offset) ? rep.offset : [0.2, 0, 0];
          obj.position.set(basePos.x + off[0] * i, basePos.y + off[1] * i, basePos.z + off[2] * i);
        }
      };
      place(original, 0);
      for (var i = 1; i < count; i++) {
        var clone = original.clone(true);
        clone.name = req.id + '-' + i;
        place(clone, i);
        parent.add(clone);
        clone.traverse(function (child) { if (child.isMesh) meshes.push(child); });
      }
    });
    // contact backstop — a part touching nothing is pulled into ~0.03 overlap
    // with the support it DECLARED, via the minimal per-axis translation
    // (closes gaps in ANY direction, not just straight down). A part with no
    // declared attachTo stays exactly where it was authored: guessing the
    // nearest neighbour used to drag parts the reference never contained onto
    // whatever happened to be closest, welding them into a clump. maxSnap
    // scales with the object (shared with the inset pass below) so a solver can
    // only close an authoring gap, never relocate a part across the model.
    root.updateWorldMatrix(true, true);
    var solverSize = new THREE.Box3().setFromObject(root).getSize(new THREE.Vector3());
    var maxSnap = 0.15 * Math.max(solverSize.x, solverSize.y, solverSize.z, 0.001);
    if (meshes.length > 1) {
      root.updateWorldMatrix(true, true);
      var boxes = meshes.map(function (mesh) {
        var b = new THREE.Box3().setFromObject(mesh);
        b.expandByScalar(0.03);
        return b;
      });
      var floating = [];
      for (var i = 0; i < meshes.length; i++) {
        var touches = false;
        for (var j = 0; j < meshes.length; j++) {
          if (i !== j && boxes[i].intersectsBox(boxes[j])) { touches = true; break; }
        }
        if (!touches) floating.push(i);
      }
      var attachToByName = new Map();
      attachments.forEach(function (att) { attachToByName.set(att.id, att.to); });
      var contactDelta = function (a, b) {
        var margin = 0.03;
        var delta = new THREE.Vector3();
        ['x', 'y', 'z'].forEach(function (axis) {
          if (a.min[axis] > b.max[axis]) delta[axis] = b.max[axis] - a.min[axis] + margin;
          else if (a.max[axis] < b.min[axis]) delta[axis] = b.min[axis] - a.max[axis] + margin;
        });
        return delta;
      };
      floating.forEach(function (i) {
        var name = meshes[i].name || '';
        var baseName = name.replace(/-\\d+$/, '');
        var targetBox;
        // the declared joint is the only snap target
        var attachTo = attachToByName.has(name) ? attachToByName.get(name) : attachToByName.get(baseName);
        var targetObj = attachTo ? objects.get(attachTo) : undefined;
        if (targetObj && targetObj !== meshes[i]) {
          var tb = new THREE.Box3().setFromObject(targetObj);
          if (!tb.isEmpty()) { targetBox = tb; }
        }
        if (!targetBox) return;
        var delta = contactDelta(boxes[i], targetBox);
        var dist = delta.length();
        if (dist === 0 || dist > maxSnap) return;
        var worldPos = meshes[i].getWorldPosition(new THREE.Vector3());
        worldPos.add(delta);
        meshes[i].position.copy(meshes[i].parent ? meshes[i].parent.worldToLocal(worldPos) : worldPos);
        boxes[i].translate(delta);
      });
      root.updateWorldMatrix(true, true);
    }
    // inset thin panels (windows / glass / signs) flush into their wall. The
    // panel's thinnest world axis is its surface normal; using the WALL's
    // thinnest axis moves side windows onto roofs whenever Y is the wall's
    // smallest dimension.
    // rings and bands never qualify: a torus/flatRing/arch encircles its host
    // instead of sitting in one of its faces, and its thinnest axis is the one
    // it wraps around — so insetting slides a collar or a cap rib to the end of
    // the very part it should be banding.
    root.updateWorldMatrix(true, true);
    var NEVER_INSET = ['torus', 'flatRing', 'arch'];
    attachments.forEach(function (att) {
      if (NEVER_INSET.indexOf(att.prim) !== -1) return;
      var obj = objects.get(att.id);
      var wall = objects.get(att.to);
      if (!obj || !wall || obj === wall) return;
      var p = new THREE.Box3().setFromObject(obj);
      var w = new THREE.Box3().setFromObject(wall);
      if (p.isEmpty() || w.isEmpty()) return;
      var pSize = p.getSize(new THREE.Vector3());
      var wSize = w.getSize(new THREE.Vector3());
      var axes = ['x', 'y', 'z'];
      var normal = axes.reduce(function (a, b) { return pSize[b] < pSize[a] ? b : a; });
      var faceAxes = axes.filter(function (a) { return a !== normal; });
      // a panel must be a PLATE in its own right — thickness a small fraction
      // of its own face. Comparing only against the wall let any small part
      // qualify: a screwcap is "thinner" than a bottle on all three axes, so it
      // was flush-mounted to the bottle's SIDE and sat off-axis beside the neck.
      // A roughly square cross-section (caps, knobs, wheels) never qualifies.
      var face = faceAxes.map(function (a) { return pSize[a]; });
      var plateLike = pSize[normal] < 0.3 * Math.min(face[0], face[1]);
      var thin = pSize[normal] < wSize[normal] * 0.6;
      var fits = faceAxes.every(function (a) { return pSize[a] <= wSize[a] * 1.1; });
      if (!plateLike || !thin || !fits) return;
      var pCenter = p.getCenter(new THREE.Vector3());
      var wCenter = w.getCenter(new THREE.Vector3());
      var side = pCenter[normal] >= wCenter[normal] ? 1 : -1;
      var d = side > 0 ? w.max[normal] - p.max[normal] : w.min[normal] - p.min[normal];
      if (Math.abs(d) < 0.001 || Math.abs(d) > maxSnap) return;
      var worldPos = obj.getWorldPosition(new THREE.Vector3());
      worldPos[normal] += d;
      obj.position.copy(obj.parent ? obj.parent.worldToLocal(worldPos) : worldPos);
      obj.updateWorldMatrix(true, true);
    });
    root.updateWorldMatrix(true, true);

    // stand the object on the ground — LAST, once every solver above has
    // finished, and only when the spec never used the "grounded" flag (which has
    // its own drop). The model does not set that flag in practice, so without
    // this an object sits wherever its coordinates landed: sunk into the ground,
    // or floating above its own contact shadow.
    if (!groundedDeclared) {
      var standing = new THREE.Box3();
      for (var si = 0; si < meshes.length; si++) {
        var sm = meshes[si];
        if (/shadow/i.test(sm.name) || sm.isSprite) continue;
        standing.union(new THREE.Box3().setFromObject(sm));
      }
      if (!standing.isEmpty()) {
        var gdy = -standing.min.y;
        var gh = standing.max.y - standing.min.y;
        if (Math.abs(gdy) > 0.02 && gh > 0 && Math.abs(gdy) <= gh) {
          root.position.y += gdy;
          root.updateWorldMatrix(true, true);
        }
      }
    }
  }`;

// ---------------------------------------------------------------------------
// public API
// ---------------------------------------------------------------------------

export interface CodeExportMeta {
  round?: number | null;
  score?: number | null;
}

// the standalone .js module: buildSculpture(THREE) → { group, meshes }
export function generateModelJs(spec: any, meta?: CodeExportMeta): string {
  let nodes = specNodes(spec);
  let materials = specMaterials(spec);
  let unlit = spec?.inputKind === 'flat-graphic';
  let name = spec?.objectName || 'sculpture';

  let usedPrimitives = new Set(nodes.map((n) => n.primitive));
  let colorById = new Map(
    materials.map((m) => [m.materialId, m.baseColor || '#eeeeee']),
  );

  let lines: string[] = [];
  // generated artifact — keep repo linters out of it
  lines.push('/* eslint-disable */');
  lines.push(`// ${name} — procedural three.js model`);
  let provenance = ['generated by Boxel Img-to-3D Studio from its sculpt spec'];
  if (typeof meta?.round === 'number') provenance.push(`round ${meta.round}`);
  if (typeof meta?.score === 'number') provenance.push(`score ${meta.score}`);
  lines.push(`// ${provenance.join(' · ')}`);
  lines.push('//');
  lines.push('// Usage (three.js r0.147):');
  lines.push('//   var built = buildSculpture(THREE);');
  lines.push('//   scene.add(built.group);');
  lines.push('//');
  lines.push(
    '// Every part below is one addPart() call — dimensions, positions and',
  );
  lines.push('// materials are plain numbers you can edit directly.');
  lines.push('');
  lines.push('function buildSculpture(THREE) {');
  lines.push("  'use strict';");
  lines.push('  var root = new THREE.Group();');
  lines.push(`  root.name = ${q(name)};`);
  lines.push('');
  lines.push(...emitMaterials(materials, unlit));
  lines.push('');

  // helpers, only the ones this spec needs
  let helperBlocks: string[] = [];
  if ([...usedPrimitives].some((p) => NEEDS_ROUNDED_RECT.has(p))) {
    helperBlocks.push(HELPER_ROUNDED_RECT);
  }
  if ([...usedPrimitives].some((p) => NEEDS_MULBERRY.has(p))) {
    helperBlocks.push(HELPER_MULBERRY);
  }
  let usesTexturedDecal = nodes.some(
    (n) =>
      n.textureUrl &&
      (n.primitive === 'textDecal' || n.primitive === 'curvedDecal'),
  );
  if (usesTexturedDecal) helperBlocks.push(HELPER_LOAD_TEXTURE);
  if (usedPrimitives.has('textDecal')) helperBlocks.push(HELPER_TEXT_DECAL);
  if (usedPrimitives.has('curvedDecal')) helperBlocks.push(HELPER_CURVED_DECAL);
  if (usedPrimitives.has('glow')) helperBlocks.push(HELPER_GLOW);
  let usedFinishes = new Set(
    materials
      .map((m: any) => String(m?.finish ?? ''))
      .filter((f) => f && FINISH_PAINTER_SOURCES[f]),
  );
  if (usedFinishes.size) helperBlocks.push(emitFinishHelpers(usedFinishes));

  // geometry builder with only the used primitive cases
  let cases = [...usedPrimitives]
    .filter((p) => GEOMETRY_CASES[p])
    .map((p) => GEOMETRY_CASES[p]);
  helperBlocks.push(
    [
      '  // geometry per primitive — same defaults as the studio interpreter',
      '  function buildGeometry(primitive, d) {',
      '    switch (primitive) {',
      ...cases,
      '      default:',
      "        return null; // 'group' carries no geometry",
      '    }',
      '  }',
    ].join('\n'),
  );
  lines.push(helperBlocks.join('\n\n'));
  lines.push('');
  lines.push(ASSEMBLY_RUNTIME);
  lines.push('');
  lines.push('  // ===== parts =====');

  for (let node of nodes) {
    if (node.primitive === 'meshAsset') {
      lines.push(
        `  // (skipped) meshAsset '${node.nodeId}' — external .glb assets are not exported`,
      );
      continue;
    }
    let fields: string[] = [`id: ${q(node.nodeId)}`];
    if (node.parentId) fields.push(`parent: ${q(node.parentId)}`);
    fields.push(`primitive: ${q(node.primitive)}`);
    if (node.dimensions.length) fields.push(`d: ${fmtArr(node.dimensions)}`);
    fields.push(`pos: ${fmtArr(node.position)}`);
    if (node.rotation.some((n) => n !== 0))
      fields.push(`rot: ${fmtArr(node.rotation)}`);
    if (node.scale.some((n) => n !== 1))
      fields.push(`scl: ${fmtArr(node.scale)}`);
    if (
      node.primitive === 'glow' ||
      node.primitive === 'textDecal' ||
      node.primitive === 'curvedDecal'
    ) {
      fields.push(
        `color: ${q(colorById.get(node.materialId ?? '') || '#eeeeee')}`,
      );
      // textDecal falls back to the note as its label (interpreter parity);
      // curvedDecal must NOT — a recipe note painted onto a wine label reads
      // as gibberish text on the model
      let label =
        node.primitive === 'textDecal' ? node.text || node.note : node.text;
      if (label) fields.push(`text: ${q(label)}`);
      if (node.textureUrl) fields.push(`texture: ${q(node.textureUrl)}`);
    } else if (node.materialId) {
      fields.push(`mat: ${q(node.materialId)}`);
    }
    if (node.attachTo) fields.push(`attachTo: ${q(node.attachTo)}`);
    if (node.repeat && typeof node.repeat === 'object') {
      let rep = node.repeat;
      let repFields: string[] = [`count: ${fmt(rep.count ?? 0)}`];
      if (rep.mode) repFields.push(`mode: ${q(rep.mode)}`);
      if (typeof rep.radius === 'number')
        repFields.push(`radius: ${fmt(rep.radius)}`);
      if (rep.axis) repFields.push(`axis: ${q(rep.axis)}`);
      if (Array.isArray(rep.offset))
        repFields.push(`offset: ${fmtArr(rep.offset)}`);
      fields.push(`repeat: { ${repFields.join(', ')} }`);
    }
    let comment = node.note
      ? ` // ${String(node.note).replace(/\n/g, ' ')}`
      : '';
    lines.push(`  addPart({ ${fields.join(', ')} });${comment}`);
  }

  lines.push('');
  lines.push('  assemble();');
  lines.push('  return { group: root, meshes: meshes };');
  lines.push('}');
  lines.push('');
  lines.push(
    '// machine-readable source spec — the studio reads this back to refine or',
    '// regenerate; editing addPart() lines above without updating it is fine',
    '// for one-off tweaks, but regeneration works from this data',
    `var SCULPT_SPEC = ${JSON.stringify(plainSpec(spec))};`,
    '',
    "if (typeof module !== 'undefined') {",
    '  module.exports = { buildSculpture: buildSculpture, SCULPT_SPEC: SCULPT_SPEC };',
    '}',
  );
  lines.push('');
  return lines.join('\n');
}

// the normalized, JSON-safe form of the spec that rides inside the .js file —
// card instances no longer persist the spec, so the file is the carrier
export function plainSpec(spec: any): any {
  return {
    objectName: spec?.objectName || 'sculpture',
    inputKind: spec?.inputKind || 'object',
    objectClass: spec?.objectClass || null,
    complexity: spec?.complexity || null,
    identityFeatures: Array.isArray(spec?.identityFeatures)
      ? [...spec.identityFeatures]
      : [],
    materials: specMaterials(spec),
    components: specNodes(spec).map((n) => ({
      nodeId: n.nodeId,
      parentId: n.parentId,
      primitive: n.primitive,
      dimensions: n.dimensions,
      position: n.position,
      rotation: n.rotation,
      scale: n.scale,
      materialId: n.materialId,
      text: n.text,
      partRef: n.partRef,
      textureRef: n.textureRef,
      textureUrl: n.textureUrl,
      repeat: n.repeat,
      attachTo: n.attachTo,
      note: n.note,
    })),
  };
}

// reads the embedded SCULPT_SPEC back out of a generated model .js file
export function specFromModelJs(code: string): any | null {
  let match = code.match(/^var SCULPT_SPEC = (.*);$/m);
  if (!match) return null;
  try {
    return JSON.parse(match[1]);
  } catch {
    return null;
  }
}

// the SHARED viewer page (one per generator, not per model): reads the model
// .js URL from its ?model= query param, fetches and executes it, and renders
// with the same scene/lights/orbit as the studio viewport. Its realm URL —
// viewer.html?model=<js url> — is the iframe src for every exported model.
// Same-origin embedders (the studio) can also call the window API it exposes:
// captureScreenshot() / captureViews(refCamera) / exportGlb().
export function generateViewerHarnessHtml(bakedModelUrl?: string): string {
  let harness = `(function () {
  // model source, in priority order: inline code (draft builds — the studio
  // measures proportions before persisting anything), a baked-in URL
  // (srcdoc viewport embeds), or the ?model= query param (external iframes)
  if (window.SCULPT_MODEL_INLINE) {
    var inlineFactory = new Function(
      window.SCULPT_MODEL_INLINE + '\\nreturn buildSculpture;',
    );
    start(inlineFactory());
    return;
  }
  var modelUrl =
    window.SCULPT_MODEL_URL ||
    new URLSearchParams(window.location.search).get('model');
  function fail(message) {
    var p = document.createElement('p');
    p.style.cssText = 'color:#9aa0b2;font:14px ui-monospace,monospace;padding:1rem;';
    p.textContent = message;
    document.body.appendChild(p);
  }
  if (!modelUrl) {
    fail('no model — open as viewer.html?model=<model .js URL>');
    return;
  }

  fetch(modelUrl, { headers: { Accept: '*/*' } })
    .then(function (response) {
      if (!response.ok) throw new Error('could not load model (' + response.status + ')');
      return response.text();
    })
    .then(function (code) {
      // the model file declares buildSculpture(THREE); execute it in a plain
      // (non-module) scope and pull the function out
      var factory = new Function(code + '\\nreturn buildSculpture;');
      start(factory());
    })
    .catch(function (e) {
      fail(String((e && e.message) || e));
    });

  function start(buildSculpture) {
  var renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.outputEncoding = THREE.sRGBEncoding;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.0;
  if (THREE.ColorManagement) THREE.ColorManagement.legacyMode = false;
  document.body.appendChild(renderer.domElement);

  var scene = new THREE.Scene();
  scene.background = new THREE.Color('#2b303d');
  scene.fog = new THREE.Fog('#2b303d', 14, 30);

  var camera = new THREE.PerspectiveCamera(38, 1, 0.1, 100);

  // near-neutral three-point light rig
  var key = new THREE.DirectionalLight('#fffaf2', 1.2); key.position.set(4, 6, 5); key.castShadow = true;
  var fill = new THREE.DirectionalLight('#f2f5ff', 0.45); fill.position.set(-5, 2, -2);
  var rim = new THREE.DirectionalLight('#dffbff', 0.25); rim.position.set(0, 4, -6);
  var dome = new THREE.HemisphereLight('#5a6070', '#15161c', 0.6);
  scene.add(key, fill, rim, dome);

  // minimal PMREM environment so metals and glass have something to reflect
  var pmrem = new THREE.PMREMGenerator(renderer);
  var envScene = new THREE.Scene();
  var room = new THREE.Mesh(
    new THREE.BoxGeometry(10, 10, 10),
    new THREE.MeshBasicMaterial({ color: '#444444', side: THREE.BackSide }));
  envScene.add(room);
  [[0, 4.9, 0, 6], [4, 2, 4, 3], [-4, 3, -2, 2]].forEach(function (p) {
    var panel = new THREE.Mesh(
      new THREE.PlaneGeometry(3, 3),
      new THREE.MeshBasicMaterial({ color: new THREE.Color('#ffffff').multiplyScalar(p[3]) }));
    panel.position.set(p[0], p[1], p[2]);
    panel.lookAt(0, 0, 0);
    envScene.add(panel);
  });
  scene.environment = pmrem.fromScene(envScene, 0.04).texture;

  var built = buildSculpture(THREE);
  // normalize into view — same framing as the studio viewport
  var box = new THREE.Box3().setFromObject(built.group);
  var size = box.getSize(new THREE.Vector3());
  var center = box.getCenter(new THREE.Vector3());
  var maxDim = Math.max(size.x, size.y, size.z) || 1;
  var scaleFactor = 2.6 / maxDim;
  built.group.scale.setScalar(scaleFactor);
  built.group.position.set(
    -center.x * scaleFactor, -center.y * scaleFactor, -center.z * scaleFactor);
  scene.add(built.group);

  // staggered pop-in: parts appear one after another, each springing up to
  // its real size (same feel as the studio's original canvas viewport)
  var popStart = performance.now();
  var popDone = false;
  var popParts = built.meshes.map(function (mesh, i) {
    var base = mesh.scale.clone();
    mesh.scale.setScalar(0.0001);
    return { mesh: mesh, base: base, at: popStart + i * 55 };
  });
  function easeOutBack(t) {
    var c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
  }
  function animatePopIn(now) {
    if (popDone) return;
    var allDone = true;
    for (var i = 0; i < popParts.length; i++) {
      var p = popParts[i];
      var t = (now - p.at) / 320;
      if (t < 1) allDone = false;
      if (t < 0) t = 0;
      if (t > 1) t = 1;
      var s = t === 1 ? 1 : easeOutBack(t);
      p.mesh.scale.set(p.base.x * s, p.base.y * s, p.base.z * s);
    }
    popDone = allDone;
  }
  // screenshots must show the finished model, never a mid-animation frame
  function finishPopIn() {
    for (var i = 0; i < popParts.length; i++) {
      popParts[i].mesh.scale.copy(popParts[i].base);
    }
    popDone = true;
  }

  // drag-to-orbit / wheel-to-zoom with idle auto-rotate
  var orbit = { theta: 0.85, phi: 1.12, radius: 6 };
  var dragging = false, lastX = 0, lastY = 0, lastInteraction = 0;
  var el = renderer.domElement;
  el.style.touchAction = 'none';
  el.addEventListener('pointerdown', function (e) {
    dragging = true; lastX = e.clientX; lastY = e.clientY;
    el.setPointerCapture(e.pointerId);
  });
  el.addEventListener('pointermove', function (e) {
    if (!dragging) return;
    orbit.theta -= (e.clientX - lastX) * 0.008;
    orbit.phi = Math.min(2.6, Math.max(0.35, orbit.phi - (e.clientY - lastY) * 0.006));
    lastX = e.clientX; lastY = e.clientY;
    lastInteraction = performance.now();
  });
  el.addEventListener('pointerup', function () { dragging = false; });
  el.addEventListener('wheel', function (e) {
    e.preventDefault();
    orbit.radius = Math.min(22, Math.max(2, orbit.radius + e.deltaY * 0.01));
    lastInteraction = performance.now();
  }, { passive: false });

  function resize() {
    var w = window.innerWidth, h = window.innerHeight;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  window.addEventListener('resize', resize);
  resize();

  function frame(now) {
    animatePopIn(now);
    if (!dragging && now - lastInteraction > 2500) orbit.theta += 0.0032;
    camera.position.set(
      orbit.radius * Math.sin(orbit.phi) * Math.sin(orbit.theta),
      orbit.radius * Math.cos(orbit.phi),
      orbit.radius * Math.sin(orbit.phi) * Math.cos(orbit.theta));
    camera.lookAt(0, 0, 0);
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  function renderAt(theta, phi) {
    camera.position.set(
      orbit.radius * Math.sin(phi) * Math.sin(theta),
      orbit.radius * Math.cos(phi),
      orbit.radius * Math.sin(phi) * Math.cos(theta));
    camera.lookAt(0, 0, 0);
    renderer.render(scene, camera);
  }

  // same-origin embedder API (the studio calls these through contentWindow)
  window.captureScreenshot = function () {
    finishPopIn();
    renderer.render(scene, camera);
    return renderer.domElement.toDataURL('image/webp', 0.9);
  };
  // per-part world bounding boxes — the studio compares these against the
  // analysis bbox targets to auto-correct proportions (no vision call).
  // The root transform below is presentation-only framing; neutralize it
  // while measuring so returned positions use the original spec's units.
  window.measureParts = function () {
    finishPopIn();
    var framedPosition = built.group.position.clone();
    var framedScale = built.group.scale.clone();
    built.group.position.set(0, 0, 0);
    built.group.scale.set(1, 1, 1);
    built.group.updateWorldMatrix(true, true);
    var box = function (object) {
      var b = new THREE.Box3().setFromObject(object);
      return { min: [b.min.x, b.min.y, b.min.z], max: [b.max.x, b.max.y, b.max.z] };
    };
    var measurement = {
      whole: box(built.group),
      parts: built.meshes.map(function (mesh) {
        var b = box(mesh);
        return { name: mesh.name, min: b.min, max: b.max };
      }),
    };
    built.group.position.copy(framedPosition);
    built.group.scale.copy(framedScale);
    built.group.updateWorldMatrix(true, true);
    return measurement;
  };
  window.captureViews = function (refCamera) {
    finishPopIn();
    var views = [
      { label: 'front', theta: 0, phi: 1.35 },
      { label: 'side', theta: Math.PI / 2, phi: 1.35 },
      { label: 'three-quarter', theta: 0.85, phi: 1.12 },
    ];
    if (refCamera && typeof refCamera.azimuthDeg === 'number') {
      views.unshift({
        label: 'reference angle',
        theta: (refCamera.azimuthDeg * Math.PI) / 180,
        phi: Math.PI / 2 - (((refCamera.elevationDeg || 0) * Math.PI) / 180),
      });
    }
    var shots = views.map(function (view) {
      renderAt(view.theta, view.phi);
      return { label: view.label, dataUrl: renderer.domElement.toDataURL('image/webp', 0.9) };
    });
    renderAt(orbit.theta, orbit.phi);
    return shots;
  };
  window.exportGlb = function () {
    return new Promise(function (resolve, reject) {
      function run() {
        new THREE.GLTFExporter().parse(built.group, resolve, reject, { binary: true });
      }
      if (THREE.GLTFExporter) return run();
      var s = document.createElement('script');
      s.src = '${GLTF_EXPORTER_CDN}';
      s.onload = run;
      s.onerror = function () { reject(new Error('could not load GLTFExporter')); };
      document.body.appendChild(s);
    });
  };
  // lasso hit-test: given a screen-space polygon (pixels, viewport coords),
  // raycast a grid of points INSIDE the polygon and take the front-most hit at
  // each — so only the parts actually visible under the lasso are returned
  // (an occluded body behind a lassoed cap is never picked). Drives the
  // studio's inpaint/lasso targeted-edit feature.
  window.pickInRegion = function (poly) {
    finishPopIn();
    built.group.updateWorldMatrix(true, true);
    var w = renderer.domElement.clientWidth || window.innerWidth;
    var h = renderer.domElement.clientHeight || window.innerHeight;
    function inside(px, py) {
      var c = false;
      for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        var xi = poly[i].x, yi = poly[i].y, xj = poly[j].x, yj = poly[j].y;
        if (((yi > py) !== (yj > py)) &&
            (px < (xj - xi) * (py - yi) / (yj - yi) + xi)) c = !c;
      }
      return c;
    }
    var minx = Infinity, miny = Infinity, maxx = -Infinity, maxy = -Infinity;
    for (var p = 0; p < poly.length; p++) {
      if (poly[p].x < minx) minx = poly[p].x;
      if (poly[p].x > maxx) maxx = poly[p].x;
      if (poly[p].y < miny) miny = poly[p].y;
      if (poly[p].y > maxy) maxy = poly[p].y;
    }
    var raycaster = new THREE.Raycaster();
    var ndc = new THREE.Vector2();
    // ~14 samples across the lasso's shorter side, min 4px spacing
    var step = Math.max(4, Math.min(maxx - minx, maxy - miny) / 14);
    var seen = {}, hits = [];
    for (var y = miny; y <= maxy; y += step) {
      for (var x = minx; x <= maxx; x += step) {
        if (!inside(x, y)) continue;
        ndc.set((x / w) * 2 - 1, -(y / h) * 2 + 1);
        raycaster.setFromCamera(ndc, camera);
        var is = raycaster.intersectObjects(built.meshes, true);
        if (!is.length) continue;
        var obj = is[0].object;
        while (obj && !obj.name && obj.parent) obj = obj.parent;
        if (obj && obj.name && !seen[obj.name]) {
          seen[obj.name] = 1;
          hits.push(obj.name);
        }
      }
    }
    return hits;
  };
  window.sculptViewerReady = true;
  try { window.parent.postMessage({ type: 'sculpt-viewer-ready' }, '*'); } catch (e) { /* sandboxed */ }
  }
})();`;

  return [
    '<!doctype html>',
    '<html lang="en">',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<title>Sculpture Viewer</title>',
    '<style>html,body{margin:0;height:100%;background:#2b303d;overflow:hidden}canvas{display:block}</style>',
    '</head>',
    '<body>',
    ...(bakedModelUrl
      ? [
          `<script>window.SCULPT_MODEL_URL = ${JSON.stringify(bakedModelUrl)};</script>`,
        ]
      : []),
    `<script src="${THREE_CDN}"></script>`,
    `<script src="${ROUNDED_BOX_CDN}"></script>`,
    '<script>',
    harness,
    '</script>',
    '</body>',
    '</html>',
    '',
  ].join('\n');
}

// the same harness with the model URL baked in, for use as an iframe's
// `srcdoc` attribute — the browser never requests an .html from the realm,
// so this works regardless of how the realm routes text/html navigations.
// A srcdoc document inherits the embedding page's origin, so the studio can
// still call the harness's window API and the model .js fetch stays
// same-origin.
export function generateViewerSrcdoc(modelUrl: string): string {
  return generateViewerHarnessHtml(modelUrl);
}

// harness with the model CODE embedded directly (no realm file involved) —
// used for draft builds: the studio measures the draft's proportions and
// corrects the spec before any file is written. `token` stands in for the
// model URL so readiness checks work the same as for persisted models.
export function generateViewerSrcdocInline(
  code: string,
  token: string,
): string {
  let html = generateViewerHarnessHtml(token);
  return html.replace(
    '<body>',
    [
      '<body>',
      `<script>window.SCULPT_MODEL_INLINE = ${JSON.stringify(code).replace(/<\//g, '<\\/')};</script>`,
    ].join('\n'),
  );
}
