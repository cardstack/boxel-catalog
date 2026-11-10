// Closed choice: the plain single- or multi-select, for when the interviewer
// needs the answer to stay inside a fixed set. The classic count per option
// comes out, plus what a form throws away: how long the first pick took, every
// change of mind on the way (picked, then dropped), the order picks were made
// in, and where each option sat on this person's screen (the order is shuffled
// per person, so position bias averages out and can be checked).
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import TextAreaField from '@cardstack/base/text-area';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import ListCheckIcon from '@cardstack/boxel-icons/list-checks';
import {
  saveResponse,
  lines,
  parseJson,
  secs,
  hostOf,
  type ToolHost,
} from './tool-kit';
import { readMedia } from './stimuli';

const here: string = import.meta.url;
export const OTHER = '__other__';

interface Move {
  option: string; // an option, or OTHER
  on: boolean; // picked (true) or dropped (false)
  ms: number; // since the options appeared
}
interface ChoiceData {
  multi: boolean;
  shown: string[]; // the order this person saw
  picks: string[]; // final, in the order they were picked
  other: string | null;
  moves: Move[];
  firstMs: number | null;
  doneMs: number;
}

const emptyData: ChoiceData = {
  multi: false,
  shown: [],
  picks: [],
  other: null,
  moves: [],
  firstMs: null,
  doneMs: 0,
};

function shuffle<T>(xs: T[]): T[] {
  const a = [...xs];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const optLabel = (o: string, other: string | null) =>
  o === OTHER ? `Other: "${other ?? ''}"` : o;

// what changed on the way: options picked and later dropped (or swapped away
// from, for a single choice)
function dropped(d: ChoiceData) {
  const final = new Set(d.picks);
  const out: string[] = [];
  for (const m of d.moves) {
    if (m.on && !final.has(m.option) && !out.includes(m.option))
      out.push(m.option);
  }
  return out;
}

export function choiceSummary(d: ChoiceData) {
  const parts: string[] = [];
  const names = d.picks.map((o) => optLabel(o, d.other));
  const gone = dropped(d).map((o) => optLabel(o, d.other));
  if (!d.picks.length) parts.push('Chose none of the options.');
  else if (d.multi)
    parts.push(`Picked ${names.length}, in this order: ${names.join(', ')}.`);
  else parts.push(`Chose ${names[0]}.`);
  if (d.firstMs !== null)
    parts.push(
      `First pick after ${secs(d.firstMs)}; done after ${secs(d.doneMs)}.`,
    );
  if (gone.length)
    parts.push(
      d.multi
        ? `Picked, then dropped: ${gone.join(', ')}.`
        : `Changed their mind; first went for ${gone.join(', then ')}.`,
    );
  else if (d.picks.length) parts.push('No changes of mind.');
  return parts.join(' ');
}

type Step = 'intro' | 'choose' | 'saving' | 'done';

class Isolated extends Component<typeof ChoiceQuestion> {
  @tracked tab: 'take' | 'results' = 'take';
  @tracked step: Step = 'intro';
  @tracked name = '';
  @tracked shown: string[] = [];
  @tracked picks: string[] = [];
  @tracked other = '';
  @tracked moves: Move[] = [];
  @tracked responseId = '';
  @tracked summary = '';
  @tracked error = '';
  started = 0;

  // inside an interview: no intro, straight to the question
  get host(): ToolHost | undefined {
    return hostOf(this.args);
  }
  constructor(owner: any, args: any) {
    super(owner, args);
    const h = hostOf(args);
    if (h) {
      this.name = h.respondent ?? '';
      this.start();
    }
  }

  get options() {
    return lines(this.args.model.options);
  }
  get multi() {
    return Boolean(this.args.model.multi);
  }
  get max() {
    const m = Number(this.args.model.maxPicks ?? 0);
    return this.multi && m > 0 ? m : this.multi ? 0 : 1;
  }
  get full() {
    return this.multi && this.max > 0 && this.picks.length >= this.max;
  }
  get hint() {
    if (!this.multi) return 'Pick one.';
    return this.max ? `Pick up to ${this.max}.` : 'Pick as many as apply.';
  }
  get media() {
    return readMedia((this.args.model as any).media);
  }
  get hasMedia() {
    return this.shown.some((o) => this.media[o]);
  }
  get tiles() {
    return this.shown.map((o) => {
      const on = this.picks.includes(o);
      return {
        o,
        on,
        off: !on && this.full,
        pic: this.media[o]?.image ?? null,
      };
    });
  }
  get otherOn() {
    return this.picks.includes(OTHER);
  }
  get otherOff() {
    return !this.otherOn && this.full;
  }
  get canFinish() {
    return (
      this.picks.length > 0 && (!this.otherOn || this.other.trim().length > 0)
    );
  }

  setName = (e: Event) => (this.name = (e.target as HTMLInputElement).value);
  setOther = (e: Event) => (this.other = (e.target as HTMLInputElement).value);
  start = () => {
    this.shown = this.args.model.shuffle ? shuffle(this.options) : this.options;
    this.picks = [];
    this.moves = [];
    this.other = '';
    this.error = '';
    this.started = performance.now();
    this.step = 'choose';
  };
  private log(option: string, isOn: boolean) {
    this.moves = [
      ...this.moves,
      { option, on: isOn, ms: Math.round(performance.now() - this.started) },
    ];
  }
  toggle = (o: string) => {
    if (this.picks.includes(o)) {
      this.picks = this.picks.filter((x) => x !== o);
      this.log(o, false);
      return;
    }
    if (!this.multi) {
      // a single choice swaps: the old pick counts as dropped
      for (const p of this.picks) this.log(p, false);
      this.picks = [o];
    } else {
      if (this.full) return;
      this.picks = [...this.picks, o];
    }
    this.log(o, true);
  };
  toggleOther = () => this.toggle(OTHER);
  finish = async () => {
    this.step = 'saving';
    const firstOn = this.moves.find((m) => m.on);
    const data: ChoiceData = {
      multi: this.multi,
      shown: this.shown,
      picks: this.picks,
      other: this.otherOn ? this.other.trim() : null,
      moves: this.moves,
      firstMs: firstOn ? firstOn.ms : null,
      doneMs: Math.round(performance.now() - this.started),
    };
    this.summary = choiceSummary(data);
    try {
      this.responseId = await saveResponse(
        this.args,
        new URL('./choice', here).href,
        'ChoiceResponse',
        {
          respondent: this.name.trim() || null,
          data: JSON.stringify(data),
          summary: this.summary,
        },
      );
    } catch (e: any) {
      this.error = `Saving failed: ${e?.message ?? e}`;
    }
    this.step = 'done';
    this.host?.done({ summary: this.summary, responseId: this.responseId });
  };
  openResponse = () => {
    if (this.responseId)
      this.args.viewCard?.(new URL(this.responseId) as any, 'isolated');
  };
  again = () => {
    this.responseId = '';
    this.step = 'intro';
  };

  // ─── results: share per option ────────────────────────────────────────
  get realms() {
    const r = this.args.model[realmURL];
    return r ? [r.href] : [];
  }
  responsesQuery = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: {
            module: new URL('./choice', here).href,
            name: 'ChoiceResponse',
          },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  get responses(): any[] {
    const id = (this.args.model as any).id;
    return ((this.responsesQuery?.instances ?? []) as any[]).filter(
      (r) => r.question?.id === id,
    );
  }
  get all(): ChoiceData[] {
    return this.responses.map((r) => parseJson<ChoiceData>(r.data, emptyData));
  }
  get rows() {
    const all = this.all;
    const n = all.length || 1;
    const pct = (k: number) => Math.round((k / n) * 100);
    const opts = [
      ...this.options,
      ...(this.args.model.allowOther ? [OTHER] : []),
    ];
    return opts
      .map((o) => {
        const k = all.filter((d) => d.picks.includes(o)).length;
        const wavered = all.filter((d) => dropped(d).includes(o)).length;
        return {
          o: o === OTHER ? 'Other' : o,
          pct: pct(k),
          k,
          wavered,
          bar: htmlSafe(`width:${pct(k)}%`),
        };
      })
      .sort((a, b) => b.k - a.k);
  }
  get otherTexts() {
    return this.all.map((d) => d.other).filter((t): t is string => Boolean(t));
  }
  get medianFirst() {
    const xs = this.all
      .map((d) => d.firstMs)
      .filter((x): x is number => x !== null)
      .sort((a, b) => a - b);
    return xs.length ? secs(xs[Math.floor(xs.length / 2)]) : '–';
  }
  get changed() {
    return this.all.filter((d) => dropped(d).length > 0).length;
  }
  showTake = () => (this.tab = 'take');
  showResults = () => (this.tab = 'results');
  open = (card: any) => this.args.viewCard?.(card, 'isolated');

  <template>
    <article class='sv cq {{if this.host "hosted"}}'>
      <header class='top'>
        <div>
          <p class='kicker'>{{if this.multi 'Choose any' 'Choose one'}}</p>
          <h1>{{@model.cardTitle}}</h1>
        </div>
        <nav class='tabs' aria-label='View'>
          <button
            type='button'
            class={{if (eq this.tab 'take') 'on'}}
            {{on 'click' this.showTake}}
          >Take it</button>
          <button
            type='button'
            class={{if (eq this.tab 'results') 'on'}}
            {{on 'click' this.showResults}}
          >Results · {{this.responses.length}}</button>
        </nav>
      </header>

      {{#if (eq this.tab 'take')}}
        <section class='panel'>
          {{#if (eq this.step 'intro')}}
            <p class='lead'>One question with a set list of answers.</p>
            <label class='field'>
              <span>Your first name or a nickname (optional)</span>
              <input
                type='text'
                value={{this.name}}
                autocomplete='given-name'
                {{on 'input' this.setName}}
              />
            </label>
            <div class='actions'><button
                type='button'
                class='primary'
                {{on 'click' this.start}}
              >Start</button></div>
          {{else if (eq this.step 'choose')}}
            <blockquote class='statement'>{{@model.prompt}}</blockquote>
            <p class='qmeta' aria-live='polite'>{{this.hint}}{{#if this.full}}
                That's the most you can pick; untick one to swap.{{/if}}</p>
            {{#if this.hasMedia}}
              <div class='pics' role='group' aria-label={{@model.prompt}}>
                {{#each this.tiles as |t|}}
                  <button
                    type='button'
                    class='pict {{if t.on "on"}}'
                    aria-pressed={{if t.on 'true' 'false'}}
                    disabled={{t.off}}
                    {{on 'click' (fn this.toggle t.o)}}
                  >
                    {{#if t.pic}}<img src={{t.pic}} alt={{t.o}} />{{/if}}<span
                    >{{t.o}}</span>
                  </button>
                {{/each}}
              </div>
            {{/if}}
            <div
              class='opts {{if this.hasMedia "hide"}}'
              role={{if this.multi 'group' 'radiogroup'}}
              aria-label={{@model.prompt}}
            >
              {{#each this.tiles as |t|}}
                <button
                  type='button'
                  class='opt {{if t.on "on"}}'
                  role={{if this.multi 'checkbox' 'radio'}}
                  aria-checked={{if t.on 'true' 'false'}}
                  disabled={{t.off}}
                  {{on 'click' (fn this.toggle t.o)}}
                ><span
                    class='mark {{if this.multi "sq"}}'
                    aria-hidden='true'
                  ></span>{{t.o}}</button>
              {{/each}}
              {{#if @model.allowOther}}
                <button
                  type='button'
                  class='opt other {{if this.otherOn "on"}}'
                  role={{if this.multi 'checkbox' 'radio'}}
                  aria-checked={{if this.otherOn 'true' 'false'}}
                  disabled={{this.otherOff}}
                  {{on 'click' this.toggleOther}}
                ><span
                    class='mark {{if this.multi "sq"}}'
                    aria-hidden='true'
                  ></span>Something else</button>
              {{/if}}
            </div>
            {{#if this.otherOn}}
              <label class='field wide'>
                <span>What is it?</span>
                <input
                  type='text'
                  value={{this.other}}
                  {{on 'input' this.setOther}}
                />
              </label>
            {{/if}}
            <div class='actions'>
              <button
                type='button'
                class='primary'
                disabled={{if this.canFinish false true}}
                {{on 'click' this.finish}}
              >Done</button>
            </div>
          {{else if (eq this.step 'saving')}}
            <p class='lead muted'>Saving…</p>
          {{else}}
            <p class='lead'>Thanks, that's saved.</p>
            <p class='said'>{{this.summary}}</p>
            <div class='actions'>
              {{#if this.responseId}}<button
                  type='button'
                  class='primary'
                  {{on 'click' this.openResponse}}
                >Open the response</button>{{/if}}
              <button type='button' class='quiet' {{on 'click' this.again}}>Take
                it again</button>
            </div>
          {{/if}}
          {{#if this.error}}<p
              class='err'
              role='alert'
            >{{this.error}}</p>{{/if}}
        </section>
      {{else}}
        <section class='results'>
          {{#if @model.brief}}<p class='brief'><b>What we want to learn</b>
              {{@model.brief}}</p>{{/if}}
          <p class='sum'>{{this.responses.length}}
            {{if (eq this.responses.length 1) 'response' 'responses'}}
            · median first pick
            {{this.medianFirst}}
            ·
            {{this.changed}}
            changed their mind on the way.</p>
          <div class='bars'>
            {{#each this.rows as |r|}}
              <div class='brow'>
                <span class='bname'>{{r.o}}</span>
                <span class='track'><span
                    class='fill'
                    style={{r.bar}}
                  ></span></span>
                <span class='bnum'>{{r.pct}}%{{#if r.wavered}}
                    ·
                    {{r.wavered}}
                    dropped it{{/if}}</span>
              </div>
            {{/each}}
          </div>
          {{#if this.otherTexts.length}}<p class='sum'><b>Something else:</b>
              {{#each this.otherTexts as |t|}}<span class='chip'>{{t}}</span>
              {{/each}}</p>{{/if}}
          {{#if this.responses.length}}
            <ul class='list'>
              {{#each this.responses as |r|}}<li><button
                    type='button'
                    class='rowbtn'
                    {{on 'click' (fn this.open r)}}
                  >{{r.cardTitle}}</button></li>{{/each}}
            </ul>
          {{/if}}
        </section>
      {{/if}}
    </article>
    <style scoped>
      .hosted {
        padding: 0 !important;
        max-width: none !important;
        min-height: 0 !important;
        width: 100% !important;
        margin: 0 !important;
        background: transparent !important;
      }
      .hosted > .top {
        display: none !important;
      }
      .sv {
        --sv-paper: #fbfaf7;
        --sv-panel: #ffffff;
        --sv-ink: #1d1c1a;
        --sv-muted: #6b675f;
        --sv-rule: #e4e0d8;
        --sv-live: #e2553b;
        --sv-sans:
          ui-sans-serif, -apple-system, 'Segoe UI', system-ui, sans-serif;
        --sv-mono: ui-monospace, 'SF Mono', Menlo, monospace;
        container-type: inline-size;
        background: var(--sv-paper);
        color: var(--sv-ink);
        font-family: var(--sv-sans);
        box-sizing: border-box;
      }
      .cq {
        min-height: 100%;
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 20px;
        align-content: start;
        max-width: 880px;
        margin: 0 auto;
      }
      .top {
        display: flex;
        justify-content: space-between;
        align-items: end;
        gap: 16px;
        flex-wrap: wrap;
      }
      .kicker {
        margin: 0;
        color: var(--sv-muted);
        font-size: 13px;
      }
      h1 {
        margin: 2px 0 0;
        font: 600 clamp(22px, 3.4cqw, 30px)/1.15 var(--sv-sans);
        letter-spacing: -0.01em;
      }
      .tabs {
        display: flex;
        gap: 4px;
        padding: 4px;
        border-radius: 10px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .tabs button {
        border: 0;
        background: transparent;
        padding: 7px 12px;
        border-radius: 7px;
        font: 500 13px/1 var(--sv-sans);
        color: var(--sv-muted);
        cursor: pointer;
      }
      .tabs button.on {
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .panel {
        display: grid;
        gap: 16px;
        padding: clamp(18px, 3cqw, 32px);
        border-radius: 14px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .lead {
        margin: 0;
        font-size: 15px;
        line-height: 1.55;
        max-width: 64ch;
      }
      .muted,
      .qmeta {
        color: var(--sv-muted);
      }
      .qmeta {
        margin: 0;
        font-size: 13px;
      }
      .statement {
        margin: 0;
        font: 600 clamp(20px, 3cqw, 26px)/1.3 var(--sv-sans);
        letter-spacing: -0.01em;
        max-width: 36ch;
      }
      .said {
        margin: 0;
        color: var(--sv-muted);
        line-height: 1.5;
        max-width: 64ch;
      }
      .field {
        display: grid;
        gap: 6px;
        max-width: 360px;
        font-size: 13px;
        color: var(--sv-muted);
      }
      .field.wide {
        max-width: 480px;
      }
      input[type='text'] {
        font: 400 15px/1.45 var(--sv-sans);
        padding: 10px 12px;
        border-radius: 9px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-paper);
        color: var(--sv-ink);
      }
      input[type='text']:focus-visible {
        outline: 2px solid var(--sv-ink);
        outline-offset: 1px;
      }
      .opts {
        display: grid;
        gap: 8px;
        max-width: 560px;
      }
      .opts.hide > .opt:not(.other) {
        display: none;
      }
      .pics {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
        gap: 10px;
        margin-bottom: 8px;
      }
      .pict {
        display: grid;
        gap: 6px;
        padding: 8px;
        border-radius: 10px;
        border: 1px solid var(--sv-rule, #e4e0d8);
        background: #fff;
        color: inherit;
        font:
          600 13px/1.2 ui-sans-serif,
          system-ui,
          sans-serif;
        text-align: left;
        cursor: pointer;
      }
      .pict img {
        width: 100%;
        aspect-ratio: 16 / 10;
        object-fit: contain;
        background: #ece8df;
        border-radius: 6px;
        display: block;
      }
      .pict.on {
        border-color: var(--sv-ink, #1d1c1a);
        box-shadow: inset 0 0 0 2px var(--sv-ink, #1d1c1a);
      }
      .pict:disabled {
        opacity: 0.45;
        cursor: default;
      }
      .opt {
        display: flex;
        align-items: center;
        gap: 12px;
        text-align: left;
        padding: 13px 14px;
        border-radius: 10px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-paper);
        font: 500 15px/1.35 var(--sv-sans);
        color: var(--sv-ink);
        cursor: pointer;
        transition:
          border-color 0.15s,
          background 0.15s;
      }
      .opt:hover:not(:disabled) {
        border-color: var(--sv-ink);
      }
      .opt.on {
        border-color: var(--sv-ink);
        background: var(--sv-panel);
        box-shadow: inset 0 0 0 1px var(--sv-ink);
      }
      .mark {
        flex: none;
        width: 18px;
        height: 18px;
        border-radius: 50%;
        border: 1.5px solid var(--sv-muted);
        box-sizing: border-box;
      }
      .mark.sq {
        border-radius: 5px;
      }
      .opt.on .mark {
        border: 5px solid var(--sv-ink);
      }
      .opt.on .mark.sq {
        border: 0;
        background: var(--sv-ink)
          url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cpath d='M3.5 8.5l3 3 6-7' fill='none' stroke='%23fbfaf7' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E")
          center/14px no-repeat;
      }
      .actions {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        align-items: center;
      }
      .primary,
      .quiet {
        font: 600 14px/1 var(--sv-sans);
        padding: 11px 16px;
        border-radius: 9px;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: var(--sv-ink);
        color: var(--sv-paper);
      }
      .quiet {
        border: 1px solid var(--sv-rule);
        background: transparent;
        color: var(--sv-ink);
      }
      button:disabled {
        opacity: 0.4;
        cursor: default;
      }
      button:focus-visible {
        outline: 2px solid var(--sv-live);
        outline-offset: 2px;
      }
      .err {
        margin: 0;
        color: #b3261e;
        font-size: 13px;
      }
      .results {
        display: grid;
        gap: 16px;
      }
      .brief,
      .sum {
        margin: 0;
        line-height: 1.6;
        max-width: 72ch;
      }
      .brief b {
        margin-right: 6px;
      }
      .sum {
        color: var(--sv-muted);
        font-size: 13px;
      }
      .chip {
        padding: 4px 9px;
        border-radius: 999px;
        background: var(--sv-ink);
        color: var(--sv-paper);
        font-size: 12px;
        white-space: nowrap;
      }
      .bars {
        display: grid;
        gap: 8px;
        padding: 16px 18px;
        border-radius: 12px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .brow {
        display: grid;
        grid-template-columns: minmax(110px, 240px) 1fr auto;
        gap: 12px;
        align-items: center;
        font-size: 14px;
      }
      .bname {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .track {
        position: relative;
        height: 12px;
        border-radius: 3px;
        background: var(--sv-paper);
      }
      .fill {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        border-radius: 3px;
        background: var(--sv-ink);
      }
      .bnum {
        font: 500 12px/1 var(--sv-mono);
        color: var(--sv-muted);
        white-space: nowrap;
      }
      .list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 6px;
      }
      .rowbtn {
        width: 100%;
        text-align: left;
        padding: 10px 12px;
        border-radius: 9px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-panel);
        font: 500 14px/1.3 var(--sv-sans);
        color: var(--sv-ink);
        cursor: pointer;
      }
      .rowbtn:hover {
        border-color: var(--sv-ink);
      }
    </style>
  </template>
}

class Fitted extends Component<typeof ChoiceQuestion> {
  <template>
    <div class='tf'>
      <span class='icon'><ListCheckIcon width='18' height='18' /></span>
      <div class='txt'><b>{{@model.cardTitle}}</b><span>{{if
            @model.multi
            'Choose any'
            'Choose one'
          }}</span></div>
    </div>
    <style scoped>
      .tf {
        height: 100%;
        padding: 12px 14px;
        display: flex;
        gap: 10px;
        align-items: center;
        overflow: hidden;
        box-sizing: border-box;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
      }
      .icon {
        flex: none;
        width: 34px;
        height: 34px;
        border-radius: 9px;
        display: grid;
        place-items: center;
        background: #1d1c1a;
        color: #fbfaf7;
      }
      .txt {
        display: grid;
        min-width: 0;
      }
      b {
        font-size: 14px;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      span {
        font-size: 12px;
        color: #6b675f;
      }
    </style>
  </template>
}

export class ChoiceQuestion extends CardDef {
  static displayName = 'Choice Question';
  static icon = ListCheckIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ChoiceQuestion) {
      return this.title;
    },
  });
  @field brief = contains(TextAreaField); // what whoever asks wants to learn
  @field prompt = contains(StringField);
  @field options = contains(TextAreaField); // one per line
  @field multi = contains(BooleanField); // false: pick one
  @field maxPicks = contains(NumberField); // multi only; 0 or empty: no limit
  @field allowOther = contains(BooleanField); // adds "Something else" with a text box
  @field shuffle = contains(BooleanField); // a fresh order per person
  @field media = contains(TextAreaField); // JSON: option → {image, video}, for options that are pictures
  static isolated = Isolated;
  static embedded = Fitted;
  static fitted = Fitted;
}

// ─── one person's answer ─────────────────────────────────────────────────
class ResponseView extends Component<typeof ChoiceResponse> {
  get d(): ChoiceData {
    return parseJson<ChoiceData>(this.args.model.data, emptyData);
  }
  get picks() {
    return this.d.picks.map((o, i) => ({
      n: i + 1,
      t: optLabel(o, this.d.other),
      pos: this.d.shown.indexOf(o) + 1,
    }));
  }
  get trail() {
    return this.d.moves.map((m) => ({
      t: optLabel(m.option, this.d.other),
      on: m.on,
      at: secs(m.ms),
    }));
  }
  <template>
    <article class='cr'>
      <p class='kicker'>Choice response{{#if @model.question}}
          ·
          {{@model.question.cardTitle}}{{/if}}</p>
      <h1>{{if @model.respondent @model.respondent 'Anonymous'}}</h1>
      <p class='summary'>{{@model.summary}}</p>
      <section>
        <h2>Chose</h2>
        {{#if this.picks.length}}
          <ol class='rows'>
            {{#each this.picks as |p|}}<li><span class='n'>{{p.n}}</span><b
                >{{p.t}}</b>{{#if p.pos}}<span class='t'>shown
                    {{p.pos}}
                    of
                    {{this.d.shown.length}}</span>{{/if}}</li>{{/each}}
          </ol>
        {{else}}<p class='none'>Nothing.</p>{{/if}}
      </section>
      <section>
        <h2>Every tap, in order</h2>
        <ol class='rows'>
          {{#each this.trail as |m|}}<li class={{unless m.on 'off'}}><span
                class='n'
              >{{if m.on '+' '−'}}</span>{{m.t}}<span
                class='t'
              >{{m.at}}</span></li>{{/each}}
        </ol>
      </section>
    </article>
    <style scoped>
      .cr {
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 20px;
        max-width: 760px;
        margin: 0 auto;
        container-type: inline-size;
        background: #fbfaf7;
        color: #1d1c1a;
        font-family:
          ui-sans-serif,
          -apple-system,
          'Segoe UI',
          system-ui,
          sans-serif;
      }
      .kicker {
        margin: 0;
        color: #6b675f;
        font-size: 13px;
      }
      h1 {
        margin: -14px 0 0;
        font-size: 28px;
        font-weight: 600;
        line-height: 1.2;
      }
      .summary {
        margin: 0;
        padding: 14px 16px;
        border-left: 3px solid #e2553b;
        background: #fff;
        border-radius: 0 10px 10px 0;
        line-height: 1.55;
      }
      h2 {
        margin: 0 0 8px;
        font-size: 12px;
        font-weight: 600;
        line-height: 1.3;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: #6b675f;
      }
      .rows {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 6px;
      }
      .rows li {
        display: flex;
        gap: 10px;
        align-items: baseline;
        padding: 10px 12px;
        border-radius: 9px;
        background: #fff;
        border: 1px solid #e4e0d8;
      }
      .rows li.off {
        border-style: dashed;
        color: #6b675f;
      }
      .n {
        font:
          600 11px/1 ui-monospace,
          monospace;
        color: #6b675f;
        min-width: 10px;
      }
      .t {
        margin-left: auto;
        font:
          500 12px/1 ui-monospace,
          monospace;
        color: #6b675f;
        white-space: nowrap;
      }
      .none {
        margin: 0;
        color: #6b675f;
        font-size: 14px;
      }
    </style>
  </template>
}

class ResponseRow extends Component<typeof ChoiceResponse> {
  <template>
    <div class='le'><b>{{if
          @model.respondent
          @model.respondent
          'Anonymous'
        }}</b><p>{{@model.summary}}</p></div>
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

export class ChoiceResponse extends CardDef {
  static displayName = 'Choice Response';
  static icon = ListCheckIcon;
  @field question = linksTo(() => ChoiceQuestion);
  @field respondent = contains(StringField);
  @field takenAt = contains(StringField);
  @field data = contains(TextAreaField); // JSON: ChoiceData
  @field summary = contains(TextAreaField); // for the interviewer
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ChoiceResponse) {
      const who = this.respondent || 'Anonymous';
      return this.question?.cardTitle
        ? `${who} · ${this.question.cardTitle}`
        : who;
    },
  });
  static isolated = ResponseView;
  static embedded = ResponseRow;
  static fitted = ResponseRow;
}

export { Isolated as ChoiceTool };
