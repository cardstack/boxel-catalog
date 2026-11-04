/**
 * THE LYRIC VIDEO: one reel, two languages, one camera, four layers.
 *
 *   back     three.js (WebGPU, WebGL2 fallback): the shot's photo, the
 *            seams between shots, the look — split on the kick, a
 *            restrained bloom, liquid glass
 *   lyrics   a choreo scene per section per language, each holding
 *            <Lyric> phrases; the whole layer sits at its own depth under
 *            the same camera, so a pan moves it against the photo
 *   front    her cutout, nearer the lens than the words
 *   overlay  the cold open's title, the now-playing tag, the interlude and
 *            the outro, painted from t
 *
 * Everything lands on the version's own beat grid. Switching language
 * mid-song swaps the lyric layer, crossfades to the other mix and seeks to
 * the same musical moment in it.
 */
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import Component from '@glimmer/component';
import { modifier } from 'ember-modifier';

import { Sound } from './sound';
import { Lyric, prepareThrough, Reel } from './choreo';
import {
  beatLength,
  cameraPath,
  DURATION,
  framing,
  LIGHT_INK,
  isChorus,
  type Lang,
  mapTime,
  type Photo,
  type Place,
  type Pose,
  scenes,
  sectionAt,
  sectionStarts,
  type Shot,
  shotAt,
  shots,
  VERSIONS,
  type Version,
} from './song-clock';
import { DepthPicture, LOW_POWER } from './stage-gl';
import type { MixHint } from './mix-analysis';
import type { SongLyrics } from './lyric-types';

const FPS = 30;
const SEAMS = { dissolve: 0, glass: 1, whip: 2, glitch: 3 } as const;

/** words that carry a line; they are set big */
const KEYS = [
  'SUN',
  'SKY',
  'MOON',
  'STARS',
  'LOVE',
  'FIRE',
  'FLAME',
  'ICE',
  'FOREVER',
  'TONIGHT',
  'SATISFIED',
  'CRAZY',
  'RUSH',
  'ALIVE',
  'EYES',
  'NIGHT',
  'DAY',
  'WANT',
  'FINE',
  'SMILE',
  'MIND',
  'TEASE',
  'SIDE',
  'ANYTHING',
  'TOUCH',
  'TIME',
  'DESIRES',
  'ASK',
  'BOY',
  'BABE',
];

const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const prog = (x: number, a: number, b: number) => clamp01((x - a) / (b - a));
const expoOut = (t: number) => (t >= 1 ? 1 : 1 - 2 ** (-10 * clamp01(t)));
/** a damped spring from 0 to 1, t in seconds */
const spring = (t: number, k = 260, c = 18) => {
  if (t <= 0) return 0;
  const w = Math.sqrt(k);
  const z = c / (2 * w);
  const wd = w * Math.sqrt(Math.max(1e-6, 1 - z * z));
  return (
    1 -
    Math.exp(-z * w * t) *
      (Math.cos(wd * t) + ((z * w) / wd) * Math.sin(wd * t))
  );
};

interface PlacedLine {
  id: string;
  words: { text: string; start: number; end: number }[];
  exit: number;
  translation: string;
  keys: string[];
  place: Place;
  ink: 'dark' | 'light';
  starts: string;
  ends: string;
  title: boolean;
  size: number;
}

interface PlacedScene {
  id: string;
  at: number;
  until: number;
  lines: PlacedLine[];
}

interface Signature {
  Args: {
    audioUrl: (lang: Lang) => string;
    /** each mix's waveform and tempo map, as measured on the card */
    hint?: (lang: Lang) => MixHint | undefined;
    /** each version's lyrics and word times, as kept on its card */
    lyrics?: (lang: Lang) => SongLyrics | undefined;
    /** a realm file under `media/`, by its path there */
    mediaUrl: (path: string) => string;
    lang?: Lang;
    title?: string;
    artist?: string;
    credits?: string;
    publisher?: string;
  };
}

/** the shot covering most of [a, b] */
function longestShot(list: ReturnType<typeof shots>, a: number, b: number) {
  let best = list[shotAt(list, a)]!;
  let most = -1;
  for (let i = 0; i < list.length; i++) {
    const s = list[i]!;
    const end = list[i + 1]?.start ?? Infinity;
    const over = Math.min(b, end) - Math.max(a, s.start);
    if (over > most) {
      most = over;
      best = s;
    }
  }
  return best;
}

/** "Christopher Tse" -> "C. Tse"; a name ending in an initial stays whole: "Dana G" */
function shortName(name: string): string {
  const parts = name.trim().split(/\s+/);
  const last = parts[parts.length - 1] ?? '';
  if (parts.length < 2) return name;
  return last.length === 1
    ? name
    : `${parts[0]![0]}. ${parts.slice(1).join(' ')}`;
}

const NO_BEATS = {
  times: [] as number[],
  strength: [] as number[],
  beat: [] as number[],
};

export class LyricPlayer extends Component<Signature> {
  /** both versions, with the lyrics their cards keep (the built-in ones if a card has none) */
  versions: Record<Lang, Version> = {
    en: {
      ...VERSIONS.en,
      lyrics: this.args.lyrics?.('en') ?? VERSIONS.en.lyrics,
    },
    ko: {
      ...VERSIONS.ko,
      lyrics: this.args.lyrics?.('ko') ?? VERSIONS.ko.lyrics,
    },
  };

  /** a mix's tempo map: every eighth, its strength and 0/1/2 off/beat/bar */
  beats(lang: Lang): { times: number[]; strength: number[]; beat: number[] } {
    const h = this.args.hint?.(lang);
    return h
      ? { times: h.eighths, strength: h.strength, beat: h.beat }
      : NO_BEATS;
  }

  /** a mix's loudness in bars, for the waveform */
  loudness(lang: Lang): number[] {
    return this.args.hint?.(lang)?.peaks ?? [];
  }

  /* ---- plain state: the reel forbids tracked writes after prepare ---- */
  // the Korean version is the default
  lang: Lang = this.args.lang ?? 'ko';
  langLabel = this.lang === 'en' ? '한국어' : 'English';
  langName = this.lang === 'en' ? 'English' : '한국어';
  runtime = ((d: number) =>
    `${Math.floor(d / 60)}:${String(Math.floor(d % 60)).padStart(2, '0')}`)(
    this.versions[this.lang].duration,
  );
  root?: HTMLElement;
  picture?: DepthPicture;
  transport?: {
    seek(t: number): Promise<void>;
    time(): number;
    readonly playing: boolean;
    play(): Promise<void>;
    pause(): void;
  };
  sound?: Sound;
  wantPlay = false;
  els: Record<string, HTMLElement | null> = {};
  typeLayers: HTMLElement[] = [];
  page?: HTMLElement;
  ghostK?: number;
  waveDrawn = '';
  dragging = false;
  pendingSeek?: number;
  letters: HTMLElement[] = [];
  /** each title letter's word, and each word's first letter */
  letterWord: number[] = [];
  wordFirst: number[] = [];
  writerEls: HTMLElement[] = [];
  /** every sung word of a language, in order: when it starts and where it is drawn */
  dotWords: Partial<Record<Lang, { start: number; el: HTMLElement }[]>> = {};
  writerChars: HTMLElement[][] = [];
  writerRules: (HTMLElement | null)[] = [];

  shots = { en: shots(this.versions.en), ko: shots(this.versions.ko) };
  starts = {
    en: sectionStarts(this.versions.en),
    ko: sectionStarts(this.versions.ko),
  };
  scenesEn = this.place(this.versions.en);
  scenesKo = this.place(this.versions.ko);
  cameras = {
    en: this.camera(this.versions.en),
    ko: this.camera(this.versions.ko),
  };
  grid = {
    en: {
      beat: beatLength(this.versions.en),
      downbeat: this.versions.en.downbeat,
    },
    ko: {
      beat: beatLength(this.versions.ko),
      downbeat: this.versions.ko.downbeat,
    },
  };

  /** the title as the key art sets it: two lines, letter by letter */
  titleLines = [
    ['just', 'ask'],
    ['for', 'it'],
  ].map((line) =>
    line.map((word) => ({ cls: `w-${word}`, text: word, letters: [...word] })),
  );

  /** the title's style: c (one line, "ask" and "it" in the serif) unless ?title=a|b */
  titleStyle = (() => {
    try {
      const v = new URLSearchParams(window.location.search).get('title');
      return v === 'a' || v === 'b' ? v : 'c';
    } catch {
      return 'c';
    }
  })();

  /** the whole lyric sheet, as a reader sees it under the video */
  sheetOf(v: Version) {
    let last = -1;
    return v.lyrics.lines.map((line, i) => {
      const head =
        line.section !== last ? v.lyrics.sections[line.section]! : '';
      last = line.section;
      const text = line.words
        .map((w) => w.text.toLowerCase())
        .join(' ')
        .replace(/\bi\b/g, 'I')
        .replace(/\bi'/g, "I'")
        .replace(/^./, (c) => c.toUpperCase());
      return {
        i,
        head,
        text,
        translation: line.translation,
        start: line.words[0]!.start,
      };
    });
  }

  sheetEn = this.sheetOf(this.versions.en);
  sheetKo = this.sheetOf(this.versions.ko);
  /** the waveform scrubber: each mix's loudness in bars */
  /** the lyric line lit on the sheet */
  nowLine = -1;

  camera(v: Version): (t: number) => Pose {
    const path = cameraPath(v);
    const sample = prepareThrough(path.from, path.through, 0.5);
    return (t: number) => sample(clamp01(t / path.seconds)) as Pose;
  }

  /** each line, with the placement of the shot it is sung over */
  place(v: Version): PlacedScene[] {
    const list = shots(v);
    return scenes(v).map((s) => ({
      id: s.id,
      at: s.at,
      until: s.until,
      lines: s.lines.map((l) => {
        // the shot the line is on screen with longest decides where it sits
        const shot = longestShot(list, l.line.words[0]!.start - 0.2, l.exit);
        const words = l.line.words;
        const english = words.filter((w) =>
          KEYS.includes(w.text.replace(/[^A-Z]/g, '')),
        );
        // a line with no key word of its own: its longest word carries it
        const longest = [...words].sort(
          (a, b) => b.text.length - a.text.length,
        )[0]!.text;
        const keys = l.title
          ? ['ASK', 'IT']
          : english.length
            ? english.map((w) => w.text)
            : [longest];
        return {
          id: l.id,
          words,
          starts: words.map((w) => w.start.toFixed(3)).join(','),
          ends: words.map((w) => w.end.toFixed(3)).join(','),
          exit: l.exit,
          translation: l.line.translation,
          keys,
          place: l.title ? ('low' as Place) : framing(shot.photo).place,
          ink: LIGHT_INK.has(shot.photo) ? 'light' : 'dark',
          title: l.title,
          size: l.title ? 96 : s.chorus ? 64 : 56,
        };
      }),
    }));
  }

  get fontFaces(): string {
    const face = (family: string, file: string, style = 'normal') =>
      `@font-face{font-family:"${family}";src:url("${this.args.mediaUrl(`fonts/${file}`)}") format("truetype");font-style:${style};font-display:block}`;
    const pre = (weight: number, file: string) =>
      `@font-face{font-family:"Pretendard";src:url("${this.args.mediaUrl(`fonts/${file}`)}") format("opentype");font-weight:${weight};font-display:block}`;
    return [
      // the metadata face: a condensed mono with a slight edge
      `@import url('https://fonts.googleapis.com/css2?family=Martian+Mono:wdth,wght@75..112.5,300..500&display=block');`,
      pre(200, 'Pretendard-ExtraLight.otf'),
      pre(300, 'Pretendard-Light.otf'),
      pre(500, 'Pretendard-Medium.otf'),
      face('Instrument Serif', 'InstrumentSerif-Italic.ttf', 'italic'),
    ].join('\n');
  }

  /* rules for what the reel and <Lyric> render: outside this template's scope */
  get sheet(): string {
    return `${this.fontFaces}
.lv-player .cf-reel-stage { container-type: size; perspective: 1800px; }
.lv-player .cf-reel-layer, .lv-player .cf-reel-scene { --u: min(100cqw / 1920, 100cqh / 1080); --boost: 1.6; }
@container (aspect-ratio < 1) { .lv-player .cf-reel-layer, .lv-player .cf-reel-scene { --u: min(100cqw / 1080, 100cqh / 1920); --boost: 1.75; } }
.lv-player [data-lang-layer] { transform-origin: 50% 50%; will-change: transform; }
.lv-player[data-lang="en"] [data-lang-layer="ko"] .cf-lyric, .lv-player[data-lang="ko"] [data-lang-layer="en"] .cf-lyric { display: none; }
.lv-player .cf-lyric { position: absolute; display: flex; flex-direction: column; opacity: 0; color: #fff; }
.lv-player .cf-lyric-words { display: flex; flex-wrap: wrap; align-items: baseline; column-gap: calc(var(--lyric-size) * 0.26 * var(--u) * var(--boost, 1.3)); font: 200 calc(var(--lyric-size) * var(--u) * var(--boost, 1.3)) / 1.08 Pretendard, sans-serif; letter-spacing: -0.01em; text-transform: lowercase; }
.lv-player .cf-lyric-word { position: relative; display: inline-block; }
.lv-player .lv-motes { position: absolute; inset: 0; overflow: hidden; pointer-events: none; }
.lv-player .lv-mote { position: absolute; left: 0; top: 0; width: calc(26 * var(--u, 1px)); height: calc(26 * var(--u, 1px)); margin: calc(-13 * var(--u, 1px)); border-radius: 50%; opacity: .45; background: radial-gradient(closest-side, rgba(255,255,255,.9), rgba(255,255,255,.25) 45%, transparent); }
.lv-player .lv-mote:nth-child(3n+1) { background: radial-gradient(closest-side, rgba(150,240,255,.85), rgba(25,219,239,.25) 45%, transparent); }
.lv-player .lv-mote:nth-child(3n+2) { background: radial-gradient(closest-side, rgba(255,170,185,.8), rgba(255,45,79,.22) 45%, transparent); opacity: .4; }
.lv-player .cf-lyric-word.key { font-family: "Instrument Serif", serif; font-style: italic; font-weight: 400; font-size: 2em; letter-spacing: 0; line-height: 0.9; }
.lv-player .cf-lyric-base { color: rgba(255,255,255,.62); text-shadow: calc(-1 * var(--split, 0) * var(--u)) 0 rgba(25,219,239,.35), calc(var(--split, 0) * var(--u)) 0 rgba(255,45,79,.35), 0 0 calc(3 * var(--u)) rgba(8,10,28,.35), 0 0 calc(34 * var(--u)) rgba(8,10,28,.6); }
.lv-player .cf-lyric-hot { position: absolute; left: 0; top: 0; color: #fff; clip-path: inset(-30% 100% -30% 0); text-shadow: calc(-1 * (1.5 + var(--split, 0)) * var(--u)) 0 rgba(25,219,239,.8), calc((1.5 + var(--split, 0)) * var(--u)) 0 rgba(255,45,79,.8), 0 0 calc(3 * var(--u)) rgba(8,10,28,.35), 0 0 calc(34 * var(--u)) rgba(8,10,28,.55); }
.lv-player .lv-ink-dark .cf-lyric-base { color: rgba(18,18,26,.38); text-shadow: 0 0 calc(30 * var(--u)) rgba(235,240,248,.7); }
.lv-player .lv-ink-dark .cf-lyric-hot { color: #121218; text-shadow: calc(-1 * (1.5 + var(--split, 0)) * var(--u)) 0 rgba(25,219,239,.7), calc((1.5 + var(--split, 0)) * var(--u)) 0 rgba(255,45,79,.7), 0 0 calc(30 * var(--u)) rgba(235,240,248,.6); }
.lv-player .lv-ink-dark .cf-lyric-translation { color: rgba(18,18,26,.8); text-shadow: 0 0 calc(16 * var(--u)) rgba(235,240,248,.8); }
.lv-player .cf-lyric-translation { margin: calc(16 * var(--u)) 0 0; font: 300 calc(28 * var(--u)) / 1.3 Pretendard, sans-serif; letter-spacing: 0.01em; color: rgba(255,255,255,.88); text-shadow: 0 0 calc(16 * var(--u)) rgba(8,10,28,.7); }
.lv-player .lv-place-low { left: 7%; right: 7%; bottom: calc(80 * var(--u) + 90px); align-items: center; }
.lv-player .lv-place-low .cf-lyric-words { justify-content: center; }
.lv-player .lv-place-top { left: 7%; right: 7%; top: calc(250 * var(--u)); align-items: center; }
.lv-player .lv-place-top .cf-lyric-words { justify-content: center; }
.lv-player .lv-place-left { left: 8%; right: 50%; top: calc(330 * var(--u)); align-items: center; rotate: -4deg; }
.lv-player .lv-place-left .cf-lyric-words { justify-content: center; }
.lv-player .lv-place-right { left: 50%; right: 8%; top: calc(300 * var(--u)); align-items: center; rotate: 4deg; }
.lv-player .lv-place-right .cf-lyric-words { justify-content: center; }
.lv-player .lv-place-diag { left: 5%; right: 34%; top: calc(560 * var(--u)); align-items: flex-start; rotate: -11deg; }
.lv-player .lv-place-side { right: 5%; top: calc(140 * var(--u)); width: 30%; align-items: flex-end; }
.lv-player .lv-place-side .cf-lyric-words { flex-direction: column; align-items: flex-end; }
/* the lyrics are never behind her: no cut-out layer in front of the type */
.lv-player canvas.lv-front { visibility: hidden; }
/* the video: 16:9 on wide screens, the phone's full height upright */
.lv-player .cf-reel.lv { position: relative; width: 100%; height: auto; aspect-ratio: 16 / 9; max-height: calc(100vh - 100px); min-height: 200px; overflow: hidden; }
.lv-card:fullscreen .lv-player .cf-reel.lv { aspect-ratio: auto; height: 100vh; max-height: none; }
@media (max-width: 700px) and (orientation: portrait) {
  .lv-player .cf-reel.lv { aspect-ratio: auto; height: min(calc((100vw - 16px) * 16 / 9), calc(100svh - 104px - env(safe-area-inset-top) - env(safe-area-inset-bottom))); min-height: 420px; max-height: none; }
}
@container (aspect-ratio < 1) {
  .lv-player canvas.lv-front { visibility: hidden; }
  .lv-player .lv-over .lv-ka-plate { top: 4%; right: -12%; width: 118%; height: auto; -webkit-mask-image: linear-gradient(to right, transparent, #000 10%, #000 90%, transparent), linear-gradient(to bottom, transparent, #000 8%, #000 78%, transparent); -webkit-mask-composite: source-in; mask-image: linear-gradient(to right, transparent, #000 10%, #000 90%, transparent), linear-gradient(to bottom, transparent, #000 8%, #000 78%, transparent); mask-composite: intersect; }
  .lv-player .lv-over .lv-ka-cut { -webkit-mask-image: linear-gradient(to bottom, #000 78%, transparent); mask-image: linear-gradient(to bottom, #000 78%, transparent); }
  .lv-player .lv-over .lv-title { z-index: 3; }
  .lv-player .lv-place-side .cf-lyric-words { flex-direction: row; align-items: baseline; justify-content: center; }
  .lv-player .lv-over .lv-title { left: 6%; top: auto; bottom: 26%; font-size: min(calc(88cqw / var(--tw, 3.1)), 11.5cqh); line-height: 0.86; }
  .lv-player .lv-over .lv-writer { font-size: min(calc(120 * var(--u)), 8.6cqw); }
  .lv-player .lv-place-left, .lv-player .lv-place-right, .lv-player .lv-place-diag, .lv-player .lv-place-side, .lv-player .lv-place-low { left: 6%; right: 6%; top: calc(430 * var(--u)); bottom: auto; width: auto; align-items: center; rotate: -3deg; }
  .lv-player .cf-lyric-words { justify-content: center; flex-direction: row; align-items: baseline; }
  .lv-player .lv-over .lv-writers { bottom: 24%; }
}
`;
  }

  fonts = [
    '200 64px Pretendard',
    '300 32px Pretendard',
    '500 24px Pretendard',
    'italic 400 64px "Instrument Serif"',
  ];

  /** the songwriters from the credit line: "Written by A, B, C" */
  get writers(): string[] {
    const credits =
      this.args.credits ?? 'Written by Christopher Tse, Dana G, Steve Ingino';
    return credits
      .replace(/^\s*written by\s*/i, '')
      .split(/\s*(?:,|&|\band\b)\s*/)
      .filter(Boolean);
  }

  /** the credit under the title */
  get writersLine(): string {
    return this.writers.map(shortName).join(', ');
  }

  /** each writer's name as letters, for the credit's per-letter entrance */
  get writerLetters(): { letters: string[] }[] {
    return this.writers.map((name) => ({
      letters: [...name].map((c) => (c === ' ' ? '\u00a0' : c)),
    }));
  }

  get version(): Version {
    return this.versions[this.lang];
  }

  /* ---- the stage ------------------------------------------------------ */

  setup = modifier((el: HTMLElement) => {
    this.root = el;
    // tooling: the MP4 renderer (`?render`) drives the player from outside
    if (new URLSearchParams(window.location.search).has('render')) {
      (window as unknown as { __lyric?: LyricPlayer }).__lyric = this;
    }
    const player = el.closest<HTMLElement>('.lv-player') ?? el;
    const q = (k: string) =>
      player.querySelector<HTMLElement>(`[data-lv="${k}"]`);
    const page = el.closest<HTMLElement>('.lv-page') ?? player;
    for (const k of [
      'tag',
      'tag-lang',
      'intro',
      'outro',
      'adlib',
      'black',
      'writers',
      'writers-head',
      'writers-pub',
    ])
      this.els[k] = q(k);
    for (const k of [
      'lang',
      'play',
      'chip',
      'chip-now',
      'chip-all',
      'head',
      'full',
      'label-lang',
      'dot',
    ]) {
      this.els[k] = page.querySelector<HTMLElement>(`[data-lv="${k}"]`);
    }
    this.page = page;
    this.dressBrowser();
    // bound here: dragging needs the press, which the template lint forbids binding
    const wave = page.querySelector<HTMLElement>('.lv-wave');
    wave?.addEventListener('pointerdown', this.wavePress);
    this.letters = [
      ...player.querySelectorAll<HTMLElement>('[data-lv="intro"] .lv-letter'),
    ];
    const titleWords = [
      ...player.querySelectorAll<HTMLElement>('[data-lv="intro"] .lv-word'),
    ];
    this.letterWord = this.letters.map((el) =>
      titleWords.indexOf(el.closest<HTMLElement>('.lv-word')!),
    );
    this.wordFirst = titleWords.map((w) =>
      this.letters.findIndex((el) => w.contains(el)),
    );
    this.writerEls = [...player.querySelectorAll<HTMLElement>('.lv-writer')];
    this.writerChars = this.writerEls.map((el) => [
      ...el.querySelectorAll<HTMLElement>('.lv-wl'),
    ]);
    this.writerRules = this.writerEls.map((el) =>
      el.querySelector<HTMLElement>('.lv-writer-rule'),
    );

    const back = el.querySelector<HTMLCanvasElement>('canvas.lv-back')!;
    const front = player.querySelector<HTMLCanvasElement>('canvas.lv-front')!;
    this.picture = new DepthPicture(back, front, this.args.mediaUrl);
    // a new size reframes the picture at once (not a stretched old frame),
    // and the waveform and the dot are measured again
    const fit = () => {
      const r = back.getBoundingClientRect();
      this.picture?.resize(r.width, r.height);
      this.waveDrawn = '';
      if (this.transport && !this.transport.playing)
        this.paint(this.transport.time());
    };
    const ro = new ResizeObserver(fit);
    ro.observe(back);
    void this.picture.ready.then(fit);

    // the mix on screen starts loading now: its stream and its decode
    // the mix versions in the URL, so a new bounce is never served from a cache
    // (a mix measured again gets a new one)
    const sound = new Sound(
      (lang) =>
        `${this.args.audioUrl(lang)}?mix=${this.args.hint?.(lang)?.version ?? '0'}`,
      this.lang,
    );
    this.sound = sound;
    sound.preload(this.lang);
    sound.onReady = () => {
      if (this.transport && !this.transport.playing)
        this.paint(this.transport.time());
    };
    window.addEventListener('keydown', this.playerKey);
    return () => {
      window.removeEventListener('keydown', this.playerKey);
      ro.disconnect();
      this.picture?.destroy();
      sound.destroy();
    };
  });

  /** registers the paint on the reel's clock and keeps its transport */
  clocked = modifier((_el: HTMLElement, [r]: [any]) => {
    this.transport = r.transport;
    if (this.wantPlay) {
      this.wantPlay = false;
      void r.transport.play();
    }
    return r.addClocked({ order: 10, paint: (t: number) => this.paint(t) });
  });

  prepare = async () => {
    await this.picture?.ready;
  };

  /** the sound plays itself on Web Audio and gives the reel its clock */
  sink = {
    clock: () => this.sound?.clock(),
    onPlay: (t: number) => {
      this.sound?.start(t);
    },
    onPause: () => this.sound?.stop(),
    onSeek: (t: number) => {
      if (this.sound?.playing) this.sound.start(t);
    },
  };

  /* ---- chrome ------------------------------------------------------- */

  togglePlay = () => {
    const tr = this.transport;
    // inside the tap: phones only let sound start here
    this.sound?.unlock();
    // tapped before the player is up: play as soon as it is
    if (!tr) {
      this.wantPlay = true;
      return;
    }
    if (!tr.playing && this.page?.dataset.started !== 'true') this.magicMove();
    if (tr.playing) tr.pause();
    else if (tr.time() >= this.version.duration - 0.25)
      void tr.seek(0).then(() => tr.play());
    else void tr.play();
  };

  /* ---- the waveform: press, drag, let go, like SoundCloud ----------- */

  waveAt(e: PointerEvent): number {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    return Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
  }

  /** the lighter preview from the start to the pointer */
  ghost(k: number | undefined): void {
    this.ghostK = k;
    const t = this.transport?.time() ?? 0;
    this.drawWave(Math.min(1, t / this.version.duration));
  }

  /**
   * The waveform on a canvas at the device's own pixels: as many bars as the
   * width holds at a 4 px pitch, every edge on a whole device pixel, so no
   * bar shimmers between pixels. Redrawn only when something visible moves.
   */
  drawWave(played: number): void {
    const c = this.page?.querySelector<HTMLCanvasElement>(
      'canvas.lv-wave-canvas',
    );
    if (!c) return;
    const w = c.clientWidth;
    const h = c.clientHeight;
    if (!w || !h) return;
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    const W = Math.round(w * dpr);
    const H = Math.round(h * dpr);
    const idle =
      this.page?.dataset.started !== 'true' ||
      this.page?.dataset.ended === 'true';
    const lang = this.version.lang;
    const key = `${lang}|${W}|${H}|${Math.round(played * W)}|${this.ghostK === undefined ? -1 : Math.round(this.ghostK * W)}|${idle}`;
    if (key === this.waveDrawn) return;
    this.waveDrawn = key;
    if (c.width !== W || c.height !== H) {
      c.width = W;
      c.height = H;
    }
    const g = c.getContext('2d');
    if (!g) return;
    g.clearRect(0, 0, W, H);
    const data = this.loudness(lang);
    // SoundCloud's shape: bars up from a baseline at 72%, and their
    // reflection below it, dimmer; a bar every 3 CSS px, 2 px wide
    const count = Math.max(24, Math.floor(w / 3));
    const pitch = W / count;
    const bar = Math.max(1, Math.round(pitch * 0.67));
    const base = Math.round(H * 0.72);
    const up = base;
    const down = H - base - Math.round(dpr);
    const hot = g.createLinearGradient(0, base, 0, 0);
    hot.addColorStop(0, '#ff3d00');
    hot.addColorStop(1, '#ff8a1f');
    const playedX = played * W;
    const ghostX = this.ghostK === undefined ? -1 : this.ghostK * W;
    const colour = (mid: number, reflect: boolean) => {
      if (mid <= playedX) return reflect ? 'rgba(255,120,60,0.45)' : hot;
      if (mid <= ghostX)
        return reflect ? 'rgba(255,120,60,0.22)' : 'rgba(255,110,40,0.55)';
      if (idle) return reflect ? 'rgba(22,22,29,0.12)' : 'rgba(22,22,29,0.3)';
      return reflect ? 'rgba(255,255,255,0.3)' : 'rgba(255,255,255,0.78)';
    };
    // a faint shadow under the unplayed bars keeps them legible on pale shots
    g.shadowColor = idle ? 'transparent' : 'rgba(10,12,30,0.35)';
    g.shadowBlur = 2 * dpr;
    for (let i = 0; i < count; i++) {
      // the loudest of the slices this bar stands for
      const a = Math.floor((i * data.length) / count);
      const b = Math.max(a + 1, Math.floor(((i + 1) * data.length) / count));
      let v = 0;
      for (let j = a; j < b; j++) v = Math.max(v, data[j] ?? 0);
      const x = Math.round(i * pitch);
      const mid = x + bar / 2;
      const bh = Math.max(Math.round(dpr), Math.round(v * up));
      g.fillStyle = colour(mid, false);
      g.fillRect(x, base - bh, bar, bh);
      g.fillStyle = colour(mid, true);
      g.fillRect(
        x,
        base + Math.round(dpr),
        bar,
        Math.max(1, Math.round(v * down)),
      );
    }
    g.shadowColor = 'transparent';
  }

  /** seeks at most once a frame while dragging */
  seekSoon(k: number): void {
    const first = this.pendingSeek === undefined;
    this.pendingSeek = k;
    if (!first) return;
    // eslint-disable-next-line @cardstack/boxel/no-raf-for-state
    requestAnimationFrame(() => {
      const at = this.pendingSeek;
      this.pendingSeek = undefined;
      if (at !== undefined)
        void this.transport?.seek(at * this.version.duration);
    });
  }

  wavePress = (e: PointerEvent) => {
    const bar = e.currentTarget as HTMLElement;
    bar.setPointerCapture(e.pointerId);
    this.dragging = true;
    bar.dataset.drag = 'true';
    const k = this.waveAt(e);
    this.ghost(k);
    this.seekSoon(k);
  };

  waveMove = (e: PointerEvent) => {
    const k = this.waveAt(e);
    if (e.pointerType === 'mouse' || this.dragging) this.ghost(k);
    if (this.dragging) this.seekSoon(k);
  };

  waveRelease = (e: PointerEvent) => {
    const bar = e.currentTarget as HTMLElement;
    if (bar.hasPointerCapture(e.pointerId))
      bar.releasePointerCapture(e.pointerId);
    this.dragging = false;
    bar.dataset.drag = 'false';
    if (e.pointerType !== 'mouse') this.ghost(undefined);
  };

  waveLeave = () => {
    if (!this.dragging) this.ghost(undefined);
  };

  /**
   * YouTube's keys: Space or K play and pause, J and L ten seconds back and
   * on, the arrows five, 0–9 a tenth of the song each, Home and End, M mute,
   * F full screen, and , . a frame at a time while paused.
   */
  playerKey = (e: KeyboardEvent) => {
    const target = e.target as HTMLElement | null;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (target?.closest('input, textarea, select, [contenteditable], .lv-wave'))
      return;
    const tr = this.transport;
    const d = this.version.duration;
    const seek = (to: number) => void tr?.seek(Math.min(d, Math.max(0, to)));
    const now = tr?.time() ?? 0;
    const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
    const act = (f: () => void) => {
      e.preventDefault();
      f();
    };
    if (k === ' ' || k === 'k') return act(this.togglePlay);
    if (k === 'j') return act(() => seek(now - 10));
    if (k === 'l') return act(() => seek(now + 10));
    if (k === 'ArrowLeft') return act(() => seek(now - 5));
    if (k === 'ArrowRight') return act(() => seek(now + 5));
    if (k === 'Home') return act(() => seek(0));
    if (k === 'End') return act(() => seek(d - 0.3));
    if (/^[0-9]$/.test(k)) return act(() => seek((Number(k) / 10) * d));
    if (k === 'm') return act(() => this.sound?.setMuted(!this.sound.muted));
    if (k === 'f') return act(this.fullscreen);
    if ((k === ',' || k === '.') && !tr?.playing)
      return act(() => seek(now + (k === ',' ? -1 : 1) / 30));
  };

  /** arrows step five seconds */
  waveKey = (e: KeyboardEvent) => {
    const step = e.key === 'ArrowRight' ? 5 : e.key === 'ArrowLeft' ? -5 : 0;
    const tr = this.transport;
    if (!step || !tr) return;
    e.preventDefault();
    void tr.seek(
      Math.min(this.version.duration, Math.max(0, tr.time() + step)),
    );
  };

  /**
   * MAGIC MOVE, poster to video: the big title flies into the corner label
   * while the cover pushes in and dissolves into the first shot.
   */
  wasPlaying = false;

  /**
   * The end frame: the key art's title transmutes into the poster's, word
   * by word, and the rest of the poster fades in around it.
   */
  endMove(): void {
    const page = this.page;
    const poster = page?.querySelector<HTMLElement>('.lv-poster');
    if (!page || !poster || getComputedStyle(poster).display === 'none') return;
    const from = [
      ...page.querySelectorAll<HTMLElement>('[data-lv="intro"] .lv-word'),
    ];
    const to = [
      ...poster.querySelectorAll<HTMLElement>('.lv-poster-title .lv-word'),
    ];
    const ease = 'cubic-bezier(0.65, 0, 0.15, 1)';
    const runs: Animation[] = [];
    to.forEach((w, i) => {
      const a = from[i]?.getBoundingClientRect();
      const b = w.getBoundingClientRect();
      if (!a?.width || !b.width) return;
      w.style.display = 'inline-block';
      w.style.transformOrigin = '0 0';
      const k = a.height / b.height;
      runs.push(
        w.animate(
          [
            {
              transform: `translate(${a.left - b.left}px, ${a.top - b.top}px) scale(${k})`,
              textShadow:
                '-10px 0 rgba(25,219,239,.8), 10px 0 rgba(255,45,79,.8)',
            },
            {
              transform: 'none',
              textShadow: '0 0 transparent, 0 0 transparent',
            },
          ],
          { duration: 1100, delay: i * 60, easing: ease, fill: 'backwards' },
        ),
      );
    });
    const fade = (sel: string, delay: number, extra: Keyframe = {}) => {
      for (const el of poster.querySelectorAll<HTMLElement>(sel)) {
        runs.push(
          el.animate(
            [
              { opacity: 0, ...extra },
              { opacity: 1, transform: 'none' },
            ],
            { duration: 700, delay, easing: 'ease-out', fill: 'backwards' },
          ),
        );
      }
    };
    fade('.lv-poster-bg', 0);
    fade('.lv-poster-cover:not(.lv-poster-cut)', 150, {
      transform: 'scale(1.04)',
    });
    fade('.lv-poster-cut', 350, { transform: 'scale(1.06)' });
    fade('.lv-poster-sub', 700, { transform: 'translateY(10px)' });
    fade('.lv-poster-cta', 850, { transform: 'translateY(10px)' });
    void Promise.all(runs.map((r) => r.finished.catch(() => {}))).then(() => {
      for (const w of to) w.style.display = '';
    });
  }

  magicMove(): void {
    const page = this.page;
    const poster = page?.querySelector<HTMLElement>('.lv-poster');
    const label = page?.querySelector<HTMLElement>('.lv-label.title');
    if (
      !page ||
      !poster ||
      !label ||
      getComputedStyle(poster).display === 'none'
    )
      return;
    const target = label.getBoundingClientRect();
    if (!target.width) return;
    const ease = 'cubic-bezier(0.7, 0, 0.2, 1)';
    const out = 'cubic-bezier(0.2, 0.8, 0.2, 1)';
    const runs: Animation[] = [];
    const go = (
      el: Element | null,
      frames: Keyframe[],
      o: KeyframeAnimationOptions,
    ) => {
      if (el) runs.push(el.animate(frames, { fill: 'forwards', ...o }));
    };

    // 1. THE TITLE, word by word, into the corner label
    const words = [
      ...poster.querySelectorAll<HTMLElement>('.lv-poster-title .lv-word'),
    ];
    let x = target.left;
    const scale =
      (target.height * 0.55) /
      (words[0]?.getBoundingClientRect().height || target.height);
    words.forEach((w, i) => {
      const r = w.getBoundingClientRect();
      w.style.display = 'inline-block';
      w.style.transformOrigin = '0 0';
      const dx = x - r.left;
      const dy = target.top + target.height * 0.2 - r.top;
      x += r.width * scale + target.height * 0.18;
      go(
        w,
        [
          { transform: 'none', opacity: 1 },
          {
            transform: `translate(${dx}px, ${dy}px) scale(${scale})`,
            opacity: 1,
            offset: 0.8,
          },
          {
            transform: `translate(${dx}px, ${dy}px) scale(${scale})`,
            opacity: 0,
          },
        ],
        { duration: 900, delay: i * 70, easing: ease },
      );
    });

    // 2. HER, toward the lens, her cyan and red ghosts splitting apart
    go(
      poster.querySelector('.lv-poster-cut'),
      [
        {
          transform: 'scale(1)',
          filter:
            'drop-shadow(0 0 0 rgba(25,219,239,0)) drop-shadow(0 0 0 rgba(255,45,79,0))',
          opacity: 1,
        },
        {
          transform: 'scale(1.08) translateY(-1%)',
          filter:
            'drop-shadow(-14px 0 0 rgba(25,219,239,.85)) drop-shadow(14px 0 0 rgba(255,45,79,.85))',
          opacity: 1,
          offset: 0.45,
        },
        {
          transform: 'scale(1.22) translateY(-3%)',
          filter:
            'drop-shadow(-46px 0 0 rgba(25,219,239,0)) drop-shadow(46px 0 0 rgba(255,45,79,0))',
          opacity: 0,
        },
      ],
      { duration: 1100, easing: out },
    );

    // 3. THE COVER wipes away, her side last, onto the video underneath
    go(
      poster.querySelector('.lv-poster-cover:not(.lv-poster-cut)'),
      [
        { clipPath: 'inset(0 0 0 0)', transform: 'scale(1)' },
        { clipPath: 'inset(0 0 0 100%)', transform: 'scale(1.06)' },
      ],
      { duration: 900, delay: 120, easing: ease },
    );

    // 4. THE PLAY PILL flies into the play button under the video
    const cta = poster.querySelector<HTMLElement>('.lv-poster-cta');
    const play = page.querySelector<HTMLElement>('.lv-row .lv-play');
    if (cta && play) {
      const r = cta.getBoundingClientRect();
      const p = play.getBoundingClientRect();
      go(
        cta,
        [
          { transform: 'none', opacity: 1 },
          {
            transform: `translate(${p.left - r.left}px, ${p.top - r.top}px) scale(${p.height / r.height})`,
            opacity: 0,
          },
        ],
        { duration: 700, easing: ease },
      );
      cta.style.transformOrigin = '0 0';
    }
    // 5. the language line lifts away
    go(
      poster.querySelector('.lv-poster-sub'),
      [
        { transform: 'none', opacity: 1 },
        { transform: 'translateY(-12px)', opacity: 0 },
      ],
      { duration: 400, easing: out },
    );

    page.dataset.moving = 'true';
    // eslint-disable-next-line @cardstack/boxel/no-raf-for-state
    setTimeout(() => {
      // the poster is gone before its parts are put back: hidden at once,
      // no fade (a fade here would flash the whole title screen back)
      poster.style.transition = 'none';
      poster.style.opacity = '0';
      delete page.dataset.moving;
      for (const r of runs) r.cancel();
      for (const w of words) w.style.display = '';
      // eslint-disable-next-line @cardstack/boxel/no-raf-for-state
      requestAnimationFrame(() => {
        poster.style.transition = '';
        poster.style.opacity = '';
      });
    }, 1800);
  }

  /** paints the phone browser's bars black and lets the page run as a home-screen app */
  dressBrowser(): void {
    const meta = (name: string, content: string) => {
      let m = document.head.querySelector<HTMLMetaElement>(
        `meta[name="${name}"]`,
      );
      if (!m) {
        m = document.createElement('meta');
        m.name = name;
        document.head.appendChild(m);
      }
      m.content = content;
    };
    meta('theme-color', '#0f0f10');
    meta('apple-mobile-web-app-capable', 'yes');
    meta('mobile-web-app-capable', 'yes');
    meta('apple-mobile-web-app-status-bar-style', 'black-translucent');
    meta('apple-mobile-web-app-title', 'Just Ask For It');
    const vp = document.head.querySelector<HTMLMetaElement>(
      'meta[name="viewport"]',
    );
    if (vp && !vp.content.includes('viewport-fit'))
      vp.content += ', viewport-fit=cover';
    // an installable web app: its name, the album cover as its icon
    const root = new URL('../', this.args.mediaUrl('x')).href;
    const link = (rel: string, href: string, sizes?: string) => {
      let l = document.head.querySelector<HTMLLinkElement>(
        `link[rel="${rel}"]${sizes ? `[sizes="${sizes}"]` : ''}`,
      );
      if (!l) {
        l = document.createElement('link');
        l.rel = rel;
        if (sizes) l.sizes.value = sizes;
        document.head.appendChild(l);
      }
      l.href = href;
    };
    link('manifest', `${root}manifest.json`);
    // the host brings its own home-screen icon: the album cover replaces it
    for (const l of document.head.querySelectorAll<HTMLLinkElement>(
      'link[rel="apple-touch-icon"]',
    ))
      l.remove();
    link(
      'apple-touch-icon',
      this.args.mediaUrl('icons/icon-180.png'),
      '180x180',
    );
    link('icon', this.args.mediaUrl('icons/icon-192.png'), '192x192');
    document.title = 'Just Ask For It';
    meta('application-name', 'Just Ask For It');
    document.documentElement.style.background = '#0f0f10';
    document.body.style.background = '#0f0f10';
    const d = document as Document & { webkitFullscreenEnabled?: boolean };
    if (this.els.full)
      this.els.full.hidden = !(
        d.fullscreenEnabled || d.webkitFullscreenEnabled
      );
  }

  /** the card alone, full screen (Android, iPad and desktop; iPhone Safari has no element full screen) */
  fullscreen = () => {
    const card = this.page?.querySelector<HTMLElement>('.lv-card') as
      | (HTMLElement & { webkitRequestFullscreen?: () => void })
      | null
      | undefined;
    const d = document as Document & {
      webkitFullscreenElement?: Element;
      webkitExitFullscreen?: () => void;
    };
    if (document.fullscreenElement || d.webkitFullscreenElement) {
      if (document.exitFullscreen) void document.exitFullscreen();
      else d.webkitExitFullscreen?.();
      return;
    }
    if (!card) return;
    if (card.requestFullscreen)
      void card.requestFullscreen({ navigationUI: 'hide' }).catch(() => {});
    else card.webkitRequestFullscreen?.();
  };

  showLyrics = () => {
    this.page
      ?.querySelector('.lv-lyrics')
      ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  share = async () => {
    const url = window.location.href.split('?')[0]!;
    const nav = navigator as Navigator & {
      share?: (d: { title: string; url: string }) => Promise<void>;
    };
    try {
      if (nav.share)
        await nav.share({ title: this.args.title ?? 'Just Ask For It', url });
      else await navigator.clipboard.writeText(url);
    } catch {
      /* dismissed */
    }
  };

  /** click on a lyric line: jump to it */
  jump = (start: number) => {
    void this.transport?.seek(Math.max(0, start - 0.3));
  };

  /** the poster's two words: the version to play */
  pickLang = (lang: Lang) => {
    if (lang !== this.lang) this.switchLang();
  };

  switchLang = () => {
    const tr = this.transport;
    const from = this.version;
    const to = this.versions[this.lang === 'en' ? 'ko' : 'en'];
    const t = tr ? mapTime(from, to, tr.time()) : 0;
    this.lang = to.lang;
    const player = this.root?.closest<HTMLElement>('.lv-player');
    if (player) player.dataset.lang = to.lang;
    if (this.els.lang)
      this.els.lang.textContent = to.lang === 'en' ? '한국어' : 'English';
    if (this.page) this.page.dataset.lang = to.lang;
    this.nowLine = -1;
    // the sound restarts in the other mix at the same musical moment (onSeek)
    this.sound?.unlock();
    if (this.sound) {
      this.sound.lang = to.lang;
      this.sound.preload(to.lang);
    }
    void tr?.seek(t);
  };

  /* ---- the bouncing dot ------------------------------------------------ */

  wordsOf(lang: Lang): { start: number; el: HTMLElement }[] {
    const known = this.dotWords[lang];
    if (known?.length) return known;
    const player = this.root?.closest('.lv-player');
    const list: { start: number; el: HTMLElement }[] = [];
    for (const line of player?.querySelectorAll<HTMLElement>(
      `[data-lang-layer="${lang}"] .cf-lyric[data-starts]`,
    ) ?? []) {
      const starts = (line.dataset.starts ?? '').split(',').map(Number);
      const words = line.querySelectorAll<HTMLElement>('.cf-lyric-word');
      starts.forEach(
        (start, i) => words[i] && list.push({ start, el: words[i]! }),
      );
    }
    list.sort((a, b) => a.start - b.start);
    this.dotWords[lang] = list;
    return list;
  }

  /**
   * A karaoke ball that never stops: it lands on each word as it is sung,
   * arcs to the next, and through the gaps keeps bouncing on the beat where
   * it is. It reads where the words are drawn, so it rides the camera too.
   */
  bounce(t: number, v: Version): void {
    const dot = this.els.dot;
    const card = this.page?.querySelector<HTMLElement>('.lv-card');
    if (!dot || !card) return;
    const words = this.wordsOf(v.lang);
    const first = words[0];
    if (!first || t < first.start - 1.2 || t > v.outro) {
      dot.style.opacity = '0';
      return;
    }
    // it lands on every eighth note of the mix's tempo map, on whichever word
    // is being sung at that eighth
    const box = card.getBoundingClientRect();
    const spot = (el: HTMLElement) => {
      const r = el.getBoundingClientRect();
      return {
        x: r.left + r.width / 2 - box.left,
        y: r.top - box.top,
        h: r.height,
      };
    };
    // one style read per line per frame, however often it is asked
    const seen = new Map<Element, boolean>();
    const shown = (el: HTMLElement) => {
      const line = el.closest('.cf-lyric') ?? el;
      let v = seen.get(line);
      if (v === undefined) {
        v = Number(getComputedStyle(line).opacity) > 0.35;
        seen.set(line, v);
      }
      return v;
    };
    const at = (time: number) => {
      let k = 0;
      while (k + 1 < words.length && words[k + 1]!.start <= time + 0.08) k++;
      // a word whose line hasn't arrived yet: keep to the last one on screen
      for (let j = k; j >= Math.max(0, k - 16); j--)
        if (shown(words[j]!.el)) return words[j]!;
      return words[k]!;
    };
    const { times, strength, beat: level } = this.beats(v.lang);
    // not measured yet (Edit → Measure mix): no beats to land on
    if (!times.length) {
      dot.style.opacity = '0';
      return;
    }
    let lo = 0;
    let hi = times.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (times[mid]! <= t) lo = mid;
      else hi = mid - 1;
    }
    const eighth = beatLength(v) / 2;
    const landA = times[lo]!;
    const landB = times[lo + 1] ?? landA + eighth;
    const p = clamp01((t - landA) / (landB - landA));
    // where it lands on the eighths around this one: it glides through them
    // on one smooth curve (Catmull-Rom), so it never stops and starts
    const land = (i: number) =>
      spot(at(Math.max(times[i] ?? landA + (i - lo) * eighth, first.start)).el);
    const p0 = land(lo - 1);
    const p1 = land(lo);
    const p2 = land(lo + 1);
    const p3 = land(lo + 2);
    const cr = (a: number, b: number, c: number, d: number) =>
      0.5 *
      (2 * b +
        (c - a) * p +
        (2 * a - 5 * b + 4 * c - d) * p * p +
        (3 * b - a - 3 * c + d) * p * p * p);
    const x = cr(p0.x, p1.x, p2.x, p3.x);
    const y = cr(p0.y, p1.y, p2.y, p3.y);
    const h = p1.h + (p2.h - p1.h) * p;
    const dist = Math.hypot(p2.x - p1.x, p2.y - p1.y);
    // a rounder arc into a beat, a small skip to the off-eighth, higher when
    // it has further to go; sin² keeps the lift soft at both ends
    const toBeat = (level[lo + 1] ?? 1) > 0;
    // a wide frame has the room: it bounces higher there
    const wide = box.width > box.height ? 1.5 : 1;
    const peak = Math.min(
      h * (wide > 1 ? 1 : 0.7),
      (h * (toBeat ? 0.26 : 0.1) + dist * 0.18) * wide,
    );
    const lift = peak * Math.sin(Math.PI * p) ** 1.6;
    // a gentle squash on touchdown (deeper on a harder hit) and a slight
    // stretch while it rises and falls fast
    const near = p < 0.5 ? p : 1 - p;
    const landing = p < 0.5 ? lo : lo + 1;
    const hit = Math.min(
      1,
      (strength[landing] ?? 0) + (level[landing] === 2 ? 0.35 : 0),
    );
    const squash = (0.1 + 0.12 * hit) * Math.exp(-((near / 0.06) ** 2));
    const stretch =
      0.06 * Math.abs(Math.cos(Math.PI * p)) * (peak / Math.max(1, h * 0.26));
    const sy = 1 - squash + stretch * (1 - Math.exp(-((near / 0.06) ** 2)));
    const sq = Math.max(0.78, sy);
    const fade = t < first.start ? clamp01((t - (first.start - 1.2)) / 0.4) : 1;
    dot.style.cssText = `opacity:${fade.toFixed(3)};transform:translate(${x.toFixed(1)}px,${(y - lift - box.width * 0.008).toFixed(1)}px) translate(-50%,-100%) scale(${(1 / sq).toFixed(3)},${sq.toFixed(3)})`;
  }

  /* ---- the page around the video ------------------------------------ */

  /** progress, time, play state and the lyric line being sung */
  follow(t: number, v: Version): void {
    const k = Math.min(1, t / v.duration);
    this.drawWave(k);
    // the chip rides the playhead but never leaves the waveform
    if (this.els.head) this.els.head.style.left = `${(k * 100).toFixed(3)}%`;
    const clock = (x: number) =>
      `${Math.floor(x / 60)}:${String(Math.floor(x % 60)).padStart(2, '0')}`;
    const now = clock(t);
    if (this.els['chip-now'] && this.els['chip-now'].textContent !== now)
      this.els['chip-now'].textContent = now;
    const all = clock(v.duration);
    if (this.els['chip-all'] && this.els['chip-all'].textContent !== all)
      this.els['chip-all'].textContent = all;
    const playing = this.transport?.playing ?? false;
    if (this.els.play) this.els.play.dataset.playing = String(playing);
    const langName = v.lang === 'en' ? 'English' : '한국어';
    if (
      this.els['label-lang'] &&
      this.els['label-lang'].textContent !== langName
    )
      this.els['label-lang'].textContent = langName;
    if (this.page) {
      const started = String(playing || t > 0.05);
      const ended = String(!playing && t >= v.duration - 0.25);
      if (this.page.dataset.started !== started)
        this.page.dataset.started = started;
      if (this.page.dataset.ended !== ended) {
        this.page.dataset.ended = ended;
        // ran out while playing: the title becomes the poster's
        if (ended === 'true' && this.wasPlaying) this.endMove();
      }
      this.wasPlaying = playing;
      // the controls wake when the app is live, the picture is up and enough
      // of the mix is here to start (a prerendered page shows them dimmed)
      const ready = String(
        !!this.picture && !this.picture.failed && !!this.sound?.canStart(),
      );
      if (this.page.dataset.ready !== ready) this.page.dataset.ready = ready;
    }

    let line = -1;
    for (let i = 0; i < v.lyrics.lines.length; i++) {
      if (v.lyrics.lines[i]!.words[0]!.start - 0.15 <= t) line = i;
      else break;
    }
    if (line === this.nowLine || !this.page) return;
    this.nowLine = line;
    const list = this.page.querySelector<HTMLElement>(
      `.lv-sheet[data-sheet="${v.lang}"]`,
    );
    list?.querySelector('.is-now')?.classList.remove('is-now');
    const row = list?.querySelector<HTMLElement>(`[data-line="${line}"]`);
    if (row && list) {
      row.classList.add('is-now');
      // keep the sung line in the middle of the sheet, never scroll the page
      list.scrollTo({
        top: row.offsetTop - list.clientHeight / 2 + row.clientHeight / 2,
        behavior: playing ? 'smooth' : 'auto',
      });
    }
  }

  /* ---- depth: planes at their own distances -------------------------- */

  /** the MP4 export (`?render`): it alone draws the light motes */
  rendering =
    typeof window !== 'undefined' &&
    new URLSearchParams(window.location.search).has('render');
  motes?: HTMLElement[];
  moteList = Array.from({ length: LOW_POWER ? 5 : 9 }, (_, n) => n);

  /** each language's lines, with their words and a depth of their own */
  planeLines: Partial<
    Record<
      Lang,
      {
        el: HTMLElement;
        a: number;
        b: number;
        depth: number;
        words: HTMLElement[];
      }[]
    >
  > = {};

  linesOf(lang: Lang) {
    const known = this.planeLines[lang];
    if (known?.length) return known;
    const player = this.root?.closest('.lv-player');
    const list = [
      ...(player?.querySelectorAll<HTMLElement>(
        `[data-lang-layer="${lang}"] .cf-lyric[data-starts]`,
      ) ?? []),
    ].map((el, n) => {
      const starts = (el.dataset.starts ?? '').split(',').map(Number);
      const ends = (el.dataset.ends ?? '').split(',').map(Number);
      return {
        el,
        a: (starts[0] ?? 0) - 2,
        b: (ends[ends.length - 1] ?? 0) + 3,
        // lines sit a little nearer or further than the type plane, in turn
        depth: [0.18, -0.12, 0.06, -0.2, 0.12][n % 5]!,
        words: [...el.querySelectorAll<HTMLElement>('.cf-lyric-word')],
      };
    });
    this.planeLines[lang] = list;
    return list;
  }

  /**
   * The parallax of everything in front of the photo, scaled by distance:
   * each lyric line on its own plane (a nearer one slides further on a pan
   * and grows a touch on a push), each word riding a slow travelling wave,
   * and a colour split on the words that opens with the camera's speed.
   */
  planes(t: number, v: Version, pose: Pose): void {
    const card = this.page?.querySelector<HTMLElement>('.lv-card');
    if (!card) return;
    const w = card.clientWidth;
    // the camera's pan, as a share of the frame
    const panX = pose.x + pose.yaw / 30;
    const panY = pose.y - pose.pitch / 30;
    const push = 1 - pose.dolly;
    // the camera's speed (per second), for the split: from the camera path
    // itself a moment earlier, so it is the same however t was reached
    const before = this.cameras[v.lang](Math.max(0, t - 0.05));
    const speed =
      Math.hypot(
        pose.x - before.x,
        (pose.yaw - before.yaw) / 30,
        pose.dolly - before.dolly,
      ) / 0.05;
    const split = Math.round(Math.min(3, 0.4 + speed * 14) * 4) / 4;
    for (const layer of this.typeLayers) {
      const val = split.toFixed(2);
      if (layer.style.getPropertyValue('--split') !== val)
        layer.style.setProperty('--split', val);
    }

    const lite = this.page?.dataset.lite === 'true';
    for (const line of this.linesOf(v.lang)) {
      if (t < line.a || t > line.b) continue;
      const d = line.depth;
      line.el.style.translate = `${(-panX * d * w * 0.5).toFixed(1)}px ${(panY * d * w * 0.3).toFixed(1)}px`;
      line.el.style.scale = (1 + push * d * 0.35).toFixed(4);
      // the wave runs through the line, word to word, slow as breathing
      if (!lite)
        line.words.forEach((word, k) => {
          const ph = t * 1.35 - k * 0.55 + d * 9;
          word.style.translate = `0 calc(${(Math.sin(ph) * 5).toFixed(2)} * var(--u))`;
          word.style.rotate = `${(Math.sin(ph + 1.1) * 0.7).toFixed(3)}deg`;
        });
    }

    // the near plane (export only): motes rising slowly, nearer ones faster,
    // each a pure function of t and the camera
    if (!this.rendering) return;
    const motes = (this.motes ??= [
      ...(this.page?.querySelectorAll<HTMLElement>('.lv-mote') ?? []),
    ]);
    motes.forEach((m, n) => {
      const depth = 1.4 + (n % 3) * 0.6;
      const seed = n * 12.9898;
      const bx = (((Math.sin(seed) * 43758.5453) % 1) + 1) % 1;
      const by = (((Math.sin(seed * 1.7) * 23421.631) % 1) + 1) % 1;
      const rise = (((by - t * 0.012 * depth) % 1) + 1) % 1;
      const y = rise * 1.2 - 0.1;
      const x = bx + Math.sin(t * 0.3 + n) * 0.02 - panX * depth * 0.5;
      const size = (1 + push * depth * 0.6) * (0.6 + depth * 0.4);
      m.style.transform = `translate3d(${((((x % 1) + 1) % 1) * 100).toFixed(2)}cqw, ${(y * 100).toFixed(2)}cqh, 0) scale(${size.toFixed(3)})`;
    });
  }

  /* ---- the frame ---------------------------------------------------- */

  prefetchedAt = -1;

  /** frame times while playing, to step quality down on a slow device */
  frameAt = 0;
  frameMs = 16;
  slowFrames = 0;

  pace(): void {
    const now = performance.now();
    const dt = now - this.frameAt;
    this.frameAt = now;
    if (!this.transport?.playing || dt > 250) return;
    this.frameMs += (dt - this.frameMs) * 0.05;
    this.slowFrames = this.frameMs > 24 ? this.slowFrames + 1 : 0;
    // about two seconds under 40 fps: fewer pixels, then the light version
    if (this.slowFrames > 90) {
      this.slowFrames = 0;
      this.frameMs = 16;
      if (!this.picture?.lower() && this.page) this.page.dataset.lite = 'true';
    }
  }

  paint(t: number): void {
    this.pace();
    const v = this.version;
    // each mix ends at its own length (the reel runs to the longer one)
    if (t >= v.duration - 0.02 && this.transport?.playing) {
      this.transport.pause();
      t = v.duration;
    }
    t = Math.min(t, v.duration);
    const lang = v.lang;
    const beat = beatLength(v);
    const bar = beat * 4;
    const section = sectionAt(v, t);
    const intro = section === undefined;
    const outro = t >= v.outro;
    // the picture holds still: no pumping or throbbing on the kick
    const kick = 0;

    // the shot, the one before it, and how far across the seam we are
    const list: Shot[] = this.shots[lang];
    const i = shotAt(list, t);
    const shot = list[i]!;
    const before = list[i - 1] ?? shot;
    const mix = shot.over > 0 ? prog(t, shot.start, shot.start + shot.over) : 1;
    const seam = SEAMS[shot.blend];
    const seamMix = mix;
    let flash = 0;
    this.starts[lang].forEach((s, k) => {
      if (t >= s - 0.05)
        flash = Math.max(
          flash,
          (isChorus(v, k) ? 0.1 : 0.05) * Math.exp(-(t - s + 0.05) * 5),
        );
    });
    const pose = this.cameras[lang](t);
    // across a seam the outgoing shot keeps the pose it ended its move on
    const crossing = seamMix < 1 && i > 0;
    const poseFrom = crossing ? this.cameras[lang](shot.start - 1e-3) : pose;
    const holding = mix > 0.5 ? shot.photo : before.photo;
    // the next few shots get their sharp images ahead of time
    const second = Math.floor(t);
    if (second !== this.prefetchedAt) {
      this.prefetchedAt = second;
      const near = new Set<Photo>([shot.photo]);
      for (let k = i + 1; k < list.length && list[k]!.start < t + 12; k++)
        near.add(list[k]!.photo);
      this.picture?.prefetch([...near]);
    }
    this.picture?.paint({
      from: crossing ? before.photo : shot.photo,
      to: shot.photo,
      mix: seamMix,
      seam,
      pose,
      poseFrom,
      kick,
      flash,
      time: t,
    });

    // the lyrics sit at their own depth under the same camera
    if (!this.typeLayers.length && this.root) {
      const player = this.root.closest('.lv-player');
      this.typeLayers = player
        ? [...player.querySelectorAll<HTMLElement>('[data-lang-layer]')]
        : [];
    }
    // the lyric plane never cuts: across a seam it eases from the outgoing
    // camera to the incoming one
    const glide = crossing ? mix * mix * (3 - 2 * mix) : 1;
    const typePose: Pose = {
      dolly: poseFrom.dolly + (pose.dolly - poseFrom.dolly) * glide,
      x: poseFrom.x + (pose.x - poseFrom.x) * glide,
      y: poseFrom.y + (pose.y - poseFrom.y) * glide,
      yaw: poseFrom.yaw + (pose.yaw - poseFrom.yaw) * glide,
      pitch: poseFrom.pitch + (pose.pitch - poseFrom.pitch) * glide,
    };
    const transform = this.picture?.typeTransform(typePose, holding) ?? '';
    for (const layer of this.typeLayers) layer.style.transform = transform;
    this.planes(t, v, typePose);

    const set = (k: string, css: string) => {
      const el = this.els[k];
      if (el) el.style.cssText = css;
    };

    // COLD OPEN: bars 7–8, the title builds letter by letter from the
    // centre on springs, then leaves on the verse's downbeat
    const titleAt = v.downbeat + bar * 6;
    const verse = this.starts[lang][0]!;
    const titleOn = intro && t >= titleAt - 0.1;
    // the key art fades up over a beat, then pushes in and dissolves on the verse
    const push = prog(t, verse - 0.7, verse);
    // and the outro settles back onto the same key art, which the end screen holds
    const settle = outro ? prog(t, v.outro, v.outro + bar) : 0;
    // (opacity and transforms only: no blur, it's cheap on a phone)
    set(
      'intro',
      titleOn
        ? `opacity:${(prog(t, titleAt - 0.1, titleAt + beat * 0.5) * (1 - prog(t, verse - 0.25, verse))).toFixed(3)};transform:scale(${(1.03 - 0.03 * expoOut(prog(t, titleAt, titleAt + bar)) + 0.2 * push * push * push).toFixed(4)})`
        : outro
          ? `opacity:${expoOut(settle).toFixed(3)};transform:scale(${(1.08 - 0.08 * expoOut(settle)).toFixed(4)})`
          : 'opacity:0',
    );
    const keyart = String(titleOn || outro);
    if (this.page && this.page.dataset.keyart !== keyart)
      this.page.dataset.keyart = keyart;
    if (outro && !titleOn) {
      for (const el of this.letters) el.style.cssText = 'opacity:1';
    }
    if (titleOn) {
      // one word per eighth from the bar's downbeat, its letters a flick
      // apart: each drops in from alternate sides with a spin and a snap,
      // its cyan/red ghosts closing as it lands; then the words keep
      // breathing on a slow wave, and on the verse they scatter upward
      const leave = verse - beat;
      this.letters.forEach((el, n) => {
        const word = this.letterWord[n] ?? 0;
        const at =
          titleAt +
          word * (beat / 2) +
          (n - (this.wordFirst[word] ?? 0)) * 0.028;
        const s = spring(t - at, 420, 19);
        const side = n % 2 ? 1 : -1;
        const out = prog(t, leave + n * 0.018, leave + n * 0.018 + beat);
        const o = out * out;
        const wave = Math.sin((t - at) * 2.2 - n * 0.5) * 4 * clamp01(t - at);
        const split = (1 - clamp01(s)) * 18 + o * 24;
        el.style.opacity = t >= at ? (1 - o).toFixed(3) : '0';
        el.style.transform = `translate(calc(${(side * (1 - s) * 30).toFixed(1)} * var(--u)), calc(${((1 - s) * -120 * side + wave - o * 160).toFixed(1)} * var(--u))) rotate(${(side * (1 - s) * 24 + o * side * 20).toFixed(2)}deg) scale(${(1 + (1 - s) * 0.5).toFixed(3)})`;
        el.style.textShadow =
          split > 0.5
            ? `calc(${(-split).toFixed(1)} * var(--u)) 0 rgba(25,219,239,.8), calc(${split.toFixed(1)} * var(--u)) 0 rgba(255,45,79,.8)`
            : '';
      });
    }

    // WRITERS: bars 2–6 of the cold open, one name a bar, out before the title
    const wAt = v.downbeat + bar * 1.5;
    const wOut = titleAt - bar * 0.5;
    const wOn = intro && t >= wAt - 0.2 && t < wOut + 0.6;
    // their ink follows the shot behind them: white on a dark one, ink on a pale
    // one, tweened across the seam so it never flips on a cut
    const darkness = (p: Photo) => (LIGHT_INK.has(p) ? 1 : 0);
    const dark =
      darkness(before.photo) +
      (darkness(shot.photo) - darkness(before.photo)) * clamp01(seamMix);
    const ink = (k: number, from: number) =>
      Math.round(from + (255 - from) * k);
    const inkOn = `${ink(dark, 18)},${ink(dark, 18)},${ink(dark, 24)}`;
    // the whole block rises slowly the whole time it is up
    const wUp = Math.max(0, t - wAt);
    set(
      'writers',
      `transform:translateY(calc(${(-wUp * 7).toFixed(1)} * var(--u)));opacity:${wOn ? (1 - prog(t, wOut, wOut + 0.5)).toFixed(3) : '0'};filter:blur(${(prog(t, wOut, wOut + 0.5) * 12).toFixed(1)}px);color:rgb(${inkOn});--wsub:rgba(${inkOn},.75);text-shadow:0 0 calc(30 * var(--u)) rgba(${dark > 0.5 ? '8,10,28,.55' : '235,240,248,.6'})`,
    );
    if (wOn) {
      const rise = (at: number) => {
        const s = spring(t - at, 170, 22);
        return `opacity:${clamp01((t - at) / 0.35).toFixed(3)};transform:translateY(calc(${((1 - s) * 40).toFixed(1)} * var(--u)));filter:blur(${((1 - clamp01(s)) * 10).toFixed(1)}px)`;
      };
      set('writers-head', rise(wAt));
      const last = this.writerEls.length - 1;
      this.writerEls.forEach((el, n) => {
        const at = wAt + bar * (0.5 + n);
        const next = at + bar;
        // each name lands on its bar; the ones before it step back
        const back = n < last ? prog(t, next - 0.05, next + 0.45) : 0;
        // never parked: each name keeps travelling (alternate ways) while it is up
        const up = Math.max(0, t - at);
        // it eases toward a stop, so a long name never travels out of frame
        const drift = (n % 2 ? -1 : 1) * 36 * (1 - Math.exp(-up / 2.5));
        el.style.cssText = `opacity:${t >= at - 0.05 ? (1 - 0.6 * back).toFixed(3) : '0'};transform:translateX(calc(${(drift - back * 18).toFixed(1)} * var(--u))) scale(${(1 - 0.12 * back + up * 0.006).toFixed(4)})`;
        this.writerChars[n]?.forEach((ch, i) => {
          const a = at + i * 0.026;
          const sp = spring(t - a, 230, 17);
          const c = clamp01(sp);
          const split = (1 - c) * 28 + 1.2;
          ch.style.cssText = `opacity:${clamp01((t - a) / 0.1).toFixed(3)};transform:translateY(calc(${((1 - sp) * 80).toFixed(1)} * var(--u))) rotateX(${((1 - c) * 80).toFixed(1)}deg);filter:blur(${((1 - c) * 9).toFixed(1)}px);text-shadow:calc(${(-split).toFixed(1)} * var(--u)) 0 rgba(25,219,239,.85),calc(${split.toFixed(1)} * var(--u)) 0 rgba(255,45,79,.85)`;
        });
        const rule = this.writerRules[n];
        if (rule)
          rule.style.transform = `scaleX(${expoOut(prog(t, at + 0.1, at + 0.75)).toFixed(4)})`;
      });
      set('writers-pub', rise(wAt + bar * (0.5 + this.writerEls.length)));
    }

    // NOW PLAYING: glides in at each section head, holds two bars, settles
    const head = section !== undefined ? this.starts[lang][section]! : 0;
    const since = t - head;
    const tagIn = !intro && !outro ? spring(since, 200, 20) : 0;
    const tagDim = since > bar * 2 ? 0.35 : 1;
    set(
      'tag',
      `opacity:${(tagIn * (since > bar * 2 ? tagDim + (1 - tagDim) * (1 - prog(since, bar * 2, bar * 2 + 0.6)) : 1)).toFixed(3)};transform:translateX(calc(${((1 - tagIn) * -40).toFixed(1)} * var(--u)))`,
    );
    if (this.els['tag-lang']) {
      const l = lang === 'en' ? 'EN' : 'KO';
      if (this.els['tag-lang'].textContent !== l)
        this.els['tag-lang'].textContent = l;
    }

    // the interlude's "oh, yeah"
    const [a0, a1] = v.interlude;
    const adlib =
      t >= a0 && t < a1 + 0.4
        ? expoOut((t - a0) / 0.5) * (1 - prog(t, a1, a1 + 0.4))
        : 0;
    set(
      'adlib',
      `opacity:${adlib.toFixed(3)};transform:rotate(-6deg) scale(${(0.94 + 0.06 * spring(t - a0) + (t - a0) * 0.01).toFixed(4)})`,
    );

    this.follow(t, v);
    this.bounce(t, v);

    // OUTRO: the key art closes the song (the old cover-card is retired)
    set('outro', 'opacity:0');
  }

  <template>
    <style>
      {{this.sheet}}
    </style>
    <div
      class='lv-page'
      data-lang={{this.lang}}
      data-title={{this.titleStyle}}
      data-started='false'
      data-ended='false'
      data-ready='false'
    >
      <div class='lv-card'>
        <div class='lv-player' data-lang={{this.lang}}>
          <Reel
            @name='lyric-video'
            @duration={{DURATION}}
            @fps={{FPS}}
            @width={{1920}}
            @height={{1080}}
            @fit='fill'
            @contained={{true}}
            @keys={{false}}
            @background='#05060f'
            @fonts={{this.fonts}}
            @prepare={{this.prepare}}
            @sink={{this.sink}}
            class='lv'
            as |r|
          >
            <r.Layer @name='back' @z={{0}}>
              <div class='lv-root' {{this.setup}} {{this.clocked r}}>
                <canvas class='lv-back'></canvas>
              </div>
            </r.Layer>

            {{#each this.scenesEn as |s|}}
              <r.Scene
                @id={{s.id}}
                @at={{s.at}}
                @until={{s.until}}
                @layer={{2}}
                data-lang-layer='en'
                as |c|
              >
                {{#each s.lines as |l|}}
                  <Lyric
                    @c={{c}}
                    @id={{l.id}}
                    @words={{l.words}}
                    @at={{s.at}}
                    @exit={{l.exit}}
                    @beat={{this.grid.en.beat}}
                    @downbeat={{this.grid.en.downbeat}}
                    @keys={{l.keys}}
                    @size={{l.size}}
                    @font='Pretendard'
                    class='lv-place-{{l.place}} lv-ink-{{l.ink}}'
                    data-starts={{l.starts}}
                    data-ends={{l.ends}}
                  />
                {{/each}}
              </r.Scene>
            {{/each}}
            {{#each this.scenesKo as |s|}}
              <r.Scene
                @id={{s.id}}
                @at={{s.at}}
                @until={{s.until}}
                @layer={{2}}
                data-lang-layer='ko'
                as |c|
              >
                {{#each s.lines as |l|}}
                  <Lyric
                    @c={{c}}
                    @id={{l.id}}
                    @words={{l.words}}
                    @at={{s.at}}
                    @exit={{l.exit}}
                    @beat={{this.grid.ko.beat}}
                    @downbeat={{this.grid.ko.downbeat}}
                    @keys={{l.keys}}
                    @size={{l.size}}
                    @font='Pretendard'
                    @translation={{l.translation}}
                    class='lv-place-{{l.place}} lv-ink-{{l.ink}}'
                    data-starts={{l.starts}}
                    data-ends={{l.ends}}
                  />
                {{/each}}
              </r.Scene>
            {{/each}}

            <r.Layer @name='front' @z={{3}}>
              <canvas class='lv-front'></canvas>
            </r.Layer>

            <r.Layer @name='overlay' @z={{4}}>
              <div class='lv-over'>
                {{! the nearest plane, in the video export only: soft motes of light }}
                {{#if this.rendering}}
                  <div class='lv-motes' aria-hidden='true'>
                    {{#each this.moteList}}<i class='lv-mote'></i>{{/each}}
                  </div>
                {{/if}}
                {{! the cold open lands on the key art: the cover, the title, her in front }}
                <div class='lv-keyart' data-lv='intro'>
                  <img
                    class='lv-ka-plate'
                    src={{@mediaUrl 'images/cover.jpg'}}
                    alt=''
                  />
                  <div class='lv-title lv-tt'>
                    {{#each this.titleLines as |line|}}
                      <span class='lv-tline'>
                        {{#each line as |w|}}
                          <span class='lv-word {{w.cls}}'>{{#each
                              w.letters
                              as |ch|
                            }}<span
                                class='lv-letter'
                              >{{ch}}</span>{{/each}}</span>
                        {{/each}}
                      </span>
                    {{/each}}
                  </div>
                  <img
                    class='lv-ka-plate lv-ka-cut'
                    src={{@mediaUrl 'cut/cover.webp'}}
                    alt=''
                  />
                </div>
                <div class='lv-tag' data-lv='tag'>
                  <i class='lv-eq'><b></b><b></b><b></b></i>
                  <span>Just Ask For It</span>
                  <em data-lv='tag-lang'>EN</em>
                </div>
                <div class='lv-adlib' data-lv='adlib'>oh, yeah</div>
                <div class='lv-writers' data-lv='writers'>
                  <p class='lv-writers-head' data-lv='writers-head'>written by</p>
                  {{#each this.writerLetters as |w|}}
                    <p class='lv-writer'>
                      <span class='lv-wname'>{{#each w.letters as |ch|}}<span
                            class='lv-wl'
                          >{{ch}}</span>{{/each}}</span>
                      <i class='lv-writer-rule'></i>
                    </p>
                  {{/each}}
                  {{#if @publisher}}
                    <p class='lv-writers-pub' data-lv='writers-pub'>published by
                      {{@publisher}}</p>
                  {{/if}}
                </div>
                <div class='lv-outro' data-lv='outro'>
                  <img
                    class='lv-cover'
                    src={{@mediaUrl 'images/cover.jpg'}}
                    alt=''
                  />
                  <p class='lv-outro-title'><span class='lv-mark'><span
                        class='m-just'
                      >just</span>
                      <span class='m-ask'>ask</span>
                      <span class='m-for'>for</span>
                      <span class='m-it'>it</span></span></p>
                </div>
                <div class='lv-black' data-lv='black'></div>
              </div>
            </r.Layer>

          </Reel>
        </div>
        <div class='lv-poster'>
          {{! key art composited in HTML: a textured white ground, the cover, the
            title, her in front. On play the ground dissolves first, so nothing
            white is left framing the picture as it fades into the video. }}
          <div class='lv-poster-bg'></div>
          <img
            class='lv-poster-cover'
            src={{@mediaUrl 'images/cover.jpg'}}
            alt=''
          />
          <img
            class='lv-poster-cover lv-poster-cut'
            src={{@mediaUrl 'cut/cover.webp'}}
            alt=''
          />
          <div class='lv-poster-type'>
            <p class='lv-poster-title lv-tt'>{{#each
                this.titleLines
                as |line|
              }}<span class='lv-tline'>{{#each line as |w|}}<span
                      class='lv-word {{w.cls}}'
                    >{{w.text}}</span>{{/each}}</span>{{/each}}</p>
            <p class='lv-poster-sub'>
              <button
                type='button'
                class='lv-pick'
                data-pick='ko'
                {{on 'click' (fn this.pickLang 'ko')}}
              >한국어</button>
              <i></i>
              <button
                type='button'
                class='lv-pick'
                data-pick='en'
                {{on 'click' (fn this.pickLang 'en')}}
              >english</button>
            </p>
            <button
              type='button'
              class='lv-poster-cta'
              aria-label='Play'
              {{on 'click' this.togglePlay}}
            >
              <span class='lv-cta-icon'>
                <svg class='play' viewBox='0 0 24 24'><path
                    d='M8 5v14l11-7z'
                  /></svg>
                <svg class='again' viewBox='0 0 24 24'><path
                    d='M4 12a8 8 0 1 0 2.3-5.7M4 4v4h4'
                  /></svg>
              </span>
              <span class='play'>Play</span>
              <span class='again'>Play again</span>
              <span class='lv-cta-time'>{{this.runtime}}</span>
            </button>
          </div>
        </div>
        <button
          type='button'
          class='lv-tap'
          aria-label='Play or pause'
          {{on 'click' this.togglePlay}}
        ></button>
        <div class='lv-labels'>
          <span class='lv-label title'>Just Ask For It</span>
          <span
            class='lv-label lang'
            data-lv='label-lang'
          >{{this.langName}}</span>
        </div>
        <div class='lv-scrim' aria-hidden='true'></div>
        <i class='lv-dot' data-lv='dot' aria-hidden='true'></i>
        <canvas class='lv-wave-canvas' aria-hidden='true'></canvas>
        <button
          type='button'
          class='lv-wave'
          aria-label='Seek: drag along the waveform, or use the arrow keys'
          data-drag='false'
          {{on 'pointermove' this.waveMove}}
          {{on 'pointerup' this.waveRelease}}
          {{on 'pointercancel' this.waveRelease}}
          {{on 'pointerleave' this.waveLeave}}
          {{on 'keydown' this.waveKey}}
        >
          <span class='lv-wave-head' data-lv='head'></span>
          <span class='lv-time now' data-lv='chip-now'>0:00</span>
          <span class='lv-time all' data-lv='chip-all'></span>
        </button>
      </div>

      {{! under the video, never on it: the waveform, then play, title and tools }}
      <div class='lv-deck'>
        <div class='lv-row'>
          <button
            type='button'
            class='lv-play'
            data-lv='play'
            data-playing='false'
            aria-label='Play or pause'
            {{on 'click' this.togglePlay}}
          >
            <svg class='icon-play' viewBox='0 0 24 24' aria-hidden='true'><path
                d='M8 5v14l11-7z'
              /></svg>
            <svg class='icon-pause' viewBox='0 0 24 24' aria-hidden='true'><path
                d='M7 5h4v14H7zM13 5h4v14h-4z'
              /></svg>
          </button>
          <div class='lv-titling'>
            <h1 class='lv-name'><span class='lv-mark flat'><span
                  class='m-just'
                >just</span>
                <span class='m-ask'>ask</span>
                <span class='m-for'>for</span>
                <span class='m-it'>it</span></span></h1>
            <p class='lv-byline lv-caps'>{{this.writersLine}}</p>
          </div>
          <div class='lv-tools'>
            <button
              type='button'
              class='lv-lang'
              data-lv='lang'
              {{on 'click' this.switchLang}}
            >{{this.langLabel}}</button>
            <button
              type='button'
              class='lv-act'
              aria-label='Lyrics'
              {{on 'click' this.showLyrics}}
            >
              <svg viewBox='0 0 24 24' aria-hidden='true'><path
                  d='M4 6h16M4 11h16M4 16h10M17 15v5l4-2.5z'
                /></svg>
            </button>
            <button
              type='button'
              class='lv-act'
              aria-label='Share'
              {{on 'click' this.share}}
            >
              <svg viewBox='0 0 24 24' aria-hidden='true'><path
                  d='M12 3v12M7 8l5-5 5 5M5 13v7h14v-7'
                /></svg>
            </button>
            <button
              type='button'
              class='lv-act'
              data-lv='full'
              aria-label='Full screen'
              {{on 'click' this.fullscreen}}
            >
              <svg viewBox='0 0 24 24' aria-hidden='true'><path
                  d='M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5'
                /></svg>
            </button>
          </div>
        </div>
      </div>

      <section class='lv-info'>
        {{#if @credits}}<p class='lv-credit'>{{@credits}}</p>{{/if}}
        {{#if @publisher}}<p class='lv-credit'>Published by
            {{@publisher}}</p>{{/if}}
      </section>

      <section class='lv-lyrics' aria-label='Lyrics'>
        <h2>Lyrics</h2>
        <ol class='lv-sheet' data-sheet='en'>
          {{#each this.sheetEn as |l|}}
            {{#if l.head}}<li class='lv-head'>{{l.head}}</li>{{/if}}
            <li class='lv-line' data-line={{l.i}}><button
                type='button'
                {{on 'click' (fn this.jump l.start)}}
              >{{l.text}}</button></li>
          {{/each}}
        </ol>
        <ol class='lv-sheet' data-sheet='ko'>
          {{#each this.sheetKo as |l|}}
            {{#if l.head}}<li class='lv-head'>{{l.head}}</li>{{/if}}
            <li class='lv-line' data-line={{l.i}}><button
                type='button'
                {{on 'click' (fn this.jump l.start)}}
              >{{l.text}}{{#if l.translation}}<span
                    class='lv-tr'
                  >{{l.translation}}</span>{{/if}}</button></li>
          {{/each}}
        </ol>
      </section>
    </div>

    <style scoped>
      .lv-page {
        background: #0f0f10;
        color: #f1f1f1;
        font-family: Pretendard, system-ui, sans-serif;
        max-width: 1280px;
        margin: 0 auto;
      }
      .lv-player {
        position: relative;
        /* the video's final size from the first frame: nothing below it moves
           while the page loads, so an early tap lands where it's aimed */
        min-height: min(
          calc((min(100vw, 1280px) - 24px) * 9 / 16),
          calc(100vh - 100px)
        );
      }
      @media (max-width: 700px) and (orientation: portrait) {
        .lv-player {
          min-height: max(
            420px,
            min(
              calc((100vw - 16px) * 16 / 9),
              calc(
                100svh - 104px - env(safe-area-inset-top) -
                  env(safe-area-inset-bottom)
              )
            )
          );
        }
      }
      /* once the video is there the card hugs it exactly: the scrubber sits
         inside the picture, never in a strip below it */
      .lv-player:has(.cf-reel.lv) {
        min-height: 0;
      }
      .lv-card {
        position: relative;
        /* the labels and the dot are sized by the frame, not the screen, so
           they keep their proportion at any resolution (a 1920 export too) */
        container-type: inline-size;
        margin: 12px;
        border-radius: 16px;
        overflow: hidden;
        background: #05060f;
      }
      /* the in-video tag is for the render; the page has its labels */
      .lv-card .lv-tag {
        display: none;
      }
      /* the poster frame: the cover until the song starts (not on phones,
         which open on the video itself) */
      /* the album cover, whole, on its own pale studio sweep */
      .lv-poster {
        position: absolute;
        inset: 0;
        z-index: 4;
        container-type: size;
        background: transparent;
        pointer-events: none;
        transition: opacity 0.5s;
      }
      .lv-poster-bg {
        position: absolute;
        inset: 0;
        background-color: #d4dce7;
        background-image:
          url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='220' height='220'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3' stitchTiles='stitch'/%3E%3CfeColorMatrix values='0 0 0 0 .5 0 0 0 0 .52 0 0 0 0 .58 0 0 0 .07 0'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E"),
          radial-gradient(
            120% 90% at 70% 40%,
            #dbe3ed 0%,
            #d3dbe6 55%,
            #c8d0db 100%
          );
        transition: opacity 0.3s;
      }
      .lv-page[data-moving='true'] .lv-poster-bg,
      .lv-page[data-started='true']:not([data-ended='true']) .lv-poster-bg {
        opacity: 0;
      }
      .lv-poster-cover {
        position: absolute;
        top: 0;
        right: 3%;
        height: 100%;
        aspect-ratio: 1;
        object-fit: cover;
        -webkit-mask-image:
          linear-gradient(
            to right,
            transparent 0%,
            #000 14%,
            #000 88%,
            transparent 100%
          ),
          linear-gradient(
            to bottom,
            transparent 0%,
            #000 8%,
            #000 86%,
            transparent 100%
          );
        -webkit-mask-composite: source-in;
        mask-image:
          linear-gradient(
            to right,
            transparent 0%,
            #000 14%,
            #000 88%,
            transparent 100%
          ),
          linear-gradient(
            to bottom,
            transparent 0%,
            #000 8%,
            #000 86%,
            transparent 100%
          );
        mask-composite: intersect;
      }
      /* her, cut out, in front of the title */
      .lv-poster-cut {
        z-index: 2;
        -webkit-mask-image: none;
        mask-image: none;
        -webkit-mask-composite: source-over;
        mask-composite: add;
        filter: drop-shadow(0 0 1.5cqh rgba(40, 50, 80, 0.12));
      }
      /* the title: one face, huge, tucked behind her shoulder, with the
         cover's cyan and red misregistration */
      .lv-poster-title {
        margin: 0;
        display: grid;
        /* as big as the room left of her allows, in width and in height */
        font-size: clamp(
          6cqh,
          min(
            calc((91.5cqw - 84.7cqh) / var(--tw, 3.1)),
            calc((88cqh - 250px) / var(--th, 2.3))
          ),
          22cqh
        );
        white-space: nowrap;
      }
      /* one column left of her: title, language, play; never overlapping */
      .lv-poster-type {
        position: absolute;
        z-index: 1;
        left: 5.5%;
        top: 6cqh;
        bottom: 110px;
        display: flex;
        flex-direction: column;
        justify-content: center;
        align-items: flex-start;
        color: #16161d;
      }
      .lv-poster-sub {
        display: flex;
        align-items: center;
        gap: 1.2em;
        margin: 3.2cqh 0 0 0.15em;
        font:
          500 1.9cqh / 1 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: 0.32em;
        text-transform: uppercase;
        color: #56607a;
      }
      .lv-pick {
        font: inherit;
        letter-spacing: inherit;
        text-transform: inherit;
        color: inherit;
        background: none;
        border: 0;
        padding: 0.6em 0;
        opacity: 0.55;
        cursor: pointer;
        pointer-events: auto;
        background-image: linear-gradient(#ff2d4f, #ff2d4f);
        background-repeat: no-repeat;
        background-position: 0 100%;
        background-size: 0 1.5px;
        transition:
          opacity 0.2s,
          color 0.2s,
          background-size 0.35s cubic-bezier(0.2, 0.8, 0.2, 1);
      }
      .lv-pick:hover {
        opacity: 0.85;
      }
      .lv-page[data-lang='ko'] .lv-pick[data-pick='ko'],
      .lv-page[data-lang='en'] .lv-pick[data-pick='en'] {
        opacity: 1;
        color: #16161d;
        background-size: 100% 1.5px;
      }
      .lv-page[data-started='true']:not([data-ended='true']) .lv-pick {
        pointer-events: none;
      }
      .lv-poster-sub i {
        width: 3.5em;
        height: 1px;
        background: currentColor;
      }
      /* before the song starts the poster owns the card: its Play pill is the
         only thing that answers a touch (nothing under it can steal it) */
      .lv-page[data-started='false'] .lv-poster,
      .lv-page[data-ended='true'] .lv-poster {
        z-index: 8;
      }
      .lv-page[data-started='false'] .lv-poster-cta,
      .lv-page[data-ended='true'] .lv-poster-cta {
        pointer-events: auto;
        cursor: pointer;
      }
      .lv-page[data-started='false'] .lv-wave,
      .lv-page[data-started='false'] .lv-line button {
        pointer-events: none;
      }
      /* until the app, the picture and the mix are ready: dimmed, untappable */
      .lv-page[data-ready='false'] .lv-poster-cta,
      .lv-page[data-ready='false'] .lv-play,
      .lv-page[data-ready='false'] .lv-lang,
      .lv-page[data-ready='false'] .lv-act {
        opacity: 0.4;
        pointer-events: none;
      }
      .lv-page[data-ready='false'] .lv-tap,
      .lv-page[data-ready='false'] .lv-wave,
      .lv-page[data-ready='false'] .lv-line button {
        pointer-events: none;
      }
      .lv-page[data-ready='false'] .lv-poster-cta .play:not(svg)::after {
        content: '…';
      }
      .lv-page[data-started='true'] .lv-poster {
        opacity: 0;
        transition: opacity 0.4s;
      }
      /* each part of the poster leaves on its own during the move */
      .lv-page[data-moving='true'] .lv-poster {
        opacity: 1;
        transition: none;
      }
      .lv-page[data-moving='true'] .lv-labels {
        transition: opacity 0.3s 0.8s;
      }
      .lv-page[data-ended='true'] .lv-poster {
        display: block;
        opacity: 1;
      }
      /* one call to action, set with the title, never over her */
      .lv-poster-cta {
        border: 0;
        font-family: inherit;
        display: inline-flex;
        align-items: center;
        gap: 14px;
        margin-top: 4cqh;
        height: 56px;
        padding: 0 26px 0 8px;
        border-radius: 999px;
        background: #121218;
        color: #fff;
        font:
          600 16px/1 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: -0.005em;
        box-shadow: 0 10px 28px -14px rgba(18, 18, 24, 0.45);
        transition: transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1);
      }
      .lv-card:hover .lv-poster-cta {
        transform: translateY(-1px);
      }
      .lv-cta-icon {
        flex: none;
        width: 40px;
        height: 40px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        background: #ff2d4f;
      }
      .lv-poster-cta svg {
        width: 16px;
        height: 16px;
      }
      .lv-poster-cta svg.play {
        fill: currentColor;
        margin-left: 2px;
      }
      .lv-poster-cta svg.again {
        fill: none;
        stroke: currentColor;
        stroke-width: 2.4;
        stroke-linecap: round;
        stroke-linejoin: round;
      }
      .lv-cta-time {
        padding-left: 14px;
        border-left: 1px solid rgba(255, 255, 255, 0.14);
        font:
          400 11px/1 'Martian Mono',
          ui-monospace,
          monospace;
        letter-spacing: 0.1em;
        color: rgba(255, 255, 255, 0.6);
      }
      .lv-poster-cta .again,
      .lv-page[data-ended='true'] .lv-poster-cta .play {
        display: none;
      }
      .lv-page[data-ended='true'] .lv-poster-cta .again {
        display: inline;
      }
      .lv-page[data-ended='true'] .lv-poster-cta svg.again {
        display: block;
      }
      .lv-full {
        position: absolute;
        top: 12px;
        right: 12px;
        z-index: 7;
        width: 40px;
        height: 40px;
        border: 0;
        border-radius: 50%;
        background: rgba(10, 10, 12, 0.45);
        color: #fff;
        display: grid;
        place-items: center;
        cursor: pointer;
      }
      .lv-full[hidden] {
        display: none;
      }
      .lv-full svg {
        width: 20px;
        height: 20px;
        fill: none;
        stroke: currentColor;
        stroke-width: 2;
        stroke-linecap: round;
      }
      .lv-card:fullscreen {
        margin: 0;
        border-radius: 0;
        display: grid;
        place-items: center;
        background: #000;
      }
      .lv-card:fullscreen .lv-player {
        width: 100%;
      }
      .lv-card:fullscreen .lv {
        aspect-ratio: auto;
        height: 100vh;
        max-height: none;
      }
      .lv-tap {
        position: absolute;
        inset: 0;
        z-index: 5;
        border: 0;
        background: transparent;
        cursor: pointer;
      }
      /* ---- TYPE --------------------------------------------------------
         Simple: Pretendard for the title and text, Instrument Serif italic only
         for key lyric words, Martian Mono for the small metadata. */
      .lv-mark {
        font-family: Pretendard, system-ui, sans-serif;
        font-weight: 500;
        font-style: normal;
        letter-spacing: -0.02em;
        text-transform: capitalize;
      }
      /* metadata: a condensed mono with a slight edge */
      .lv-caps,
      .lv-byline,
      .lv-time,
      .lv-credit,
      .lv-lyrics h2,
      .lv-head,
      .lv-poster-sub {
        font-family:
          'Martian Mono', Pretendard, ui-monospace, monospace !important;
        font-stretch: 87.5%;
        font-variation-settings: 'wdth' 87.5;
        font-weight: 400 !important;
      }
      .lv-caps {
        font-size: 10px;
        line-height: 1.4;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        color: #8a8a93;
      }

      /* ---- THE DECK: under the video, never on it ----------------------- */
      .lv-deck {
        padding: 6px 20px 0;
      }
      .lv-dot {
        position: absolute;
        left: 0;
        top: 0;
        z-index: 6;
        --d: clamp(10px, 1.4cqw, 30px);
        width: var(--d);
        height: var(--d);
        border-radius: 50%;
        background: #ff2d4f;
        box-shadow:
          calc(var(--d) * -0.15) 0 0 rgba(25, 219, 239, 0.85),
          0 0 var(--d) rgba(255, 45, 79, 0.65);
        transform-origin: 50% 100%;
        opacity: 0;
        pointer-events: none;
        will-change: transform;
      }
      @media (max-width: 700px) and (orientation: portrait) {
        .lv-dot {
          --d: clamp(10px, 3cqw, 16px);
        }
      }
      /* the corner label while the video plays */
      .lv-labels {
        position: absolute;
        left: clamp(12px, 1.6cqw, 40px);
        top: clamp(12px, 1.6cqw, 40px);
        z-index: 6;
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: clamp(3px, 0.4cqw, 10px);
        pointer-events: none;
        transition: opacity 0.4s;
      }

      .lv-label {
        background: #0b0b0c;
        color: #fff;
        padding: 0.32em 0.58em 0.37em;
        font:
          600 clamp(14px, 1.9cqw, 44px) / 1.1 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: -0.01em;
      }
      .lv-label.lang {
        padding: 0.5em 0.9em 0.6em;
        font:
          400 clamp(10px, 1.05cqw, 24px) / 1.2 'Martian Mono',
          Pretendard,
          ui-monospace,
          monospace;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: #c9c9cf;
      }
      /* the scrubber lives in the video, over a soft shade at its foot */
      .lv-scrim {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        height: max(200px, 36%);
        z-index: 5;
        /* an eased curve (sine, softened): dense at the foot, melting upward */
        background: linear-gradient(
          to top,
          rgba(8, 10, 20, 0.5) 0%,
          rgba(8, 10, 20, 0.486) 8%,
          rgba(8, 10, 20, 0.447) 17%,
          rgba(8, 10, 20, 0.388) 25%,
          rgba(8, 10, 20, 0.316) 33%,
          rgba(8, 10, 20, 0.238) 42%,
          rgba(8, 10, 20, 0.165) 50%,
          rgba(8, 10, 20, 0.102) 58%,
          rgba(8, 10, 20, 0.054) 67%,
          rgba(8, 10, 20, 0.023) 75%,
          rgba(8, 10, 20, 0.007) 83%,
          rgba(8, 10, 20, 0.001) 92%,
          rgba(8, 10, 20, 0) 100%
        );
        pointer-events: none;
        transition: opacity 0.4s;
      }
      .lv-page[data-started='false'] .lv-scrim,
      .lv-page[data-ended='true'] .lv-scrim {
        opacity: 0;
      }
      .lv-wave {
        position: absolute;
        left: 20px;
        right: 20px;
        bottom: 12px;
        z-index: 6;
        display: block;
        height: 64px;
        padding: 0;
        border: 0;
        background: transparent;
        cursor: pointer;
        touch-action: none;
        -webkit-tap-highlight-color: transparent;
      }
      /* under the (transparent) scrub button, on the same box as its bars */
      .lv-wave-canvas {
        position: absolute;
        left: 20px;
        right: 20px;
        bottom: 26px;
        z-index: 6;
        width: calc(100% - 40px);
        height: 48px;
        display: block;
        pointer-events: none;
      }
      .lv-wave-head {
        position: absolute;
        top: 2px;
        height: 46px;
        left: 0;
        width: 1px;
        background: #fff;
        pointer-events: none;
        opacity: 0;
        transition: opacity 0.2s;
      }
      .lv-wave:hover .lv-wave-head,
      .lv-wave[data-drag='true'] .lv-wave-head,
      .lv-page[data-started='true'] .lv-wave-head {
        opacity: 1;
      }
      .lv-wave-head::after {
        content: '';
        position: absolute;
        left: 50%;
        top: -4px;
        width: 9px;
        height: 9px;
        border-radius: 50%;
        background: #fff;
        transform: translateX(-50%) scale(0.8);
        transition: transform 0.15s;
      }
      .lv-wave:hover .lv-wave-head::after,
      .lv-wave[data-drag='true'] .lv-wave-head::after {
        transform: translateX(-50%) scale(1.4);
      }
      .lv-time {
        position: absolute;
        bottom: 0;
        font:
          500 11px/1 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: 0.08em;
        font-variant-numeric: tabular-nums;
        color: rgba(255, 255, 255, 0.75);
        pointer-events: none;
      }
      .lv-page[data-started='false'] .lv-time.all,
      .lv-page[data-ended='true'] .lv-time.all {
        color: #56607a;
      }
      .lv-time.now {
        left: 0;
        color: #ff7a1a;
      }
      .lv-time.all {
        right: 0;
      }
      .lv-row {
        display: flex;
        align-items: center;
        gap: 16px;
        padding: 12px 0 10px;
      }
      .lv-play {
        flex: none;
        width: 52px;
        height: 52px;
        border: 0;
        border-radius: 50%;
        background: #ff5500;
        color: #fff;
        cursor: pointer;
        display: grid;
        place-items: center;
        box-shadow: 0 6px 24px rgba(255, 85, 0, 0.35);
      }
      .lv-play svg {
        width: 24px;
        height: 24px;
        fill: currentColor;
      }
      .lv-play .icon-play {
        margin-left: 3px;
      }
      .lv-play .icon-pause,
      .lv-play[data-playing='true'] .icon-play {
        display: none;
      }
      .lv-play[data-playing='true'] .icon-pause {
        display: block;
      }
      .lv-titling {
        flex: 1;
        min-width: 0;
      }
      .lv-name {
        margin: 0;
        font-size: clamp(24px, 3vw, 34px);
        line-height: 1.05;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .lv-byline {
        margin: 6px 0 0;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .lv-tools {
        flex: none;
        display: flex;
        align-items: center;
        gap: 4px;
      }
      .lv-act {
        width: 40px;
        height: 40px;
        border: 0;
        border-radius: 50%;
        background: transparent;
        color: #d6d6db;
        display: grid;
        place-items: center;
        cursor: pointer;
      }
      .lv-act:hover {
        background: rgba(255, 255, 255, 0.08);
        color: #fff;
      }
      .lv-act[hidden] {
        display: none;
      }
      .lv-act svg {
        width: 21px;
        height: 21px;
        fill: none;
        stroke: currentColor;
        stroke-width: 1.5;
        stroke-linecap: round;
        stroke-linejoin: round;
      }
      .lv-lang {
        height: 32px;
        margin-right: 6px;
        padding: 0 14px;
        border: 1px solid rgba(255, 255, 255, 0.22);
        border-radius: 999px;
        background: transparent;
        color: #eee;
        font:
          500 12px/1 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: 0.06em;
        cursor: pointer;
      }
      .lv-lang:hover {
        border-color: rgba(255, 255, 255, 0.5);
      }

      /* ---- credits and lyrics ---------------------------------------- */
      .lv-info {
        padding: 18px 20px 4px;
        border-top: 1px solid rgba(255, 255, 255, 0.07);
        margin: 0 20px;
        padding-left: 0;
        padding-right: 0;
      }
      .lv-credit {
        margin: 0 0 4px;
        font:
          500 10.5px/1.7 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: #6f6f78;
      }
      .lv-lyrics {
        margin: 20px;
        padding: 26px 28px;
        border-radius: 18px;
        background: #17171a;
      }
      .lv-lyrics h2 {
        margin: 0 0 6px;
        font:
          500 11px/1 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: 0.3em;
        text-transform: uppercase;
        color: #8a8a93;
      }
      .lv-sheet {
        list-style: none;
        margin: 0;
        padding: 0;
        max-height: 420px;
        overflow-y: auto;
        scroll-behavior: smooth;
        scrollbar-width: none;
        -webkit-mask-image: linear-gradient(
          to bottom,
          transparent,
          #000 24px,
          #000 calc(100% - 40px),
          transparent
        );
        mask-image: linear-gradient(
          to bottom,
          transparent,
          #000 24px,
          #000 calc(100% - 40px),
          transparent
        );
      }
      .lv-page[data-lang='en'] .lv-sheet[data-sheet='ko'],
      .lv-page[data-lang='ko'] .lv-sheet[data-sheet='en'] {
        display: none;
      }
      .lv-head {
        margin: 28px 0 8px;
        font:
          500 10px/1 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: 0.3em;
        text-transform: uppercase;
        color: #5c5c64;
      }
      .lv-line button {
        display: block;
        width: 100%;
        text-align: left;
        border: 0;
        background: transparent;
        color: #6e6e76;
        font:
          300 20px/1.5 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: -0.01em;
        padding: 3px 0;
        cursor: pointer;
        transition: color 0.3s;
      }
      .lv-line button:hover {
        color: #bdbdc4;
      }
      .lv-line.is-now button {
        color: #fff;
      }
      .lv-tr {
        display: block;
        font:
          300 14px/1.45 Pretendard,
          system-ui,
          sans-serif;
        color: #5c5c64;
      }
      .lv-line.is-now .lv-tr {
        color: #b9b9c0;
      }
      @media (max-width: 700px) and (orientation: portrait) {
        .lv-card {
          border-radius: 22px;
          margin: 8px;
          margin-top: calc(8px + env(safe-area-inset-top));
        }
        .lv-page {
          display: flex;
          flex-direction: column;
        }
        .lv-deck {
          padding: 2px 16px 0;
        }
        .lv-row {
          gap: 12px;
          padding: 10px 0 6px;
        }
        .lv-play {
          width: 46px;
          height: 46px;
        }
        .lv-name {
          font-size: clamp(18px, 5.6vw, 23px);
        }
        .lv-byline {
          font-size: 9.5px;
          letter-spacing: 0.18em;
        }
        .lv-tools .lv-act:not([data-lv='full']) {
          display: none;
        }
        .lv-lyrics {
          order: 1;
          margin: 8px 8px 12px;
          padding: 22px 20px;
        }
        .lv-info {
          order: 2;
          margin: 0 16px 24px;
        }
        .lv-sheet {
          max-height: 46vh;
        }
        .lv-line button {
          font-size: 18px;
        }
      }
      /* a phone held upright gets a vertical video, like Shorts */
      @media (max-width: 700px) and (orientation: portrait) {
        .lv-poster-cover {
          top: 4%;
          right: -12%;
          left: auto;
          width: 118%;
          height: auto;
          -webkit-mask-image:
            linear-gradient(
              to right,
              transparent 0%,
              #000 10%,
              #000 90%,
              transparent 100%
            ),
            linear-gradient(
              to bottom,
              transparent 0%,
              #000 8%,
              #000 78%,
              transparent 100%
            );
          -webkit-mask-composite: source-in;
          mask-image:
            linear-gradient(
              to right,
              transparent 0%,
              #000 10%,
              #000 90%,
              transparent 100%
            ),
            linear-gradient(
              to bottom,
              transparent 0%,
              #000 8%,
              #000 78%,
              transparent 100%
            );
          mask-composite: intersect;
        }
        .lv-poster-cut {
          -webkit-mask-image: linear-gradient(to bottom, #000 78%, transparent);
          mask-image: linear-gradient(to bottom, #000 78%, transparent);
        }
        .lv-poster-type {
          z-index: 3;
        }
        .lv-poster-title {
          font-size: min(calc(86cqw / var(--tw, 3.1)), 9cqh);
        }
        .lv-poster-type {
          left: 7%;
          right: 7%;
          top: 56%;
          bottom: 100px;
        }
        .lv-poster-cta {
          margin-top: 3cqh;
        }
      }
      .lv-root,
      .lv-over {
        position: absolute;
        inset: 0;
      }
      .lv-back,
      .lv-front {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        display: block;
        pointer-events: none;
      }
      /* the writers, one a bar: dark ink on the pale opening shots */
      .lv-writers {
        position: absolute;
        left: 7%;
        bottom: 30%;
        opacity: 0;
        color: #121218;
        perspective: calc(900 * var(--u));
      }
      .lv-writers p {
        margin: 0;
        opacity: 0;
        transform-origin: 0 50%;
      }
      .lv-writers-head {
        font:
          italic 400 calc(52 * var(--u)) / 1.2 'Instrument Serif',
          serif;
        color: var(--wsub, #3c4254);
        margin-bottom: calc(14 * var(--u)) !important;
      }
      .lv-writer {
        position: relative;
        font:
          500 calc(112 * var(--u)) / 1.02 Pretendard,
          sans-serif;
        letter-spacing: -0.045em;
        text-transform: uppercase;
        padding-bottom: calc(10 * var(--u));
      }
      .lv-wname {
        display: inline-block;
        transform-style: preserve-3d;
      }
      .lv-wl {
        display: inline-block;
        transform-origin: 50% 100%;
      }
      .lv-writer-rule {
        position: absolute;
        left: 0;
        bottom: 0;
        width: calc(120 * var(--u));
        height: calc(4 * var(--u));
        background: #e8203f;
        transform: scaleX(0);
        transform-origin: 0 50%;
      }
      .lv-writers-pub {
        margin-top: calc(30 * var(--u)) !important;
        font:
          400 calc(20 * var(--u)) / 1 'Martian Mono',
          Pretendard,
          monospace;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: var(--wsub, #3c4254);
      }
      .lv-keyart {
        position: absolute;
        inset: 0;
        overflow: hidden;
        opacity: 0;
        transform-origin: 62% 30%;
        background: radial-gradient(
          120% 90% at 70% 45%,
          #d8e1ec 0%,
          #d2dae5 55%,
          #c6ced9 100%
        );
      }
      .lv-ka-plate {
        position: absolute;
        top: 0;
        right: 3%;
        height: 100%;
        aspect-ratio: 1;
        object-fit: cover;
        -webkit-mask-image:
          linear-gradient(
            to right,
            transparent 0%,
            #000 14%,
            #000 88%,
            transparent 100%
          ),
          linear-gradient(
            to bottom,
            transparent 0%,
            #000 8%,
            #000 86%,
            transparent 100%
          );
        -webkit-mask-composite: source-in;
        mask-image:
          linear-gradient(
            to right,
            transparent 0%,
            #000 14%,
            #000 88%,
            transparent 100%
          ),
          linear-gradient(
            to bottom,
            transparent 0%,
            #000 8%,
            #000 86%,
            transparent 100%
          );
        mask-composite: intersect;
      }
      .lv-ka-cut {
        z-index: 2;
        -webkit-mask-image: none;
        mask-image: none;
      }
      /* the same title as the poster, sized to the free width left of her */
      .lv-title {
        position: absolute;
        z-index: 1;
        left: 5.5%;
        top: 17%;
        display: grid;
        font-size: clamp(
          6cqh,
          min(
            calc((91.5cqw - 84.7cqh) / var(--tw, 3.1)),
            calc(70cqh / var(--th, 2.3))
          ),
          22cqh
        );
        white-space: nowrap;
      }
      /* THE TITLE in the lyrics' own type: light lowercase Pretendard with
         Instrument Serif italic key words, in ink (the plates are pale) */
      .lv-tt {
        font-family: Pretendard, sans-serif;
        font-weight: 200;
        line-height: 0.98;
        letter-spacing: -0.03em;
        text-transform: lowercase;
        color: #121218;
        text-shadow:
          -0.012em 0 0 rgba(25, 219, 239, 0.6),
          0.012em 0 0 rgba(255, 45, 79, 0.55);
      }
      .lv-tt .lv-tline {
        display: flex;
        align-items: baseline;
        gap: 0.24em;
      }
      .lv-page[data-title='a'] .lv-tt .w-it,
      .lv-page[data-title='b'] .lv-tt .w-ask,
      .lv-page[data-title='c'] .lv-tt .w-ask,
      .lv-page[data-title='c'] .lv-tt .w-it {
        font-family: 'Instrument Serif', serif;
        font-style: italic;
        font-weight: 400;
        font-size: 1.5em;
        line-height: 0.8;
        letter-spacing: 0;
      }
      .lv-page[data-title='b'] .lv-tt .w-ask {
        color: #e8203f;
      }
      .lv-page[data-title='a'] .lv-tt {
        --tw: 3.1;
        --th: 2.2;
      }
      .lv-page[data-title='b'] .lv-tt {
        --tw: 3.5;
        --th: 2.2;
      }
      /* c: one line, both verbs of the ask in the serif */
      .lv-page[data-title='c'] .lv-tt {
        --tw: 6.2;
        --th: 1.3;
        display: flex;
        align-items: baseline;
        gap: 0.24em;
      }
      .lv-page[data-title='c'] .lv-title {
        top: auto;
        bottom: 30%;
      }
      .lv-page[data-title='c'] .lv-tt .lv-tline {
        display: contents;
      }
      .lv-word {
        display: inline-flex;
      }
      .lv-letter {
        display: inline-block;
        opacity: 0;
      }
      /* at the end the poster's title takes over from the key art's */
      .lv-page[data-ended='true'] [data-lv='intro'] .lv-title {
        visibility: hidden;
      }
      .lv-tag {
        position: absolute;
        left: calc(56 * var(--u));
        top: calc(48 * var(--u));
        display: flex;
        align-items: center;
        gap: calc(12 * var(--u));
        opacity: 0;
        font:
          500 calc(24 * var(--u)) / 1 Pretendard,
          sans-serif;
        font-weight: 300;
        letter-spacing: 0.04em;
        color: #fff;
        text-shadow: 0 0 calc(12 * var(--u)) rgba(8, 10, 28, 0.7);
      }
      .lv-tag em {
        font-style: normal;
        font-size: 0.7em;
        letter-spacing: 0.2em;
        opacity: 0.75;
      }
      .lv-eq {
        display: flex;
        align-items: flex-end;
        gap: calc(3 * var(--u));
        height: calc(18 * var(--u));
      }
      .lv-eq b {
        width: calc(4 * var(--u));
        background: #ff2d4f;
        height: 60%;
      }
      .lv-eq b:nth-child(2) {
        height: 100%;
      }
      .lv-eq b:nth-child(3) {
        height: 40%;
      }
      .lv-adlib {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        opacity: 0;
        font:
          italic 400 calc(240 * var(--u)) / 1 'Instrument Serif',
          serif;
        color: #fff;
        text-shadow:
          calc(-10 * var(--u)) 0 #19dbef,
          calc(10 * var(--u)) 0 #ff2d4f;
      }
      .lv-outro {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: calc(36 * var(--u));
        opacity: 0;
      }
      .lv-cover {
        width: calc(420 * var(--u));
        height: calc(420 * var(--u));
        object-fit: cover;
        box-shadow:
          calc(-14 * var(--u)) calc(-14 * var(--u)) 0 #19dbef,
          calc(14 * var(--u)) calc(14 * var(--u)) 0 #ff2d4f;
      }
      .lv-outro-title {
        margin: 0;
        font-size: calc(120 * var(--u));
        line-height: 1;
        color: #fff;
      }
      .lv-black {
        position: absolute;
        inset: 0;
        background: #000;
        opacity: 0;
        pointer-events: none;
      }
      .lv-chrome {
        position: absolute;
        right: 16px;
        bottom: 16px;
        display: flex;
        gap: 8px;
        z-index: 5;
      }
      .lv-chrome button {
        font:
          600 14px/1 system-ui,
          sans-serif;
        padding: 10px 14px;
        border-radius: 999px;
        border: 0;
        background: rgba(8, 10, 28, 0.75);
        color: #fff;
        cursor: pointer;
      }
      .lv-chrome button[data-lv='lang'] {
        background: #ff2d4f;
      }
    </style>
  </template>
}
