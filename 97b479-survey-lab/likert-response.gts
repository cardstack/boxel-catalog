// One person's adaptive Likert: for each statement, their words, where the
// AI placed them (ring), where they moved it (diamond), where fine-tuning
// settled (dot), and the in-between statements they chose. Plus the readout.
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import UserCheckIcon from '@cardstack/boxel-icons/user-check';
import { LikertQuestion } from './likert-question';
import { LikertStrip } from './likert-scale';
import { pointLabel, ladderLabel } from './likert-ai';
import type { LikertItem, LikertReadout } from './likert-ai';
import { parse } from './media';

class Isolated extends Component<typeof LikertResponse> {
  get readout(): LikertReadout | null {
    return parse<LikertReadout | null>(this.args.model.readout, null);
  }
  get items() {
    return parse<LikertItem[]>(this.args.model.items, []).map((it, i) => {
      const ladder = it.scale === 'ladder' && (it.rungs?.length ?? 0) > 1;
      const steps = ladder ? it.rungs!.length - 1 : 6;
      return {
        ...it,
        n: i + 1,
        ladder,
        labels: ladder ? it.rungs : undefined,
        finalLabel:
          it.final === null
            ? 'Skipped'
            : ladder
              ? `Ended ${ladderLabel(it.final, it.rungs!)}`
              : `${it.point} of 7 · ${pointLabel(it.final)}`,
        gapNote:
          it.aiPos !== null &&
          it.selfPos !== null &&
          Math.abs(it.selfPos - it.aiPos) > 0.02
            ? `Moved the AI's guess ${it.selfPos > it.aiPos ? 'up' : 'down'} by ${(Math.abs(it.selfPos - it.aiPos) * steps).toFixed(1)} ${ladder ? 'rungs' : 'points'}.`
            : it.aiPos !== null
              ? 'Agreed with where the AI placed them.'
              : 'Used the scale directly.',
        picks: it.probes.map((p) => ({
          ...p,
          lowOn: p.picked === 'low',
          highOn: p.picked === 'high',
          note:
            p.picked === 'between'
              ? 'Somewhere between'
              : p.picked === 'skip'
                ? 'Skipped'
                : '',
          verdict:
            p.picked === 'below'
              ? 'Lower than'
              : p.picked === 'above'
                ? 'Higher than'
                : p.picked === 'here'
                  ? 'About'
                  : 'Skipped',
          secs: (p.ms / 1000).toFixed(1),
        })),
      };
    });
  }
  get when() {
    const d = this.args.model.takenAt
      ? new Date(this.args.model.takenAt)
      : null;
    return d && !isNaN(d.getTime())
      ? d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
      : '';
  }

  <template>
    <article class='sv lr'>
      <header>
        <p class='kicker'>Likert response{{#if @model.question}}
            ·
            {{@model.question.cardTitle}}{{/if}}</p>
        <h1>{{if @model.respondent @model.respondent 'Anonymous'}}</h1>
        <p class='kicker'>{{this.when}}</p>
      </header>

      {{#if @model.summary}}<p class='forint'>{{@model.summary}}</p>{{/if}}

      {{#if this.readout}}
        <section class='readout'>
          {{#if this.readout.label}}<p
              class='badge'
            >{{this.readout.label}}</p>{{/if}}
          <p class='headline'>{{this.readout.headline}}</p>
          <div class='cols'>
            <div>
              <h2>For</h2>
              <ul>{{#each this.readout.for as |x|}}<li>{{x}}</li>{{/each}}</ul>
            </div>
            <div>
              <h2>Doubts</h2>
              <ul>{{#each this.readout.against as |x|}}<li
                  >{{x}}</li>{{/each}}</ul>
            </div>
          </div>
          <div class='sell'>
            <p><b>Lead with</b> {{this.readout.leadWith}}</p>
            <p><b>Avoid</b> {{this.readout.avoid}}</p>
            <blockquote>{{this.readout.pitch}}</blockquote>
          </div>
        </section>
      {{/if}}

      <section class='items'>
        {{#each this.items as |it|}}
          <div class='item'>
            <p class='st'><span class='n'>{{it.n}}</span>{{it.statement}}</p>
            {{#if it.answer}}<p class='said'>“{{it.answer}}”</p>{{/if}}
            <LikertStrip
              @aiPos={{it.aiPos}}
              @selfPos={{it.selfPos}}
              @final={{it.final}}
              @labels={{it.labels}}
            />
            <p class='fin'><b>{{it.finalLabel}}</b>
              ·
              {{it.gapNote}}{{#if it.frustrated}}
                Sounded done with questions, so fine-tuning was skipped.{{/if}}</p>
            {{#if it.aiWhy}}<p class='why'>AI: {{it.aiWhy}}</p>{{/if}}
            {{#each it.picks as |pk|}}
              {{#if it.ladder}}
                <p class='rung'><b>{{pk.verdict}}</b>
                  {{pk.anchor}}
                  <em>{{pk.secs}} s</em></p>
              {{else}}
                <div class='pick'>
                  <span class='{{if pk.lowOn "chosen"}}'>{{pk.low}}</span>
                  <span class='{{if pk.highOn "chosen"}}'>{{pk.high}}</span>
                  <em>{{#if pk.note}}{{pk.note}} · {{/if}}{{pk.secs}} s</em>
                </div>
              {{/if}}
            {{/each}}
          </div>
        {{/each}}
      </section>
      <p class='legend'><span class='k ring'></span>where the AI placed them
        <span class='k dia'></span>where they moved it
        <span class='k dot'></span>final</p>
    </article>
    <style scoped>
      .forint {
        margin: 0;
        padding: 14px 16px;
        border-left: 3px solid #e2553b;
        background: #fff;
        border-radius: 0 10px 10px 0;
        line-height: 1.55;
      }
      .sv {
        --sv-paper: #fbfaf7;
        --sv-panel: #ffffff;
        --sv-ink: #1d1c1a;
        --sv-muted: #6b675f;
        --sv-rule: #e4e0d8;
        --sv-live: #e2553b;
        --sv-surprise: #7a55c9;
        --sv-sans:
          ui-sans-serif, -apple-system, 'Segoe UI', system-ui, sans-serif;
        container-type: inline-size;
        background: var(--sv-paper);
        color: var(--sv-ink);
        font-family: var(--sv-sans);
        box-sizing: border-box;
      }
      .lr {
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 24px;
        max-width: 880px;
        margin: 0 auto;
      }
      h1 {
        margin: 2px 0 4px;
        font: 600 28px/1.15 var(--sv-sans);
        letter-spacing: -0.01em;
      }
      .kicker {
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
      .items {
        display: grid;
        gap: 14px;
      }
      .item {
        display: grid;
        gap: 10px;
        padding: 18px;
        border-radius: 12px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .st {
        margin: 0;
        font-weight: 600;
        line-height: 1.4;
        display: flex;
        gap: 10px;
      }
      .n {
        flex: none;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        display: grid;
        place-items: center;
        background: var(--sv-paper);
        border: 1px solid var(--sv-rule);
        font-size: 12px;
      }
      .said {
        margin: 0;
        font-style: italic;
        line-height: 1.5;
      }
      .fin,
      .why {
        margin: 0;
        font-size: 14px;
        line-height: 1.45;
      }
      .why {
        color: var(--sv-muted);
        font-size: 13px;
      }
      .pick {
        display: grid;
        grid-template-columns: 1fr 1fr auto;
        gap: 8px;
        align-items: start;
        font-size: 13px;
        line-height: 1.4;
      }
      .pick span {
        padding: 8px 10px;
        border-radius: 8px;
        border: 1px dashed var(--sv-rule);
        color: var(--sv-muted);
      }
      .pick span.chosen {
        border: 1.5px solid var(--sv-ink);
        color: var(--sv-ink);
        background: var(--sv-paper);
      }
      .pick em {
        color: var(--sv-muted);
        font-style: normal;
        white-space: nowrap;
        padding-top: 8px;
      }
      .rung {
        margin: 0;
        padding: 8px 10px;
        border-radius: 8px;
        border: 1px dashed var(--sv-rule);
        font-size: 13px;
        line-height: 1.4;
      }
      .rung em {
        color: var(--sv-muted);
        font-style: normal;
        margin-left: 6px;
      }
      .legend {
        margin: 0;
        display: flex;
        gap: 8px;
        align-items: center;
        flex-wrap: wrap;
        color: var(--sv-muted);
        font-size: 12px;
      }
      .k {
        display: inline-block;
        width: 11px;
        height: 11px;
        box-sizing: border-box;
        margin-left: 8px;
      }
      .k:first-child {
        margin-left: 0;
      }
      .ring {
        border-radius: 50%;
        border: 2px solid var(--sv-surprise);
      }
      .dia {
        transform: rotate(45deg);
        border: 2px solid var(--sv-ink);
        width: 9px;
        height: 9px;
      }
      .dot {
        border-radius: 50%;
        background: var(--sv-live);
      }
      @container (max-width: 600px) {
        .cols,
        .pick {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

class Embedded extends Component<typeof LikertResponse> {
  get readout(): LikertReadout | null {
    return parse<LikertReadout | null>(this.args.model.readout, null);
  }
  <template>
    <div class='le'>
      <div class='row'>
        <b>{{if @model.respondent @model.respondent 'Anonymous'}}</b>
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
      .le {
        height: 100%;
        box-sizing: border-box;
        padding: 12px 14px;
        display: grid;
        gap: 4px;
        align-content: start;
        overflow: hidden;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
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
        background: #1d1c1a;
        color: #fbfaf7;
        font-size: 11px;
        font-weight: 600;
      }
      p {
        margin: 0;
        color: #6b675f;
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

export class LikertResponse extends CardDef {
  static displayName = 'Likert Response';
  static icon = UserCheckIcon;
  @field question = linksTo(() => LikertQuestion);
  @field respondent = contains(StringField);
  @field takenAt = contains(StringField);
  @field items = contains(TextAreaField); // JSON: LikertItem[]
  @field readout = contains(TextAreaField); // JSON: LikertReadout
  @field summary = contains(TextAreaField); // for the interviewer
  @field cardTitle = contains(StringField, {
    computeVia: function (this: LikertResponse) {
      const who = this.respondent || 'Anonymous';
      return this.question?.cardTitle
        ? `${who} · ${this.question.cardTitle}`
        : who;
    },
  });
  static isolated = Isolated;
  static embedded = Embedded;
  static fitted = Embedded;
}
