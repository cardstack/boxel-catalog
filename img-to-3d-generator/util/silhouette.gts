// Silhouette tracing: extract a lathe profile for a rotationally symmetric
// part straight from the reference photo's pixels, instead of trusting the
// vision model to invent one. The traced half-width-per-height sequence IS
// the part's real outline — cone-shaped bottles and invented bulges cannot
// survive it.

export interface SilhouetteBbox {
  left: number;
  top: number;
  width: number;
  height: number;
}

interface Segmentation {
  w: number;
  h: number;
  outside: Uint8Array;
}

// Shared segmentation: downsample the crop and split foreground from background
// with a direct per-pixel color threshold against the corner-sampled ground.
// (Deliberately NOT a border flood-fill — see the note at the threshold below;
// on glossy bottles a flood leaks along bright edge highlights and eats the
// body.) Interior gaps a threshold leaves — a pale label, a highlight — are
// repaired later per-row. Returns the mask (`outside[k]===0` ⇒ foreground), or
// null (with a reason pushed to `diag`) when the crop can't segment cleanly.
function segmentCrop(
  image: HTMLImageElement,
  bbox: SilhouetteBbox,
  diag?: string[],
): Segmentation | null {
  let fail = (reason: string): null => {
    diag?.push(reason);
    return null;
  };
  if (!(bbox?.width > 0) || !(bbox?.height > 0))
    return fail('bbox has no area');
  let sx = Math.round(bbox.left * image.width);
  let sy = Math.round(bbox.top * image.height);
  let sw = Math.max(4, Math.round(bbox.width * image.width));
  let sh = Math.max(4, Math.round(bbox.height * image.height));

  // downsample the crop — silhouette scanning needs shape, not resolution
  let maxDim = 220;
  let scale = Math.min(1, maxDim / Math.max(sw, sh));
  let w = Math.max(4, Math.round(sw * scale));
  let h = Math.max(4, Math.round(sh * scale));
  let canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  let ctx = canvas.getContext('2d')!;
  ctx.drawImage(image, sx, sy, sw, sh, 0, 0, w, h);
  let data: Uint8ClampedArray;
  try {
    data = ctx.getImageData(0, 0, w, h).data;
  } catch {
    return fail('tainted canvas — reference pixels unreadable (CORS)');
  }

  // background = the average of the four corner patches (product shots have
  // clean grounds)
  let corner = (cx: number, cy: number) => {
    let r = 0,
      g = 0,
      b = 0,
      n = 0;
    for (let y = cy; y < cy + 3 && y < h; y++) {
      for (let x = cx; x < cx + 3 && x < w; x++) {
        let i = (y * w + x) * 4;
        r += data[i];
        g += data[i + 1];
        b += data[i + 2];
        n++;
      }
    }
    return [r / n, g / n, b / n];
  };
  let corners = [
    corner(0, 0),
    corner(w - 3, 0),
    corner(0, h - 3),
    corner(w - 3, h - 3),
  ];
  let bg = [0, 1, 2].map(
    (c) => corners.reduce((s, k) => s + k[c], 0) / corners.length,
  );
  // DIRECT-THRESHOLD segmentation (NOT a border flood-fill): a pixel is
  // foreground when it is NOT near-white background. On a clean product shot
  // EVERYTHING that isn't the white ground is the object — dark glass, the cream
  // label, and the lighter curved-glass edges alike — so the threshold is LOW,
  // just above pure white. A high threshold was the bug: it excluded the pale
  // label and the light glass edges, leaving only the dark centre, so the body
  // traced as a thin strip (its width collapsed to the label's dark text). A
  // per-pixel test also can't "flow" like a flood-fill, which on a glossy bottle
  // leaks inward along the bright rim highlights and eats both whole sides.
  let fgTol = 26 * 26; // squared distance from white that still counts as body
  let outside = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let i = (y * w + x) * 4;
      let dr = data[i] - bg[0];
      let dg = data[i + 1] - bg[1];
      let db = data[i + 2] - bg[2];
      let fg = data[i + 3] >= 32 && dr * dr + dg * dg + db * db > fgTol;
      outside[y * w + x] = fg ? 0 : 1;
    }
  }

  // sanity: the mask must be mostly-but-not-entirely foreground
  let fgCount = 0;
  for (let y = 0; y < h; y += 2) {
    for (let x = 0; x < w; x += 2) {
      if (outside[y * w + x] === 0) fgCount++;
    }
  }
  let fgFraction = fgCount / ((w / 2) * (h / 2));
  if (fgFraction < 0.03 || fgFraction > 0.98) {
    return fail(
      `foreground fraction ${fgFraction.toFixed(2)} out of range — busy background or crop fills the frame`,
    );
  }
  return { w, h, outside };
}

// Fill a spans array's null gaps by linear-interpolating between the nearest
// non-null rows above and below (leading/trailing nulls stay null).
function interpolateSpans(vals: (number | null)[]): (number | null)[] {
  let out = vals.slice();
  let prev = -1;
  for (let i = 0; i < out.length; i++) {
    if (out[i] == null) continue;
    if (prev >= 0 && i - prev > 1) {
      let a = out[prev] as number;
      let b = out[i] as number;
      let gap = i - prev;
      for (let k = 1; k < gap; k++) out[prev + k] = a + ((b - a) * k) / gap;
    }
    prev = i;
  }
  return out;
}

// Median-smooth a spans array — robust to single-row spikes from label text,
// reflections, or antialiasing (a moving average would round shoulders and
// still be dragged toward an outlier).
function medianSmoothSpans(
  vals: (number | null)[],
  radius: number,
): (number | null)[] {
  return vals.map((v, i) => {
    if (v == null) return null;
    let s: number[] = [];
    for (
      let j = Math.max(0, i - radius);
      j <= Math.min(vals.length - 1, i + radius);
      j++
    ) {
      let x = vals[j];
      if (x != null) s.push(x);
    }
    s.sort((a, b) => a - b);
    return s.length ? s[Math.floor(s.length / 2)] : v;
  });
}

// Repair a revolved-object mask so a white/pale label, transparent glass, or a
// bright reflection can't punch a hole (or cut an inward spike) into the
// silhouette. For each row take the OUTER foreground span [left,right] (the true
// bottle edges survive even when the label between them reads as background),
// drop the drop-shadow flare at the base, interpolate rows the label ate
// entirely, median-smooth both boundaries, then fill every valid row solid
// left→right. The result is one continuous silhouette that BOTH the lathe
// profile and the SVG outline consume, keeping preview, body, and clamp
// envelope in sync. Only sound for lathe-like bodies (the per-row fill would
// erase intentional holes) — callers use it exclusively on revolved parts.
function repairLatheSilhouetteMask(
  outside: Uint8Array,
  w: number,
  h: number,
  diag?: string[],
): Uint8Array {
  let left: (number | null)[] = new Array(h).fill(null);
  let right: (number | null)[] = new Array(h).fill(null);
  let minSpan = Math.max(2, Math.round(w * 0.01));
  let widths: number[] = [];
  for (let y = 0; y < h; y++) {
    let minX = w;
    let maxX = -1;
    for (let x = 0; x < w; x++) {
      if (outside[y * w + x] === 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }
    if (maxX >= minX && maxX - minX >= minSpan) {
      left[y] = minX;
      right[y] = maxX;
      widths.push(maxX - minX);
    }
  }
  if (widths.length < 3) return outside; // too little to repair — keep raw
  // drop the drop-shadow flare: trailing (base) rows much wider than the median
  let sortedW = widths.slice().sort((a, b) => a - b);
  let medW = sortedW[Math.floor(sortedW.length / 2)] || 1;
  for (let y = h - 1; y >= 0; y--) {
    if (left[y] == null) continue;
    if ((right[y] as number) - (left[y] as number) > medW * 1.35) {
      left[y] = null;
      right[y] = null;
    } else break;
  }
  let sl = medianSmoothSpans(interpolateSpans(left), 3);
  let sr = medianSmoothSpans(interpolateSpans(right), 3);
  let repaired = new Uint8Array(w * h).fill(1);
  let filled = 0;
  let interpolated = 0;
  for (let y = 0; y < h; y++) {
    let l = sl[y];
    let r = sr[y];
    if (l == null || r == null || r < l) continue;
    if (left[y] == null) interpolated++;
    let s = Math.max(0, Math.floor(l));
    let e = Math.min(w - 1, Math.ceil(r));
    for (let x = s; x <= e; x++) repaired[y * w + x] = 0;
    filled++;
  }
  if (!filled) return outside;
  if (interpolated > 0) {
    diag?.push(`repaired lathe silhouette across ${interpolated} missing rows`);
  }
  return repaired;
}

// Average colour of a small patch, used to sample backdrop corners.
function patchColor(
  data: Uint8ClampedArray,
  w: number,
  x0: number,
  y0: number,
  size: number,
): [number, number, number] {
  let r = 0,
    g = 0,
    b = 0,
    n = 0;
  for (let y = y0; y < y0 + size; y++) {
    for (let x = x0; x < x0 + size; x++) {
      let i = (y * w + x) * 4;
      r += data[i];
      g += data[i + 1];
      b += data[i + 2];
      n++;
    }
  }
  return [r / n, g / n, b / n];
}

function colorDistanceSq(a: number[], b: number[]): number {
  return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2;
}

// Squared RGB distance from the backdrop colour. Below CUT a pixel IS the
// backdrop and goes fully transparent; above KEEP it is object and stays
// opaque; between the two it is the antialiased rim and fades. Both are
// deliberately tight — a product shot's ground is near-uniform, so a wide
// tolerance starts eating pale parts of the object (a cream label, a chrome
// bezel) rather than the ground.
const CUT_TOLERANCE = 30 * 30;
const KEEP_TOLERANCE = 55 * 55;

function unionBox(boxes: SilhouetteBbox[]): SilhouetteBbox {
  let left = Math.min(...boxes.map((b) => b.left));
  let top = Math.min(...boxes.map((b) => b.top));
  return {
    left,
    top,
    width: Math.max(...boxes.map((b) => b.left + b.width)) - left,
    height: Math.max(...boxes.map((b) => b.top + b.height)) - top,
  };
}

// Which region of the reference to trace as THE object's revolved silhouette,
// or a reason not to trace at all.
//
// Analysis usually splits one revolved body into stacked parts — a bottle's
// body / shoulder / neck / lip — which share an axis, so the region to trace
// is their union. Two conditions have to hold for that union to mean anything,
// and a machine with a round component satisfies neither:
//
//   · ONE AXIS. Parts at opposite ends of an object are not a stack. A
//     Thompson's drum magazine and barrel unioned to a box around the whole
//     weapon, whose traced outline revolved into a wooden spinning top.
//   · IT IS THE BODY. A single revolved part passes the axis test trivially —
//     nothing disagrees with it — so a drum magazine alone would otherwise
//     hand its own outline to the entire gun.
//
// The second condition matters more than the profile it rejects: the traced
// outline also becomes the envelope every solid part is clamped into, so a
// wrong trace does not just add one bad part, it displaces all the good ones.
export function revolvedSilhouetteBbox(plan: any[]): {
  bbox?: SilhouetteBbox;
  skipped?: string;
} {
  let sized = (plan ?? []).filter((p: any) => p?.bbox?.width > 0);
  let revolved = sized.filter((p: any) => p?.approach === 'revolved');
  if (!revolved.length) return { skipped: 'no revolved parts' };

  let bbox = unionBox(revolved.map((p: any) => p.bbox));
  // PAIRWISE, not each-part-against-the-union: every part is inside the union
  // by construction, so measuring against it always returns the part's own
  // width and passes everything.
  let overlap = (a: SilhouetteBbox, b: SilhouetteBbox) =>
    Math.min(a.left + a.width, b.left + b.width) - Math.max(a.left, b.left);
  for (let i = 0; i < revolved.length; i++) {
    for (let j = i + 1; j < revolved.length; j++) {
      let a = revolved[i].bbox;
      let b = revolved[j].bbox;
      if (overlap(a, b) < 0.6 * Math.min(a.width, b.width)) {
        return { skipped: 'revolved parts are not on one axis' };
      }
    }
  }

  let objectBox = unionBox(sized.map((p: any) => p.bbox));
  if (
    bbox.height < 0.6 * objectBox.height ||
    bbox.width < 0.5 * objectBox.width
  ) {
    return { skipped: 'revolved parts are a detail, not the body' };
  }
  return { bbox };
}

// The photo's backdrop colour, sampled from the four image corners — which
// are backdrop by construction on the product shots this pipeline is fed.
// Returns null when those corners disagree, i.e. the reference has no clean
// ground to key against and nothing should be cut.
function referenceBackdrop(
  image: HTMLImageElement,
  diag?: string[],
): [number, number, number] | null {
  let side = 64;
  let canvas = document.createElement('canvas');
  canvas.width = side;
  canvas.height = side;
  let ctx = canvas.getContext('2d')!;
  ctx.drawImage(image, 0, 0, side, side);
  let data: Uint8ClampedArray;
  try {
    data = ctx.getImageData(0, 0, side, side).data;
  } catch {
    diag?.push('tainted canvas — backdrop unreadable (CORS)');
    return null;
  }
  let patch = 4;
  let far = side - patch;
  let corners = [
    patchColor(data, side, 0, 0, patch),
    patchColor(data, side, far, 0, patch),
    patchColor(data, side, 0, far, patch),
    patchColor(data, side, far, far, patch),
  ];
  let backdrop = [0, 1, 2].map(
    (c) => corners.reduce((s, k) => s + k[c], 0) / corners.length,
  ) as [number, number, number];
  if (corners.some((corner) => colorDistanceSq(corner, backdrop) >= 30 * 30)) {
    diag?.push('reference has no uniform backdrop — crop left opaque');
    return null;
  }
  return backdrop;
}

// Crops `bbox` out of the image with the BACKDROP knocked out to transparent,
// for artwork that gets pasted onto the model as a decal.
//
// A bbox is a rectangle and the thing inside it rarely is: the region around a
// bottle's foil capsule, or a character's face, is mostly the photo's ground.
// Pasted as an opaque decal, that ground lands on the model as a pale slab
// around the artwork — the capsule arrived wearing two white wings.
//
// Keyed against the WHOLE IMAGE's backdrop colour, never against the crop's
// own corners. A crop's corners are only the backdrop when the crop happens to
// straddle the object's edge; inside a wine label they are the label's cream
// ground, and cutting on that answer keeps the lettering and throws the label
// away. It also survives a crop that clips a neighbouring part — the capsule's
// bbox catches the top of the bottle body, and that body is object, not ground.
//
// The crop keeps the bbox's full extent rather than trimming to what survived:
// the decal's authored width/height were chosen for this rectangle, so
// shrinking it would stretch the graphic across a plane it no longer matches.
// Transparent margin costs nothing to render.
//
// Returns null — caller falls back to a plain opaque crop — when the reference
// has no clean ground, when the crop lies entirely on the object (the common
// and correct case for a label), or when the cut would take nearly everything.
export function cropWithBackgroundRemoved(
  image: HTMLImageElement,
  bbox: SilhouetteBbox,
  diag?: string[],
): HTMLCanvasElement | null {
  let backdrop = referenceBackdrop(image, diag);
  if (!backdrop) return null;

  let sx = Math.round(bbox.left * image.width);
  let sy = Math.round(bbox.top * image.height);
  let sw = Math.max(1, Math.round(bbox.width * image.width));
  let sh = Math.max(1, Math.round(bbox.height * image.height));
  let canvas = document.createElement('canvas');
  canvas.width = sw;
  canvas.height = sh;
  let ctx = canvas.getContext('2d')!;
  ctx.drawImage(image, sx, sy, sw, sh, 0, 0, sw, sh);
  let frame;
  try {
    frame = ctx.getImageData(0, 0, sw, sh);
  } catch {
    diag?.push('tainted canvas — artwork pixels unreadable (CORS)');
    return null;
  }
  let pixels = frame.data;
  let isBackdrop = (i: number) =>
    colorDistanceSq([pixels[i], pixels[i + 1], pixels[i + 2]], backdrop);

  // Is there any ground in this rectangle at all? Measured on the border ring
  // rather than the four corners: a bbox drawn tight around a part is a few
  // pixels of margin at most, so corner patches land on the part itself and
  // report "no backdrop" for exactly the crops that need cutting. The ring is
  // a far larger sample and degrades gracefully — a part flush against one
  // edge of its own bbox still leaves the other three.
  let border = 0;
  let onBackdrop = 0;
  let sample = (x: number, y: number) => {
    border++;
    if (isBackdrop((y * sw + x) * 4) < CUT_TOLERANCE) onBackdrop++;
  };
  for (let x = 0; x < sw; x++) {
    sample(x, 0);
    sample(x, sh - 1);
  }
  for (let y = 1; y < sh - 1; y++) {
    sample(0, y);
    sample(sw - 1, y);
  }
  if (onBackdrop / Math.max(1, border) < 0.12) {
    diag?.push('crop lies on the object — left opaque');
    return null;
  }

  // Ramp rather than threshold: a pixel well clear of the ground keeps its
  // alpha, one indistinguishable from it goes fully transparent, and the
  // antialiased rim in between fades. A hard cut leaves a jagged edge and a
  // halo of ground colour one pixel wide all the way round the artwork.
  let kept = 0;
  for (let i = 0; i < pixels.length; i += 4) {
    let d = isBackdrop(i);
    let opacity =
      d <= CUT_TOLERANCE
        ? 0
        : d >= KEEP_TOLERANCE
          ? 1
          : (d - CUT_TOLERANCE) / (KEEP_TOLERANCE - CUT_TOLERANCE);
    pixels[i + 3] = Math.round(pixels[i + 3] * opacity);
    if (opacity > 0.5) kept++;
  }
  let keptFraction = kept / (pixels.length / 4);
  if (keptFraction < 0.03) {
    diag?.push('cut would remove the whole crop — left opaque');
    return null;
  }
  diag?.push(`cut backdrop, kept ${Math.round(keptFraction * 100)}% of the crop`);
  ctx.putImageData(frame, 0, 0);
  return canvas;
}

// Traces the part inside `bbox` (normalized to the image) and returns a
// lathe dimensions array [x0,y0, x1,y1, ...] bottom→top, where x is the
// half-width and y the height, both normalized so the profile spans
// height 0..1 with half-widths as fractions of that height. Returns null
// (with a reason pushed to `diag`) when the crop can't segment cleanly.
export function traceLatheProfile(
  image: HTMLImageElement,
  bbox: SilhouetteBbox,
  samples = 12,
  diag?: string[],
): number[] | null {
  let fail = (reason: string): null => {
    diag?.push(reason);
    return null;
  };
  let seg = segmentCrop(image, bbox, diag);
  if (!seg) return null;
  let { w, h } = seg;
  // repair white-label / reflection gaps so the profile follows the true bottle
  let outside = repairLatheSilhouetteMask(seg.outside, w, h, diag);
  let isForeground = (x: number, y: number) => outside[y * w + x] === 0;

  // per-sample row: the silhouette half-width is (rightmost − leftmost) / 2 of
  // the segmented object on that row. The filled mask means interior label /
  // highlight pixels no longer break the span, so a clean outline falls out — no
  // symmetry assumption and no center-line scan needed.
  let rows: { y: number; half: number }[] = [];
  for (let s = 0; s < samples; s++) {
    // bottom→top, sampling row centers so the lip and base are included
    let y = Math.round(((samples - 1 - s + 0.5) / samples) * (h - 1));
    let minX = -1;
    let maxX = -1;
    for (let x = 0; x < w; x++) {
      if (isForeground(x, y)) {
        if (minX < 0) minX = x;
        maxX = x;
      }
    }
    rows.push({
      y: s / (samples - 1),
      half: minX < 0 ? 0 : (maxX - minX + 1) / 2 / h,
    });
  }

  // drop leading/trailing empty rows (crop padding), keep at least 3 rows
  let first = rows.findIndex((r) => r.half > 0);
  let last = rows.length - 1 - [...rows].reverse().findIndex((r) => r.half > 0);
  if (first < 0 || last - first < 2) {
    return fail('fewer than 3 solid rows — silhouette too sparse to trace');
  }
  let kept = rows.slice(first, last + 1);

  // physical shape prior for revolved containers: the true outline is
  // UNIMODAL — it never narrows on the way up to its widest point, and never
  // widens again above it (a small lip flare at the very top excepted).
  // Every violation is segmentation noise: light labels reading as
  // background, glass reflections eroding an edge row. Clamp to the
  // envelope instead of trusting wavy rows.
  let smoothed = kept.map((r, i) => {
    let window = [kept[i - 1]?.half, r.half, kept[i + 1]?.half].filter(
      (v): v is number => typeof v === 'number',
    );
    window.sort((a, b) => a - b);
    return { y: r.y, half: window[Math.floor(window.length / 2)] };
  });
  let peak = smoothed.reduce(
    (best, r, i) => (r.half > smoothed[best].half ? i : best),
    0,
  );
  for (let i = 1; i <= peak; i++) {
    // base → widest point: non-decreasing
    smoothed[i].half = Math.max(smoothed[i].half, smoothed[i - 1].half);
  }
  for (let i = peak + 1; i < smoothed.length; i++) {
    // widest point → top: non-increasing, but let the last rows flare a
    // little (bottle lips / rolled rims)
    let flare = i >= smoothed.length - 2 ? 1.2 : 1;
    smoothed[i].half = Math.min(smoothed[i].half, smoothed[i - 1].half * flare);
  }
  kept = smoothed;

  // the traced widths are the measurement of record (the threshold already
  // keeps shadows out); the bbox aspect only CAPS them — analysis bboxes run
  // loose, so scaling UP to the bbox width fattens slender objects
  let maxHalf = Math.max(...kept.map((r) => r.half));
  if (!(maxHalf > 0)) return fail('traced width is zero');
  let capHalf = (w / h / 2) * 1.15;
  let renorm = maxHalf > capHalf ? capHalf / maxHalf : 1;

  let span = kept[kept.length - 1].y - kept[0].y || 1;
  let y0 = kept[0].y;
  let profile: number[] = [];
  // start closed on the axis so the lathe caps its base
  profile.push(0, 0);
  for (let row of kept) {
    profile.push(
      Number((row.half * renorm).toFixed(4)),
      Number(((row.y - y0) / span).toFixed(4)),
    );
  }
  return profile;
}

export interface TracedOutline {
  // SVG path string in the crop's own pixel space (0..width, 0..height)
  path: string;
  width: number;
  height: number;
}

// The RAW segmented outline as an SVG path — the actual contour the tracer
// sees, at full row resolution and WITHOUT the unimodal clamp the lathe uses.
// A viewer can render this next to the reference to see exactly what was traced
// (and where it's imperfect). Same segmentation as traceLatheProfile, so the
// displayed outline and the built profile always agree on the foreground.
export function traceSilhouetteSvg(
  image: HTMLImageElement,
  bbox: SilhouetteBbox,
  diag?: string[],
): TracedOutline | null {
  let seg = segmentCrop(image, bbox, diag);
  if (!seg) return null;
  let { w, h } = seg;
  // same repaired mask the lathe profile uses — so preview and body agree
  let outside = repairLatheSilhouetteMask(seg.outside, w, h);
  let rows: { y: number; min: number; max: number }[] = [];
  for (let y = 0; y < h; y++) {
    let minX = -1;
    let maxX = -1;
    for (let x = 0; x < w; x++) {
      if (outside[y * w + x] === 0) {
        if (minX < 0) minX = x;
        maxX = x;
      }
    }
    if (minX >= 0) rows.push({ y, min: minX, max: maxX });
  }
  if (rows.length < 3) {
    diag?.push('outline has too few solid rows to draw');
    return null;
  }
  // draw the SAME unimodal, axis-symmetric envelope the lathe body is built
  // from — so the preview shows the shape that actually gets sculpted, not the
  // raw per-row spans (which zig-zag through a label even after mask repair).
  let centers = rows.map((r) => (r.min + r.max) / 2).sort((a, b) => a - b);
  let axis = centers[Math.floor(centers.length / 2)];
  let halfs = rows.map((r) => Math.max(axis - r.min, r.max - axis));
  let peak = halfs.reduce((b, v, i) => (v > halfs[b] ? i : b), 0);
  // non-increasing away from the widest point in both directions (a small lip
  // flare at the very top is allowed)
  for (let i = peak - 1; i >= 0; i--) {
    let flare = i <= 1 ? 1.2 : 1;
    halfs[i] = Math.min(halfs[i], halfs[i + 1] * flare);
  }
  for (let i = peak + 1; i < halfs.length; i++) {
    halfs[i] = Math.min(halfs[i], halfs[i - 1]);
  }
  let fmt = (n: number) => Number(n.toFixed(1));
  let ys = rows.map((r) => r.y);
  let d = 'M ' + halfs.map((hw, i) => `${fmt(axis + hw)} ${ys[i]}`).join(' L ');
  for (let i = halfs.length - 1; i >= 0; i--) {
    d += ` L ${fmt(axis - halfs[i])} ${ys[i]}`;
  }
  d += ' Z';
  return { path: d, width: w, height: h };
}
