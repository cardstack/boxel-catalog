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
  if (!(bbox?.width > 0) || !(bbox?.height > 0)) return fail('bbox has no area');
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
  let d =
    'M ' + halfs.map((hw, i) => `${fmt(axis + hw)} ${ys[i]}`).join(' L ');
  for (let i = halfs.length - 1; i >= 0; i--) {
    d += ` L ${fmt(axis - halfs[i])} ${ys[i]}`;
  }
  d += ' Z';
  return { path: d, width: w, height: h };
}
