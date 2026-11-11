/**
 * WHAT A MIX SOUNDS LIKE, MEASURED ONCE AND KEPT ON THE CARD.
 *
 * The same Web Audio decode that plays a mix measures it: its loudness for
 * the waveform scrubber, and its tempo map for the bouncing dot. Edit mode
 * runs this and stores the result in the card's MixAnalysis fields, so the
 * player never has to (the port of data/transients.py).
 *
 * Tempo map:
 * 1. Mono at ~22 kHz; onset strength = half-wave-rectified spectral flux
 *    (1024 window, 64 hop ≈ 2.9 ms), the slow swell removed.
 * 2. The strong onsets, as a phase against the sixteenths of (bpm, downbeat).
 * 3. In 8 s windows every 2 s, the strength-weighted circular mean of those
 *    phases is how far the drums sit from the grid there; smoothed, that
 *    offset curve moves every eighth note (no per-hit jitter).
 * 4. Per eighth: its onset strength 0..1, and 0 off-eighth / 1 beat / 2 bar.
 */

export interface MixMeasure {
  duration: number;
  /** loudness in bars, 0.04..1 */
  peaks: number[];
  bpm: number;
  downbeat: number;
  eighths: number[];
  strength: number[];
  beat: number[];
}

const BARS = 480;
const RATE = 22050;

/** the mix at `url`, decoded to mono near 22 kHz */
export async function decodeMono(
  url: string,
): Promise<{ x: Float32Array; sr: number }> {
  const bytes = await (await fetch(url)).arrayBuffer();
  // an offline context decodes straight to its own rate
  const ctx = new OfflineAudioContext(1, 1, RATE);
  const buf = await ctx.decodeAudioData(bytes);
  return { x: mono(buf), sr: buf.sampleRate };
}

/** an already decoded buffer (the player's), as mono near 22 kHz */
export function monoOf(buf: AudioBuffer): { x: Float32Array; sr: number } {
  const x = mono(buf);
  const f = Math.max(1, Math.floor(buf.sampleRate / RATE));
  if (f === 1) return { x, sr: buf.sampleRate };
  const out = new Float32Array(Math.floor(x.length / f));
  for (let i = 0; i < out.length; i++) {
    let s = 0;
    for (let j = 0; j < f; j++) s += x[i * f + j]!;
    out[i] = s / f;
  }
  return { x: out, sr: buf.sampleRate / f };
}

function mono(buf: AudioBuffer): Float32Array {
  const out = new Float32Array(buf.length);
  for (let c = 0; c < buf.numberOfChannels; c++) {
    const ch = buf.getChannelData(c);
    for (let i = 0; i < ch.length; i++)
      out[i]! += ch[i]! / buf.numberOfChannels;
  }
  return out;
}

/**
 * Loudness per bar, like SoundCloud's waveform: the RMS of each slice on a
 * linear scale (the loudest bar at 1).
 */
export function loudness(x: Float32Array, bars = BARS): number[] {
  const rms: number[] = [];
  for (let i = 0; i < bars; i++) {
    const a = Math.floor((i * x.length) / bars);
    const b = Math.floor(((i + 1) * x.length) / bars);
    let s = 0;
    for (let j = a; j < b; j++) s += x[j]! * x[j]!;
    rms.push(Math.sqrt(s / Math.max(1, b - a)));
  }
  // a mastered mix is loud all the way: stretch from just under its quietest
  // twentieth to its loudest bar, so verses, drops and breaks show their shape
  const top = Math.max(...rms) || 1;
  const sorted = rms.map((r) => r / top).sort((p, q) => p - q);
  const floor = (sorted[Math.floor(sorted.length * 0.05)] ?? 0) * 0.85;
  return rms.map((r) =>
    round(
      Math.max(0.04, Math.max(0, (r / top - floor) / (1 - floor)) ** 1.3),
      3,
    ),
  );
}

/** onset strength (spectral flux), and the time of each value */
export async function onsets(x: Float32Array, sr: number, yieldEvery = 4000) {
  const N = 1024;
  const HOP = Math.max(1, Math.round((64 * sr) / RATE));
  const frames = 1 + Math.floor((x.length - N) / HOP);
  const win = new Float32Array(N);
  for (let i = 0; i < N; i++)
    win[i] = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (N - 1));
  const fft = fftOf(N);
  const re = new Float64Array(N);
  const im = new Float64Array(N);
  const half = N / 2 + 1;
  let prev = new Float64Array(half);
  let cur = new Float64Array(half);
  const env = new Float64Array(Math.max(0, frames - 1));
  for (let f = 0; f < frames; f++) {
    const o = f * HOP;
    for (let i = 0; i < N; i++) {
      re[i] = x[o + i]! * win[i]!;
      im[i] = 0;
    }
    fft(re, im);
    let flux = 0;
    for (let k = 0; k < half; k++) {
      cur[k] = Math.log1p(100 * Math.hypot(re[k]!, im[k]!));
      if (f > 0) flux += Math.max(0, cur[k]! - prev[k]!);
    }
    if (f > 0) env[f - 1] = flux;
    [prev, cur] = [cur, prev];
    if (f % yieldEvery === 0) await new Promise((r) => setTimeout(r, 0));
  }
  // the slow swell removed: minus a 128-frame moving average
  const swell = movingAverage(env, 128);
  for (let i = 0; i < env.length; i++)
    env[i] = Math.max(0, env[i]! - swell[i]!);
  const p = percentile(env, 99.5) + 1e-9;
  for (let i = 0; i < env.length; i++) env[i]! /= p;
  const times = Array.from(env, (_, i) => ((i + 1) * HOP) / sr);
  return { env, times };
}

/** numpy's convolve(v, ones(m)/m, mode="same") */
function movingAverage(v: Float64Array, m: number): Float64Array {
  const out = new Float64Array(v.length);
  const off = Math.floor((m - 1) / 2);
  const cum = new Float64Array(v.length + 1);
  for (let i = 0; i < v.length; i++) cum[i + 1] = cum[i]! + v[i]!;
  for (let i = 0; i < v.length; i++) {
    const lo = Math.max(0, i + off - m + 1);
    const hi = Math.min(v.length, i + off + 1);
    out[i] = (cum[hi]! - cum[lo]!) / m;
  }
  return out;
}

function percentile(v: Float64Array, q: number): number {
  const s = Float64Array.from(v).sort();
  const pos = ((s.length - 1) * q) / 100;
  const lo = Math.floor(pos);
  return s[lo]! + (s[Math.min(s.length - 1, lo + 1)]! - s[lo]!) * (pos - lo);
}

/** numpy's interp: linear, clamped at the ends */
function interp(
  t: number,
  xs: ArrayLike<number>,
  ys: ArrayLike<number>,
): number {
  const n = xs.length;
  if (t <= xs[0]!) return ys[0]!;
  if (t >= xs[n - 1]!) return ys[n - 1]!;
  let lo = 0;
  let hi = n - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (xs[mid]! <= t) lo = mid;
    else hi = mid;
  }
  const k = (t - xs[lo]!) / (xs[hi]! - xs[lo]! || 1);
  return ys[lo]! + (ys[hi]! - ys[lo]!) * k;
}

/**
 * The tempo, from how the onsets repeat: the autocorrelation peak between
 * 70 and 180 BPM (refined between frames), and where its beats fall.
 */
function estimateGrid(
  env: Float64Array,
  times: number[],
): { bpm: number; downbeat: number } {
  const dt = times[1]! - times[0]!;
  const lagOf = (bpm: number) => 60 / bpm / dt;
  const ac = (lag: number) => {
    let s = 0;
    for (let i = 0; i + lag < env.length; i++) s += env[i]! * env[i + lag]!;
    return s;
  };
  let best = 0;
  let bestLag = 0;
  for (let lag = Math.floor(lagOf(180)); lag <= Math.ceil(lagOf(70)); lag++) {
    const v = ac(lag);
    if (v > best) [best, bestLag] = [v, lag];
  }
  const [a, b, c] = [ac(bestLag - 1), best, ac(bestLag + 1)];
  const shift = (a - c) / (2 * (a - 2 * b + c) || 1);
  const beat = (bestLag + shift) * dt;
  // the phase of the beat, by circular mean of the onsets
  let zr = 0;
  let zi = 0;
  env.forEach((w, i) => {
    const ph = (2 * Math.PI * times[i]!) / beat;
    zr += w * Math.cos(ph);
    zi += w * Math.sin(ph);
  });
  const phase = ((Math.atan2(zi, zr) / (2 * Math.PI)) * beat + beat) % beat;
  return { bpm: round(60 / beat, 2), downbeat: round(phase, 3) };
}

/**
 * Measure a mono mix. `bpm` and `downbeat` place the bar grid (the first
 * downbeat's second); leave them out to have them estimated.
 */
export async function measure(
  x: Float32Array,
  sr: number,
  grid: { bpm?: number; downbeat?: number } = {},
): Promise<MixMeasure> {
  const duration = x.length / sr;
  const { env, times } = await onsets(x, sr);
  const guess =
    grid.bpm && grid.downbeat !== undefined
      ? undefined
      : estimateGrid(env, times);
  const bpm = grid.bpm || guess!.bpm;
  const downbeat = grid.downbeat ?? guess!.downbeat;

  const beat = 60 / bpm;
  const six = beat / 4;
  const pt: number[] = [];
  const pw: number[] = [];
  for (let i = 0; i < env.length; i++) {
    const v = env[i]!;
    const before = env[(i - 1 + env.length) % env.length]!;
    const after = env[(i + 1) % env.length]!;
    if (v > before && v >= after && v > 0.4) {
      pt.push(times[i]!);
      pw.push(v);
    }
  }
  const phase = pt.map((t) => mod((t - downbeat) / six + 0.5, 1) - 0.5);

  // the offset curve: 8 s windows every 2 s, weighted circular mean
  const centres: number[] = [];
  for (let c = 0; c < duration + 2; c += 2) centres.push(c);
  const raw = centres.map((c) => {
    let n = 0;
    let zr = 0;
    let zi = 0;
    let ws = 0;
    pt.forEach((t, i) => {
      if (Math.abs(t - c) >= 4) return;
      n++;
      zr += pw[i]! * Math.cos(2 * Math.PI * phase[i]!);
      zi += pw[i]! * Math.sin(2 * Math.PI * phase[i]!);
      ws += pw[i]!;
    });
    if (n < 6) return NaN;
    return Math.hypot(zr, zi) / ws > 0.5
      ? (Math.atan2(zi, zr) / (2 * Math.PI)) * six
      : NaN;
  });
  const gx = centres.filter((_, i) => !Number.isNaN(raw[i]));
  const gy = raw.filter((v) => !Number.isNaN(v));
  const filled = gx.length
    ? centres.map((c) => interp(c, gx, gy))
    : centres.map(() => 0);
  // ±4 s smoothing, edges held
  const offs = filled.map((_, i) => {
    let s = 0;
    for (let j = -2; j <= 2; j++)
      s += filled[Math.min(filled.length - 1, Math.max(0, i + j))]!;
    return s / 5;
  });

  const eighth = beat / 2;
  const smooth = movingAverage(env, 5);
  const eighths: number[] = [];
  const strength: number[] = [];
  const level: number[] = [];
  const k0 = -Math.floor(downbeat / eighth);
  const k1 = Math.floor((duration - downbeat) / eighth);
  for (let k = k0; k <= k1; k++) {
    const g = downbeat + eighth * k;
    if (g < 0 || g > duration) continue;
    const e = g + interp(g, centres, offs);
    eighths.push(round(e, 4));
    strength.push(round(Math.min(1, Math.max(0, interp(e, times, smooth))), 3));
    level.push((mod(k, 2) === 0 ? 1 : 0) + (mod(k, 8) === 0 ? 1 : 0));
  }
  return {
    duration: round(duration, 3),
    peaks: loudness(x),
    bpm,
    downbeat,
    eighths,
    strength,
    beat: level,
  };
}

function mod(a: number, n: number): number {
  return ((a % n) + n) % n;
}

function round(v: number, d: number): number {
  const p = 10 ** d;
  return Math.round(v * p) / p;
}

/** an in-place radix-2 complex FFT of size n */
function fftOf(n: number) {
  const bits = Math.log2(n);
  const rev = new Uint32Array(n);
  for (let i = 0; i < n; i++) {
    let r = 0;
    for (let b = 0; b < bits; b++) r |= ((i >> b) & 1) << (bits - 1 - b);
    rev[i] = r;
  }
  const cos = new Float64Array(n / 2);
  const sin = new Float64Array(n / 2);
  for (let i = 0; i < n / 2; i++) {
    cos[i] = Math.cos((-2 * Math.PI * i) / n);
    sin[i] = Math.sin((-2 * Math.PI * i) / n);
  }
  return (re: Float64Array, im: Float64Array) => {
    for (let i = 0; i < n; i++) {
      const j = rev[i]!;
      if (j > i) {
        [re[i], re[j]] = [re[j]!, re[i]!];
        [im[i], im[j]] = [im[j]!, im[i]!];
      }
    }
    for (let size = 2; size <= n; size *= 2) {
      const step = n / size;
      const h = size / 2;
      for (let s = 0; s < n; s += size) {
        for (let k = 0; k < h; k++) {
          const c = cos[k * step]!;
          const si = sin[k * step]!;
          const a = s + k;
          const b = a + h;
          const tr = re[b]! * c - im[b]! * si;
          const ti = re[b]! * si + im[b]! * c;
          re[b] = re[a]! - tr;
          im[b] = im[a]! - ti;
          re[a]! += tr;
          im[a]! += ti;
        }
      }
    }
  };
}

/* ---- kept on the card as text: numbers separated by spaces ---------- */

export function packNumbers(v: readonly number[]): string {
  return v.join(' ');
}

export function unpackNumbers(s: string | null | undefined): number[] {
  return (s ?? '').trim().split(/\s+/).filter(Boolean).map(Number);
}

/** the seconds where notes start: peaks of the onset strength above `floor` */
export function onsetTimes(
  env: Float64Array,
  times: number[],
  floor = 0.3,
): number[] {
  const out: number[] = [];
  for (let i = 1; i + 1 < env.length; i++) {
    if (env[i]! > floor && env[i]! > env[i - 1]! && env[i]! >= env[i + 1]!)
      out.push(times[i]!);
  }
  return out;
}
