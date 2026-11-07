import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe, type SafeString } from '@ember/template';
import { modifier } from 'ember-modifier';

import {
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import StringField from '@cardstack/base/string';

import { decodeMono, onsetTimes, onsets } from './analyze';
import type { SongLyrics } from './lyric-types';

/** one sung word: its text as shown, and the seconds of its own mix it is sung over */
export class LyricWord extends FieldDef {
  static displayName = 'Lyric word';
  @field text = contains(StringField);
  @field start = contains(NumberField);
  @field end = contains(NumberField);
  /** set once someone has checked its timing by ear (no longer flagged) */
  @field checked = contains(BooleanField);

  static embedded = class Embedded extends Component<typeof LyricWord> {
    <template>
      <span class='w'>{{@model.text}} <small>{{@model.start}}</small></span>
      <style scoped>
        .w {
          font: 500 13px/1.3 var(--boxel-font-family, system-ui);
        }
        small {
          color: #7a808b;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
  static atom = LyricWord.embedded;
}

/** one line of the song: its section, its words, and (for Korean) the English under it */
export class LyricLine extends FieldDef {
  static displayName = 'Lyric line';
  /** "Verse 1", "Chorus 1" … */
  @field section = contains(StringField);
  /** the English of a Korean line, shown small under it */
  @field translation = contains(StringField);
  @field words = containsMany(LyricWord);

  static embedded = class Embedded extends Component<typeof LyricLine> {
    get text() {
      return (this.args.model.words ?? []).map((w) => w.text).join(' ');
    }
    <template>
      <div class='l'>
        <span class='s'>{{@model.section}}</span>
        <span>{{this.text}}</span>
        {{#if @model.translation}}<em>{{@model.translation}}</em>{{/if}}
      </div>
      <style scoped>
        .l {
          display: grid;
          gap: 2px;
          font: 400 14px/1.35 var(--boxel-font-family, system-ui);
        }
        .s {
          font:
            500 10px/1 ui-monospace,
            monospace;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          color: #7a808b;
        }
        em {
          color: #5a606b;
          font-size: 12px;
        }
      </style>
    </template>
  };
}

/** the lines of a card, in the shape the player reads */
export function songLyricsOf(
  lines: LyricLine[] | undefined | null,
): SongLyrics | undefined {
  const list = (lines ?? []).filter((l) => (l.words ?? []).length);
  if (!list.length) return undefined;
  const sections: string[] = [];
  return {
    sections,
    lines: list.map((l) => {
      const name = l.section ?? '';
      if (sections[sections.length - 1] !== name) sections.push(name);
      return {
        section: sections.length - 1,
        translation: l.translation ?? '',
        words: (l.words ?? []).map((w) => ({
          text: w.text ?? '',
          start: w.start ?? 0,
          end: w.end ?? w.start ?? 0,
        })),
      };
    }),
  };
}

/* ======================================================================
   THE TIMING EDITOR
   A timeline of the vocal (the waveform, the song's eighth-note grid, a
   block per word whose edges drag and snap to the grid), a live preview
   of the line with the bouncing dot landing exactly as the video will,
   doubtful words tinted, and tapping along at any speed.
   ====================================================================== */

interface Flat {
  line: number;
  index: number;
  word: LyricWord;
}

interface Drag {
  flat: Flat;
  edge: 'start' | 'end' | 'both';
  x0: number;
  start0: number;
  end0: number;
  start: number;
  end: number;
}

interface Undo {
  word: LyricWord;
  start: number;
  end: number;
}

const round = (t: number) => Math.round(t * 1000) / 1000;
const clockOf = (t: number) =>
  `${Math.floor(t / 60)}:${(t % 60).toFixed(2).padStart(5, '0')}`;
const LANE_H = 34;

const setupTimeline = modifier(
  (el: HTMLElement, [owner]: [LyricTimingEditor]) => {
    owner.scroller = el;
    const ro = new ResizeObserver(() => owner.draw());
    ro.observe(el);
    const scroll = () => owner.draw();
    el.addEventListener('scroll', scroll, { passive: true });
    return () => {
      ro.disconnect();
      el.removeEventListener('scroll', scroll);
    };
  },
);

const setupAudio = modifier(
  (el: HTMLAudioElement, [owner]: [LyricTimingEditor]) => {
    owner.audio = el;
    const play = () => owner.run();
    const seeked = () => owner.frame();
    el.addEventListener('play', play);
    el.addEventListener('seeked', seeked);
    el.addEventListener('pause', seeked);
    return () => {
      el.removeEventListener('play', play);
      el.removeEventListener('seeked', seeked);
      el.removeEventListener('pause', seeked);
      owner.stopRun();
    };
  },
);

const setupPreview = modifier(
  (el: HTMLElement, [owner]: [LyricTimingEditor]) => {
    owner.preview = el;
    owner.frame();
  },
);

const setupKeys = modifier((_el: HTMLElement, [owner]: [LyricTimingEditor]) => {
  const key = (e: KeyboardEvent) => owner.key(e);
  window.addEventListener('keydown', key);
  return () => window.removeEventListener('keydown', key);
});

/** pressing starts at once (a drag, or a tap timed to the syllable), so it listens for the press itself */
const onPress = modifier(
  (el: HTMLElement, [handler]: [(e: PointerEvent) => void]) => {
    el.addEventListener('pointerdown', handler);
    return () => el.removeEventListener('pointerdown', handler);
  },
);

const setupCanvas = modifier(
  (el: HTMLCanvasElement, [owner]: [LyricTimingEditor]) => {
    owner.canvas = el;
    owner.draw();
  },
);

export class LyricTimingEditor extends GlimmerComponent<{
  Args: {
    lines: LyricLine[] | undefined;
    /** the mix, to play */
    url: string;
    /** the vocal alone, if the card links one: a clearer waveform and onsets */
    vocalsUrl?: string;
    /** the mix's eighth notes (seconds) and 0/1/2 off/beat/bar, for the grid */
    eighths?: number[];
    beat?: number[];
  };
}> {
  audio?: HTMLAudioElement;
  scroller?: HTMLElement;
  canvas?: HTMLCanvasElement;
  preview?: HTMLElement;

  @tracked pps = 140;
  @tracked sel = 0;
  @tracked tapping = false;
  @tracked rate = 1;
  @tracked looping = false;
  @tracked drag?: Drag;
  @tracked status = 'Loading the waveform…';
  @tracked onsetList: number[] = [];
  @tracked edits = 0;

  /** loudness every 5 ms, and the clock of the audio element between its updates */
  private peaks?: Float32Array;
  private peakRate = 200;
  private raf = 0;
  private seenAt = 0;
  private seenPos = 0;
  private undos: Undo[] = [];
  private previewLine = -1;
  private previewSpots: { x: number; y: number }[] = [];
  private loading = false;

  /* ---- data ----------------------------------------------------------- */

  get lines(): LyricLine[] {
    return this.args.lines ?? [];
  }

  get flat(): Flat[] {
    void this.edits;
    const out: Flat[] = [];
    this.lines.forEach((l, line) =>
      (l.words ?? []).forEach((word, index) => out.push({ line, index, word })),
    );
    return out;
  }

  get selected(): Flat | undefined {
    return this.flat[this.sel];
  }

  get duration(): number {
    const last = this.flat[this.flat.length - 1]?.word;
    return Math.max((last?.end ?? 0) + 6, 30);
  }

  get trackStyle(): SafeString {
    return htmlSafe(`width:${Math.ceil(this.duration * this.pps)}px`);
  }

  async loadWave() {
    const url = this.args.vocalsUrl || this.args.url;
    if (!url || this.loading || this.peaks) return;
    this.loading = true;
    try {
      const { x, sr } = await decodeMono(url);
      const step = Math.round(sr / this.peakRate);
      const peaks = new Float32Array(Math.ceil(x.length / step));
      for (let i = 0; i < peaks.length; i++) {
        let m = 0;
        const end = Math.min(x.length, (i + 1) * step);
        for (let j = i * step; j < end; j++) m = Math.max(m, Math.abs(x[j]!));
        peaks[i] = m;
      }
      let top = 0;
      for (const v of peaks) top = Math.max(top, v);
      for (let i = 0; i < peaks.length; i++)
        peaks[i] = Math.sqrt(peaks[i]! / (top || 1));
      this.peaks = peaks;
      this.status = this.args.vocalsUrl
        ? 'Vocal waveform'
        : 'Mix waveform (link a vocal stem for a clearer one)';
      this.draw();
      // where notes start: on a vocal stem, the doubtful words are the ones
      // that start away from any
      if (this.args.vocalsUrl) {
        const { env, times } = await onsets(x, sr);
        this.onsetList = onsetTimes(env, times, 0.25);
      }
    } catch (e) {
      this.status = `Couldn't load the audio: ${String(e)}`;
    } finally {
      this.loading = false;
    }
  }

  /** words to check: evenly spread runs (the aligner guessed them), odd lengths, or away from a vocal onset */
  get doubts(): Set<LyricWord> {
    void this.edits;
    const flat = this.flat;
    const out = new Set<LyricWord>();
    for (let i = 0; i + 2 < flat.length; i++) {
      const [a, b, c] = [flat[i]!.word, flat[i + 1]!.word, flat[i + 2]!.word];
      const g1 = (b.start ?? 0) - (a.start ?? 0);
      const g2 = (c.start ?? 0) - (b.start ?? 0);
      if (Math.abs(g1 - g2) < 0.004 && g1 > 0)
        [a, b, c].forEach((w) => out.add(w));
    }
    const ons = this.onsetList;
    for (const { word } of flat) {
      const len = (word.end ?? 0) - (word.start ?? 0);
      if (len < 0.06 || len > 2.5) out.add(word);
      if (ons.length) {
        const s = word.start ?? 0;
        let lo = 0;
        let hi = ons.length - 1;
        while (lo < hi) {
          const mid = (lo + hi) >> 1;
          if (ons[mid]! < s) lo = mid + 1;
          else hi = mid;
        }
        const near = Math.min(
          Math.abs((ons[lo] ?? Infinity) - s),
          Math.abs((ons[lo - 1] ?? Infinity) - s),
        );
        if (near > 0.07) out.add(word);
      }
    }
    for (const { word } of flat) if (word.checked) out.delete(word);
    return out;
  }

  get doubtCount(): number {
    return this.doubts.size;
  }

  /* ---- the blocks ----------------------------------------------------- */

  timesOf(f: Flat): { start: number; end: number } {
    const d = this.drag;
    if (d && d.flat.word === f.word) return { start: d.start, end: d.end };
    return { start: f.word.start ?? 0, end: f.word.end ?? f.word.start ?? 0 };
  }

  blockStyle = (f: Flat): SafeString => {
    void this.edits;
    const { start, end } = this.timesOf(f);
    const left = start * this.pps;
    const width = Math.max(6, (end - start) * this.pps);
    return htmlSafe(
      `left:${left.toFixed(1)}px;width:${width.toFixed(1)}px;top:${f.line % 2 ? LANE_H + 4 : 0}px`,
    );
  };

  blockClass = (f: Flat, i: number): string => {
    const c = ['blk'];
    if (i === this.sel) c.push('sel');
    if (this.doubts.has(f.word)) c.push('doubt');
    if (f.word.checked) c.push('ok');
    if (f.index === 0) c.push('head');
    return c.join(' ');
  };

  lineLabel = (f: Flat): string =>
    f.index === 0 ? (this.lines[f.line]?.section ?? '') : '';

  /* ---- time ----------------------------------------------------------- */

  /** the playhead: the element's time, run on smoothly between its coarse updates */
  now(): number {
    const el = this.audio;
    if (!el) return 0;
    if (el.paused) return el.currentTime;
    const t = performance.now();
    if (el.currentTime !== this.seenPos) {
      this.seenPos = el.currentTime;
      this.seenAt = t;
    }
    return (
      this.seenPos +
      Math.min(0.25, ((t - this.seenAt) / 1000) * el.playbackRate)
    );
  }

  run = () => {
    this.stopRun();
    const tick = () => {
      this.frame();
      if (this.audio && !this.audio.paused) {
        this.raf = requestAnimationFrame(tick);
      }
    };
    tick();
  };

  stopRun() {
    cancelAnimationFrame(this.raf);
  }

  /** one frame: loop, follow, the playhead, the waveform and the preview */
  frame() {
    void this.loadWave();
    const t = this.now();
    const el = this.audio;
    const f = this.selected;
    if (el && !el.paused && this.looping && f) {
      const line = this.lines[f.line]?.words ?? [];
      const a = (line[0]?.start ?? 0) - 0.6;
      const b = (line[line.length - 1]?.end ?? 0) + 0.4;
      if (t > b) el.currentTime = Math.max(0, a);
    }
    // keep the playhead in view while it plays
    const sc = this.scroller;
    if (sc && el && !el.paused && !this.drag) {
      const x = t * this.pps;
      if (x < sc.scrollLeft + 40 || x > sc.scrollLeft + sc.clientWidth * 0.75)
        sc.scrollLeft = x - sc.clientWidth * 0.3;
    }
    this.draw(t);
    this.paintPreview(t);
    const clock =
      this.scroller?.parentElement?.querySelector<HTMLElement>('[data-clock]');
    if (clock) clock.textContent = clockOf(t);
  }

  /* ---- drawing -------------------------------------------------------- */

  draw(t = this.now()) {
    const c = this.canvas;
    const sc = this.scroller;
    if (!c || !sc) return;
    const dpr = window.devicePixelRatio || 1;
    const w = sc.clientWidth;
    const h = c.clientHeight;
    if (c.width !== Math.round(w * dpr) || c.height !== Math.round(h * dpr)) {
      c.width = Math.round(w * dpr);
      c.height = Math.round(h * dpr);
    }
    c.style.left = `${sc.scrollLeft}px`;
    c.style.width = `${w}px`;
    const g = c.getContext('2d');
    if (!g) return;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, w, h);
    const t0 = sc.scrollLeft / this.pps;
    const t1 = t0 + w / this.pps;
    const xOf = (s: number) => (s - t0) * this.pps;

    // the grid: every eighth faint, beats firmer, bars with their number
    const e = this.args.eighths ?? [];
    const lv = this.args.beat ?? [];
    let bar = 0;
    e.forEach((s, i) => {
      if ((lv[i] ?? 0) === 2) bar++;
      if (s < t0 - 1 || s > t1 + 1) return;
      const x = Math.round(xOf(s)) + 0.5;
      g.fillStyle =
        lv[i] === 2
          ? 'rgba(20,20,24,.35)'
          : lv[i] === 1
            ? 'rgba(20,20,24,.16)'
            : 'rgba(20,20,24,.07)';
      g.fillRect(x, 0, 1, h);
      if (lv[i] === 2) {
        g.fillStyle = 'rgba(20,20,24,.5)';
        g.font = '500 10px ui-monospace, monospace';
        g.fillText(String(bar), x + 3, 11);
      }
    });

    // the waveform, mirrored about the middle
    const p = this.peaks;
    if (p) {
      const mid = h * 0.5;
      g.fillStyle = 'rgba(255,90,31,.55)';
      for (let x = 0; x < w; x++) {
        const a = Math.floor((t0 + x / this.pps) * this.peakRate);
        const b = Math.max(
          a + 1,
          Math.floor((t0 + (x + 1) / this.pps) * this.peakRate),
        );
        let m = 0;
        for (let j = a; j < b; j++) m = Math.max(m, p[j] ?? 0);
        const bh = m * (h * 0.45);
        g.fillRect(x, mid - bh, 1, bh * 2 || 1);
      }
    }
    // vocal onsets, as small ticks at the bottom
    g.fillStyle = 'rgba(25,160,190,.8)';
    for (const o of this.onsetList)
      if (o >= t0 && o <= t1) g.fillRect(Math.round(xOf(o)), h - 7, 1, 7);

    // the playhead
    const px = Math.round(xOf(t)) + 0.5;
    g.fillStyle = '#ff2d4f';
    g.fillRect(px - 0.5, 0, 2, h);
  }

  /**
   * The preview: the line at the playhead, as the video sets it, with the
   * dot landing on every eighth on whichever word is being sung then (the
   * player's own rule).
   */
  paintPreview(t: number) {
    const el = this.preview;
    if (!el) return;
    const flat = this.flat;
    // the line being sung, or the next one
    let li = -1;
    for (const f of flat) {
      if ((f.word.start ?? 0) <= t + 0.3) li = f.line;
      else break;
    }
    li = Math.max(0, li);
    const words = this.lines[li]?.words ?? [];
    const row = el.querySelector<HTMLElement>('[data-row]');
    const dot = el.querySelector<HTMLElement>('[data-dot]');
    if (!row || !dot) return;
    if (li !== this.previewLine || row.childElementCount !== words.length) {
      this.previewLine = li;
      row.replaceChildren(
        ...words.map((w) => {
          const s = document.createElement('span');
          s.textContent = (w.text ?? '').toLowerCase();
          return s;
        }),
      );
      const box = el.getBoundingClientRect();
      this.previewSpots = [...row.children].map((c) => {
        const r = c.getBoundingClientRect();
        return { x: r.left + r.width / 2 - box.left, y: r.top - box.top };
      });
      const tr = el.querySelector<HTMLElement>('[data-tr]');
      if (tr) tr.textContent = this.lines[li]?.translation ?? '';
    }
    // sung words light up
    [...row.children].forEach((c, i) =>
      c.classList.toggle('on', (words[i]?.start ?? Infinity) <= t),
    );
    // the dot: eighth to eighth, on the word sung at each
    const e = this.args.eighths ?? [];
    const first = words[0]?.start ?? 0;
    const last = words[words.length - 1]?.end ?? 0;
    if (!e.length || !words.length || t < first - 1 || t > last + 0.6) {
      dot.style.opacity = '0';
      return;
    }
    const wordAt = (time: number) => {
      let k = 0;
      while (k + 1 < words.length && (words[k + 1]!.start ?? 0) <= time + 0.08)
        k++;
      return k;
    };
    let lo = 0;
    let hi = e.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (e[mid]! <= t) lo = mid;
      else hi = mid - 1;
    }
    const a = e[lo]!;
    const b = e[lo + 1] ?? a + 0.33;
    const p = Math.min(1, Math.max(0, (t - a) / (b - a)));
    const A = this.previewSpots[wordAt(Math.max(a, first))];
    const B = this.previewSpots[wordAt(Math.max(b, first))];
    if (!A || !B) return;
    const ease = p * p * (3 - 2 * p);
    const x = A.x + (B.x - A.x) * ease;
    const y = A.y + (B.y - A.y) * ease;
    const lift =
      (14 + Math.hypot(B.x - A.x, B.y - A.y) * 0.18) *
      Math.sin(Math.PI * p) ** 1.6;
    dot.style.opacity = '1';
    dot.style.transform = `translate(${x.toFixed(1)}px, ${(y - lift - 6).toFixed(1)}px) translate(-50%, -100%)`;
  }

  /* ---- editing -------------------------------------------------------- */

  /** the nearest sixteenth of the mix's grid, if within 45 ms */
  snap(t: number): number {
    const e = this.args.eighths ?? [];
    let best = t;
    let d = 0.045;
    for (let i = 0; i < e.length; i++) {
      const a = e[i]!;
      if (a > t + 0.4) break;
      if (a < t - 0.4) continue;
      for (const c of [a, (a + (e[i + 1] ?? a + 0.333)) / 2]) {
        if (Math.abs(c - t) < d) [best, d] = [c, Math.abs(c - t)];
      }
    }
    return best;
  }

  commit(word: LyricWord, start: number, end: number) {
    this.undos.push({ word, start: word.start ?? start, end: word.end ?? end });
    if (this.undos.length > 200) this.undos.shift();
    word.start = round(start);
    word.end = round(Math.max(start + 0.05, end));
    word.checked = true;
    this.edits++;
    this.draw();
  }

  undo = () => {
    const u = this.undos.pop();
    if (!u) return;
    u.word.start = u.start;
    u.word.end = u.end;
    this.edits++;
  };

  grab = (i: number, edge: 'start' | 'end' | 'both', e: PointerEvent) => {
    e.preventDefault();
    e.stopPropagation();
    const flat = this.flat[i];
    if (!flat) return;
    this.sel = i;
    const start0 = flat.word.start ?? 0;
    const end0 = flat.word.end ?? start0;
    this.drag = {
      flat,
      edge,
      x0: e.clientX,
      start0,
      end0,
      start: start0,
      end: end0,
    };
    const target = e.currentTarget as HTMLElement;
    target.setPointerCapture(e.pointerId);
    const move = (ev: PointerEvent) => {
      const d = this.drag;
      if (!d) return;
      const dt = (ev.clientX - d.x0) / this.pps;
      const free = ev.altKey;
      const snap = (v: number) => (free ? v : this.snap(v));
      let start = d.start0;
      let end = d.end0;
      if (d.edge === 'start') start = Math.min(snap(d.start0 + dt), end - 0.05);
      else if (d.edge === 'end')
        end = Math.max(snap(d.end0 + dt), start + 0.05);
      else {
        start = snap(d.start0 + dt);
        end = start + (d.end0 - d.start0);
      }
      this.drag = { ...d, start, end };
    };
    const up = () => {
      target.removeEventListener('pointermove', move);
      target.removeEventListener('pointerup', up);
      target.removeEventListener('pointercancel', up);
      const d = this.drag;
      this.drag = undefined;
      if (d && (d.start !== d.start0 || d.end !== d.end0))
        this.commit(d.flat.word, d.start, d.end);
    };
    target.addEventListener('pointermove', move);
    target.addEventListener('pointerup', up);
    target.addEventListener('pointercancel', up);
  };

  /** a click on the timeline's empty space moves the playhead there */
  seek = (ev: Event) => {
    const e = ev as MouseEvent;
    const sc = this.scroller;
    if (!sc || !this.audio) return;
    const r = sc.getBoundingClientRect();
    this.audio.currentTime = Math.max(
      0,
      (e.clientX - r.left + sc.scrollLeft) / this.pps,
    );
    this.frame();
  };

  select = (i: number) => {
    this.sel = Math.max(0, Math.min(this.flat.length - 1, i));
    const f = this.selected;
    const sc = this.scroller;
    if (f && sc) {
      const x = (f.word.start ?? 0) * this.pps;
      if (x < sc.scrollLeft || x > sc.scrollLeft + sc.clientWidth - 60)
        sc.scrollLeft = x - sc.clientWidth * 0.3;
    }
  };

  nudge = (edge: 'start' | 'end', ms: number) => {
    const f = this.selected;
    if (!f) return;
    const s = f.word.start ?? 0;
    const e = f.word.end ?? s;
    if (edge === 'start')
      this.commit(f.word, Math.min(s + ms / 1000, e - 0.05), e);
    else this.commit(f.word, s, e + ms / 1000);
  };

  /** the selected word starts now (the one before ends there), then the next is picked */
  tap = () => {
    const f = this.selected;
    if (!f || !this.audio) return;
    const t = this.now();
    const span = Math.max(0.12, (f.word.end ?? t) - (f.word.start ?? t));
    const prev = this.flat[this.sel - 1]?.word;
    if (prev && (prev.end ?? 0) > t) prev.end = round(t);
    this.commit(f.word, t, t + span);
    this.select(this.sel + 1);
  };

  playFrom = (t: number) => {
    if (!this.audio) return;
    this.audio.currentTime = Math.max(0, t);
    void this.audio.play();
  };

  playLine = () => {
    const f = this.selected;
    const w = this.lines[f?.line ?? 0]?.words ?? [];
    this.playFrom((w[0]?.start ?? 0) - 1);
  };

  playWord = () => this.playFrom((this.selected?.word.start ?? 0) - 0.5);

  toggle = () => {
    if (!this.audio) return;
    if (this.audio.paused) void this.audio.play();
    else this.audio.pause();
  };

  setRate = (r: number) => {
    this.rate = r;
    if (this.audio) {
      this.audio.playbackRate = r;
      (
        this.audio as HTMLAudioElement & { preservesPitch?: boolean }
      ).preservesPitch = true;
    }
  };

  zoom = (k: number) => {
    const sc = this.scroller;
    const centre = sc ? (sc.scrollLeft + sc.clientWidth / 2) / this.pps : 0;
    this.pps = Math.max(30, Math.min(600, this.pps * k));
    if (sc) sc.scrollLeft = centre * this.pps - sc.clientWidth / 2;
    this.draw();
  };

  nextDoubt = () => {
    const d = this.doubts;
    const flat = this.flat;
    for (let k = 1; k <= flat.length; k++) {
      const i = (this.sel + k) % flat.length;
      if (d.has(flat[i]!.word)) {
        this.select(i);
        this.playWord();
        return;
      }
    }
  };

  markChecked = () => {
    const f = this.selected;
    if (!f) return;
    f.word.checked = !f.word.checked;
    this.edits++;
  };

  toggleTapping = () => {
    this.tapping = !this.tapping;
  };

  toggleLoop = () => {
    this.looping = !this.looping;
  };

  setText = (e: Event) => {
    const f = this.selected;
    if (f) f.word.text = (e.target as HTMLInputElement).value;
  };

  setTime = (edge: 'start' | 'end', e: Event) => {
    const f = this.selected;
    const v = Number((e.target as HTMLInputElement).value);
    if (!f || !Number.isFinite(v)) return;
    this.commit(
      f.word,
      edge === 'start' ? v : (f.word.start ?? 0),
      edge === 'end' ? v : (f.word.end ?? v),
    );
  };

  key(e: KeyboardEvent) {
    const target = e.target as HTMLElement | null;
    if (target?.closest('input, textarea, select, [contenteditable]')) return;
    const k = e.key;
    const big = e.shiftKey ? 50 : 10;
    const act = (f: () => void) => {
      e.preventDefault();
      f();
    };
    if ((e.metaKey || e.ctrlKey) && k.toLowerCase() === 'z')
      return act(this.undo);
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (k === ' ') return act(this.toggle);
    if (k === 't' || k === 'T') return act(this.tap);
    if (k === 'ArrowRight') return act(() => this.select(this.sel + 1));
    if (k === 'ArrowLeft') return act(() => this.select(this.sel - 1));
    if (k === '[' || k === '{')
      return act(() =>
        this.nudge(k === '[' ? 'start' : 'end', k === '[' ? -big : -50),
      );
    if (k === ']' || k === '}')
      return act(() =>
        this.nudge(k === ']' ? 'start' : 'end', k === ']' ? big : 50),
      );
    if (k === 'l' || k === 'L') return act(this.toggleLoop);
    if (k === 'n' || k === 'N') return act(this.nextDoubt);
    if (k === 'p' || k === 'P') return act(this.playWord);
    if (k === 'c' || k === 'C') return act(this.markChecked);
    if (k === '=' || k === '+') return act(() => this.zoom(1.25));
    if (k === '-') return act(() => this.zoom(0.8));
  }

  isRate = (r: number) => this.rate === r;
  fmt = (t: number | null | undefined) =>
    t === null || t === undefined ? '' : t.toFixed(3);

  <template>
    <div class='ed' {{setupKeys this}}>
      {{! LIVE PREVIEW: the line with the dot, as the video lands it }}
      <div class='preview' {{setupPreview this}}>
        <div class='row' data-row></div>
        <p class='tr' data-tr></p>
        <i class='dot' data-dot></i>
      </div>

      {{! TRANSPORT }}
      <div class='bar'>
        <audio src={{@url}} preload='auto' {{setupAudio this}}><track
            kind='captions'
          /></audio>
        <button type='button' class='primary' {{on 'click' this.toggle}}>Play /
          pause</button>
        <span class='clock' data-clock>0:00.00</span>
        <span class='group'>
          <button
            type='button'
            class={{if (this.isRate 0.5) 'on'}}
            {{on 'click' (fn this.setRate 0.5)}}
          >½×</button>
          <button
            type='button'
            class={{if (this.isRate 0.75) 'on'}}
            {{on 'click' (fn this.setRate 0.75)}}
          >¾×</button>
          <button
            type='button'
            class={{if (this.isRate 1) 'on'}}
            {{on 'click' (fn this.setRate 1)}}
          >1×</button>
        </span>
        <button
          type='button'
          class={{if this.looping 'on'}}
          {{on 'click' this.toggleLoop}}
        >Loop line</button>
        <button
          type='button'
          class={{if this.tapping 'tap on' 'tap'}}
          {{on 'click' this.toggleTapping}}
        >
          {{if this.tapping 'Tapping: press T on each word' 'Tap along'}}
        </button>
        {{#if this.tapping}}
          <button type='button' class='tapnow' {{onPress this.tap}}>TAP</button>
        {{/if}}
        <button type='button' {{on 'click' this.nextDoubt}}>Next to check ({{this.doubtCount}})</button>
        <span class='group'>
          <button type='button' {{on 'click' (fn this.zoom 0.8)}}>−</button>
          <button type='button' {{on 'click' (fn this.zoom 1.25)}}>+</button>
        </span>
        <button type='button' {{on 'click' this.undo}}>Undo</button>
      </div>

      {{! TIMELINE: waveform, grid, word blocks }}
      <div class='tl' {{setupTimeline this}}>
        {{! template-lint-disable no-invalid-interactive }}
        <div class='track' style={{this.trackStyle}} {{on 'click' this.seek}}>
          <canvas class='wave' {{setupCanvas this}}></canvas>
          <div class='lanes'>
            {{#each this.flat as |f i|}}
              <div class={{this.blockClass f i}} style={{this.blockStyle f}}>
                {{#if (this.lineLabel f)}}<span class='sec'>{{this.lineLabel
                      f
                    }}</span>{{/if}}
                <span
                  class='edge a'
                  {{onPress (fn this.grab i 'start')}}
                ></span>
                <span
                  class='body'
                  {{onPress (fn this.grab i 'both')}}
                >{{f.word.text}}</span>
                <span class='edge b' {{onPress (fn this.grab i 'end')}}></span>
              </div>
            {{/each}}
          </div>
        </div>
      </div>
      <p class='hint'>{{this.status}}
        · drag a word's edges, they snap to the grid (hold Alt to place freely)
        · Space play · T tap · ← → word · [ ] start ±10 ms (Shift ±50) · Shift+[
        ] end ±50 · P play word · L loop · N next to check · C mark checked · ⌘Z
        undo · + − zoom</p>

      {{! THE SELECTED WORD }}
      {{#if this.selected}}
        <div class='word'>
          <label>Word
            <input
              value={{this.selected.word.text}}
              {{on 'change' this.setText}}
            /></label>
          <label>Start
            <input
              type='number'
              step='0.01'
              value={{this.fmt this.selected.word.start}}
              {{on 'change' (fn this.setTime 'start')}}
            /></label>
          <label>End
            <input
              type='number'
              step='0.01'
              value={{this.fmt this.selected.word.end}}
              {{on 'change' (fn this.setTime 'end')}}
            /></label>
          <button type='button' {{on 'click' this.playWord}}>▶ Word</button>
          <button type='button' {{on 'click' this.playLine}}>▶ Line</button>
          <button
            type='button'
            class={{if this.selected.word.checked 'on'}}
            {{on 'click' this.markChecked}}
          >
            {{if this.selected.word.checked 'Checked ✓' 'Mark checked'}}
          </button>
        </div>
      {{/if}}
    </div>
    <style scoped>
      .ed {
        display: grid;
        gap: 10px;
        font-family: var(--boxel-font-family, system-ui);
      }
      .preview {
        position: relative;
        min-height: 132px;
        padding: 44px 24px 18px;
        border-radius: 10px;
        background: #d4dce7;
        overflow: hidden;
      }
      .row {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: 0 0.28em;
        font:
          200 38px/1.1 Pretendard,
          system-ui,
          sans-serif;
        color: rgba(20, 20, 24, 0.38);
      }
      .tr {
        margin: 8px 0 0;
        text-align: center;
        font:
          300 14px/1.3 Pretendard,
          system-ui,
          sans-serif;
        color: #3c4254;
        min-height: 1em;
      }
      .dot {
        position: absolute;
        left: 0;
        top: 0;
        width: 12px;
        height: 12px;
        border-radius: 50%;
        background: #ff2d4f;
        box-shadow: -2px 0 0 rgba(25, 219, 239, 0.85);
        opacity: 0;
        will-change: transform;
      }
      .bar {
        position: sticky;
        top: 0;
        z-index: 3;
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        align-items: center;
        padding: 8px;
        border-radius: 8px;
        background: #fff;
        box-shadow: 0 1px 0 #e3e6eb;
      }
      .clock {
        min-width: 74px;
        font:
          500 14px/1 ui-monospace,
          'Martian Mono',
          monospace;
        font-variant-numeric: tabular-nums;
      }
      .group {
        display: inline-flex;
        gap: 2px;
      }
      button {
        font: 600 12px/1 var(--boxel-font-family, system-ui);
        padding: 7px 10px;
        border-radius: 6px;
        border: 0;
        background: #fff;
        color: #141418;
        cursor: pointer;
        box-shadow: inset 0 0 0 1px #c8ccd4;
      }
      button.on,
      button.primary {
        background: #141418;
        color: #fff;
        box-shadow: none;
      }
      button.tap.on {
        background: #ff2d4f;
      }
      button.tapnow {
        padding: 7px 22px;
        background: #ff2d4f;
        color: #fff;
        box-shadow: none;
        touch-action: manipulation;
      }
      .tl {
        position: relative;
        overflow-x: auto;
        overflow-y: hidden;
        border-radius: 8px;
        background: #f3f5f8;
      }
      .track {
        position: relative;
        height: 176px;
        cursor: text;
      }
      .wave {
        position: absolute;
        top: 0;
        height: 100px;
        pointer-events: none;
      }
      .lanes {
        position: absolute;
        left: 0;
        right: 0;
        top: 104px;
        height: 72px;
      }
      .blk {
        position: absolute;
        height: 30px;
        display: flex;
        align-items: stretch;
        border-radius: 5px;
        background: #fff;
        box-shadow: inset 0 0 0 1px #b9bfca;
        font: 500 12px/30px var(--boxel-font-family, system-ui);
        color: #141418;
      }
      .blk.head {
        box-shadow:
          inset 0 0 0 1px #b9bfca,
          -2px 0 0 #141418;
      }
      .blk.doubt {
        background: #fff1c2;
        box-shadow: inset 0 0 0 1px #e0b300;
      }
      .blk.ok {
        background: #eaf7ee;
      }
      .blk.sel {
        box-shadow: inset 0 0 0 2px #ff2d4f;
        z-index: 2;
      }
      .body {
        flex: 1;
        min-width: 0;
        padding: 0 3px;
        overflow: hidden;
        white-space: nowrap;
        cursor: grab;
        touch-action: none;
      }
      .edge {
        flex: 0 0 6px;
        cursor: ew-resize;
        touch-action: none;
      }
      .edge:hover {
        background: rgba(255, 45, 79, 0.35);
      }
      .sec {
        position: absolute;
        bottom: 100%;
        left: 0;
        font:
          500 9px/1.4 ui-monospace,
          monospace;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: #7a808b;
        white-space: nowrap;
        pointer-events: none;
      }
      .hint {
        margin: 0;
        font-size: 11px;
        line-height: 1.5;
        color: #6a707b;
      }
      .word {
        display: flex;
        flex-wrap: wrap;
        gap: 8px 12px;
        align-items: end;
        padding: 10px;
        border-radius: 8px;
        background: #fff;
        box-shadow: 0 1px 8px rgba(20, 20, 24, 0.1);
      }
      .word label {
        display: grid;
        gap: 3px;
        font-size: 11px;
        font-weight: 600;
        color: #3b4049;
      }
      .word input {
        width: 110px;
        font:
          500 14px/1.2 ui-monospace,
          monospace;
        padding: 5px 6px;
        border: 1px solid #c8ccd4;
        border-radius: 5px;
      }
    </style>
    <style>
      .ed .row span.on {
        color: #141418;
        text-shadow:
          -1.5px 0 rgba(25, 219, 239, 0.7),
          1.5px 0 rgba(255, 45, 79, 0.7);
      }
    </style>
  </template>
}
