// One person's response to a video question: their reaction second by
// second (worked out on their device; no picture of their face is kept), the
// moments the interviewer asked about with their answers, and the readout for
// whoever wants to sell to them. Replay the video with the reaction under it.
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import ScanFaceIcon from '@cardstack/boxel-icons/scan-face';
import { VideoQuestion } from './video-question';
import { ReactionTimeline } from './reaction';
import { clock, KIND_WORDS } from './face-signals';
import type { Bin } from './face-signals';
import type { FollowUp, Readout } from './survey-ai';
import { videoBlobUrl, grabFrames, parse, inPrerender } from './media';

class Isolated extends Component<typeof VideoResponse> {
  @tracked src = '';
  @tracked note = '';
  @tracked now = 0;
  @tracked thumbs: { t: number; url: string }[] = [];
  video: HTMLVideoElement | null = null;
  private loadedFor = '';

  get bins(): Bin[] {
    return parse<Bin[]>(this.args.model.bins, []);
  }
  get followUps(): FollowUp[] {
    return parse<FollowUp[]>(this.args.model.followUps, []);
  }
  get readout(): Readout | null {
    return parse<Readout | null>(this.args.model.readout, null);
  }
  get duration() {
    return this.args.model.duration || 0;
  }
  get pins() {
    return this.followUps.map((f) => ({
      t: f.t,
      label: KIND_WORDS[f.kind as keyof typeof KIND_WORDS] ?? f.kind,
    }));
  }
  get qas() {
    return this.followUps.map((f, i) => ({
      ...f,
      n: i + 1,
      time: clock(f.t),
      what: KIND_WORDS[f.kind as keyof typeof KIND_WORDS] ?? f.kind,
    }));
  }
  get when() {
    const d = this.args.model.takenAt
      ? new Date(this.args.model.takenAt)
      : null;
    return d && !isNaN(d.getTime())
      ? d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
      : '';
  }
  get videoUrl() {
    const q = this.args.model.question as VideoQuestion | undefined;
    return q?.videoFile ? new URL(q.videoFile, (q as any).id).href : '';
  }
  get measured() {
    if (!this.args.model.camera) return 'Answers only (camera off)';
    return this.args.model.calibrated
      ? 'Face and gaze, calibrated'
      : 'Face only (no gaze calibration)';
  }

  load = modifier((_el: Element, [url]: [string]) => {
    if (inPrerender() || !url || this.loadedFor === url) return;
    this.loadedFor = url;
    this.note = 'Loading the video…';
    videoBlobUrl(
      url,
      (f) => (this.note = `Loading the video… ${Math.round(f * 100)}%`),
    )
      .then(async (src) => {
        this.src = src;
        this.note = '';
        const d = this.duration || 30;
        const n = 12;
        const times = Array.from({ length: n }, (_, i) => ((i + 0.5) / n) * d);
        const urls = await grabFrames(src, times, 200);
        this.thumbs = urls.map((url, i) => ({ t: times[i], url }));
      })
      .catch((e) => (this.note = String(e?.message ?? e)));
  });
  registerVideo = modifier((el: HTMLVideoElement) => {
    this.video = el;
    const tick = () => (this.now = el.currentTime);
    el.addEventListener('timeupdate', tick);
    el.addEventListener('seeked', tick);
    return () => {
      el.removeEventListener('timeupdate', tick);
      el.removeEventListener('seeked', tick);
    };
  });
  seek = (t: number) => {
    if (this.video) {
      this.video.currentTime = t;
      this.now = t;
    }
  };

  <template>
    <article class='sv vr' {{this.load this.videoUrl}}>
      <header class='top'>
        <p class='kicker'>Video response{{#if @model.question}}
            ·
            {{@model.question.cardTitle}}{{/if}}</p>
        <h1>{{if @model.respondent @model.respondent 'Anonymous viewer'}}</h1>
        <p class='meta'>{{this.when}} · {{this.measured}}</p>
      </header>

      {{#if this.readout}}
        <section class='readout'>
          {{#if this.readout.label}}<p
              class='badge'
            >{{this.readout.label}}</p>{{/if}}
          <p class='headline'>{{this.readout.headline}}</p>
          <div class='cols'>
            <div>
              <h2>Landed</h2>
              <ul>{{#each this.readout.landed as |x|}}<li
                  >{{x}}</li>{{/each}}</ul>
            </div>
            <div>
              <h2>Lost them</h2>
              <ul>{{#each this.readout.lost as |x|}}<li>{{x}}</li>{{/each}}</ul>
            </div>
          </div>
          <div class='sell'>
            <p><b>Lead with</b> {{this.readout.leadWith}}</p>
            <p><b>Avoid</b> {{this.readout.avoid}}</p>
            <blockquote>{{this.readout.pitch}}</blockquote>
          </div>
        </section>
      {{/if}}

      <section class='replay'>
        <div class='player'>
          {{#if this.src}}
            {{! template-lint-disable require-media-caption }}
            <video
              src={{this.src}}
              controls
              playsinline
              {{this.registerVideo}}
            ></video>
          {{else}}
            <p class='loading'>{{if this.note this.note 'No video linked.'}}</p>
          {{/if}}
        </div>
        <ReactionTimeline
          @bins={{this.bins}}
          @duration={{this.duration}}
          @thumbs={{this.thumbs}}
          @pins={{this.pins}}
          @cursor={{this.now}}
          @onSeek={{this.seek}}
          @camera={{@model.camera}}
        />
      </section>

      {{#if this.qas.length}}
        <section class='qa'>
          <h2>What we asked</h2>
          <ol>
            {{#each this.qas as |f|}}
              <li>
                <button
                  type='button'
                  class='at'
                  {{on 'click' (fn this.seek f.t)}}
                >{{f.time}}</button>
                <div>
                  <p class='why'>{{f.what}}</p>
                  <p class='q'>{{f.question}}</p>
                  <p class='a'>{{if f.answer f.answer '(skipped)'}}</p>
                </div>
              </li>
            {{/each}}
          </ol>
        </section>
      {{/if}}
      <p class='privacy'>Measured on the viewer's own device. No image of their
        face was saved or sent; only the numbers above.</p>
    </article>
    <style scoped>
      .sv {
        --sv-paper: #fbfaf7;
        --sv-panel: #ffffff;
        --sv-ink: #1d1c1a;
        --sv-muted: #6b675f;
        --sv-rule: #e4e0d8;
        --sv-live: #e2553b;
        --sv-att: #2f7d74;
        --sv-smile: #d48a1a;
        --sv-surprise: #7a55c9;
        --sv-frown: #4a6a9a;
        --sv-sans:
          ui-sans-serif, -apple-system, 'Segoe UI', system-ui, sans-serif;
        --sv-mono: ui-monospace, 'SF Mono', Menlo, monospace;
        container-type: inline-size;
        background: var(--sv-paper);
        color: var(--sv-ink);
        font-family: var(--sv-sans);
        box-sizing: border-box;
      }
      .vr {
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 28px;
        max-width: 980px;
        margin: 0 auto;
      }
      .top h1 {
        margin: 2px 0 4px;
        font: 600 28px/1.15 var(--sv-sans);
        letter-spacing: -0.01em;
      }
      .kicker,
      .meta {
        margin: 0;
        color: var(--sv-muted);
        font-size: 13px;
      }
      .readout {
        display: grid;
        gap: 14px;
        padding: 20px;
        border-radius: 14px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .badge {
        justify-self: start;
        margin: 0;
        padding: 4px 10px;
        border-radius: 999px;
        background: var(--sv-ink);
        color: var(--sv-paper);
        font: 600 12px/1.4 var(--sv-sans);
      }
      .headline {
        margin: 0;
        font: 500 19px/1.4 var(--sv-sans);
      }
      .cols {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 20px;
      }
      h2 {
        margin: 0 0 6px;
        font: 600 12px/1.3 var(--sv-sans);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--sv-muted);
      }
      ul {
        margin: 0;
        padding-left: 18px;
        display: grid;
        gap: 4px;
        line-height: 1.45;
      }
      .sell {
        display: grid;
        gap: 6px;
        border-top: 1px solid var(--sv-rule);
        padding-top: 14px;
      }
      .sell p {
        margin: 0;
        line-height: 1.45;
      }
      .sell b {
        display: inline-block;
        min-width: 76px;
        font-weight: 600;
      }
      blockquote {
        margin: 6px 0 0;
        padding: 12px 14px;
        border-left: 3px solid var(--sv-live);
        background: var(--sv-paper);
        border-radius: 0 8px 8px 0;
        font-style: italic;
        line-height: 1.5;
      }
      .replay {
        display: grid;
        gap: 14px;
      }
      .player {
        aspect-ratio: 16 / 9;
        background: #111;
        border-radius: 12px;
        overflow: hidden;
        display: grid;
        place-items: center;
      }
      .player video {
        width: 100%;
        height: 100%;
        object-fit: contain;
        display: block;
      }
      .loading {
        color: #bbb;
        font-size: 13px;
      }
      .qa ol {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 14px;
      }
      .qa li {
        display: grid;
        grid-template-columns: 64px 1fr;
        gap: 12px;
        align-items: start;
      }
      .at {
        font: 600 12px/1 var(--sv-mono);
        padding: 7px 8px;
        border-radius: 8px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-panel);
        color: var(--sv-ink);
        cursor: pointer;
      }
      .at:hover {
        border-color: var(--sv-live);
      }
      .why {
        margin: 0;
        font-size: 12px;
        color: var(--sv-muted);
      }
      .q {
        margin: 2px 0;
        font-weight: 600;
        line-height: 1.4;
      }
      .a {
        margin: 0;
        line-height: 1.5;
      }
      .privacy {
        margin: 0;
        color: var(--sv-muted);
        font-size: 12px;
      }
      @container (max-width: 640px) {
        .cols {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

class Embedded extends Component<typeof VideoResponse> {
  get readout(): Readout | null {
    return parse<Readout | null>(this.args.model.readout, null);
  }
  <template>
    <div class='sv ve'>
      <div class='row'>
        <b>{{if @model.respondent @model.respondent 'Anonymous viewer'}}</b>
        {{#if this.readout.label}}<span
            class='badge'
          >{{this.readout.label}}</span>{{/if}}
      </div>
      <p>{{if
          this.readout.headline
          this.readout.headline
          'No readout yet.'
        }}</p>
    </div>
    <style scoped>
      .sv {
        --sv-paper: #fbfaf7;
        --sv-panel: #ffffff;
        --sv-ink: #1d1c1a;
        --sv-muted: #6b675f;
        --sv-rule: #e4e0d8;
        --sv-live: #e2553b;
        --sv-att: #2f7d74;
        --sv-smile: #d48a1a;
        --sv-surprise: #7a55c9;
        --sv-frown: #4a6a9a;
        --sv-sans:
          ui-sans-serif, -apple-system, 'Segoe UI', system-ui, sans-serif;
        --sv-mono: ui-monospace, 'SF Mono', Menlo, monospace;
        container-type: inline-size;
        background: var(--sv-paper);
        color: var(--sv-ink);
        font-family: var(--sv-sans);
        box-sizing: border-box;
      }
      .ve {
        padding: 12px 14px;
        display: grid;
        gap: 4px;
        height: 100%;
        box-sizing: border-box;
        overflow: hidden;
      }
      .row {
        display: flex;
        gap: 8px;
        align-items: center;
        min-width: 0;
      }
      .row b {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .badge {
        flex: none;
        padding: 2px 8px;
        border-radius: 999px;
        background: var(--sv-ink);
        color: var(--sv-paper);
        font-size: 11px;
        font-weight: 600;
      }
      p {
        margin: 0;
        color: var(--sv-muted);
        font-size: 13px;
        line-height: 1.4;
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
    </style>
  </template>
}

export class VideoResponse extends CardDef {
  static displayName = 'Video Response';
  static icon = ScanFaceIcon;
  @field question = linksTo(() => VideoQuestion);
  @field respondent = contains(StringField);
  @field takenAt = contains(StringField);
  @field camera = contains(BooleanField);
  @field calibrated = contains(BooleanField);
  @field duration = contains(NumberField);
  @field bins = contains(TextAreaField); // JSON: Bin[] per quarter second
  @field followUps = contains(TextAreaField); // JSON: FollowUp[]
  @field readout = contains(TextAreaField); // JSON: Readout
  @field summary = contains(TextAreaField); // for the interviewer
  @field cardTitle = contains(StringField, {
    computeVia: function (this: VideoResponse) {
      const who = this.respondent || 'Anonymous viewer';
      return this.question?.cardTitle
        ? `${who} · ${this.question.cardTitle}`
        : who;
    },
  });
  static isolated = Isolated;
  static embedded = Embedded;
  static fitted = Embedded;
}
