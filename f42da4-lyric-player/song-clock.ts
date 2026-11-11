/**
 * THE SONG AS NUMBERS: both mixes of "Just Ask For It", where their lines
 * fall, how one mix's second maps onto the other's, which photo is on screen
 * and where the camera is. Everything here is a pure function of t, so the
 * reel can stand any frame, and switching language mid-song is a seek.
 */
import type { SongLyrics, TimedLine } from './lyric-types';

/**
 * One beat of the English bounce. The Korean bounce is a touch faster, so
 * every version carries its own tempo; this is only the default.
 */
export const BEAT = 60 / 90;

export type Lang = 'en' | 'ko';

export interface Version {
  lang: Lang;
  lyrics: SongLyrics;
  /** measured from the kick: EN holds 90.00 all song, KO 90.51 */
  bpm: number;
  /** the first kick of this bounce */
  downbeat: number;
  /** length of the bounce */
  duration: number;
  /** the "oh, yeah" between chorus 1 and verse 2 */
  interlude: [number, number];
  /** the closing title card starts here */
  outro: number;
  /** lyric font and its size relative to Anton */
  font: string;
  fontScale: number;
}

const NO_LYRICS: SongLyrics = { sections: [], lines: [] };

export const VERSIONS: Record<Lang, Version> = {
  en: {
    lang: 'en',
    // the lyrics are the SongVersion card's; the player fills them in
    lyrics: NO_LYRICS,
    bpm: 90,
    downbeat: 0.435,
    duration: 274,
    interlude: [109.7, 113.7],
    outro: 272,
    font: 'Anton',
    fontScale: 1,
  },
  ko: {
    lang: 'ko',
    lyrics: NO_LYRICS,
    bpm: 90.51,
    downbeat: 0.356,
    duration: 272,
    interlude: [109.9, 111.7],
    outro: 270.2,
    font: 'Black Han Sans',
    fontScale: 0.86,
  },
};

/** the reel is as long as the longer mix */
export const DURATION = Math.max(VERSIONS.en.duration, VERSIONS.ko.duration);

export const lineStart = (l: TimedLine) => l.words[0]!.start;
export const lineEnd = (l: TimedLine) => l.words[l.words.length - 1]!.end;
export const isTitle = (l: TimedLine) =>
  l.words.map((w) => w.text).join(' ') === 'JUST ASK FOR IT';

export function isChorus(v: Version, section: number): boolean {
  const name = v.lyrics.sections[section] ?? '';
  return name.includes('Chorus') && !name.startsWith('Pre');
}

/** first sung second of every section */
export function sectionStarts(v: Version): number[] {
  return v.lyrics.sections.map((_, s) => {
    const line = v.lyrics.lines.find((l) => l.section === s);
    return line ? lineStart(line) : 0;
  });
}

/** section at t; undefined before the first sung word */
export function sectionAt(v: Version, t: number): number | undefined {
  let found: number | undefined;
  for (const l of v.lyrics.lines) {
    if (lineStart(l) - 0.3 > t) break;
    found = l.section;
  }
  return found;
}

/** when line i leaves: before the next one, or a while after its last word */
export function exitTime(v: Version, i: number): number {
  const line = v.lyrics.lines[i]!;
  const hold = isTitle(line) ? 3 : 2.2;
  const latest = Math.min(lineEnd(line) + hold, v.outro - 0.2);
  const next = v.lyrics.lines[i + 1];
  if (!next) return latest;
  // gone before the next one lands (its exit takes 0.36 s), so two lines are
  // never on top of each other; the last word still gets a moment
  const lastWord = line.words[line.words.length - 1]!.start;
  return Math.min(
    latest,
    Math.max(lastWord + 0.25, lineStart(next) - 0.08 - 0.4),
  );
}

/** position on the beat grid; negative before the first kick */
export const beatLength = (v: Version) => 60 / v.bpm;

export const beatAt = (v: Version, t: number) =>
  (t - v.downbeat) / beatLength(v);

/** 1 on every kick, decaying to ~0 half a beat later */
export function pulse(v: Version, t: number, sharpness = 7): number {
  const b = beatAt(v, t);
  return b < 0 ? 0 : Math.exp(-(b - Math.floor(b)) * sharpness);
}

/**
 * The same musical moment in the other mix. The two bounces share an
 * arrangement but not a layout (the Korean verse 2 comes in two seconds
 * early), so the map is piecewise linear between matching section starts.
 */
export function mapTime(from: Version, to: Version, t: number): number {
  const a = [0, ...sectionStarts(from), from.outro, from.duration];
  const b = [0, ...sectionStarts(to), to.outro, to.duration];
  for (let k = 1; k < a.length; k++) {
    if (t <= a[k]! || k === a.length - 1) {
      const span = a[k]! - a[k - 1]! || 1;
      const p = Math.min(1, Math.max(0, (t - a[k - 1]!) / span));
      return b[k - 1]! + p * (b[k]! - b[k - 1]!);
    }
  }
  return t;
}

/* ---- scenes: one per section, holding its lines --------------------- */

export interface SceneLine {
  id: string;
  line: TimedLine;
  exit: number;
  title: boolean;
}

export interface SectionScene {
  id: string;
  name: string;
  at: number;
  until: number;
  chorus: boolean;
  lines: SceneLine[];
}

export function scenes(v: Version): SectionScene[] {
  const starts = sectionStarts(v);
  return v.lyrics.sections.map((name, s) => {
    const at = Math.max(0, starts[s]! - 0.4);
    const until = s + 1 < starts.length ? starts[s + 1]! - 0.4 : v.outro;
    const lines = v.lyrics.lines
      .map((line, i) => ({ line, i }))
      .filter(({ line }) => line.section === s)
      .map(({ line, i }) => ({
        id: `${v.lang}-l${i}`,
        line,
        exit: exitTime(v, i),
        title: isTitle(line),
      }));
    return {
      id: `${v.lang}-s${s}`,
      name,
      at,
      until,
      chorus: isChorus(v, s),
      lines,
    };
  });
}

/* ---- the picture: a shot plan, not a gallery ----------------------- */

/** Every photo, by its path in `media/` without the extension. */
export const PHOTOS = [
  'images/cover',
  'images/night_a',
  'images/night_b',
  'shots/eye',
  'shots/ponytail_whip',
  'shots/flame',
  'shots/neon_rain',
  // the second shoot: editorial and candid, she is smaller in the frame
  'v2/front_laugh_wide',
  'v2/front_finger_heart_wink_wide',
  'v2/front_shhh_bend_wide',
  'v2/walk_toward_wide',
  'v2/jump_dance_wide',
  'v2/seated_cube_wide',
  'v2/front_hand_pocket_wide',
  'v2/floor_overhead_wide',
  'v2/look_up_wide',
  'v2/right_turn_laugh_wide',
  'v2/wall_lean_right_wide',
  'v2/over_shoulder_tease_wide',
] as const;
export type Photo = (typeof PHOTOS)[number];

/** photos with a background-removed cutout in `media/cut/`, for parallax */
export const CUTOUTS = new Set<Photo>([
  'v2/front_laugh_wide',
  'v2/front_finger_heart_wink_wide',
  'v2/front_shhh_bend_wide',
  'v2/walk_toward_wide',
  'v2/jump_dance_wide',
  'v2/seated_cube_wide',
  'v2/front_hand_pocket_wide',
  'v2/floor_overhead_wide',
  'v2/look_up_wide',
  'v2/right_turn_laugh_wide',
  'v2/wall_lean_right_wide',
  'v2/over_shoulder_tease_wide',
]);

/** where the lyric sits on a shot: away from her face, along her gesture */
export type Place = 'low' | 'left' | 'right' | 'top' | 'diag' | 'side';

interface Framing {
  /** her face, 0..1 across and down the photo: a tall frame crops around it */
  fx: number;
  fy?: number;
  place: Place;
  /** a wide frame's push-in (dolly factor, 1 = the whole photo) */
  zoom?: number;
}

const FRAMING: Partial<Record<Photo, Framing>> = {
  'images/cover': { fx: 0.5, place: 'low' },
  'images/night_a': { fx: 0.45, place: 'side' },
  'images/night_b': { fx: 0.35, place: 'side' },
  'shots/eye': { fx: 0.45, place: 'right' },
  'shots/ponytail_whip': { fx: 0.4, place: 'low' },
  'shots/flame': { fx: 0.6, place: 'left' },
  'shots/neon_rain': { fx: 0.62, place: 'side' },
  'v2/front_laugh_wide': { fx: 0.2, fy: 0.47, place: 'right' },
  'v2/front_finger_heart_wink_wide': { fx: 0.71, fy: 0.55, place: 'left' },
  'v2/front_shhh_bend_wide': { fx: 0.72, fy: 0.34, place: 'left' },
  'v2/walk_toward_wide': { fx: 0.22, fy: 0.33, place: 'right' },
  'v2/jump_dance_wide': { fx: 0.72, fy: 0.4, place: 'left' },
  'v2/seated_cube_wide': { fx: 0.73, fy: 0.34, place: 'left' },
  'v2/front_hand_pocket_wide': { fx: 0.22, fy: 0.31, place: 'right' },
  'v2/floor_overhead_wide': { fx: 0.75, fy: 0.56, place: 'left' },
  'v2/look_up_wide': { fx: 0.79, fy: 0.4, place: 'left' },
  'v2/right_turn_laugh_wide': { fx: 0.28, fy: 0.47, place: 'right' },
  'v2/wall_lean_right_wide': { fx: 0.28, fy: 0.28, place: 'right' },
  'v2/over_shoulder_tease_wide': { fx: 0.21, fy: 0.32, place: 'right' },
};

/**
 * Shots shown mirrored, so she isn't always turned the same way: half of the
 * ones where she looks over her shoulder to the left now look right.
 */
/** macro shots (an eye, lips): the camera drifts across them but never pushes in */
const CLOSE_UPS = new Set<Photo>(['shots/eye']);

export const MIRROR = new Set<Photo>(['shots/ponytail_whip']);

const SWAP: Partial<Record<Place, Place>> = { left: 'right', right: 'left' };

/** the dark shots: lyrics stay white on these, and go ink on everything else (pale) */
export const LIGHT_INK = new Set<Photo>([
  'images/night_a',
  'images/night_b',
  'shots/eye',
  'shots/flame',
  'shots/neon_rain',
]);

export const framing = (p: Photo): Required<Framing> => {
  const plain = FRAMING[p] ?? { fx: 0.5, place: 'low' as Place };
  const f = MIRROR.has(p)
    ? { ...plain, fx: 1 - plain.fx, place: SWAP[plain.place] ?? plain.place }
    : plain;
  // close-ups hold the face mid-frame; everything else has it in the top third
  const close = /eye|lips|kiss|bliss|face_frame|wink/.test(p);
  // the second shoot has her small in a wide frame: a wide screen pushes in
  return { fy: close ? 0.45 : 0.3, zoom: p.startsWith('v2/') ? 0.8 : 1, ...f };
};

/** How a shot arrives. */
export type Blend = 'glass' | 'dissolve' | 'whip' | 'glitch';

export interface Shot {
  start: number;
  photo: Photo;
  blend: Blend;
  /** seconds the blend takes, on the beat grid */
  over: number;
}

/**
 * The chorus follows her moods, not the words: no literal sun, moon or
 * stars. Both versions sing the chorus in the same order, so one plan per
 * chorus serves both.
 */
const CHORUS: Record<string, Photo[]> = {
  'Chorus 1': [
    'v2/front_laugh_wide',
    'v2/jump_dance_wide',
    'v2/front_finger_heart_wink_wide',
    'v2/right_turn_laugh_wide',
    'v2/over_shoulder_tease_wide',
    'v2/front_shhh_bend_wide',
    'v2/look_up_wide',
    'v2/walk_toward_wide',
    'v2/seated_cube_wide',
    'v2/wall_lean_right_wide',
    'v2/front_hand_pocket_wide',
    'v2/front_laugh_wide',
    'v2/jump_dance_wide',
  ],
  'Chorus 2': [
    'v2/jump_dance_wide',
    'v2/front_finger_heart_wink_wide',
    'v2/front_laugh_wide',
    'v2/walk_toward_wide',
    'v2/front_shhh_bend_wide',
    'v2/seated_cube_wide',
    'v2/right_turn_laugh_wide',
    'v2/look_up_wide',
    'v2/over_shoulder_tease_wide',
    'v2/wall_lean_right_wide',
    'v2/front_hand_pocket_wide',
    'v2/front_laugh_wide',
  ],
  'Final Chorus': [
    'v2/look_up_wide',
    'v2/jump_dance_wide',
    'v2/front_finger_heart_wink_wide',
    'v2/front_laugh_wide',
    'v2/walk_toward_wide',
    'v2/front_shhh_bend_wide',
    'v2/right_turn_laugh_wide',
    'v2/seated_cube_wide',
    'v2/over_shoulder_tease_wide',
    'v2/front_hand_pocket_wide',
    'v2/wall_lean_right_wide',
    'v2/jump_dance_wide',
  ],
};

/** the rest change every second line, from the section's own pool, by mood */
const POOLS: Record<string, Photo[]> = {
  // cool, sizing him up
  'Verse 1': [
    'v2/over_shoulder_tease_wide',
    'v2/front_laugh_wide',
    'v2/wall_lean_right_wide',
    'v2/walk_toward_wide',
    'v2/front_hand_pocket_wide',
  ],
  // fire
  'Pre-Chorus 1': ['shots/flame', 'v2/seated_cube_wide', 'images/night_b'],
  // the night we met
  'Verse 2': [
    'v2/right_turn_laugh_wide',
    'v2/front_laugh_wide',
    'v2/look_up_wide',
    'v2/front_hand_pocket_wide',
  ],
  // tease
  'Pre-Chorus 2': [
    'v2/front_shhh_bend_wide',
    'v2/over_shoulder_tease_wide',
    'v2/front_finger_heart_wink_wide',
  ],
  // up all night
  Bridge: [
    'images/night_a',
    'v2/walk_toward_wide',
    'shots/neon_rain',
    'v2/floor_overhead_wide',
    'images/night_b',
  ],
};

/** the cold open, bar by bar: see `intro` in the player */
export const INTRO_BARS = 8;

/** snap to the version's grid, in `div` subdivisions of a beat */
export function snap(v: Version, t: number, div = 1): number {
  const step = beatLength(v) / div;
  return v.downbeat + Math.round((t - v.downbeat) / step) * step;
}

export function shots(v: Version): Shot[] {
  const bar = beatLength(v) * 4;
  const out: Shot[] = [
    // the cold open: eye, ponytail, the split silhouettes, the cover
    { start: 0, photo: 'shots/eye', blend: 'glitch', over: 0 },
    // the writers' bars, a new picture every bar: she keeps to the right,
    // their names take the left
    {
      start: snap(v, v.downbeat + bar),
      photo: 'v2/look_up_wide',
      blend: 'glass',
      over: beatLength(v),
    },
    {
      start: snap(v, v.downbeat + bar * 2),
      photo: 'v2/jump_dance_wide',
      blend: 'whip',
      over: beatLength(v) / 2,
    },
    {
      start: snap(v, v.downbeat + bar * 3),
      photo: 'v2/front_finger_heart_wink_wide',
      blend: 'glass',
      over: beatLength(v) / 2,
    },
    {
      start: snap(v, v.downbeat + bar * 4),
      photo: 'v2/front_shhh_bend_wide',
      blend: 'whip',
      over: beatLength(v) / 2,
    },
    {
      start: snap(v, v.downbeat + bar * 5),
      photo: 'v2/seated_cube_wide',
      blend: 'glass',
      over: beatLength(v) / 2,
    },
    {
      start: snap(v, v.downbeat + bar * 6),
      photo: 'images/cover',
      blend: 'glass',
      over: beatLength(v),
    },
  ];
  let inSection = 0;
  let last = -1;
  for (const line of v.lyrics.lines) {
    if (line.section !== last) {
      last = line.section;
      inSection = 0;
    }
    const name = v.lyrics.sections[line.section]!;
    const head = inSection === 0;
    const chorus = CHORUS[name];
    const at = snap(v, lineStart(line) - 0.12);
    if (chorus) {
      out.push({
        start: at,
        photo: chorus[inSection % chorus.length]!,
        blend: head ? 'glitch' : inSection % 4 === 3 ? 'whip' : 'glass',
        over: head ? beatLength(v) / 2 : beatLength(v) / 2,
      });
    } else if (inSection % 2 === 0) {
      const pool = POOLS[name] ?? ['images/cover'];
      out.push({
        start: at,
        photo: pool[(inSection / 2) % pool.length]!,
        blend: head ? 'glitch' : name === 'Bridge' ? 'glass' : 'dissolve',
        over: head ? beatLength(v) / 2 : beatLength(v),
      });
    }
    inSection++;
  }
  out.push({
    start: snap(v, v.interlude[0]),
    photo: 'shots/ponytail_whip',
    blend: 'whip',
    over: beatLength(v) / 2,
  });
  out.push({
    start: snap(v, v.outro),
    photo: 'images/cover',
    blend: 'glass',
    over: beatLength(v) * 2,
  });
  return out.sort((a, b) => a.start - b.start);
}

export function shotAt(list: Shot[], t: number): number {
  let i = 0;
  for (let k = 0; k < list.length; k++) if (list[k]!.start <= t) i = k;
  return i;
}

/** a camera pose, choreo's Camera3DState: dolly, pan and tilt of one shot */
export interface Pose {
  dolly: number;
  pitch: number;
  yaw: number;
  x: number;
  y: number;
  look?: { x: number; y: number; z: number };
}

export interface Waypoint extends Partial<Pose> {
  cut?: boolean;
  slots?: number;
}

const wobble = (n: number, k: number) => {
  const x = Math.sin(n * 91.7 + k * 13.1) * 43758.547;
  return (x - Math.floor(x)) * 2 - 1;
};

/**
 * The score's c.Camera3D @through path. Every shot is a splice (its own
 * clamped spline) with three waypoints across it, so the camera never
 * stops: a slow push or pull (a few percent), a small truck and pedestal,
 * a degree or two of pan and tilt, velocity carried through the middle.
 * The picture in every shot is at the origin; `look` stays there.
 */
export function cameraPath(v: Version): {
  from: Pose;
  through: Waypoint[];
  seconds: number;
} {
  const list = shots(v);
  const through: Waypoint[] = [];
  let prev = 0;
  list.forEach((s, n) => {
    const end = list[n + 1]?.start ?? v.duration;
    const len = Math.max(0.2, end - s.start);
    // a real move on every shot, never a still: a push or a pull of about a
    // fifth, a continuous slide across, and a turn of a couple of degrees so
    // the frame shifts in perspective. Pushes and pulls alternate.
    const push = n % 2 === 0;
    const side = wobble(n, 1) >= 0 ? 1 : -1;
    // never too close on skin: a gentle push, and none at all on a close-up
    const depth = CLOSE_UPS.has(s.photo) ? 0.03 : 0.16;
    const pose = (k: number, f: number): Waypoint => ({
      dolly: push ? 1 - depth * f : 1 - depth + depth * f,
      x: side * (-0.06 + 0.12 * f),
      y: wobble(n, 3) * 0.03 * (1 - 2 * f),
      yaw: side * (-2.5 + 5 * f),
      pitch: wobble(n, 7) * 1.5 * (1 - 2 * f),
      look: { x: 0, y: 0, z: 0 },
      cut: k === 0 && n > 0,
    });
    through.push({ ...pose(0, 0), slots: Math.max(0.02, s.start - prev) });
    through.push({ ...pose(1, 0.5), slots: len * 0.5 });
    through.push({ ...pose(2, 1), slots: len * 0.5 });
    prev = s.start + len;
  });
  return {
    from: {
      dolly: 1,
      pitch: 0,
      yaw: 0,
      x: 0,
      y: 0,
      look: { x: 0, y: 0, z: 0 },
    },
    through,
    seconds: prev,
  };
}
