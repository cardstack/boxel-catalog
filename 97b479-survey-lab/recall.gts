// Recall first, then the list: the awareness question without giving the
// answers away. The person types whatever comes to mind, one at a time (the
// order and the seconds it took are kept: first named is top of mind). The AI
// matches what they typed to the list, typos and nicknames included, and only
// then shows the options they did not name: "heard of any of these?"
// The classic numbers come out (top of mind, unaided, aided awareness) plus
// what the old list could never catch: names that are not on it.
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
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import LightbulbIcon from '@cardstack/boxel-icons/lightbulb';
import {
  askJson,
  toolCtx,
  saveResponse,
  lines,
  parseJson,
  secs,
  hostOf,
  type ToolHost,
} from './tool-kit';

// @ts-ignore import.meta is fine here (the host loads cards as ES modules); the catalog's CommonJS type check rejects it
const here: string = import.meta.url;

interface Entry {
  text: string;
  ms: number; // since the question appeared
  option: string | null; // the list option it matched, if any
}
interface RecallData {
  entries: Entry[];
  recognised: string[];
  unknown: string[];
}

const MATCHER = `You match what a survey respondent typed from memory to a fixed list of options.
Match typos, nicknames, products of a brand and partial names to the option they clearly mean ("monday" → "Monday.com", "power apps" → "Microsoft Power Apps"). If an entry is not clearly one option, match it to null. Never match two entries to the same option unless they are the same thing typed twice.
Answer ONLY with JSON: {"matches": [{"entry": "<exactly as typed>", "option": "<exactly as in the list, or null>"}]}`;

async function matchEntries(
  ctx: any,
  options: string[],
  entries: Entry[],
): Promise<Entry[]> {
  const local = (t: string) =>
    options.find(
      (o) =>
        o.toLowerCase() === t.toLowerCase() ||
        o.toLowerCase().replace(/\W/g, '') ===
          t.toLowerCase().replace(/\W/g, ''),
    ) ?? null;
  if (!entries.length) return entries;
  try {
    const j = await askJson(
      ctx,
      MATCHER,
      `Options:\n${options.join('\n')}\n\nTyped:\n${entries.map((e) => e.text).join('\n')}`,
      0,
    );
    const found = new Map<string, string | null>();
    for (const m of Array.isArray(j?.matches) ? j.matches : []) {
      const opt = options.find((o) => o === m?.option) ?? null;
      found.set(String(m?.entry ?? ''), opt);
    }
    return entries.map((e) => ({
      ...e,
      option: found.has(e.text) ? found.get(e.text)! : local(e.text),
    }));
  } catch {
    return entries.map((e) => ({ ...e, option: local(e.text) }));
  }
}

export function recallSummary(d: RecallData) {
  const named = d.entries.filter((e) => e.option);
  const others = d.entries.filter((e) => !e.option);
  const parts: string[] = [];
  if (!d.entries.length) parts.push('Could not name any unprompted.');
  else if (named.length)
    parts.push(
      `Named ${named.length} from the list unprompted, in order: ${named.map((e, i) => (i === 0 ? `${e.option} (first, after ${secs(e.ms)})` : e.option)).join(', ')}.`,
    );
  else parts.push('Named nothing from the list unprompted.');
  if (others.length)
    parts.push(
      `Also named, not on the list: ${others.map((e) => e.text).join(', ')}.`,
    );
  if (d.recognised.length)
    parts.push(`Recognised when shown: ${d.recognised.join(', ')}.`);
  if (d.unknown.length) parts.push(`Never heard of: ${d.unknown.join(', ')}.`);
  return parts.join(' ');
}

type Step = 'intro' | 'recall' | 'matching' | 'aided' | 'saving' | 'done';

class Isolated extends Component<typeof RecallQuestion> {
  @tracked tab: 'take' | 'results' = 'take';
  @tracked step: Step = 'intro';
  @tracked name = '';
  @tracked draft = '';
  @tracked entries: Entry[] = [];
  @tracked recognised: string[] = [];
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
  get unnamed() {
    const named = new Set(this.entries.map((e) => e.option).filter(Boolean));
    return this.options
      .filter((o) => !named.has(o))
      .map((o) => ({ o, on: this.recognised.includes(o) }));
  }
  get namedChips() {
    return this.entries.map((e, i) => ({ ...e, i, n: i + 1, off: !e.option }));
  }

  setName = (e: Event) => (this.name = (e.target as HTMLInputElement).value);
  setDraft = (e: Event) => (this.draft = (e.target as HTMLInputElement).value);
  start = () => {
    this.entries = [];
    this.recognised = [];
    this.draft = '';
    this.error = '';
    this.started = performance.now();
    this.step = 'recall';
  };
  add = () => {
    // a comma-separated burst counts as several, all at the same moment
    const ms = Math.round(performance.now() - this.started);
    const fresh = this.draft
      .split(',')
      .map((t) => t.trim())
      .filter(
        (t) =>
          t &&
          !this.entries.some((e) => e.text.toLowerCase() === t.toLowerCase()),
      );
    this.entries = [
      ...this.entries,
      ...fresh.map((text) => ({ text, ms, option: null })),
    ];
    this.draft = '';
  };
  key = (ev: Event) => {
    const e = ev as KeyboardEvent;
    if (e.key === 'Enter') {
      e.preventDefault();
      this.add();
    }
  };
  remove = (i: number) =>
    (this.entries = this.entries.filter((_, j) => j !== i));
  doneRecalling = async () => {
    if (this.draft.trim()) this.add();
    this.step = 'matching';
    this.entries = await matchEntries(
      toolCtx(this.args.context),
      this.options,
      this.entries,
    );
    if (!this.unnamed.length) {
      await this.save();
      return;
    }
    this.step = 'aided';
  };
  toggle = (o: string) =>
    (this.recognised = this.recognised.includes(o)
      ? this.recognised.filter((x) => x !== o)
      : [...this.recognised, o]);
  finish = () => this.save();

  private async save() {
    this.step = 'saving';
    const named = new Set(this.entries.map((e) => e.option).filter(Boolean));
    const data: RecallData = {
      entries: this.entries,
      recognised: this.recognised,
      unknown: this.options.filter(
        (o) => !named.has(o) && !this.recognised.includes(o),
      ),
    };
    this.summary = recallSummary(data);
    try {
      this.responseId = await saveResponse(
        this.args,
        new URL('./recall', here).href,
        'RecallResponse',
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
  }
  openResponse = () => {
    if (this.responseId)
      this.args.viewCard?.(new URL(this.responseId) as any, 'isolated');
  };
  again = () => {
    this.responseId = '';
    this.step = 'intro';
  };

  // ─── results: the awareness funnel per option ─────────────────────────
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
            module: new URL('./recall', here).href,
            name: 'RecallResponse',
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
  get funnel() {
    const all = this.responses.map((r) =>
      parseJson<RecallData>(r.data, {
        entries: [],
        recognised: [],
        unknown: [],
      }),
    );
    const n = all.length || 1;
    const pct = (k: number) => Math.round((k / n) * 100);
    return this.options
      .map((o) => {
        const top = all.filter(
          (d) => d.entries.find((e) => e.option)?.option === o,
        ).length;
        const unaided = all.filter((d) =>
          d.entries.some((e) => e.option === o),
        ).length;
        const aware =
          unaided + all.filter((d) => d.recognised.includes(o)).length;
        return {
          o,
          top: pct(top),
          unaided: pct(unaided),
          aware: pct(aware),
          topBar: htmlSafe(`width:${pct(top)}%`),
          unaidedBar: htmlSafe(`width:${pct(unaided)}%`),
          awareBar: htmlSafe(`width:${pct(aware)}%`),
        };
      })
      .sort((a, b) => b.aware - a.aware || b.unaided - a.unaided);
  }
  get otherNames() {
    const counts = new Map<string, number>();
    for (const r of this.responses) {
      for (const e of parseJson<RecallData>(r.data, {
        entries: [],
        recognised: [],
        unknown: [],
      }).entries) {
        if (!e.option)
          counts.set(
            e.text.toLowerCase(),
            (counts.get(e.text.toLowerCase()) ?? 0) + 1,
          );
      }
    }
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([t, c]) => (c > 1 ? `${t} ×${c}` : t));
  }
  showTake = () => (this.tab = 'take');
  showResults = () => (this.tab = 'results');
  open = (card: any) => this.args.viewCard?.(card, 'isolated');

  <template>
    <article class='sv rq {{if this.host "hosted"}}'>
      <header class='top'>
        <div>
          <p class='kicker'>Recall first</p>
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
            <p class='lead'>One quick question from memory, then a short list.
              There are no wrong answers; naming nothing is an answer too.</p>
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
          {{else if (eq this.step 'recall')}}
            <blockquote class='statement'>{{@model.prompt}}</blockquote>
            <p class='qmeta'>Type one, press Enter, then the next. Whatever
              comes to mind first.</p>
            <div class='adder'>
              <input
                type='text'
                value={{this.draft}}
                aria-label='A name that comes to mind'
                placeholder='Type a name…'
                {{on 'input' this.setDraft}}
                {{on 'keydown' this.key}}
              />
              <button
                type='button'
                class='quiet'
                disabled={{if this.draft false true}}
                {{on 'click' this.add}}
              >Add</button>
            </div>
            {{#if this.entries.length}}
              <ol class='chips'>
                {{#each this.namedChips as |c|}}
                  <li class='chip'><span
                      class='ord'
                    >{{c.n}}</span>{{c.text}}<button
                      type='button'
                      class='x'
                      aria-label='Remove {{c.text}}'
                      {{on 'click' (fn this.remove c.i)}}
                    >×</button></li>
                {{/each}}
              </ol>
            {{/if}}
            <div class='actions'>
              <button
                type='button'
                class='primary'
                {{on 'click' this.doneRecalling}}
              >{{if
                  this.entries.length
                  "That's all I can think of"
                  'None come to mind'
                }}</button>
            </div>
          {{else if (eq this.step 'matching')}}
            <p class='lead muted'>One moment…</p>
          {{else if (eq this.step 'aided')}}
            {{#if this.entries.length}}
              <p class='qmeta'>You named</p>
              <ol class='chips'>
                {{#each this.namedChips as |c|}}<li
                    class='chip {{if c.off "off"}}'
                  >{{if c.option c.option c.text}}</li>{{/each}}
              </ol>
            {{/if}}
            <blockquote class='statement small'>Have you heard of any of these?
              Tap the ones you know, even just by name.</blockquote>
            <div class='tiles'>
              {{#each this.unnamed as |u|}}
                <button
                  type='button'
                  class='tile {{if u.on "on"}}'
                  aria-pressed={{if u.on 'true' 'false'}}
                  {{on 'click' (fn this.toggle u.o)}}
                >{{u.o}}</button>
              {{/each}}
            </div>
            <div class='actions'><button
                type='button'
                class='primary'
                {{on 'click' this.finish}}
              >Done</button></div>
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
            {{if (eq this.responses.length 1) 'response' 'responses'}}. For each
            option:
            <span class='k top'></span>named first
            <span class='k un'></span>named unprompted
            <span class='k aw'></span>aware at all (named or recognised).</p>
          <div class='funnel'>
            {{#each this.funnel as |f|}}
              <div class='frow'>
                <span class='fname'>{{f.o}}</span>
                <span class='bars'>
                  <span class='bar aw' style={{f.awareBar}}></span>
                  <span class='bar un' style={{f.unaidedBar}}></span>
                  <span class='bar top' style={{f.topBar}}></span>
                </span>
                <span class='fnum'>{{f.top}}
                  ·
                  {{f.unaided}}
                  ·
                  {{f.aware}}%</span>
              </div>
            {{/each}}
          </div>
          {{#if this.otherNames.length}}<p class='sum'><b>Named but not on the
                list:</b>
              {{#each this.otherNames as |t|}}<span
                  class='chip off'
                >{{t}}</span>
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
      .rq {
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
        max-width: 32ch;
      }
      .statement.small {
        font-size: 18px;
        max-width: 48ch;
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
      .adder {
        display: flex;
        gap: 8px;
        max-width: 480px;
      }
      .adder input {
        flex: 1;
        min-width: 0;
      }
      .chips {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .chip {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 6px 8px 6px 10px;
        border-radius: 999px;
        background: var(--sv-ink);
        color: var(--sv-paper);
        font: 500 14px/1 var(--sv-sans);
      }
      .chip.off {
        background: transparent;
        color: var(--sv-ink);
        border: 1px dashed var(--sv-muted);
        padding: 5px 10px;
      }
      .ord {
        font: 600 10px/1 var(--sv-mono);
        opacity: 0.6;
      }
      .x {
        border: 0;
        background: none;
        color: inherit;
        opacity: 0.6;
        font-size: 16px;
        line-height: 1;
        cursor: pointer;
        padding: 0 2px;
      }
      .x:hover {
        opacity: 1;
      }
      .tiles {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
        gap: 10px;
      }
      .tile {
        padding: 14px 12px;
        border-radius: 10px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-paper);
        font: 500 15px/1.3 var(--sv-sans);
        color: var(--sv-ink);
        cursor: pointer;
        transition:
          border-color 0.15s,
          background 0.15s;
      }
      .tile:hover {
        border-color: var(--sv-ink);
      }
      .tile.on {
        background: var(--sv-ink);
        color: var(--sv-paper);
        border-color: var(--sv-ink);
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
      .sum .chip {
        font-size: 12px;
      }
      .k {
        display: inline-block;
        width: 10px;
        height: 10px;
        border-radius: 2px;
        margin: 0 2px 0 8px;
        vertical-align: -1px;
      }
      .k.top,
      .bar.top {
        background: var(--sv-live);
      }
      .k.un,
      .bar.un {
        background: var(--sv-ink);
      }
      .k.aw,
      .bar.aw {
        background: var(--sv-rule);
      }
      .funnel {
        display: grid;
        gap: 8px;
        padding: 16px 18px;
        border-radius: 12px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      .frow {
        display: grid;
        grid-template-columns: minmax(110px, 180px) 1fr auto;
        gap: 12px;
        align-items: center;
        font-size: 14px;
      }
      .fname {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .bars {
        position: relative;
        height: 14px;
        border-radius: 3px;
        background: var(--sv-paper);
      }
      .bar {
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        border-radius: 3px;
      }
      .bar.un {
        top: 3px;
        bottom: 3px;
      }
      .bar.top {
        top: 5px;
        bottom: 5px;
      }
      .fnum {
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

class Fitted extends Component<typeof RecallQuestion> {
  <template>
    <div class='tf'>
      <span class='icon'><LightbulbIcon width='18' height='18' /></span>
      <div class='txt'><b>{{@model.cardTitle}}</b><span>Recall first</span></div>
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

export class RecallQuestion extends CardDef {
  static displayName = 'Recall Question';
  static icon = LightbulbIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: RecallQuestion) {
      return this.title;
    },
  });
  @field brief = contains(TextAreaField); // what whoever asks wants to learn
  @field prompt = contains(StringField); // the from-memory question
  @field options = contains(TextAreaField); // the list, one per line
  static isolated = Isolated;
  static embedded = Fitted;
  static fitted = Fitted;
}

// ─── one person's answer ─────────────────────────────────────────────────
class ResponseView extends Component<typeof RecallResponse> {
  get d(): RecallData {
    return parseJson<RecallData>(this.args.model.data, {
      entries: [],
      recognised: [],
      unknown: [],
    });
  }
  get rows() {
    return this.d.entries.map((e, i) => ({
      ...e,
      n: i + 1,
      t: secs(e.ms),
      off: !e.option,
    }));
  }
  <template>
    <article class='rr'>
      <p class='kicker'>Recall response{{#if @model.question}}
          ·
          {{@model.question.cardTitle}}{{/if}}</p>
      <h1>{{if @model.respondent @model.respondent 'Anonymous'}}</h1>
      <p class='summary'>{{@model.summary}}</p>
      <section>
        <h2>From memory, in order</h2>
        {{#if this.rows.length}}
          <ol class='mem'>
            {{#each this.rows as |r|}}
              <li class={{if r.off 'off'}}><span class='n'>{{r.n}}</span><b
                >{{r.text}}</b>{{#if r.option}}{{#unless (eq r.option r.text)}}
                    →
                    {{r.option}}{{/unless}}{{else}}
                  <em>not on the list</em>{{/if}}<span
                  class='t'
                >{{r.t}}</span></li>
            {{/each}}
          </ol>
        {{else}}<p class='none'>Nothing came to mind.</p>{{/if}}
      </section>
      <section class='two'>
        <div><h2>Recognised when shown</h2><p>{{#each
              this.d.recognised
              as |o|
            }}<span class='chip'>{{o}}</span> {{else}}<span
                class='none'
              >None</span>{{/each}}</p></div>
        <div><h2>Never heard of</h2><p>{{#each this.d.unknown as |o|}}<span
                class='chip off'
              >{{o}}</span>
            {{else}}<span class='none'>None</span>{{/each}}</p></div>
      </section>
    </article>
    <style scoped>
      .rr {
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
      .mem {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 6px;
      }
      .mem li {
        display: flex;
        gap: 10px;
        align-items: baseline;
        padding: 10px 12px;
        border-radius: 9px;
        background: #fff;
        border: 1px solid #e4e0d8;
      }
      .mem li.off {
        border-style: dashed;
      }
      .mem em {
        color: #6b675f;
        font-size: 13px;
      }
      .n {
        font:
          600 11px/1 ui-monospace,
          monospace;
        color: #6b675f;
      }
      .t {
        margin-left: auto;
        font:
          500 12px/1 ui-monospace,
          monospace;
        color: #6b675f;
      }
      .two {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 20px;
      }
      .two p {
        margin: 0;
        line-height: 2.2;
      }
      .chip {
        padding: 5px 10px;
        border-radius: 999px;
        background: #1d1c1a;
        color: #fbfaf7;
        font-size: 13px;
        white-space: nowrap;
      }
      .chip.off {
        background: transparent;
        color: #1d1c1a;
        border: 1px dashed #6b675f;
      }
      .none {
        color: #6b675f;
        font-size: 14px;
      }
      @container (max-width: 520px) {
        .two {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

class ResponseRow extends Component<typeof RecallResponse> {
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

export class RecallResponse extends CardDef {
  static displayName = 'Recall Response';
  static icon = LightbulbIcon;
  @field question = linksTo(() => RecallQuestion);
  @field respondent = contains(StringField);
  @field takenAt = contains(StringField);
  @field data = contains(TextAreaField); // JSON: RecallData
  @field summary = contains(TextAreaField); // for the interviewer
  @field cardTitle = contains(StringField, {
    computeVia: function (this: RecallResponse) {
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

export { Isolated as RecallTool };
