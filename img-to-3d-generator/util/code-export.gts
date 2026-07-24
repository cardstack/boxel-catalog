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
// output: procedural finish textures render as flat color, and meshAsset
// nodes (dormant feature) are skipped.

// three.js UMD pins — keep in step with util/three-loader.gts
const THREE_CDN =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/build/three.min.js';
const ROUNDED_BOX_CDN =
  'https://cdn.jsdelivr.net/npm/three@0.147.0/examples/js/geometries/RoundedBoxGeometry.js';

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
      repeat: safeRepeat(c.repeat),
      attachTo: c.attachTo || null,
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

// single-quoted JS string literal
function q(s: string): string {
  return "'" + String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'") + "'";
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
    let finishNote = m.finish
      ? ` // finish '${m.finish}' is a procedural canvas texture in the studio — flat color here`
      : '';
    lines.push(
      `  MATERIALS[${q(m.materialId)}] = new THREE.${ctor}({ ${params.join(', ')} });${finishNote}`,
    );
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

const HELPER_TEXT_DECAL = `  // canvas-painted text on a transparent plane
  function buildTextDecal(d, text, color) {
    var w = d[0] ?? 0.8, h = d[1] ?? 0.25;
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

const HELPER_CURVED_DECAL = `  // painted label wrapped around a cylindrical body
  function buildCurvedDecal(d, text, baseColor) {
    var radius = Math.abs(d[0] ?? 0.5), height = Math.abs(d[1] ?? 0.6);
    var arc = (Math.min(Math.max(d[2] ?? 120, 20), 350) * Math.PI) / 180;
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
// attachTo pull, repeat expansion, gravity snap — the interpreter's
// post-build passes in the same order
const ASSEMBLY_RUNTIME = `  // ===== assembly plumbing (mirrors the studio interpreter) =====
  var objects = new Map();
  var meshes = [];
  var parentIds = new Map();
  var attachments = [];
  var repeats = [];

  function material(id) {
    if (id && MATERIALS[id]) return MATERIALS[id];
    var first = Object.keys(MATERIALS)[0];
    return first ? MATERIALS[first] : FALLBACK_MATERIAL;
  }

  function addPart(p) {
    if (objects.has(p.id)) return;
    var obj;
    if (p.primitive === 'glow') {
      obj = buildGlowSprite(p.d || [], p.color || '#eeeeee');
      obj.name = p.id;
      obj.position.set(p.pos[0] || 0, p.pos[1] || 0, p.pos[2] || 0);
      objects.set(p.id, obj);
      parentIds.set(p.id, p.parent || null);
      return;
    }
    if (p.primitive === 'textDecal') {
      obj = buildTextDecal(p.d || [], p.text || '', p.color || '#eeeeee');
      meshes.push(obj);
    } else if (p.primitive === 'curvedDecal') {
      obj = buildCurvedDecal(p.d || [], p.text || '', p.color || '#eeeeee');
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
    obj.rotation.set(rot[0] || 0, rot[1] || 0, rot[2] || 0);
    var scl = p.scl || [1, 1, 1];
    obj.scale.set(scl[0] || 1, scl[1] || 1, scl[2] || 1);
    objects.set(p.id, obj);
    parentIds.set(p.id, p.parent || null);
    if (p.attachTo) attachments.push({ id: p.id, to: p.attachTo });
    if (p.repeat) repeats.push({ id: p.id, rep: p.repeat });
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
      for (var i = 1; i < count; i++) {
        var clone = original.clone(true);
        clone.name = req.id + '-' + i;
        if (rep.mode === 'radial') {
          var radius = rep.radius != null ? rep.radius : 0.5;
          var axis = rep.axis === 'x' ? 'x' : rep.axis === 'z' ? 'z' : 'y';
          var angle = (i / count) * Math.PI * 2;
          var ca = Math.cos(angle) * radius, sa = Math.sin(angle) * radius;
          if (axis === 'y') {
            clone.position.set(original.position.x + ca, original.position.y, original.position.z + sa);
            clone.rotation.y = original.rotation.y + angle;
          } else if (axis === 'x') {
            clone.position.set(original.position.x, original.position.y + ca, original.position.z + sa);
            clone.rotation.x = original.rotation.x + angle;
          } else {
            clone.position.set(original.position.x + ca, original.position.y + sa, original.position.z);
            clone.rotation.z = original.rotation.z + angle;
          }
        } else {
          var off = Array.isArray(rep.offset) ? rep.offset : [0.2, 0, 0];
          clone.position.set(
            original.position.x + off[0] * i,
            original.position.y + off[1] * i,
            original.position.z + off[2] * i);
        }
        parent.add(clone);
        clone.traverse(function (child) { if (child.isMesh) meshes.push(child); });
      }
    });
    // gravity snap — a part touching nothing drops onto the surface below it
    // (only small gaps close; big gaps are intentional elevation)
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
      floating.forEach(function (i) {
        var supportTop, groundY;
        for (var j = 0; j < meshes.length; j++) {
          if (j === i || floating.indexOf(j) !== -1) continue;
          groundY = groundY === undefined ? boxes[j].min.y : Math.min(groundY, boxes[j].min.y);
          var overlapsPlan =
            boxes[i].min.x <= boxes[j].max.x && boxes[i].max.x >= boxes[j].min.x &&
            boxes[i].min.z <= boxes[j].max.z && boxes[i].max.z >= boxes[j].min.z;
          if (overlapsPlan && boxes[j].max.y <= boxes[i].min.y) {
            supportTop = supportTop === undefined ? boxes[j].max.y : Math.max(supportTop, boxes[j].max.y);
          }
        }
        var targetY = supportTop !== undefined ? supportTop : groundY;
        var dy = targetY === undefined ? 0 : boxes[i].min.y - targetY;
        if (dy > 0 && dy <= 0.35) {
          var worldPos = meshes[i].getWorldPosition(new THREE.Vector3());
          worldPos.y -= dy;
          meshes[i].position.copy(meshes[i].parent ? meshes[i].parent.worldToLocal(worldPos) : worldPos);
          boxes[i].translate(new THREE.Vector3(0, -dy, 0));
        }
      });
      root.updateWorldMatrix(true, true);
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
  if (usedPrimitives.has('textDecal')) helperBlocks.push(HELPER_TEXT_DECAL);
  if (usedPrimitives.has('curvedDecal')) helperBlocks.push(HELPER_CURVED_DECAL);
  if (usedPrimitives.has('glow')) helperBlocks.push(HELPER_GLOW);

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
      if (node.text || node.note)
        fields.push(`text: ${q(node.text || node.note || '')}`);
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
    "if (typeof module !== 'undefined') module.exports = { buildSculpture: buildSculpture };",
  );
  lines.push('');
  return lines.join('\n');
}

// the self-contained viewer page: model code inlined, three.js from CDN,
// scene/lights/orbit mirroring the studio's model-viewer. The page's realm
// URL is directly usable as an iframe src.
export function generateViewerHtml(spec: any, meta?: CodeExportMeta): string {
  let modelJs = generateModelJs(spec, meta);
  let name = spec?.objectName || 'sculpture';
  let title = String(name).replace(/&/g, '&amp;').replace(/</g, '&lt;');
  let needsRoundedBox = specNodes(spec).some(
    (n) => n.primitive === 'roundedBox',
  );

  let harness = `(function () {
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
  scene.background = new THREE.Color('#0a0b10');
  scene.fog = new THREE.Fog('#0a0b10', 14, 30);

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
})();`;

  return [
    '<!doctype html>',
    '<html lang="en">',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<title>${title}</title>`,
    '<style>html,body{margin:0;height:100%;background:#0a0b10;overflow:hidden}canvas{display:block}</style>',
    '</head>',
    '<body>',
    `<script src="${THREE_CDN}"></script>`,
    ...(needsRoundedBox ? [`<script src="${ROUNDED_BOX_CDN}"></script>`] : []),
    '<script>',
    modelJs,
    harness,
    '</script>',
    '</body>',
    '</html>',
    '',
  ].join('\n');
}
