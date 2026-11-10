// Duels: ranking without the drag-to-sort list. "This or that?", a pair at a
// time. After each pick the card refits a Bradley–Terry model (how likely each
// item is to beat an average one) and shows the pair it is least sure about,
// so about 1.6 picks per item give a full ranking. It keeps what a sorted list
// throws away: how long each pick took (the slow ones are the close calls),
// "can't choose", and loops (A over B, B over C, C over A).
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
import SwordsIcon from '@cardstack/boxel-icons/swords';
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

interface Pick {
  a: string;
  b: string;
  won: 'a' | 'b' | 'tie';
  ms: number;
}
interface DuelsData {
  items: string[];
  picks: Pick[];
  // after fitting: chance of beating an average item, 0–100
  scores: Record<string, number>;
  ranking: string[];
  closeCalls: { a: string; b: string; ms: number; tie: boolean }[];
  loops: string[][];
}

// ─── the model ───────────────────────────────────────────────────────────
// Bradley–Terry by minorise–maximise, with one virtual win and one virtual
// loss against an average item each, so nobody goes to infinity on 2 picks
export function fit(items: string[], picks: Pick[]): Record<string, number> {
  const s: Record<string, number> = Object.fromEntries(
    items.map((i) => [i, 1]),
  );
  for (let it = 0; it < 100; it++) {
    const next: Record<string, number> = {};
    for (const i of items) {
      let wins = 1;
      let denom = 2 / (s[i] + 1);
      for (const p of picks) {
        if (p.a !== i && p.b !== i) continue;
        const other = p.a === i ? p.b : p.a;
        const mine = p.a === i ? 'a' : 'b';
        wins += p.won === 'tie' ? 0.5 : p.won === mine ? 1 : 0;
        denom += 1 / (s[i] + s[other]);
      }
      next[i] = wins / denom;
    }
    const g = Math.exp(
      items.reduce((t, i) => t + Math.log(next[i]), 0) / items.length,
    );
    for (const i of items) s[i] = next[i] / g;
  }
  return Object.fromEntries(
    items.map((i) => [i, Math.round((s[i] / (s[i] + 1)) * 100)]),
  );
}

// the next pair: items seen least first, then the pair the model is least sure of
function nextPair(
  items: string[],
  picks: Pick[],
  scores: Record<string, number>,
): [string, string] | null {
  const seen = new Set(picks.map((p) => [p.a, p.b].sort().join('\u0000')));
  const count = (i: string) =>
    picks.filter((p) => p.a === i || p.b === i).length;
  let best: [string, string] | null = null;
  let bestKey = [Infinity, -Infinity];
  for (let x = 0; x < items.length; x++) {
    for (let y = x + 1; y < items.length; y++) {
      const a = items[x];
      const b = items[y];
      if (seen.has([a, b].sort().join('\u0000'))) continue;
      const pa = scores[a] / 100;
      const pb = scores[b] / 100;
      // chance a beats b, from each one's chance against average
      const sa = pa / (1 - pa + 1e-9);
      const sb = pb / (1 - pb + 1e-9);
      const p = sa / (sa + sb);
      const key = [
        Math.min(count(a), count(b)),
        p * (1 - p) + Math.random() * 1e-3,
      ];
      if (
        key[0] < bestKey[0] ||
        (key[0] === bestKey[0] && key[1] > bestKey[1])
      ) {
        bestKey = key;
        best = Math.random() < 0.5 ? [a, b] : [b, a];
      }
    }
  }
  return best;
}

function loopsIn(items: string[], picks: Pick[]) {
  const beat = new Set(
    picks
      .filter((p) => p.won !== 'tie')
      .map((p) =>
        p.won === 'a' ? `${p.a}\u0000${p.b}` : `${p.b}\u0000${p.a}`,
      ),
  );
  const over = (x: string, y: string) => beat.has(`${x}\u0000${y}`);
  const out: string[][] = [];
  for (let i = 0; i < items.length; i++)
    for (let j = i + 1; j < items.length; j++)
      for (let k = j + 1; k < items.length; k++) {
        const [a, b, c] = [items[i], items[j], items[k]];
        if (over(a, b) && over(b, c) && over(c, a)) out.push([a, b, c]);
        else if (over(a, c) && over(c, b) && over(b, a)) out.push([a, c, b]);
      }
  return out;
}

export function analyse(items: string[], picks: Pick[]): DuelsData {
  const scores = fit(items, picks);
  const ranking = [...items].sort((x, y) => scores[y] - scores[x]);
  const times = picks.map((p) => p.ms).sort((x, y) => x - y);
  const median = times.length ? times[Math.floor(times.length / 2)] : 0;
  const closeCalls = picks
    .filter((p) => p.won === 'tie' || (p.ms > median * 1.6 && p.ms > 2500))
    .sort((x, y) => y.ms - x.ms)
    .slice(0, 3)
    .map((p) => ({ a: p.a, b: p.b, ms: p.ms, tie: p.won === 'tie' }));
  return {
    items,
    picks,
    scores,
    ranking,
    closeCalls,
    loops: loopsIn(items, picks),
  };
}

export function duelsSummary(d: DuelsData) {
  const parts = [
    `Ranked: ${d.ranking.map((r, i) => `${i + 1}. ${r} (${d.scores[r]})`).join(', ')}. Scores are the chance of beating an average item.`,
  ];
  if (d.closeCalls.length)
    parts.push(
      `Hardest calls: ${d.closeCalls.map((c) => `${c.a} vs ${c.b} (${c.tie ? "couldn't choose" : secs(c.ms)})`).join('; ')}.`,
    );
  if (d.loops.length)
    parts.push(
      `Not consistent between ${d.loops[0].join(', ')} (each beat the next, the last beat the first), so treat those as close.`,
    );
  if (d.picks.length) parts.push(`${d.picks.length} picks.`);
  return parts.join(' ');
}

// ─── the card ────────────────────────────────────────────────────────────
type Step = 'intro' | 'duel' | 'saving' | 'done';

class Isolated extends Component<typeof DuelsQuestion> {
  @tracked tab: 'take' | 'results' = 'take';
  @tracked step: Step = 'intro';
  @tracked name = '';
  @tracked picks: Pick[] = [];
  @tracked pair: [string, string] | null = null;
  @tracked result: DuelsData | null = null;
  @tracked responseId = '';
  @tracked error = '';
  @tracked flash: 'a' | 'b' | 'tie' | null = null;
  shownAt = 0;

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

  get items() {
    return lines(this.args.model.items);
  }
  get budget() {
    const n = this.items.length;
    return Math.min((n * (n - 1)) / 2, Math.max(n + 3, Math.round(n * 1.6)));
  }
  get progressStyle() {
    return htmlSafe(
      `width:${((this.picks.length / Math.max(1, this.budget)) * 100).toFixed(1)}%`,
    );
  }
  get countLabel() {
    return `${Math.min(this.picks.length + 1, this.budget)} of ${this.budget}`;
  }
  get pairA() {
    return this.pair?.[0] ?? '';
  }
  get media() {
    return readMedia((this.args.model as any).media);
  }
  get picA() {
    return this.media[this.pairA] ?? null;
  }
  get picB() {
    return this.media[this.pairB] ?? null;
  }
  get pairB() {
    return this.pair?.[1] ?? '';
  }
  get canStop() {
    return this.picks.length >= this.items.length;
  }
  get liveRanking() {
    const s = fit(this.items, this.picks);
    return [...this.items]
      .sort((x, y) => s[y] - s[x])
      .map((i) => ({ i, bar: htmlSafe(`width:${s[i]}%`) }));
  }

  setName = (e: Event) => (this.name = (e.target as HTMLInputElement).value);
  start = () => {
    this.picks = [];
    this.result = null;
    this.error = '';
    this.step = 'duel';
    this.advance();
  };
  private advance() {
    if (this.picks.length >= this.budget) {
      this.finish();
      return;
    }
    this.pair = nextPair(this.items, this.picks, fit(this.items, this.picks));
    if (!this.pair) {
      this.finish();
      return;
    }
    this.shownAt = performance.now();
  }
  choose = (won: 'a' | 'b' | 'tie') => {
    if (!this.pair || this.flash) return;
    const [a, b] = this.pair;
    this.picks = [
      ...this.picks,
      { a, b, won, ms: Math.round(performance.now() - this.shownAt) },
    ];
    // a beat of feedback on the chosen side before the next pair
    this.flash = won;
    setTimeout(() => {
      this.flash = null;
      this.advance();
    }, 220);
  };
  chooseA = () => this.choose('a');
  chooseB = () => this.choose('b');
  chooseTie = () => this.choose('tie');
  finish = async () => {
    this.step = 'saving';
    this.result = analyse(this.items, this.picks);
    try {
      this.responseId = await saveResponse(
        this.args,
        new URL('./duels', here).href,
        'DuelsResponse',
        {
          respondent: this.name.trim() || null,
          data: JSON.stringify(this.result),
          summary: duelsSummary(this.result),
        },
      );
    } catch (e: any) {
      this.error = `Saving failed: ${e?.message ?? e}`;
    }
    this.step = 'done';
    this.host?.done({
      summary: this.result ? duelsSummary(this.result) : '',
      responseId: this.responseId,
    });
  };
  get doneRanking() {
    const r = this.result;
    return r
      ? r.ranking.map((i, k) => ({
          i,
          n: k + 1,
          score: r.scores[i],
          bar: htmlSafe(`width:${r.scores[i]}%`),
        }))
      : [];
  }
  openResponse = () => {
    if (this.responseId)
      this.args.viewCard?.(new URL(this.responseId) as any, 'isolated');
  };
  again = () => {
    this.responseId = '';
    this.step = 'intro';
  };

  // ─── results: average score per item ──────────────────────────────────
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
            module: new URL('./duels', here).href,
            name: 'DuelsResponse',
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
  get overall() {
    const all = this.responses
      .map((r) => parseJson<DuelsData | null>(r.data, null))
      .filter((d): d is DuelsData => Boolean(d));
    return this.items
      .map((i) => {
        const sc = all
          .map((d) => d.scores[i])
          .filter((x) => typeof x === 'number');
        const firsts = all.filter((d) => d.ranking[0] === i).length;
        const mean = sc.length
          ? Math.round(sc.reduce((a, b) => a + b, 0) / sc.length)
          : 0;
        return { i, mean, firsts, bar: htmlSafe(`width:${mean}%`) };
      })
      .sort((x, y) => y.mean - x.mean);
  }
  showTake = () => (this.tab = 'take');
  showResults = () => (this.tab = 'results');
  open = (card: any) => this.args.viewCard?.(card, 'isolated');

  <template>
    <article class='sv dq {{if this.host "hosted"}}'>
      <header class='top'>
        <div>
          <p class='kicker'>Duels</p>
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
            <p class='lead'>Two at a time: pick the one that matters more to
              you. Go with your gut; about
              {{this.budget}}
              quick picks.</p>
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
                disabled={{if this.items.length false true}}
                {{on 'click' this.start}}
              >Start</button></div>
          {{else if (eq this.step 'duel')}}
            <div class='prog'><span style={{this.progressStyle}}></span></div>
            <p class='qmeta'>{{this.countLabel}}</p>
            <blockquote class='statement'>{{@model.prompt}}</blockquote>
            {{#if this.pair}}
              <div class='duel {{if this.picA "pics"}}'>
                <button
                  type='button'
                  class='side
                    {{if (eq this.flash "a") "won"}}
                    {{if (eq this.flash "b") "lost"}}'
                  {{on 'click' this.chooseA}}
                >{{#if this.picA}}<img
                      class='pic'
                      src={{this.picA.image}}
                      alt={{this.pairA}}
                    /><span
                      class='cap'
                    >{{this.pairA}}</span>{{else}}{{this.pairA}}{{/if}}</button>
                <span class='vs'>or</span>
                <button
                  type='button'
                  class='side
                    {{if (eq this.flash "b") "won"}}
                    {{if (eq this.flash "a") "lost"}}'
                  {{on 'click' this.chooseB}}
                >{{#if this.picB}}<img
                      class='pic'
                      src={{this.picB.image}}
                      alt={{this.pairB}}
                    /><span
                      class='cap'
                    >{{this.pairB}}</span>{{else}}{{this.pairB}}{{/if}}</button>
              </div>
            {{/if}}
            <div class='actions centre'>
              <button
                type='button'
                class='link'
                {{on 'click' this.chooseTie}}
              >Can't choose</button>
              {{#if this.canStop}}<button
                  type='button'
                  class='link'
                  {{on 'click' this.finish}}
                >That's enough</button>{{/if}}
            </div>
            <details class='peek'>
              <summary>Your order so far</summary>
              <ol>{{#each this.liveRanking as |r|}}<li><span>{{r.i}}</span><span
                      class='mini'
                    ><span style={{r.bar}}></span></span></li>{{/each}}</ol>
            </details>
          {{else if (eq this.step 'saving')}}
            <p class='lead muted'>Saving…</p>
          {{else}}
            <p class='lead'>Here's your order.</p>
            <ol class='rank'>
              {{#each this.doneRanking as |r|}}
                <li><span class='n'>{{r.n}}</span><span
                    class='nm'
                  >{{r.i}}</span><span class='mini'><span
                      style={{r.bar}}
                    ></span></span><span class='sc'>{{r.score}}</span></li>
              {{/each}}
            </ol>
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
            {{if (eq this.responses.length 1) 'response' 'responses'}}. Each bar
            is the average chance of beating an average item; "first" counts who
            put it at the top.</p>
          <ol class='rank panelish'>
            {{#each this.overall as |r|}}
              <li><span class='nm'>{{r.i}}</span><span class='mini'><span
                    style={{r.bar}}
                  ></span></span><span class='sc'>{{r.mean}}{{#if r.firsts}}
                    · first ×{{r.firsts}}{{/if}}</span></li>
            {{/each}}
          </ol>
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
      .dq {
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
      .prog {
        height: 4px;
        border-radius: 2px;
        background: var(--sv-rule);
        overflow: hidden;
      }
      .prog span {
        display: block;
        height: 100%;
        background: var(--sv-ink);
        transition: width 0.3s;
      }
      .duel {
        display: grid;
        grid-template-columns: 1fr auto 1fr;
        gap: 14px;
        align-items: stretch;
      }
      .duel.pics .side {
        padding: 8px;
        display: grid;
        gap: 6px;
        align-content: start;
      }
      .pic {
        width: 100%;
        aspect-ratio: 16 / 10;
        object-fit: contain;
        background: #ece8df;
        border-radius: 8px;
        display: block;
      }
      .cap {
        font-size: 13px;
        font-weight: 600;
      }
      .side {
        min-height: 130px;
        padding: 22px;
        border-radius: 14px;
        border: 1.5px solid var(--sv-rule);
        background: var(--sv-paper);
        font: 600 clamp(17px, 2.4cqw, 21px)/1.3 var(--sv-sans);
        color: var(--sv-ink);
        cursor: pointer;
        transition:
          border-color 0.15s,
          transform 0.15s,
          background 0.15s,
          opacity 0.15s;
      }
      .side:hover {
        border-color: var(--sv-ink);
        transform: translateY(-2px);
      }
      .side.won {
        background: var(--sv-ink);
        color: var(--sv-paper);
        border-color: var(--sv-ink);
      }
      .side.lost {
        opacity: 0.35;
      }
      .vs {
        align-self: center;
        color: var(--sv-muted);
        font: 500 13px/1 var(--sv-mono);
      }
      .actions {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        align-items: center;
      }
      .actions.centre {
        justify-content: center;
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
      .link {
        border: 0;
        background: none;
        padding: 8px 4px;
        color: var(--sv-muted);
        font: 500 13px/1 var(--sv-sans);
        text-decoration: underline;
        cursor: pointer;
      }
      button:disabled {
        opacity: 0.4;
        cursor: default;
      }
      button:focus-visible {
        outline: 2px solid var(--sv-live);
        outline-offset: 2px;
      }
      .peek {
        color: var(--sv-muted);
        font-size: 13px;
      }
      .peek summary {
        cursor: pointer;
      }
      .peek ol {
        margin: 10px 0 0;
        padding-left: 20px;
        display: grid;
        gap: 4px;
      }
      .peek li span:first-child {
        display: inline-block;
        min-width: 50%;
      }
      .mini {
        display: inline-block;
        width: 120px;
        height: 6px;
        border-radius: 3px;
        background: var(--sv-rule);
        vertical-align: middle;
        overflow: hidden;
      }
      .mini span {
        display: block;
        height: 100%;
        background: var(--sv-ink);
      }
      .rank {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 6px;
      }
      .rank li {
        display: grid;
        grid-template-columns: auto 1fr minmax(80px, 200px) auto;
        gap: 12px;
        align-items: center;
        padding: 10px 12px;
        border-radius: 9px;
        background: var(--sv-paper);
        border: 1px solid var(--sv-rule);
        font-size: 15px;
      }
      .rank .mini {
        width: 100%;
      }
      .rank.panelish li {
        grid-template-columns: 1fr minmax(80px, 240px) auto;
        background: var(--sv-panel);
      }
      .n {
        font: 600 12px/1 var(--sv-mono);
        color: var(--sv-muted);
      }
      .sc {
        font: 500 12px/1 var(--sv-mono);
        color: var(--sv-muted);
        white-space: nowrap;
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
      @container (max-width: 560px) {
        .duel {
          grid-template-columns: 1fr;
        }
        .vs {
          justify-self: center;
        }
      }
    </style>
  </template>
}

class Fitted extends Component<typeof DuelsQuestion> {
  <template>
    <div class='tf'>
      <span class='icon'><SwordsIcon width='18' height='18' /></span>
      <div class='txt'><b>{{@model.cardTitle}}</b><span>Duels</span></div>
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

export class DuelsQuestion extends CardDef {
  static displayName = 'Duels Question';
  static icon = SwordsIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: DuelsQuestion) {
      return this.title;
    },
  });
  @field brief = contains(TextAreaField);
  @field prompt = contains(StringField); // "Which matters more to you…?"
  @field items = contains(TextAreaField); // one per line
  @field media = contains(TextAreaField); // JSON: item → {image, video}, for items that are pictures
  static isolated = Isolated;
  static embedded = Fitted;
  static fitted = Fitted;
}

// ─── one person's answer ─────────────────────────────────────────────────
class ResponseView extends Component<typeof DuelsResponse> {
  get d() {
    return parseJson<DuelsData | null>(this.args.model.data, null);
  }
  get rows() {
    const d = this.d;
    return d
      ? d.ranking.map((i, k) => ({
          i,
          n: k + 1,
          score: d.scores[i],
          bar: htmlSafe(`width:${d.scores[i]}%`),
        }))
      : [];
  }
  get log() {
    return (this.d?.picks ?? []).map((p, k) => ({
      ...p,
      n: k + 1,
      t: secs(p.ms),
      aOn: p.won === 'a',
      bOn: p.won === 'b',
      tie: p.won === 'tie',
    }));
  }
  <template>
    <article class='dr'>
      <p class='kicker'>Duels response{{#if @model.question}}
          ·
          {{@model.question.cardTitle}}{{/if}}</p>
      <h1>{{if @model.respondent @model.respondent 'Anonymous'}}</h1>
      <p class='summary'>{{@model.summary}}</p>
      <ol class='rank'>
        {{#each this.rows as |r|}}
          <li><span class='n'>{{r.n}}</span><span>{{r.i}}</span><span
              class='mini'
            ><span style={{r.bar}}></span></span><span
              class='sc'
            >{{r.score}}</span></li>
        {{/each}}
      </ol>
      <section>
        <h2>Every pick</h2>
        <ol class='log'>
          {{#each this.log as |l|}}
            <li><span class={{if l.aOn 'on'}}>{{l.a}}</span><span
                class='vs'
              >{{if l.tie "can't choose" 'or'}}</span><span
                class={{if l.bOn 'on'}}
              >{{l.b}}</span><span class='t'>{{l.t}}</span></li>
          {{/each}}
        </ol>
      </section>
    </article>
    <style scoped>
      .dr {
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 18px;
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
        margin: -12px 0 0;
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
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: #6b675f;
      }
      .rank,
      .log {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 6px;
      }
      .rank li {
        display: grid;
        grid-template-columns: auto 1fr minmax(80px, 200px) auto;
        gap: 12px;
        align-items: center;
        padding: 10px 12px;
        border-radius: 9px;
        background: #fff;
        border: 1px solid #e4e0d8;
      }
      .mini {
        display: block;
        height: 6px;
        border-radius: 3px;
        background: #e4e0d8;
        overflow: hidden;
      }
      .mini span {
        display: block;
        height: 100%;
        background: #1d1c1a;
      }
      .n,
      .sc,
      .t {
        font:
          500 12px/1 ui-monospace,
          monospace;
        color: #6b675f;
      }
      .log li {
        display: grid;
        grid-template-columns: 1fr auto 1fr auto;
        gap: 10px;
        align-items: center;
        font-size: 13px;
      }
      .log li > span:not(.vs):not(.t) {
        padding: 7px 10px;
        border-radius: 8px;
        border: 1px dashed #e4e0d8;
        color: #6b675f;
      }
      .log li > span.on {
        border: 1.5px solid #1d1c1a;
        color: #1d1c1a;
        background: #fff;
      }
      .vs {
        color: #6b675f;
        font-size: 12px;
      }
    </style>
  </template>
}

class ResponseRow extends Component<typeof DuelsResponse> {
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

export class DuelsResponse extends CardDef {
  static displayName = 'Duels Response';
  static icon = SwordsIcon;
  @field question = linksTo(() => DuelsQuestion);
  @field respondent = contains(StringField);
  @field takenAt = contains(StringField);
  @field data = contains(TextAreaField); // JSON: DuelsData
  @field summary = contains(TextAreaField); // for the interviewer
  @field cardTitle = contains(StringField, {
    computeVia: function (this: DuelsResponse) {
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

export { Isolated as DuelsTool };
