import type { TemplateOnlyComponent } from '@ember/component/template-only';

// The compact parts the work-order, maintenance-plan and spare-part cards
// share: a type mark, dot + text status, a stat strip, flat ruled sections,
// key-value rows and a framed chip for links that are not cards.

/** ok | warn | bad | info | muted — mapped to the theme's status tokens. */
export type Tone = 'ok' | 'warn' | 'bad' | 'info' | 'muted';

export const Mark: TemplateOnlyComponent<{
  Args: { mark: string };
  Element: HTMLSpanElement;
}> = <template>
  <span class='mark' aria-hidden='true' ...attributes>{{@mark}}</span>
  <style scoped>
    .mark {
      flex: none;
      display: inline-grid;
      place-items: center;
      inline-size: 1.75rem;
      block-size: 1.75rem;
      border-radius: calc(var(--radius) * 0.6);
      background-color: var(--muted);
      color: var(--foreground);
      font-family: var(--font-mono);
      font-size: 0.5625rem;
      font-weight: 700;
    }
  </style>
</template>;

export const Dot: TemplateOnlyComponent<{
  Args: { tone?: Tone; label?: string | null };
  Element: HTMLSpanElement;
}> = <template>
  <span class='st' data-tone={{@tone}} ...attributes><span
      class='dot'
      aria-hidden='true'
    ></span>{{@label}}</span>
  <style scoped>
    .st {
      --tone: var(--muted-foreground);
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      font-weight: 600;
      white-space: nowrap;
    }
    .st[data-tone='ok'] {
      --tone: var(--success);
    }
    .st[data-tone='warn'] {
      --tone: var(--warning);
    }
    .st[data-tone='bad'] {
      --tone: var(--destructive);
    }
    .st[data-tone='info'] {
      --tone: var(--info);
    }
    .dot {
      flex: none;
      inline-size: 0.4375rem;
      block-size: 0.4375rem;
      border-radius: 50%;
      background-color: var(--tone);
    }
  </style>
</template>;

/** Mark + name + dot + state on one line; the name ellipsizes first. Framed
 * for a link that is not a card (an owner, a part line); bare as an atom. */
export const Chip: TemplateOnlyComponent<{
  Args: {
    mark: string;
    name?: string | null;
    tone?: Tone;
    meta?: string | null;
    bare?: boolean;
  };
  Element: HTMLSpanElement;
}> = <template>
  <span class='chip' data-bare={{@bare}} ...attributes>
    <span class='cm' aria-hidden='true'>{{@mark}}</span>
    <span class='cn'>{{if @name @name '—'}}</span>
    {{#if @tone}}<Dot @tone={{@tone}} @label={{@meta}} class='cs' />{{/if}}
  </span>
  <style scoped>
    .chip {
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
      font-size: 0.6875rem;
      line-height: 1.4;
      vertical-align: middle;
    }
    .chip[data-bare] {
      padding: 0;
      border: 0;
      background: none;
      font-size: 0.75rem;
    }
    .cm {
      flex: none;
      display: inline-grid;
      place-items: center;
      inline-size: 1rem;
      block-size: 1rem;
      border-radius: calc(var(--radius) * 0.5);
      background-color: var(--muted);
      font-family: var(--font-mono);
      font-size: 0.4375rem;
      font-weight: 700;
    }
    .cn {
      min-inline-size: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-weight: 600;
    }
    .cs {
      font-weight: 400;
      color: var(--muted-foreground);
    }
  </style>
</template>;

/** Isolated / embedded header: mark + bold name + one grey meta line. */
export const Head: TemplateOnlyComponent<{
  Args: { mark: string; title?: string | null; meta?: string };
  Blocks: { default: [] };
  Element: HTMLElement;
}> = <template>
  <header class='head' ...attributes>
    <div class='who'>
      <Mark @mark={{@mark}} />
      <div class='id'>
        <h1 class='name'>{{if @title @title 'Untitled'}}</h1>
        {{#if @meta}}<p class='meta'>{{@meta}}</p>{{/if}}
      </div>
    </div>
    {{#if (has-block)}}<div class='bar'>{{yield}}</div>{{/if}}
  </header>
  <style scoped>
    .head {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      padding: var(--boxel-sp-sm);
    }
    .who {
      display: flex;
      align-items: center;
      gap: var(--boxel-sp-xs);
      min-inline-size: 0;
    }
    .id {
      min-inline-size: 0;
    }
    .name {
      margin: 0;
      font-family: var(--font-sans);
      font-size: 0.8125rem;
      font-weight: 700;
      line-height: 1.3;
      letter-spacing: normal;
      text-transform: none;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .meta {
      margin: 0;
      font-size: 0.6875rem;
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .bar {
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
      font-size: 0.5625rem;
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .num {
      font-size: 1.375rem;
      font-weight: 700;
      line-height: 1.15;
      font-variant-numeric: tabular-nums;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .meta {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  </style>
</template>;

/** A flat section: small bold title over ruled content, one hairline below. */
export const Section: TemplateOnlyComponent<{
  Args: { title: string };
  Blocks: { default: [] };
  Element: HTMLElement;
}> = <template>
  <section class='sec' ...attributes>
    <h2 class='t'>{{@title}}</h2>
    {{yield}}
  </section>
  <style scoped>
    .sec {
      display: grid;
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      border-block-end: 1px solid var(--border);
      min-inline-size: 0;
    }
    .sec:last-child {
      border-block-end: 0;
    }
    .t {
      margin: 0;
      padding-block-end: var(--boxel-sp-5xs);
      border-block-end: 1px solid var(--border);
      font-family: var(--font-sans);
      font-size: 0.75rem;
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
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
      font-size: 0.5625rem;
      font-weight: 600;
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
      padding-inline-end: var(--boxel-sp-xs);
    }
    .v {
      flex-wrap: wrap;
      gap: var(--boxel-sp-5xs);
      font-size: 0.75rem;
      overflow-wrap: anywhere;
    }
  </style>
</template>;

/** A list row: bold title + grey sub line, dot + text state on the right. */
export const ItemRow: TemplateOnlyComponent<{
  Args: {
    title?: string | null;
    sub?: string | null;
    tone?: Tone;
    state?: string | null;
  };
  Element: HTMLDivElement;
}> = <template>
  <div class='row' ...attributes>
    <span class='lead'>
      <span class='t'>{{@title}}</span>
      {{#if @sub}}<span class='s'>{{@sub}}</span>{{/if}}
    </span>
    {{#if @state}}<Dot @tone={{@tone}} @label={{@state}} />{{/if}}
  </div>
  <style scoped>
    .row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: var(--boxel-sp-xs);
      padding-block: var(--boxel-sp-5xs);
      border-block-end: 1px solid var(--border);
      font-size: 0.75rem;
    }
    .row:last-child {
      border-block-end: 0;
    }
    .lead {
      display: grid;
      min-inline-size: 0;
    }
    .t {
      font-weight: 600;
    }
    .s {
      font-size: 0.6875rem;
      color: var(--muted-foreground);
    }
  </style>
</template>;

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

export function money(amount?: number | null, code?: string | null): string {
  if (amount == null) return '';
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency: code || 'USD',
  }).format(amount);
}

export function initials(name?: string | null): string {
  return (name ?? '')
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
}

const HUE_TONE: Record<string, Tone> = {
  green: 'ok',
  red: 'bad',
  orange: 'warn',
  amber: 'warn',
  blue: 'info',
  teal: 'info',
};
/** The vocabulary's hue names, as a status tone. */
export function hueTone(hue?: string | null): Tone {
  return HUE_TONE[hue ?? ''] ?? 'muted';
}
