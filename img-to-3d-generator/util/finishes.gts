// Procedural surface-finish painters, ported from the img2threejs showcase
// War-Hauler demo: every texture is PAINTED on a canvas with a seeded RNG —
// no image files. The same canvas doubles as color map and roughnessMap,
// which is what makes surfaces read as weathered/tactile instead of plastic.
//
// The LLM only ever names a finish ('worn' | 'brushed' | 'hazard' | 'tread');
// all painting happens here, deterministically per material id.

export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function seedFrom(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

function newCanvas(size: number): {
  cv: HTMLCanvasElement;
  ctx: CanvasRenderingContext2D;
} {
  let cv = document.createElement('canvas');
  cv.width = size;
  cv.height = size;
  return { cv, ctx: cv.getContext('2d')! };
}

// grime blotches + soot streaks + brushed scratches over a bright base, so
// the material's own baseColor shows through and weathering stays subtle
function paintWorn(
  ctx: CanvasRenderingContext2D,
  S: number,
  rand: () => number,
) {
  ctx.fillStyle = '#efefef';
  ctx.fillRect(0, 0, S, S);
  for (let i = 0; i < 130; i++) {
    let x = rand() * S;
    let y = rand() * S;
    let r = 30 + rand() * 90;
    let g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, `rgba(60,50,30,${0.04 + rand() * 0.1})`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  for (let i = 0; i < 60; i++) {
    ctx.strokeStyle = `rgba(50,40,26,${0.05 + rand() * 0.1})`;
    ctx.lineWidth = 1 + rand() * 3;
    let x = rand() * S;
    let y0 = rand() * S;
    ctx.beginPath();
    ctx.moveTo(x, y0);
    ctx.bezierCurveTo(
      x + (rand() - 0.5) * 24,
      y0 + 60,
      x + (rand() - 0.5) * 24,
      y0 + 140,
      x + (rand() - 0.5) * 18,
      y0 + 210,
    );
    ctx.stroke();
  }
  paintScratches(ctx, S, rand, 420);
}

function paintScratches(
  ctx: CanvasRenderingContext2D,
  S: number,
  rand: () => number,
  count: number,
) {
  for (let i = 0; i < count; i++) {
    ctx.strokeStyle =
      rand() > 0.5
        ? `rgba(255,255,255,${0.06 + rand() * 0.12})`
        : `rgba(120,100,60,${0.05 + rand() * 0.1})`;
    ctx.lineWidth = rand() * 1.2;
    let x = rand() * S;
    let y = rand() * S;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + (rand() - 0.5) * 36, y + (rand() - 0.5) * 6);
    ctx.stroke();
  }
}

function paintBrushed(
  ctx: CanvasRenderingContext2D,
  S: number,
  rand: () => number,
) {
  ctx.fillStyle = '#e8e8e8';
  ctx.fillRect(0, 0, S, S);
  paintScratches(ctx, S, rand, 1200);
}

// diagonal caution stripes — the map carries the colors, so the material's
// baseColor should stay near-white for this finish
function paintHazard(ctx: CanvasRenderingContext2D, S: number) {
  ctx.fillStyle = '#151515';
  ctx.fillRect(0, 0, S, S);
  ctx.save();
  ctx.translate(S / 2, S / 2);
  ctx.rotate(-Math.PI / 4);
  ctx.fillStyle = '#f7c948';
  for (let x = -S; x < S; x += 52) {
    ctx.fillRect(x, -S, 26, S * 2);
  }
  ctx.restore();
}

// parallel tread grooves that MULTIPLY with the material's own baseColor —
// a black tire stays black, with slightly lighter ribs catching the light
function paintTread(
  ctx: CanvasRenderingContext2D,
  S: number,
  rand: () => number,
) {
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, S, S);
  let rows = 14;
  let rowH = S / rows;
  for (let r = 0; r < rows; r++) {
    // dark groove line per row
    ctx.fillStyle = '#5f5f5f';
    ctx.fillRect(0, r * rowH + rowH * 0.62, S, rowH * 0.3);
    // staggered lug notches
    ctx.fillStyle = '#7a7a7a';
    let offset = (r % 2) * (S / 12);
    for (let x = -S / 12; x < S; x += S / 6) {
      ctx.fillRect(x + offset, r * rowH + rowH * 0.1, S / 24, rowH * 0.45);
    }
    if (rand() > 2) break; // keep rand consumed signature-compatible
  }
}

function shade(hex: string, factor: number): string {
  let n = parseInt(hex.replace('#', ''), 16);
  if (isNaN(n)) n = 0x8a8f9c;
  let ch = (v: number) => Math.min(255, Math.max(0, Math.round(v * factor)));
  let r = ch((n >> 16) & 255);
  let g = ch((n >> 8) & 255);
  let b = ch(n & 255);
  return `rgb(${r},${g},${b})`;
}

// organic camouflage blotches in tones derived from the material's own
// baseColor (War-Hauler oxidized-panel technique, parameterized)
function paintCamo(
  ctx: CanvasRenderingContext2D,
  S: number,
  rand: () => number,
  baseColor: string,
) {
  ctx.fillStyle = shade(baseColor, 1);
  ctx.fillRect(0, 0, S, S);
  let tones = [shade(baseColor, 0.62), shade(baseColor, 1.35)];
  for (let t = 0; t < tones.length; t++) {
    ctx.fillStyle = tones[t];
    for (let i = 0; i < 26; i++) {
      let x = rand() * S;
      let y = rand() * S;
      ctx.beginPath();
      ctx.moveTo(x, y);
      // lumpy blob: a closed run of arcs at varying radii
      let lobes = 5 + Math.floor(rand() * 4);
      for (let l = 0; l <= lobes; l++) {
        let ang = (l / lobes) * Math.PI * 2;
        let r = 40 + rand() * 90;
        ctx.lineTo(x + Math.cos(ang) * r, y + Math.sin(ang) * r);
      }
      ctx.closePath();
      ctx.fill();
    }
  }
  paintScratches(ctx, S, rand, 200);
}

// horizontal ribbed vent slats (dark panel louvers)
function paintLouver(ctx: CanvasRenderingContext2D, S: number) {
  ctx.fillStyle = '#3a3d40';
  ctx.fillRect(0, 0, S, S);
  let rows = 12;
  let rowH = S / rows;
  for (let r = 0; r < rows; r++) {
    ctx.fillStyle = '#15171a';
    ctx.fillRect(0, r * rowH + rowH * 0.45, S, rowH * 0.4);
    ctx.fillStyle = '#6a6e72';
    ctx.fillRect(0, r * rowH + rowH * 0.05, S, rowH * 0.12);
  }
}

// height-driven oxidation: the top of the surface blooms into a teal-green
// patina over the material's own baseColor (weathered-brass technique)
function paintPatina(
  ctx: CanvasRenderingContext2D,
  S: number,
  rand: () => number,
) {
  ctx.fillStyle = '#f0f0f0';
  ctx.fillRect(0, 0, S, S);
  let grad = ctx.createLinearGradient(0, 0, 0, S);
  grad.addColorStop(0, 'rgba(63, 111, 76, 0.85)');
  grad.addColorStop(0.35, 'rgba(63, 111, 76, 0.3)');
  grad.addColorStop(0.7, 'rgba(63, 111, 76, 0)');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, S, S);
  for (let i = 0; i < 40; i++) {
    let x = rand() * S;
    let y = rand() * S * 0.5;
    let r = 20 + rand() * 60;
    let g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, `rgba(63, 111, 76, ${0.15 + rand() * 0.25})`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }
  paintScratches(ctx, S, rand, 260);
}

// diamond cross-hatch grip relief (knife handles, tool grips). Routed to a
// bumpMap by the interpreter: mid-gray base = flat, dark diagonal grooves =
// recessed, so the diamonds read as raised knurling.
function paintKnurl(ctx: CanvasRenderingContext2D, S: number) {
  ctx.fillStyle = '#9a9a9a';
  ctx.fillRect(0, 0, S, S);
  ctx.strokeStyle = '#2c2c2c';
  ctx.lineWidth = S / 128;
  let step = S / 24;
  for (let k = -S; k < S * 2; k += step) {
    ctx.beginPath();
    ctx.moveTo(k, 0);
    ctx.lineTo(k + S, S);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(k + S, 0);
    ctx.lineTo(k, S);
    ctx.stroke();
  }
}

// returns a CanvasTexture for the named finish, deterministic per seedText
export function makeFinishTexture(
  THREE: any,
  finish: string,
  seedText: string,
  baseColor?: string,
): any {
  const S = 1024;
  let { cv, ctx } = newCanvas(S);
  let rand = mulberry32(seedFrom(seedText));
  switch (finish) {
    case 'worn':
      paintWorn(ctx, S, rand);
      break;
    case 'brushed':
      paintBrushed(ctx, S, rand);
      break;
    case 'hazard':
      paintHazard(ctx, S);
      break;
    case 'tread':
      paintTread(ctx, S, rand);
      break;
    case 'camo':
      paintCamo(ctx, S, rand, baseColor || '#7a7f5a');
      break;
    case 'louver':
      paintLouver(ctx, S);
      break;
    case 'patina':
      paintPatina(ctx, S, rand);
      break;
    case 'knurl':
      paintKnurl(ctx, S);
      break;
    default:
      return undefined;
  }
  let tex = new THREE.CanvasTexture(cv);
  tex.encoding = THREE.sRGBEncoding;
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.anisotropy = 8;
  return tex;
}
