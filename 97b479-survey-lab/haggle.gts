// Haggle: the price question answered by behaviour instead of a guess. A
// seller character opens at the list price and haggles with the person in a
// short chat (clearly role-play, nothing is bought). The card keeps every
// offer and counter, and the reasons they gave. What comes out is a bracket
// for what they would really pay (above their best offer, below the price they
// walked away from) and the arguments a real salesperson would need to answer.
// The seller never goes below a floor the questioner sets, and never raises
// its price; both are enforced here, not left to the model.
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import TextAreaField from '@cardstack/base/text-area';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import HandshakeIcon from '@cardstack/boxel-icons/handshake';
import {
  askJson,
  toolCtx,
  saveResponse,
  parseJson,
  hostOf,
  type ToolHost,
} from './tool-kit';

// @ts-ignore import.meta is fine here (the host loads cards as ES modules); the catalog's CommonJS type check rejects it
const here: string = import.meta.url;
const MAX_TURNS = 8;

interface Turn {
  who: 'seller' | 'them';
  text: string;
  ask?: number; // seller's price after this turn
  offer?: number | null; // their price, if they named one
  reason?: string; // what they argued, in a few words
  ms?: number;
}
interface HaggleData {
  turns: Turn[];
  outcome: 'deal' | 'walked';
  dealPrice: number | null;
  firstOffer: number | null;
  bestOffer: number | null;
  refusedAsk: number | null; // the lowest price they walked away from
  low: number | null; // what they'd pay, at least
  high: number | null; // and at most (null if they took a deal)
  reasons: string[];
  listPrice: number;
}

const SELLER = `You play a friendly, professional salesperson in a short role-play haggle that is part of a market research survey. Nothing is really sold; the respondent knows it is role-play. Stay in character, warm and brief (1–3 sentences), never pushy or manipulative, never invent discounts beyond the rules, never mention the floor price or that you have one.
Rules for your price ("ask"):
- Start from the current ask. Never go up. Never go below the FLOOR.
- Concede slowly and only when they give a reason or make an offer; each concession at most about a quarter of the gap between your ask and their offer, and smaller each time.
- Ask what they'd use it for, or offer a non-price trade (annual billing, fewer seats) now and then, so their reasons come out.
- Hold out: a quick deal teaches us little. Only accept (set "accept": true and ask = their offer) if their offer is within about 10% of your current ask, or they have pushed at least 5 times and the offer is at or above the FLOOR. "Final offer" alone is not a reason to accept; counter instead.
Also read their message: the price they named, if any, and the reason they gave, if any.
Answer ONLY with JSON: {"reply": "...", "ask": <number>, "accept": <true|false>, "offer": <number or null>, "reason": "<their argument in under 8 words, or empty>"}`;

function haggleSummary(d: HaggleData, cur: string) {
  const m = (n: number | null) => (n === null ? '–' : `${cur}${Math.round(n)}`);
  const parts: string[] = [];
  if (d.outcome === 'deal')
    parts.push(
      `Took a deal at ${m(d.dealPrice)} (list ${m(d.listPrice)}), so they would pay at least that.`,
    );
  else
    parts.push(
      `Walked away at ${m(d.refusedAsk)} (list ${m(d.listPrice)}).${d.bestOffer !== null ? ` Their best offer was ${m(d.bestOffer)}, so they would pay somewhere between ${m(d.bestOffer)} and ${m(d.refusedAsk)}.` : ' They never named a price.'}`,
    );
  if (d.firstOffer !== null)
    parts.push(
      `First offer ${m(d.firstOffer)} (${Math.round((d.firstOffer / d.listPrice) * 100)}% of list).`,
    );
  if (d.reasons.length) parts.push(`Arguments: ${d.reasons.join('; ')}.`);
  return parts.join(' ');
}

type Step = 'intro' | 'chat' | 'saving' | 'done';

class Isolated extends Component<typeof HaggleQuestion> {
  @tracked tab: 'take' | 'results' = 'take';
  @tracked step: Step = 'intro';
  @tracked name = '';
  @tracked turns: Turn[] = [];
  @tracked ask = 0;
  @tracked draft = '';
  @tracked thinking = false;
  @tracked result: HaggleData | null = null;
  @tracked responseId = '';
  @tracked error = '';
  lastAt = 0;

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

  get cur() {
    return this.args.model.currency || '$';
  }
  get list() {
    return Number(this.args.model.listPrice) || 0;
  }
  get floor() {
    return Math.min(
      this.list,
      Number(this.args.model.floorPrice) || this.list * 0.7,
    );
  }
  get seller() {
    return this.args.model.seller || 'Sam';
  }
  money = (n: number | null | undefined) =>
    typeof n === 'number' ? `${this.cur}${Math.round(n)}` : '–';
  get askLabel() {
    return `${this.money(this.ask)}${this.args.model.unit ? ` ${this.args.model.unit}` : ''}`;
  }
  get theirTurns() {
    return this.turns.filter((t) => t.who === 'them').length;
  }
  get finalRound() {
    return this.theirTurns >= MAX_TURNS;
  }
  get shown() {
    return this.turns.map((t) => ({ ...t, mine: t.who === 'them' }));
  }

  setName = (e: Event) => (this.name = (e.target as HTMLInputElement).value);
  setDraft = (e: Event) =>
    (this.draft = (e.target as HTMLTextAreaElement).value);
  start = () => {
    this.ask = this.list;
    this.result = null;
    this.error = '';
    this.turns = [
      {
        who: 'seller',
        text: `Hi, I'm ${this.seller}. ${this.args.model.product} is ${this.askLabel}. What would you be using it for?`,
        ask: this.list,
      },
    ];
    this.lastAt = performance.now();
    this.step = 'chat';
  };
  key = (ev: Event) => {
    const e = ev as KeyboardEvent;
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.send();
    }
  };
  send = async () => {
    const text = this.draft.trim();
    if (!text || this.thinking || this.finalRound) return;
    const ms = Math.round(performance.now() - this.lastAt);
    this.draft = '';
    this.turns = [...this.turns, { who: 'them', text, ms }];
    this.thinking = true;
    try {
      const history = this.turns
        .map((t) => `${t.who === 'seller' ? 'You' : 'Them'}: ${t.text}`)
        .join('\n');
      const j = await askJson(
        toolCtx(this.args.context),
        SELLER,
        `Product: ${this.args.model.product}\n${this.args.model.details ?? ''}\nList price: ${this.list} ${this.args.model.unit ?? ''}\nFLOOR (secret): ${this.floor}\nCurrent ask: ${this.ask}\nCurrency symbol: ${this.cur}\n${this.args.model.context ? `What we know about them: ${this.args.model.context}\n` : ''}Turns left after this one: ${MAX_TURNS - this.theirTurns}\n\nConversation so far:\n${history}`,
        0.6,
      );
      const offer =
        Number.isFinite(Number(j?.offer)) && j?.offer !== null
          ? Number(j.offer)
          : null;
      // the rules the model must not bend: never up, never below the floor
      let ask = Math.round(
        Math.min(this.ask, Math.max(this.floor, Number(j?.ask) || this.ask)),
      );
      // a quick deal only tells us a lower bound, so the seller holds out:
      // it takes an offer near its ask, or one above the floor after 5 pushes
      const fair =
        offer !== null &&
        offer >= this.floor &&
        (offer >= this.ask * 0.9 || this.theirTurns >= 5);
      const accepted = Boolean(j?.accept) && fair;
      let reply = String(j?.reply ?? '');
      if (j?.accept && !fair && offer !== null) {
        ask = Math.round(
          Math.max(
            this.floor,
            Math.min(ask, this.ask - (this.ask - offer) * 0.25),
          ),
        );
        reply = `I can't quite do ${this.money(offer)}. I could meet you at ${this.money(ask)}${this.args.model.unit ? ` ${this.args.model.unit}` : ''}.`;
      }
      if (offer !== null && offer >= this.ask) ask = this.ask; // they met the price
      const last = this.turns[this.turns.length - 1];
      this.turns = [
        ...this.turns.slice(0, -1),
        { ...last, offer, reason: String(j?.reason ?? '').slice(0, 80) },
      ];
      if (accepted || (offer !== null && offer >= this.ask)) {
        const price = accepted ? Math.max(this.floor, offer!) : this.ask;
        this.turns = [
          ...this.turns,
          {
            who: 'seller',
            text: reply || `Deal at ${this.money(price)}.`,
            ask: price,
          },
        ];
        this.ask = price;
        this.thinking = false;
        await this.end('deal');
        return;
      }
      this.ask = ask;
      const closing =
        this.theirTurns >= MAX_TURNS
          ? ` That's the best I can do: ${this.askLabel}.`
          : '';
      this.turns = [
        ...this.turns,
        { who: 'seller', text: reply + closing, ask },
      ];
    } catch (e: any) {
      this.error = `${this.seller} lost the thread (${e?.message ?? e}). You can still take the deal or walk away.`;
    }
    this.thinking = false;
    this.lastAt = performance.now();
  };
  takeDeal = () => this.end('deal');
  walk = () => this.end('walked');

  private async end(outcome: 'deal' | 'walked') {
    this.step = 'saving';
    const offers = this.turns
      .map((t) => t.offer)
      .filter((o): o is number => typeof o === 'number');
    const best = offers.length ? Math.max(...offers) : null;
    const d: HaggleData = {
      turns: this.turns,
      outcome,
      dealPrice: outcome === 'deal' ? this.ask : null,
      firstOffer: offers.length ? offers[0] : null,
      bestOffer: best,
      refusedAsk: outcome === 'walked' ? this.ask : null,
      low: outcome === 'deal' ? this.ask : best,
      high: outcome === 'walked' ? this.ask : null,
      reasons: this.turns.map((t) => t.reason ?? '').filter(Boolean),
      listPrice: this.list,
    };
    this.result = d;
    try {
      this.responseId = await saveResponse(
        this.args,
        new URL('./haggle', here).href,
        'HaggleResponse',
        {
          respondent: this.name.trim() || null,
          data: JSON.stringify(d),
          summary: haggleSummary(d, this.cur),
        },
      );
    } catch (e: any) {
      this.error = `Saving failed: ${e?.message ?? e}`;
    }
    this.step = 'done';
    this.host?.done({
      summary: this.result ? haggleSummary(this.result, this.cur) : '',
      responseId: this.responseId,
    });
  }
  get doneLine() {
    const d = this.result;
    if (!d) return '';
    return d.outcome === 'deal'
      ? `Deal at ${this.money(d.dealPrice)}. Nicely done.`
      : `You walked away at ${this.money(d.refusedAsk)}. Fair enough.`;
  }
  openResponse = () => {
    if (this.responseId)
      this.args.viewCard?.(new URL(this.responseId) as any, 'isolated');
  };
  again = () => {
    this.responseId = '';
    this.step = 'intro';
  };

  // ─── results: who would pay what ──────────────────────────────────────
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
            module: new URL('./haggle', here).href,
            name: 'HaggleResponse',
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
  get datas() {
    return this.responses
      .map((r) => ({ r, d: parseJson<HaggleData | null>(r.data, null) }))
      .filter((x) => x.d);
  }
  // each person as a bracket on a price line from 0 to list
  get brackets() {
    const top = this.list || 1;
    const at = (n: number) => Math.min(100, Math.max(0, (n / top) * 100));
    return this.datas.map(({ r, d }) => {
      const lo = d!.low ?? 0;
      const hi = d!.high ?? top;
      return {
        who: r.respondent || 'Anonymous',
        style: htmlSafe(
          `left:${at(lo).toFixed(1)}%;width:${Math.max(0.8, at(hi) - at(lo)).toFixed(1)}%`,
        ),
        open: d!.high === null,
        label:
          d!.outcome === 'deal'
            ? `deal ${this.money(d!.dealPrice)}`
            : `${this.money(d!.low)}–${this.money(d!.high)}`,
      };
    });
  }
  // the share sure to pay at least each price
  get atLeast() {
    const n = this.datas.length || 1;
    const steps = [0.5, 0.6, 0.7, 0.8, 0.9, 1].map((f) =>
      Math.round(this.list * f),
    );
    return steps.map((p) => {
      const k = this.datas.filter(({ d }) => (d!.low ?? 0) >= p).length;
      const pct = Math.round((k / n) * 100);
      return { p: this.money(p), pct, bar: htmlSafe(`height:${pct}%`) };
    });
  }
  get allReasons() {
    return this.datas.flatMap(({ d }) => d!.reasons);
  }
  get floorNote() {
    return `${this.seller} never goes below ${this.money(this.floor)} (hidden from respondents).`;
  }
  showTake = () => (this.tab = 'take');
  showResults = () => (this.tab = 'results');
  open = (card: any) => this.args.viewCard?.(card, 'isolated');

  <template>
    <article class='sv hq {{if this.host "hosted"}}'>
      <header class='top'>
        <div>
          <p class='kicker'>Haggle</p>
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
            <div class='product'>
              <p class='pname'>{{@model.product}}</p>
              {{#if @model.details}}<p
                  class='pdesc'
                >{{@model.details}}</p>{{/if}}
              <p class='price'>{{this.money this.list}}
                <small>{{@model.unit}}</small></p>
            </div>
            <p class='lead'>A quick role-play:
              {{this.seller}}
              is selling this, and you're the buyer. Haggle the way you really
              would, or walk away. Nothing is actually bought.</p>
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
                disabled={{if this.list false true}}
                {{on 'click' this.start}}
              >Start</button></div>
          {{else if (eq this.step 'chat')}}
            <div class='bar'>
              <span class='who'><span class='av'>{{this.seller}}</span></span>
              <span class='now'>Asking <b>{{this.askLabel}}</b></span>
            </div>
            <ol class='chat' aria-live='polite'>
              {{#each this.shown as |t|}}
                <li class={{if t.mine 'me' 'them'}}>{{t.text}}</li>
              {{/each}}
              {{#if this.thinking}}<li class='them typing'>…</li>{{/if}}
            </ol>
            {{#unless this.finalRound}}
              <div class='say'>
                <textarea
                  rows='2'
                  value={{this.draft}}
                  placeholder='Make an offer, ask a question, push back…'
                  aria-label='Your reply'
                  {{on 'input' this.setDraft}}
                  {{on 'keydown' this.key}}
                ></textarea>
                <button
                  type='button'
                  class='primary'
                  disabled={{if this.draft (if this.thinking true false) true}}
                  {{on 'click' this.send}}
                >Send</button>
              </div>
            {{/unless}}
            <div class='actions'>
              <button
                type='button'
                class='quiet'
                disabled={{this.thinking}}
                {{on 'click' this.takeDeal}}
              >Deal at {{this.askLabel}}</button>
              <button
                type='button'
                class='link'
                disabled={{this.thinking}}
                {{on 'click' this.walk}}
              >Walk away</button>
            </div>
          {{else if (eq this.step 'saving')}}
            <p class='lead muted'>Saving…</p>
          {{else}}
            <p class='lead'><b>{{this.doneLine}}</b>
              That was the whole thing; thanks for playing along.</p>
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
            {{if (eq this.responses.length 1) 'response' 'responses'}}. List
            {{this.money this.list}}.
            {{this.floorNote}}</p>
          <div class='card'>
            <h2>Sure to pay at least</h2>
            <div class='cols'>
              {{#each this.atLeast as |a|}}
                <div class='col'><span class='pct'>{{a.pct}}%</span><span
                    class='well'
                  ><span style={{a.bar}}></span></span><span
                    class='p'
                  >{{a.p}}</span></div>
              {{/each}}
            </div>
          </div>
          <div class='card'>
            <h2>Each person: what they'd pay, from best offer to the price they
              walked from</h2>
            {{#each this.brackets as |b|}}
              <div class='brow'><span class='bw'>{{b.who}}</span><span
                  class='line'
                ><span
                    class='seg {{if b.open "open"}}'
                    style={{b.style}}
                  ></span></span><span class='bl'>{{b.label}}</span></div>
            {{/each}}
          </div>
          {{#if this.allReasons.length}}
            <div class='card'><h2>What they argued</h2><ul>{{#each
                  this.allReasons
                  as |x|
                }}<li>{{x}}</li>{{/each}}</ul></div>
          {{/if}}
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
      .hq {
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
      .muted {
        color: var(--sv-muted);
      }
      .product {
        display: grid;
        gap: 6px;
        padding: 18px;
        border-radius: 12px;
        background: var(--sv-paper);
        border: 1px solid var(--sv-rule);
        max-width: 460px;
      }
      .pname {
        margin: 0;
        font-weight: 600;
        font-size: 18px;
      }
      .pdesc {
        margin: 0;
        color: var(--sv-muted);
        line-height: 1.5;
        font-size: 14px;
      }
      .price {
        margin: 4px 0 0;
        font: 600 28px/1 var(--sv-sans);
      }
      .price small {
        font-size: 14px;
        font-weight: 500;
        color: var(--sv-muted);
      }
      .field {
        display: grid;
        gap: 6px;
        max-width: 360px;
        font-size: 13px;
        color: var(--sv-muted);
      }
      input[type='text'],
      textarea {
        font: 400 15px/1.45 var(--sv-sans);
        padding: 10px 12px;
        border-radius: 9px;
        border: 1px solid var(--sv-rule);
        background: var(--sv-paper);
        color: var(--sv-ink);
      }
      .bar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 12px;
        padding-bottom: 12px;
        border-bottom: 1px solid var(--sv-rule);
      }
      .av {
        display: inline-flex;
        align-items: center;
        gap: 8px;
        font-weight: 600;
      }
      .av::before {
        content: '';
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: #3f8a6e;
      }
      .now {
        font-size: 14px;
        color: var(--sv-muted);
      }
      .now b {
        color: var(--sv-ink);
        font-size: 18px;
        margin-left: 4px;
      }
      .chat {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 8px;
        max-height: 420px;
        overflow-y: auto;
      }
      .chat li {
        max-width: 78%;
        padding: 10px 14px;
        border-radius: 14px;
        line-height: 1.45;
        font-size: 15px;
      }
      .chat .them {
        justify-self: start;
        background: var(--sv-paper);
        border: 1px solid var(--sv-rule);
        border-bottom-left-radius: 4px;
      }
      .chat .me {
        justify-self: end;
        background: var(--sv-ink);
        color: var(--sv-paper);
        border-bottom-right-radius: 4px;
      }
      .typing {
        color: var(--sv-muted);
        letter-spacing: 2px;
      }
      .say {
        display: flex;
        gap: 8px;
        align-items: end;
      }
      .say textarea {
        flex: 1;
        min-width: 0;
        resize: none;
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
      .card {
        display: grid;
        gap: 10px;
        padding: 16px 18px;
        border-radius: 12px;
        background: var(--sv-panel);
        border: 1px solid var(--sv-rule);
      }
      h2 {
        margin: 0;
        font-size: 12px;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--sv-muted);
      }
      .cols {
        display: grid;
        grid-template-columns: repeat(6, 1fr);
        gap: 10px;
      }
      .col {
        display: grid;
        gap: 4px;
        justify-items: center;
        font-size: 12px;
      }
      .pct {
        font: 600 13px/1 var(--sv-mono);
      }
      .well {
        position: relative;
        width: 100%;
        height: 80px;
        border-radius: 6px;
        background: var(--sv-paper);
        overflow: hidden;
      }
      .well span {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        background: var(--sv-ink);
      }
      .p {
        color: var(--sv-muted);
        font-family: var(--sv-mono);
      }
      .brow {
        display: grid;
        grid-template-columns: minmax(80px, 140px) 1fr auto;
        gap: 12px;
        align-items: center;
        font-size: 13px;
      }
      .bw {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .line {
        position: relative;
        height: 10px;
        border-radius: 5px;
        background: var(--sv-paper);
      }
      .seg {
        position: absolute;
        top: 0;
        bottom: 0;
        border-radius: 5px;
        background: var(--sv-live);
      }
      .seg.open {
        background: linear-gradient(
          90deg,
          var(--sv-live),
          rgba(226, 85, 59, 0.1)
        );
      }
      .bl {
        font: 500 12px/1 var(--sv-mono);
        color: var(--sv-muted);
        white-space: nowrap;
      }
      .card ul {
        margin: 0;
        padding-left: 18px;
        display: grid;
        gap: 4px;
        line-height: 1.45;
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
        .chat li {
          max-width: 90%;
        }
        .cols {
          grid-template-columns: repeat(3, 1fr);
        }
      }
    </style>
  </template>
}

class Fitted extends Component<typeof HaggleQuestion> {
  <template>
    <div class='tf'>
      <span class='icon'><HandshakeIcon width='18' height='18' /></span>
      <div class='txt'><b>{{@model.cardTitle}}</b><span>Haggle</span></div>
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

export class HaggleQuestion extends CardDef {
  static displayName = 'Haggle Question';
  static icon = HandshakeIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: HaggleQuestion) {
      return this.title;
    },
  });
  @field brief = contains(TextAreaField);
  @field product = contains(StringField); // what is on sale
  @field details = contains(TextAreaField); // what the buyer is told about it
  @field currency = contains(StringField); // symbol, e.g. $
  @field unit = contains(StringField); // e.g. "a month"
  @field listPrice = contains(NumberField);
  @field floorPrice = contains(NumberField); // the seller never goes below this; hidden
  @field seller = contains(StringField); // the seller's name
  @field context = contains(TextAreaField); // what the interviewer knows about this person
  static isolated = Isolated;
  static embedded = Fitted;
  static fitted = Fitted;
}

// ─── one person's haggle ─────────────────────────────────────────────────
class ResponseView extends Component<typeof HaggleResponse> {
  get d() {
    return parseJson<HaggleData | null>(this.args.model.data, null);
  }
  get cur() {
    return (this.args.model.question as any)?.currency || '$';
  }
  get turns() {
    return (this.d?.turns ?? []).map((t) => ({
      ...t,
      mine: t.who === 'them',
      tag:
        t.who === 'seller' && typeof t.ask === 'number'
          ? `asks ${this.cur}${t.ask}`
          : typeof t.offer === 'number'
            ? `offers ${this.cur}${t.offer}`
            : '',
    }));
  }
  <template>
    <article class='hr'>
      <p class='kicker'>Haggle response{{#if @model.question}}
          ·
          {{@model.question.cardTitle}}{{/if}}</p>
      <h1>{{if @model.respondent @model.respondent 'Anonymous'}}</h1>
      <p class='summary'>{{@model.summary}}</p>
      <ol class='chat'>
        {{#each this.turns as |t|}}
          <li class={{if t.mine 'me' 'them'}}><span>{{t.text}}</span>{{#if
              t.tag
            }}<em>{{t.tag}}{{#if t.reason}}
                  ·
                  {{t.reason}}{{/if}}</em>{{/if}}</li>
        {{/each}}
      </ol>
    </article>
    <style scoped>
      .hr {
        padding: clamp(16px, 4cqw, 40px);
        display: grid;
        gap: 18px;
        max-width: 760px;
        margin: 0 auto;
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
      .chat {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 8px;
      }
      .chat li {
        max-width: 80%;
        display: grid;
        gap: 4px;
        padding: 10px 14px;
        border-radius: 14px;
        line-height: 1.45;
        font-size: 14px;
      }
      .chat .them {
        justify-self: start;
        background: #fff;
        border: 1px solid #e4e0d8;
      }
      .chat .me {
        justify-self: end;
        background: #1d1c1a;
        color: #fbfaf7;
      }
      .chat em {
        font:
          normal 500 11px/1.3 ui-monospace,
          monospace;
        opacity: 0.65;
      }
    </style>
  </template>
}

class ResponseRow extends Component<typeof HaggleResponse> {
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

export class HaggleResponse extends CardDef {
  static displayName = 'Haggle Response';
  static icon = HandshakeIcon;
  @field question = linksTo(() => HaggleQuestion);
  @field respondent = contains(StringField);
  @field takenAt = contains(StringField);
  @field data = contains(TextAreaField); // JSON: HaggleData
  @field summary = contains(TextAreaField); // for the interviewer
  @field cardTitle = contains(StringField, {
    computeVia: function (this: HaggleResponse) {
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

export { Isolated as HaggleTool };
