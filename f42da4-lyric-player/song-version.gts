import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import FileDef from '@cardstack/base/file-api';
import StringField from '@cardstack/base/string';

import { htmlSafe, type SafeString } from '@ember/template';
import FileMusicIcon from '@cardstack/boxel-icons/file-music';

import {
  MixAnalysis,
  MixAnalysisEditor,
  clock,
  drawPreview,
  hintOf,
  lyricFonts,
  type MixHint,
} from './mix-analysis';
import { LyricLine, LyricTimingEditor, songLyricsOf } from './lyrics-field';
import type { SongLyrics } from './lyric-types';

class Edit extends Component<typeof SongVersion> {
  get url() {
    return this.args.model.mix?.url ?? '';
  }
  get vocalsUrl() {
    return this.args.model.vocals?.url ?? '';
  }
  get eighths() {
    return this.args.model.hint?.eighths ?? [];
  }
  get beat() {
    return this.args.model.hint?.beat ?? [];
  }
  <template>
    <div class='sv-edit'>
      <div class='row'>
        <label>Name <@fields.name /></label>
        <label>Language code <@fields.language /></label>
      </div>
      <section>
        <h2>Mix</h2>
        <@fields.mix />
      </section>
      <section>
        <h2>Vocal stem (for word timing)</h2>
        <@fields.vocals />
      </section>
      <section>
        <h2>Waveform and tempo map</h2>
        <MixAnalysisEditor
          @model={{@model.analysis}}
          @fields={{@fields.analysis}}
          @url={{this.url}}
        />
      </section>
      <section>
        <h2>Lyrics and word timing</h2>
        <LyricTimingEditor
          @lines={{@model.lines}}
          @url={{this.url}}
          @vocalsUrl={{this.vocalsUrl}}
          @eighths={{this.eighths}}
          @beat={{this.beat}}
        />
      </section>
    </div>
    <style scoped>
      .sv-edit {
        display: grid;
        gap: 24px;
        padding: 24px;
        font-family: var(--boxel-font-family, system-ui);
      }
      .row {
        display: grid;
        grid-template-columns: 2fr 1fr;
        gap: 12px;
      }
      section {
        display: grid;
        gap: 10px;
      }
      h2 {
        margin: 0;
        font-size: 15px;
      }
      label {
        display: grid;
        gap: 4px;
        font-size: 12px;
        font-weight: 600;
        color: #3b4049;
      }
    </style>
  </template>
}

/** what every format shows: the version's code, its measured facts, its fonts */
class Base extends Component<typeof SongVersion> {
  get code(): string {
    const m = this.args.model;
    return (m.language || m.name || '··').slice(0, 2).toUpperCase();
  }
  get mixUrl(): string | undefined {
    return this.args.model.mix?.url ?? undefined;
  }
  get hint(): MixHint | undefined {
    return this.args.model.hint;
  }
  get duration(): string {
    return clock(this.args.model.analysis?.duration);
  }
  get bpm(): number | null | undefined {
    return this.args.model.analysis?.bpm;
  }
  get eighths(): number {
    return this.hint?.eighths.length ?? 0;
  }
  get bars(): number {
    return this.hint?.beat.filter((b) => b === 2).length ?? 0;
  }
}

class Isolated extends Base {
  get fileName(): string {
    const url = this.mixUrl ?? '';
    return decodeURIComponent(url.split('/').pop() ?? '') || 'No mix linked';
  }
  get seconds(): string {
    const d = this.args.model.analysis?.duration;
    return d ? `${d.toFixed(2)} s` : '';
  }
  get measured(): string {
    const at = this.args.model.analysis?.measuredAt;
    return at ? `${at.slice(0, 10)} · ${at.slice(11, 16)} UTC` : 'Not yet';
  }
  /** a label under the waveform at every minute */
  get ticks(): { label: string; style: SafeString }[] {
    const d = this.args.model.analysis?.duration;
    if (!d) return [];
    const out: { label: string; style: SafeString }[] = [];
    for (let t = 0; t < d - 15; t += 60) {
      out.push({
        label: t ? clock(t) : '0:00',
        style: htmlSafe(`left: ${(t / d) * 100}%`),
      });
    }
    return out;
  }

  <template>
    <article class='sv-page' {{lyricFonts this.mixUrl}}>
      <header class='top'>
        <span class='code'>{{this.code}}</span>
        <p class='eyebrow'><span class='dot' aria-hidden='true'></span>Song
          version ·
          {{if @model.language @model.language '—'}}</p>
      </header>
      <h1 class='name'>{{if @model.name @model.name 'Untitled version'}}</h1>

      <figure class='stage'>
        <canvas
          class='wave'
          {{drawPreview this.hint}}
          role='img'
          aria-label='Waveform and beat grid of the mix'
        ></canvas>
        <div class='axis' aria-hidden='true'>
          {{#each this.ticks as |t|}}
            <span class='tick' style={{t.style}}>{{t.label}}</span>
          {{/each}}
        </div>
        {{#unless this.hint}}
          <figcaption class='empty'>Not measured yet: open Edit and measure the
            mix.</figcaption>
        {{/unless}}
      </figure>

      <dl class='facts'>
        <div><dt>Duration</dt><dd>{{this.duration}}<small
            >{{this.seconds}}</small></dd></div>
        <div><dt>Tempo</dt><dd>{{if this.bpm this.bpm '—'}}<small
            >bpm</small></dd></div>
        <div><dt>First downbeat</dt><dd>{{if
              @model.analysis.downbeat
              @model.analysis.downbeat
              '—'
            }}<small>s</small></dd></div>
        <div><dt>Eighths</dt><dd>{{this.eighths}}<small>{{this.bars}}
              bars</small></dd></div>
        <div><dt>Measured</dt><dd class='date'>{{this.measured}}</dd></div>
      </dl>

      <section class='mix'>
        <p class='eyebrow'>Mix</p>
        <p class='file'>{{this.fileName}}</p>
        {{#if this.mixUrl}}
          <audio
            class='player'
            controls
            preload='none'
            src={{this.mixUrl}}
          ><track kind='captions' /></audio>
        {{/if}}
      </section>
    </article>
    <style scoped>
      .sv-page {
        --ground: #d4dce7;
        --ink: #141418;
        --red: #ff2d4f;
        --cyan: #19dbef;
        --lyric:
          Pretendard, system-ui, -apple-system, 'Helvetica Neue', sans-serif;
        --mono: 'Martian Mono', ui-monospace, 'SF Mono', Menlo, monospace;
        height: 100%;
        overflow-y: auto;
        container-type: inline-size;
        display: grid;
        align-content: start;
        gap: 28px;
        padding: clamp(20px, 5%, 56px);
        font-family: var(--lyric);
      }
      .top {
        display: flex;
        align-items: center;
        gap: 14px;
      }
      .code {
        background: var(--ink);
        color: #fff;
        font: 500 13px/1 var(--lyric);
        letter-spacing: 0.04em;
        padding: 6px 8px 5px;
      }
      .eyebrow {
        margin: 0;
        font: 400 11px/1.3 var(--mono);
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: #5a606b;
      }
      .dot {
        display: inline-block;
        width: 7px;
        height: 7px;
        margin-right: 9px;
        border-radius: 50%;
        background: var(--red);
        box-shadow: -2px 0 0 var(--cyan);
        vertical-align: 1px;
      }
      .name {
        margin: -8px 0 0;
        font: 200 clamp(44px, 11cqi, 104px)/0.95 var(--lyric);
        letter-spacing: -0.02em;
        text-transform: lowercase;
        color: var(--ink);
      }
      .stage {
        margin: 0;
        position: relative;
        background: var(--ground);
        padding: 28px 24px 34px;
      }
      .wave {
        display: block;
        width: 100%;
        height: 220px;
      }
      .axis {
        position: relative;
        height: 0;
      }
      .tick {
        position: absolute;
        top: 10px;
        transform: translateX(-50%);
        font: 400 10px/1 var(--mono);
        letter-spacing: 0.08em;
        color: #5a606b;
        font-variant-numeric: tabular-nums;
      }
      .tick:first-child {
        transform: none;
      }
      .empty {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        font: 400 12px/1.4 var(--mono);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: #5a606b;
      }
      .facts {
        margin: 0;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
        gap: 1px;
        background: #c3ccd8;
        border-block: 1px solid #c3ccd8;
      }
      .facts > div {
        background: var(--background, #fff);
        padding: 14px 16px 16px;
        display: grid;
        gap: 8px;
        align-content: start;
      }
      dt {
        font: 400 10px/1.2 var(--mono);
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: #5a606b;
      }
      dd {
        margin: 0;
        font: 200 34px/1 var(--lyric);
        color: var(--ink);
        font-variant-numeric: tabular-nums;
      }
      dd small {
        margin-left: 6px;
        font: 400 10px/1 var(--mono);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: #5a606b;
      }
      dd.date {
        font: 400 13px/1.4 var(--mono);
        letter-spacing: 0.04em;
        padding-top: 10px;
      }
      .mix {
        display: grid;
        gap: 8px;
      }
      .file {
        margin: 0;
        font: 500 16px/1.3 var(--lyric);
        color: var(--ink);
        overflow-wrap: anywhere;
      }
      .player {
        width: 100%;
        max-width: 520px;
      }
    </style>
  </template>
}

class Embedded extends Base {
  <template>
    <article class='sv-embedded' {{lyricFonts this.mixUrl}}>
      <header class='head'>
        <span class='code'>{{this.code}}</span>
        <h3 class='name'>{{if @model.name @model.name 'Untitled version'}}</h3>
        <span class='dur'>{{this.duration}}</span>
      </header>
      <@fields.analysis @format='embedded' />
    </article>
    <style scoped>
      .sv-embedded {
        --lyric:
          Pretendard, system-ui, -apple-system, 'Helvetica Neue', sans-serif;
        --mono: 'Martian Mono', ui-monospace, 'SF Mono', Menlo, monospace;
        display: grid;
        gap: 12px;
        padding: 16px 18px 18px;
      }
      .head {
        display: flex;
        align-items: baseline;
        gap: 12px;
        min-width: 0;
      }
      .code {
        align-self: center;
        background: #141418;
        color: #fff;
        font: 500 11px/1 var(--lyric);
        letter-spacing: 0.04em;
        padding: 5px 6px 4px;
      }
      .name {
        margin: 0;
        flex: 1;
        min-width: 0;
        font: 200 30px/1 var(--lyric);
        letter-spacing: -0.01em;
        text-transform: lowercase;
        color: #141418;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .dur {
        font: 400 12px/1 var(--mono);
        letter-spacing: 0.08em;
        color: #141418;
        font-variant-numeric: tabular-nums;
      }
    </style>
  </template>
}

class Fitted extends Base {
  <template>
    <article class='fit' {{lyricFonts this.mixUrl}}>
      <header class='head'>
        <span class='code'>{{this.code}}</span>
        <span class='name'>{{if
            @model.name
            @model.name
            'Untitled version'
          }}</span>
        <span class='dur'>{{this.duration}}</span>
      </header>
      <canvas
        class='wave'
        {{drawPreview this.hint}}
        aria-hidden='true'
      ></canvas>
      <p class='meta'>
        <span class='dot' aria-hidden='true'></span>{{if this.bpm this.bpm '—'}}
        bpm ·
        {{this.bars}}
        bars
      </p>
    </article>
    <style scoped>
      .fit {
        --lyric:
          Pretendard, system-ui, -apple-system, 'Helvetica Neue', sans-serif;
        --mono: 'Martian Mono', ui-monospace, 'SF Mono', Menlo, monospace;
        width: 100%;
        height: 100%;
        overflow: hidden;
        display: grid;
        grid-template: 'head' auto 'wave' minmax(0, 1fr) 'meta' auto / minmax(
            0,
            1fr
          );
        gap: 10px;
        padding: 14px;
        background: #d4dce7;
        color: #141418;
      }
      .head {
        grid-area: head;
        display: flex;
        align-items: center;
        gap: 10px;
        min-width: 0;
        overflow: hidden;
      }
      .code {
        flex: none;
        background: #141418;
        color: #fff;
        font: 500 11px/1 var(--lyric);
        letter-spacing: 0.04em;
        padding: 5px 6px 4px;
      }
      .name {
        flex: 1;
        min-width: 0;
        font: 200 26px/1.05 var(--lyric);
        letter-spacing: -0.01em;
        text-transform: lowercase;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .dur,
      .meta {
        font: 400 10px/1.2 var(--mono);
        letter-spacing: 0.1em;
        text-transform: uppercase;
        font-variant-numeric: tabular-nums;
      }
      .dur {
        flex: none;
      }
      .wave {
        grid-area: wave;
        display: block;
        width: 100%;
        height: 100%;
        min-height: 0;
      }
      .meta {
        grid-area: meta;
        margin: 0;
        color: #5a606b;
        overflow: hidden;
        white-space: nowrap;
        text-overflow: ellipsis;
      }
      .dot {
        display: inline-block;
        width: 6px;
        height: 6px;
        margin-right: 7px;
        border-radius: 50%;
        background: #ff2d4f;
        box-shadow: -2px 0 0 #19dbef;
        vertical-align: 1px;
      }

      /* tile: the name stacks over the waveform, larger */
      @container fitted-card (width <= 260px) and (height > 130px) {
        .head {
          flex-wrap: wrap;
          row-gap: 12px;
          align-content: flex-start;
        }
        .name {
          flex-basis: 100%;
          order: 3;
          font-size: 30px;
          white-space: normal;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .dur {
          margin-left: auto;
        }
      }
      @container fitted-card (width > 260px) and (height > 200px) {
        .fit {
          padding: 20px;
          gap: 14px;
        }
        .name {
          font-size: 38px;
        }
      }
      /* strip: one row, the waveform beside the name */
      @container fitted-card (height <= 130px) {
        .fit {
          grid-template:
            'head wave' minmax(0, 1fr)
            'meta wave' auto / auto minmax(0, 1fr);
          column-gap: 14px;
          row-gap: 4px;
          padding: 10px 12px;
        }
        .head {
          align-self: end;
        }
        .name {
          font-size: 20px;
        }
        .dur {
          display: none;
        }
        .meta {
          align-self: start;
        }
      }
      @container fitted-card (height <= 80px) {
        .fit {
          grid-template: 'head wave' minmax(0, 1fr) / auto minmax(0, 1fr);
          padding: 6px 10px;
        }
        .head {
          align-self: center;
        }
        .meta {
          display: none;
        }
        .name {
          font-size: 17px;
          max-width: 12ch;
        }
      }
      @container fitted-card (height <= 80px) and (width <= 240px) {
        .fit {
          grid-template: 'head' 1fr / minmax(0, 1fr);
        }
        .wave {
          display: none;
        }
        .name {
          max-width: none;
        }
        .dur {
          display: block;
        }
      }
      /* badge */
      @container fitted-card (height <= 50px) {
        .fit {
          padding: 4px 8px;
        }
        .head {
          gap: 7px;
        }
        .code {
          font-size: 10px;
          padding: 4px 5px 3px;
        }
        .name {
          font-size: 15px;
        }
      }
      @container fitted-card (height <= 50px) and (width <= 170px) {
        .dur {
          display: none;
        }
      }
    </style>
  </template>
}

/** [EN] english 4:36 */
class Atom extends Base {
  <template>
    <span class='sv-atom' {{lyricFonts this.mixUrl}}>
      <span class='code'>{{this.code}}</span>
      <span class='name'>{{if
          @model.name
          @model.name
          'Untitled version'
        }}</span>
      <span class='dur'>{{this.duration}}</span>
    </span>
    <style scoped>
      .sv-atom {
        display: inline-flex;
        align-items: baseline;
        gap: 0.45em;
        white-space: nowrap;
      }
      .code {
        align-self: center;
        background: #141418;
        color: #fff;
        font:
          500 0.7em/1 Pretendard,
          system-ui,
          sans-serif;
        letter-spacing: 0.04em;
        padding: 0.3em 0.35em 0.25em;
      }
      .name {
        font:
          200 1em/1 Pretendard,
          system-ui,
          sans-serif;
        text-transform: lowercase;
      }
      .dur {
        font:
          400 0.75em/1 'Martian Mono',
          ui-monospace,
          'SF Mono',
          Menlo,
          monospace;
        letter-spacing: 0.06em;
        font-variant-numeric: tabular-nums;
        opacity: 0.75;
      }
    </style>
  </template>
}

/**
 * One language version of the song: its own mix, measured once (the
 * waveform and the tempo map the dot bounces on), and, next, its lyrics.
 */
export class SongVersion extends CardDef {
  static displayName = 'Song Version';
  static icon = FileMusicIcon;

  /** "한국어", "English" */
  @field name = contains(StringField);
  /** "ko", "en" */
  @field language = contains(StringField);
  @field mix = linksTo(FileDef);
  /** the vocal alone, for timing words: a clear waveform and its onsets */
  @field vocals = linksTo(FileDef);
  @field analysis = contains(MixAnalysis);
  /** the lyrics, line by line, every word timed to this mix */
  @field lines = containsMany(LyricLine);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: SongVersion) {
      return this.name ?? 'Song version';
    },
  });

  /** the lyrics in the shape the player reads */
  get songLyrics(): SongLyrics | undefined {
    return songLyricsOf(this.lines);
  }

  get hint(): MixHint | undefined {
    return hintOf(this.analysis);
  }

  static isolated = Isolated;
  static embedded = Embedded;
  static fitted = Fitted;
  static atom = Atom;
  static edit = Edit;
}
