// =============================================================================
// Munsell color math — the measured data and pure functions behind the tree.
//
// Munsell space is perceptual, not mathematical: each of the 10 principal
// hues has its own maximum chroma (C_PEAK) reached at its own value level
// (V_PEAK). Yellow crowns near value 8.5, purple-blue near value 3. The
// quadratic falloff from each hue's peak gives the solid its honest,
// lopsided canopy — it refuses to be a sphere.
// =============================================================================
import { htmlSafe } from '@ember/template';

/* ═══════════════════════════════════════════════════════════════════════════
   MUNSELL DATA — measured, lumpy, human
   ═══════════════════════════════════════════════════════════════════════════ */
export const TAU = Math.PI * 2;
export const V_STEP = 2.2; // world units per value step
export const C_SCALE = 0.9; // world units per chroma step
export const CENTER_V = 5; // value 5 sits at y = 0
export const SPHERE_R = 9; // Itten's idealized sphere radius

export const HUE_NAMES = [
  '5R',
  '5YR',
  '5Y',
  '5GY',
  '5G',
  '5BG',
  '5B',
  '5PB',
  '5P',
  '5RP',
];
// peak chroma each principal hue can reach (approx. Munsell renotation)
export const C_PEAK = [14, 13, 13, 11, 11, 9, 9, 13, 12, 12];
// the value level at which that peak chroma occurs
export const V_PEAK = [5, 6, 8.5, 7.5, 6, 5.5, 4.5, 3, 3.5, 4.5];
// display hue angle (HSL degrees) for each principal hue
export const HUE_DEG = [357, 32, 58, 95, 145, 182, 212, 255, 288, 332];

export const HUE_TIERS = [10, 20, 40];
export const EDGE_BASE = [1.5, 1.15, 0.95]; // denser lattices, smaller cubes

export function lerpWrap(arr: number[], h: number): number {
  let x = h * 10;
  let i = Math.floor(x) % 10;
  let j = (i + 1) % 10;
  let f = x - Math.floor(x);
  f = f * f * (3 - 2 * f);
  return arr[i] + (arr[j] - arr[i]) * f;
}

export function lerpWrapDeg(h: number): number {
  let x = h * 10;
  let i = Math.floor(x) % 10;
  let j = (i + 1) % 10;
  let f = x - Math.floor(x);
  f = f * f * (3 - 2 * f);
  let a = HUE_DEG[i];
  let b = HUE_DEG[j];
  if (b - a > 180) {
    b -= 360;
  } else if (a - b > 180) {
    b += 360;
  }
  return (((a + (b - a) * f) % 360) + 360) % 360;
}

export function maxChroma(h: number, v: number): number {
  let cp = lerpWrap(C_PEAK, h);
  let vp = lerpWrap(V_PEAK, h);
  let spread = v > vp ? 10.6 - vp : vp + 0.9;
  let t = (v - vp) / spread;
  return Math.max(0, cp * (1 - t * t));
}

export function hslToRgb(
  h: number,
  s: number,
  l: number,
): [number, number, number] {
  h = (((h % 360) + 360) % 360) / 360;
  let q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  let p = 2 * l - q;
  let hk = (t: number) => {
    t = ((t % 1) + 1) % 1;
    if (t < 1 / 6) {
      return p + (q - p) * 6 * t;
    }
    if (t < 1 / 2) {
      return q;
    }
    if (t < 2 / 3) {
      return p + (q - p) * (2 / 3 - t) * 6;
    }
    return p;
  };
  return [hk(h + 1 / 3), hk(h), hk(h - 1 / 3)];
}

export function chipColor(
  h: number,
  v: number,
  c: number,
): [number, number, number] {
  if (c < 0.5) {
    let l = 0.07 + 0.86 * (v / 10);
    return [l * 0.92, l * 0.96, l];
  }
  let deg = lerpWrapDeg(h);
  let s = Math.min(1, (c / 13) * 1.12);
  let l = 0.07 + 0.86 * (v / 10);
  return hslToRgb(deg, s, l);
}

export function toHex2(x: number): string {
  let v = Math.max(0, Math.min(255, Math.round(x * 255)));
  return v.toString(16).padStart(2, '0');
}

export function chipHex(h: number, v: number, c: number): string {
  let [r, g, b] = chipColor(h, v, c);
  return `#${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
}

export function rgbHex(r: number, g: number, b: number): string {
  return `#${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
}

export function swatchStyle(color: string | undefined | null) {
  return htmlSafe(`background-color: ${color || '#39505e'}`);
}

/* ═══════════════════════════════════════════════════════════════════════════
   ATLAS — the third address: the printed page. Unlike the tree/sphere
   addresses (baked once per voxel into instanced attributes), the page
   is not a separate data structure — the same voxel mesh is laid flat by
   the vertex shader itself (see VOXEL_VSH's uChart branch), so there is
   nothing here to build or gap-fill on the CPU.
   ═══════════════════════════════════════════════════════════════════════════ */
export function hueLabel(h: number): string {
  return HUE_NAMES[Math.round(h * 10) % 10];
}

export function munsellNotation(h: number, v: number, c: number): string {
  if (c < 0.5) {
    return `N ${v}/`;
  }
  let idx = Math.round(h * 10) % 10;
  return `${HUE_NAMES[idx]} ${v}/${Math.round(c)}`;
}

/* ═══════════════════════════════════════════════════════════════════════════
   LATTICE — every voxel knows two addresses: the tree and the sphere
   ═══════════════════════════════════════════════════════════════════════════ */
export interface ChipArrays {
  tree: number[];
  sphere: number[];
  cols: number[];
  cfr: number[];
  ang: number[];
  seed: number[];
  val: number[];
  chr: number[];
  edg: number[];
  hues: number[];
}

export function buildArrays(hueCount: number, densityIdx: number): ChipArrays {
  let base = EDGE_BASE[densityIdx];
  let a: ChipArrays = {
    tree: [],
    sphere: [],
    cols: [],
    cfr: [],
    ang: [],
    seed: [],
    val: [],
    chr: [],
    edg: [],
    hues: [],
  };
  let push = (h: number, v: number, c: number) => {
    let theta = h * TAU;
    let mc = Math.max(maxChroma(h, v), 0.001);
    let f = Math.min(1, c / mc);
    let r = c * C_SCALE;
    a.tree.push(
      Math.cos(theta) * r,
      (v - CENTER_V) * V_STEP,
      Math.sin(theta) * r,
    );
    // Itten's sphere: value maps to latitude, chroma fraction to longitude reach
    let ct = v / 5 - 1;
    let st = Math.sqrt(Math.max(0, 1 - ct * ct));
    let rs = SPHERE_R * st * f;
    a.sphere.push(Math.cos(theta) * rs, SPHERE_R * ct, Math.sin(theta) * rs);
    let rgb = chipColor(h, v, c);
    a.cols.push(rgb[0], rgb[1], rgb[2]);
    a.cfr.push(c < 0.5 ? 0 : f);
    a.ang.push(theta);
    a.seed.push(Math.random());
    a.val.push(v);
    a.chr.push(c);
    a.hues.push(h);
    // each cube solves its own edge so neighbors never touch:
    // tangential room at radius r is r·2π/H, radial room is one chroma step
    let e: number;
    if (c < 0.5) {
      e = Math.min(base * 0.85, 0.82 * V_STEP);
    } else {
      let tang = (r * TAU) / hueCount;
      e = Math.min(base, 0.82 * tang, 0.82 * 2 * C_SCALE);
    }
    a.edg.push(e);
  };
  for (let hi = 0; hi < hueCount; hi++) {
    let h = hi / hueCount;
    for (let v = 1; v <= 9; v++) {
      let mc = maxChroma(h, v);
      for (let c = 2; c <= mc + 0.001; c += 2) {
        push(h, v, c);
      }
    }
  }
  for (let v = 0; v <= 10; v++) {
    push(0, v, 0); // the gray trunk
  }
  return a;
}
