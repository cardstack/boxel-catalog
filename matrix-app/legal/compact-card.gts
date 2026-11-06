// The compact card parts the contract-execution cards share (legal/* and
// audit/audit-entry): one isolated layout, one embedded layout, one fitted
// layout over FitTile, and one atom, so every card reads the same way.
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { FitTile } from '../shared/fit-tile';

export type Tone = 'success' | 'info' | 'warning' | 'danger' | 'neutral';

export interface Dot {
  label: string;
  tone?: Tone;
}
export interface StatItem {
  label: string;
  value: string;
  hint?: string;
  tone?: Tone;
}
/** A ruled key-value row; `mono` sets ids, money and dates in mono. */
export interface Fact {
  key: string;
  value: string;
  mono?: boolean;
}
export interface Row {
  title: string;
  sub?: string;
  dot?: Dot;
}

const STAT_TONES: Tone[] = ['success', 'info', 'warning'];

/** Stats with the strip's default dot colours (green, blue, orange). */
export function stats(items: StatItem[]): StatItem[] {
  return items.map((s, i) => ({ ...s, tone: s.tone ?? STAT_TONES[i % 3] }));
}

export function dash(v?: string | null): string {
  return v && String(v).trim().length ? String(v) : '—';
}

/** "$100k" / "$48,000": the stat strip's short money. */
export function shortMoney(amount?: number | null, code?: string | null) {
  if (typeof amount !== 'number') return '—';
  let sym = !code || code === 'USD' ? '$' : `${code} `;
  if (amount >= 100_000 && amount % 1000 === 0) {
    return `${sym}${(amount / 1000).toLocaleString('en-US')}k`;
  }
  return `${sym}${amount.toLocaleString('en-US')}`;
}

/** "USD 100,000": the details rows' money. */
export function longMoney(amount?: number | null, code?: string | null) {
  if (typeof amount !== 'number') return '—';
  return `${code ?? 'USD'} ${amount.toLocaleString('en-US')}`;
}

function toDate(d?: Date | string | null): Date | undefined {
  if (!d) return undefined;
  // a bare 'YYYY-MM-DD' is a calendar day, not UTC midnight
  let date =
    d instanceof Date
      ? d
      : /^\d{4}-\d{2}-\d{2}$/.test(d)
        ? new Date(`${d}T00:00:00`)
        : new Date(d);
  return isNaN(date.getTime()) ? undefined : date;
}
/** "Feb 4, 2026" */
export function longDate(d?: Date | string | null): string {
  let date = toDate(d);
  return date
    ? date.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '—';
}
/** ["Feb 4", "2026"]: a stat value and its grey line. */
export function dayAndYear(d?: Date | string | null): [string, string] {
  let date = toDate(d);
  if (!date) return ['—', ''];
  return [
    date.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    }),
    String(date.getFullYear()),
  ];
}

export function cap(s?: string | null): string {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : '—';
}

// ── Mark: the type mark (initials in a square) ───────────────────────────
interface MarkSignature {
  Args: { text: string; size?: 'sm' | 'md' | 'lg' };
}
export const Mark: TemplateOnlyComponent<MarkSignature> = <template>
  <span class='cc-mark' data-size={{@size}} aria-hidden='true'>{{@text}}</span>
  <style scoped>
    .cc-mark {
      display: inline-grid;
      place-items: center;
      flex: none;
      inline-size: 1.75rem;
      block-size: 1.75rem;
      border-radius: var(--radius);
      background: var(--muted);
      color: var(--foreground);
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 700;
    }
    .cc-mark[data-size='lg'] {
      inline-size: 2.25rem;
      block-size: 2.25rem;
      font-size: 0.75rem;
    }
    .cc-mark[data-size='sm'] {
      inline-size: 1.125rem;
      block-size: 1.125rem;
      font-size: 0.5rem;
    }
  </style>
</template>;

// ── DotText: status as dot + text, never a pill ──────────────────────────
interface DotTextSignature {
  Args: { label: string; tone?: Tone };
}
export const DotText: TemplateOnlyComponent<DotTextSignature> = <template>
  <span class='cc-dot' data-tone={{if @tone @tone 'neutral'}}>{{@label}}</span>
  <style scoped>
    .cc-dot {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      min-inline-size: 0;
      font-size: 0.75rem;
      font-weight: 600;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      --cc-dot: var(--muted-foreground);
    }
    .cc-dot::before {
      content: '';
      flex: none;
      inline-size: 0.4375rem;
      block-size: 0.4375rem;
      border-radius: 50%;
      background: var(--cc-dot);
    }
    .cc-dot[data-tone='success'] {
      --cc-dot: var(--success);
    }
    .cc-dot[data-tone='info'] {
      --cc-dot: var(--info);
    }
    .cc-dot[data-tone='warning'] {
      --cc-dot: var(--warning);
    }
    .cc-dot[data-tone='danger'] {
      --cc-dot: var(--destructive);
    }
  </style>
</template>;

// ── Facts: ruled key-value rows, mono caps labels ────────────────────────
interface FactsSignature {
  Args: { items: Fact[] };
}
export const Facts: TemplateOnlyComponent<FactsSignature> = <template>
  <dl class='cc-facts'>
    {{#each @items as |f|}}
      <div class='cc-fact'>
        <dt>{{f.key}}</dt>
        <dd class={{if f.mono 'is-mono'}}>{{f.value}}</dd>
      </div>
    {{/each}}
  </dl>
  <style scoped>
    .cc-facts {
      margin: 0;
      display: grid;
    }
    .cc-fact {
      display: grid;
      grid-template-columns: minmax(6rem, 2fr) minmax(0, 3fr);
      align-items: baseline;
      gap: var(--boxel-sp-xs);
      padding-block: var(--boxel-sp-5xs);
      border-top: 1px solid var(--border);
    }
    .cc-fact dt {
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .cc-fact dd {
      margin: 0;
      min-inline-size: 0;
      font-size: 0.75rem;
      overflow-wrap: anywhere;
    }
    .cc-fact dd.is-mono {
      font-family: var(--font-mono);
      font-size: 0.6875rem;
      font-variant-numeric: tabular-nums;
      color: var(--muted-foreground);
    }
  </style>
</template>;

// ── Rows: equal-height list rows, title + grey line, dot status ──────────
interface RowsSignature {
  Args: { rows: Row[] };
}
export const Rows: TemplateOnlyComponent<RowsSignature> = <template>
  <ul class='cc-rows'>
    {{#each @rows as |r|}}
      <li class='cc-row'>
        <span class='cc-row-id'>
          <span class='cc-row-title'>{{r.title}}</span>
          {{#if r.sub}}<span class='cc-row-sub'>{{r.sub}}</span>{{/if}}
        </span>
        {{#if r.dot}}<DotText
            @label={{r.dot.label}}
            @tone={{r.dot.tone}}
          />{{/if}}
      </li>
    {{/each}}
  </ul>
  <style scoped>
    .cc-rows {
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .cc-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: var(--boxel-sp-xs);
      padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
      border-top: 1px solid var(--border);
    }
    .cc-row-id {
      display: grid;
      flex: 1;
      min-inline-size: 0;
    }
    .cc-row > :last-child:not(.cc-row-id) {
      flex: none;
    }
    .cc-row-title {
      font-size: 0.75rem;
      font-weight: 600;
    }
    .cc-row-sub {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
  </style>
</template>;

// ── Dots: a wrapping strip of dot + text items ───────────────────────────
interface DotsSignature {
  Args: { items: Dot[] };
}
export const Dots: TemplateOnlyComponent<DotsSignature> = <template>
  <p class='cc-dots'>
    {{#each @items as |d|}}<DotText
        @label={{d.label}}
        @tone={{d.tone}}
      />{{/each}}
  </p>
  <style scoped>
    .cc-dots {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp-5xs) var(--boxel-sp);
      margin: 0;
      padding: var(--boxel-sp-xs);
    }
  </style>
</template>;

// ── Section: a flat block with a small bold title ────────────────────────
interface SectionSignature {
  Args: { title: string; flush?: boolean };
  Blocks: { default: [] };
}
export const Section: TemplateOnlyComponent<SectionSignature> = <template>
  <section class='cc-section {{if @flush "is-flush"}}'>
    <h2 class='cc-section-title'>{{@title}}</h2>
    <div class='cc-section-body'>{{yield}}</div>
  </section>
  <style scoped>
    .cc-section {
      min-inline-size: 0;
      border: 1px solid var(--border);
      border-radius: var(--radius);
      background: var(--card);
      color: var(--card-foreground);
    }
    .cc-section-title {
      margin: 0;
      padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-5xs);
      font-size: 0.75rem;
      font-weight: 700;
    }
    .cc-section-body {
      padding: 0 var(--boxel-sp-xs) var(--boxel-sp-xs);
      font-size: 0.75rem;
      line-height: 1.6;
    }
    .is-flush .cc-section-body {
      padding: 0;
    }
  </style>
</template>;

/** A paragraph inside a Section. */
export const Text: TemplateOnlyComponent<{ Blocks: { default: [] } }> =
  <template>
    <p class='cc-text'>{{yield}}</p>
    <style scoped>
      .cc-text {
        margin: 0;
        padding-block-start: var(--boxel-sp-5xs);
        white-space: pre-line;
      }
    </style>
  </template>;

// ── LinkRow: a label + a linked card's bare atom ─────────────────────────
interface LinkRowSignature {
  Args: { label: string };
  Blocks: { default: [] };
}
export const LinkRow: TemplateOnlyComponent<LinkRowSignature> = <template>
  <div class='cc-link'>
    <span class='cc-link-k'>{{@label}}</span>
    <span class='cc-link-v'>{{yield}}</span>
  </div>
  <style scoped>
    .cc-link {
      display: grid;
      grid-template-columns: minmax(6rem, 2fr) minmax(0, 3fr);
      align-items: center;
      gap: var(--boxel-sp-xs);
      padding-block: var(--boxel-sp-5xs);
      border-top: 1px solid var(--border);
    }
    .cc-link-k {
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .cc-link-v {
      display: flex;
      flex-wrap: wrap;
      min-inline-size: 0;
      font-size: 0.75rem;
    }
  </style>
</template>;

// ── Isolated: header, stat strip, two columns ────────────────────────────
interface IsolatedSignature {
  Args: {
    title: string;
    subtitle?: string;
    statuses?: Dot[];
    stats?: StatItem[];
  };
  Blocks: {
    /** the type mark or an avatar */
    mark: [];
    /** primary action buttons, right of the statuses */
    actions: [];
    /** the module's main content, as Sections */
    main: [];
    /** Linked then Details, as Sections */
    side: [];
  };
}
export const IsoLayout: TemplateOnlyComponent<IsolatedSignature> = <template>
  <article class='cc-iso'>
    <div class='cc-top'>
      <header class='cc-head'>
        {{yield to='mark'}}
        <div class='cc-id'>
          <h1 class='cc-title'>{{@title}}</h1>
          {{#if @subtitle}}<p class='cc-sub'>{{@subtitle}}</p>{{/if}}
        </div>
        <div class='cc-state'>
          {{#each @statuses as |d|}}<DotText
              @label={{d.label}}
              @tone={{d.tone}}
            />{{/each}}
          {{yield to='actions'}}
        </div>
      </header>
      {{#if @stats}}
        <dl class='cc-stats'>
          {{#each @stats as |s|}}
            <div class='cc-stat'>
              <dt class='cc-stat-k' data-tone={{s.tone}}>{{s.label}}</dt>
              <dd class='cc-stat-v'>{{s.value}}</dd>
              {{#if s.hint}}<dd class='cc-stat-h'>{{s.hint}}</dd>{{/if}}
            </div>
          {{/each}}
        </dl>
      {{/if}}
    </div>
    <div class='cc-cols'>
      <div class='cc-col'>{{yield to='main'}}</div>
      <div class='cc-col'>{{yield to='side'}}</div>
    </div>
  </article>
  <style scoped>
    .cc-iso {
      container-type: inline-size;
      box-sizing: border-box;
      min-block-size: 100%;
      display: grid;
      align-content: start;
      gap: var(--boxel-sp-xs);
      padding: var(--boxel-sp-xs);
      background: var(--muted);
      color: var(--card-foreground);
      font-family: var(--font-sans);
      font-size: 0.75rem;
    }
    .cc-top {
      border: 1px solid var(--border);
      border-radius: var(--radius);
      background: var(--card);
      overflow: hidden;
    }
    .cc-head {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: var(--boxel-sp-xs);
      padding: var(--boxel-sp-xs);
    }
    .cc-id {
      flex: 1 1 12rem;
      min-inline-size: 0;
    }
    .cc-title {
      margin: 0;
      font-size: 0.8125rem;
      font-weight: 700;
      line-height: 1.4;
    }
    .cc-sub {
      margin: 0;
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
    .cc-state {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs);
    }
    .cc-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
      margin: 0;
      border-top: 1px solid var(--border);
    }
    .cc-stat {
      display: grid;
      padding: var(--boxel-sp-xs);
      border-inline-end: 1px solid var(--border);
    }
    .cc-stat:last-child {
      border-inline-end: 0;
    }
    .cc-stat dd {
      margin: 0;
    }
    .cc-stat-k {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
      --cc-dot: var(--muted-foreground);
    }
    .cc-stat-k::before {
      content: '';
      inline-size: 0.375rem;
      block-size: 0.375rem;
      border-radius: 50%;
      background: var(--cc-dot);
    }
    .cc-stat-k[data-tone='success'] {
      --cc-dot: var(--success);
    }
    .cc-stat-k[data-tone='info'] {
      --cc-dot: var(--info);
    }
    .cc-stat-k[data-tone='warning'] {
      --cc-dot: var(--warning);
    }
    .cc-stat-k[data-tone='danger'] {
      --cc-dot: var(--destructive);
    }
    .cc-stat-v {
      font-size: 1.375rem;
      font-weight: 700;
      line-height: 1.3;
      font-variant-numeric: tabular-nums;
    }
    .cc-stat-h {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
    .cc-cols {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
      gap: var(--boxel-sp-xs);
      align-items: start;
    }
    .cc-col {
      display: grid;
      gap: var(--boxel-sp-xs);
      min-inline-size: 0;
    }
    @container (width < 40rem) {
      .cc-cols {
        grid-template-columns: minmax(0, 1fr);
      }
    }
  </style>
</template>;

// ── Embedded: header line, one fact line, ruled rows ─────────────────────
interface EmbeddedSignature {
  Args: {
    title: string;
    subtitle?: string;
    status?: Dot;
    fact?: string;
    facts?: Fact[];
  };
  Blocks: { mark: []; linked: [] };
}
export const EmbLayout: TemplateOnlyComponent<EmbeddedSignature> = <template>
  <article class='cc-emb'>
    <header class='cc-emb-head'>
      {{yield to='mark'}}
      <div class='cc-emb-id'>
        <h3 class='cc-emb-title'>{{@title}}</h3>
        {{#if @subtitle}}<p class='cc-emb-sub'>{{@subtitle}}</p>{{/if}}
      </div>
      {{#if @status}}<DotText
          @label={{@status.label}}
          @tone={{@status.tone}}
        />{{/if}}
    </header>
    {{#if @fact}}<p class='cc-emb-fact'>{{@fact}}</p>{{/if}}
    {{#if @facts}}<Facts @items={{@facts}} />{{/if}}
    {{#if (has-block 'linked')}}{{yield to='linked'}}{{/if}}
  </article>
  <style scoped>
    .cc-emb {
      container-type: inline-size;
      display: grid;
      gap: var(--boxel-sp-5xs);
      padding: var(--boxel-sp-xs);
      background: var(--card);
      color: var(--card-foreground);
      font-family: var(--font-sans);
      font-size: 0.75rem;
    }
    .cc-emb-head {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      min-inline-size: 0;
    }
    .cc-emb-id {
      flex: 1;
      min-inline-size: 0;
    }
    .cc-emb-title,
    .cc-emb-sub {
      margin: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .cc-emb-title {
      font-size: 0.8125rem;
      font-weight: 700;
    }
    .cc-emb-sub,
    .cc-emb-fact {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
    .cc-emb-fact {
      margin: 0;
      padding-block-end: var(--boxel-sp-5xs);
    }
  </style>
</template>;

// ── Fitted: FitTile, then ruled fact rows that fill the rest ─────────────
interface FittedStat {
  key: string;
  value: string;
}
interface FittedSignature {
  Args: {
    title: string;
    subtitle?: string;
    status?: Dot;
    fact?: string;
    facts?: Fact[];
    stats?: FittedStat[];
  };
  Blocks: { mark: [] };
}
export const FitLayout: TemplateOnlyComponent<FittedSignature> = <template>
  <div class='cc-fitx'>
    <div class='cc-fitx-tile'>
      <FitTile class='cc-fit'>
        <:avatar>{{yield to='mark'}}</:avatar>
        <:title><span
            class='cc-fit-title'
            role='heading'
            aria-level='3'
          >{{@title}}</span></:title>
        <:subtitle>{{@subtitle}}</:subtitle>
        <:status>{{#if @status}}<DotText
              @label={{@status.label}}
              @tone={{@status.tone}}
            />{{/if}}</:status>
        <:fact>{{@fact}}</:fact>
      </FitTile>
    </div>
    {{#if @stats}}
      <dl class='cc-fitx-stats'>
        {{#each @stats as |s|}}
          <div class='cc-fitx-stat'><dt>{{s.key}}</dt><dd>{{s.value}}</dd></div>
        {{/each}}
      </dl>
    {{/if}}
    {{#if @facts}}
      {{! a column of whole rows: a row that does not fit wraps into a second
        column past the right edge, so the list fills any height and never
        shows half a row }}
      <dl class='cc-fitx-facts'>
        {{#each @facts as |f|}}
          <div class='cc-fitx-fact'>
            <dt>{{f.key}}</dt>
            <dd class={{if f.mono 'is-mono'}}>{{f.value}}</dd>
          </div>
        {{/each}}
      </dl>
    {{/if}}
  </div>
  <style scoped>
    .cc-fitx {
      display: flex;
      flex-direction: column;
      block-size: 100%;
      overflow: hidden;
      font-family: var(--font-sans);
    }
    .cc-fitx-tile {
      flex: 1 1 0;
      min-block-size: 0;
    }
    .cc-fit-title {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .cc-fitx-stats,
    .cc-fitx-facts {
      display: none;
      margin: 0;
      padding: 0 var(--boxel-sp-sm);
    }
    .cc-fitx-stats {
      grid-template-columns: repeat(3, minmax(0, 1fr));
      border-top: 1px solid var(--border);
    }
    .cc-fitx-stat {
      padding: var(--boxel-sp-5xs) var(--boxel-sp-xs) var(--boxel-sp-5xs) 0;
      border-inline-end: 1px solid var(--border);
      min-inline-size: 0;
    }
    .cc-fitx-stat:last-child {
      border-inline-end: 0;
    }
    .cc-fitx-stat dt,
    .cc-fitx-fact dt {
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
      white-space: nowrap;
    }
    .cc-fitx-stat dd {
      margin: 0;
      font-size: 0.75rem;
      font-weight: 700;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .cc-fitx-facts {
      flex: 1 1 0;
      min-block-size: 0;
      flex-direction: column;
      flex-wrap: wrap;
      align-content: flex-start;
      column-gap: var(--boxel-sp-xl);
      overflow: hidden;
    }
    .cc-fitx-fact {
      box-sizing: border-box;
      inline-size: 100%;
      display: flex;
      align-items: baseline;
      justify-content: space-between;
      gap: var(--boxel-sp-xs);
      padding-block: var(--boxel-sp-5xs);
      border-top: 1px solid var(--border);
    }
    .cc-fitx-fact dd {
      margin: 0;
      min-inline-size: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-size: 0.75rem;
    }
    .cc-fitx-fact dd.is-mono {
      font-family: var(--font-mono);
      font-size: 0.6875rem;
      font-variant-numeric: tabular-nums;
    }
    /* 170 tall and up: the tile keeps its own height, the rows fill the rest */
    @container fitted-card (height >= 170px) {
      .cc-fitx-tile {
        flex: none;
      }
      .cc-fitx-facts {
        display: flex;
      }
    }
    @container fitted-card (height >= 400px) and (width >= 400px) {
      .cc-fitx-stats {
        display: grid;
      }
    }
  </style>
</template>;

// ── Atom: mark + name on one line ────────────────────────────────────────
interface AtomSignature {
  Args: { title?: string };
  Blocks: { mark: [] };
}
export const AtomLayout: TemplateOnlyComponent<AtomSignature> = <template>
  <span class='cc-atom'>
    {{yield to='mark'}}
    <span class='cc-atom-name'>{{@title}}</span>
  </span>
  <style scoped>
    .cc-atom {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      max-inline-size: 100%;
      min-inline-size: 0;
      vertical-align: middle;
      font-size: 0.75rem;
      font-weight: 600;
    }
    .cc-atom-name {
      min-inline-size: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  </style>
</template>;

/** low → green, medium → orange, high and critical → red. */
export function riskTone(level?: string | null): Tone {
  return level === 'low'
    ? 'success'
    : level === 'medium'
      ? 'warning'
      : level === 'high' || level === 'critical'
        ? 'danger'
        : 'neutral';
}
