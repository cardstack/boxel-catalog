import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';

import { Component, FieldDef, contains, field } from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import StringField from '@cardstack/base/string';

import MusicIcon from '@cardstack/boxel-icons/music';

import { decodeMono, measure, packNumbers, unpackNumbers } from './analyze';

/** what the player reads: a mix's loudness and tempo map, unpacked */
export interface MixHint {
  duration: number;
  peaks: number[];
  eighths: number[];
  strength: number[];
  beat: number[];
  /** changes when the mix is measured again: its URL's cache key */
  version: string;
}

/** the hint in a MixAnalysis field, unpacked once per measurement */
const unpacked = new Map<string, MixHint>();
export function hintOf(a: MixAnalysis | undefined | null): MixHint | undefined {
  if (!a?.eighths || !a.peaks) return undefined;
  const key = `${a.measuredAt}|${a.eighths.length}|${a.peaks.length}`;
  let hint = unpacked.get(key);
  if (!hint) {
    hint = {
      duration: a.duration ?? 0,
      peaks: unpackNumbers(a.peaks),
      eighths: unpackNumbers(a.eighths),
      strength: unpackNumbers(a.strength),
      beat: unpackNumbers(a.beat),
      version:
        (a.measuredAt ?? '').replace(/\D/g, '').slice(0, 14) ||
        String(a.eighths.length),
    };
    unpacked.set(key, hint);
  }
  return hint;
}

/** the loudness bars and, under them, a tick per beat (taller on the bar); redrawn when the canvas resizes */
export const drawPreview = modifier(
  (canvas: HTMLCanvasElement, [hint]: [MixHint | undefined]) => {
    const draw = () => {
      const dpr = window.devicePixelRatio || 1;
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
      const g = canvas.getContext('2d');
      if (!g || !w || !h) return;
      g.scale(dpr, dpr);
      g.clearRect(0, 0, w, h);
      if (!hint?.duration) return;
      const tick = Math.min(12, Math.round(h * 0.18));
      const waveH = h - tick - 4;
      const count = Math.floor(w / 3);
      g.fillStyle = '#ff5a1f';
      for (let i = 0; i < count; i++) {
        const a = Math.floor((i * hint.peaks.length) / count);
        const b = Math.max(
          a + 1,
          Math.floor(((i + 1) * hint.peaks.length) / count),
        );
        let v = 0;
        for (let j = a; j < b; j++) v = Math.max(v, hint.peaks[j] ?? 0);
        const bh = Math.max(1, v * waveH);
        g.fillRect(i * 3, waveH - bh, 2, bh);
      }
      hint.eighths.forEach((t, i) => {
        const level = hint.beat[i] ?? 0;
        if (!level) return;
        const x = Math.round((t / hint.duration) * w) + 0.5;
        const th = level === 2 ? tick : Math.ceil(tick / 2);
        g.fillStyle = level === 2 ? 'rgba(20,20,24,0.9)' : 'rgba(20,20,24,0.3)';
        g.fillRect(x, h - th, 1, th);
      });
    };
    draw();
    // fitted cells and split panes size the canvas after it is inserted
    let last = `${canvas.clientWidth}x${canvas.clientHeight}`;
    const ro = new ResizeObserver(() => {
      const now = `${canvas.clientWidth}x${canvas.clientHeight}`;
      if (now !== last) {
        last = now;
        draw();
      }
    });
    ro.observe(canvas);
    return () => ro.disconnect();
  },
);

const FONT_SHEET =
  'https://fonts.googleapis.com/css2?family=Martian+Mono:wdth,wght@75..112.5,300..500&display=swap';
const FACES: [
  family: string,
  file: string,
  descriptors: FontFaceDescriptors,
][] = [
  ['Pretendard', 'Pretendard-ExtraLight.otf', { weight: '200' }],
  ['Pretendard', 'Pretendard-Medium.otf', { weight: '500' }],
  ['Instrument Serif', 'InstrumentSerif-Italic.ttf', { style: 'italic' }],
];
const requested = new Set<string>();

/**
 * The video's faces for the cards around it: Pretendard and Instrument
 * Serif from the realm's media/fonts (next to the linked mix, at
 * media/audio/), Martian Mono from Google Fonts. Loaded once per page;
 * until then (or without a mix) the cards fall back to system faces.
 */
export const lyricFonts = modifier(
  (_el: HTMLElement, [mixUrl]: [string | undefined]) => {
    if (typeof document === 'undefined') return;
    if (!document.querySelector(`link[href="${FONT_SHEET}"]`)) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = FONT_SHEET;
      document.head.appendChild(link);
    }
    if (!mixUrl || typeof FontFace === 'undefined') return;
    for (const [family, file, descriptors] of FACES) {
      let src: string;
      try {
        src = new URL(`../fonts/${file}`, mixUrl).href;
      } catch {
        return;
      }
      if (requested.has(src)) continue;
      requested.add(src);
      new FontFace(family, `url("${src}")`, { display: 'swap', ...descriptors })
        .load()
        .then((face) => document.fonts.add(face))
        .catch(() => requested.delete(src));
    }
  },
);

/** "4:36": a duration as the player's clock shows it */
export const clock = (d: number | null | undefined): string => {
  if (!d) return '—';
  const s = Math.floor(d);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
};

const fmt = (d: number | null | undefined) =>
  d ? `${Math.floor(d / 60)}:${(d % 60).toFixed(2).padStart(5, '0')}` : '—';

class Embedded extends Component<typeof MixAnalysis> {
  get hint() {
    return hintOf(this.args.model as MixAnalysis);
  }
  get count() {
    return this.hint?.eighths.length ?? 0;
  }
  <template>
    <figure class='mix'>
      <canvas
        class='preview'
        {{drawPreview this.hint}}
        aria-hidden='true'
      ></canvas>
      <figcaption class='facts'>
        {{#if this.hint}}
          <span class='fact'><b>{{clock @model.duration}}</b></span>
          <span class='fact'><b>{{@model.bpm}}</b> bpm</span>
          <span class='fact'>downbeat <b>{{@model.downbeat}}</b> s</span>
          <span class='fact'><b>{{this.count}}</b> eighths</span>
        {{else}}
          <span class='fact'>not measured yet</span>
        {{/if}}
      </figcaption>
    </figure>
    <style scoped>
      .mix {
        margin: 0;
        display: grid;
        gap: 8px;
      }
      .preview {
        width: 100%;
        height: 64px;
        display: block;
        background: #d4dce7;
        border-radius: 3px;
      }
      .facts {
        display: flex;
        flex-wrap: wrap;
        gap: 4px 14px;
        font:
          400 10px/1.4 'Martian Mono',
          ui-monospace,
          'SF Mono',
          Menlo,
          monospace;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: #5a606b;
        font-variant-numeric: tabular-nums;
      }
      .fact b {
        font-weight: 500;
        color: #141418;
      }
    </style>
  </template>
}

/** "4:36 · 90 BPM" */
class Atom extends Component<typeof MixAnalysis> {
  <template>
    <span class='mix-atom'>
      {{#if @model.duration}}
        <span class='dot' aria-hidden='true'></span>{{clock @model.duration}}
        ·
        {{@model.bpm}}
        BPM
      {{else}}
        not measured
      {{/if}}
    </span>
    <style scoped>
      .mix-atom {
        font:
          400 0.8em/1 'Martian Mono',
          ui-monospace,
          'SF Mono',
          Menlo,
          monospace;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      .dot {
        display: inline-block;
        width: 0.55em;
        height: 0.55em;
        margin-right: 0.5em;
        border-radius: 50%;
        background: #ff2d4f;
        box-shadow: -2px 0 0 #19dbef;
        vertical-align: 0.05em;
      }
    </style>
  </template>
}

/**
 * A mix, measured: the waveform the scrubber draws and the tempo map the
 * bouncing dot lands on. The grid (BPM, first downbeat) is set by ear;
 * "Measure" decodes the mix with Web Audio and follows the drums from it.
 */
export class MixAnalysis extends FieldDef {
  static displayName = 'Mix analysis';
  static icon = MusicIcon;

  /** the bar grid, set by ear: tempo, and the second of the first downbeat */
  @field bpm = contains(NumberField);
  @field downbeat = contains(NumberField);
  /** measured */
  @field duration = contains(NumberField);
  /** loudness in 480 bars, 0.04..1, space separated */
  @field peaks = contains(StringField);
  /** every eighth note's second, its onset strength 0..1, and 0/1/2 off-eighth/beat/bar */
  @field eighths = contains(StringField);
  @field strength = contains(StringField);
  @field beat = contains(StringField);
  @field measuredAt = contains(StringField);

  static embedded = Embedded;
  static atom = Atom;
}

/** set the grid, measure the mix, and see what came out */
export class MixAnalysisEditor extends Component<{
  Args: {
    model: MixAnalysis | undefined;
    fields: any;
    /** the linked mix file */
    url: string;
  };
}> {
  @tracked busy = false;
  @tracked status = '';

  get hint() {
    return hintOf(this.args.model);
  }

  get facts() {
    const m = this.args.model;
    const h = this.hint;
    if (!m || !h) return 'Not measured yet';
    return `${fmt(m.duration)} · ${h.eighths.length} eighths · measured ${m.measuredAt?.slice(0, 16).replace('T', ' ') ?? ''}`;
  }

  measure = async (estimate: boolean) => {
    if (!this.args.url || this.busy) return;
    this.busy = true;
    try {
      const a = this.args.model;
      if (!a) return;
      this.status = 'Decoding…';
      const { x, sr } = await decodeMono(this.args.url);
      this.status = 'Following the drums…';
      const grid = estimate
        ? {}
        : { bpm: a.bpm ?? undefined, downbeat: a.downbeat ?? undefined };
      const m = await measure(x, sr, grid);
      a.bpm = m.bpm;
      a.downbeat = m.downbeat;
      a.duration = m.duration;
      a.peaks = packNumbers(m.peaks);
      a.eighths = packNumbers(m.eighths);
      a.strength = packNumbers(m.strength);
      a.beat = packNumbers(m.beat);
      a.measuredAt = new Date().toISOString();
      this.status = estimate
        ? `Estimated ${m.bpm} BPM, downbeat ${m.downbeat} s: check it by ear`
        : 'Measured';
    } catch (e) {
      this.status = `Couldn't measure: ${String(e)}`;
    } finally {
      this.busy = false;
    }
  };

  <template>
    <div class='editor'>
      <div class='grid'>
        <label>BPM <@fields.bpm /></label>
        <label>First downbeat (s) <@fields.downbeat /></label>
      </div>
      <canvas class='preview' {{drawPreview this.hint}}></canvas>
      <div class='row'>
        <button
          type='button'
          disabled={{this.busy}}
          {{on 'click' (fn this.measure false)}}
        >
          Measure mix
        </button>
        <button
          type='button'
          class='quiet'
          disabled={{this.busy}}
          {{on 'click' (fn this.measure true)}}
        >
          Estimate the grid
        </button>
        <span class='facts'>{{if this.status this.status this.facts}}</span>
      </div>
    </div>
    <style scoped>
      .editor {
        display: grid;
        gap: 10px;
      }
      .grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 12px;
      }
      label {
        display: grid;
        gap: 4px;
        font: 600 12px/1.3 var(--boxel-font-family, system-ui);
        color: #3b4049;
      }
      .preview {
        width: 100%;
        height: 72px;
        display: block;
        background: #f3f5f8;
        border-radius: 6px;
      }
      .row {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        align-items: center;
      }
      button {
        font: 600 13px/1 var(--boxel-font-family, system-ui);
        padding: 9px 14px;
        border-radius: 6px;
        border: 0;
        background: #141418;
        color: #fff;
        cursor: pointer;
      }
      button.quiet {
        background: transparent;
        color: #141418;
        box-shadow: inset 0 0 0 1px #c8ccd4;
      }
      button:disabled {
        opacity: 0.5;
        cursor: progress;
      }
      .facts {
        font: 500 12px/1.4 var(--boxel-font-family, system-ui);
        color: #5a606b;
        font-variant-numeric: tabular-nums;
      }
    </style>
  </template>
}
