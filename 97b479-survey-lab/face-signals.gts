// What the webcam can tell us while someone watches, worked out on this
// device only: no picture of the face is kept or sent anywhere, only a few
// numbers per moment. MediaPipe's face landmarker gives ~50 expression scores
// (smile, brows, jaw…) and a head pose; a short follow-the-dot calibration
// turns eye and head direction into "where on the video are they looking".
// Webcam gaze is coarse: regions of the screen, not words.

const VISION = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14';
const MODEL =
  'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';
// a plain dynamic import, out of reach of the card loader's rewriting
const importUrl = new Function('u', 'return import(u)') as (
  u: string,
) => Promise<any>;

let markerPromise: Promise<any> | null = null;
export function loadMarker(): Promise<any> {
  markerPromise ??= (async () => {
    const vision = await importUrl(`${VISION}/vision_bundle.mjs`);
    const files = await vision.FilesetResolver.forVisionTasks(`${VISION}/wasm`);
    return vision.FaceLandmarker.createFromOptions(files, {
      baseOptions: { modelAssetPath: MODEL, delegate: 'GPU' },
      runningMode: 'VIDEO',
      numFaces: 1,
      outputFaceBlendshapes: true,
      outputFacialTransformationMatrixes: true,
    });
  })().catch((e) => {
    markerPromise = null;
    throw e;
  });
  return markerPromise;
}

// one reading of the face
export interface Reading {
  feat: number[]; // gaze features, for the calibration fit
  smile: number;
  browUp: number;
  browDown: number;
  jaw: number;
}

export function read(
  marker: any,
  video: HTMLVideoElement,
  now: number,
): Reading | null {
  const res = marker.detectForVideo(video, now);
  const shapes: { categoryName: string; score: number }[] | undefined =
    res?.faceBlendshapes?.[0]?.categories;
  const m: number[] | undefined = res?.facialTransformationMatrixes?.[0]?.data;
  if (!shapes || !m) return null;
  const s: Record<string, number> = {};
  for (const c of shapes) s[c.categoryName] = c.score;
  // the eyes: how far each looks in / out / up / down
  const h =
    (s.eyeLookOutLeft -
      s.eyeLookInLeft +
      s.eyeLookInRight -
      s.eyeLookOutRight) /
    2;
  const v =
    (s.eyeLookUpLeft +
      s.eyeLookUpRight -
      s.eyeLookDownLeft -
      s.eyeLookDownRight) /
    2;
  // the head: yaw and pitch from the pose matrix (column-major 4×4)
  const yaw = Math.asin(Math.max(-1, Math.min(1, -m[2])));
  const pitch = Math.atan2(m[6], m[10]);
  return {
    feat: [1, h, v, yaw, pitch],
    smile: ((s.mouthSmileLeft ?? 0) + (s.mouthSmileRight ?? 0)) / 2,
    browUp:
      ((s.browInnerUp ?? 0) +
        (s.browOuterUpLeft ?? 0) +
        (s.browOuterUpRight ?? 0)) /
      3,
    browDown: ((s.browDownLeft ?? 0) + (s.browDownRight ?? 0)) / 2,
    jaw: s.jawOpen ?? 0,
  };
}

// ─── calibration: a small ridge regression from features to the screen ──────
export interface GazeFit {
  wx: number[];
  wy: number[];
}

function solve(A: number[][], b: number[]): number[] {
  // Gaussian elimination with partial pivoting; A is small and square
  const n = b.length;
  const M = A.map((row, i) => [...row, b[i]]);
  for (let c = 0; c < n; c++) {
    let p = c;
    for (let r = c + 1; r < n; r++)
      if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]];
    const d = M[c][c] || 1e-9;
    for (let r = 0; r < n; r++) {
      if (r === c) continue;
      const f = M[r][c] / d;
      for (let k = c; k <= n; k++) M[r][k] -= f * M[c][k];
    }
  }
  return M.map((row, i) => row[n] / (row[i] || 1e-9));
}

// rows: features; tx, ty: where the dot was (0–1 across the video)
export function fitGaze(
  rows: number[][],
  tx: number[],
  ty: number[],
  ridge = 0.02,
): GazeFit | null {
  if (rows.length < 12) return null;
  const k = rows[0].length;
  const XtX = Array.from({ length: k }, () => new Array(k).fill(0));
  const Xtx = new Array(k).fill(0);
  const Xty = new Array(k).fill(0);
  rows.forEach((r, i) => {
    for (let a = 0; a < k; a++) {
      Xtx[a] += r[a] * tx[i];
      Xty[a] += r[a] * ty[i];
      for (let b = 0; b < k; b++) XtX[a][b] += r[a] * r[b];
    }
  });
  for (let a = 1; a < k; a++) XtX[a][a] += ridge * rows.length; // leave the constant unpenalised
  return { wx: solve(XtX, Xtx), wy: solve(XtX, Xty) };
}

export function gazeAt(fit: GazeFit, feat: number[]): { x: number; y: number } {
  let x = 0;
  let y = 0;
  feat.forEach((f, i) => {
    x += f * fit.wx[i];
    y += f * fit.wy[i];
  });
  return { x, y };
}

// the nine dots, as fractions across and down the video
export const DOTS: [number, number][] = [
  [0.5, 0.5],
  [0.1, 0.1],
  [0.5, 0.1],
  [0.9, 0.1],
  [0.9, 0.5],
  [0.9, 0.9],
  [0.5, 0.9],
  [0.1, 0.9],
  [0.1, 0.5],
];

// ─── what gets saved: one row per quarter second of video ────────────────
// t: video seconds · face: share of readings with a face · on: share looking
// at the video (null = no calibration) · gx, gy: mean gaze on the video ·
// smile / surprise / frown: above this person's own resting face
export interface Bin {
  t: number;
  face: number;
  on: number | null;
  gx: number | null;
  gy: number | null;
  smile: number;
  surprise: number;
  frown: number;
}

export interface Sample {
  t: number;
  r: Reading | null;
}

export interface Baseline {
  smile: number;
  browUp: number;
  browDown: number;
  jaw: number;
}

export function baselineOf(readings: Reading[]): Baseline {
  const med = (xs: number[]) => {
    if (!xs.length) return 0;
    const s = [...xs].sort((a, b) => a - b);
    return s[Math.floor(s.length / 2)];
  };
  return {
    smile: med(readings.map((r) => r.smile)),
    browUp: med(readings.map((r) => r.browUp)),
    browDown: med(readings.map((r) => r.browDown)),
    jaw: med(readings.map((r) => r.jaw)),
  };
}

const r3 = (n: number) => Math.round(n * 1000) / 1000;

export function binSamples(
  samples: Sample[],
  duration: number,
  fit: GazeFit | null,
  base: Baseline,
  step = 0.25,
): Bin[] {
  const n = Math.max(1, Math.ceil(duration / step));
  const bins: Bin[] = [];
  for (let i = 0; i < n; i++) {
    const t0 = i * step;
    const inBin = samples.filter((s) => s.t >= t0 && s.t < t0 + step);
    const faces = inBin.filter((s) => s.r) as { t: number; r: Reading }[];
    const face = inBin.length ? faces.length / inBin.length : 0;
    let on: number | null = null;
    let gx: number | null = null;
    let gy: number | null = null;
    if (fit && inBin.length) {
      const pts = faces.map((s) => gazeAt(fit, s.r.feat));
      const onCount = pts.filter(
        (p) => p.x > -0.12 && p.x < 1.12 && p.y > -0.12 && p.y < 1.12,
      ).length;
      on = r3(onCount / inBin.length);
      if (pts.length) {
        gx = r3(
          Math.min(
            1,
            Math.max(0, pts.reduce((a, p) => a + p.x, 0) / pts.length),
          ),
        );
        gy = r3(
          Math.min(
            1,
            Math.max(0, pts.reduce((a, p) => a + p.y, 0) / pts.length),
          ),
        );
      }
    }
    const mean = (f: (r: Reading) => number) =>
      faces.length ? faces.reduce((a, s) => a + f(s.r), 0) / faces.length : 0;
    bins.push({
      t: r3(t0),
      face: r3(face),
      on,
      gx,
      gy,
      smile: r3(Math.max(0, mean((r) => r.smile) - base.smile)),
      surprise: r3(
        Math.max(
          0,
          mean((r) => r.browUp) -
            base.browUp +
            0.5 * Math.max(0, mean((r) => r.jaw) - base.jaw),
        ),
      ),
      frown: r3(Math.max(0, mean((r) => r.browDown) - base.browDown)),
    });
  }
  return bins;
}

// ─── the moments worth asking about ──────────────────────────────────────
export type MomentKind =
  | 'smile'
  | 'surprise'
  | 'frown'
  | 'away'
  | 'pause'
  | 'pick';
export interface Moment {
  t: number;
  kind: MomentKind;
  strength: number;
}

export const KIND_WORDS: Record<MomentKind, string> = {
  smile: 'smiled',
  surprise: 'brows went up',
  frown: 'brows pulled down',
  away: 'looked away',
  pause: 'paused',
  pick: 'no clear reaction, picked to ask about',
};

function smooth(xs: number[], w = 2): number[] {
  return xs.map((_, i) => {
    let s = 0;
    let c = 0;
    for (let j = i - w; j <= i + w; j++) {
      if (j >= 0 && j < xs.length) {
        s += xs[j];
        c++;
      }
    }
    return s / c;
  });
}

// Peaks against this person's own range: what stood out for them, not what
// would stand out for an average face.
export function findMoments(
  bins: Bin[],
  pauses: number[],
  duration: number,
  max = 3,
): Moment[] {
  const cands: Moment[] = [];
  const peak = (kind: MomentKind, xs: number[], floor: number) => {
    const s = smooth(xs);
    const mean = s.reduce((a, b) => a + b, 0) / (s.length || 1);
    const sd =
      Math.sqrt(s.reduce((a, b) => a + (b - mean) ** 2, 0) / (s.length || 1)) ||
      1e-6;
    s.forEach((x, i) => {
      const z = (x - mean) / sd;
      const local =
        (i === 0 || x >= s[i - 1]) && (i === s.length - 1 || x >= s[i + 1]);
      if (local && z > 1.4 && x > floor)
        cands.push({ t: bins[i].t, kind, strength: z });
    });
  };
  peak(
    'smile',
    bins.map((b) => b.smile),
    0.06,
  );
  peak(
    'surprise',
    bins.map((b) => b.surprise),
    0.05,
  );
  peak(
    'frown',
    bins.map((b) => b.frown),
    0.05,
  );
  // looking away: a second or more of no face, or of eyes off the video
  let run = 0;
  bins.forEach((b, i) => {
    const away = b.face < 0.3 || (b.on !== null && b.on < 0.3);
    run = away ? run + 1 : 0;
    if (run === 4)
      cands.push({ t: bins[i - 3].t, kind: 'away', strength: 2.5 });
  });
  pauses.forEach((t) => cands.push({ t, kind: 'pause', strength: 2.2 }));
  cands.sort((a, b) => b.strength - a.strength);
  const out: Moment[] = [];
  for (const c of cands) {
    if (out.length >= max) break;
    if (out.every((o) => Math.abs(o.t - c.t) >= 4)) out.push(c);
  }
  // a flat face is an answer too, but we still want something to talk about
  for (const f of [0.3, 0.6, 0.85]) {
    if (out.length >= Math.min(2, max)) break;
    const t = Math.round(duration * f * 4) / 4;
    if (out.every((o) => Math.abs(o.t - t) >= 4))
      out.push({ t, kind: 'pick', strength: 0 });
  }
  return out.sort((a, b) => a.t - b.t);
}

export function clock(t: number) {
  const s = Math.max(0, Math.floor(t));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

// SVG path for a 0–1 series across a w×h box
export function linePath(xs: number[], w: number, h: number, top = 1): string {
  if (!xs.length) return '';
  const n = xs.length;
  return xs
    .map((x, i) => {
      const px = (i / Math.max(1, n - 1)) * w;
      const py = h - Math.min(1, Math.max(0, x / top)) * h;
      return `${i ? 'L' : 'M'}${px.toFixed(1)},${py.toFixed(1)}`;
    })
    .join(' ');
}
