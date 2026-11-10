import type { TemplateOnlyComponent } from '@ember/component/template-only';

// The compact parts every maintenance card shares: a type mark, dot + text
// status, a one-line chip, the isolated head, a stat strip, ruled sections,
// rows and key-value lines, and the isolated and embedded layouts. Layout
// only; every control is Pret UI.

/** ok | warn | bad | info | muted — mapped to the theme's status tokens. */
export type Tone = 'ok' | 'warn' | 'bad' | 'info' | 'muted';

const HUE_TONE: Record<string, Tone> = {
  green: 'ok',
  red: 'bad',
  orange: 'warn',
  amber: 'warn',
  blue: 'info',
  teal: 'info',
};
/** The vocabulary's hue names as a status tone; no tone for other hues. */
export function hueTone(hue?: string | null): Tone | undefined {
  return HUE_TONE[hue ?? ''];
}

/** 'in-service' → 'in service' */
export function enumText(value?: string | null): string {
  return value ? value.replace(/-/g, ' ') : '—';
}

export function dash(v: unknown): string {
  return v == null || v === '' ? '—' : String(v);
}

export function num(n?: number | null, unit?: string | null): string {
  if (n == null) return '—';
  return `${n.toLocaleString()}${unit ? ` ${unit}` : ''}`;
}

export function join(...parts: unknown[]): string {
  return parts.filter((p) => p != null && p !== '').join(' · ');
}

function asDate(d?: Date | string | null): Date | undefined {
  if (!d) return undefined;
  // a bare YYYY-MM-DD is a calendar day, not UTC midnight
  let date =
    typeof d === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d)
      ? new Date(`${d}T00:00:00`)
      : new Date(d);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

export function shortDate(d?: Date | string | null): string {
  let date = asDate(d);
  return date
    ? date.toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '—';
}

export function monthYear(d?: Date | string | null): string {
  let date = asDate(d);
  return date
    ? date.toLocaleDateString(undefined, { month: 'short', year: 'numeric' })
    : '—';
}

export function fmtDay(d?: Date | string | null, year = false): string {
  if (!d) return '';
  let date = typeof d === 'string' ? new Date(d) : d;
  if (isNaN(date.getTime())) return '';
  return date.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    ...(year ? { year: 'numeric' } : {}),
  });
}

export function fmtStamp(d?: Date | string | null): string {
  if (!d) return '';
  let date = typeof d === 'string' ? new Date(d) : d;
  if (isNaN(date.getTime())) return '';
  return `${fmtDay(date, true)}, ${date.toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })}`;
}

/** A currency amount; `digits` caps the decimals (0 for whole amounts). */
export function money(
  amount?: number | null,
  code?: string | null,
  digits?: number,
): string {
  if (amount == null) return '—';
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: code || 'USD',
      ...(digits == null ? {} : { maximumFractionDigits: digits }),
    }).format(amount);
  } catch {
    // an unknown currency code throws; show the bare number
    return String(amount);
  }
}

export function initials(name?: string | null): string {
  return (name ?? '')
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
}

export interface KvItem {
  key: string;
  value: string;
}

/** Status as dot + text; the text carries the meaning, the dot the tone. */
export const Dot: TemplateOnlyComponent<{
  Args: { tone?: Tone | string; label?: string | null };
  Element: HTMLSpanElement;
}> = <template>
  <span class='mt-dot' data-tone={{@tone}} ...attributes><span
      class='mt-dot-i'
      aria-hidden='true'
    ></span>{{#if @label}}<span class='mt-dot-t'>{{@label}}</span>{{/if}}</span>
  <style scoped>
    .mt-dot {
      --_tone: var(--muted-foreground);
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      min-width: 0;
      font-weight: 600;
      white-space: nowrap;
    }
    .mt-dot[data-tone='ok'] {
      --_tone: var(--success);
    }
    .mt-dot[data-tone='warn'] {
      --_tone: var(--warning);
    }
    .mt-dot[data-tone='bad'] {
      --_tone: var(--destructive);
    }
    .mt-dot[data-tone='info'] {
      --_tone: var(--info);
    }
    .mt-dot-i {
      flex: none;
      width: 0.4375rem;
      height: 0.4375rem;
      border-radius: 50%;
      background-color: var(--_tone);
    }
    .mt-dot-t {
      overflow: hidden;
      text-overflow: ellipsis;
    }
  </style>
</template>;

/** The two-letter type mark (As, Ca, WO) that pairs with every name. Its
 * glyph is decorative and sized to the box, so it sits below the type ladder. */
export const Mark: TemplateOnlyComponent<{
  Args: { text: string; size?: 'sm' | 'md' | 'lg' };
  Element: HTMLSpanElement;
}> = <template>
  <span
    class='mt-mark'
    data-size={{if @size @size 'sm'}}
    aria-hidden='true'
    ...attributes
  >{{@text}}</span>
  <style scoped>
    .mt-mark {
      flex: none;
      display: inline-grid;
      place-items: center;
      width: 1rem;
      height: 1rem;
      border-radius: calc(var(--radius) * 0.4);
      background-color: var(--muted);
      font-family: var(--font-mono);
      font-size: 0.5rem;
      font-weight: 700;
      color: var(--foreground);
    }
    .mt-mark[data-size='md'] {
      width: 1.375rem;
      height: 1.375rem;
      font-size: 0.5625rem;
    }
    .mt-mark[data-size='lg'] {
      width: 2rem;
      height: 2rem;
      border-radius: calc(var(--radius) * 0.6);
      font-size: var(--boxel-font-size-2xs);
    }
  </style>
</template>;

/** Mark + name + dot + state on one line; the name ellipsizes first. Framed
 * for a link that is not a card (an owner, a part line); bare as an atom. */
export const Chip: TemplateOnlyComponent<{
  Args: {
    mark: string;
    name?: string | null;
    tone?: Tone | string;
    meta?: string | null;
    bare?: boolean;
  };
  Element: HTMLSpanElement;
}> = <template>
  <span class='mt-chip' data-bare={{@bare}} title={{@name}} ...attributes>
    <Mark @text={{@mark}} />
    <span class='mt-chip-n'>{{if @name @name '—'}}</span>
    {{#if @meta}}
      <Dot class='mt-chip-s' @tone={{@tone}} @label={{@meta}} />
    {{else if @tone}}
      <Dot @tone={{@tone}} />
    {{/if}}
  </span>
  <style scoped>
    .mt-chip {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      max-inline-size: 100%;
      min-inline-size: 0;
      padding: var(--boxel-sp-6xs) var(--boxel-sp-xs) var(--boxel-sp-6xs)
        var(--boxel-sp-6xs);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      background-color: var(--card);
      font-size: var(--boxel-font-size-2xs);
      line-height: 1.4;
      vertical-align: middle;
    }
    .mt-chip[data-bare] {
      padding: 0;
      border: 0;
      background: none;
      font-size: var(--boxel-font-size-xs);
    }
    .mt-chip-n {
      min-inline-size: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-weight: 600;
    }
    .mt-chip-s {
      flex: none;
      font-weight: 400;
      color: var(--muted-foreground);
    }
  </style>
</template>;

/** Isolated / embedded head: mark + bold name + one grey meta line, with
 * status and actions (or a plain default block) on the right. */
export const Head: TemplateOnlyComponent<{
  Args: { mark: string; title?: string | null; meta?: string | null };
  Blocks: { default: []; status: []; actions: [] };
  Element: HTMLElement;
}> = <template>
  <header class='mt-head' ...attributes>
    <Mark @text={{@mark}} @size='lg' />
    <div class='mt-head-id'>
      <h1>{{if @title @title 'Untitled'}}</h1>
      {{#if @meta}}<p>{{@meta}}</p>{{/if}}
    </div>
    {{#if (has-block)}}
      <div class='mt-head-bar'>{{yield}}</div>
    {{else if (has-block 'status')}}
      <div class='mt-head-bar'>
        <span class='mt-head-st'>{{yield to='status'}}</span>
        {{yield to='actions'}}
      </div>
    {{else if (has-block 'actions')}}
      <div class='mt-head-bar'>{{yield to='actions'}}</div>
    {{/if}}
  </header>
  <style scoped>
    .mt-head {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      padding: var(--boxel-sp-sm);
    }
    .mt-head-id {
      flex: 1 1 12rem;
      min-width: 0;
    }
    h1 {
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-sm);
      font-weight: 700;
      line-height: 1.3;
      letter-spacing: normal;
      text-transform: none;
    }
    p {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    .mt-head-bar,
    .mt-head-st {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
    }
  </style>
</template>;

export interface StatItem {
  label: string;
  value: string;
  meta?: string;
}

/** Joined stat strip; tiles draw right + bottom dividers clipped by the strip. */
export const Stats: TemplateOnlyComponent<{
  Args: { items: StatItem[] };
  Element: HTMLDivElement;
}> = <template>
  <div class='stats' ...attributes>
    {{#each @items as |s|}}
      <div class='stat'>
        <span class='cap'>{{s.label}}</span>
        <span class='num'>{{s.value}}</span>
        {{#if s.meta}}<span class='meta'>{{s.meta}}</span>{{/if}}
      </div>
    {{/each}}
  </div>
  <style scoped>
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
      overflow: hidden;
      border-block: 1px solid var(--border);
    }
    .stat {
      display: grid;
      align-content: start;
      gap: var(--boxel-sp-6xs);
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      margin: 0 -1px -1px 0;
      border-inline-end: 1px solid var(--border);
      border-block-end: 1px solid var(--border);
      min-inline-size: 0;
    }
    .cap {
      font-family: var(--font-mono);
      font-size: var(--boxel-eyebrow-font-size);
      font-weight: var(--boxel-eyebrow-font-weight);
      letter-spacing: var(--boxel-eyebrow-letter-spacing);
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .num {
      font-size: var(--boxel-font-size-lg);
      font-weight: 700;
      line-height: 1.15;
      font-variant-numeric: tabular-nums;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .meta {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  </style>
</template>;

/** A flat ruled section with a small bold title. */
export const Section: TemplateOnlyComponent<{
  Args: { title: string };
  Blocks: { default: [] };
  Element: HTMLElement;
}> = <template>
  <section class='mt-sec' ...attributes>
    <h2>{{@title}}</h2>
    {{yield}}
  </section>
  <style scoped>
    .mt-sec {
      min-inline-size: 0;
      padding-bottom: var(--boxel-sp-xs);
      --pretui-kv-label-font-size: var(--boxel-eyebrow-font-size);
      --pretui-kv-label-letter-spacing: var(--boxel-eyebrow-letter-spacing);
    }
    .mt-sec + .mt-sec {
      border-top: 1px solid var(--border);
    }
    h2 {
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-5xs);
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-xs);
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
    }
    .mt-sec > :not(h2) {
      margin-inline: var(--boxel-sp-sm);
    }
  </style>
</template>;

/** Ruled key-value list; put KvRow children inside. */
export const Kv: TemplateOnlyComponent<{
  Blocks: { default: [] };
  Element: HTMLDListElement;
}> = <template>
  <dl class='kv' ...attributes>{{yield}}</dl>
  <style scoped>
    .kv {
      display: grid;
      grid-template-columns: minmax(5rem, 30%) minmax(0, 1fr);
      margin: 0;
    }
  </style>
</template>;

export const KvRow: TemplateOnlyComponent<{
  Args: { label: string; value?: string | null };
  Blocks: { default: [] };
}> = <template>
  <dt class='k'>{{@label}}</dt>
  <dd class='v'>{{#if (has-block)}}{{yield}}{{else}}{{if
        @value
        @value
        '—'
      }}{{/if}}</dd>
  <style scoped>
    .k,
    .v {
      margin: 0;
      min-block-size: 1.75rem;
      display: flex;
      align-items: center;
      border-block-end: 1px solid var(--border);
      min-inline-size: 0;
    }
    .k {
      font-family: var(--font-mono);
      font-size: var(--boxel-eyebrow-font-size);
      font-weight: var(--boxel-eyebrow-font-weight);
      letter-spacing: var(--boxel-eyebrow-letter-spacing);
      text-transform: uppercase;
      color: var(--muted-foreground);
      padding-inline-end: var(--boxel-sp-xs);
    }
    .v {
      flex-wrap: wrap;
      gap: var(--boxel-sp-5xs);
      font-size: var(--boxel-font-size-xs);
      overflow-wrap: break-word;
    }
  </style>
</template>;

/** A ruled two-line row: bold title over grey meta, dot + text on the right. */
export const Row: TemplateOnlyComponent<{
  Args: {
    title?: string | null;
    meta?: string | null;
    tone?: Tone | string;
    state?: string | null;
  };
  Element: HTMLDivElement;
}> = <template>
  <div class='mt-row' ...attributes>
    <div class='mt-row-l'>
      <span class='mt-row-t'>{{@title}}</span>
      {{#if @meta}}<span class='mt-row-m'>{{@meta}}</span>{{/if}}
    </div>
    {{#if @state}}<Dot @tone={{@tone}} @label={{@state}} />{{/if}}
  </div>
  <style scoped>
    .mt-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: var(--boxel-sp-sm);
      padding-block: var(--boxel-sp-4xs);
      border-top: 1px solid var(--border);
    }
    .mt-row-l {
      display: flex;
      flex-direction: column;
      min-width: 0;
    }
    .mt-row-t {
      font-weight: 600;
    }
    .mt-row-m {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
      overflow-wrap: break-word;
    }
  </style>
</template>;

/** The one fact line: "Next: **Quarterly service** · in 12 days". */
export const Fact: TemplateOnlyComponent<{
  Args: { lead?: string; strong?: string | null; rest?: string | null };
  Element: HTMLSpanElement;
}> = <template>
  <span class='mt-fact' ...attributes>{{@lead}}
    <strong>{{@strong}}</strong>{{#if @rest}} · {{@rest}}{{/if}}</span>
  <style scoped>
    .mt-fact strong {
      font-weight: 700;
    }
  </style>
</template>;

/** The isolated layout: head, a joined stat strip, then main | side columns. */
export const Sheet: TemplateOnlyComponent<{
  Blocks: { head: []; stats: []; main: []; side: [] };
  Element: HTMLElement;
}> = <template>
  <article class='mt-sheet' ...attributes>
    {{yield to='head'}}
    <div class='mt-stats'>{{yield to='stats'}}</div>
    <div class='mt-cols'>
      <div class='mt-main'>{{yield to='main'}}</div>
      <aside class='mt-side'>{{yield to='side'}}</aside>
    </div>
  </article>
  <style scoped>
    .mt-sheet {
      container-type: inline-size;
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-xs);
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      overflow: hidden;
      --text-stat: var(--boxel-font-size-lg);
    }
    .mt-stats {
      display: grid;
      grid-auto-flow: column;
      grid-auto-columns: minmax(0, 1fr);
      gap: var(--boxel-sp-sm);
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      border-block: 1px solid var(--border);
    }
    .mt-stats > * {
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
    }
    .mt-stats > * + * {
      border-inline-start: 1px solid var(--border);
    }
    .mt-cols {
      display: grid;
      grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    }
    .mt-side {
      border-inline-start: 1px solid var(--border);
    }
    @container (max-width: 40rem) {
      .mt-stats {
        grid-auto-flow: row;
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
      .mt-stats > * {
        border-block-end: 1px solid var(--border);
      }
      .mt-stats > :nth-child(odd) {
        border-inline-start: 0;
      }
      .mt-cols {
        grid-template-columns: minmax(0, 1fr);
      }
      .mt-side {
        border-inline-start: 0;
        border-top: 1px solid var(--border);
      }
    }
  </style>
</template>;

/** The embedded layout: mark + name + meta, a dot line, one fact, ruled rows. */
export const Brief: TemplateOnlyComponent<{
  Args: { mark: string; title?: string | null; meta?: string | null };
  Blocks: { status: []; fact: []; default: [] };
  Element: HTMLElement;
}> = <template>
  <article class='mt-brief' ...attributes>
    <header>
      <Mark @text={{@mark}} @size='md' />
      <div class='mt-brief-id'>
        <h3 title={{@title}}>{{@title}}</h3>
        {{#if @meta}}<p title={{@meta}}>{{@meta}}</p>{{/if}}
      </div>
    </header>
    {{#if (has-block 'status')}}
      <div class='mt-brief-st'>{{yield to='status'}}</div>
    {{/if}}
    {{#if (has-block 'fact')}}
      <p class='mt-brief-fact'>{{yield to='fact'}}</p>
    {{/if}}
    <div class='mt-brief-kv'>{{yield}}</div>
  </article>
  <style scoped>
    .mt-brief {
      display: flex;
      flex-direction: column;
      gap: var(--boxel-sp-xs);
      padding: var(--boxel-sp-sm);
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-xs);
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
      --pretui-kv-label-font-size: var(--boxel-eyebrow-font-size);
      --pretui-kv-label-letter-spacing: var(--boxel-eyebrow-letter-spacing);
    }
    header {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      min-width: 0;
    }
    .mt-brief-id {
      min-width: 0;
    }
    h3 {
      font-size: var(--boxel-font-size-sm);
      font-weight: 700;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    p {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .mt-brief-st {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp-5xs) var(--boxel-sp-sm);
    }
    .mt-brief-fact {
      font-size: var(--boxel-font-size-xs);
      color: var(--card-foreground);
    }
    .mt-brief-kv {
      border-top: 1px solid var(--border);
    }
  </style>
</template>;
