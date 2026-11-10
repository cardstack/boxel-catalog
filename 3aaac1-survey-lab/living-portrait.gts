// A living portrait: one AI-generated photo brought to life. The studio makes
// a base portrait, then edits of that same photo (eyes closed, two mouth
// shapes, a smile) and a depth map. The stage cuts the photo into three flat
// layers (background, hair and shoulders, face) and lays each edit over the
// face as a patch of only the pixels it changed. Choreo performs the whole
// thing from a score: blinks, syllable-timed mouth shapes, the smile,
// breathing, a slow camera drift and a push-in. The pointer adds parallax on
// top. Every image is AI-generated: the person does not exist.
import window from 'ember-window-mock';
import {
  CardDef,
  Component,
  field,
  contains,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import NumberField from '@cardstack/base/number';
import { tracked } from '@glimmer/tracking';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
// @ts-ignore the host provides Choreo; its types aren't bundled with the CLI
import { Choreo } from '@cardstack/choreo';
// @ts-ignore as above
import type { ChoreoRun } from '@cardstack/choreo';
// @ts-ignore the host provides glimmer-motion; its types aren't bundled with the CLI
import { motion } from 'glimmer-motion';
import SparklesIcon from '@cardstack/boxel-icons/sparkles';
import SendRequestViaProxyCommand from '@cardstack/boxel-host/tools/send-request-via-proxy';
import WriteBinaryFileCommand from '@cardstack/boxel-host/tools/write-binary-file';
import { listen, send } from './stage-bus';
import type { SceneMsg } from './stage-bus';

const MODEL = 'google/gemini-2.5-flash-image';

function inPrerender() {
  return Boolean((globalThis as any).__boxelRenderContext);
}

// ─── the images the studio makes ─────────────────────────────────────────
type Slot = 'base' | 'blink' | 'mouthA' | 'mouthO' | 'smile' | 'depth';
const KEEP =
  'Edit this exact photo. Keep everything else identical: the same person, framing, head position, pose, hair, clothes, lighting, colours and background, pixel for pixel. Only change:';
const SLOTS: { key: Slot; label: string; edit?: string }[] = [
  { key: 'base', label: 'The portrait' },
  {
    key: 'blink',
    label: 'Eyes closed',
    edit: `${KEEP} her eyes are gently closed, as in the middle of a natural blink. Mouth stays closed.`,
  },
  {
    key: 'mouthA',
    label: 'Mouth: "ah"',
    edit: `${KEEP} her mouth is open as if saying "ah" mid-sentence, relaxed, upper teeth just visible. Eyes stay open.`,
  },
  {
    key: 'mouthO',
    label: 'Mouth: "oo"',
    edit: `${KEEP} her lips are softly rounded as if saying "oo" mid-sentence. Eyes stay open.`,
  },
  {
    key: 'smile',
    label: 'Smile',
    edit: `${KEEP} she gives a warm, natural closed-mouth smile; her cheeks lift a little. Eyes stay open.`,
  },
  {
    key: 'depth',
    label: 'Depth map',
    edit: 'Make a depth map of this exact photo: the same framing, as a smooth greyscale image where the nearest parts (the tip of the nose, the face) are white and the farthest parts (the background) are black. Soft gradients, no texture, no text, no outlines.',
  },
];
// image paths may be relative to the card (so a copied workspace keeps working)
const abs = (u: any, base: string) => (u ? new URL(String(u), base).href : u);
const FIELD: Record<Slot, string> = {
  base: 'baseImage',
  blink: 'blinkImage',
  mouthA: 'mouthAImage',
  mouthO: 'mouthOImage',
  smile: 'smileImage',
  depth: 'depthImage',
};

// ─── the performance: what she says, and when ────────────────────────────
// A performance is a list of her lines (and, in a scene, the other card's
// lines she listens to), baked into Choreo tracks by makePerformance.
type Said = {
  at: number;
  text: string;
  dur: number;
  smile?: boolean;
  mine: boolean;
};
const CPS = 14; // characters a second
const INTRO: Said[] = [
  { at: 1.2, text: 'Hi. I am not a video.' },
  { at: 4.4, text: 'I am one photograph, and five edits of it.' },
  { at: 8.4, text: 'Move your cursor. I am cut into three layers.' },
  { at: 13.2, text: 'Every blink and every word is a patch of pixels.' },
  { at: 17.6, text: 'And Choreo is the one who directs me.', smile: true },
].map((l) => ({ ...l, dur: l.text.length / CPS, mine: true }));
function readVoicePref() {
  try {
    return window.localStorage.getItem('living-portrait-voice') === 'on';
  } catch {
    return false;
  }
}
const STEP = 1 / 30;
const DEPTH: Record<string, number> = { back: 3, body: 9, face: 15 };
const smooth = (x: number) => {
  const c = Math.max(0, Math.min(1, x));
  return c * c * (3 - 2 * c);
};
const breath = (t: number) => Math.sin((t / 3.8) * Math.PI * 2);
type Track = {
  id: string;
  prop: 'opacity' | 'x' | 'y' | 'scale';
  values: number[];
  times: number[];
};
type Performance = {
  total: number;
  tracks: Track[];
  captionAt: (t: number) => string;
};

function makePerformance(
  said: Said[],
  total: number,
  scene = false,
): Performance {
  const mine = said.filter((l) => l.mine);
  const captionAt = (t: number) => {
    let cur: Said | null = null;
    for (const l of mine) if (t >= l.at) cur = l;
    if (!cur || (scene && t > cur.at + cur.dur + 0.8)) return '';
    return cur.text.slice(
      0,
      Math.min(
        cur.text.length,
        Math.floor(((t - cur.at) / cur.dur) * cur.text.length),
      ),
    );
  };
  // a syllable is a run of vowels: the mouth opens once per syllable, as the
  // caption types it. Rounded vowels make the "oo" shape, the rest "ah"
  const syls: { at: number; shape: 'a' | 'o'; amp: number }[] = [];
  for (const l of mine) {
    const re = /[aeiouy]+/gi;
    let m: RegExpExecArray | null;
    while ((m = re.exec(l.text))) {
      const v = m[0].toLowerCase();
      syls.push({
        at: l.at + ((m.index + v.length / 2) / l.text.length) * l.dur,
        shape: /[ou]/.test(v) && !/a/.test(v) ? 'o' : 'a',
        amp: v === 'i' || v === 'y' ? 0.6 : 1,
      });
    }
  }
  // each syllable is a smooth bump, about a sixth of a second wide
  const mouthAt = (t: number) => {
    let a = 0;
    let o = 0;
    for (const s of syls) {
      const u = (t - s.at) / 0.17;
      if (u <= -1 || u >= 1) continue;
      const w = s.amp * (0.5 + 0.5 * Math.cos(u * Math.PI));
      if (s.shape === 'a') a = Math.max(a, w);
      else o = Math.max(o, w);
    }
    return { a: Math.min(1, a), o: Math.min(1, o) };
  };
  // she smiles from a smiling line's last words until the next line starts
  const smileAt = (t: number) => {
    let w = 0;
    said.forEach((l, i) => {
      if (!l.smile) return;
      const from = l.mine ? l.at + l.dur * 0.6 : l.at + 0.3;
      const until = said[i + 1]?.at ?? total + 1;
      w = Math.max(
        w,
        Math.min(smooth((t - from) / 0.5), smooth((until - t) / 0.5)),
      );
    });
    return w;
  };
  // where her attention is: toward the other card (left) while it talks
  const lookAt = (t: number) => {
    if (!scene) return Math.sin((t / total) * Math.PI * 1.5 - 0.6);
    let w = 0;
    for (const l of said)
      if (!l.mine)
        w = Math.max(
          w,
          Math.min(
            smooth((t - l.at + 0.3) / 0.6),
            smooth((l.at + l.dur + 0.4 - t) / 0.6),
          ),
        );
    return -0.9 * w + 0.15;
  };
  const sampled = (
    id: string,
    prop: Track['prop'],
    f: (t: number) => number,
  ): Track => {
    const values: number[] = [];
    const times: number[] = [];
    for (let t = 0; t <= total + 1e-9; t += STEP) {
      times.push(Math.min(1, t / total));
      values.push(Number(f(t).toFixed(3)));
    }
    times[times.length - 1] = 1;
    return { id, prop, values, times };
  };
  // a blink is a cut, not a fade (half-closed would be a double exposure)
  const blinkTrack = (): Track => {
    const values = [0];
    const times = [0];
    for (let b = 0.8; b < total - 0.3; b += 2.5 + ((b * 7.3) % 1.9)) {
      values.push(0, 1, 1, 0);
      times.push(
        b / total,
        (b + 0.001) / total,
        (b + 0.13) / total,
        (b + 0.131) / total,
      );
    }
    values.push(0);
    times.push(1);
    return { id: 'p-blink', prop: 'opacity', values, times };
  };
  const last = mine[mine.length - 1];
  const tracks: Track[] = [
    sampled('p-mouthA', 'opacity', (t) => mouthAt(t).a),
    sampled('p-mouthO', 'opacity', (t) => mouthAt(t).o),
    sampled('p-smile', 'opacity', smileAt),
    blinkTrack(),
    ...(['back', 'body', 'face'] as const).flatMap((l) => [
      sampled(l, 'x', (t) => lookAt(t) * DEPTH[l] * 0.7),
      sampled(
        l,
        'y',
        (t) =>
          -breath(t - (l === 'face' ? 0.15 : 0)) *
          (l === 'back' ? 0 : l === 'body' ? 1.2 : 1.6),
      ),
    ]),
    // the camera pushes in on her last line
    sampled(
      'rig',
      'scale',
      (t) => 1.05 + (last ? 0.05 * smooth((t - last.at + 0.6) / 3.5) : 0),
    ),
  ];
  return { total, tracks, captionAt };
}
const INTRO_PERF = makePerformance(INTRO, 23);

// through an image element, as the page shows them: the workspace and the app
// share an origin, so the pixels stay readable. A just-saved file can 404
// for a moment, so it retries
async function loadImage(url: string): Promise<ImageBitmap> {
  for (let i = 0; ; i++) {
    try {
      const img = new Image();
      img.decoding = 'async';
      await new Promise<void>((ok, fail) => {
        img.onload = () => ok();
        img.onerror = () =>
          fail(new Error(`couldn't load ${url.split('/').pop()}`));
        img.src = url;
      });
      return await createImageBitmap(img);
    } catch (e) {
      if (i >= 3) throw e;
      await new Promise((ok) => setTimeout(ok, 1500));
    }
  }
}
// Gemini's edits drift: the face can come back a little larger or shifted.
// Find the scale and shift that best lay the edit over the base (coarse
// search, then a fine one), comparing small greyscale copies
type Fit = { s: number; dx: number; dy: number };
function grey(img: CanvasImageSource, gw: number, gh: number) {
  const c = document.createElement('canvas');
  c.width = gw;
  c.height = gh;
  const x = c.getContext('2d', { willReadFrequently: true })!;
  x.drawImage(img, 0, 0, gw, gh);
  const d = x.getImageData(0, 0, gw, gh).data;
  const g = new Float32Array(gw * gh);
  for (let i = 0; i < g.length; i++)
    g[i] = (d[i * 4] * 0.3 + d[i * 4 + 1] * 0.59 + d[i * 4 + 2] * 0.11) / 255;
  return g;
}
function cost(
  a: Float32Array,
  b: Float32Array,
  gw: number,
  gh: number,
  f: Fit,
) {
  const cx = gw / 2;
  const cy = gh / 2;
  let sum = 0;
  let n = 0;
  for (let y = 1; y < gh - 1; y += 1) {
    for (let x = 1; x < gw - 1; x += 1) {
      const qx = Math.round(cx + (x - cx - f.dx) / f.s);
      const qy = Math.round(cy + (y - cy - f.dy) / f.s);
      if (qx < 0 || qy < 0 || qx >= gw || qy >= gh) continue;
      sum += Math.abs(a[y * gw + x] - b[qy * gw + qx]);
      n++;
    }
  }
  return n > gw * gh * 0.6 ? sum / n : 1e9;
}
function align(base: ImageBitmap, edit: ImageBitmap): Fit {
  const coarse = (
    gw: number,
    gh: number,
    ss: number[],
    r: number,
    around: Fit,
  ) => {
    const a = grey(base, gw, gh);
    const b = grey(edit, gw, gh);
    let best = around;
    let bc = 1e9;
    for (const s of ss)
      for (let dx = -r; dx <= r; dx++)
        for (let dy = -r; dy <= r; dy++) {
          const f = { s, dx: around.dx + dx, dy: around.dy + dy };
          const c = cost(a, b, gw, gh, f);
          if (c < bc) {
            bc = c;
            best = f;
          }
        }
    return best;
  };
  const h48 = Math.round((48 * base.height) / base.width);
  const ss1: number[] = [];
  for (let s = 0.84; s <= 1.2; s += 0.02) ss1.push(s);
  const f1 = coarse(48, h48, ss1, 6, { s: 1, dx: 0, dy: 0 });
  const h96 = Math.round((96 * base.height) / base.width);
  const ss2: number[] = [];
  for (let s = f1.s - 0.02; s <= f1.s + 0.0201; s += 0.005) ss2.push(s);
  const f2 = coarse(96, h96, ss2, 2, { s: f1.s, dx: f1.dx * 2, dy: f1.dy * 2 });
  // as fractions of the picture, so they apply at any size
  return { s: f2.s, dx: f2.dx / 96, dy: f2.dy / h96 };
}
// where each edit is allowed to show, as [x0, y0, x1, y1] fractions of the portrait
type Box = [number, number, number, number];
const REGIONS: Record<string, Box> = {
  blink: [0.35, 0.32, 0.65, 0.42],
  mouthA: [0.39, 0.44, 0.61, 0.56],
  mouthO: [0.39, 0.44, 0.61, 0.56],
  smile: [0.34, 0.39, 0.66, 0.57],
};
// an edit, laid over the base, carrying a mask in its alpha: where it really
// differs from the base, inside its region, with soft edges
function masked(
  base: ImageBitmap,
  edit: ImageBitmap,
  w: number,
  h: number,
  box: Box,
): HTMLCanvasElement {
  const f = align(base, edit);
  const out = document.createElement('canvas');
  out.width = w;
  out.height = h;
  const ox = out.getContext('2d', { willReadFrequently: true })!;
  ox.translate(w / 2 + f.dx * w, h / 2 + f.dy * h);
  ox.scale(f.s, f.s);
  ox.translate(-w / 2, -h / 2);
  ox.drawImage(edit, 0, 0, w, h);
  ox.setTransform(1, 0, 0, 1, 0, 0);
  const bc = document.createElement('canvas');
  bc.width = w;
  bc.height = h;
  const bx = bc.getContext('2d', { willReadFrequently: true })!;
  bx.drawImage(base, 0, 0, w, h);
  const A = bx.getImageData(0, 0, w, h).data;
  const E = ox.getImageData(0, 0, w, h);
  const [x0, y0, x1, y1] = box;
  const feather = 0.025;
  const soft = (v: number, lo: number, hi: number) =>
    Math.max(0, Math.min(1, (v - lo) / feather, (hi - v) / feather));
  for (let y = 0; y < h; y++) {
    const fy = soft(y / h, y0, y1);
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      const fxy = fy * soft(x / w, x0, x1);
      if (fxy <= 0) {
        E.data[i + 3] = 0;
        continue;
      }
      const d =
        Math.max(
          Math.abs(A[i] - E.data[i]),
          Math.abs(A[i + 1] - E.data[i + 1]),
          Math.abs(A[i + 2] - E.data[i + 2]),
        ) / 255;
      // inside the region, take the edit wherever it changed; the blur below
      // grows that into a smooth patch
      E.data[i + 3] = Math.round(
        fxy * Math.max(0, Math.min(1, (d - 0.04) / 0.08)) * 255,
      );
    }
  }
  ox.putImageData(E, 0, 0);
  // soften the mask: redraw the alpha blurred, keep the colour
  const m = document.createElement('canvas');
  m.width = w;
  m.height = h;
  const mx = m.getContext('2d')!;
  mx.filter = `blur(${Math.max(2, Math.round(w / 120))}px)`;
  mx.drawImage(out, 0, 0);
  const col = document.createElement('canvas');
  col.width = w;
  col.height = h;
  const cx = col.getContext('2d')!;
  cx.translate(w / 2 + f.dx * w, h / 2 + f.dy * h);
  cx.scale(f.s, f.s);
  cx.translate(-w / 2, -h / 2);
  cx.drawImage(edit, 0, 0, w, h);
  cx.setTransform(1, 0, 0, 1, 0, 0);
  cx.globalCompositeOperation = 'destination-in';
  cx.drawImage(m, 0, 0);
  return col;
}

// cut a canvas out of the photo through a mask (alpha = keep)
function cutout(
  photo: ImageBitmap,
  w: number,
  h: number,
  mask: (x: number, y: number) => number,
) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const x = c.getContext('2d', { willReadFrequently: true })!;
  x.drawImage(photo, 0, 0, w, h);
  const d = x.getImageData(0, 0, w, h);
  for (let j = 0; j < h; j++)
    for (let i = 0; i < w; i++)
      d.data[(j * w + i) * 4 + 3] = Math.round(255 * mask(i / w, j / h));
  x.putImageData(d, 0, 0);
  return c;
}
// the person: lighter than the background in the depth map. Thresholds come
// from the map itself (its corners are background, its centre is her)
function personMask(depth: ImageBitmap | undefined, w: number, h: number) {
  if (!depth)
    return (x: number, y: number) =>
      smooth(1 - Math.hypot((x - 0.5) / 0.42, (y - 0.62) / 0.62));
  const gw = 64;
  const gh = Math.round((64 * h) / w);
  const c = document.createElement('canvas');
  c.width = gw;
  c.height = gh;
  const x = c.getContext('2d', { willReadFrequently: true })!;
  x.filter = 'blur(1.5px)';
  x.drawImage(depth, 0, 0, gw, gh);
  const d = x.getImageData(0, 0, gw, gh).data;
  const at = (i: number, j: number) => d[(j * gw + i) * 4] / 255;
  const bg =
    (at(2, 2) +
      at(gw - 3, 2) +
      at(2, Math.round(gh * 0.3)) +
      at(gw - 3, Math.round(gh * 0.3))) /
    4;
  const fg = at(gw >> 1, Math.round(gh * 0.4));
  const lo = bg + (fg - bg) * 0.3;
  const hi = bg + (fg - bg) * 0.55;
  return (u: number, v: number) => {
    const i = Math.min(gw - 1, Math.max(0, u * gw - 0.5));
    const j = Math.min(gh - 1, Math.max(0, v * gh - 0.5));
    const i0 = Math.floor(i);
    const j0 = Math.floor(j);
    const fi = i - i0;
    const fj = j - j0;
    const g = (a: number, b: number) =>
      at(Math.min(gw - 1, a), Math.min(gh - 1, b));
    const val =
      g(i0, j0) * (1 - fi) * (1 - fj) +
      g(i0 + 1, j0) * fi * (1 - fj) +
      g(i0, j0 + 1) * (1 - fi) * fj +
      g(i0 + 1, j0 + 1) * fi * fj;
    return smooth((val - lo) / Math.max(0.02, hi - lo));
  };
}
// the face: a soft oval around the eyes, nose, mouth and chin
const faceMask = (x: number, y: number) =>
  smooth((1 - Math.hypot((x - 0.5) / 0.165, (y - 0.43) / 0.2)) / 0.35);

class Isolated extends Component<typeof LivingPortrait> {
  @tracked perf: Performance = INTRO_PERF;
  get tracks() {
    return this.perf.tracks;
  }
  get total() {
    return this.perf.total;
  }
  // a new performance rebuilds the Choreo region, so no old tween lingers
  get takes() {
    return [this.perf];
  }
  private pendingStart = 0;
  private stopListening: (() => void) | null = null;
  // in a scene, the other card calls; she answers when her layers are ready
  // the name this portrait answers to on the bus: its title (Mei, Sam, Pip…)
  get who() {
    return String(this.m.title || 'Mei').toLowerCase();
  }
  private hear = (m: SceneMsg) => {
    if (m.kind === 'ping')
      send({ kind: 'here', who: this.who, ready: this.ready });
    if (m.kind === 'scene') {
      const said = m.lines.map((l) => ({
        at: l.at,
        dur: l.dur,
        text: l.text,
        mine: String(l.speaker).toLowerCase() === this.who,
        smile: ['happy', 'delighted', 'playful', 'shy'].includes(l.mood ?? ''),
      }));
      this.perf = makePerformance(said, m.total, true);
      this.t = 0;
      this.playing = false;
      this.pendingStart = m.startAt;
      this.speak(
        said.filter((l) => l.mine),
        m.startAt,
      );
    }
  };

  // ─── an optional voice: the browser's own speech, tuned per character ──
  @tracked voiceOn = readVoicePref();
  private voiceTimers: ReturnType<typeof setTimeout>[] = [];
  toggleVoice = () => {
    this.voiceOn = !this.voiceOn;
    try {
      window.localStorage.setItem(
        'living-portrait-voice',
        this.voiceOn ? 'on' : 'off',
      );
    } catch {
      // a private window: the choice lasts for this page only
    }
    if (!this.voiceOn) this.hush();
  };
  private hush() {
    this.voiceTimers.forEach((t) => clearTimeout(t));
    this.voiceTimers = [];
    try {
      speechSynthesis.cancel();
    } catch {
      // no speech in this browser
    }
  }
  private pickVoice(): SpeechSynthesisVoice | null {
    try {
      const voices = speechSynthesis
        .getVoices()
        .filter((v) => v.lang.startsWith('en'));
      const hints = String(this.m.voiceHints ?? '')
        .split(',')
        .map((h) => h.trim().toLowerCase())
        .filter(Boolean);
      for (const h of hints) {
        const v = voices.find((x) => x.name.toLowerCase().includes(h));
        if (v) return v;
      }
      return voices[0] ?? null;
    } catch {
      return null;
    }
  }
  private speak(lines: { at: number; text: string }[], startAt: number) {
    this.hush();
    if (!this.voiceOn || typeof speechSynthesis === 'undefined') return;
    const voice = this.pickVoice();
    for (const l of lines) {
      const delay = Math.max(0, startAt + l.at * 1000 - performance.now());
      this.voiceTimers.push(
        setTimeout(() => {
          const u = new SpeechSynthesisUtterance(l.text);
          if (voice) u.voice = voice;
          u.pitch = Number(this.m.voicePitch) || 1;
          u.rate = Number(this.m.voiceRate) || 1;
          speechSynthesis.speak(u);
        }, delay),
      );
    }
  }
  @tracked playing = false;
  @tracked caption = '';
  @tracked busy = '';
  @tracked error = '';
  @tracked ready = false;
  @tracked now = 0;
  private t = 0;
  private last = 0;
  private raf = 0;
  private alive = true;
  private c: { run: ChoreoRun | null } | null = null;
  private run: ChoreoRun | null = null;
  private rig: HTMLElement | null = null;
  private look = { x: 0, y: 0, tx: 0, ty: 0 };
  private layers: Record<string, HTMLCanvasElement> = {};
  private loadedFor = '';

  constructor(owner: Owner, args: any) {
    super(owner, args);
    if (inPrerender()) return;
    this.stopListening = listen(this.hear);
    // the performance's frame loop: a paint callback, not state scheduling
    // eslint-disable-next-line @cardstack/boxel/no-raf-for-state
    this.raf = requestAnimationFrame(this.frame);
  }
  willDestroy() {
    super.willDestroy();
    this.alive = false;
    cancelAnimationFrame(this.raf);
    this.stopListening?.();
    this.hush();
  }
  get baseSrc() {
    return abs(this.m.baseImage, this.m.id);
  }
  get ctx() {
    return (
      (this.args.context as any)?.toolContext ??
      (this.args.context as any)?.commandContext
    );
  }
  get m() {
    return this.args.model as any;
  }
  get rows() {
    return SLOTS.map((s) => ({
      ...s,
      url: abs(this.m[FIELD[s.key]], this.m.id) as string | undefined,
      canMake: s.key === 'base' || !!this.m.baseImage,
    }));
  }
  get complete() {
    return SLOTS.every((s) => this.m[FIELD[s.key]]);
  }

  wire = modifier((_el: Element, [c]: [{ run: ChoreoRun | null }]) => {
    this.c = c;
  });
  registerRig = modifier((el: HTMLElement) => {
    this.rig = el;
  });
  // put a built layer's canvas into its slot once the layers are ready
  mount = modifier((el: HTMLElement, [name, ready]: [string, boolean]) => {
    const cv = ready ? this.layers[name] : null;
    if (cv && cv.parentElement !== el) {
      el.replaceChildren(cv);
    }
  });
  load = modifier((_el: HTMLElement, [key]: [string]) => {
    if (inPrerender() || !key || key === this.loadedFor) return;
    this.loadedFor = key;
    this.build();
  });
  point = (ev: Event) => {
    const e = ev as PointerEvent;
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    this.look.tx = ((e.clientX - r.left) / r.width - 0.5) * 2;
    this.look.ty = ((e.clientY - r.top) / r.height - 0.5) * 2;
  };
  leave = () => {
    this.look.tx = 0;
    this.look.ty = 0;
  };

  private async build() {
    this.ready = false;
    this.error = '';
    const m = this.m;
    if (!m.baseImage) return;
    try {
      const imgs: Partial<Record<Slot, ImageBitmap>> = {};
      // one at a time: the host's fetch handles a queue better than a burst
      for (const s of SLOTS) {
        const u = abs(m[FIELD[s.key]], m.id);
        if (!u) continue;
        imgs[s.key] = await loadImage(u);
      }
      if (!this.alive) return;
      const base = imgs.base!;
      const w = Math.min(900, base.width);
      const h = Math.round((w * base.height) / base.width);
      const person = personMask(imgs.depth, w, h);
      this.layers = {
        back: cutout(base, w, h, () => 1),
        body: cutout(base, w, h, person),
        face: cutout(
          base,
          w,
          h,
          (x, y) => faceMask(x, y) * Math.max(0.0, person(x, y)),
        ),
      };
      for (const k of ['smile', 'mouthA', 'mouthO', 'blink'] as const) {
        const img = imgs[k];
        if (img) this.layers[k] = masked(base, img, w, h, REGIONS[k]);
      }
      this.ready = true;
    } catch (e: any) {
      this.error = `The portrait didn't load: ${e?.message ?? e}`;
    }
  }

  frame = (ms: number) => {
    if (!this.alive) return;
    const dt = this.last ? Math.min((ms - this.last) / 1000, 0.1) : 0;
    this.last = ms;
    if (this.pendingStart && performance.now() >= this.pendingStart) {
      this.t = (performance.now() - this.pendingStart) / 1000;
      this.pendingStart = 0;
      this.playing = true;
    }
    if (this.playing) {
      this.t = Math.min(this.total, this.t + dt);
      if (this.t >= this.total) this.playing = false;
    }
    // Choreo's run is held paused and told the time: the score is the clock
    const run = this.c?.run ?? null;
    if (run) {
      if (run !== this.run) {
        this.run = run;
        run.pause();
      }
      if (!run.paused) run.pause();
      if (Math.abs(run.time - this.t) > 1e-3) run.time = this.t;
    }
    const k = 1 - Math.exp(-dt * 5);
    this.look.x += (this.look.tx - this.look.x) * k;
    this.look.y += (this.look.ty - this.look.y) * k;
    if (this.rig) {
      this.rig.style.setProperty('--lx', this.look.x.toFixed(3));
      this.rig.style.setProperty('--ly', this.look.y.toFixed(3));
    }
    const cap = this.perf.captionAt(this.t);
    if (cap !== this.caption) this.caption = cap;
    if (
      Math.abs(this.now - this.t) > 0.05 ||
      (this.t === this.total && this.now !== this.total)
    )
      this.now = this.t;
    // the performance's frame loop: a paint callback, not state scheduling
    // eslint-disable-next-line @cardstack/boxel/no-raf-for-state
    this.raf = requestAnimationFrame(this.frame);
  };

  toggle = () => {
    if (!this.playing && this.t >= this.total) this.t = 0;
    this.playing = !this.playing;
  };
  restart = () => {
    this.t = 0;
    this.playing = true;
  };
  scrub = (e: Event) => {
    this.t = Number((e.target as HTMLInputElement).value);
    this.playing = false;
  };

  // ─── the studio ────────────────────────────────────────────────────────
  generate = async (slot: Slot) => {
    if (!this.ctx) {
      this.error =
        "This view can't make images. Open the card from its workspace.";
      return;
    }
    const s = SLOTS.find((x) => x.key === slot)!;
    this.error = '';
    this.busy = `Making “${s.label}”…`;
    try {
      const content: any[] = [];
      if (slot === 'base') {
        content.push({
          type: 'text',
          text:
            this.m.portraitPrompt ||
            'A photorealistic head-and-shoulders portrait.',
        });
      } else {
        const r = await fetch(abs(this.m.baseImage, this.m.id));
        const blob = await r.blob();
        const b64 = await blobToBase64(blob);
        content.push({ type: 'text', text: s.edit });
        // the workspace may not label the file's type: take it from the name
        const ext = (this.m.baseImage as string)
          .split('.')
          .pop()
          ?.toLowerCase();
        const mime =
          ext === 'jpg' || ext === 'jpeg'
            ? 'image/jpeg'
            : ext === 'webp'
              ? 'image/webp'
              : 'image/png';
        content.push({
          type: 'image_url',
          image_url: { url: `data:${mime};base64,${b64}` },
        });
      }
      const body: any = {
        model: MODEL,
        modalities: ['image', 'text'],
        messages: [{ role: 'user', content }],
      };
      if (slot === 'base') body.image_config = { aspect_ratio: '3:4' };
      const result = await new SendRequestViaProxyCommand(this.ctx).execute({
        url: 'https://openrouter.ai/api/v1/chat/completions',
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'HTTP-Referer': 'https://boxel.ai',
          'X-Title': 'Living portrait',
        },
        requestBody: JSON.stringify(body),
      } as any);
      const data = await parseProxyJson(result);
      const img = data?.choices?.[0]?.message?.images?.[0];
      const url: string | undefined =
        img?.image_url?.url ?? img?.imageUrl?.url ?? img?.url;
      const match = url?.match(
        /^data:(image\/[a-zA-Z0-9.+-]+);base64,([A-Za-z0-9+/=]+)$/,
      );
      if (!match) throw new Error('the model sent back no image');
      const [, type, b64] = match;
      const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
      this.m[FIELD[slot]] = await this.save(slot, new Blob([bytes], { type }));
      // a new base makes the old edits wrong: they were edits of another photo
      if (slot === 'base')
        for (const x of SLOTS)
          if (x.key !== 'base') this.m[FIELD[x.key]] = null;
    } catch (e: any) {
      this.error = `“${s.label}” failed: ${e?.message ?? e}`;
    } finally {
      this.busy = '';
    }
  };
  // saves an image as a JPEG (a tenth of a PNG's size: the stage loads six)
  private async save(slot: Slot, blob: Blob) {
    const bmp = await createImageBitmap(blob);
    const c = document.createElement('canvas');
    c.width = bmp.width;
    c.height = bmp.height;
    c.getContext('2d')!.drawImage(bmp, 0, 0);
    const jpg = await new Promise<Blob>((ok, fail) =>
      c.toBlob(
        (b) => (b ? ok(b) : fail(new Error('JPEG encode failed'))),
        'image/jpeg',
        0.9,
      ),
    );
    const written = await new WriteBinaryFileCommand(this.ctx).execute({
      realm: this.m[realmURL]?.href,
      path: `Portraits/${slugify(this.m.title || 'portrait')}-${slot}.jpg`,
      base64Content: await blobToBase64(jpg),
      contentType: 'image/jpeg',
      useNonConflictingFilename: true,
    } as any);
    const fileUrl = (written as any)?.fileIdentifier;
    if (!fileUrl) throw new Error('the image was made but not saved');
    return fileUrl as string;
  }
  // bring your own image for a slot (a photo you took, or a better edit)
  upload = async (slot: Slot, e: Event) => {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    if (!this.ctx) {
      this.error =
        "This view can't save files. Open the card from its workspace.";
      return;
    }
    this.error = '';
    this.busy = `Saving ${file.name}…`;
    try {
      this.m[FIELD[slot]] = await this.save(slot, file);
    } catch (err: any) {
      this.error = `Upload failed: ${err?.message ?? err}`;
    } finally {
      this.busy = '';
      input.value = '';
    }
  };
  generateMissing = async () => {
    for (const s of SLOTS) {
      if (!this.alive) return;
      if (!this.m[FIELD[s.key]]) await this.generate(s.key);
      if (this.error) return;
    }
  };

  get stageKey() {
    return SLOTS.map((s) => this.m[FIELD[s.key]] ?? '').join('|');
  }

  <template>
    <article class='lp'>
      <header class='head'>
        <p class='kicker'>LIVING PORTRAIT · ONE PHOTO · THREE LAYERS · CHOREO</p>
        <h1>{{@model.title}}</h1>
      </header>
      <div
        class='stage'
        {{on 'pointermove' this.point}}
        {{on 'pointerleave' this.leave}}
        {{this.load this.stageKey}}
      >
        {{#if @model.baseImage}}
          <img
            class='still {{if this.ready "gone"}}'
            src={{this.baseSrc}}
            alt=''
          />
          {{#each this.takes key='@identity' as |_take|}}
            <Choreo class='region {{if this.ready "on"}}' as |c|>
              <span class='wire' {{this.wire c}}></span>
              <div
                class='rig'
                {{this.registerRig}}
                {{motion id='rig' role='rig'}}
              >
                <div class='layer' {{motion id='back' role='back'}}><div
                    class='slot d-back'
                    {{this.mount 'back' this.ready}}
                  ></div></div>
                <div class='layer' {{motion id='body' role='body'}}><div
                    class='slot d-body'
                    {{this.mount 'body' this.ready}}
                  ></div></div>
                <div class='layer' {{motion id='face' role='face'}}>
                  <div class='slot d-face'>
                    <div class='patch' {{this.mount 'face' this.ready}}></div>
                    <div
                      class='patch'
                      {{motion id='p-smile' role='p-smile'}}
                      {{this.mount 'smile' this.ready}}
                    ></div>
                    <div
                      class='patch'
                      {{motion id='p-mouthA' role='p-mouthA'}}
                      {{this.mount 'mouthA' this.ready}}
                    ></div>
                    <div
                      class='patch'
                      {{motion id='p-mouthO' role='p-mouthO'}}
                      {{this.mount 'mouthO' this.ready}}
                    ></div>
                    <div
                      class='patch'
                      {{motion id='p-blink' role='p-blink'}}
                      {{this.mount 'blink' this.ready}}
                    ></div>
                  </div>
                </div>
              </div>
              <c.Parallel>
                <c.Wait @duration={{this.total}} />
                {{#each this.tracks as |q|}}
                  {{#if (eq q.prop 'opacity')}}
                    <c.Tween
                      @of={{c.id q.id}}
                      @opacity={{q.values}}
                      @times={{q.times}}
                      @duration={{this.total}}
                      @ease='linear'
                    />
                  {{else if (eq q.prop 'x')}}
                    <c.Tween
                      @of={{c.id q.id}}
                      @x={{q.values}}
                      @times={{q.times}}
                      @duration={{this.total}}
                      @ease='linear'
                    />
                  {{else if (eq q.prop 'y')}}
                    <c.Tween
                      @of={{c.id q.id}}
                      @y={{q.values}}
                      @times={{q.times}}
                      @duration={{this.total}}
                      @ease='linear'
                    />
                  {{else if (eq q.prop 'scale')}}
                    <c.Tween
                      @of={{c.id q.id}}
                      @scale={{q.values}}
                      @times={{q.times}}
                      @duration={{this.total}}
                      @ease='linear'
                    />
                  {{/if}}
                {{/each}}
              </c.Parallel>
            </Choreo>
          {{/each}}
          {{#if this.caption}}<p class='cap'>{{this.caption}}</p>{{/if}}
        {{else}}
          <div class='empty'>No portrait yet. Make one in the studio below.</div>
        {{/if}}
      </div>
      <div class='transport'>
        <button
          type='button'
          class='play'
          {{on 'click' this.toggle}}
          disabled={{if this.ready false true}}
        >{{if this.playing 'Pause' 'Play'}}</button>
        <button
          type='button'
          class='ghost'
          {{on 'click' this.restart}}
          disabled={{if this.ready false true}}
        >Restart</button>
        <button
          type='button'
          class='ghost {{if this.voiceOn "on"}}'
          aria-pressed={{if this.voiceOn 'true' 'false'}}
          {{on 'click' this.toggleVoice}}
        >{{if this.voiceOn 'Voice: on' 'Voice: off'}}</button>
        <input
          class='scrub'
          type='range'
          min='0'
          max={{this.total}}
          step='0.01'
          value={{this.now}}
          aria-label='Scrub'
          {{on 'input' this.scrub}}
        />
      </div>
      <p class='hint'>Move your cursor over the portrait. Choreo performs the
        score; the cursor adds parallax.</p>

      <section class='studio'>
        <h2>Studio</h2>
        <p class='fine'>Each image is made once by Gemini (through OpenRouter)
          and saved to this workspace. The edits all start from the portrait, so
          they line up with it. Every image is AI-generated; the person does not
          exist.</p>
        <ol class='rows'>
          {{#each this.rows as |r|}}
            <li class='row'>
              {{#if r.url}}<img
                  class='thumb'
                  src={{r.url}}
                  alt=''
                />{{else}}<span class='thumb none'></span>{{/if}}
              <span class='lbl'>{{r.label}}</span>
              <span class='acts'>
                <label class='ghost up'>Upload<input
                    type='file'
                    accept='image/*'
                    data-slot={{r.key}}
                    disabled={{if this.busy true false}}
                    {{on 'change' (fn this.upload r.key)}}
                  /></label>
                <button
                  type='button'
                  class='ghost'
                  disabled={{if this.busy true (if r.canMake false true)}}
                  {{on 'click' (fn this.generate r.key)}}
                >{{if r.url 'Make again' 'Make'}}</button>
              </span>
            </li>
          {{/each}}
        </ol>
        <button
          type='button'
          class='play'
          disabled={{if this.busy true (if this.complete true false)}}
          {{on 'click' this.generateMissing}}
        >Make everything that's missing</button>
        {{#if this.busy}}<p class='busy'>{{this.busy}}</p>{{/if}}
        {{#if this.error}}<p class='err'>{{this.error}}</p>{{/if}}
      </section>
    </article>
    <style scoped>
      .lp {
        --ink: #f3efe8;
        --mute: #a49d93;
        --acc: #ffd23f;
        background: #0d0c0b;
        color: var(--ink);
        font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
        padding: 20px;
        min-height: 100%;
        box-sizing: border-box;
      }
      .head h1 {
        margin: 2px 0 14px;
        font-size: 28px;
        letter-spacing: -0.01em;
      }
      .kicker {
        margin: 0;
        color: var(--acc);
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.08em;
      }
      .stage {
        position: relative;
        width: 100%;
        max-width: 560px;
        margin: 0 auto;
        aspect-ratio: 3 / 4;
        border-radius: 14px;
        overflow: hidden;
        background: #1a1816;
      }
      .still {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        transform: scale(1.05);
        transition: opacity 0.4s;
      }
      .still.gone {
        opacity: 0;
      }
      .region {
        position: absolute;
        inset: 0;
        opacity: 0;
        transition: opacity 0.4s;
      }
      .region.on {
        opacity: 1;
      }
      .wire {
        display: none;
      }
      .rig,
      .layer,
      .slot,
      .patch {
        position: absolute;
        inset: 0;
      }
      .rig {
        --lx: 0;
        --ly: 0;
      }
      .slot {
        will-change: transform;
      }
      .d-back {
        transform: translate3d(
          calc(var(--lx) * -3px),
          calc(var(--ly) * -2px),
          0
        );
      }
      .d-body {
        transform: translate3d(calc(var(--lx) * 7px), calc(var(--ly) * 4px), 0);
      }
      .d-face {
        transform: translate3d(
          calc(var(--lx) * 14px),
          calc(var(--ly) * 8px),
          0
        );
      }
      .patch :deep(canvas),
      .slot :deep(canvas) {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        display: block;
      }
      .patch {
        opacity: 1;
      }
      .stage {
        cursor: crosshair;
      }
      .scrub {
        flex: 1;
        max-width: 260px;
        accent-color: var(--acc);
      }
      .cap {
        position: absolute;
        left: 16px;
        right: 16px;
        bottom: 16px;
        margin: 0;
        padding: 10px 14px;
        border-radius: 10px;
        background: rgba(10, 9, 8, 0.72);
        backdrop-filter: blur(6px);
        font-size: 17px;
        line-height: 1.35;
        border-left: 3px solid var(--acc);
      }
      .empty {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        color: var(--mute);
        padding: 24px;
        text-align: center;
      }
      .transport {
        display: flex;
        gap: 8px;
        align-items: center;
        justify-content: center;
        margin: 12px 0 18px;
      }
      .hint {
        color: var(--mute);
        font-size: 13px;
        text-align: center;
        margin: -12px 0 20px;
      }
      button {
        font: inherit;
        font-size: 14px;
        border-radius: 999px;
        padding: 7px 16px;
        cursor: pointer;
        border: 1px solid #3a3631;
      }
      button:disabled {
        opacity: 0.45;
        cursor: default;
      }
      .play {
        background: var(--acc);
        color: #111;
        border-color: var(--acc);
        font-weight: 700;
      }
      .ghost {
        background: transparent;
        color: var(--ink);
      }
      .ghost.on {
        background: var(--ink);
        color: var(--paper, #111);
      }
      .studio {
        max-width: 560px;
        margin: 0 auto;
        border-top: 1px solid #2a2622;
        padding-top: 14px;
      }
      .studio h2 {
        font-size: 15px;
        margin: 0 0 4px;
      }
      .fine {
        color: var(--mute);
        font-size: 12.5px;
        line-height: 1.45;
        margin: 0 0 10px;
      }
      .rows {
        list-style: none;
        padding: 0;
        margin: 0 0 12px;
        display: grid;
        gap: 6px;
      }
      .row {
        display: grid;
        grid-template-columns: 40px 1fr auto;
        gap: 10px;
        align-items: center;
      }
      .thumb {
        width: 40px;
        height: 53px;
        object-fit: cover;
        border-radius: 6px;
      }
      .thumb.none {
        display: block;
        background: #1f1c19;
      }
      .lbl {
        font-size: 14px;
      }
      .acts {
        display: flex;
        gap: 6px;
      }
      .up {
        position: relative;
        font-size: 14px;
        border-radius: 999px;
        padding: 7px 16px;
        border: 1px solid #3a3631;
        cursor: pointer;
      }
      .up input {
        position: absolute;
        inset: 0;
        opacity: 0;
        cursor: pointer;
      }
      .busy {
        color: var(--acc);
        font-size: 13px;
      }
      .err {
        color: #ff7b7b;
        font-size: 13px;
      }
    </style>
  </template>
}

async function blobToBase64(blob: Blob) {
  const buf = new Uint8Array(await blob.arrayBuffer());
  let s = '';
  for (let i = 0; i < buf.length; i += 0x8000)
    s += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  return btoa(s);
}
function slugify(s: string) {
  return (
    s
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '') || 'portrait'
  );
}
async function parseProxyJson(result: any): Promise<any> {
  const response = result?.response ?? result;
  const ok = response?.ok ?? (response?.status ?? 200) < 400;
  if (!ok) {
    let body = '';
    try {
      body =
        typeof response.text === 'function'
          ? await response.text()
          : String(result.body ?? '');
    } catch {
      body = '';
    }
    throw new Error(
      `OpenRouter said ${response.status ?? '?'}: ${body.replace(/\\+/g, '').slice(0, 600)}`,
    );
  }
  if (typeof response.json === 'function') return response.json();
  if (typeof result.body === 'string') return JSON.parse(result.body);
  if (typeof response.body === 'string') return JSON.parse(response.body);
  return response;
}

class Fitted extends Component<typeof LivingPortrait> {
  get baseSrc() {
    return abs(this.args.model.baseImage, (this.args.model as any).id);
  }
  <template>
    <div class='f'>
      {{#if @model.baseImage}}<img src={{this.baseSrc}} alt='' />{{/if}}
      <span class='t'>{{@model.title}}</span>
    </div>
    <style scoped>
      .f {
        position: relative;
        width: 100%;
        height: 100%;
        overflow: hidden;
        background: #0d0c0b;
        color: #f3efe8;
        font-family: -apple-system, Arial, sans-serif;
      }
      img {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        object-position: 50% 25%;
      }
      .t {
        position: absolute;
        left: 8px;
        bottom: 8px;
        right: 8px;
        font-weight: 700;
        font-size: 13px;
        text-shadow: 0 1px 3px #000;
      }
    </style>
  </template>
}

export class LivingPortrait extends CardDef {
  static displayName = 'Living Portrait';
  static icon = SparklesIcon;
  @field title = contains(StringField);
  @field portraitPrompt = contains(TextAreaField);
  @field baseImage = contains(StringField);
  @field blinkImage = contains(StringField);
  @field mouthAImage = contains(StringField);
  @field mouthOImage = contains(StringField);
  @field smileImage = contains(StringField);
  @field depthImage = contains(StringField);
  // the optional voice: browser voice names to try in order, and its pitch and speed
  @field voiceHints = contains(StringField);
  @field voicePitch = contains(NumberField);
  @field voiceRate = contains(NumberField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: LivingPortrait) {
      return this.title;
    },
  });
  static isolated = Isolated;
  static fitted = Fitted;
  static embedded = Fitted;
}
