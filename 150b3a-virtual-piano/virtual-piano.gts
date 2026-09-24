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
import { CardDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { Button, BoxelInput } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  codeRef,
  realmURL,
  type Query,
  type LooseSingleCardDocument,
} from '@cardstack/runtime-common';
import PianoIcon from '@cardstack/boxel-icons/piano';
import type { Genre } from './genre';
import { diffLabel, diffClass } from './utils/diff-helpers';
import {
  KEYBOARD_MAPPING,
  pianoKeyFromKeyboardEvent,
  type KeyData,
  WHITE_KEYS,
  BLACK_KEYS,
} from './utils/keyboard-helpers';
import { type Beat, parseNotationBeats } from './utils/notation-helpers';
import { noteFreq, INSTRUMENT_PROFILES } from './utils/audio-helpers';

/* @ts-expect-error import.meta is valid ESM */
const here: string = import.meta.url;
const musicSheetRef = codeRef(here, './music-sheet', 'MusicSheet');

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
    } catch {
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
    } catch {
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
    if (!this.selectedSong?.difficulty) return '';
    return diffLabel(this.selectedSong.difficulty);
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
    } catch {
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
        } catch {
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
        } catch {
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
      } catch {
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
  handleSearchInput(value: string) {
    this.searchQuery = value;
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
      } catch {
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
          <BoxelInput
            @type='search'
            class='vp-search-input'
            @value={{this.searchQuery}}
            @placeholder='Search songs…'
            @onInput={{this.handleSearchInput}}
          />
          <Button
            @kind='text-only'
            @size='auto'
            class='vp-new-song-btn'
            type='button'
            title='Create a new Music Sheet card'
            {{on 'click' this.createNewSong}}
          >＋ New Song</Button>
          <Button
            @kind='text-only'
            @size='auto'
            class='vp-btn-icon'
            type='button'
            {{on 'click' this.closeSongPanel}}
          >✕</Button>
        </div>
        <div class='vp-song-list'>
          {{#if this.hasSongs}}
            {{#each this.filteredSongs as |song|}}
              <Button
                @kind='text-only'
                @size='auto'
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
              </Button>
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
      <header class='vp-header'>
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
        <nav class='vp-header-right' aria-label='Piano actions'>
          <Button
            @kind='text-only'
            @size='auto'
            class='vp-hbtn vp-hbtn--ghost'
            type='button'
            {{on 'click' this.toggleShowKeys}}
          >
            {{if this.showKeys 'Hide' 'Show'}}
            Keys
          </Button>
          {{! When not recording: open panel. When recording: stop directly. Disabled during auto-play. }}
          {{#if this.isRecording}}
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-hbtn vp-hbtn--rec vp-hbtn--rec--active'
              type='button'
              {{on 'click' this.stopRecording}}
            >
              <span class='vp-rec-dot vp-rec-dot--on'></span>
              {{this.recordTimeLabel}}
              · STOP
            </Button>
          {{else}}
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-hbtn vp-hbtn--rec
                {{if this.isAutoPlaying "vp-hbtn--disabled"}}'
              type='button'
              disabled={{this.isAutoPlaying}}
              {{on 'click' this.openRecordPanel}}
            >
              <span class='vp-rec-dot'></span>
              {{if this.isAutoPlaying 'Playing…' 'Record'}}
            </Button>
          {{/if}}
          <Button
            @kind='text-only'
            @size='auto'
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
          </Button>
        </nav>

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
              <Button
                @kind='text-only'
                @size='auto'
                class='vp-btn-icon'
                type='button'
                {{on 'click' this.toggleRecordPanel}}
              >✕</Button>
            </div>

            {{! After stop: playback row }}
            {{#if this.recordedBlob}}
              {{! Full-width replay button (pill style like reference) }}
              <Button
                @kind='text-only'
                @size='auto'
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
              </Button>

              {{! Download }}
              <Button
                @kind='text-only'
                @size='auto'
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
              </Button>

              {{! Record again }}
              <div class='vp-rec-again-row'>
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='vp-rec-again-btn'
                  type='button'
                  {{on 'click' this.openRecordPanel}}
                >
                  <span class='vp-rec-btn-dot'></span>
                  Record Again
                </Button>
              </div>
            {{/if}}

          </div>
        {{/if}}
      </header>

      {{! ══ CONTROLS ROW — always-visible horizontal strip ══════════════ }}
      <nav class='vp-controls' aria-label='Sound and playback controls'>

        {{! ── Sound / Instrument ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Sound
            <span
              class='vp-cval vp-cval--accent'
            >{{this.instrumentDisplayName}}</span>
          </span>
          <div class='vp-preset-btns vp-preset-btns--scroll'>
            {{#each this.instrumentOptions as |opt|}}
              <Button
                @kind='text-only'
                @size='auto'
                class='vp-preset-btn
                  {{if (eq this.instrument opt.key) "vp-preset-btn--active"}}'
                type='button'
                {{on 'click' (fn this.setInstrument opt.key)}}
              >{{opt.label}}</Button>
            {{/each}}
          </div>
        </div>

        <div class='vp-vsep'></div>

        {{! ── Sustain ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Sustain</span>
          <div class='vp-preset-btns'>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.sustainPreset "off") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setSustainPreset 'off')}}
            >OFF</Button>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.sustainPreset "low") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setSustainPreset 'low')}}
            >Low</Button>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.sustainPreset "medium") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setSustainPreset 'medium')}}
            >Med</Button>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.sustainPreset "high") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setSustainPreset 'high')}}
            >High</Button>
          </div>
        </div>

        {{! ── Reverb ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Reverb</span>
          <div class='vp-preset-btns'>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.reverbPreset "low") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setReverbPreset 'low')}}
            >Low</Button>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.reverbPreset "medium") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setReverbPreset 'medium')}}
            >Med</Button>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.reverbPreset "hall") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setReverbPreset 'hall')}}
            >Hall</Button>
          </div>
        </div>

        {{! ── Velocity ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Velocity</span>
          <div class='vp-preset-btns'>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.velocityPreset "low") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setVelocityPreset 'low')}}
            >Low</Button>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if
                  (eq this.velocityPreset "medium")
                  "vp-preset-btn--active"
                }}'
              type='button'
              {{on 'click' (fn this.setVelocityPreset 'medium')}}
            >Med</Button>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-preset-btn
                {{if (eq this.velocityPreset "high") "vp-preset-btn--active"}}'
              type='button'
              {{on 'click' (fn this.setVelocityPreset 'high')}}
            >High</Button>
          </div>
        </div>

        <div class='vp-vsep'></div>

        {{! ── Volume ── }}
        {{! type='range' kept native: BoxelInput has no range-slider variant }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Vol
            <span class='vp-cval'>{{this.volumeLevel}}%</span></span>
          <input
            class='vp-slider'
            type='range'
            aria-label='Volume'
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
            {{! type='range' kept native: BoxelInput has no range-slider variant }}
            <input
              class='vp-slider vp-slider--bpm'
              type='range'
              aria-label='BPM'
              min='40'
              max='240'
              value={{this.bpmOverride}}
              {{on 'input' this.handleBpmChange}}
            />
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-metro-btn {{if this.metronomeOn "vp-metro-btn--on"}}'
              type='button'
              {{on 'click' this.toggleMetronome}}
            >🎵</Button>
          </div>
        </div>

        <div class='vp-vsep'></div>

        {{! ── Transpose ── }}
        <div class='vp-cg'>
          <span class='vp-clabel'>Transpose
            <span class='vp-cval'>{{this.transpose}} st</span></span>
          <div class='vp-inline-row'>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-step-btn'
              type='button'
              {{on 'click' (fn this.adjustTranspose -1)}}
            >−1</Button>
            <span class='vp-transpose-val'>{{this.transpose}}</span>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-step-btn'
              type='button'
              {{on 'click' (fn this.adjustTranspose 1)}}
            >+1</Button>
          </div>
        </div>

        <div class='vp-cg vp-cg--reset'>
          <Button
            @kind='text-only'
            @size='auto'
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
          </Button>
        </div>

      </nav>

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
            <Button
              @kind='text-only'
              @size='auto'
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
            </Button>
            <Button
              @kind='text-only'
              @size='auto'
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
            </Button>
            <Button
              @kind='text-only'
              @size='auto'
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
            </Button>
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
          <Button
            @kind='text-only'
            @size='auto'
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
          </Button>
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
              <h2>Virtual Piano · FAQ &amp; Notation Guide</h2>
            </div>
            <Button
              @kind='text-only'
              @size='auto'
              class='vp-btn-icon'
              type='button'
              {{on 'click' this.closeFaq}}
            >✕</Button>
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
      {{! Kept as native <button> rather than BoxelButton: this is a 61-key
          grid rendered from a tight absolute-positioning layout
          (WW/leftPx math in utils/keyboard-helpers.gts) where every extra
          wrapper element or the boxel-button base class's own padding/border
          would throw off key width and the black-key overlay offsets.
          A real <button> is still correct semantic HTML for a key. }}
      <section class='vp-keyboard-wrapper' aria-label='Piano keyboard'>
        <div class='vp-keyboard'>
          {{#each WHITE_KEYS as |keyData|}}
            <button
              class='vp-key vp-key--white
                {{if (get this.pressedMap keyData.id) "vp-key--active"}}'
              type='button'
              aria-label='{{keyData.note}}{{keyData.octave}}'
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
              aria-label='{{keyData.note}}{{keyData.octave}}'
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
      </section>

    </div>

    <style scoped>
      /* ══ Design Tokens — Silver Chrome Gaming ══════════════════════════ */
      .vp-app {
        /* ── Chrome / Silver palette ── */
        --vp-chrome-dim: color-mix(in oklch, var(--border) 10%, transparent);
        --vp-chrome-border: color-mix(in oklch, var(--border) 24%, transparent);

        /* ── Cyan gaming accent ── */
        --vp-accent-dim: color-mix(in oklch, var(--info) 12%, transparent);
        --vp-accent-border: color-mix(in oklch, var(--info) 30%, transparent);
        --vp-accent-glow: color-mix(in oklch, var(--info) 22%, transparent);

        /* ── Legacy gold kept for parchment / notation only ── */
        --vp-gold-dim: color-mix(in oklch, var(--accent) 12%, transparent);
        --vp-gold-border: color-mix(in oklch, var(--accent) 26%, transparent);

        /* ── Backgrounds ── */

        /* ── Text ── */

        /* ── Borders ── */

        /* ── Difficulty colours ── */
        --vp-diff-easy-bg: var(--hover);
        --vp-diff-super-easy-bg: var(--hover);
        --vp-diff-inter-bg: var(--hover);
        --vp-diff-expert-bg: var(--hover);

        --radius-sm: 0.1875rem;

        /* ── Silver-frame bezel ── */
        --vp-bezel-top: color-mix(in oklch, var(--inset) 32%, transparent);
        --vp-bezel-side: color-mix(
          in oklch,
          var(--subtle-foreground) 20%,
          transparent
        );
        --vp-bezel-bottom: color-mix(
          in oklch,
          var(--muted-foreground) 45%,
          transparent
        );

        display: flex;
        flex-direction: column;
        height: 100%;
        min-height: 0;
        background-color: var(--card);
        color: var(--card-foreground);
        font-family: 'Inter', system-ui, sans-serif;
        overflow: hidden;
        position: relative;

        /* Silver frame */
        border-top: 2px solid var(--vp-bezel-top);
        border-left: 2px solid var(--vp-bezel-side);
        border-right: 2px solid var(--vp-bezel-side);
        border-bottom: 2px solid var(--vp-bezel-bottom);
        box-sizing: border-box;
        box-shadow:
          inset 0 0 0 1px color-mix(in oklch, var(--card) 6%, transparent),
          inset 1px 1px 0 color-mix(in oklch, var(--card) 10%, transparent),
          0 8px 40px color-mix(in oklch, var(--shadow-color) 70%, transparent);
      }

      /* ══ Song Search Overlay (full screen) ═══════════════════════════ */
      .vp-song-overlay {
        position: absolute;
        inset: 0;
        z-index: 300;
        background-color: var(--tooltip);
        color: var(--tooltip-foreground);
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
        border-bottom: 1px solid
          color-mix(in oklch, var(--border) 12%, transparent);
        box-shadow:
          0 1px 0 color-mix(in oklch, var(--info) 8%, transparent),
          0 4px 20px color-mix(in oklch, var(--shadow-color) 40%, transparent);
        flex-shrink: 0;
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        color: var(--info-ink);
      }
      .vp-search-input {
        flex: 1;
        background-color: transparent;
        border: none;
        color: var(--card-foreground);
        font-size: 1.0625rem;
        font-weight: 500;
        letter-spacing: 0.2px;
        outline: none;
      }
      .vp-search-input::placeholder {
        color: var(--muted-foreground);
      }
      .vp-btn-icon {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 1.875rem;
        height: 1.875rem;
        background-color: var(--vp-chrome-dim);
        border: 1px solid var(--vp-chrome-border);
        border-radius: 50%;
        color: var(--subtle-foreground);
        cursor: pointer;
        font-size: 0.8125rem;
        transition: all 0.15s;
        line-height: 1;
      }
      .vp-btn-icon:hover {
        background-color: color-mix(in oklch, var(--border) 20%, transparent);
        color: var(--card-foreground);
        border-color: color-mix(in oklch, var(--border) 40%, transparent);
      }
      .vp-new-song-btn {
        display: inline-flex;
        align-items: center;
        gap: 0.25rem;
        padding: 0.4rem 0.75rem;
        background-color: var(--primary);
        border: 1px solid var(--primary);
        border-radius: 62.4375rem;
        color: var(--primary-foreground);
        cursor: pointer;
        font-size: 0.75rem;
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
        border-top: 1px solid var(--vp-chrome-border);
        color: var(--muted-foreground);
        font-size: 0.6875rem;
        line-height: 1.5;
        text-align: center;
      }
      .vp-song-overlay-footer a {
        color: var(--card-foreground);
        text-decoration: underline;
      }
      .vp-song-overlay-footer a:hover {
        color: var(--primary-ink);
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
        background-color: transparent;
        border: none;
        border-bottom: 1px solid var(--border);
        cursor: pointer;
        text-align: left;
        transition: background 0.12s;
      }
      .vp-song-item:hover {
        background-color: var(--hover);
      }
      .vp-song-item-info {
        display: flex;
        flex-direction: column;
        gap: 2px;
        min-width: 0;
        flex: 1;
      }
      .vp-song-item-title {
        font-size: 0.8125rem;
        font-weight: 600;
        color: var(--card-foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .vp-song-item-artist {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .vp-song-item-meta {
        display: flex;
        align-items: center;
        gap: 0.25rem;
        flex-wrap: wrap;
      }
      .vp-meta-tag {
        padding: 1px 0.375rem;
        border-radius: 0.25rem;
        font-size: 0.5625rem;
        font-weight: 700;
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .vp-empty-songs {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.5rem;
        padding: 2.5rem 1.5rem;
        text-align: center;
        color: var(--muted-foreground);
        font-size: 0.75rem;
        line-height: 1.5;
      }

      /* ══ Header Row — brushed steel bar ════════════════════════════════ */
      .vp-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        padding: 0.6rem 1rem;
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border-bottom: 1px solid
          color-mix(in oklch, var(--border) 18%, transparent);
        box-shadow:
          0 1px 0 color-mix(in oklch, var(--card) 6%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 8%, transparent);
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
        color: var(--subtle-foreground);
        flex-shrink: 0;
      }
      .vp-brand {
        font-size: 0.9375rem;
        font-weight: 800;
        color: var(--card-foreground);
        letter-spacing: 1.5px;
        white-space: nowrap;
        flex-shrink: 0;
        text-transform: uppercase;
        text-shadow:
          0 1px 0 color-mix(in oklch, var(--shadow-color) 50%, transparent),
          0 0 8px color-mix(in oklch, var(--info) 18%, transparent);
      }
      /* .vp-sep / .vp-song-title / .vp-song-artist removed — now in .vp-song-bar */
      .vp-diff-badge {
        padding: 1px 0.3125rem;
        border-radius: 0.375rem;
        font-size: 0.5rem;
        font-weight: 800;
        letter-spacing: 0.4px;
        flex-shrink: 0;
      }
      .vp-bpm-badge {
        font-size: 0.625rem;
        font-weight: 700;
        color: var(--info-ink);
        background-color: var(--vp-accent-dim);
        border: 1px solid var(--vp-accent-border);
        border-radius: 0.25rem;
        padding: 1px 0.375rem;
        white-space: nowrap;
        flex-shrink: 0;
        box-shadow: 0 0 6px var(--vp-accent-glow);
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
        gap: 0.3125rem;
        padding: 0.375rem 0.875rem;
        border-radius: var(--radius-sm);
        font-size: 0.8125rem;
        font-weight: 600;
        cursor: pointer;
        border: 1px solid transparent;
        background-color: transparent;
        color: var(--subtle-foreground);
        transition: all 0.12s;
        white-space: nowrap;
      }
      .vp-hbtn:active {
        transform: scale(0.95);
      }
      .vp-hbtn--ghost {
        border-color: var(--vp-chrome-border);
        color: var(--subtle-foreground);
        background-color: var(--vp-chrome-dim);
      }
      .vp-hbtn--ghost:hover {
        border-color: color-mix(in oklch, var(--border) 45%, transparent);
        color: var(--card-foreground);
        background-color: color-mix(in oklch, var(--border) 16%, transparent);
      }
      .vp-hbtn--gold {
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        color: var(--info-ink);
        font-weight: 700;
        border-color: var(--vp-accent-border);
        box-shadow:
          0 0 8px var(--vp-accent-glow),
          inset 0 1px 0 color-mix(in oklch, var(--card) 8%, transparent);
      }
      .vp-hbtn--gold:hover {
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        box-shadow: 0 0 14px var(--vp-accent-glow);
      }
      .vp-hbtn--play {
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        color: var(--info-ink);
        font-weight: 700;
        border-color: var(--vp-accent-border);
        box-shadow: 0 0 8px var(--vp-accent-glow);
      }
      .vp-hbtn--play:hover {
        box-shadow: 0 0 16px var(--vp-accent-glow);
      }
      .vp-hbtn--stop {
        background-color: color-mix(
          in oklch,
          var(--destructive) 14%,
          transparent
        );
        color: var(--destructive-ink);
        border-color: color-mix(in oklch, var(--destructive) 28%, transparent);
      }
      .vp-hbtn--stop:hover {
        background-color: color-mix(
          in oklch,
          var(--destructive) 24%,
          transparent
        );
      }

      /* Difficulty badges */
      .diff-super-easy {
        background-color: var(--vp-diff-super-easy-bg);
        color: var(--success-ink);
        border: 1px solid color-mix(in oklch, var(--success) 25%, transparent);
      }
      .diff-easy {
        background-color: var(--vp-diff-easy-bg);
        color: var(--primary-ink);
        border: 1px solid color-mix(in oklch, var(--primary) 25%, transparent);
      }
      .diff-intermediate {
        background-color: var(--vp-diff-inter-bg);
        color: var(--accent-ink);
        border: 1px solid color-mix(in oklch, var(--accent) 30%, transparent);
      }
      .diff-expert {
        background-color: var(--vp-diff-expert-bg);
        color: var(--destructive-ink);
        border: 1px solid
          color-mix(in oklch, var(--destructive) 28%, transparent);
      }
      .diff-unknown {
        background-color: transparent;
        color: var(--muted-foreground);
        border: 1px solid var(--border);
      }

      /* ══ Song Bar — above notation ═══════════════════════════════════ */
      .vp-song-bar {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        padding: 0.55rem 1rem;
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border-bottom: 1px solid
          color-mix(in oklch, var(--border) 15%, transparent);
        box-shadow:
          inset 0 -1px 0
            color-mix(in oklch, var(--shadow-color) 40%, transparent),
          0 1px 0 color-mix(in oklch, var(--card) 4%, transparent);
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
          color-mix(in oklch, var(--info) 5%, transparent) 0%,
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
        width: 2.25rem;
        height: 2.25rem;
        border-radius: 50%;
        background: radial-gradient(
          ellipse at 40% 35%,
          var(--primary) 0%,
          var(--card) 100%
        );
        border: 2px solid var(--info);
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--info-ink);
        flex-shrink: 0;
        box-shadow:
          0 0 16px var(--vp-accent-glow),
          inset 0 1px 2px color-mix(in oklch, var(--primary) 15%, transparent);
        transition: all 0.2s ease;
      }
      .vp-song-bar-icon.playing {
        animation: musicBounce 0.6s ease-in-out infinite;
        box-shadow:
          0 0 24px var(--vp-accent-glow),
          inset 0 1px 2px color-mix(in oklch, var(--primary) 25%, transparent);
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
        font-size: 0.625rem;
        font-weight: 700;
        color: var(--info-ink);
        text-transform: uppercase;
        letter-spacing: 0.8px;
        opacity: 1;
        text-shadow: 0 0 4px
          color-mix(in oklch, var(--primary) 40%, transparent);
      }
      .vp-sb-title {
        font-size: 0.9375rem;
        font-weight: 700;
        color: var(--card-foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        letter-spacing: 0.1px;
      }
      .vp-sb-artist {
        font-size: 0.75rem;
        color: var(--muted-foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .vp-song-bar-badges {
        display: flex;
        align-items: center;
        gap: 0.3125rem;
        flex-shrink: 0;
      }
      .vp-song-bar-center {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.25rem;
        flex-shrink: 0;
        min-width: 7.5rem;
      }
      .vp-beat-counter {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--subtle-foreground);
        font-variant-numeric: tabular-nums;
        letter-spacing: 0.5px;
      }
      .vp-beat-sep {
        color: var(--muted-foreground);
        font-weight: 400;
        margin: 0 1px;
      }
      .vp-sb-progress-wrap {
        width: 100%;
      }
      .vp-sb-progress-track {
        width: 100%;
        height: 0.1875rem;
        background-color: var(--border);
        border-radius: 2px;
        overflow: hidden;
      }
      .vp-sb-progress-fill {
        height: 100%;
        background: linear-gradient(
          90deg,
          var(--info) 0%,
          color-mix(in oklch, var(--info) 84%, var(--shadow-color)) 100%
        );
        border-radius: 2px;
        transition: width 0.2s linear;
        box-shadow: 0 0 6px var(--vp-accent-glow);
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
        gap: 0.25rem;
        padding: 0.25rem 0.625rem;
        border-radius: var(--radius-sm);
        font-size: 0.6875rem;
        font-weight: 700;
        cursor: pointer;
        border: 1px solid transparent;
        background-color: transparent;
        color: var(--subtle-foreground);
        transition: all 0.12s;
        white-space: nowrap;
        height: 2rem;
      }
      .vp-sb-btn:active {
        transform: scale(0.93);
      }
      .vp-sb-btn--ghost {
        border-color: var(--vp-chrome-border);
        color: var(--subtle-foreground);
        background-color: var(--vp-chrome-dim);
        padding: 0.25rem 0.4375rem;
      }
      .vp-sb-btn--ghost:hover {
        border-color: color-mix(in oklch, var(--border) 40%, transparent);
        color: var(--card-foreground);
      }
      .vp-sb-btn--sm {
        padding: 0.3125rem 0.5rem;
      }
      .vp-sb-btn--lg {
        padding: 0.375rem 1rem;
      }
      .vp-sb-btn--play {
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        color: var(--info-ink);
        border-color: var(--vp-accent-border);
        box-shadow:
          0 0 10px var(--vp-accent-glow),
          inset 0 1px 0 color-mix(in oklch, var(--card) 8%, transparent);
      }
      .vp-sb-btn--play:hover {
        box-shadow: 0 0 18px var(--vp-accent-glow);
        border-color: var(--info-ink);
      }
      .vp-sb-btn--stop {
        background-color: color-mix(
          in oklch,
          var(--destructive) 14%,
          transparent
        );
        color: var(--destructive-ink);
        border-color: color-mix(in oklch, var(--destructive) 28%, transparent);
      }
      .vp-sb-btn--stop:hover {
        background-color: color-mix(
          in oklch,
          var(--destructive) 26%,
          transparent
        );
      }

      /* ══ Record button (header) ═════════════════════════════════════════ */
      .vp-hbtn--rec {
        border-color: color-mix(in oklch, var(--destructive) 35%, transparent);
        color: var(--destructive-ink);
        background-color: color-mix(
          in oklch,
          var(--destructive) 8%,
          transparent
        );
        font-variant-numeric: tabular-nums;
        gap: 0.375rem;
      }
      .vp-hbtn--rec:hover {
        background-color: color-mix(
          in oklch,
          var(--destructive) 16%,
          transparent
        );
        border-color: color-mix(in oklch, var(--destructive) 55%, transparent);
      }
      .vp-hbtn--rec--active {
        background-color: color-mix(
          in oklch,
          var(--destructive) 18%,
          transparent
        );
        border-color: color-mix(in oklch, var(--destructive) 60%, transparent);
        color: var(--destructive-ink);
        box-shadow: 0 0 10px
          color-mix(in oklch, var(--destructive) 25%, transparent);
      }
      .vp-rec-dot {
        display: inline-block;
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        background-color: var(--destructive);
        color: var(--destructive-foreground);
        flex-shrink: 0;
      }
      .vp-rec-dot--on {
        background-color: var(--destructive);
        color: var(--destructive-foreground);
        box-shadow: 0 0 6px var(--destructive);
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
        top: calc(100% + 0.25rem);
        right: 0;
        z-index: 400;
        width: 19.375rem;
        background: linear-gradient(
          160deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border: 1px solid
          color-mix(in oklch, var(--destructive) 25%, transparent);
        border-radius: 0.75rem;
        box-shadow:
          0 20px 60px color-mix(in oklch, var(--shadow-color) 70%, transparent),
          0 0 0 1px color-mix(in oklch, var(--card) 5%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 7%, transparent);
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
        border-bottom: 1px solid var(--border);
        background-color: var(--hover);
      }
      .vp-rec-panel-title {
        display: flex;
        align-items: center;
        gap: 0.4375rem;
        font-size: 0.75rem;
        font-weight: 700;
        color: var(--destructive-ink);
        letter-spacing: 0.5px;
        text-transform: uppercase;
      }

      /* Live notation scroll area */
      .vp-rec-notation {
        min-height: 4rem;
        max-height: 6.875rem;
        overflow-y: auto;
        overflow-x: hidden;
        margin: 0.6rem 1rem;
        padding: 0.6rem 0.75rem;
        background-color: var(--muted);
        color: var(--muted-foreground);
        border: 1px solid
          color-mix(in oklch, var(--destructive) 18%, transparent);
        border-radius: 0.5rem;
        display: flex;
        flex-wrap: wrap;
        gap: 0.25rem;
        align-content: flex-start;
        scroll-behavior: smooth;
      }
      .vp-rec-note {
        display: inline-flex;
        align-items: center;
        padding: 2px 0.4375rem;
        border-radius: 0.25rem;
        font-size: 0.6875rem;
        font-weight: 700;
        font-family: 'SF Mono', 'Fira Code', monospace;
        background-color: color-mix(
          in oklch,
          var(--destructive) 12%,
          transparent
        );
        border: 1px solid
          color-mix(in oklch, var(--destructive) 28%, transparent);
        color: var(--destructive-ink);
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
        font-size: 0.6875rem;
        color: var(--muted-foreground);
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
        gap: 0.4375rem;
        flex: 1;
        justify-content: center;
        padding: 0.55rem 0.75rem;
        border-radius: 0.5rem;
        font-size: 0.6875rem;
        font-weight: 700;
        cursor: pointer;
        border: 1.5px solid
          color-mix(in oklch, var(--destructive) 40%, transparent);
        background-color: color-mix(
          in oklch,
          var(--destructive) 8%,
          transparent
        );
        color: var(--destructive-ink);
        transition: all 0.13s;
        text-transform: uppercase;
        letter-spacing: 0.3px;
      }
      .vp-rec-again-btn:hover {
        background-color: color-mix(
          in oklch,
          var(--destructive) 16%,
          transparent
        );
        border-color: color-mix(in oklch, var(--destructive) 60%, transparent);
      }
      .vp-rec-btn-dot {
        display: inline-block;
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        background-color: var(--destructive);
        color: var(--destructive-foreground);
        box-shadow: 0 0 5px var(--destructive);
        flex-shrink: 0;
      }

      /* Replay pill — full width orange-bordered button */
      .vp-rec-replay-pill {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 0.5625rem;
        width: calc(100% - 2rem);
        margin: 0.75rem 1rem 0.5rem;
        padding: 0.7rem 1rem;
        border-radius: 1.5rem;
        font-size: 0.8125rem;
        font-weight: 800;
        letter-spacing: 1px;
        cursor: pointer;
        border: 1.5px solid color-mix(in oklch, var(--warning) 65%, transparent);
        background-color: transparent;
        color: var(--warning-ink);
        text-transform: uppercase;
        transition: all 0.15s;
        box-shadow: 0 0 12px
          color-mix(in oklch, var(--warning) 15%, transparent);
      }
      .vp-rec-replay-pill:hover {
        background-color: color-mix(in oklch, var(--warning) 10%, transparent);
        border-color: color-mix(in oklch, var(--warning) 90%, transparent);
        box-shadow: 0 0 20px
          color-mix(in oklch, var(--warning) 25%, transparent);
        color: var(--warning-ink);
      }

      /* Progress row */
      .vp-rec-playback {
        padding: 0 1rem 0.25rem;
      }
      .vp-rec-progress-wrap {
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
      }
      .vp-rec-progress-track {
        height: 0.25rem;
        background-color: var(--hover);
        border-radius: 0.1875rem;
        overflow: visible;
        position: relative;
        border: 1px solid var(--border);
      }
      .vp-rec-progress-fill {
        height: 100%;
        background: linear-gradient(
          90deg,
          var(--destructive) 0%,
          var(--warning) 100%
        );
        border-radius: 0.1875rem;
        transition: width 0.1s linear;
        position: relative;
      }
      .vp-rec-progress-thumb {
        position: absolute;
        right: -0.375rem;
        top: 50%;
        transform: translateY(-50%);
        width: 0.75rem;
        height: 0.75rem;
        border-radius: 50%;
        background: radial-gradient(
          ellipse at 38% 32%,
          var(--card) 0%,
          var(--accent) 35%,
          var(--accent) 100%
        );
        box-shadow:
          0 1px 4px color-mix(in oklch, var(--shadow-color) 60%, transparent),
          0 0 6px color-mix(in oklch, var(--warning) 40%, transparent);
      }
      .vp-rec-time-row {
        display: flex;
        justify-content: space-between;
        font-size: 0.625rem;
        font-weight: 600;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }

      /* Download button — full width, ghost style */
      .vp-rec-dl-btn {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        width: calc(100% - 2rem);
        margin: 0.5rem 1rem 0;
        justify-content: center;
        padding: 0.55rem 1rem;
        border-radius: 0.5rem;
        font-size: 0.75rem;
        font-weight: 700;
        cursor: pointer;
        background-color: var(--vp-chrome-dim);
        border: 1px solid var(--vp-chrome-border);
        color: var(--subtle-foreground);
        transition: all 0.13s;
        text-transform: uppercase;
        letter-spacing: 0.6px;
      }
      .vp-rec-dl-btn:hover {
        background-color: color-mix(in oklch, var(--border) 18%, transparent);
        color: var(--card-foreground);
      }
      .vp-rec-again-row {
        display: flex;
        justify-content: center;
        padding: 0.5rem 1rem 1rem;
      }
      .vp-rec-again-btn {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.4rem 1.1rem;
        border-radius: 1.25rem;
        font-size: 0.6875rem;
        font-weight: 700;
        cursor: pointer;
        border: 1px solid
          color-mix(in oklch, var(--destructive) 30%, transparent);
        background-color: transparent;
        color: color-mix(in oklch, var(--destructive-ink) 70%, transparent);
        transition: all 0.13s;
        letter-spacing: 0.3px;
      }
      .vp-rec-again-btn:hover {
        background-color: color-mix(
          in oklch,
          var(--destructive) 10%,
          transparent
        );
        color: var(--destructive-ink);
        border-color: color-mix(in oklch, var(--destructive) 55%, transparent);
      }

      /* ══ Disabled header button ═════════════════════════════════════════ */
      .vp-hbtn--disabled {
        opacity: 0.35;
        cursor: not-allowed;
        pointer-events: none;
      }
      .vp-hbtn--disabled .vp-rec-dot {
        background-color: var(--muted);
        color: var(--muted-foreground);
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
          color-mix(in oklch, var(--destructive) 14%, transparent) 0%,
          color-mix(in oklch, var(--card) 0%, transparent) 60%
        );
        border-bottom: 1px solid
          color-mix(in oklch, var(--destructive) 20%, transparent);
        flex-shrink: 0;
        overflow: hidden;
      }
      .vp-rec-ticker-dot {
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        background-color: var(--destructive);
        color: var(--destructive-foreground);
        box-shadow: 0 0 8px var(--destructive);
        flex-shrink: 0;
        animation: vp-rec-pulse 1s ease-in-out infinite;
      }
      .vp-rec-ticker-label {
        font-size: 0.625rem;
        font-weight: 800;
        color: var(--destructive-ink);
        letter-spacing: 1px;
        text-transform: uppercase;
        font-variant-numeric: tabular-nums;
        flex-shrink: 0;
        min-width: 3.5rem;
      }
      .vp-rec-ticker-notes {
        display: flex;
        align-items: center;
        gap: 0.25rem;
        overflow: hidden;
        flex: 1;
        /* show only the tail — newest notes on right */
        flex-direction: row;
        justify-content: flex-end;
        mask-image: linear-gradient(90deg, transparent 0%, var(--card) 18%);
        -webkit-mask-image: linear-gradient(
          90deg,
          transparent 0%,
          var(--card) 18%
        );
      }
      .vp-rec-ticker-note {
        display: inline-flex;
        align-items: center;
        padding: 1px 0.375rem;
        border-radius: 0.1875rem;
        font-size: 0.625rem;
        font-weight: 700;
        font-family: 'SF Mono', 'Fira Code', monospace;
        background-color: color-mix(
          in oklch,
          var(--destructive) 14%,
          transparent
        );
        border: 1px solid
          color-mix(in oklch, var(--destructive) 30%, transparent);
        color: var(--destructive-ink);
        flex-shrink: 0;
        animation: vp-note-pop 0.12s cubic-bezier(0.22, 0.68, 0.36, 1);
      }
      .vp-rec-ticker-hint {
        font-size: 0.625rem;
        color: var(--muted-foreground);
        font-style: italic;
      }

      /* ══ Controls Row — recessed gaming panel ══════════════════════════ */
      .vp-controls {
        display: flex;
        align-items: center;
        gap: 0;
        padding: 0 1rem;
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border-bottom: 1px solid
          color-mix(in oklch, var(--border) 14%, transparent);
        box-shadow:
          inset 0 2px 8px
            color-mix(in oklch, var(--shadow-color) 60%, transparent),
          inset 0 -1px 0 color-mix(in oklch, var(--card) 4%, transparent);
        flex-shrink: 0;
        overflow-x: auto;
        height: 5rem;
      }
      .vp-controls::-webkit-scrollbar {
        display: none;
      }
      .vp-cg {
        display: flex;
        flex-direction: column;
        gap: 0.375rem;
        padding: 0 1rem;
        flex-shrink: 0;
      }
      .vp-clabel {
        font-size: 0.6875rem;
        font-weight: 700;
        color: var(--muted-foreground);
        text-transform: uppercase;
        letter-spacing: 0.8px;
        white-space: nowrap;
      }
      .vp-cval {
        color: var(--card-foreground);
        text-transform: none;
        font-weight: 800;
        letter-spacing: 0;
        font-size: 0.8125rem;
      }
      .vp-vsep {
        width: 1px;
        height: 2.75rem;
        background: linear-gradient(
          180deg,
          transparent 0%,
          color-mix(in oklch, var(--border) 20%, transparent) 30%,
          color-mix(in oklch, var(--border) 20%, transparent) 70%,
          transparent 100%
        );
        flex-shrink: 0;
        margin: 0 0.2rem;
      }
      /* ── Preset button groups (Sustain / Reverb / Velocity / Sound) ── */
      .vp-preset-btns {
        display: flex;
        gap: 0.1875rem;
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
        padding: 0.25rem 0.625rem;
        border-radius: var(--radius-sm);
        font-size: 0.6875rem;
        font-weight: 700;
        cursor: pointer;
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border: 1px solid var(--vp-chrome-border);
        color: var(--subtle-foreground);
        white-space: nowrap;
        transition: all 0.12s;
        box-shadow: inset 0 1px 0
          color-mix(in oklch, var(--card) 6%, transparent);
        letter-spacing: 0.3px;
      }
      .vp-preset-btn:hover {
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        color: var(--card-foreground);
      }
      .vp-preset-btn--active {
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border-color: var(--vp-accent-border);
        color: var(--info-ink);
        box-shadow:
          0 0 6px var(--vp-accent-glow),
          inset 0 1px 0 color-mix(in oklch, var(--card) 8%, transparent);
      }
      .vp-cval--accent {
        color: var(--info-ink);
        font-weight: 700;
      }

      /* keep old class for any remaining references */
      .vp-instrument-btns {
        display: flex;
        gap: 0.1875rem;
      }
      .vp-inst-btn {
        display: none;
      }
      /* Chrome slider: recessed track + chrome knob thumb */
      .vp-slider {
        width: 8.75rem;
        cursor: pointer;
        height: 0.3125rem;
        -webkit-appearance: none;
        appearance: none;
        background: linear-gradient(
          180deg,
          color-mix(in oklch, var(--card) 72%, var(--shadow-color)) 0%,
          color-mix(in oklch, var(--card) 88%, var(--shadow-color)) 50%,
          var(--card) 100%
        );
        border-radius: 0.1875rem;
        border: 1px solid color-mix(in oklch, var(--border) 16%, transparent);
        box-shadow:
          inset 0 1px 4px
            color-mix(in oklch, var(--shadow-color) 80%, transparent),
          inset 0 -1px 0 color-mix(in oklch, var(--card) 4%, transparent);
        outline: none;
      }
      .vp-slider::-webkit-slider-thumb {
        -webkit-appearance: none;
        width: 1.375rem;
        height: 1.375rem;
        border-radius: 50%;
        background: radial-gradient(
          ellipse at 38% 30%,
          var(--inset) 0%,
          var(--border) 28%,
          var(--muted) 65%,
          var(--card) 100%
        );
        border: 1px solid var(--border);
        box-shadow:
          0 2px 6px color-mix(in oklch, var(--shadow-color) 75%, transparent),
          0 0 0 1px color-mix(in oklch, var(--shadow-color) 40%, transparent),
          inset 0 1px 1px color-mix(in oklch, var(--card) 40%, transparent),
          inset 0 -1px 1px
            color-mix(in oklch, var(--shadow-color) 30%, transparent);
        cursor: ew-resize;
        transition: box-shadow 0.1s;
      }
      .vp-slider::-webkit-slider-thumb:hover {
        box-shadow:
          0 2px 8px color-mix(in oklch, var(--shadow-color) 85%, transparent),
          0 0 0 2px var(--vp-accent-border),
          inset 0 1px 1px color-mix(in oklch, var(--card) 45%, transparent);
      }
      .vp-slider::-moz-range-thumb {
        width: 1.375rem;
        height: 1.375rem;
        border-radius: 50%;
        background: radial-gradient(
          ellipse at 38% 30%,
          var(--inset) 0%,
          var(--border) 28%,
          var(--muted) 65%,
          var(--card) 100%
        );
        border: 1px solid var(--border);
        box-shadow:
          0 2px 6px color-mix(in oklch, var(--shadow-color) 75%, transparent),
          inset 0 1px 1px color-mix(in oklch, var(--card) 40%, transparent);
        cursor: ew-resize;
      }
      .vp-slider--bpm {
        width: 6.25rem;
      }
      .vp-inline-row {
        display: flex;
        align-items: center;
        gap: 0.3125rem;
      }
      .vp-cg--reset {
        margin-left: auto;
        padding-right: 0;
      }
      .vp-metro-btn {
        padding: 0.3125rem 0.625rem;
        border-radius: var(--radius-sm);
        font-size: 0.875rem;
        cursor: pointer;
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border: 1px solid var(--vp-chrome-border);
        color: var(--subtle-foreground);
        transition: all 0.12s;
        line-height: 1.2;
        box-shadow: inset 0 1px 0
          color-mix(in oklch, var(--card) 6%, transparent);
      }
      .vp-metro-btn--on {
        background-color: color-mix(in oklch, var(--info) 8%, transparent);
        border-color: var(--vp-accent-border);
        color: var(--info-ink);
        box-shadow: 0 0 6px var(--vp-accent-glow);
      }
      .vp-transpose-val {
        font-size: 0.875rem;
        font-weight: 700;
        color: var(--card-foreground);
        min-width: 1.5rem;
        text-align: center;
      }
      .vp-step-btn {
        padding: 0.3125rem 0.6875rem;
        border-radius: var(--radius-sm);
        font-size: 0.75rem;
        font-weight: 700;
        cursor: pointer;
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border: 1px solid var(--vp-chrome-border);
        color: var(--subtle-foreground);
        transition: all 0.12s;
        box-shadow: inset 0 1px 0
          color-mix(in oklch, var(--card) 6%, transparent);
      }
      .vp-step-btn:hover {
        color: var(--card-foreground);
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
      }

      /* Reset — large silver gaming button */
      .vp-reset-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 0.4375rem;
        padding: 0.625rem 1.375rem;
        border-radius: 0.5rem;
        font-size: 0.875rem;
        font-weight: 800;
        letter-spacing: 0.5px;
        cursor: pointer;
        border: 1px solid color-mix(in oklch, var(--border) 30%, transparent);
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 90%, var(--shadow-color)) 40%,
          color-mix(in oklch, var(--card) 80%, var(--shadow-color)) 70%,
          color-mix(in oklch, var(--card) 68%, var(--shadow-color)) 100%
        );
        color: var(--card-foreground);
        text-transform: uppercase;
        transition: all 0.14s;
        box-shadow:
          0 0 0 1px color-mix(in oklch, var(--card) 6%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 20%, transparent),
          inset 0 -1px 0
            color-mix(in oklch, var(--shadow-color) 40%, transparent),
          0 4px 14px color-mix(in oklch, var(--shadow-color) 60%, transparent);
        white-space: nowrap;
      }
      .vp-reset-btn:hover {
        background: linear-gradient(
          180deg,
          var(--muted) 0%,
          var(--card) 30%,
          var(--card) 70%,
          var(--card) 100%
        );
        border-color: color-mix(in oklch, var(--border) 48%, transparent);
        box-shadow:
          0 0 0 1px color-mix(in oklch, var(--card) 9%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 28%, transparent),
          0 0 12px color-mix(in oklch, var(--primary) 18%, transparent),
          0 4px 18px color-mix(in oklch, var(--shadow-color) 65%, transparent);
        color: var(--card-foreground);
      }
      .vp-reset-btn:active {
        transform: scale(0.96);
        box-shadow:
          inset 0 2px 6px
            color-mix(in oklch, var(--shadow-color) 50%, transparent),
          0 1px 4px color-mix(in oklch, var(--shadow-color) 40%, transparent);
      }

      /* ══ Sheet Music (parchment, centred, only when song loaded) ═════ */
      .vp-sheet-outer {
        flex-shrink: 0;
        background-color: var(--card);
        color: var(--card-foreground);
        display: flex;
        justify-content: center;
        padding: 0.6rem 1rem;
        border-bottom: 1px solid var(--border);
      }
      .vp-sheet-wrap {
        width: 100%;
        max-width: 80%;
        background-color: var(--inset);
        border-radius: 0.375rem;
        overflow: hidden;
        box-shadow: 0 2px 12px
          color-mix(in oklch, var(--shadow-color) 35%, transparent);
        max-height: 10rem;
        display: flex;
        flex-direction: column;
      }
      .vp-progress-track {
        height: 2px;
        background-color: var(--hover);
        flex-shrink: 0;
      }
      .vp-progress-fill {
        height: 100%;
        background-color: var(--warning);
        transition: width 0.15s linear;
      }
      .vp-sheet {
        flex: 1;
        overflow-y: auto;
        padding: 0.45rem 0.875rem;
        display: flex;
        flex-direction: column;
        gap: 0.1875rem;
      }
      .vp-row {
        display: flex;
        flex-wrap: wrap;
        gap: 1px 0.1875rem;
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
        font-size: 0.75rem;
        padding: 1px 0.25rem;
        min-width: 1rem;
        transition: background 0.08s;
        line-height: 1.3;
      }
      .vp-token--note {
        color: var(--foreground);
      }
      .vp-token--chord {
        color: var(--warning-ink);
        background-color: color-mix(in oklch, var(--warning) 7%, transparent);
        padding: 1px 0.3125rem;
      }
      .vp-token--rest {
        color: var(--muted-foreground);
        font-size: 0.625rem;
      }
      .vp-token--current {
        background-color: var(--info) !important;
        color: var(--info-foreground) !important;
        font-weight: 900;
        border-radius: 0.1875rem;
        box-shadow: 0 1px 8px color-mix(in oklch, var(--info) 55%, transparent);
        transform: scale(1.1);
      }
      .vp-token--played {
        color: var(--subtle-foreground);
      }

      /* ══ Fallboard — chrome status rail ═════════════════════════════════ */
      .vp-fallboard {
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 90%, var(--shadow-color)) 40%,
          color-mix(in oklch, var(--card) 80%, var(--shadow-color)) 70%,
          color-mix(in oklch, var(--card) 68%, var(--shadow-color)) 100%
        );
        border-top: 1px solid
          color-mix(in oklch, var(--border) 20%, transparent);
        border-bottom: 2px solid var(--border-strong);
        box-shadow:
          inset 0 1px 0 color-mix(in oklch, var(--card) 8%, transparent),
          inset 0 -1px 0
            color-mix(in oklch, var(--shadow-color) 30%, transparent);
        padding: 0.5rem 1.25rem;
        display: flex;
        align-items: center;
        justify-content: space-between;
        flex-shrink: 0;
        gap: 1rem;
        min-height: 2.625rem;
      }

      /* Left — brand */
      .vp-fallboard-left {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        flex-shrink: 0;
      }
      .vp-fallboard-dot {
        display: inline-block;
        width: 0.3125rem;
        height: 0.3125rem;
        border-radius: 50%;
        background: radial-gradient(
          circle at 40% 35%,
          var(--inset),
          var(--muted-foreground)
        );
        box-shadow: 0 0 4px color-mix(in oklch, var(--primary) 35%, transparent);
      }
      .vp-fallboard-brand {
        font-size: 0.6875rem;
        font-weight: 800;
        color: var(--card-foreground);
        letter-spacing: 0.25rem;
        text-transform: uppercase;
        text-shadow:
          0 1px 0 color-mix(in oklch, var(--shadow-color) 70%, transparent),
          0 0 12px color-mix(in oklch, var(--info) 20%, transparent);
      }

      /* Center — status chips */
      .vp-fallboard-center {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        flex: 1;
        justify-content: center;
      }
      .vp-fb-chip {
        display: inline-flex;
        align-items: center;
        gap: 0.3125rem;
        padding: 0.1875rem 0.625rem;
        border-radius: 1.25rem;
        font-size: 0.6875rem;
        font-weight: 600;
        background-color: var(--hover);
        border: 1px solid var(--border);
        color: var(--muted-foreground);
        white-space: nowrap;
        transition: all 0.2s;
      }
      .vp-fb-chip--on {
        background-color: color-mix(in oklch, var(--info) 10%, transparent);
        border-color: var(--vp-accent-border);
        color: var(--info-ink);
        box-shadow: 0 0 8px var(--vp-accent-glow);
      }
      .vp-fb-chip--accent {
        background-color: color-mix(in oklch, var(--primary) 8%, transparent);
        border-color: var(--vp-chrome-border);
        color: var(--card-foreground);
      }
      .vp-fb-chip-dot {
        width: 0.375rem;
        height: 0.375rem;
        border-radius: 50%;
        background-color: var(--muted);
        color: var(--muted-foreground);
        transition: all 0.2s;
      }
      .vp-fb-chip--on .vp-fb-chip-dot {
        background-color: var(--info);
        box-shadow: 0 0 6px var(--info);
      }
      .vp-fb-divider {
        width: 1px;
        height: 1rem;
        background-color: var(--border);
        flex-shrink: 0;
      }
      .vp-fb-label {
        font-size: 0.625rem;
        color: var(--muted-foreground);
        white-space: nowrap;
      }

      /* Right — key count */
      .vp-fallboard-right {
        flex-shrink: 0;
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }

      /* Two-hand feature highlight chip */
      .vp-fb-twohand {
        display: inline-flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.25rem 0.75rem;
        border-radius: 1.25rem;
        font-size: 0.625rem;
        font-weight: 800;
        letter-spacing: 0.6px;
        text-transform: uppercase;
        color: var(--info-ink);
        background: linear-gradient(
          90deg,
          color-mix(in oklch, var(--info) 18%, transparent) 0%,
          color-mix(in oklch, var(--info) 6%, transparent) 100%
        );
        border: 1px solid var(--vp-accent-border);
        box-shadow:
          0 0 10px var(--vp-accent-glow),
          inset 0 1px 0 color-mix(in oklch, var(--card) 8%, transparent);
        position: relative;
        white-space: nowrap;
      }
      .vp-fb-twohand svg {
        color: var(--info-ink);
        filter: drop-shadow(0 0 4px var(--vp-accent-glow));
      }
      .vp-fb-twohand-pulse {
        display: inline-block;
        width: 0.375rem;
        height: 0.375rem;
        border-radius: 50%;
        background-color: var(--info);
        box-shadow: 0 0 6px var(--info);
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
        gap: 0.3125rem;
        padding: 0.25rem 0.75rem;
        border-radius: 1.25rem;
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.5px;
        text-transform: uppercase;
        color: var(--card-foreground);
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border: 1px solid var(--vp-chrome-border);
        cursor: pointer;
        transition: all 0.14s;
        box-shadow: inset 0 1px 0
          color-mix(in oklch, var(--card) 8%, transparent);
        white-space: nowrap;
      }
      .vp-fb-faq-btn:hover {
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border-color: var(--vp-accent-border);
        color: var(--info-ink);
        box-shadow: 0 0 10px var(--vp-accent-glow);
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
        background-color: var(--tooltip);
        color: var(--tooltip-foreground);
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
        border-bottom: 1px solid
          color-mix(in oklch, var(--border) 12%, transparent);
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        flex-shrink: 0;
        box-shadow:
          0 1px 0 color-mix(in oklch, var(--info) 8%, transparent),
          0 4px 20px color-mix(in oklch, var(--shadow-color) 40%, transparent);
      }
      .vp-faq-hdr-title {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        font-size: 0.9375rem;
        font-weight: 700;
        color: var(--info-ink);
        letter-spacing: 0.3px;
      }
      .vp-faq-hdr-title svg {
        color: var(--info-ink);
        filter: drop-shadow(0 0 6px var(--vp-accent-glow));
      }
      .vp-faq-body {
        flex: 1;
        overflow-y: auto;
        padding: 1.25rem 1.5rem 2rem;
        max-width: 51.25rem;
        margin: 0 auto;
        width: 100%;
        box-sizing: border-box;
      }
      .vp-faq-section {
        padding: 1rem 1.1rem;
        margin-bottom: 0.85rem;
        background-color: var(--hover);
        border: 1px solid var(--border);
        border-radius: 0.5rem;
      }
      .vp-faq-section--highlight {
        background: linear-gradient(
          135deg,
          color-mix(in oklch, var(--info) 7%, transparent) 0%,
          color-mix(in oklch, var(--info) 2%, transparent) 100%
        );
        border: 1px solid var(--vp-accent-border);
        box-shadow:
          0 0 18px color-mix(in oklch, var(--info) 8%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 5%, transparent);
      }
      .vp-faq-q {
        display: flex;
        align-items: center;
        gap: 0.6rem;
        margin: 0 0 0.65rem;
        font-size: 0.875rem;
        font-weight: 700;
        color: var(--card-foreground);
        letter-spacing: 0.2px;
      }
      .vp-faq-q-num {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 1.375rem;
        height: 1.375rem;
        border-radius: 50%;
        font-size: 0.6875rem;
        font-weight: 800;
        background-color: var(--vp-chrome-dim);
        border: 1px solid var(--vp-chrome-border);
        color: var(--subtle-foreground);
        flex-shrink: 0;
      }
      .vp-faq-q-num--accent {
        background-color: var(--vp-accent-dim);
        border-color: var(--vp-accent-border);
        color: var(--info-ink);
        box-shadow: 0 0 8px var(--vp-accent-glow);
      }
      .vp-faq-badge {
        margin-left: auto;
        padding: 2px 0.5rem;
        font-size: 0.625rem;
        font-weight: 800;
        letter-spacing: 0.6px;
        color: var(--success-ink);
        background-color: color-mix(in oklch, var(--success) 12%, transparent);
        border: 1px solid color-mix(in oklch, var(--success) 35%, transparent);
        border-radius: 0.625rem;
      }
      .vp-faq-a {
        margin: 0 0 0.55rem;
        font-size: 0.7812rem;
        line-height: 1.6;
        color: var(--subtle-foreground);
      }
      .vp-faq-a strong {
        color: var(--card-foreground);
        font-weight: 700;
      }
      .vp-faq-a em {
        color: var(--info-ink);
        font-style: normal;
        font-weight: 600;
      }
      .vp-faq-a--note {
        margin-top: 0.7rem;
        padding: 0.55rem 0.75rem;
        background-color: color-mix(in oklch, var(--accent) 8%, transparent);
        border-left: 2px solid var(--accent);
        border-radius: 0 0.25rem 0.25rem 0;
        font-size: 0.75rem;
        color: var(--accent-ink);
      }
      .vp-faq-a a,
      .vp-faq-footer a {
        color: var(--info-ink);
        text-decoration: underline;
      }
      .vp-faq-a a:hover,
      .vp-faq-footer a:hover {
        color: var(--info-ink);
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
        font-size: 0.7812rem;
        color: var(--subtle-foreground);
        line-height: 1.5;
      }
      .vp-faq-symbols li > span {
        flex: 1;
      }
      .vp-faq-tok {
        flex-shrink: 0;
        display: inline-block;
        padding: 2px 0.5rem;
        min-width: 3.5rem;
        text-align: center;
        font-family: 'SF Mono', 'Fira Code', monospace;
        font-size: 0.7188rem;
        font-weight: 700;
        background-color: color-mix(in oklch, var(--info) 8%, transparent);
        border: 1px solid var(--vp-accent-border);
        border-radius: 0.25rem;
        color: var(--info-ink);
      }
      .vp-faq-handmap {
        margin: 0.65rem 0;
        padding: 0.75rem;
        background-color: var(--muted);
        color: var(--muted-foreground);
        border: 1px solid var(--border);
        border-radius: 0.375rem;
        display: grid;
        gap: 0.55rem;
      }
      .vp-faq-handmap-row {
        display: flex;
        align-items: center;
        gap: 0.65rem;
        font-size: 0.7188rem;
        color: var(--subtle-foreground);
      }
      .vp-faq-hand {
        flex-shrink: 0;
        padding: 0.1875rem 0.5rem;
        border-radius: 0.25rem;
        font-size: 0.625rem;
        font-weight: 800;
        letter-spacing: 0.4px;
        min-width: 6.875rem;
        text-align: center;
      }
      .vp-faq-hand--left {
        background-color: color-mix(in oklch, var(--primary) 14%, transparent);
        color: var(--primary-ink);
        border: 1px solid color-mix(in oklch, var(--primary) 30%, transparent);
      }
      .vp-faq-hand--mid {
        background-color: color-mix(in oklch, var(--accent) 14%, transparent);
        color: var(--accent-ink);
        border: 1px solid color-mix(in oklch, var(--accent) 30%, transparent);
      }
      .vp-faq-hand--right {
        background-color: color-mix(in oklch, var(--success) 14%, transparent);
        color: var(--success-ink);
        border: 1px solid color-mix(in oklch, var(--success) 30%, transparent);
      }
      .vp-faq-hand-keys code {
        font-family: 'SF Mono', 'Fira Code', monospace;
        font-size: 0.6875rem;
        color: var(--card-foreground);
        background-color: var(--hover);
        padding: 1px 0.3125rem;
        border-radius: 0.1875rem;
      }
      .vp-faq-example {
        margin: 0.55rem 0 0;
        padding: 0.75rem 0.9rem;
        background-color: var(--inset);
        color: var(--foreground);
        border-radius: 0.3125rem;
        font-family: 'SF Mono', 'Fira Code', monospace;
        font-size: 0.7812rem;
        font-weight: 700;
        line-height: 1.7;
        white-space: pre-wrap;
        box-shadow: 0 2px 10px
          color-mix(in oklch, var(--shadow-color) 40%, transparent);
      }
      .vp-faq-footer {
        padding: 0.85rem 1rem;
        border-top: 1px solid var(--border);
        background-color: var(--hover);
        text-align: center;
        font-size: 0.7188rem;
        color: var(--muted-foreground);
        flex-shrink: 0;
      }

      .vp-fallboard-keys {
        display: inline-flex;
        align-items: center;
        gap: 0.3125rem;
        font-size: 0.6875rem;
        color: var(--subtle-foreground);
        font-weight: 600;
        padding: 0.1875rem 0.625rem;
        border: 1px solid var(--vp-chrome-border);
        border-radius: 1.25rem;
        background-color: var(--vp-chrome-dim);
      }
      .vp-sustain-state {
        color: var(--subtle-foreground);
        font-size: 0.625rem;
      }
      .vp-transpose-accent {
        color: var(--info-ink);
      }
      .vp-kbd {
        display: inline-flex;
        align-items: center;
        padding: 2px 0.4375rem;
        background: linear-gradient(
          180deg,
          var(--card) 0%,
          color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
        );
        border: 1px solid color-mix(in oklch, var(--border) 28%, transparent);
        border-bottom-width: 2px;
        border-radius: 0.25rem;
        font-family: monospace;
        font-size: 0.625rem;
        font-weight: 700;
        color: var(--card-foreground);
        box-shadow:
          0 2px 0 color-mix(in oklch, var(--shadow-color) 40%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 10%, transparent);
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
          var(--card) 0%,
          color-mix(in oklch, var(--card) 88%, var(--shadow-color)) 50%,
          color-mix(in oklch, var(--card) 74%, var(--shadow-color)) 100%
        );
        display: flex;
        align-items: flex-end;
        padding: 0 0 1rem;
        overflow-x: auto;
        box-shadow:
          inset 0 6px 24px
            color-mix(in oklch, var(--shadow-color) 80%, transparent),
          inset 0 2px 0 color-mix(in oklch, var(--card) 4%, transparent);
      }
      .vp-keyboard {
        display: flex;
        align-items: flex-end;
        position: relative;
        height: 15rem;
        gap: 2px;
        flex-shrink: 0;
      }
      .vp-key--white {
        position: relative;
        flex: 0 0 2.375rem;
        height: 100%;
        background: linear-gradient(
          to bottom,
          var(--tooltip-foreground) 0%,
          var(--tooltip-foreground) 65%,
          color-mix(in oklch, var(--tooltip-foreground) 92%, var(--tooltip))
            100%
        );
        border: 1px solid var(--border);
        border-top: none;
        border-radius: 0 0 0.5rem 0.5rem;
        cursor: pointer;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-end;
        padding-bottom: 0.625rem;
        z-index: 1;
        box-shadow:
          2px 4px 16px color-mix(in oklch, var(--shadow-color) 55%, transparent),
          inset 0 1px 0
            color-mix(in oklch, var(--tooltip-foreground) 95%, transparent),
          inset -1px 0 0
            color-mix(in oklch, var(--shadow-color) 6%, transparent);
        transition:
          background 0.06s,
          box-shadow 0.06s;
        user-select: none;
      }
      .vp-key--white:hover {
        background: linear-gradient(
          to bottom,
          var(--card) 0%,
          var(--card) 65%,
          var(--inset) 100%
        );
      }
      .vp-key--white.vp-key--active {
        background: linear-gradient(
          to bottom,
          var(--primary) 0%,
          color-mix(in oklch, var(--primary) 88%, var(--shadow-color)) 50%,
          color-mix(in oklch, var(--primary) 74%, var(--shadow-color)) 100%
        );
        box-shadow:
          1px 1px 4px color-mix(in oklch, var(--shadow-color) 45%, transparent),
          0 0 14px color-mix(in oklch, var(--info) 28%, transparent),
          inset 0 -1px 0
            color-mix(in oklch, var(--shadow-color) 18%, transparent),
          inset 0 1px 0
            color-mix(in oklch, var(--tooltip-foreground) 40%, transparent);
      }
      .vp-key--black {
        position: absolute;
        top: 0;
        width: 1.625rem;
        height: 62%;
        background: linear-gradient(
          to bottom,
          var(--tooltip) 0%,
          color-mix(in oklch, var(--tooltip) 84%, var(--shadow-color)) 100%
        );
        border: 1px solid var(--border-strong);
        border-top: none;
        border-radius: 0 0 0.375rem 0.375rem;
        cursor: pointer;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: flex-end;
        padding-bottom: 0.375rem;
        z-index: 2;
        box-shadow:
          3px 7px 16px color-mix(in oklch, var(--shadow-color) 85%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--card) 8%, transparent),
          inset 1px 0 0 color-mix(in oklch, var(--card) 3%, transparent);
        transition:
          background 0.06s,
          box-shadow 0.06s;
        user-select: none;
      }
      .vp-key--black:hover {
        background: linear-gradient(
          to bottom,
          var(--tooltip) 0%,
          color-mix(in oklch, var(--tooltip) 84%, var(--shadow-color)) 100%
        );
      }
      .vp-key--black.vp-key--active {
        background: linear-gradient(
          to bottom,
          var(--primary) 0%,
          var(--tooltip) 65%,
          var(--tooltip) 100%
        );
        box-shadow:
          1px 2px 6px color-mix(in oklch, var(--shadow-color) 80%, transparent),
          0 0 12px color-mix(in oklch, var(--info) 30%, transparent),
          inset 0 -1px 0
            color-mix(in oklch, var(--shadow-color) 50%, transparent),
          inset 0 1px 0 color-mix(in oklch, var(--info) 15%, transparent);
      }
      .vp-key-label {
        font-size: 0.625rem;
        font-weight: 700;
        font-family: monospace;
        line-height: 1;
        pointer-events: none;
        user-select: none;
      }
      .vp-key--white .vp-key-label {
        color: color-mix(in oklch, var(--tooltip) 40%, transparent);
      }
      .vp-key--white.vp-key--active .vp-key-label {
        color: color-mix(in oklch, var(--tooltip) 70%, transparent);
      }
      .vp-key--black .vp-key-label {
        color: color-mix(in oklch, var(--tooltip-foreground) 60%, transparent);
        font-size: 0.5625rem;
      }
      .vp-key--black.vp-key--active .vp-key-label {
        color: color-mix(in oklch, var(--info-ink) 85%, transparent);
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
          --vp-accent-dim: color-mix(in oklch, var(--info) 14%, transparent);
          --vp-accent-border: color-mix(in oklch, var(--info) 32%, transparent);
          --vp-accent-glow: color-mix(in oklch, var(--info) 20%, transparent);
          --vp-led-glow: color-mix(in oklch, var(--success) 35%, transparent);
          /* chrome bezel shadow */
          --vp-bezel:
            0 1px 0 color-mix(in oklch, var(--inset) 25%, transparent) inset,
            0 -1px 0 var(--overlay) inset,
            1px 0 0 color-mix(in oklch, var(--inset) 10%, transparent) inset,
            -1px 0 0 var(--muted) inset;

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
            transparent 0.1875rem,
            color-mix(in oklch, var(--foreground) 7%, transparent) 0.1875rem,
            color-mix(in oklch, var(--foreground) 7%, transparent) 0.25rem
          );
          pointer-events: none;
          z-index: 0;
        }

        /* ── LED indicator ── */
        .led {
          display: inline-block;
          width: 0.3125rem;
          height: 0.3125rem;
          border-radius: 50%;
          background-color: var(--muted);
          color: var(--muted-foreground);
          box-shadow: none;
        }
        .led--on {
          background-color: var(--success);
          color: var(--success-foreground);
          box-shadow:
            0 0 6px var(--vp-led-glow),
            0 0 2px var(--success);
        }
        .led--pulse {
          background-color: var(--info);
          box-shadow:
            0 0 6px var(--vp-accent-glow),
            0 0 2px var(--info);
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
            gap: 0.5rem;
            background-color: var(--card);
            color: var(--card-foreground);
            padding: 0.625rem 0.5rem;
          }
        }

        .badge-bezel {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.375rem;
          padding: 0.5rem 0.625rem 0.375rem;
          background: linear-gradient(
            180deg,
            var(--tooltip) 0%,
            var(--card) 100%
          );
          border-radius: 0.375rem;
          box-shadow:
            var(--vp-bezel),
            0 2px 8px color-mix(in oklch, var(--shadow-color) 50%, transparent);
          border: 1px solid var(--border);
        }

        .badge-keys {
          display: flex;
          align-items: flex-end;
          gap: 1px;
          height: 1.25rem;
        }

        .bk {
          display: block;
          border-radius: 0 0 2px 2px;
          flex-shrink: 0;
        }
        .bk-w {
          width: 0.375rem;
          height: 1.25rem;
          background: linear-gradient(
            180deg,
            var(--inset) 0%,
            var(--border) 100%
          );
          border: 1px solid var(--border);
        }
        .bk-b {
          width: 0.25rem;
          height: 0.8125rem;
          background: linear-gradient(
            180deg,
            var(--tooltip) 0%,
            color-mix(in oklch, var(--tooltip) 84%, var(--shadow-color)) 100%
          );
          margin: 0 -2px;
          z-index: 1;
          position: relative;
          border-radius: 0 0 2px 2px;
          border: 1px solid var(--border);
        }

        .badge-led-row {
          display: flex;
          gap: 0.25rem;
          align-items: center;
        }

        .badge-label {
          font-size: 0.5625rem;
          font-weight: 800;
          color: var(--info-ink);
          letter-spacing: 0.12em;
          text-transform: uppercase;
        }

        /* ══ STRIP >150 × <170 ══ */
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            position: relative;
            align-items: center;
            gap: 0.625rem;
            padding: 0 0.875rem;
            background-color: var(--card);
            color: var(--card-foreground);
            border-left: 3px solid var(--info);
            box-shadow: inset 0 0 40px
              color-mix(in oklch, var(--info) 4%, transparent);
          }
        }

        .strip-left {
          flex-shrink: 0;
          position: relative;
          z-index: 1;
        }

        .strip-icon {
          width: 1.75rem;
          height: 1.75rem;
          border-radius: 50%;
          background-color: var(--vp-accent-dim);
          border: 1px solid var(--vp-accent-border);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--info-ink);
          box-shadow: 0 0 10px var(--vp-accent-glow);
        }

        .strip-title {
          position: relative;
          z-index: 1;
          flex: 1;
          font-size: 0.8125rem;
          font-weight: 800;
          color: var(--card-foreground);
          letter-spacing: 0.03em;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .strip-chips {
          position: relative;
          z-index: 1;
          display: flex;
          gap: 0.25rem;
          flex-shrink: 0;
        }

        .strip-chip {
          font-size: 0.5625rem;
          font-weight: 700;
          color: var(--primary-foreground);
          background-color: var(--primary);
          border: 1px solid var(--border);
          border-radius: 0.1875rem;
          padding: 2px 0.3125rem;
          white-space: nowrap;
          box-shadow: var(--vp-bezel);
        }

        .strip-chip--accent {
          color: var(--info-ink);
          background-color: var(--vp-accent-dim);
          border-color: var(--vp-accent-border);
          box-shadow: 0 0 6px var(--vp-accent-glow);
        }

        /* ══ TILE <400 × ≥170 ══ */
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            position: relative;
            background-color: var(--card);
            color: var(--card-foreground);
          }
        }

        .tile-hd {
          position: relative;
          z-index: 1;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0.5rem 0.75rem;
          border-bottom: 1px solid var(--border);
          flex-shrink: 0;
          background: linear-gradient(
            180deg,
            var(--inset) 0%,
            var(--card) 100%
          );
          box-shadow: 0 1px 0
            color-mix(in oklch, var(--shadow-color) 40%, transparent);
        }

        .tile-hd-left {
          display: flex;
          align-items: center;
          gap: 0.4375rem;
        }

        .tile-brand {
          width: 1.25rem;
          height: 1.25rem;
          border-radius: 0.25rem;
          background-color: var(--vp-accent-dim);
          border: 1px solid var(--vp-accent-border);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--info-ink);
          box-shadow: 0 0 6px var(--vp-accent-glow);
        }

        .tile-title {
          font-size: 0.6875rem;
          font-weight: 800;
          color: var(--card-foreground);
          letter-spacing: 0.04em;
        }

        .tile-leds {
          display: flex;
          gap: 0.3125rem;
          align-items: center;
        }

        .tile-body {
          position: relative;
          z-index: 1;
          flex: 1;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 0.75rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }

        .tile-keys-panel {
          background: linear-gradient(
            180deg,
            var(--inset) 0%,
            var(--card) 100%
          );
          border-radius: 0.5rem;
          padding: 0.5rem 0.625rem;
          box-shadow:
            var(--vp-bezel),
            0 4px 16px color-mix(in oklch, var(--shadow-color) 60%, transparent),
            0 0 0 1px var(--border),
            inset 0 0 12px color-mix(in oklch, var(--info) 3%, transparent);
        }

        .tile-keys-bezel {
          background-color: var(--card);
          color: var(--card-foreground);
          border-radius: 0.1875rem;
          padding: 0.25rem 0.25rem 0;
          box-shadow: inset 0 2px 4px
            color-mix(in oklch, var(--shadow-color) 80%, transparent);
        }

        .tile-keys {
          display: flex;
          align-items: flex-end;
          gap: 2px;
          height: 2.5rem;
          position: relative;
          padding-bottom: 2px;
        }

        .tk {
          display: block;
          border-radius: 0 0 0.1875rem 0.1875rem;
          flex-shrink: 0;
        }
        .tk-w {
          width: 0.6875rem;
          height: 2.5rem;
          background: linear-gradient(
            180deg,
            var(--inset) 0%,
            var(--border) 100%
          );
          border: 1px solid var(--border);
        }
        .tk-b {
          width: 0.4375rem;
          height: 1.625rem;
          background: linear-gradient(
            180deg,
            var(--tooltip) 0%,
            color-mix(in oklch, var(--tooltip) 84%, var(--shadow-color)) 100%
          );
          border: 1px solid var(--border);
          margin: 0 -0.25rem;
          z-index: 1;
          position: relative;
        }

        .tile-ft {
          position: relative;
          z-index: 1;
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: 0.375rem 0.75rem;
          border-top: 1px solid var(--border);
          flex-shrink: 0;
          background: linear-gradient(
            180deg,
            var(--card) 0%,
            var(--inset) 100%
          );
        }

        .tile-ft-left {
          display: flex;
          gap: 0.25rem;
        }

        .ft-chip {
          font-size: 0.5625rem;
          font-weight: 600;
          color: var(--primary-foreground);
          background-color: var(--primary);
          border: 1px solid var(--border);
          border-radius: 0.1875rem;
          padding: 2px 0.375rem;
          white-space: nowrap;
          box-shadow: var(--vp-bezel);
        }

        .ft-chip--accent {
          color: var(--info-ink);
          background-color: var(--vp-accent-dim);
          border-color: var(--vp-accent-border);
          box-shadow: 0 0 6px var(--vp-accent-glow);
        }

        /* ══ CARD ≥400 × ≥170 ══ */
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            flex-direction: row;
            background-color: var(--card);
            color: var(--card-foreground);
          }
        }

        .card-left {
          width: 8.125rem;
          flex-shrink: 0;
          position: relative;
          background: linear-gradient(
            180deg,
            var(--inset) 0%,
            var(--card) 100%
          );
          border-right: 1px solid var(--border);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          box-shadow: inset -2px 0 8px
            color-mix(in oklch, var(--shadow-color) 30%, transparent);
        }

        .card-keys-panel {
          position: relative;
          z-index: 1;
          background: linear-gradient(
            180deg,
            var(--inset) 0%,
            var(--card) 100%
          );
          border-radius: 0.375rem;
          padding: 0.375rem 0.5rem;
          box-shadow:
            var(--vp-bezel),
            0 3px 12px color-mix(in oklch, var(--shadow-color) 50%, transparent),
            0 0 0 1px var(--border),
            inset 0 0 8px color-mix(in oklch, var(--info) 3%, transparent);
        }

        .card-keys-bezel {
          background-color: var(--card);
          color: var(--card-foreground);
          border-radius: 2px;
          padding: 0.1875rem 0.1875rem 0;
          box-shadow: inset 0 2px 4px
            color-mix(in oklch, var(--shadow-color) 80%, transparent);
        }

        .card-keys {
          display: flex;
          align-items: flex-end;
          gap: 1px;
          height: 1.875rem;
          position: relative;
          padding-bottom: 2px;
        }

        .ck {
          display: block;
          border-radius: 0 0 2px 2px;
          flex-shrink: 0;
        }
        .ck-w {
          width: 0.5rem;
          height: 1.875rem;
          background: linear-gradient(
            180deg,
            var(--inset) 0%,
            var(--border) 100%
          );
          border: 1px solid var(--border);
        }
        .ck-b {
          width: 0.3125rem;
          height: 1.1875rem;
          background: linear-gradient(
            180deg,
            var(--tooltip) 0%,
            color-mix(in oklch, var(--tooltip) 84%, var(--shadow-color)) 100%
          );
          border: 1px solid var(--border);
          margin: 0 -0.1875rem;
          z-index: 1;
          position: relative;
        }

        .card-left-leds {
          position: relative;
          z-index: 1;
          display: flex;
          gap: 0.3125rem;
        }

        .card-keys-label {
          position: relative;
          z-index: 1;
          font-size: 0.5rem;
          font-weight: 800;
          color: var(--info-ink);
          letter-spacing: 0.12em;
        }

        .card-divider {
          width: 1px;
          background-color: var(--border);
          flex-shrink: 0;
          box-shadow: 1px 0 0
            color-mix(in oklch, var(--shadow-color) 50%, transparent);
        }

        .card-body {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          padding: 0.875rem 1rem;
          justify-content: center;
          background: linear-gradient(
            135deg,
            var(--card) 0%,
            color-mix(in oklch, var(--card) 84%, var(--shadow-color)) 100%
          );
          box-shadow: inset 0 0 60px
            color-mix(in oklch, var(--info) 2%, transparent);
        }

        .card-icon-row {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin-bottom: 2px;
        }

        .card-brand-icon {
          width: 1.125rem;
          height: 1.125rem;
          border-radius: 0.25rem;
          background-color: var(--vp-accent-dim);
          border: 1px solid var(--vp-accent-border);
          display: flex;
          align-items: center;
          justify-content: center;
          color: var(--info-ink);
          flex-shrink: 0;
          box-shadow: 0 0 6px var(--vp-accent-glow);
        }

        .card-eyebrow {
          font-size: 0.625rem;
          font-weight: 700;
          color: var(--info-ink);
          text-transform: uppercase;
          letter-spacing: 0.1em;
        }

        .card-title {
          font-size: 0.9375rem;
          font-weight: 800;
          color: var(--card-foreground);
          line-height: 1.2;
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .card-meta {
          font-size: 0.625rem;
          color: var(--muted-foreground);
          margin: 0;
          letter-spacing: 0.02em;
        }

        .card-chips {
          display: flex;
          gap: 0.25rem;
          flex-wrap: wrap;
          margin-top: 0.25rem;
        }

        .chip {
          font-size: 0.5625rem;
          font-weight: 600;
          color: var(--primary-foreground);
          background-color: var(--primary);
          border: 1px solid var(--border);
          border-radius: 0.1875rem;
          padding: 2px 0.4375rem;
          white-space: nowrap;
          box-shadow: var(--vp-bezel);
        }

        .chip--accent {
          color: var(--info-ink);
          background-color: var(--vp-accent-dim);
          border-color: var(--vp-accent-border);
          box-shadow: 0 0 6px var(--vp-accent-glow);
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
          border-radius: 0.375rem;
          background-color: var(--hover);
          border: 1px solid color-mix(in oklch, var(--border) 12%, transparent);
        }

        .vpe-icon {
          color: var(--warning-ink);
          flex-shrink: 0;
        }

        .vpe-label {
          font-weight: 600;
          font-size: 0.8125rem;
          color: var(--foreground);
          flex: 1;
        }

        .vpe-tag {
          padding: 1px 0.375rem;
          border-radius: 0.5rem;
          font-size: 0.5625rem;
          font-weight: 700;
          background-color: color-mix(
            in oklch,
            var(--warning) 10%,
            transparent
          );
          color: var(--warning-ink);
          border: 1px solid color-mix(in oklch, var(--warning) 20%, transparent);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}
