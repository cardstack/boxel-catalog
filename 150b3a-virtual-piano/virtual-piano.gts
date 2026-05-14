// =============================================================================
// VirtualPianoCard — Full VP.net-compatible interactive piano
//
// Notation theory implemented:
//   • Letter keys → piano notes (C2–C7, 61 keys)
//   • [abc]       → chord beat (all keys play simultaneously)
//   • -           → rest beat (silence)
//   • |           → phrase divider / timing pause
//   • BPM rate    → beatMs = 60 000 / BPM controls auto-play speed
//   • Transposition → semitone shift via frequency multiplier
//   • ADSR envelope per note for natural piano sound
//   • Instrument profiles: classical | electric | organ | harpsichord
// =============================================================================
import {
  CardDef,
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  codeRef,
  realmURL,
  type Query,
  type LooseSingleCardDocument,
} from '@cardstack/runtime-common';
import PianoIcon from '@cardstack/boxel-icons/piano';
import type { Genre } from './genre';

/* @ts-expect-error import.meta is valid ESM */
const here: string = import.meta.url;
const musicSheetRef = codeRef(here, './music-sheet', 'MusicSheet');

/* ═══════════════════════════════════════════════════════════════════════════
   VP.NET KEYBOARD MAPPING — 61 keys C2–C7
   ─────────────────────────────────────────────────────────────────────────
   White keys per octave:
     Oct 2: 1 2 3 4 5 6 7
     Oct 3: 8 9 0 q w e r
     Oct 4: t y u i o p a        ← Middle C (t = C4)
     Oct 5: s d f g h j k
     Oct 6: l z x c v b n
     C7 only: m

   Black keys (Shift+key):
     Oct 2: ! @ $ % ^
     Oct 3: * ( Q W E
     Oct 4: T Y I O P
     Oct 5: S D G H J
     Oct 6: L Z C V B
   ═══════════════════════════════════════════════════════════════════════════ */
const KEYBOARD_MAPPING: Record<string, { note: string; octave: number }> = {
  /* oct 2 */ '1': { note: 'C', octave: 2 },
  '!': { note: 'C#', octave: 2 },
  '2': { note: 'D', octave: 2 },
  '@': { note: 'D#', octave: 2 },
  '3': { note: 'E', octave: 2 },
  '4': { note: 'F', octave: 2 },
  $: { note: 'F#', octave: 2 },
  '5': { note: 'G', octave: 2 },
  '%': { note: 'G#', octave: 2 },
  '6': { note: 'A', octave: 2 },
  '^': { note: 'A#', octave: 2 },
  '7': { note: 'B', octave: 2 },
  /* oct 3 */ '8': { note: 'C', octave: 3 },
  '*': { note: 'C#', octave: 3 },
  '9': { note: 'D', octave: 3 },
  '(': { note: 'D#', octave: 3 },
  '0': { note: 'E', octave: 3 },
  q: { note: 'F', octave: 3 },
  Q: { note: 'F#', octave: 3 },
  w: { note: 'G', octave: 3 },
  W: { note: 'G#', octave: 3 },
  e: { note: 'A', octave: 3 },
  E: { note: 'A#', octave: 3 },
  r: { note: 'B', octave: 3 },
  /* oct 4 */ t: { note: 'C', octave: 4 },
  T: { note: 'C#', octave: 4 },
  y: { note: 'D', octave: 4 },
  Y: { note: 'D#', octave: 4 },
  u: { note: 'E', octave: 4 },
  i: { note: 'F', octave: 4 },
  I: { note: 'F#', octave: 4 },
  o: { note: 'G', octave: 4 },
  O: { note: 'G#', octave: 4 },
  p: { note: 'A', octave: 4 },
  P: { note: 'A#', octave: 4 },
  a: { note: 'B', octave: 4 },
  /* oct 5 */ s: { note: 'C', octave: 5 },
  S: { note: 'C#', octave: 5 },
  d: { note: 'D', octave: 5 },
  D: { note: 'D#', octave: 5 },
  f: { note: 'E', octave: 5 },
  g: { note: 'F', octave: 5 },
  G: { note: 'F#', octave: 5 },
  h: { note: 'G', octave: 5 },
  H: { note: 'G#', octave: 5 },
  j: { note: 'A', octave: 5 },
  J: { note: 'A#', octave: 5 },
  k: { note: 'B', octave: 5 },
  /* oct 6 */ l: { note: 'C', octave: 6 },
  L: { note: 'C#', octave: 6 },
  z: { note: 'D', octave: 6 },
  Z: { note: 'D#', octave: 6 },
  x: { note: 'E', octave: 6 },
  c: { note: 'F', octave: 6 },
  C: { note: 'F#', octave: 6 },
  v: { note: 'G', octave: 6 },
  V: { note: 'G#', octave: 6 },
  b: { note: 'A', octave: 6 },
  B: { note: 'A#', octave: 6 },
  n: { note: 'B', octave: 6 },
  /* C7   */ m: { note: 'C', octave: 7 },
};

const SHIFT_KEY_MAPPING: Record<string, string> = {
  Digit1: '!',
  Digit2: '@',
  Digit4: '$',
  Digit5: '%',
  Digit6: '^',
  Digit8: '*',
  Digit9: '(',
  KeyQ: 'Q',
  KeyW: 'W',
  KeyE: 'E',
  KeyT: 'T',
  KeyY: 'Y',
  KeyI: 'I',
  KeyO: 'O',
  KeyP: 'P',
  KeyS: 'S',
  KeyD: 'D',
  KeyG: 'G',
  KeyH: 'H',
  KeyJ: 'J',
  KeyL: 'L',
  KeyZ: 'Z',
  KeyC: 'C',
  KeyV: 'V',
  KeyB: 'B',
};

function pianoKeyFromKeyboardEvent(e: KeyboardEvent): string {
  if (e.shiftKey) {
    return SHIFT_KEY_MAPPING[e.code] ?? e.key;
  }
  return e.key;
}

/* reverse map: "C4" → keyboard letter */
const NOTE_TO_KEY: Record<string, string> = {};
for (const [k, v] of Object.entries(KEYBOARD_MAPPING)) {
  NOTE_TO_KEY[`${v.note}${v.octave}`] = k;
}

/* ── Song data shape ─────────────────────────────────────────────────── */
interface SongData {
  title: string;
  artist: string;
  difficulty: number; /* VP.net scale 1–10: 1=SuperEasy 2-4=Easy 5-7=Inter 8-10=Expert */
  notation: string; /* raw text extracted from MarkdownField */
  tempo: number; /* BPM — 0 means use default 120 */
  genre: string[]; /* genre tags e.g. ["POP", "CLASSICAL"] — from GenreField.name */
  transposition: number;
  timeSignature: string;
}

/* ── Difficulty helpers (mirrors piano-song.gts) ─────────────────────── */
function diffLabel(level: number): string {
  if (!level) return '';
  if (level === 1) return 'SUPER EASY';
  if (level <= 4) return 'EASY';
  if (level <= 7) return 'INTERMEDIATE';
  return 'EXPERT';
}

function diffClass(level: number): string {
  if (!level) return 'diff-unknown';
  if (level === 1) return 'diff-super-easy';
  if (level <= 4) return 'diff-easy';
  if (level <= 7) return 'diff-intermediate';
  return 'diff-expert';
}

/* ── Piano key layout data ───────────────────────────────────────────── */
interface KeyData {
  note: string;
  octave: number;
  isBlack: boolean;
  id: string;
  kbKey: string;
  leftPx?: number; /* absolute left offset (px) for black keys only */
}

function buildKeyLayout(): KeyData[] {
  const WHITE_NOTES = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
  const BLACK_AFTER: Record<string, string> = {
    C: 'C#',
    D: 'D#',
    F: 'F#',
    G: 'G#',
    A: 'A#',
  };
  /* WW = white-key slot width: key (38 px) + flex gap (2 px) = 40 px */
  const WW = 40;
  /* BW = black key visual width */
  const BW = 26;
  const keys: KeyData[] = [];
  let wIdx = 0; /* running white-key counter for leftPx */
  for (const oct of [2, 3, 4, 5, 6]) {
    for (const note of WHITE_NOTES) {
      const id = `${note}${oct}`;
      keys.push({
        note,
        octave: oct,
        isBlack: false,
        id,
        kbKey: NOTE_TO_KEY[id] ?? '',
      });
      if (BLACK_AFTER[note]) {
        const bNote = BLACK_AFTER[note]!;
        const bid = `${bNote}${oct}`;
        /* Centre black key over the boundary between this white key and the next:
           right edge of wIdx key = (wIdx+1)*WW (gap is included),
           minus half black-key width = centre over that boundary. */
        const leftPx = (wIdx + 1) * WW - Math.round(BW / 2);
        keys.push({
          note: bNote,
          octave: oct,
          isBlack: true,
          id: bid,
          kbKey: NOTE_TO_KEY[bid] ?? '',
          leftPx,
        });
      }
      wIdx++;
    }
  }
  keys.push({ note: 'C', octave: 7, isBlack: false, id: 'C7', kbKey: 'm' });
  return keys;
}

const KEY_LAYOUT = buildKeyLayout();
const WHITE_KEYS = KEY_LAYOUT.filter((k) => !k.isBlack);
const BLACK_KEYS = KEY_LAYOUT.filter((k) => k.isBlack);

/* ═══════════════════════════════════════════════════════════════════════════
   BEAT PARSER
   VP.net notation rules:
     • Whitespace separates groups (phrase chunks)
     • Within a group, each CHARACTER = one beat played in sequence
     • [abc] inside a group = one chord beat (all keys simultaneously)
     • -  = rest beat (silence)
     • |  = phrase pause / timing separator
   ─────────────────────────────────────────────────────────────────────────
   Example: "pf[80wp]" → beat(p), beat(f), chord-beat(8,0,w,p)
   ═══════════════════════════════════════════════════════════════════════════ */
interface Beat {
  keys: string[]; /* keys to press; empty = rest */
  isChord: boolean; /* true when multiple keys from [...] */
  isPause: boolean; /* rest or phrase divider */
  display: string; /* what to render in the sheet */
}

function parseNotationBeats(notation: string): Beat[] {
  const beats: Beat[] = [];
  const chunks = notation.split(/\s+/).filter((t) => t.length > 0);
  for (const chunk of chunks) {
    let i = 0;
    while (i < chunk.length) {
      if (chunk[i] === '[') {
        const end = chunk.indexOf(']', i);
        if (end === -1) {
          i++;
          continue;
        }
        const inner = chunk.slice(i + 1, end);
        const keys = inner.split('').filter((k) => k in KEYBOARD_MAPPING);
        beats.push({
          keys,
          isChord: true,
          isPause: false,
          display: `[${inner}]`,
        });
        i = end + 1;
      } else if (chunk[i] === '-') {
        beats.push({ keys: [], isChord: false, isPause: true, display: '—' });
        i++;
      } else if (chunk[i] === '|') {
        beats.push({ keys: [], isChord: false, isPause: true, display: '|' });
        i++;
      } else {
        const k = chunk[i]!;
        if (k in KEYBOARD_MAPPING) {
          beats.push({ keys: [k], isChord: false, isPause: false, display: k });
        }
        i++;
      }
    }
  }
  return beats;
}

/* ── Global keyboard modifier ────────────────────────────────────────── */
const keyboardModifier = modifier(
  (
    _el: Element,
    [enabled, onDown, onUp, onCleanup]: [
      boolean,
      (e: KeyboardEvent) => void,
      (e: KeyboardEvent) => void,
      () => void,
    ],
  ) => {
    if (!enabled) return;
    const down = (e: KeyboardEvent) => onDown(e);
    const up = (e: KeyboardEvent) => onUp(e);
    const unload = () => onCleanup();
    window.addEventListener('keydown', down);
    window.addEventListener('keyup', up);
    window.addEventListener('beforeunload', unload);
    window.addEventListener('pagehide', unload);
    return () => {
      window.removeEventListener('keydown', down);
      window.removeEventListener('keyup', up);
      window.removeEventListener('beforeunload', unload);
      window.removeEventListener('pagehide', unload);
    };
  },
);

/* ── Sheet auto-scroll modifier ──────────────────────────────────────── */
const sheetAutoScrollModifier = modifier(
  (el: Element, [currentRowIndex]: [number]) => {
    const sheet = el.querySelector('.vp-sheet') as HTMLElement;
    if (!sheet) return;

    const row = sheet.querySelector(`[data-row-idx="${currentRowIndex}"]`);
    if (!row) return;

    const rowEl = row as HTMLElement;

    /* Scroll so current row is visible; aim for middle of viewport when playing */
    const sheetRect = sheet.getBoundingClientRect();
    const rowRect = rowEl.getBoundingClientRect();

    /* Check if row is below visible area or very near bottom */
    const isNearBottom = rowRect.top > sheetRect.bottom - 50;
    if (isNearBottom) {
      rowEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  },
);

/* ── Frequency calculation ───────────────────────────────────────────── */
const BASE_FREQS: Record<string, number> = {
  C: 261.63,
  'C#': 277.18,
  D: 293.66,
  'D#': 311.13,
  E: 329.63,
  F: 349.23,
  'F#': 369.99,
  G: 392.0,
  'G#': 415.3,
  A: 440.0,
  'A#': 466.16,
  B: 493.88,
};

function noteFreq(note: string, octave: number): number {
  return (BASE_FREQS[note] ?? 440) * Math.pow(2, octave - 4);
}

/* ── Instrument profiles (harmonic stacking + ADSR) ─────────────────── */
interface InstrumentProfile {
  harmonics: { ratio: number; gain: number; detune?: number }[];
  attack: number;
  decay: number;
  sustainLevel: number;
  releaseDecay: number; /* how fast the tail fades (seconds to near-zero) */
}

const INSTRUMENT_PROFILES: Record<string, InstrumentProfile> = {
  classical: {
    /* Grand piano: inharmonic overtones (real strings are slightly sharp above
       fundamental), two detuned unison oscillators for natural "chorus".
       ADSR: very fast attack → rapid initial decay → slow long tail (piano
       strings don't have a flat sustain level — they just keep decaying). */
    harmonics: [
      { ratio: 1.0, gain: 0.5 } /* fundamental */,
      { ratio: 1.0, gain: 0.1, detune: 5 } /* unison +5 cents */,
      { ratio: 2.005, gain: 0.22 } /* 2nd harmonic slightly sharp */,
      { ratio: 3.015, gain: 0.1 } /* 3rd */,
      { ratio: 4.03, gain: 0.06 } /* 4th */,
      { ratio: 5.05, gain: 0.03 } /* 5th */,
      { ratio: 6.08, gain: 0.015 } /* 6th */,
      { ratio: 8.13, gain: 0.008 } /* 8th */,
    ],
    attack: 0.004,
    decay: 0.12,
    sustainLevel: 0.18 /* piano strings continue decaying — no flat sustain */,
    releaseDecay: 1.8,
  },
  electric: {
    /* Rhodes-style: mellow mid harmonics, slightly warmer detune */
    harmonics: [
      { ratio: 1.0, gain: 0.42 },
      { ratio: 1.0, gain: 0.08, detune: 3 },
      { ratio: 2.002, gain: 0.28 },
      { ratio: 3.005, gain: 0.15 },
      { ratio: 4.01, gain: 0.08 },
      { ratio: 5.02, gain: 0.04 },
    ],
    attack: 0.012,
    decay: 0.2,
    sustainLevel: 0.25,
    releaseDecay: 1.2,
  },
  organ: {
    /* Hammond-style: perfectly harmonic, steady sustain — NO decay */
    harmonics: [
      { ratio: 1.0, gain: 0.38 },
      { ratio: 2.0, gain: 0.28 },
      { ratio: 3.0, gain: 0.2 },
      { ratio: 4.0, gain: 0.1 },
      { ratio: 6.0, gain: 0.04 },
    ],
    attack: 0.006,
    decay: 0.01,
    sustainLevel: 0.45,
    releaseDecay: 0.06,
  },
  harpsichord: {
    /* Sharp percussive attack, fast decay, bright upper harmonics */
    harmonics: [
      { ratio: 1.0, gain: 0.48 },
      { ratio: 2.002, gain: 0.26 },
      { ratio: 4.008, gain: 0.16 },
      { ratio: 8.02, gain: 0.08 },
      { ratio: 16.05, gain: 0.03 },
    ],
    attack: 0.003,
    decay: 0.03,
    sustainLevel: 0.06,
    releaseDecay: 0.5,
  },
  felt: {
    /* Felt/soft piano: muted, warm — piano with felt strip on strings */
    harmonics: [
      { ratio: 1.0, gain: 0.48 },
      { ratio: 2.002, gain: 0.14 },
      { ratio: 3.01, gain: 0.06 },
      { ratio: 4.02, gain: 0.03 },
    ],
    attack: 0.008,
    decay: 0.18,
    sustainLevel: 0.22,
    releaseDecay: 2.4,
  },
  bright: {
    /* Bright piano: strong upper harmonics, crisp attack */
    harmonics: [
      { ratio: 1.0, gain: 0.42 },
      { ratio: 1.0, gain: 0.09, detune: 7 },
      { ratio: 2.005, gain: 0.26 },
      { ratio: 3.02, gain: 0.16 },
      { ratio: 4.04, gain: 0.12 },
      { ratio: 5.08, gain: 0.08 },
      { ratio: 6.12, gain: 0.05 },
      { ratio: 8.2, gain: 0.03 },
    ],
    attack: 0.002,
    decay: 0.08,
    sustainLevel: 0.14,
    releaseDecay: 1.5,
  },
  symphonic: {
    /* Symphonic / Concert Grand: rich overtones, long tail */
    harmonics: [
      { ratio: 1.0, gain: 0.45 },
      { ratio: 1.0, gain: 0.12, detune: 4 },
      { ratio: 2.004, gain: 0.24 },
      { ratio: 3.012, gain: 0.14 },
      { ratio: 4.025, gain: 0.09 },
      { ratio: 5.045, gain: 0.05 },
      { ratio: 6.07, gain: 0.03 },
      { ratio: 7.1, gain: 0.02 },
    ],
    attack: 0.005,
    decay: 0.15,
    sustainLevel: 0.2,
    releaseDecay: 3.2,
  },
  violin: {
    /* Violin: slow bow attack, flat sustain, expressive tail */
    harmonics: [
      { ratio: 1.0, gain: 0.4 },
      { ratio: 2.0, gain: 0.3 },
      { ratio: 3.0, gain: 0.18 },
      { ratio: 4.0, gain: 0.08 },
      { ratio: 5.0, gain: 0.04 },
    ],
    attack: 0.08,
    decay: 0.05,
    sustainLevel: 0.42,
    releaseDecay: 0.3,
  },
  harp: {
    /* Harp: plucked, clean fast attack, warm decay */
    harmonics: [
      { ratio: 1.0, gain: 0.5 },
      { ratio: 2.001, gain: 0.22 },
      { ratio: 3.004, gain: 0.12 },
      { ratio: 4.009, gain: 0.07 },
      { ratio: 5.016, gain: 0.04 },
      { ratio: 6.025, gain: 0.02 },
    ],
    attack: 0.003,
    decay: 0.05,
    sustainLevel: 0.1,
    releaseDecay: 2.8,
  },
};

/* ═══════════════════════════════════════════════════════════════════════════
   ISOLATED COMPONENT — the full interactive piano
   ═══════════════════════════════════════════════════════════════════════════ */
class IsolatedVirtualPiano extends Component<typeof VirtualPiano> {
  /* ── Web Audio (non-tracked) ─────────────────────────────────────── */
  private audioCtx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private reverbNode: ConvolverNode | null = null;
  private reverbGain: GainNode | null = null;
  private sustainedNodes = new Map<string, OscillatorNode[]>();
  private activeKeyboardKeys = new Map<string, string>();
  private autoPlayTimer: ReturnType<typeof setTimeout> | null = null;
  /** AudioContext-clock anchor for auto-play scheduling (sub-ms accuracy) */
  private nextNoteTime = 0;
  private metronomeTimer: ReturnType<typeof setInterval> | null = null;
  private visualTimers = new Set<ReturnType<typeof setTimeout>>();

  /* ── Recording (MediaRecorder → WAV blob, in-memory only) ────────── */
  private mediaRecorder: MediaRecorder | null = null;
  private recordChunks: BlobPart[] = [];
  private recordDestination: MediaStreamAudioDestinationNode | null = null;
  private recordClockTimer: ReturnType<typeof setInterval> | null = null;

  /* ── UI state ────────────────────────────────────────────────────── */
  @tracked mode: 'play' | 'song' = 'play';
  @tracked overlayVisible: boolean = false;
  @tracked isRecording = false;
  @tracked recordPanelOpen = false;
  @tracked recordedBlob: Blob | null = null;
  @tracked recordSeconds = 0;
  @tracked replayProgress = 0;
  @tracked isReplaying = false;
  @tracked recordedNotes: string[] = []; /* live notation log */

  get showRecordPanel() {
    return this.recordPanelOpen && !this.isRecording;
  }

  get keyboardEnabled() {
    return !this.overlayVisible;
  }
  @tracked searchQuery = '';
  @tracked selectedSong: SongData | null = null;
  @tracked currentBeatIndex = 0;
  @tracked isAutoPlaying = false;
  @tracked pressedKeys = new Set<string>();
  @tracked showKeys = true;
  @tracked isSustain = true;

  /* ── Sound settings ──────────────────────────────────────────────── */
  @tracked instrument = 'classical';
  @tracked transpose = 0;
  @tracked reverbLevel = 20; /* 0–100: reverb wet mix % — low by default */
  @tracked sustainAmount = 2; /* 0–10: short tail by default (VP.net style) */
  @tracked volumeLevel = 80;
  @tracked bpmOverride = 120;
  @tracked metronomeOn = false;

  /* ── Preset selectors (VP.net-style) ────────────────────────────── */
  @tracked sustainPreset = 'medium'; /* 'off' | 'low' | 'medium' | 'high' */
  @tracked reverbPreset = 'medium'; /* 'low' | 'medium' | 'hall' */
  @tracked velocityPreset = 'medium'; /* 'low' | 'medium' | 'high' */

  get velocityGain(): number {
    const map: Record<string, number> = { low: 0.3, medium: 0.5, high: 0.78 };
    return map[this.velocityPreset] ?? 0.5;
  }

  get instrumentOptions(): Array<{ key: string; label: string }> {
    return [
      { key: 'classical', label: 'Grand' },
      { key: 'felt', label: 'Felt' },
      { key: 'bright', label: 'Bright' },
      { key: 'electric', label: 'Electric' },
      { key: 'symphonic', label: 'Symphony' },
      { key: 'violin', label: 'Violin' },
      { key: 'organ', label: 'Organ' },
      { key: 'harp', label: 'Harp' },
      { key: 'harpsichord', label: 'Harpsi' },
    ];
  }

  get instrumentDisplayName(): string {
    return (
      this.instrumentOptions.find((o) => o.key === this.instrument)?.label ??
      this.instrument
    );
  }

  /* ── Panels ──────────────────────────────────────────────────────── */
  @tracked showSoundPanel = false;
  @tracked showInfoPanel = false;
  @tracked faqOpen = false;
  @tracked faqVisible = false;

  /* ── Lifecycle cleanup ───────────────────────────────────────────── */
  willDestroy() {
    this.stopAutoPlay();
    this.stopAllNotes();
  }

  /* ── Live song query ─────────────────────────────────────────────── */
  get musicSheetQuery(): Query {
    return { filter: { type: musicSheetRef } };
  }

  get realms(): string[] {
    const url = this.args.model[realmURL];
    return url ? [url.href] : [];
  }

  songsSearch = this.args.context?.getCards(
    this,
    () => this.musicSheetQuery,
    () => this.realms,
    { isLive: true },
  );

  /* ── Derived getters ─────────────────────────────────────────────── */
  get filteredSongs(): SongData[] {
    try {
      const instances = (this.songsSearch?.instances ?? []) as any[];
      const mapped: SongData[] = instances.map((s: any) => ({
        title: s.songTitle ?? 'Untitled',
        artist: s.artist ?? '',
        difficulty: s.difficulty ?? 0,
        notation: (s.notation ??
          '') as string /* MarkdownField stores plain text */,
        tempo: s.tempo ?? 0,
        genre: ((s.genre ?? []) as Genre[])
          .map((g: Genre) => (g as any).name ?? '')
          .filter(Boolean),
        transposition: s.transposition ?? 0,
        timeSignature: s.timeSignature ?? '4/4',
      }));
      const q = this.searchQuery.trim().toLowerCase();
      if (!q) return mapped;
      return mapped.filter(
        (s) =>
          s.title.toLowerCase().includes(q) ||
          s.artist.toLowerCase().includes(q),
      );
    } catch (_e) {
      return [];
    }
  }

  get hasSongs(): boolean {
    return (this.songsSearch?.instances?.length ?? 0) > 0;
  }

  /* flat beat array — single source of truth for display + playback */
  get parsedBeats(): Beat[] {
    try {
      return parseNotationBeats(this.selectedSong?.notation ?? '');
    } catch (_e) {
      return [];
    }
  }

  get totalBeats(): number {
    return this.parsedBeats.length;
  }

  get progressPercent(): number {
    if (this.totalBeats === 0) return 0;
    return Math.round((this.currentBeatIndex / this.totalBeats) * 100);
  }

  /* sheet rows — one row per NEWLINE in the raw notation field, matching
     how VP.net's left panel displays the sheet: each typed line = one row.
     | pipes appear inline within a row (as rest tokens), not as row breaks.
     Global beat index tracks across rows so current/played state is correct. */
  get sheetRows(): Array<Array<{ display: string; cls: string; idx: number }>> {
    const notation = this.selectedSong?.notation ?? '';
    if (!notation.trim()) return [];
    const rows: Array<Array<{ display: string; cls: string; idx: number }>> =
      [];
    let globalIdx = 0;
    for (const rawLine of notation.split('\n')) {
      const trimmed = rawLine.trim();
      if (!trimmed) continue;
      const lineBeats = parseNotationBeats(trimmed);
      if (lineBeats.length === 0) continue;
      const row: Array<{ display: string; cls: string; idx: number }> = [];
      for (const beat of lineBeats) {
        let cls = 'vp-token';
        if (beat.isPause) cls += ' vp-token--rest';
        else if (beat.isChord) cls += ' vp-token--chord';
        else cls += ' vp-token--note';
        if (globalIdx === this.currentBeatIndex && !beat.isPause)
          cls += ' vp-token--current';
        else if (globalIdx < this.currentBeatIndex) cls += ' vp-token--played';
        row.push({ display: beat.display, cls, idx: globalIdx });
        globalIdx++;
      }
      rows.push(row);
    }
    return rows;
  }

  /* map of noteId → pressed/highlighted boolean */
  get pressedMap(): Record<string, boolean> {
    const result: Record<string, boolean> = {};
    for (const id of this.pressedKeys) {
      result[id] = true;
    }
    /* highlight the next expected beat */
    if (this.selectedSong && !this.isAutoPlaying) {
      const beat = this.parsedBeats[this.currentBeatIndex];
      if (beat && !beat.isPause) {
        for (const k of beat.keys) {
          const mapping = KEYBOARD_MAPPING[k];
          if (mapping) result[`${mapping.note}${mapping.octave}`] = true;
        }
      }
    }
    return result;
  }

  get activeTempo(): number {
    const song = this.selectedSong;
    if (song && song.tempo > 0) return song.tempo;
    return this.bpmOverride > 0 ? this.bpmOverride : 120;
  }

  get difficultyLabel(): string {
    return diffLabel(this.selectedSong?.difficulty ?? 0);
  }

  get difficultyClass(): string {
    return diffClass(this.selectedSong?.difficulty ?? 0);
  }

  get hasNotation(): boolean {
    return (this.selectedSong?.notation ?? '').trim().length > 0;
  }

  /* Current row index (for auto-scroll) — which row the currentBeatIndex falls into */
  get currentRowIndex(): number {
    let globalIdx = 0;
    for (let rowIdx = 0; rowIdx < this.sheetRows.length; rowIdx++) {
      const rowSize = this.sheetRows[rowIdx]!.length;
      if (globalIdx + rowSize > this.currentBeatIndex) {
        return rowIdx;
      }
      globalIdx += rowSize;
    }
    return this.sheetRows.length > 0 ? this.sheetRows.length - 1 : 0;
  }

  /* ── Audio engine ────────────────────────────────────────────────── */
  private getAudioCtx(): AudioContext {
    if (!this.audioCtx || this.audioCtx.state === 'closed') {
      this.audioCtx = new AudioContext();

      /* Master output gain */
      this.masterGain = this.audioCtx.createGain();
      this.masterGain.gain.setValueAtTime(
        this.volumeLevel / 100,
        this.audioCtx.currentTime,
      );
      this.masterGain.connect(this.audioCtx.destination);

      /* Reverb (convolver with synthetic room impulse response)
         Signal flow: noteGain ──dry──► masterGain ──► destination
                                └──wet──► reverbNode ──► reverbGain ──► masterGain */
      this.reverbNode = this.createReverb(this.audioCtx);
      this.reverbGain = this.audioCtx.createGain();
      this.reverbGain.gain.setValueAtTime(
        this.reverbLevel / 100,
        this.audioCtx.currentTime,
      );
      this.reverbNode.connect(this.reverbGain);
      this.reverbGain.connect(this.masterGain);
    }
    return this.audioCtx;
  }

  /** Concert-hall impulse response modelled in three stages:
   *  1. Pre-delay  (0–20 ms)  — near-silence; direct sound reaches ears first
   *  2. Early reflections (20–80 ms) — discrete wall bounces, adds spaciousness
   *  3. Late tail (80 ms – 3.5 s) — smooth exponential decay, the "echo bloom"
   *
   *  This shape is what gives VP.net its 优美的旋律回音 — the echo rises
   *  gently rather than slamming in full-force from t=0. */
  private createReverb(ctx: AudioContext): ConvolverNode {
    const convolver = ctx.createConvolver();
    const sr = ctx.sampleRate;
    const totalSec = 3.5;
    const len = Math.floor(sr * totalSec);
    const ir = ctx.createBuffer(2, len, sr);

    /* Slightly different noise per channel → natural stereo spread */
    for (let ch = 0; ch < 2; ch++) {
      const data = ir.getChannelData(ch);
      for (let i = 0; i < len; i++) {
        const t = i / sr;
        let amp: number;

        if (t < 0.018) {
          /* Pre-delay: nearly silent (room travel time) */
          amp = 0.015;
        } else if (t < 0.08) {
          /* Early reflections: spiky, bright, moderate level */
          const er = (t - 0.018) / 0.062; /* 0→1 within this window */
          amp = 0.55 * Math.exp(-er * 4.5);
        } else {
          /* Late tail: smooth, slow-decaying diffuse field */
          const tail = (t - 0.08) / (totalSec - 0.08);
          amp = 0.3 * Math.exp(-tail * 3.8);
        }

        data[i] = (Math.random() * 2 - 1) * amp;
      }
    }

    convolver.buffer = ir;
    return convolver;
  }

  @action
  playNote(note: string, octave: number, durationSec = 1.8, atTime?: number) {
    /* Log note to live notation when recording (skip auto-play scheduled notes) */
    if (this.isRecording && atTime === undefined) {
      this.recordedNotes = [...this.recordedNotes, `${note}${octave}`];
    }
    try {
      const ctx = this.getAudioCtx();
      if (ctx.state === 'suspended') ctx.resume();

      const baseFreq = noteFreq(note, octave);
      /* transposition: shift semitones via frequency multiplier */
      const freq = baseFreq * Math.pow(2, this.transpose / 12);
      /* VP.net feel: note length ≈ beat slot, with a small sustain tail.
         sustainAmount 0-10 adds up to ~50% extra tail proportionally.
         Never shorter than 0.12s (prevents inaudible ultra-fast notes). */
      const dur = Math.max(
        0.12,
        durationSec * (1 + this.sustainAmount * 0.045),
      );
      /* Use provided AudioContext time (for scheduled playback) or play now */
      const startTime = atTime !== undefined ? atTime : ctx.currentTime;

      const profile =
        INSTRUMENT_PROFILES[this.instrument] ??
        INSTRUMENT_PROFILES['classical']!;

      /* Piano ADSR — real piano strings have no flat sustain level; they
         decay continuously.  Attack → quick initial decay → long slow tail */
      const noteGain = ctx.createGain();
      const peakTime = startTime + profile.attack;
      const decayEnd = peakTime + profile.decay;
      const releaseEnd = startTime + dur;
      const oscillators: OscillatorNode[] = [];

      noteGain.gain.setValueAtTime(0, startTime);
      noteGain.gain.linearRampToValueAtTime(this.velocityGain, peakTime);
      noteGain.gain.exponentialRampToValueAtTime(
        profile.sustainLevel,
        decayEnd,
      );
      noteGain.gain.exponentialRampToValueAtTime(0.0001, releaseEnd);

      /* Dry path → masterGain */
      noteGain.connect(this.masterGain!);
      /* Wet path → reverb → reverbGain → masterGain (gives the "echo/hall" sound) */
      if (this.reverbNode) noteGain.connect(this.reverbNode);

      /* Harmonic stack — supports optional per-partial detuning (cents) for
         the warm "chorus" that makes piano sound less synthesiser-like */
      for (const h of profile.harmonics) {
        const osc = ctx.createOscillator();
        const hGain = ctx.createGain();
        osc.type = 'sine';
        /* Apply cents detune if specified (1 cent = freq × 2^(c/1200)) */
        const detuneFreq = h.detune
          ? freq * h.ratio * Math.pow(2, h.detune / 1200)
          : freq * h.ratio;
        osc.frequency.setValueAtTime(detuneFreq, startTime);
        hGain.gain.setValueAtTime(h.gain, startTime);
        osc.connect(hGain);
        hGain.connect(noteGain);
        osc.start(startTime);
        osc.stop(releaseEnd + 0.3);
        oscillators.push(osc);
      }

      const id = `${note}${octave}`;
      this.sustainedNodes.set(id, oscillators);
      return oscillators;
    } catch (_e) {
      return [];
    }
  }

  @action
  stopNote(note: string, octave: number) {
    const id = `${note}${octave}`;
    const oscillators = this.sustainedNodes.get(id);
    if (oscillators && this.audioCtx) {
      const now = this.audioCtx.currentTime;
      oscillators.forEach((oscillator) => {
        try {
          oscillator.stop(now + 0.55);
        } catch (_e) {
          /* already stopped */
        }
      });
      this.sustainedNodes.delete(id);
    }
  }

  @action
  stopAllNotes() {
    for (const [, oscillators] of this.sustainedNodes) {
      oscillators.forEach((oscillator) => {
        try {
          oscillator.stop(0);
        } catch (_e) {
          /**/
        }
      });
    }
    this.sustainedNodes.clear();
    this.activeKeyboardKeys.clear();
    this.pressedKeys = new Set();
    /* Also stop metronome */
    if (this.metronomeTimer !== null) {
      clearInterval(this.metronomeTimer);
      this.metronomeTimer = null;
      this.metronomeOn = false;
    }
  }

  /* ── Keyboard handlers ───────────────────────────────────────────── */
  @action
  handleKeyDown(e: KeyboardEvent) {
    if (e.repeat) return;
    const key = pianoKeyFromKeyboardEvent(e);
    const mapping = KEYBOARD_MAPPING[key];
    if (mapping) {
      e.preventDefault();
      this.activeKeyboardKeys.set(e.code, key);
      const id = `${mapping.note}${mapping.octave}`;
      if (!this.pressedKeys.has(id)) {
        this.pressedKeys = new Set([...this.pressedKeys, id]);
        this.playNote(mapping.note, mapping.octave);
        this.advanceSheet(key);
      }
    }
    if (e.code === 'Space') {
      e.preventDefault();
      this.isSustain = !this.isSustain;
    }
    if (e.key === 'Escape' && this.mode === 'song') {
      e.preventDefault();
      this.overlayVisible = false;
      setTimeout(() => {
        this.mode = 'play';
      }, 280);
    }
  }

  @action
  handleKeyUp(e: KeyboardEvent) {
    const key =
      this.activeKeyboardKeys.get(e.code) ?? pianoKeyFromKeyboardEvent(e);
    this.activeKeyboardKeys.delete(e.code);
    const mapping = KEYBOARD_MAPPING[key];
    if (mapping) {
      const id = `${mapping.note}${mapping.octave}`;
      const next = new Set(this.pressedKeys);
      next.delete(id);
      this.pressedKeys = next;
      if (!this.isSustain) this.stopNote(mapping.note, mapping.octave);
    }
  }

  @action
  handleCleanup() {
    this.stopAllNotes();
  }

  /* ── Recording ───────────────────────────────────────────────────── */
  get recordTimeLabel(): string {
    const m = Math.floor(this.recordSeconds / 60)
      .toString()
      .padStart(2, '0');
    const s = (this.recordSeconds % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  }

  @action
  toggleRecordPanel() {
    this.recordPanelOpen = !this.recordPanelOpen;
  }

  @action
  openRecordPanel() {
    this.recordPanelOpen = false;
    this.recordedBlob = null;
    /* Auto-start recording — panel will appear after stop */
    this.startRecording();
  }

  @action
  startRecording() {
    const ctx = this.getAudioCtx();
    if (!this.masterGain) return;

    /* Wire a MediaStreamDestination off the master gain */
    this.recordDestination = ctx.createMediaStreamDestination();
    this.masterGain.connect(this.recordDestination);

    this.recordChunks = [];
    this.recordSeconds = 0;
    this.recordedBlob = null;
    this.replayProgress = 0;
    this.recordedNotes = [];

    const mimeType = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
      ? 'audio/webm;codecs=opus'
      : 'audio/webm';

    this.mediaRecorder = new MediaRecorder(this.recordDestination.stream, {
      mimeType,
    });
    this.mediaRecorder.ondataavailable = (e: BlobEvent) => {
      if (e.data.size > 0) this.recordChunks.push(e.data);
    };
    this.mediaRecorder.onstop = () => {
      this.recordedBlob = new Blob(this.recordChunks, { type: mimeType });
      this.recordChunks = [];
    };
    this.mediaRecorder.start(100); /* collect every 100 ms */
    this.isRecording = true;

    /* Clock timer — update display every second */
    this.recordClockTimer = setInterval(() => {
      this.recordSeconds += 1;
    }, 1000);
  }

  @action
  stopRecording() {
    if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
      this.mediaRecorder.stop();
    }
    if (this.masterGain && this.recordDestination) {
      try {
        this.masterGain.disconnect(this.recordDestination);
      } catch (_) {
        /* ignore */
      }
    }
    this.recordDestination = null;
    this.isRecording = false;
    if (this.recordClockTimer) {
      clearInterval(this.recordClockTimer);
      this.recordClockTimer = null;
    }
    /* Always open the panel so the user sees replay + download immediately */
    this.recordPanelOpen = true;
  }

  @action
  toggleRecording() {
    if (this.isRecording) {
      this.stopRecording();
    } else {
      this.startRecording();
    }
  }

  @action
  replayRecording() {
    if (!this.recordedBlob || this.isReplaying) return;
    const url = URL.createObjectURL(this.recordedBlob);
    const audio = new Audio(url);
    this.isReplaying = true;
    this.replayProgress = 0;

    let rafId = 0;
    let startWall = 0;
    let startAudioTime = 0;

    const tick = () => {
      const dur = audio.duration;
      if (dur && dur > 0) {
        /* Use wall-clock elapsed + audio offset for smooth interpolation */
        const elapsed = (performance.now() - startWall) / 1000 + startAudioTime;
        this.replayProgress = Math.min((elapsed / dur) * 100, 100);
      }
      if (this.isReplaying) rafId = requestAnimationFrame(tick);
    };

    /* Only start RAF once audio is actually playing */
    audio.onplaying = () => {
      startWall = performance.now();
      startAudioTime = audio.currentTime;
      rafId = requestAnimationFrame(tick);
    };

    audio.onended = () => {
      cancelAnimationFrame(rafId);
      this.replayProgress = 100;
      this.isReplaying = false;
      URL.revokeObjectURL(url);
    };

    audio.play().catch(() => {
      this.isReplaying = false;
      URL.revokeObjectURL(url);
    });
  }

  @action
  downloadRecording() {
    if (!this.recordedBlob) return;
    const url = URL.createObjectURL(this.recordedBlob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'virtual-piano-recording.webm';
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  /* ── Mouse / touch handlers ──────────────────────────────────────── */
  @action
  handleMouseDown(keyData: KeyData) {
    const id = keyData.id;
    if (!this.pressedKeys.has(id)) {
      this.pressedKeys = new Set([...this.pressedKeys, id]);
      this.playNote(keyData.note, keyData.octave);
    }
  }

  @action
  handleMouseUp(keyData: KeyData) {
    const next = new Set(this.pressedKeys);
    next.delete(keyData.id);
    this.pressedKeys = next;
    if (!this.isSustain) this.stopNote(keyData.note, keyData.octave);
  }

  /* ── Sheet navigation ────────────────────────────────────────────── */
  advanceSheet(key: string) {
    if (!this.selectedSong) return;
    const beats = this.parsedBeats;
    const beat = beats[this.currentBeatIndex];
    if (!beat || beat.isPause) return;
    if (beat.keys.includes(key)) {
      let next = this.currentBeatIndex + 1;
      while (next < beats.length && beats[next]!.isPause) next++;
      this.currentBeatIndex = Math.min(next, beats.length);
    }
  }

  /* ── Auto-play engine ────────────────────────────────────────────────
     BPM rate: beatMs = (60 / BPM) × 1000
     Each beat fires at that interval; chords play all keys simultaneously
     ─────────────────────────────────────────────────────────────────── */
  @action
  toggleAutoPlay() {
    if (this.isAutoPlaying) {
      this.stopAutoPlay();
    } else {
      this.startAutoPlay();
    }
  }

  private startAutoPlay() {
    if (!this.selectedSong) return;
    this.isAutoPlaying = true;
    this.runAutoPlay();
  }

  private runAutoPlay() {
    /* ── Web Audio lookahead scheduler ───────────────────────────────────
       Instead of relying on setTimeout accuracy for note timing, we use the
       AudioContext clock directly. Notes are scheduled ahead into the audio
       graph; setTimeout just drives the scheduler loop every LOOKAHEAD_MS.
       This gives sub-millisecond note accuracy regardless of JS jitter.
       ─────────────────────────────────────────────────────────────────── */
    const beats = this.parsedBeats;
    if (this.currentBeatIndex >= beats.length) this.currentBeatIndex = 0;

    const ctx = this.getAudioCtx();
    if (ctx.state === 'suspended') ctx.resume();

    /* beatSec = 60 / BPM — core tempo formula */
    const beatSec = 60 / this.activeTempo;
    const pauseSec = beatSec * 0.5;

    /* Adaptive note duration — mirrors how VP.net feels at each tempo:
       ≤ 80 BPM  → 3.0× (slow ballads, lots of legato overlap)
       ≤ 120 BPM → 2.0× (moderate, gentle overlap)
       ≤ 150 BPM → 1.4× (upbeat, slight tail only)
       > 150 BPM → 1.05× (fast songs like Come & Get It at 160 — each note
                           is crisp and ends just as the next one starts) */
    const bpm = this.activeTempo;
    /* MIDI-like articulation: each note fills its beat slot with
       slight legato at slow tempos, crisp staccato at fast ones.
       This is what VP.net autoplay actually sounds like. */
    const durationMult =
      bpm <= 70 ? 1.25 : bpm <= 100 ? 1.05 : bpm <= 140 ? 0.92 : 0.78;
    const noteDurationSec = beatSec * durationMult;

    /* Anchor first note 60ms in the future to give JS time to settle */
    this.nextNoteTime = ctx.currentTime + 0.06;

    /* Schedule this many seconds ahead of the playhead */
    const SCHEDULE_AHEAD = 0.12;
    /* How often the scheduler loop runs (ms) */
    const LOOKAHEAD_MS = 25;

    const scheduler = () => {
      if (!this.isAutoPlaying) return;

      const now = this.audioCtx!.currentTime;

      /* Keep scheduling beats until we've filled the look-ahead window */
      while (this.nextNoteTime < now + SCHEDULE_AHEAD) {
        const idx = this.currentBeatIndex;

        if (idx >= beats.length) {
          /* All beats scheduled — stop after last note finishes */
          const msUntilEnd = Math.max(0, (this.nextNoteTime - now) * 1000);
          this.autoPlayTimer = setTimeout(
            () => {
              this.isAutoPlaying = false;
            },
            msUntilEnd + noteDurationSec * 1000,
          );
          return;
        }

        const beat = beats[idx]!;

        if (beat.isPause) {
          this.nextNoteTime += pauseSec;
        } else {
          /* Schedule ALL keys in a chord at EXACTLY the same AudioContext time
             so they are guaranteed to sound simultaneously */
          const scheduledStart = this.nextNoteTime;
          const beatKeys: string[] = [];

          for (const k of beat.keys) {
            const mapping = KEYBOARD_MAPPING[k];
            if (mapping) {
              beatKeys.push(`${mapping.note}${mapping.octave}`);
              this.playNote(
                mapping.note,
                mapping.octave,
                noteDurationSec,
                scheduledStart,
              );
            }
          }

          /* Visual key highlight — fires when the audio actually plays */
          const delayMs = Math.max(0, (scheduledStart - now) * 1000);
          const highlightTimer = setTimeout(() => {
            if (!this.isAutoPlaying) return;
            this.pressedKeys = new Set(beatKeys);
          }, delayMs);
          this.visualTimers.add(highlightTimer);

          /* Release visual — for fast tempos release quickly so keys visually
             "bounce" and you can see each note firing clearly */
          const releaseRatio = bpm > 150 ? 0.55 : 0.8;
          const releaseTimer = setTimeout(
            () => {
              if (!this.isAutoPlaying) return;
              this.pressedKeys = new Set();
            },
            delayMs + noteDurationSec * releaseRatio * 1000,
          );
          this.visualTimers.add(releaseTimer);

          this.nextNoteTime += beatSec;
        }

        this.currentBeatIndex = idx + 1;
      }

      this.autoPlayTimer = setTimeout(scheduler, LOOKAHEAD_MS);
    };

    scheduler();
  }

  private stopAutoPlay() {
    this.isAutoPlaying = false;
    if (this.autoPlayTimer !== null) {
      clearTimeout(this.autoPlayTimer);
      this.autoPlayTimer = null;
    }
    for (const timer of this.visualTimers) {
      clearTimeout(timer);
    }
    this.visualTimers.clear();
  }

  /* ── Song selection ──────────────────────────────────────────────── */
  @action
  selectSong(song: SongData) {
    this.selectedSong = song;
    this.currentBeatIndex = 0;
    this.stopAutoPlay();
    this.searchQuery = '';
    // close overlay with transition, then remove from DOM
    this.overlayVisible = false;
    setTimeout(() => {
      this.mode = 'play';
    }, 280);
    if (song.transposition !== undefined) {
      this.transpose = Math.max(-12, Math.min(12, song.transposition));
    }
    if (song.tempo > 0) this.bpmOverride = song.tempo;
  }

  @action
  closeSong() {
    this.stopAutoPlay();
    this.stopAllNotes();
    this.selectedSong = null;
    this.currentBeatIndex = 0;
  }

  @action
  restartSong() {
    this.stopAutoPlay();
    this.currentBeatIndex = 0;
  }

  /* ── Controls ────────────────────────────────────────────────────── */
  @action
  handleSearchInput(e: Event) {
    this.searchQuery = (e.target as HTMLInputElement).value;
    this.stopAutoPlay();
  }

  @action
  handleVolumeChange(e: Event) {
    this.volumeLevel = Number((e.target as HTMLInputElement).value);
    if (this.masterGain && this.audioCtx) {
      this.masterGain.gain.setValueAtTime(
        this.volumeLevel / 100,
        this.audioCtx.currentTime,
      );
    }
  }

  @action
  handleReverbChange(e: Event) {
    this.reverbLevel = Number((e.target as HTMLInputElement).value);
    if (this.reverbGain && this.audioCtx) {
      this.reverbGain.gain.setValueAtTime(
        this.reverbLevel / 100,
        this.audioCtx.currentTime,
      );
    }
  }

  @action
  toggleMetronome() {
    if (this.metronomeOn) {
      this.metronomeOn = false;
      if (this.metronomeTimer !== null) {
        clearInterval(this.metronomeTimer);
        this.metronomeTimer = null;
      }
      return;
    }
    this.metronomeOn = true;
    const tick = () => {
      try {
        const ctx = this.getAudioCtx();
        if (ctx.state === 'suspended') ctx.resume();
        const t = ctx.currentTime;
        /* Sharp click: brief sine burst at 1000 Hz */
        const osc = ctx.createOscillator();
        const g = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(1000, t);
        g.gain.setValueAtTime(0.35, t);
        g.gain.exponentialRampToValueAtTime(0.0001, t + 0.04);
        osc.connect(g);
        g.connect(this.masterGain!);
        osc.start(t);
        osc.stop(t + 0.06);
      } catch (_e) {
        /**/
      }
    };
    tick(); /* fire immediately */
    const intervalMs = (60 / this.activeTempo) * 1000;
    this.metronomeTimer = setInterval(tick, intervalMs);
  }

  @action
  handleBpmChange(e: Event) {
    this.bpmOverride = Number((e.target as HTMLInputElement).value);
  }

  @action
  adjustTranspose(delta: number) {
    this.transpose = Math.max(-12, Math.min(12, this.transpose + delta));
  }

  @action
  resetTranspose() {
    this.transpose = 0;
  }

  @action
  setInstrument(inst: string) {
    this.instrument = inst;
  }

  @action
  setSustainPreset(preset: string) {
    const map: Record<string, number> = { off: 0, low: 2, medium: 5, high: 9 };
    this.sustainPreset = preset;
    this.sustainAmount = map[preset] ?? 5;
  }

  @action
  setReverbPreset(preset: string) {
    const map: Record<string, number> = { low: 20, medium: 50, hall: 85 };
    this.reverbPreset = preset;
    this.reverbLevel = map[preset] ?? 50;
    if (this.reverbGain && this.audioCtx) {
      this.reverbGain.gain.setValueAtTime(
        this.reverbLevel / 100,
        this.audioCtx.currentTime,
      );
    }
  }

  @action
  setVelocityPreset(preset: string) {
    this.velocityPreset = preset;
  }

  @action
  toggleSoundPanel() {
    this.showSoundPanel = !this.showSoundPanel;
  }

  @action
  toggleInfoPanel() {
    this.showInfoPanel = !this.showInfoPanel;
  }

  @action
  openFaq() {
    this.faqOpen = true;
    setTimeout(() => {
      this.faqVisible = true;
    }, 10);
  }

  @action
  closeFaq() {
    this.faqVisible = false;
    setTimeout(() => {
      this.faqOpen = false;
    }, 280);
  }

  @action
  toggleShowKeys() {
    this.showKeys = !this.showKeys;
  }

  @action
  handleSongSearch() {
    this.mode = 'song';
    // tiny delay so element is in DOM before class is added (enables CSS transition)
    setTimeout(() => {
      this.overlayVisible = true;
    }, 10);
  }

  @action
  async createNewSong() {
    const realmHref = this.realms[0];
    if (!realmHref || !this.args.createCard) return;
    const realmURLObj = new URL(realmHref);
    const doc: LooseSingleCardDocument = {
      data: {
        type: 'card',
        attributes: {
          songTitle: 'New Song',
          artist: null,
          tempo: 120,
          notation: '',
        },
        meta: { adoptsFrom: musicSheetRef },
      },
    };
    try {
      await this.args.createCard(musicSheetRef, realmURLObj, {
        realmURL: realmURLObj,
        doc,
      });
    } catch (e) {
      console.error('Failed to create music sheet card:', e);
    }
  }

  @action
  closeSongPanel() {
    this.stopAutoPlay();
    this.stopAllNotes();
    this.overlayVisible = false;
    setTimeout(() => {
      this.mode = 'play';
    }, 280);
    this.searchQuery = '';
  }

  <template>
    <div
      class='vp-app'
      {{keyboardModifier
        this.keyboardEnabled
        this.handleKeyDown
        this.handleKeyUp
        this.handleCleanup
      }}
    >

      {{! ══ SONG SEARCH — full overlay (always in DOM, CSS-animated) ════ }}
      <div
        class='vp-song-overlay
          {{if this.overlayVisible "vp-song-overlay--open"}}'
        aria-hidden={{if this.overlayVisible 'false' 'true'}}
      >
        <div class='vp-song-overlay-hdr'>
          <svg
            width='14'
            height='14'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          ><circle cx='11' cy='11' r='8' /><line
              x1='21'
              y1='21'
              x2='16.65'
              y2='16.65'
            /></svg>
          <input
            class='vp-search-input'
            type='text'
            placeholder='Search songs…'
            value={{this.searchQuery}}
            {{on 'input' this.handleSearchInput}}
          />
          <button
            class='vp-new-song-btn'
            type='button'
            title='Create a new Music Sheet card'
            {{on 'click' this.createNewSong}}
          >＋ New Song</button>
          <button
            class='vp-btn-icon'
            type='button'
            {{on 'click' this.closeSongPanel}}
          >✕</button>
        </div>
        <div class='vp-song-list'>
          {{#if this.hasSongs}}
            {{#each this.filteredSongs as |song|}}
              <button
                class='vp-song-item'
                type='button'
                {{on 'click' (fn this.selectSong song)}}
              >
                <div class='vp-song-item-info'>
                  <span class='vp-song-item-title'>{{song.title}}</span>
                  {{#if song.artist}}<span
                      class='vp-song-item-artist'
                    >{{song.artist}}</span>{{/if}}
                </div>
                <div class='vp-song-item-meta'>
                  {{#if song.tempo}}<span class='vp-meta-tag'>{{song.tempo}}
                      BPM</span>{{/if}}
                  {{#each song.genre as |tag|}}<span
                      class='vp-meta-tag'
                    >{{tag}}</span>{{/each}}
                </div>
              </button>
            {{/each}}
            {{#if (eq this.filteredSongs.length 0)}}
              <div class='vp-empty-songs'>No songs match "{{this.searchQuery}}"</div>
            {{/if}}
          {{else}}
            <div class='vp-empty-songs'>
              <svg
                width='24'
                height='24'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='1.5'
              ><path d='M9 18V5l12-2v13' /><circle
                  cx='6'
                  cy='18'
                  r='3'
                /><circle cx='18' cy='16' r='3' /></svg>
              <p>No Music Sheets found.<br />Create a Music Sheet card to add
                songs.</p>
            </div>
          {{/if}}
        </div>
        <div class='vp-song-overlay-footer'>
          This app is inspired by
          <a
            href='https://virtualpiano.net'
            target='_blank'
            rel='noopener noreferrer'
          >virtualpiano.net</a>. Get more music sheets at
          <a
            href='https://virtualpiano.net/music-sheets/'
            target='_blank'
            rel='noopener noreferrer'
          >virtualpiano.net/music-sheets</a>.
        </div>
      </div>

      {{! ══ HEADER ROW ══════════════════════════════════════════════════ }}
      <div class='vp-header'>
        <div class='vp-header-left'>
          <svg
            class='vp-logo-icon'
            width='15'
            height='15'
            viewBox='0 0 24 24'
            fill='none'
            stroke='currentColor'
            stroke-width='2'
          >
            <path d='M9 18V5l12-2v13' /><circle cx='6' cy='18' r='3' /><circle
              cx='18'
              cy='16'
              r='3'
            />
          </svg>
          <span class='vp-brand'>Virtual Piano</span>
        </div>
        <div class='vp-header-right'>
          <button
            class='vp-hbtn vp-hbtn--ghost'
            type='button'
            {{on 'click' this.toggleShowKeys}}
          >
            {{if this.showKeys 'Hide' 'Show'}}
            Keys
          </button>
          {{! When not recording: open panel. When recording: stop directly. Disabled during auto-play. }}
          {{#if this.isRecording}}
            <button
              class='vp-hbtn vp-hbtn--rec vp-hbtn--rec--active'
              type='button'
              {{on 'click' this.stopRecording}}
            >
              <span class='vp-rec-dot vp-rec-dot--on'></span>
              {{this.recordTimeLabel}}
              · STOP
            </button>
          {{else}}
            <button
              class='vp-hbtn vp-hbtn--rec
                {{if this.isAutoPlaying "vp-hbtn--disabled"}}'
              type='button'
              disabled={{this.isAutoPlaying}}
              {{on 'click' this.openRecordPanel}}
            >
              <span class='vp-rec-dot'></span>
              {{if this.isAutoPlaying 'Playing…' 'Record'}}
            </button>
          {{/if}}
          <button
            class='vp-hbtn vp-hbtn--gold'
            type='button'
            {{on 'click' this.handleSongSearch}}
          >
            <svg
              width='13'
              height='13'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><circle cx='11' cy='11' r='8' /><line
                x1='21'
                y1='21'
                x2='16.65'
                y2='16.65'
              /></svg>
            Search Song
          </button>
        </div>

        {{! ══ RECORD PANEL — anchored inside header ══════════════════════ }}
        {{#if this.showRecordPanel}}
          <div class='vp-rec-panel'>

            {{! Header }}
            <div class='vp-rec-panel-hdr'>
              <span class='vp-rec-panel-title'>
                <span
                  class='vp-rec-dot {{if this.isRecording "vp-rec-dot--on"}}'
                ></span>
                {{#if this.isRecording}}REC ·
                  {{this.recordTimeLabel}}{{else}}Recording{{/if}}
              </span>
              <button
                class='vp-btn-icon'
                type='button'
                {{on 'click' this.toggleRecordPanel}}
              >✕</button>
            </div>

            {{! After stop: playback row }}
            {{#if this.recordedBlob}}
              {{! Full-width replay button (pill style like reference) }}
              <button
                class='vp-rec-replay-pill'
                type='button'
                {{on 'click' this.replayRecording}}
              >
                {{#if this.isReplaying}}
                  <svg
                    width='14'
                    height='14'
                    viewBox='0 0 24 24'
                    fill='currentColor'
                  ><rect x='6' y='4' width='4' height='16' /><rect
                      x='14'
                      y='4'
                      width='4'
                      height='16'
                    /></svg>
                  PLAYING…
                {{else}}
                  <svg
                    width='14'
                    height='14'
                    viewBox='0 0 24 24'
                    fill='currentColor'
                  ><polygon points='5 3 19 12 5 21 5 3' /></svg>
                  REPLAY AUDIO
                {{/if}}
              </button>

              {{! Download }}
              <button
                class='vp-rec-dl-btn'
                type='button'
                {{on 'click' this.downloadRecording}}
              >
                <svg
                  width='13'
                  height='13'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                ><path d='M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4' /><polyline
                    points='7 10 12 15 17 10'
                  /><line x1='12' y1='15' x2='12' y2='3' /></svg>
                DOWNLOAD AUDIO
              </button>

              {{! Record again }}
              <div class='vp-rec-again-row'>
                <button
                  class='vp-rec-again-btn'
                  type='button'
                  {{on 'click' this.openRecordPanel}}
                >
                  <span class='vp-rec-btn-dot'></span>
                  Record Again
                </button>
              </div>
            {{/if}}

          </div>
        {{/if}}
      </div>

      {{! ══ CONTROLS ROW — always-visible horizontal strip ══════════════ }}
      <div class='vp-controls'>

        {{! ── Sound / Instrument ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Sound
            <span
              class='vp-cval vp-cval--accent'
            >{{this.instrumentDisplayName}}</span>
          </span>
          <div class='vp-preset-btns vp-preset-btns--scroll'>
            {{#each this.instrumentOptions as |opt|}}
              <button
                class='vp-preset-btn
                  {{if (eq this.instrument opt.key) "vp-preset-btn--active"}}'
                type='button'
                {{on 'click' (fn this.setInstrument opt.key)}}
              >{{opt.label}}</button>
            {{/each}}
          </div>
        </div>

        <div class='vp-vsep'></div>

        {{! ── Sustain ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Sustain</span>
          <div class='vp-preset-btns'>
            <button
              class='vp-preset-btn
                {{if (eq this.sustainPreset "off") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setSustainPreset 'off')}}
            >OFF</button>
            <button
              class='vp-preset-btn
                {{if (eq this.sustainPreset "low") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setSustainPreset 'low')}}
            >Low</button>
            <button
              class='vp-preset-btn
                {{if (eq this.sustainPreset "medium") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setSustainPreset 'medium')}}
            >Med</button>
            <button
              class='vp-preset-btn
                {{if (eq this.sustainPreset "high") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setSustainPreset 'high')}}
            >High</button>
          </div>
        </div>

        {{! ── Reverb ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Reverb</span>
          <div class='vp-preset-btns'>
            <button
              class='vp-preset-btn
                {{if (eq this.reverbPreset "low") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setReverbPreset 'low')}}
            >Low</button>
            <button
              class='vp-preset-btn
                {{if (eq this.reverbPreset "medium") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setReverbPreset 'medium')}}
            >Med</button>
            <button
              class='vp-preset-btn
                {{if (eq this.reverbPreset "hall") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setReverbPreset 'hall')}}
            >Hall</button>
          </div>
        </div>

        {{! ── Velocity ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Velocity</span>
          <div class='vp-preset-btns'>
            <button
              class='vp-preset-btn
                {{if (eq this.velocityPreset "low") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setVelocityPreset 'low')}}
            >Low</button>
            <button
              class='vp-preset-btn
                {{if
                  (eq this.velocityPreset "medium")
                  "vp-preset-btn--active"
                }}'
              type='button'
              {{on 'click' (fn this.setVelocityPreset 'medium')}}
            >Med</button>
            <button
              class='vp-preset-btn
                {{if (eq this.velocityPreset "high") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setVelocityPreset 'high')}}
            >High</button>
          </div>
        </div>

        <div class='vp-vsep'></div>

        {{! ── Volume ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Vol
            <span class='vp-cval'>{{this.volumeLevel}}%</span></span>
          <input
            class='vp-slider'
            type='range'
            min='0'
            max='100'
            value={{this.volumeLevel}}
            {{on 'input' this.handleVolumeChange}}
          />
        </div>

        <div class='vp-vsep'></div>

        {{! ── BPM + metronome ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>BPM
            <span class='vp-cval'>{{this.bpmOverride}}</span></span>
          <div class='vp-inline-row'>
            <input
              class='vp-slider vp-slider--bpm'
              type='range'
              min='40'
              max='240'
              value={{this.bpmOverride}}
              {{on 'input' this.handleBpmChange}}
            />
            <button
              class='vp-metro-btn {{if this.metronomeOn "vp-metro-btn--on"}}'
              type='button'
              {{on 'click' this.toggleMetronome}}
            >🎵</button>
          </div>
        </div>

        <div class='vp-vsep'></div>

        {{! ── Transpose ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Transpose
            <span class='vp-cval'>{{this.transpose}} st</span></span>
          <div class='vp-inline-row'>
            <button
              class='vp-step-btn'
              type='button'
              {{on 'click' (fn this.adjustTranspose -1)}}
            >−1</button>
            <span class='vp-transpose-val'>{{this.transpose}}</span>
            <button
              class='vp-step-btn'
              type='button'
              {{on 'click' (fn this.adjustTranspose 1)}}
            >+1</button>
          </div>
        </div>

        <div class='vp-cg vp-cg--reset'>
          <button
            class='vp-reset-btn'
            type='button'
            {{on 'click' this.resetTranspose}}
          >
            <svg
              width='13'
              height='13'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2.2'
            ><polyline points='1 4 1 10 7 10' /><path
                d='M3.51 15a9 9 0 1 0 .49-4'
              /></svg>
            Reset
          </button>
        </div>

      </div>

      {{! ══ LIVE RECORDING TICKER — visible while recording ══════════════ }}
      {{#if this.isRecording}}
        <div class='vp-rec-ticker'>
          <span class='vp-rec-ticker-dot'></span>
          <span class='vp-rec-ticker-label'>REC {{this.recordTimeLabel}}</span>
          <div class='vp-rec-ticker-notes' id='vp-ticker-scroll'>
            {{#if this.recordedNotes.length}}
              {{#each this.recordedNotes as |n|}}
                <span class='vp-rec-ticker-note'>{{n}}</span>
              {{/each}}
            {{else}}
              <span class='vp-rec-ticker-hint'>play keys to record…</span>
            {{/if}}
          </div>
        </div>
      {{/if}}

      {{! ══ SONG BAR — above notation, only when song loaded ════════════ }}
      {{#if this.selectedSong}}
        <div class='vp-song-bar'>
          <div class='vp-song-bar-left'>
            <div class='vp-song-bar-icon {{if this.isAutoPlaying "playing"}}'>
              <svg
                width='18'
                height='18'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><path d='M9 18V5l12-2v13' /><circle
                  cx='6'
                  cy='18'
                  r='3'
                /><circle cx='18' cy='16' r='3' /></svg>
            </div>
            <div class='vp-song-bar-info'>
              <span class='vp-sb-label'>♫ Now Playing</span>
              <span class='vp-sb-title'>{{this.selectedSong.title}}</span>
              {{#if this.selectedSong.artist}}
                <span class='vp-sb-artist'>{{this.selectedSong.artist}}</span>
              {{/if}}
            </div>
            <div class='vp-song-bar-badges'>
              {{#if this.difficultyLabel}}
                <span
                  class='vp-diff-badge {{this.difficultyClass}}'
                >{{this.difficultyLabel}}</span>
              {{/if}}
              {{#if this.selectedSong.tempo}}
                <span class='vp-bpm-badge'>♩ {{this.activeTempo}}</span>
              {{/if}}
            </div>
          </div>
          <div class='vp-song-bar-center'>
            <span class='vp-beat-counter'>{{this.currentBeatIndex}}<span
                class='vp-beat-sep'
              >/</span>{{this.totalBeats}}</span>
            <div class='vp-sb-progress-wrap'>
              <div class='vp-sb-progress-track'>
                <div
                  class='vp-sb-progress-fill'
                  style='width: {{this.progressPercent}}%'
                ></div>
              </div>
            </div>
          </div>
          <div class='vp-song-bar-right'>
            <button
              class='vp-sb-btn vp-sb-btn--ghost vp-sb-btn--sm'
              type='button'
              {{on 'click' this.restartSong}}
              title='Restart'
            >
              <svg
                width='12'
                height='12'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2.2'
              ><polyline points='1 4 1 10 7 10' /><path
                  d='M3.51 15a9 9 0 1 0 .49-4'
                /></svg>
            </button>
            <button
              class='vp-sb-btn vp-sb-btn--lg
                {{if this.isAutoPlaying "vp-sb-btn--stop" "vp-sb-btn--play"}}'
              type='button'
              {{on 'click' this.toggleAutoPlay}}
            >
              {{#if this.isAutoPlaying}}
                <svg
                  width='13'
                  height='13'
                  viewBox='0 0 24 24'
                  fill='currentColor'
                ><rect x='6' y='4' width='4' height='16' /><rect
                    x='14'
                    y='4'
                    width='4'
                    height='16'
                  /></svg>
                Stop
              {{else}}
                <svg
                  width='13'
                  height='13'
                  viewBox='0 0 24 24'
                  fill='currentColor'
                ><polygon points='5 3 19 12 5 21 5 3' /></svg>
                Play
              {{/if}}
            </button>
            <button
              class='vp-sb-btn vp-sb-btn--ghost'
              type='button'
              {{on 'click' this.closeSong}}
              title='Close song'
            >
              <svg
                width='13'
                height='13'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2.2'
              ><line x1='18' y1='6' x2='6' y2='18' /><line
                  x1='6'
                  y1='6'
                  x2='18'
                  y2='18'
                /></svg>
            </button>
          </div>
        </div>
      {{/if}}

      {{! ══ SHEET MUSIC — parchment, centred (only when song loaded) ════ }}
      {{#if this.selectedSong}}
        <div class='vp-sheet-outer'>
          <div
            class='vp-sheet-wrap'
            {{sheetAutoScrollModifier this.currentRowIndex}}
          >
            {{#if this.hasNotation}}
              <div class='vp-sheet'>
                {{#each this.sheetRows as |row rowIdx|}}
                  <div class='vp-row' data-row-idx='{{rowIdx}}'>
                    {{#each row as |beat|}}
                      <span class='{{beat.cls}}'>{{beat.display}}</span>
                    {{/each}}
                  </div>
                {{/each}}
              </div>
            {{/if}}
          </div>
        </div>
      {{/if}}

      {{! ══ FALLBOARD ════════════════════════════════════════════════════ }}
      <div class='vp-fallboard'>
        {{! Left: brand }}
        <div class='vp-fallboard-left'>
          <span class='vp-fallboard-dot'></span>
          <span class='vp-fallboard-brand'>Virtual Piano</span>
          <span class='vp-fallboard-dot'></span>
        </div>

        {{! Center: live status chips }}
        <div class='vp-fallboard-center'>

          <span class='vp-fb-chip'>
            <svg
              width='10'
              height='10'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path d='M9 18V5l12-2v13' /><circle cx='6' cy='18' r='3' /><circle
                cx='18'
                cy='16'
                r='3'
              /></svg>
            {{this.instrument}}
          </span>
          {{#if this.transpose}}
            <span class='vp-fb-divider'></span>
            <span class='vp-fb-chip vp-fb-chip--accent'>
              <svg
                width='10'
                height='10'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><line x1='12' y1='5' x2='12' y2='19' /><polyline
                  points='5 12 12 5 19 12'
                /></svg>
              {{this.transpose}}
              st
            </span>
          {{/if}}

        </div>

        {{! Right: two-hand feature highlight + FAQ + key count }}
        <div class='vp-fallboard-right'>
          <span
            class='vp-fb-twohand'
            title='Two-hand notation via [chord] brackets'
          >
            <svg
              width='12'
              height='12'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><path d='M9 11V6a2 2 0 0 1 4 0v5' /><path
                d='M5 11V8a2 2 0 0 1 4 0v3'
              /><path d='M13 11V6a2 2 0 0 1 4 0v5' /><path
                d='M17 11V8a2 2 0 0 1 4 0v3'
              /><path d='M3 11h18v3a7 7 0 0 1-7 7h-4a7 7 0 0 1-7-7v-3z' /></svg>
            Two-Hand Notation
            <span class='vp-fb-twohand-pulse'></span>
          </span>
          <button
            class='vp-fb-faq-btn'
            type='button'
            {{on 'click' this.openFaq}}
            title='View FAQ'
          >
            <svg
              width='11'
              height='11'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2.4'
            ><circle cx='12' cy='12' r='10' /><path
                d='M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3'
              /><line x1='12' y1='17' x2='12.01' y2='17' /></svg>
            View FAQ
          </button>
          <span class='vp-fallboard-keys'>
            <svg
              width='11'
              height='11'
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            ><rect x='2' y='7' width='20' height='13' rx='2' /><path
                d='M7 7V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v2'
              /><line x1='12' y1='12' x2='12' y2='16' /></svg>
            61 Keys
          </span>
        </div>
      </div>

      {{! ══ FAQ OVERLAY ════════════════════════════════════════════════ }}
      {{#if this.faqOpen}}
        <div
          class='vp-faq-overlay {{if this.faqVisible "vp-faq-overlay--open"}}'
          aria-hidden={{if this.faqVisible 'false' 'true'}}
        >
          <div class='vp-faq-hdr'>
            <div class='vp-faq-hdr-title'>
              <svg
                width='16'
                height='16'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              ><circle cx='12' cy='12' r='10' /><path
                  d='M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3'
                /><line x1='12' y1='17' x2='12.01' y2='17' /></svg>
              <span>Virtual Piano · FAQ &amp; Notation Guide</span>
            </div>
            <button
              class='vp-btn-icon'
              type='button'
              {{on 'click' this.closeFaq}}
            >✕</button>
          </div>

          <div class='vp-faq-body'>

            {{! ── 1. About VP.net notation ── }}
            <section class='vp-faq-section'>
              <h3 class='vp-faq-q'>
                <span class='vp-faq-q-num'>1</span>
                What kind of music notation does this piano use?
              </h3>
              <p class='vp-faq-a'>
                This piano uses
                <strong>VP.net notation</strong>
                — a special text-based music format designed by
                <a
                  href='https://virtualpiano.net'
                  target='_blank'
                  rel='noopener noreferrer'
                >virtualpiano.net</a>. It maps every piano key to a single
                keyboard character so songs can be written as plain text and
                played on any QWERTY keyboard.
              </p>
              <p class='vp-faq-a'>
                Standard music formats like
                <em>sheet music</em>,
                <em>ABC notation</em>,
                <em>MusicXML</em>, or
                <em>MIDI</em>
                are
                <strong>not</strong>
                supported. Only the VP.net text format works.
              </p>
            </section>

            {{! ── 2. Symbols ── }}
            <section class='vp-faq-section'>
              <h3 class='vp-faq-q'>
                <span class='vp-faq-q-num'>2</span>
                What do the symbols in a music sheet mean?
              </h3>
              <ul class='vp-faq-symbols'>
                <li>
                  <code class='vp-faq-tok'>t y u i</code>
                  <span>Single keys — each character is one beat (white note)</span>
                </li>
                <li>
                  <code class='vp-faq-tok'>T Y I O</code>
                  <span>Shift + letter — black keys (sharps/flats)</span>
                </li>
                <li>
                  <code class='vp-faq-tok'>[abc]</code>
                  <span><strong>Chord beat</strong>
                    — all keys inside the brackets play
                    <em>simultaneously</em></span>
                </li>
                <li>
                  <code class='vp-faq-tok'>-</code>
                  <span>Rest beat — silence for one beat</span>
                </li>
                <li>
                  <code class='vp-faq-tok'>|</code>
                  <span>Phrase divider / timing pause</span>
                </li>
                <li>
                  <code class='vp-faq-tok'>&nbsp;&nbsp;</code>
                  <span>Whitespace separates groups (phrase chunks)</span>
                </li>
              </ul>
            </section>

            {{! ── 3. Two-hand notation — HIGHLIGHTED ── }}
            <section class='vp-faq-section vp-faq-section--highlight'>
              <h3 class='vp-faq-q'>
                <span class='vp-faq-q-num vp-faq-q-num--accent'>3</span>
                Does this support two-hand playing?
                <span class='vp-faq-badge'>YES ✓</span>
              </h3>
              <p class='vp-faq-a'>
                <strong>Yes</strong>
                — through the chord bracket
                <code class='vp-faq-tok'>[ ]</code>
                syntax. This is the standard VP.net idiom for playing both hands
                at the same time on a single beat.
              </p>
              <div class='vp-faq-handmap'>
                <div class='vp-faq-handmap-row'>
                  <span class='vp-faq-hand vp-faq-hand--left'>🤚 LEFT HAND</span>
                  <span class='vp-faq-hand-keys'>
                    <code>1 2 3 4 5 6 7</code>
                    (Oct 2) ·
                    <code>8 9 0 q w e r</code>
                    (Oct 3)
                  </span>
                </div>
                <div class='vp-faq-handmap-row'>
                  <span class='vp-faq-hand vp-faq-hand--mid'>👐 MIDDLE</span>
                  <span class='vp-faq-hand-keys'>
                    <code>t y u i o p a</code>
                    (Oct 4 — middle C is
                    <code>t</code>)
                  </span>
                </div>
                <div class='vp-faq-handmap-row'>
                  <span class='vp-faq-hand vp-faq-hand--right'>✋ RIGHT HAND</span>
                  <span class='vp-faq-hand-keys'>
                    <code>s d f g h j k</code>
                    (Oct 5) ·
                    <code>l z x c v b n m</code>
                    (Oct 6–7)
                  </span>
                </div>
              </div>
              <p class='vp-faq-a'>
                <strong>Example:</strong>
                <code class='vp-faq-tok'>[5p]</code>
                plays bass note
                <code>5</code>
                (G2 — left hand) and melody note
                <code>p</code>
                (A4 — right hand) at the same instant. A typical sheet looks
                like:
              </p>
              <pre class='vp-faq-example'>[5p] o i u [4o] i u y [3qf] f d s
[5p] o i u [4o] i u y</pre>
              <p class='vp-faq-a vp-faq-a--note'>
                <strong>Limitation:</strong>
                both hands always share the same beat. Independent rhythms (e.g.
                left hand holding a chord while right hand plays eighth notes)
                are not possible — this is a constraint of the VP.net notation
                itself, not of this app.
              </p>
            </section>

            {{! ── 4. Auto-play ── }}
            <section class='vp-faq-section'>
              <h3 class='vp-faq-q'>
                <span class='vp-faq-q-num'>4</span>
                How does auto-play work?
              </h3>
              <p class='vp-faq-a'>
                Press
                <strong>Play</strong>
                in the song bar. Notes fire at
                <code>beatMs = 60000 / BPM</code>. The
                <strong>BPM</strong>
                slider sets tempo; the song's own tempo overrides the slider
                when a song is loaded. The
                <strong>Transpose</strong>
                control shifts every note up or down by semitones.
              </p>
            </section>

            {{! ── 5. Sound controls ── }}
            <section class='vp-faq-section'>
              <h3 class='vp-faq-q'>
                <span class='vp-faq-q-num'>5</span>
                What do Sustain, Reverb, and Velocity do?
              </h3>
              <ul class='vp-faq-symbols'>
                <li>
                  <code class='vp-faq-tok'>Sustain</code>
                  <span>Length of the note tail after release — OFF for
                    staccato, HIGH for legato</span>
                </li>
                <li>
                  <code class='vp-faq-tok'>Reverb</code>
                  <span>Room ambience — Low (intimate), Med (studio), Hall
                    (concert hall echo)</span>
                </li>
                <li>
                  <code class='vp-faq-tok'>Velocity</code>
                  <span>Strike strength / loudness — Low (soft), Med, High
                    (forte)</span>
                </li>
              </ul>
            </section>

            {{! ── 6. Recording ── }}
            <section class='vp-faq-section'>
              <h3 class='vp-faq-q'>
                <span class='vp-faq-q-num'>6</span>
                Can I record what I play?
              </h3>
              <p class='vp-faq-a'>
                Yes. Tap
                <strong>Record</strong>
                in the header to start capturing audio. When you stop, you can
                replay it inline or download a
                <code>.webm</code>
                audio file.
              </p>
            </section>

            {{! ── 7. Custom songs ── }}
            <section class='vp-faq-section'>
              <h3 class='vp-faq-q'>
                <span class='vp-faq-q-num'>7</span>
                Where do I get more songs?
              </h3>
              <p class='vp-faq-a'>
                Browse the
                <a
                  href='https://virtualpiano.net/music-sheets/'
                  target='_blank'
                  rel='noopener noreferrer'
                >virtualpiano.net music sheets library</a>
                and paste the VP.net notation into a new Music Sheet card via
                the
                <strong>＋ New Song</strong>
                button.
              </p>
            </section>

          </div>

          <div class='vp-faq-footer'>
            Notation system designed by
            <a
              href='https://virtualpiano.net'
              target='_blank'
              rel='noopener noreferrer'
            >virtualpiano.net</a>. This app is an inspired implementation.
          </div>
        </div>
      {{/if}}

      {{! ══ KEYBOARD ════════════════════════════════════════════════════ }}
      <div class='vp-keyboard-wrapper'>
        <div class='vp-keyboard'>
          {{#each WHITE_KEYS as |keyData|}}
            <button
              class='vp-key vp-key--white
                {{if (get this.pressedMap keyData.id) "vp-key--active"}}'
              type='button'
              {{on 'mousedown' (fn this.handleMouseDown keyData)}}
              {{on 'mouseup' (fn this.handleMouseUp keyData)}}
              {{on 'mouseleave' (fn this.handleMouseUp keyData)}}
            >
              {{#if this.showKeys}}
                <span class='vp-key-label'>{{keyData.kbKey}}</span>
              {{/if}}
            </button>
          {{/each}}
          {{#each BLACK_KEYS as |keyData|}}
            <button
              class='vp-key vp-key--black
                {{if (get this.pressedMap keyData.id) "vp-key--active"}}'
              style='left: {{keyData.leftPx}}px'
              type='button'
              {{on 'mousedown' (fn this.handleMouseDown keyData)}}
              {{on 'mouseup' (fn this.handleMouseUp keyData)}}
              {{on 'mouseleave' (fn this.handleMouseUp keyData)}}
            >
              {{#if this.showKeys}}
                <span class='vp-key-label'>{{keyData.kbKey}}</span>
              {{/if}}
            </button>
          {{/each}}
        </div>
      </div>

    </div>

    <style scoped>
      /* ══ Design Tokens — Silver Chrome Gaming ══════════════════════════ */
      .vp-app {
        /* ── Chrome / Silver palette ── */
        --c-chrome: #b0b0c0;
        --c-chrome-hi: #dcdce8;
        --c-chrome-lo: #60606c;
        --c-chrome-dim: rgba(176, 176, 192, 0.1);
        --c-chrome-border: rgba(176, 176, 192, 0.24);

        /* ── Cyan gaming accent ── */
        --c-accent: #00d4ff;
        --c-accent-hi: #60eaff;
        --c-accent-dim: rgba(0, 212, 255, 0.12);
        --c-accent-border: rgba(0, 212, 255, 0.3);
        --c-accent-glow: rgba(0, 212, 255, 0.22);

        /* ── Legacy gold kept for parchment / notation only ── */
        --c-gold: #c9a84c;
        --c-gold-light: #e2c36a;
        --c-gold-dim: rgba(201, 168, 76, 0.12);
        --c-gold-border: rgba(201, 168, 76, 0.26);
        --c-parchment: #f2e8cd;
        --c-ink-note: #1a3d27;
        --c-ink-chord: #6e1f00;
        --c-ink-muted: rgba(28, 20, 8, 0.32);

        /* ── Backgrounds ── */
        --c-bg: #0c0c12;
        --c-panel: #141418;
        --c-surface: #0f0f14;
        --c-surface-2: #18181e;
        --c-surface-3: #202028;

        /* ── Text ── */
        --c-text: #e8e8f0;
        --c-text-2: rgba(232, 232, 240, 0.65);
        --c-muted: rgba(232, 232, 240, 0.36);

        /* ── Borders ── */
        --c-border: rgba(255, 255, 255, 0.07);
        --c-border-2: rgba(255, 255, 255, 0.13);

        /* ── Difficulty colours ── */
        --c-diff-easy-bg: rgba(33, 150, 243, 0.12);
        --c-diff-easy: #82b1ff;
        --c-diff-super-easy-bg: rgba(76, 175, 80, 0.12);
        --c-diff-super-easy: #69f0ae;
        --c-diff-inter-bg: rgba(201, 168, 76, 0.14);
        --c-diff-inter: #e2c36a;
        --c-diff-expert-bg: rgba(180, 50, 30, 0.14);
        --c-diff-expert: #ff8a80;

        --radius: 6px;
        --radius-sm: 3px;

        /* ── Silver-frame bezel ── */
        --c-bezel-top: rgba(220, 220, 234, 0.32);
        --c-bezel-side: rgba(160, 160, 175, 0.2);
        --c-bezel-bottom: rgba(80, 80, 92, 0.45);

        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        background: var(--c-bg);
        color: var(--c-text);
        font-family: 'Inter', system-ui, sans-serif;
        overflow: hidden;
        position: relative;

        /* Silver frame */
        border-top: 2px solid var(--c-bezel-top);
        border-left: 2px solid var(--c-bezel-side);
        border-right: 2px solid var(--c-bezel-side);
        border-bottom: 2px solid var(--c-bezel-bottom);
        box-sizing: border-box;
        box-shadow:
          inset 0 0 0 1px rgba(255, 255, 255, 0.06),
          inset 1px 1px 0 rgba(255, 255, 255, 0.1),
          0 8px 40px rgba(0, 0, 0, 0.7);
      }

      /* ══ Song Search Overlay (full screen) ═══════════════════════════ */
      .vp-song-overlay {
        position: absolute;
        inset: 0;
        z-index: 300;
        background: rgba(10, 10, 18, 0.97);
        backdrop-filter: blur(14px);
        -webkit-backdrop-filter: blur(14px);
        display: flex;
        flex-direction: column;
        overflow: hidden;
        /* hidden state */
        opacity: 0;
        transform: translateY(-12px) scale(0.985);
        pointer-events: none;
        transition:
          opacity 0.26s cubic-bezier(0.22, 0.68, 0.36, 1),
          transform 0.26s cubic-bezier(0.22, 0.68, 0.36, 1);
      }
      .vp-song-overlay--open {
        opacity: 1;
        transform: translateY(0) scale(1);
        pointer-events: auto;
      }
      .vp-song-overlay-hdr {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 1rem 1.25rem;
        border-bottom: 1px solid rgba(180, 180, 200, 0.12);
        box-shadow:
          0 1px 0 rgba(0, 212, 255, 0.08),
          0 4px 20px rgba(0, 0, 0, 0.4);
        flex-shrink: 0;
        background: linear-gradient(180deg, #1c1c28 0%, #12121c 100%);
        color: var(--c-accent);
      }
      .vp-search-input {
        flex: 1;
        background: transparent;
        border: none;
        color: var(--c-text);
        font-size: 17px;
        font-weight: 500;
        letter-spacing: 0.2px;
        outline: none;
      }
      .vp-search-input::placeholder {
        color: var(--c-muted);
      }
      .vp-btn-icon {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 30px;
        height: 30px;
        background: var(--c-chrome-dim);
        border: 1px solid var(--c-chrome-border);
        border-radius: 50%;
        color: var(--c-chrome);
        cursor: pointer;
        font-size: 13px;
        transition: all 0.15s;
        line-height: 1;
      }
      .vp-btn-icon:hover {
        background: rgba(176, 176, 192, 0.2);
        color: var(--c-chrome-hi);
        border-color: rgba(176, 176, 192, 0.4);
      }
      .vp-new-song-btn {
        display: inline-flex;
        align-items: center;
        gap: 0.25rem;
        padding: 0.4rem 0.75rem;
        background: var(--c-accent, #6366f1);
        border: 1px solid var(--c-accent, #6366f1);
        border-radius: 999px;
        color: #fff;
        cursor: pointer;
        font-size: 12px;
        font-weight: 600;
        letter-spacing: 0.02em;
        transition: filter 0.15s;
        white-space: nowrap;
      }
      .vp-new-song-btn:hover {
        filter: brightness(1.12);
      }
      .vp-song-overlay-footer {
        padding: 0.75rem 1rem;
        border-top: 1px solid var(--c-chrome-border);
        color: var(--c-muted);
        font-size: 11px;
        line-height: 1.5;
        text-align: center;
      }
      .vp-song-overlay-footer a {
        color: var(--c-chrome-hi);
        text-decoration: underline;
      }
      .vp-song-overlay-footer a:hover {
        color: var(--c-accent, #818cf8);
      }
      .vp-song-list {
        overflow-y: auto;
        flex: 1;
      }
      .vp-song-item {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        padding: 0.6rem 1rem;
        width: 100%;
        background: transparent;
        border: none;
        border-bottom: 1px solid var(--c-border);
        cursor: pointer;
        text-align: left;
        transition: background 0.12s;
      }
      .vp-song-item:hover {
        background: var(--c-surface-2);
      }
      .vp-song-item-info {
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
        flex: 1;
      }
      .vp-song-item-title {
        font-size: 13px;
        font-weight: 600;
        color: var(--c-text);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .vp-song-item-artist {
        font-size: 11px;
        color: var(--c-muted);
      }
      .vp-song-item-meta {
        display: flex;
        align-items: center;
        gap: 4px;
        flex-wrap: wrap;
      }
      .vp-meta-tag {
        padding: 1px 6px;
        border-radius: 4px;
        font-size: 9px;
        font-weight: 700;
        background: var(--c-surface-3);
        color: var(--c-muted);
      }
      .vp-empty-songs {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.5rem;
        padding: 2.5rem 1.5rem;
        text-align: center;
        color: var(--c-muted);
        font-size: 12px;
        line-height: 1.5;
      }

      /* ══ Header Row — brushed steel bar ════════════════════════════════ */
      .vp-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        padding: 0.6rem 1rem;
        background: linear-gradient(180deg, #242430 0%, #16161e 100%);
        border-bottom: 1px solid rgba(180, 180, 200, 0.18);
        box-shadow:
          0 1px 0 rgba(255, 255, 255, 0.06),
          inset 0 1px 0 rgba(255, 255, 255, 0.08);
        flex-shrink: 0;
        position: relative;
        z-index: 200;
      }
      .vp-header-left {
        display: flex;
        align-items: center;
        gap: 0.45rem;
        min-width: 0;
        flex: 1;
        overflow: hidden;
      }
      .vp-logo-icon {
        color: var(--c-chrome);
        flex-shrink: 0;
      }
      .vp-brand {
        font-size: 15px;
        font-weight: 800;
        color: var(--c-chrome-hi);
        letter-spacing: 1.5px;
        white-space: nowrap;
        flex-shrink: 0;
        text-transform: uppercase;
        text-shadow:
          0 1px 0 rgba(0, 0, 0, 0.5),
          0 0 8px rgba(0, 212, 255, 0.18);
      }
      /* .vp-sep / .vp-song-title / .vp-song-artist removed — now in .vp-song-bar */
      .vp-diff-badge {
        padding: 1px 5px;
        border-radius: 6px;
        font-size: 8px;
        font-weight: 800;
        letter-spacing: 0.4px;
        flex-shrink: 0;
      }
      .vp-bpm-badge {
        font-size: 10px;
        font-weight: 700;
        color: var(--c-accent);
        background: var(--c-accent-dim);
        border: 1px solid var(--c-accent-border);
        border-radius: 4px;
        padding: 1px 6px;
        white-space: nowrap;
        flex-shrink: 0;
        box-shadow: 0 0 6px var(--c-accent-glow);
      }
      .vp-header-right {
        display: flex;
        align-items: center;
        gap: 0.3rem;
        flex-shrink: 0;
      }
      /* .vp-beat-info removed — now .vp-beat-counter in song bar */

      /* Header buttons — chrome gaming style */
      .vp-hbtn {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 6px 14px;
        border-radius: var(--radius-sm);
        font-size: 13px;
        font-weight: 600;
        cursor: pointer;
        border: 1px solid transparent;
        background: transparent;
        color: var(--c-text-2);
        transition: all 0.12s;
        white-space: nowrap;
      }
      .vp-hbtn:active {
        transform: scale(0.95);
      }
      .vp-hbtn--ghost {
        border-color: var(--c-chrome-border);
        color: var(--c-chrome);
        background: var(--c-chrome-dim);
      }
      .vp-hbtn--ghost:hover {
        border-color: rgba(176, 176, 192, 0.45);
        color: var(--c-chrome-hi);
        background: rgba(176, 176, 192, 0.16);
      }
      .vp-hbtn--gold {
        background: linear-gradient(180deg, #2a2a38 0%, #1a1a24 100%);
        color: var(--c-accent);
        font-weight: 700;
        border-color: var(--c-accent-border);
        box-shadow:
          0 0 8px var(--c-accent-glow),
          inset 0 1px 0 rgba(255, 255, 255, 0.08);
      }
      .vp-hbtn--gold:hover {
        background: linear-gradient(180deg, #343448 0%, #242434 100%);
        box-shadow: 0 0 14px var(--c-accent-glow);
      }
      .vp-hbtn--play {
        background: linear-gradient(180deg, #2a2a38 0%, #1a1a24 100%);
        color: var(--c-accent);
        font-weight: 700;
        border-color: var(--c-accent-border);
        box-shadow: 0 0 8px var(--c-accent-glow);
      }
      .vp-hbtn--play:hover {
        box-shadow: 0 0 16px var(--c-accent-glow);
      }
      .vp-hbtn--stop {
        background: rgba(180, 50, 30, 0.14);
        color: #f97060;
        border-color: rgba(180, 50, 30, 0.28);
      }
      .vp-hbtn--stop:hover {
        background: rgba(180, 50, 30, 0.24);
      }

      /* Difficulty badges */
      .diff-super-easy {
        background: var(--c-diff-super-easy-bg);
        color: var(--c-diff-super-easy);
        border: 1px solid rgba(76, 175, 80, 0.25);
      }
      .diff-easy {
        background: var(--c-diff-easy-bg);
        color: var(--c-diff-easy);
        border: 1px solid rgba(33, 150, 243, 0.25);
      }
      .diff-intermediate {
        background: var(--c-diff-inter-bg);
        color: var(--c-diff-inter);
        border: 1px solid rgba(201, 168, 76, 0.3);
      }
      .diff-expert {
        background: var(--c-diff-expert-bg);
        color: var(--c-diff-expert);
        border: 1px solid rgba(180, 50, 30, 0.28);
      }
      .diff-unknown {
        background: transparent;
        color: var(--c-muted);
        border: 1px solid var(--c-border);
      }

      /* ══ Song Bar — above notation ═══════════════════════════════════ */
      .vp-song-bar {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.55rem 1rem;
        background: linear-gradient(180deg, #1c1c26 0%, #14141c 100%);
        border-bottom: 1px solid rgba(180, 180, 200, 0.15);
        box-shadow:
          inset 0 -1px 0 rgba(0, 0, 0, 0.4),
          0 1px 0 rgba(255, 255, 255, 0.04);
        flex-shrink: 0;
        position: relative;
        overflow: hidden;
      }
      .vp-song-bar::before {
        content: '';
        position: absolute;
        inset: 0;
        background: linear-gradient(
          90deg,
          rgba(0, 212, 255, 0.05) 0%,
          transparent 45%
        );
        pointer-events: none;
      }
      .vp-song-bar-left {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        flex: 1;
        min-width: 0;
        overflow: hidden;
      }
      .vp-song-bar-icon {
        width: 36px;
        height: 36px;
        border-radius: 50%;
        background: radial-gradient(
          ellipse at 40% 35%,
          #3a5a7c 0%,
          #0f1620 100%
        );
        border: 2px solid var(--c-accent);
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--c-accent);
        flex-shrink: 0;
        box-shadow:
          0 0 16px var(--c-accent-glow),
          inset 0 1px 2px rgba(100, 180, 255, 0.15);
        transition: all 0.2s ease;
      }
      .vp-song-bar-icon.playing {
        animation: musicBounce 0.6s ease-in-out infinite;
        box-shadow:
          0 0 24px var(--c-accent-glow),
          inset 0 1px 2px rgba(100, 180, 255, 0.25);
      }
      @keyframes musicBounce {
        0%,
        100% {
          transform: scale(1);
        }
        50% {
          transform: scale(1.15);
        }
      }
      .vp-song-bar-info {
        display: flex;
        flex-direction: column;
        gap: 0px;
        min-width: 0;
        overflow: hidden;
      }
      .vp-sb-label {
        font-size: 10px;
        font-weight: 700;
        color: var(--c-accent);
        text-transform: uppercase;
        letter-spacing: 0.8px;
        opacity: 1;
        text-shadow: 0 0 4px rgba(100, 180, 255, 0.4);
      }
      .vp-sb-title {
        font-size: 15px;
        font-weight: 700;
        color: var(--c-text);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        letter-spacing: 0.1px;
      }
      .vp-sb-artist {
        font-size: 12px;
        color: var(--c-muted);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .vp-song-bar-badges {
        display: flex;
        align-items: center;
        gap: 5px;
        flex-shrink: 0;
      }
      .vp-song-bar-center {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 4px;
        flex-shrink: 0;
        min-width: 120px;
      }
      .vp-beat-counter {
        font-size: 11px;
        font-weight: 700;
        color: var(--c-text-2);
        font-variant-numeric: tabular-nums;
        letter-spacing: 0.5px;
      }
      .vp-beat-sep {
        color: var(--c-muted);
        font-weight: 400;
        margin: 0 1px;
      }
      .vp-sb-progress-wrap {
        width: 100%;
      }
      .vp-sb-progress-track {
        width: 100%;
        height: 3px;
        background: var(--c-border-2);
        border-radius: 2px;
        overflow: hidden;
      }
      .vp-sb-progress-fill {
        height: 100%;
        background: linear-gradient(
          90deg,
          var(--c-accent) 0%,
          var(--c-accent-hi) 100%
        );
        border-radius: 2px;
        transition: width 0.2s linear;
        box-shadow: 0 0 6px var(--c-accent-glow);
      }
      .vp-song-bar-right {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        flex-shrink: 0;
      }
      .vp-sb-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 4px;
        padding: 4px 10px;
        border-radius: var(--radius-sm);
        font-size: 11px;
        font-weight: 700;
        cursor: pointer;
        border: 1px solid transparent;
        background: transparent;
        color: var(--c-text-2);
        transition: all 0.12s;
        white-space: nowrap;
        height: 32px;
      }
      .vp-sb-btn:active {
        transform: scale(0.93);
      }
      .vp-sb-btn--ghost {
        border-color: var(--c-chrome-border);
        color: var(--c-chrome);
        background: var(--c-chrome-dim);
        padding: 4px 7px;
      }
      .vp-sb-btn--ghost:hover {
        border-color: rgba(176, 176, 192, 0.4);
        color: var(--c-chrome-hi);
      }
      .vp-sb-btn--sm {
        padding: 5px 8px;
      }
      .vp-sb-btn--lg {
        padding: 6px 16px;
      }
      .vp-sb-btn--play {
        background: linear-gradient(180deg, #243040 0%, #141e2c 100%);
        color: var(--c-accent);
        border-color: var(--c-accent-border);
        box-shadow:
          0 0 10px var(--c-accent-glow),
          inset 0 1px 0 rgba(255, 255, 255, 0.08);
      }
      .vp-sb-btn--play:hover {
        box-shadow: 0 0 18px var(--c-accent-glow);
        border-color: var(--c-accent);
      }
      .vp-sb-btn--stop {
        background: rgba(180, 50, 30, 0.14);
        color: #f97060;
        border-color: rgba(180, 50, 30, 0.28);
      }
      .vp-sb-btn--stop:hover {
        background: rgba(180, 50, 30, 0.26);
      }

      /* ══ Record button (header) ═════════════════════════════════════════ */
      .vp-hbtn--rec {
        border-color: rgba(220, 60, 60, 0.35);
        color: #f07070;
        background: rgba(220, 60, 60, 0.08);
        font-variant-numeric: tabular-nums;
        gap: 6px;
      }
      .vp-hbtn--rec:hover {
        background: rgba(220, 60, 60, 0.16);
        border-color: rgba(220, 60, 60, 0.55);
      }
      .vp-hbtn--rec--active {
        background: rgba(220, 40, 40, 0.18);
        border-color: rgba(220, 40, 40, 0.6);
        color: #ff6060;
        box-shadow: 0 0 10px rgba(220, 40, 40, 0.25);
      }
      .vp-rec-dot {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #e04040;
        flex-shrink: 0;
      }
      .vp-rec-dot--on {
        background: #ff4040;
        box-shadow: 0 0 6px #ff4040;
        animation: vp-rec-pulse 1s ease-in-out infinite;
      }
      @keyframes vp-rec-pulse {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.35;
        }
      }

      /* ══ Record Panel (dropdown) ══════════════════════════════════════ */
      .vp-rec-panel {
        position: absolute;
        top: calc(100% + 4px);
        right: 0;
        z-index: 400;
        width: 310px;
        background: linear-gradient(160deg, #1c1c28 0%, #12121c 100%);
        border: 1px solid rgba(220, 60, 60, 0.25);
        border-radius: 12px;
        box-shadow:
          0 20px 60px rgba(0, 0, 0, 0.7),
          0 0 0 1px rgba(255, 255, 255, 0.05),
          inset 0 1px 0 rgba(255, 255, 255, 0.07);
        overflow: hidden;
        animation: vp-panel-in 0.22s cubic-bezier(0.22, 0.68, 0.36, 1);
      }
      @keyframes vp-panel-in {
        from {
          opacity: 0;
          transform: translateY(-8px) scale(0.97);
        }
        to {
          opacity: 1;
          transform: translateY(0) scale(1);
        }
      }
      .vp-rec-panel-hdr {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 0.75rem 1rem;
        border-bottom: 1px solid rgba(255, 255, 255, 0.07);
        background: rgba(255, 255, 255, 0.03);
      }
      .vp-rec-panel-title {
        display: flex;
        align-items: center;
        gap: 7px;
        font-size: 12px;
        font-weight: 700;
        color: #f07070;
        letter-spacing: 0.5px;
        text-transform: uppercase;
      }

      /* Live notation scroll area */
      .vp-rec-notation {
        min-height: 64px;
        max-height: 110px;
        overflow-y: auto;
        overflow-x: hidden;
        margin: 0.6rem 1rem;
        padding: 0.6rem 0.75rem;
        background: rgba(0, 0, 0, 0.35);
        border: 1px solid rgba(220, 60, 60, 0.18);
        border-radius: 8px;
        display: flex;
        flex-wrap: wrap;
        gap: 4px;
        align-content: flex-start;
        scroll-behavior: smooth;
      }
      .vp-rec-note {
        display: inline-flex;
        align-items: center;
        padding: 2px 7px;
        border-radius: 4px;
        font-size: 11px;
        font-weight: 700;
        font-family: 'SF Mono', 'Fira Code', monospace;
        background: rgba(220, 60, 60, 0.12);
        border: 1px solid rgba(220, 60, 60, 0.28);
        color: #f07070;
        animation: vp-note-pop 0.15s cubic-bezier(0.22, 0.68, 0.36, 1);
      }
      @keyframes vp-note-pop {
        from {
          opacity: 0;
          transform: scale(0.75);
        }
        to {
          opacity: 1;
          transform: scale(1);
        }
      }
      .vp-rec-notation-hint {
        font-size: 11px;
        color: var(--c-muted);
        font-style: italic;
        align-self: center;
        width: 100%;
        text-align: center;
      }

      /* Bottom action row */
      .vp-rec-actions {
        display: flex;
        gap: 0.5rem;
        padding: 0 1rem 1rem;
      }
      .vp-rec-again-btn {
        display: inline-flex;
        align-items: center;
        gap: 7px;
        flex: 1;
        justify-content: center;
        padding: 0.55rem 0.75rem;
        border-radius: 8px;
        font-size: 11px;
        font-weight: 700;
        cursor: pointer;
        border: 1.5px solid rgba(220, 60, 60, 0.4);
        background: rgba(220, 60, 60, 0.08);
        color: #f07070;
        transition: all 0.13s;
        text-transform: uppercase;
        letter-spacing: 0.3px;
      }
      .vp-rec-again-btn:hover {
        background: rgba(220, 60, 60, 0.16);
        border-color: rgba(220, 60, 60, 0.6);
      }
      .vp-rec-btn-dot {
        display: inline-block;
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #e04040;
        box-shadow: 0 0 5px #e04040;
        flex-shrink: 0;
      }

      /* Replay pill — full width orange-bordered button */
      .vp-rec-replay-pill {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 9px;
        width: calc(100% - 2rem);
        margin: 0.75rem 1rem 0.5rem;
        padding: 0.7rem 1rem;
        border-radius: 24px;
        font-size: 13px;
        font-weight: 800;
        letter-spacing: 1px;
        cursor: pointer;
        border: 1.5px solid rgba(220, 100, 40, 0.65);
        background: transparent;
        color: #f08040;
        text-transform: uppercase;
        transition: all 0.15s;
        box-shadow: 0 0 12px rgba(220, 100, 40, 0.15);
      }
      .vp-rec-replay-pill:hover {
        background: rgba(220, 100, 40, 0.1);
        border-color: rgba(220, 100, 40, 0.9);
        box-shadow: 0 0 20px rgba(220, 100, 40, 0.25);
        color: #ffaa60;
      }

      /* Progress row */
      .vp-rec-playback {
        padding: 0 1rem 0.25rem;
      }
      .vp-rec-progress-wrap {
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .vp-rec-progress-track {
        height: 4px;
        background: rgba(255, 255, 255, 0.07);
        border-radius: 3px;
        overflow: visible;
        position: relative;
        border: 1px solid rgba(255, 255, 255, 0.05);
      }
      .vp-rec-progress-fill {
        height: 100%;
        background: linear-gradient(90deg, #c04020 0%, #ff8040 100%);
        border-radius: 3px;
        transition: width 0.1s linear;
        position: relative;
      }
      .vp-rec-progress-thumb {
        position: absolute;
        right: -6px;
        top: 50%;
        transform: translateY(-50%);
        width: 12px;
        height: 12px;
        border-radius: 50%;
        background: radial-gradient(
          ellipse at 38% 32%,
          #ffffff 0%,
          #e0c0a0 35%,
          #c08040 100%
        );
        box-shadow:
          0 1px 4px rgba(0, 0, 0, 0.6),
          0 0 6px rgba(220, 100, 40, 0.4);
      }
      .vp-rec-time-row {
        display: flex;
        justify-content: space-between;
        font-size: 10px;
        font-weight: 600;
        color: var(--c-muted);
        font-variant-numeric: tabular-nums;
      }

      /* Download button — full width, ghost style */
      .vp-rec-dl-btn {
        display: flex;
        align-items: center;
        gap: 8px;
        width: calc(100% - 2rem);
        margin: 0.5rem 1rem 0;
        justify-content: center;
        padding: 0.55rem 1rem;
        border-radius: 8px;
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
        background: var(--c-chrome-dim);
        border: 1px solid var(--c-chrome-border);
        color: var(--c-chrome);
        transition: all 0.13s;
        text-transform: uppercase;
        letter-spacing: 0.6px;
      }
      .vp-rec-dl-btn:hover {
        background: rgba(176, 176, 192, 0.18);
        color: var(--c-chrome-hi);
      }
      .vp-rec-again-row {
        display: flex;
        justify-content: center;
        padding: 0.5rem 1rem 1rem;
      }
      .vp-rec-again-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 0.4rem 1.1rem;
        border-radius: 20px;
        font-size: 11px;
        font-weight: 700;
        cursor: pointer;
        border: 1px solid rgba(220, 60, 60, 0.3);
        background: transparent;
        color: rgba(220, 80, 80, 0.7);
        transition: all 0.13s;
        letter-spacing: 0.3px;
      }
      .vp-rec-again-btn:hover {
        background: rgba(220, 60, 60, 0.1);
        color: #f07070;
        border-color: rgba(220, 60, 60, 0.55);
      }

      /* ══ Disabled header button ═════════════════════════════════════════ */
      .vp-hbtn--disabled {
        opacity: 0.35;
        cursor: not-allowed;
        pointer-events: none;
      }
      .vp-hbtn--disabled .vp-rec-dot {
        background: var(--c-muted);
        box-shadow: none;
      }

      /* ══ Live recording ticker bar ═══════════════════════════════════════ */
      .vp-rec-ticker {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.45rem 1rem;
        background: linear-gradient(
          90deg,
          rgba(180, 30, 30, 0.14) 0%,
          rgba(10, 10, 18, 0) 60%
        );
        border-bottom: 1px solid rgba(220, 60, 60, 0.2);
        flex-shrink: 0;
        overflow: hidden;
      }
      .vp-rec-ticker-dot {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: #ff4040;
        box-shadow: 0 0 8px #ff4040;
        flex-shrink: 0;
        animation: vp-rec-pulse 1s ease-in-out infinite;
      }
      .vp-rec-ticker-label {
        font-size: 10px;
        font-weight: 800;
        color: #f07070;
        letter-spacing: 1px;
        text-transform: uppercase;
        font-variant-numeric: tabular-nums;
        flex-shrink: 0;
        min-width: 56px;
      }
      .vp-rec-ticker-notes {
        display: flex;
        align-items: center;
        gap: 4px;
        overflow: hidden;
        flex: 1;
        /* show only the tail — newest notes on right */
        flex-direction: row;
        justify-content: flex-end;
        mask-image: linear-gradient(90deg, transparent 0%, #000 18%);
        -webkit-mask-image: linear-gradient(90deg, transparent 0%, #000 18%);
      }
      .vp-rec-ticker-note {
        display: inline-flex;
        align-items: center;
        padding: 1px 6px;
        border-radius: 3px;
        font-size: 10px;
        font-weight: 700;
        font-family: 'SF Mono', 'Fira Code', monospace;
        background: rgba(220, 60, 60, 0.14);
        border: 1px solid rgba(220, 60, 60, 0.3);
        color: #f08080;
        flex-shrink: 0;
        animation: vp-note-pop 0.12s cubic-bezier(0.22, 0.68, 0.36, 1);
      }
      .vp-rec-ticker-hint {
        font-size: 10px;
        color: var(--c-muted);
        font-style: italic;
      }

      /* ══ Controls Row — recessed gaming panel ══════════════════════════ */
      .vp-controls {
        display: flex;
        align-items: center;
        gap: 0;
        padding: 0 1rem;
        background: linear-gradient(180deg, #101016 0%, #0c0c12 100%);
        border-bottom: 1px solid rgba(180, 180, 200, 0.14);
        box-shadow:
          inset 0 2px 8px rgba(0, 0, 0, 0.6),
          inset 0 -1px 0 rgba(255, 255, 255, 0.04);
        flex-shrink: 0;
        overflow-x: auto;
        height: 80px;
      }
      .vp-controls::-webkit-scrollbar {
        display: none;
      }
      .vp-cg {
        display: flex;
        flex-direction: column;
        gap: 6px;
        padding: 0 1rem;
        flex-shrink: 0;
      }
      .vp-clabel {
        font-size: 11px;
        font-weight: 700;
        color: var(--c-chrome-lo);
        text-transform: uppercase;
        letter-spacing: 0.8px;
        white-space: nowrap;
      }
      .vp-cval {
        color: var(--c-chrome-hi);
        text-transform: none;
        font-weight: 800;
        letter-spacing: 0;
        font-size: 13px;
      }
      .vp-vsep {
        width: 1px;
        height: 44px;
        background: linear-gradient(
          180deg,
          transparent 0%,
          rgba(180, 180, 200, 0.2) 30%,
          rgba(180, 180, 200, 0.2) 70%,
          transparent 100%
        );
        flex-shrink: 0;
        margin: 0 0.2rem;
      }
      /* ── Preset button groups (Sustain / Reverb / Velocity / Sound) ── */
      .vp-preset-btns {
        display: flex;
        gap: 3px;
        flex-wrap: nowrap;
      }
      .vp-preset-btns--scroll {
        overflow-x: auto;
        scrollbar-width: none;
        -ms-overflow-style: none;
      }
      .vp-preset-btns--scroll::-webkit-scrollbar {
        display: none;
      }

      .vp-preset-btn {
        padding: 4px 10px;
        border-radius: var(--radius-sm);
        font-size: 11px;
        font-weight: 700;
        cursor: pointer;
        background: linear-gradient(180deg, #1e1e28 0%, #14141c 100%);
        border: 1px solid var(--c-chrome-border);
        color: var(--c-chrome);
        white-space: nowrap;
        transition: all 0.12s;
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);
        letter-spacing: 0.3px;
      }
      .vp-preset-btn:hover {
        background: linear-gradient(180deg, #28283a 0%, #1c1c28 100%);
        color: var(--c-chrome-hi);
      }
      .vp-preset-btn--active {
        background: linear-gradient(180deg, #1c2838 0%, #101820 100%);
        border-color: var(--c-accent-border);
        color: var(--c-accent);
        box-shadow:
          0 0 6px var(--c-accent-glow),
          inset 0 1px 0 rgba(255, 255, 255, 0.08);
      }
      .vp-cval--accent {
        color: var(--c-accent);
        font-weight: 700;
      }

      /* keep old class for any remaining references */
      .vp-instrument-btns {
        display: flex;
        gap: 3px;
      }
      .vp-inst-btn {
        display: none;
      }
      /* Chrome slider: recessed track + chrome knob thumb */
      .vp-slider {
        width: 140px;
        cursor: pointer;
        height: 5px;
        -webkit-appearance: none;
        appearance: none;
        background: linear-gradient(
          180deg,
          #060608 0%,
          #121218 50%,
          #1a1a24 100%
        );
        border-radius: 3px;
        border: 1px solid rgba(180, 180, 200, 0.16);
        box-shadow:
          inset 0 1px 4px rgba(0, 0, 0, 0.8),
          inset 0 -1px 0 rgba(255, 255, 255, 0.04);
        outline: none;
      }
      .vp-slider::-webkit-slider-thumb {
        -webkit-appearance: none;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: radial-gradient(
          ellipse at 38% 30%,
          #e4e4f0 0%,
          #aaaabc 28%,
          #606070 65%,
          #2a2a34 100%
        );
        border: 1px solid rgba(255, 255, 255, 0.16);
        box-shadow:
          0 2px 6px rgba(0, 0, 0, 0.75),
          0 0 0 1px rgba(0, 0, 0, 0.4),
          inset 0 1px 1px rgba(255, 255, 255, 0.4),
          inset 0 -1px 1px rgba(0, 0, 0, 0.3);
        cursor: ew-resize;
        transition: box-shadow 0.1s;
      }
      .vp-slider::-webkit-slider-thumb:hover {
        box-shadow:
          0 2px 8px rgba(0, 0, 0, 0.85),
          0 0 0 2px var(--c-accent-border),
          inset 0 1px 1px rgba(255, 255, 255, 0.45);
      }
      .vp-slider::-moz-range-thumb {
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: radial-gradient(
          ellipse at 38% 30%,
          #e4e4f0 0%,
          #aaaabc 28%,
          #606070 65%,
          #2a2a34 100%
        );
        border: 1px solid rgba(255, 255, 255, 0.16);
        box-shadow:
          0 2px 6px rgba(0, 0, 0, 0.75),
          inset 0 1px 1px rgba(255, 255, 255, 0.4);
        cursor: ew-resize;
      }
      .vp-slider--bpm {
        width: 100px;
      }
      .vp-inline-row {
        display: flex;
        align-items: center;
        gap: 5px;
      }
      .vp-cg--reset {
        margin-left: auto;
        padding-right: 0;
      }
      .vp-metro-btn {
        padding: 5px 10px;
        border-radius: var(--radius-sm);
        font-size: 14px;
        cursor: pointer;
        background: linear-gradient(180deg, #1a1a24 0%, #121218 100%);
        border: 1px solid var(--c-chrome-border);
        color: var(--c-chrome);
        transition: all 0.12s;
        line-height: 1.2;
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);
      }
      .vp-metro-btn--on {
        background: rgba(0, 212, 255, 0.08);
        border-color: var(--c-accent-border);
        color: var(--c-accent);
        box-shadow: 0 0 6px var(--c-accent-glow);
      }
      .vp-transpose-val {
        font-size: 14px;
        font-weight: 700;
        color: var(--c-chrome-hi);
        min-width: 24px;
        text-align: center;
      }
      .vp-step-btn {
        padding: 5px 11px;
        border-radius: var(--radius-sm);
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
        background: linear-gradient(180deg, #1e1e28 0%, #14141c 100%);
        border: 1px solid var(--c-chrome-border);
        color: var(--c-chrome);
        transition: all 0.12s;
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);
      }
      .vp-step-btn:hover {
        color: var(--c-chrome-hi);
        background: linear-gradient(180deg, #282838 0%, #1c1c28 100%);
      }

      /* Reset — large silver gaming button */
      .vp-reset-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 7px;
        padding: 10px 22px;
        border-radius: 8px;
        font-size: 14px;
        font-weight: 800;
        letter-spacing: 0.5px;
        cursor: pointer;
        border: 1px solid rgba(220, 220, 236, 0.3);
        background: linear-gradient(
          180deg,
          #3a3a4a 0%,
          #28283a 30%,
          #1e1e2c 70%,
          #16161e 100%
        );
        color: var(--c-chrome-hi);
        text-transform: uppercase;
        transition: all 0.14s;
        box-shadow:
          0 0 0 1px rgba(255, 255, 255, 0.06),
          inset 0 1px 0 rgba(255, 255, 255, 0.2),
          inset 0 -1px 0 rgba(0, 0, 0, 0.4),
          0 4px 14px rgba(0, 0, 0, 0.6);
        white-space: nowrap;
      }
      .vp-reset-btn:hover {
        background: linear-gradient(
          180deg,
          #484858 0%,
          #343448 30%,
          #28283c 70%,
          #1e1e2c 100%
        );
        border-color: rgba(220, 220, 236, 0.48);
        box-shadow:
          0 0 0 1px rgba(255, 255, 255, 0.09),
          inset 0 1px 0 rgba(255, 255, 255, 0.28),
          0 0 12px rgba(176, 176, 220, 0.18),
          0 4px 18px rgba(0, 0, 0, 0.65);
        color: #ffffff;
      }
      .vp-reset-btn:active {
        transform: scale(0.96);
        box-shadow:
          inset 0 2px 6px rgba(0, 0, 0, 0.5),
          0 1px 4px rgba(0, 0, 0, 0.4);
      }

      /* ══ Sheet Music (parchment, centred, only when song loaded) ═════ */
      .vp-sheet-outer {
        flex-shrink: 0;
        background: var(--c-bg);
        display: flex;
        justify-content: center;
        padding: 0.6rem 1rem;
        border-bottom: 1px solid rgba(255, 255, 255, 0.05);
      }
      .vp-sheet-wrap {
        width: 100%;
        max-width: 80%;
        background: var(--c-parchment);
        border-radius: 6px;
        overflow: hidden;
        box-shadow: 0 2px 12px rgba(0, 0, 0, 0.35);
        max-height: 160px;
        display: flex;
        flex-direction: column;
      }
      .vp-progress-track {
        height: 2px;
        background: rgba(28, 20, 8, 0.08);
        flex-shrink: 0;
      }
      .vp-progress-fill {
        height: 100%;
        background: var(--c-ink-chord);
        transition: width 0.15s linear;
      }
      .vp-sheet {
        flex: 1;
        overflow-y: auto;
        padding: 0.45rem 0.875rem;
        display: flex;
        flex-direction: column;
        gap: 3px;
      }
      .vp-row {
        display: flex;
        flex-wrap: wrap;
        gap: 1px 3px;
        align-items: center;
        justify-content: center;
        line-height: 1;
      }
      .vp-token {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 2px;
        font-family: 'SF Mono', 'Fira Code', monospace;
        font-weight: 700;
        font-size: 12px;
        padding: 1px 4px;
        min-width: 16px;
        transition: background 0.08s;
        line-height: 1.3;
      }
      .vp-token--note {
        color: var(--c-ink-note);
      }
      .vp-token--chord {
        color: var(--c-ink-chord);
        background: rgba(110, 31, 0, 0.07);
        padding: 1px 5px;
      }
      .vp-token--rest {
        color: var(--c-ink-muted);
        font-size: 10px;
      }
      .vp-token--current {
        background: var(--c-accent) !important;
        color: #040810 !important;
        font-weight: 900;
        border-radius: 3px;
        box-shadow: 0 1px 8px rgba(0, 212, 255, 0.55);
        transform: scale(1.1);
      }
      .vp-token--played {
        color: rgba(28, 20, 8, 0.2);
      }

      /* ══ Fallboard — chrome status rail ═════════════════════════════════ */
      .vp-fallboard {
        background: linear-gradient(
          180deg,
          #2a2a38 0%,
          #1e1e2c 40%,
          #141420 70%,
          #0c0c18 100%
        );
        border-top: 1px solid rgba(220, 220, 240, 0.2);
        border-bottom: 2px solid rgba(0, 0, 0, 0.8);
        box-shadow:
          inset 0 1px 0 rgba(255, 255, 255, 0.08),
          inset 0 -1px 0 rgba(0, 0, 0, 0.3);
        padding: 0.5rem 1.25rem;
        display: flex;
        align-items: center;
        justify-content: space-between;
        flex-shrink: 0;
        gap: 1rem;
        min-height: 42px;
      }

      /* Left — brand */
      .vp-fallboard-left {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-shrink: 0;
      }
      .vp-fallboard-dot {
        display: inline-block;
        width: 5px;
        height: 5px;
        border-radius: 50%;
        background: radial-gradient(
          circle at 40% 35%,
          var(--c-chrome-hi),
          var(--c-chrome-lo)
        );
        box-shadow: 0 0 4px rgba(176, 176, 220, 0.35);
      }
      .vp-fallboard-brand {
        font-size: 11px;
        font-weight: 800;
        color: var(--c-chrome-hi);
        letter-spacing: 4px;
        text-transform: uppercase;
        text-shadow:
          0 1px 0 rgba(0, 0, 0, 0.7),
          0 0 12px rgba(0, 212, 255, 0.2);
      }

      /* Center — status chips */
      .vp-fallboard-center {
        display: flex;
        align-items: center;
        gap: 8px;
        flex: 1;
        justify-content: center;
      }
      .vp-fb-chip {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 3px 10px;
        border-radius: 20px;
        font-size: 11px;
        font-weight: 600;
        background: rgba(255, 255, 255, 0.04);
        border: 1px solid var(--c-border-2);
        color: var(--c-muted);
        white-space: nowrap;
        transition: all 0.2s;
      }
      .vp-fb-chip--on {
        background: rgba(0, 212, 255, 0.1);
        border-color: var(--c-accent-border);
        color: var(--c-accent);
        box-shadow: 0 0 8px var(--c-accent-glow);
      }
      .vp-fb-chip--accent {
        background: rgba(176, 176, 220, 0.08);
        border-color: var(--c-chrome-border);
        color: var(--c-chrome-hi);
      }
      .vp-fb-chip-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: var(--c-muted);
        transition: all 0.2s;
      }
      .vp-fb-chip--on .vp-fb-chip-dot {
        background: var(--c-accent);
        box-shadow: 0 0 6px var(--c-accent);
      }
      .vp-fb-divider {
        width: 1px;
        height: 16px;
        background: var(--c-border-2);
        flex-shrink: 0;
      }
      .vp-fb-label {
        font-size: 10px;
        color: var(--c-muted);
        white-space: nowrap;
      }

      /* Right — key count */
      .vp-fallboard-right {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        gap: 8px;
      }

      /* Two-hand feature highlight chip */
      .vp-fb-twohand {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 4px 12px;
        border-radius: 20px;
        font-size: 10px;
        font-weight: 800;
        letter-spacing: 0.6px;
        text-transform: uppercase;
        color: var(--c-accent-hi);
        background: linear-gradient(
          90deg,
          rgba(0, 212, 255, 0.18) 0%,
          rgba(0, 212, 255, 0.06) 100%
        );
        border: 1px solid var(--c-accent-border);
        box-shadow:
          0 0 10px var(--c-accent-glow),
          inset 0 1px 0 rgba(255, 255, 255, 0.08);
        position: relative;
        white-space: nowrap;
      }
      .vp-fb-twohand svg {
        color: var(--c-accent);
        filter: drop-shadow(0 0 4px var(--c-accent-glow));
      }
      .vp-fb-twohand-pulse {
        display: inline-block;
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: var(--c-accent);
        box-shadow: 0 0 6px var(--c-accent);
        animation: vp-fb-pulse 1.8s ease-in-out infinite;
      }
      @keyframes vp-fb-pulse {
        0%,
        100% {
          opacity: 1;
          transform: scale(1);
        }
        50% {
          opacity: 0.4;
          transform: scale(0.8);
        }
      }

      /* FAQ button */
      .vp-fb-faq-btn {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 4px 12px;
        border-radius: 20px;
        font-size: 10px;
        font-weight: 700;
        letter-spacing: 0.5px;
        text-transform: uppercase;
        color: var(--c-chrome-hi);
        background: linear-gradient(180deg, #2a2a38 0%, #1a1a24 100%);
        border: 1px solid var(--c-chrome-border);
        cursor: pointer;
        transition: all 0.14s;
        box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08);
        white-space: nowrap;
      }
      .vp-fb-faq-btn:hover {
        background: linear-gradient(180deg, #343448 0%, #242434 100%);
        border-color: var(--c-accent-border);
        color: var(--c-accent);
        box-shadow: 0 0 10px var(--c-accent-glow);
      }
      .vp-fb-faq-btn:active {
        transform: scale(0.96);
      }
      .vp-fb-faq-btn svg {
        flex-shrink: 0;
      }

      /* ══ FAQ Overlay ══════════════════════════════════════════════════ */
      .vp-faq-overlay {
        position: absolute;
        inset: 0;
        z-index: 500;
        background: rgba(8, 8, 14, 0.97);
        backdrop-filter: blur(16px);
        -webkit-backdrop-filter: blur(16px);
        display: flex;
        flex-direction: column;
        overflow: hidden;
        opacity: 0;
        transform: translateY(-10px) scale(0.985);
        pointer-events: none;
        transition:
          opacity 0.26s cubic-bezier(0.22, 0.68, 0.36, 1),
          transform 0.26s cubic-bezier(0.22, 0.68, 0.36, 1);
      }
      .vp-faq-overlay--open {
        opacity: 1;
        transform: translateY(0) scale(1);
        pointer-events: auto;
      }
      .vp-faq-hdr {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        padding: 1rem 1.25rem;
        border-bottom: 1px solid rgba(180, 180, 200, 0.12);
        background: linear-gradient(180deg, #1c1c28 0%, #12121c 100%);
        flex-shrink: 0;
        box-shadow:
          0 1px 0 rgba(0, 212, 255, 0.08),
          0 4px 20px rgba(0, 0, 0, 0.4);
      }
      .vp-faq-hdr-title {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        font-size: 15px;
        font-weight: 700;
        color: var(--c-accent-hi);
        letter-spacing: 0.3px;
      }
      .vp-faq-hdr-title svg {
        color: var(--c-accent);
        filter: drop-shadow(0 0 6px var(--c-accent-glow));
      }
      .vp-faq-body {
        flex: 1;
        overflow-y: auto;
        padding: 1.25rem 1.5rem 2rem;
        max-width: 820px;
        margin: 0 auto;
        width: 100%;
        box-sizing: border-box;
      }
      .vp-faq-section {
        padding: 1rem 1.1rem;
        margin-bottom: 0.85rem;
        background: rgba(255, 255, 255, 0.025);
        border: 1px solid var(--c-border);
        border-radius: 8px;
      }
      .vp-faq-section--highlight {
        background: linear-gradient(
          135deg,
          rgba(0, 212, 255, 0.07) 0%,
          rgba(0, 212, 255, 0.02) 100%
        );
        border: 1px solid var(--c-accent-border);
        box-shadow:
          0 0 18px rgba(0, 212, 255, 0.08),
          inset 0 1px 0 rgba(255, 255, 255, 0.05);
      }
      .vp-faq-q {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        margin: 0 0 0.65rem;
        font-size: 14px;
        font-weight: 700;
        color: var(--c-chrome-hi);
        letter-spacing: 0.2px;
      }
      .vp-faq-q-num {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        font-size: 11px;
        font-weight: 800;
        background: var(--c-chrome-dim);
        border: 1px solid var(--c-chrome-border);
        color: var(--c-chrome);
        flex-shrink: 0;
      }
      .vp-faq-q-num--accent {
        background: var(--c-accent-dim);
        border-color: var(--c-accent-border);
        color: var(--c-accent);
        box-shadow: 0 0 8px var(--c-accent-glow);
      }
      .vp-faq-badge {
        margin-left: auto;
        padding: 2px 8px;
        font-size: 10px;
        font-weight: 800;
        letter-spacing: 0.6px;
        color: #69f0ae;
        background: rgba(105, 240, 174, 0.12);
        border: 1px solid rgba(105, 240, 174, 0.35);
        border-radius: 10px;
      }
      .vp-faq-a {
        margin: 0 0 0.55rem;
        font-size: 12.5px;
        line-height: 1.6;
        color: var(--c-text-2);
      }
      .vp-faq-a strong {
        color: var(--c-chrome-hi);
        font-weight: 700;
      }
      .vp-faq-a em {
        color: var(--c-accent-hi);
        font-style: normal;
        font-weight: 600;
      }
      .vp-faq-a--note {
        margin-top: 0.7rem;
        padding: 0.55rem 0.75rem;
        background: rgba(201, 168, 76, 0.08);
        border-left: 2px solid var(--c-gold);
        border-radius: 0 4px 4px 0;
        font-size: 12px;
        color: var(--c-gold-light);
      }
      .vp-faq-a a,
      .vp-faq-footer a {
        color: var(--c-accent);
        text-decoration: underline;
      }
      .vp-faq-a a:hover,
      .vp-faq-footer a:hover {
        color: var(--c-accent-hi);
      }
      .vp-faq-symbols {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 0.45rem;
      }
      .vp-faq-symbols li {
        display: flex;
        align-items: flex-start;
        gap: 0.75rem;
        font-size: 12.5px;
        color: var(--c-text-2);
        line-height: 1.5;
      }
      .vp-faq-symbols li > span {
        flex: 1;
      }
      .vp-faq-tok {
        flex-shrink: 0;
        display: inline-block;
        padding: 2px 8px;
        min-width: 56px;
        text-align: center;
        font-family: 'SF Mono', 'Fira Code', monospace;
        font-size: 11.5px;
        font-weight: 700;
        background: rgba(0, 212, 255, 0.08);
        border: 1px solid var(--c-accent-border);
        border-radius: 4px;
        color: var(--c-accent-hi);
      }
      .vp-faq-handmap {
        margin: 0.65rem 0;
        padding: 0.75rem;
        background: rgba(0, 0, 0, 0.3);
        border: 1px solid var(--c-border);
        border-radius: 6px;
        display: grid;
        gap: 0.55rem;
      }
      .vp-faq-handmap-row {
        display: flex;
        align-items: center;
        gap: 0.65rem;
        font-size: 11.5px;
        color: var(--c-text-2);
      }
      .vp-faq-hand {
        flex-shrink: 0;
        padding: 3px 8px;
        border-radius: 4px;
        font-size: 10px;
        font-weight: 800;
        letter-spacing: 0.4px;
        min-width: 110px;
        text-align: center;
      }
      .vp-faq-hand--left {
        background: rgba(33, 150, 243, 0.14);
        color: var(--c-diff-easy);
        border: 1px solid rgba(33, 150, 243, 0.3);
      }
      .vp-faq-hand--mid {
        background: rgba(201, 168, 76, 0.14);
        color: var(--c-gold-light);
        border: 1px solid rgba(201, 168, 76, 0.3);
      }
      .vp-faq-hand--right {
        background: rgba(76, 175, 80, 0.14);
        color: var(--c-diff-super-easy);
        border: 1px solid rgba(76, 175, 80, 0.3);
      }
      .vp-faq-hand-keys code {
        font-family: 'SF Mono', 'Fira Code', monospace;
        font-size: 11px;
        color: var(--c-chrome-hi);
        background: rgba(255, 255, 255, 0.04);
        padding: 1px 5px;
        border-radius: 3px;
      }
      .vp-faq-example {
        margin: 0.55rem 0 0;
        padding: 0.75rem 0.9rem;
        background: var(--c-parchment);
        color: var(--c-ink-note);
        border-radius: 5px;
        font-family: 'SF Mono', 'Fira Code', monospace;
        font-size: 12.5px;
        font-weight: 700;
        line-height: 1.7;
        white-space: pre-wrap;
        box-shadow: 0 2px 10px rgba(0, 0, 0, 0.4);
      }
      .vp-faq-footer {
        padding: 0.85rem 1rem;
        border-top: 1px solid var(--c-border);
        background: rgba(255, 255, 255, 0.02);
        text-align: center;
        font-size: 11.5px;
        color: var(--c-muted);
        flex-shrink: 0;
      }

      .vp-fallboard-keys {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        font-size: 11px;
        color: var(--c-chrome);
        font-weight: 600;
        padding: 3px 10px;
        border: 1px solid var(--c-chrome-border);
        border-radius: 20px;
        background: var(--c-chrome-dim);
      }
      .vp-sustain-state {
        color: var(--c-chrome);
        font-size: 10px;
      }
      .vp-transpose-accent {
        color: var(--c-accent);
      }
      .vp-kbd {
        display: inline-flex;
        align-items: center;
        padding: 2px 7px;
        background: linear-gradient(180deg, #2c2c3c 0%, #1c1c2c 100%);
        border: 1px solid rgba(180, 180, 210, 0.28);
        border-bottom-width: 2px;
        border-radius: 4px;
        font-family: monospace;
        font-size: 10px;
        font-weight: 700;
        color: var(--c-chrome-hi);
        box-shadow:
          0 2px 0 rgba(0, 0, 0, 0.4),
          inset 0 1px 0 rgba(255, 255, 255, 0.1);
        white-space: nowrap;
      }

      /* ══ Keyboard — deep black with chrome top rail ═════════════════════ */
      .vp-keyboard-wrapper {
        flex: 1;
        min-height: 0;
        overflow-x: auto;
        overflow-y: hidden;
        background: linear-gradient(
          180deg,
          #141418 0%,
          #0a0a0e 40%,
          #040406 100%
        );
        display: flex;
        align-items: flex-end;
        padding: 0 0 1rem;
        overflow-x: auto;
        box-shadow:
          inset 0 6px 24px rgba(0, 0, 0, 0.8),
          inset 0 2px 0 rgba(255, 255, 255, 0.04);
      }
      .vp-keyboard {
        display: flex;
        align-items: flex-end;
        position: relative;
        height: 240px;
        gap: 2px;
        flex-shrink: 0;
      }
      .vp-key--white {
        position: relative;
        flex: 0 0 38px;
        height: 100%;
        background: linear-gradient(
          to bottom,
          #f8f8fc 0%,
          #ececf4 65%,
          #d8d8e2 100%
        );
        border: 1px solid #9090a4;
        border-top: none;
        border-radius: 0 0 8px 8px;
        cursor: pointer;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-end;
        padding-bottom: 10px;
        z-index: 1;
        box-shadow:
          2px 4px 16px rgba(0, 0, 0, 0.55),
          inset 0 1px 0 rgba(255, 255, 255, 0.95),
          inset -1px 0 0 rgba(0, 0, 0, 0.06);
        transition:
          background 0.06s,
          box-shadow 0.06s;
        user-select: none;
      }
      .vp-key--white:hover {
        background: linear-gradient(
          to bottom,
          #ffffff 0%,
          #f4f4fc 65%,
          #e0e0ee 100%
        );
      }
      .vp-key--white.vp-key--active {
        background: linear-gradient(
          to bottom,
          #c0d8f0 0%,
          #90b8e0 55%,
          #78a4d0 100%
        );
        box-shadow:
          1px 1px 4px rgba(0, 0, 0, 0.45),
          0 0 14px rgba(0, 212, 255, 0.28),
          inset 0 -1px 0 rgba(0, 0, 0, 0.18),
          inset 0 1px 0 rgba(255, 255, 255, 0.4);
      }
      .vp-key--black {
        position: absolute;
        top: 0;
        width: 26px;
        height: 62%;
        background: linear-gradient(
          to bottom,
          #1e1e28 0%,
          #0c0c14 35%,
          #060608 72%,
          #121218 100%
        );
        border: 1px solid rgba(0, 0, 0, 0.9);
        border-top: none;
        border-radius: 0 0 6px 6px;
        cursor: pointer;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-end;
        padding-bottom: 6px;
        z-index: 2;
        box-shadow:
          3px 7px 16px rgba(0, 0, 0, 0.85),
          inset 0 1px 0 rgba(255, 255, 255, 0.08),
          inset 1px 0 0 rgba(255, 255, 255, 0.03);
        transition:
          background 0.06s,
          box-shadow 0.06s;
        user-select: none;
      }
      .vp-key--black:hover {
        background: linear-gradient(
          to bottom,
          #28283a 0%,
          #14141e 35%,
          #0c0c14 72%,
          #181820 100%
        );
      }
      .vp-key--black.vp-key--active {
        background: linear-gradient(
          to bottom,
          #183048 0%,
          #0c1c30 65%,
          #081420 100%
        );
        box-shadow:
          1px 2px 6px rgba(0, 0, 0, 0.8),
          0 0 12px rgba(0, 212, 255, 0.3),
          inset 0 -1px 0 rgba(0, 0, 0, 0.5),
          inset 0 1px 0 rgba(0, 212, 255, 0.15);
      }
      .vp-key-label {
        font-size: 10px;
        font-weight: 700;
        font-family: monospace;
        line-height: 1;
        pointer-events: none;
        user-select: none;
      }
      .vp-key--white .vp-key-label {
        color: rgba(80, 80, 120, 0.4);
      }
      .vp-key--white.vp-key--active .vp-key-label {
        color: rgba(0, 80, 140, 0.7);
      }
      .vp-key--black .vp-key-label {
        color: rgba(176, 176, 220, 0.3);
        font-size: 9px;
      }
      .vp-key--black.vp-key--active .vp-key-label {
        color: rgba(0, 212, 255, 0.85);
      }
    </style>
  </template>
}

/* ═══════════════════════════════════════════════════════════════════════════
   VIRTUAL PIANO CARD DEF
   ═══════════════════════════════════════════════════════════════════════════ */
export class VirtualPiano extends CardDef {
  static displayName = 'Virtual Piano';
  static icon = PianoIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField, {
    computeVia: function (this: VirtualPiano) {
      return 'Virtual Piano';
    },
  });

  static isolated = IsolatedVirtualPiano;

  /* ── Fitted: icon-only / strip / tile ─────────────────────────────── */
  static fitted = class Fitted extends Component<typeof VirtualPiano> {
    <template>
      <article class='vpf'>

        {{! ══ BADGE ≤150 × <170 ══ }}
        <section class='badge'>
          <div class='badge-bezel'>
            <div class='badge-keys'>
              <span class='bk bk-w'></span><span class='bk bk-b'></span>
              <span class='bk bk-w'></span><span class='bk bk-b'></span>
              <span class='bk bk-w'></span><span class='bk bk-b'></span>
              <span class='bk bk-w'></span>
            </div>
            <div class='badge-led-row'>
              <span class='led led--on'></span>
              <span class='led'></span>
              <span class='led led--on'></span>
            </div>
          </div>
          <span class='badge-label'>VP</span>
        </section>

        {{! ══ STRIP >150 × <170 ══ }}
        <section class='strip'>
          <div class='strip-left'>
            <div class='strip-icon'>
              <svg
                width='11'
                height='11'
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              >
                <path d='M9 18V5l12-2v13' /><circle
                  cx='6'
                  cy='18'
                  r='3'
                /><circle cx='18' cy='16' r='3' />
              </svg>
            </div>
          </div>
          <div class='strip-scanlines'></div>
          <span class='strip-title'>Virtual Piano</span>
          <div class='strip-chips'>
            <span class='strip-chip'>61 Keys</span>
            <span class='strip-chip strip-chip--accent'>REC</span>
          </div>
        </section>

        {{! ══ TILE <400 × ≥170 ══ }}
        <article class='tile'>
          <div class='tile-scanlines'></div>
          <header class='tile-hd'>
            <div class='tile-hd-left'>
              <div class='tile-brand'>
                <svg
                  width='11'
                  height='11'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <path d='M9 18V5l12-2v13' /><circle
                    cx='6'
                    cy='18'
                    r='3'
                  /><circle cx='18' cy='16' r='3' />
                </svg>
              </div>
              <span class='tile-title'>Virtual Piano</span>
            </div>
            <div class='tile-leds'>
              <span class='led led--on'></span>
              <span class='led led--pulse'></span>
              <span class='led'></span>
            </div>
          </header>
          <section class='tile-body'>
            <div class='tile-keys-panel'>
              <div class='tile-keys-bezel'>
                <div class='tile-keys'>
                  <span class='tk tk-w'></span><span class='tk tk-b'></span>
                  <span class='tk tk-w'></span><span class='tk tk-b'></span>
                  <span class='tk tk-w'></span><span class='tk tk-b'></span>
                  <span class='tk tk-w'></span><span class='tk tk-b'></span>
                  <span class='tk tk-w'></span><span class='tk tk-b'></span>
                  <span class='tk tk-w'></span>
                </div>
              </div>
            </div>
          </section>
          <footer class='tile-ft'>
            <div class='tile-ft-left'>
              <span class='ft-chip'>Piano</span>
              <span class='ft-chip'>Organ</span>
              <span class='ft-chip'>Harp</span>
            </div>
            <span class='ft-chip ft-chip--accent'>● REC</span>
          </footer>
        </article>

        {{! ══ CARD ≥400 × ≥170 ══ }}
        <article class='card'>
          <div class='card-left'>
            <div class='card-scanlines'></div>
            <div class='card-keys-panel'>
              <div class='card-keys-bezel'>
                <div class='card-keys'>
                  <span class='ck ck-w'></span><span class='ck ck-b'></span>
                  <span class='ck ck-w'></span><span class='ck ck-b'></span>
                  <span class='ck ck-w'></span><span class='ck ck-b'></span>
                  <span class='ck ck-w'></span><span class='ck ck-b'></span>
                  <span class='ck ck-w'></span>
                </div>
              </div>
            </div>
            <div class='card-left-leds'>
              <span class='led led--on'></span>
              <span class='led led--pulse'></span>
            </div>
            <span class='card-keys-label'>61 KEYS</span>
          </div>
          <div class='card-divider'></div>
          <section class='card-body'>
            <div class='card-icon-row'>
              <div class='card-brand-icon'>
                <svg
                  width='11'
                  height='11'
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <path d='M9 18V5l12-2v13' /><circle
                    cx='6'
                    cy='18'
                    r='3'
                  /><circle cx='18' cy='16' r='3' />
                </svg>
              </div>
              <span class='card-eyebrow'>Virtual Piano</span>
            </div>
            <h2 class='card-title'>Play. Record.<br />Explore.</h2>
            <p class='card-meta'>VP.net notation · Multi-instrument</p>
            <div class='card-chips'>
              <span class='chip'>Piano</span>
              <span class='chip'>Organ</span>
              <span class='chip'>Harp</span>
              <span class='chip chip--accent'>● REC</span>
            </div>
          </section>
        </article>

      </article>

      <style scoped>
        .vpf {
          /* ── Dark chrome gaming tokens ── */
          --c-bg: #0a0a10;
          --c-surface: #12121a;
          --c-surface-2: #1a1a24;
          --c-surface-3: #22222e;
          --c-chrome: #b8b8cc;
          --c-chrome-hi: #e0e0f0;
          --c-chrome-lo: #5a5a6e;
          --c-accent: #00d4ff;
          --c-accent-hi: #60eaff;
          --c-accent-dim: rgba(0, 212, 255, 0.14);
          --c-accent-border: rgba(0, 212, 255, 0.32);
          --c-accent-glow: rgba(0, 212, 255, 0.2);
          --c-led-green: #00ff88;
          --c-led-glow: rgba(0, 255, 136, 0.35);
          --c-text: #e0e0f0;
          --c-text-2: #9090b0;
          --c-muted: #505068;
          --c-border: rgba(184, 184, 204, 0.12);
          --c-border-hi: rgba(184, 184, 204, 0.22);
          --c-key-white: #d8d8ea;
          --c-key-black: #0a0a12;
          /* chrome bezel shadow */
          --c-bezel:
            0 1px 0 rgba(224, 224, 240, 0.25) inset,
            0 -1px 0 rgba(0, 0, 0, 0.5) inset,
            1px 0 0 rgba(224, 224, 240, 0.1) inset,
            -1px 0 0 rgba(0, 0, 0, 0.3) inset;

          width: 100%;
          height: 100%;
          font-family:
            -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;
        }

        /* ── shared scanlines overlay ── */
        .tile-scanlines,
        .strip-scanlines,
        .card-scanlines {
          position: absolute;
          inset: 0;
          background: repeating-linear-gradient(
            0deg,
            transparent,
            transparent 3px,
            rgba(0, 0, 0, 0.07) 3px,
            rgba(0, 0, 0, 0.07) 4px
          );
          pointer-events: none;
          z-index: 0;
        }

        /* ── LED indicator ── */
        .led {
          display: inline-block;
          width: 5px;
          height: 5px;
          border-radius: 50%;
          background: var(--c-muted);
          box-shadow: none;
        }
        .led--on {
          background: var(--c-led-green);
          box-shadow:
            0 0 6px var(--c-led-glow),
            0 0 2px var(--c-led-green);
        }
        .led--pulse {
          background: var(--c-accent);
          box-shadow:
            0 0 6px var(--c-accent-glow),
            0 0 2px var(--c-accent);
        }

        /* ── All sub-formats hidden ── */
        .badge,
        .strip,
        .tile,
        .card {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
        }

        /* ══ BADGE ≤150 × <170 ══ */
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 8px;
            background: var(--c-bg);
            padding: 10px 8px;
          }
        }

        .badge-bezel {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 6px;
          padding: 8px 10px 6px;
          background: linear-gradient(
            180deg,
            var(--c-surface-2) 0%,
            var(--c-surface) 100%
          );
          border-radius: 6px;
          box-shadow:
            var(--c-bezel),
            0 2px 8px rgba(0, 0, 0, 0.5);
          border: 1px solid var(--c-border-hi);
        }

        .badge-keys {
          display: flex;
          align-items: flex-end;
          gap: 1px;
          height: 20px;
        }

        .bk {
          display: block;
          border-radius: 0 0 2px 2px;
          flex-shrink: 0;
        }
        .bk-w {
          width: 6px;
          height: 20px;
          background: linear-gradient(
            180deg,
            var(--c-key-white) 0%,
            #c0c0d4 100%
          );
          border: 1px solid rgba(0, 0, 0, 0.25);
        }
        .bk-b {
          width: 4px;
          height: 13px;
          background: linear-gradient(
            180deg,
            #1a1a28 0%,
            var(--c-key-black) 100%
          );
          margin: 0 -2px;
          z-index: 1;
          position: relative;
          border-radius: 0 0 2px 2px;
          border: 1px solid rgba(255, 255, 255, 0.05);
        }

        .badge-led-row {
          display: flex;
          gap: 4px;
          align-items: center;
        }

        .badge-label {
          font-size: 9px;
          font-weight: 800;
          color: var(--c-accent);
          letter-spacing: 0.12em;
          text-transform: uppercase;
        }

        /* ══ STRIP >150 × <170 ══ */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            position: relative;
            align-items: center;
            gap: 10px;
            padding: 0 14px;
            background: var(--c-bg);
            border-left: 3px solid var(--c-accent);
            box-shadow: inset 0 0 40px rgba(0, 212, 255, 0.04);
          }
        }

        .strip-left {
          flex-shrink: 0;
          position: relative;
          z-index: 1;
        }

        .strip-icon {
          width: 28px;
          height: 28px;
          border-radius: 50%;
          background: var(--c-accent-dim);
          border: 1px solid var(--c-accent-border);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--c-accent);
          box-shadow: 0 0 10px var(--c-accent-glow);
        }

        .strip-title {
          position: relative;
          z-index: 1;
          flex: 1;
          font-size: 13px;
          font-weight: 800;
          color: var(--c-text);
          letter-spacing: 0.03em;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .strip-chips {
          position: relative;
          z-index: 1;
          display: flex;
          gap: 4px;
          flex-shrink: 0;
        }

        .strip-chip {
          font-size: 9px;
          font-weight: 700;
          color: var(--c-text-2);
          background: var(--c-surface-2);
          border: 1px solid var(--c-border-hi);
          border-radius: 3px;
          padding: 2px 5px;
          white-space: nowrap;
          box-shadow: var(--c-bezel);
        }

        .strip-chip--accent {
          color: var(--c-accent);
          background: var(--c-accent-dim);
          border-color: var(--c-accent-border);
          box-shadow: 0 0 6px var(--c-accent-glow);
        }

        /* ══ TILE <400 × ≥170 ══ */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            position: relative;
            background: var(--c-bg);
          }
        }

        .tile-hd {
          position: relative;
          z-index: 1;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 8px 12px;
          border-bottom: 1px solid var(--c-border-hi);
          flex-shrink: 0;
          background: linear-gradient(
            180deg,
            var(--c-surface-2) 0%,
            var(--c-surface) 100%
          );
          box-shadow: 0 1px 0 rgba(0, 0, 0, 0.4);
        }

        .tile-hd-left {
          display: flex;
          align-items: center;
          gap: 7px;
        }

        .tile-brand {
          width: 20px;
          height: 20px;
          border-radius: 4px;
          background: var(--c-accent-dim);
          border: 1px solid var(--c-accent-border);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--c-accent);
          box-shadow: 0 0 6px var(--c-accent-glow);
        }

        .tile-title {
          font-size: 11px;
          font-weight: 800;
          color: var(--c-text);
          letter-spacing: 0.04em;
        }

        .tile-leds {
          display: flex;
          gap: 5px;
          align-items: center;
        }

        .tile-body {
          position: relative;
          z-index: 1;
          flex: 1;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 12px;
          background: var(--c-bg);
        }

        .tile-keys-panel {
          background: linear-gradient(
            180deg,
            var(--c-surface-3) 0%,
            var(--c-surface) 100%
          );
          border-radius: 8px;
          padding: 8px 10px;
          box-shadow:
            var(--c-bezel),
            0 4px 16px rgba(0, 0, 0, 0.6),
            0 0 0 1px var(--c-border-hi),
            inset 0 0 12px rgba(0, 212, 255, 0.03);
        }

        .tile-keys-bezel {
          background: #050508;
          border-radius: 3px;
          padding: 4px 4px 0;
          box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.8);
        }

        .tile-keys {
          display: flex;
          align-items: flex-end;
          gap: 2px;
          height: 40px;
          position: relative;
          padding-bottom: 2px;
        }

        .tk {
          display: block;
          border-radius: 0 0 3px 3px;
          flex-shrink: 0;
        }
        .tk-w {
          width: 11px;
          height: 40px;
          background: linear-gradient(
            180deg,
            var(--c-key-white) 0%,
            #c0c0d4 100%
          );
          border: 1px solid rgba(0, 0, 0, 0.2);
        }
        .tk-b {
          width: 7px;
          height: 26px;
          background: linear-gradient(
            180deg,
            #222230 0%,
            var(--c-key-black) 100%
          );
          border: 1px solid rgba(255, 255, 255, 0.05);
          margin: 0 -4px;
          z-index: 1;
          position: relative;
        }

        .tile-ft {
          position: relative;
          z-index: 1;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 6px 12px;
          border-top: 1px solid var(--c-border-hi);
          flex-shrink: 0;
          background: linear-gradient(
            180deg,
            var(--c-surface) 0%,
            var(--c-surface-2) 100%
          );
        }

        .tile-ft-left {
          display: flex;
          gap: 4px;
        }

        .ft-chip {
          font-size: 9px;
          font-weight: 600;
          color: var(--c-text-2);
          background: var(--c-surface-3);
          border: 1px solid var(--c-border-hi);
          border-radius: 3px;
          padding: 2px 6px;
          white-space: nowrap;
          box-shadow: var(--c-bezel);
        }

        .ft-chip--accent {
          color: var(--c-accent);
          background: var(--c-accent-dim);
          border-color: var(--c-accent-border);
          box-shadow: 0 0 6px var(--c-accent-glow);
        }

        /* ══ CARD ≥400 × ≥170 ══ */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: row;
            background: var(--c-bg);
          }
        }

        .card-left {
          width: 130px;
          flex-shrink: 0;
          position: relative;
          background: linear-gradient(
            180deg,
            var(--c-surface-3) 0%,
            var(--c-surface) 100%
          );
          border-right: 1px solid var(--c-border-hi);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 8px;
          box-shadow: inset -2px 0 8px rgba(0, 0, 0, 0.3);
        }

        .card-keys-panel {
          position: relative;
          z-index: 1;
          background: linear-gradient(
            180deg,
            var(--c-surface-2) 0%,
            var(--c-surface) 100%
          );
          border-radius: 6px;
          padding: 6px 8px;
          box-shadow:
            var(--c-bezel),
            0 3px 12px rgba(0, 0, 0, 0.5),
            0 0 0 1px var(--c-border-hi),
            inset 0 0 8px rgba(0, 212, 255, 0.03);
        }

        .card-keys-bezel {
          background: #050508;
          border-radius: 2px;
          padding: 3px 3px 0;
          box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.8);
        }

        .card-keys {
          display: flex;
          align-items: flex-end;
          gap: 1px;
          height: 30px;
          position: relative;
          padding-bottom: 2px;
        }

        .ck {
          display: block;
          border-radius: 0 0 2px 2px;
          flex-shrink: 0;
        }
        .ck-w {
          width: 8px;
          height: 30px;
          background: linear-gradient(
            180deg,
            var(--c-key-white) 0%,
            #c0c0d4 100%
          );
          border: 1px solid rgba(0, 0, 0, 0.2);
        }
        .ck-b {
          width: 5px;
          height: 19px;
          background: linear-gradient(
            180deg,
            #222230 0%,
            var(--c-key-black) 100%
          );
          border: 1px solid rgba(255, 255, 255, 0.05);
          margin: 0 -3px;
          z-index: 1;
          position: relative;
        }

        .card-left-leds {
          position: relative;
          z-index: 1;
          display: flex;
          gap: 5px;
        }

        .card-keys-label {
          position: relative;
          z-index: 1;
          font-size: 8px;
          font-weight: 800;
          color: var(--c-accent);
          letter-spacing: 0.12em;
        }

        .card-divider {
          width: 1px;
          background: var(--c-border-hi);
          flex-shrink: 0;
          box-shadow: 1px 0 0 rgba(0, 0, 0, 0.5);
        }

        .card-body {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 4px;
          padding: 14px 16px;
          justify-content: center;
          background: linear-gradient(
            135deg,
            var(--c-surface) 0%,
            var(--c-bg) 100%
          );
          box-shadow: inset 0 0 60px rgba(0, 212, 255, 0.02);
        }

        .card-icon-row {
          display: flex;
          align-items: center;
          gap: 6px;
          margin-bottom: 2px;
        }

        .card-brand-icon {
          width: 18px;
          height: 18px;
          border-radius: 4px;
          background: var(--c-accent-dim);
          border: 1px solid var(--c-accent-border);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--c-accent);
          flex-shrink: 0;
          box-shadow: 0 0 6px var(--c-accent-glow);
        }

        .card-eyebrow {
          font-size: 10px;
          font-weight: 700;
          color: var(--c-accent);
          text-transform: uppercase;
          letter-spacing: 0.1em;
        }

        .card-title {
          font-size: 15px;
          font-weight: 800;
          color: var(--c-text);
          line-height: 1.2;
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .card-meta {
          font-size: 10px;
          color: var(--c-muted);
          margin: 0;
          letter-spacing: 0.02em;
        }

        .card-chips {
          display: flex;
          gap: 4px;
          flex-wrap: wrap;
          margin-top: 4px;
        }

        .chip {
          font-size: 9px;
          font-weight: 600;
          color: var(--c-text-2);
          background: var(--c-surface-3);
          border: 1px solid var(--c-border-hi);
          border-radius: 3px;
          padding: 2px 7px;
          white-space: nowrap;
          box-shadow: var(--c-bezel);
        }

        .chip--accent {
          color: var(--c-accent);
          background: var(--c-accent-dim);
          border-color: var(--c-accent-border);
          box-shadow: 0 0 6px var(--c-accent-glow);
        }
      </style>
    </template>
  };

  /* ── Embedded ─────────────────────────────────────────────────────── */
  static embedded = class Embedded extends Component<typeof VirtualPiano> {
    <template>
      <div class='vpe-row'>
        <svg
          class='vpe-icon'
          width='15'
          height='15'
          viewBox='0 0 24 24'
          fill='none'
          stroke='currentColor'
          stroke-width='2'
        >
          <path d='M9 18V5l12-2v13' /><circle cx='6' cy='18' r='3' /><circle
            cx='18'
            cy='16'
            r='3'
          />
        </svg>
        <span class='vpe-label'>Virtual Piano</span>
        <span class='vpe-tag'>61 keys</span>
        <span class='vpe-tag'>VP.net</span>
      </div>

      <style scoped>
        .vpe-row {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.75rem;
          border-radius: 6px;
          background: rgba(255, 140, 66, 0.04);
          border: 1px solid rgba(255, 140, 66, 0.12);
        }

        .vpe-icon {
          color: #ff8c42;
          flex-shrink: 0;
        }

        .vpe-label {
          font-weight: 600;
          font-size: 13px;
          color: #1a1a2e;
          flex: 1;
        }

        .vpe-tag {
          padding: 1px 6px;
          border-radius: 8px;
          font-size: 9px;
          font-weight: 700;
          background: rgba(255, 140, 66, 0.1);
          color: #ff8c42;
          border: 1px solid rgba(255, 140, 66, 0.2);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}
