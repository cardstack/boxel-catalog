// The compact parts the Asset, Asset Category and Meter cards share: a type
// mark, dot + text status, a one-line atom, the isolated head, ruled sections
// and rows. Layout only; every control is Pret UI.
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import type { Hue } from '../maintenance-vocabulary';

/** The vocabulary's hues as the dot tones these parts draw. */
export function toneOfHue(hue?: Hue | string | null): string | undefined {
  switch (hue) {
    case 'green':
      return 'ok';
    case 'amber':
    case 'orange':
      return 'warn';
    case 'red':
      return 'bad';
    case 'teal':
    case 'blue':
      return 'info';
    default:
      return undefined;
  }
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

export function money(amount?: number | null, code?: string | null): string {
  if (amount == null) return '—';
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: code || 'USD',
    maximumFractionDigits: 0,
  }).format(amount);
}

export function join(...parts: unknown[]): string {
  return parts.filter((p) => p != null && p !== '').join(' · ');
}

export interface KvItem {
  key: string;
  value: string;
}

interface DotSignature {
  Args: { tone?: string; label?: string | null };
  Element: HTMLSpanElement;
}

/** Status as dot + text; the text carries the meaning, the dot the tone. */
export const Dot: TemplateOnlyComponent<DotSignature> = <template>
  <span class='mt-dot' data-tone={{@tone}} ...attributes><span
      class='mt-dot-i'
      aria-hidden='true'
    ></span>{{#if @label}}<span class='mt-dot-t'>{{@label}}</span>{{/if}}</span>
  <style scoped>
    .mt-dot {
      --tone: var(--muted-foreground);
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      min-width: 0;
      font-weight: 600;
      white-space: nowrap;
    }
    .mt-dot[data-tone='ok'] {
      --tone: var(--success);
    }
    .mt-dot[data-tone='warn'] {
      --tone: var(--warning);
    }
    .mt-dot[data-tone='bad'] {
      --tone: var(--destructive);
    }
    .mt-dot[data-tone='info'] {
      --tone: var(--info);
    }
    .mt-dot-i {
      flex: none;
      width: 0.4375rem;
      height: 0.4375rem;
      border-radius: 50%;
      background-color: var(--tone);
    }
    .mt-dot-t {
      overflow: hidden;
      text-overflow: ellipsis;
    }
  </style>
</template>;

interface MarkSignature {
  Args: { text: string; size?: 'sm' | 'md' | 'lg' };
  Element: HTMLSpanElement;
}

/** The two-letter type mark (As, Ca, Me) that pairs with every name. */
export const Mark: TemplateOnlyComponent<MarkSignature> = <template>
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
      font-size: 0.6875rem;
    }
  </style>
</template>;

interface AtomLineSignature {
  Args: {
    mark: string;
    name?: string | null;
    tone?: string;
    meta?: string | null;
  };
  Element: HTMLSpanElement;
}

/** An atom: mark + name + dot + muted meta, the name ellipsising first. */
export const AtomLine: TemplateOnlyComponent<AtomLineSignature> = <template>
  <span class='mt-atom' ...attributes>
    <Mark @text={{@mark}} />
    <span class='mt-atom-n'>{{if @name @name '—'}}</span>
    {{#if @meta}}
      <Dot class='mt-atom-s' @tone={{@tone}} @label={{@meta}} />
    {{else if @tone}}
      <Dot @tone={{@tone}} />
    {{/if}}
  </span>
  <style scoped>
    .mt-atom {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-5xs);
      min-width: 0;
      max-width: 100%;
      font-size: 0.75rem;
      line-height: 1.4;
      vertical-align: middle;
      color: var(--card-foreground);
    }
    .mt-atom-n {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
      font-weight: 600;
    }
    .mt-atom-s {
      flex: none;
      font-weight: 400;
      color: var(--muted-foreground);
    }
  </style>
</template>;

interface HeadSignature {
  Args: { mark: string; title?: string | null; meta?: string | null };
  Blocks: { status: []; actions: [] };
  Element: HTMLElement;
}

/** Isolated head: mark + name + meta line; status and actions on the right. */
export const Head: TemplateOnlyComponent<HeadSignature> = <template>
  <header class='mt-head' ...attributes>
    <Mark @text={{@mark}} @size='lg' />
    <div class='mt-head-id'>
      <h1>{{@title}}</h1>
      {{#if @meta}}<p>{{@meta}}</p>{{/if}}
    </div>
    <div class='mt-head-bar'>
      {{#if (has-block 'status')}}<span class='mt-head-st'>{{yield
            to='status'
          }}</span>{{/if}}
      {{yield to='actions'}}
    </div>
  </header>
  <style scoped>
    .mt-head {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      padding: var(--boxel-sp-sm);
      --control-height: 1.625rem;
    }
    .mt-head-id {
      flex: 1 1 12rem;
      min-width: 0;
    }
    h1 {
      margin: 0;
      font-family: var(--font-sans);
      font-size: 0.8125rem;
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
    }
    p {
      margin: 0;
      font-size: 0.6875rem;
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

interface SectionSignature {
  Args: { title: string };
  Blocks: { default: [] };
  Element: HTMLElement;
}

/** A flat ruled section with a small bold title. */
export const Section: TemplateOnlyComponent<SectionSignature> = <template>
  <section class='mt-sec' ...attributes>
    <h2>{{@title}}</h2>
    {{yield}}
  </section>
  <style scoped>
    .mt-sec {
      padding-bottom: var(--boxel-sp-xs);
      --pretui-kv-label-font-size: 0.5625rem;
      --pretui-kv-label-letter-spacing: 0.13em;
      --pretui-kv-label-color: var(--muted-foreground);
    }
    .mt-sec + .mt-sec {
      border-top: 1px solid var(--border);
    }
    h2 {
      margin: 0;
      padding: var(--boxel-sp-xs) var(--boxel-sp-sm) var(--boxel-sp-5xs);
      font-family: var(--font-sans);
      font-size: 0.75rem;
      font-weight: 700;
      letter-spacing: normal;
      text-transform: none;
    }
    .mt-sec > :not(h2) {
      margin-inline: var(--boxel-sp-sm);
    }
    p {
      margin-block: 0;
    }
  </style>
</template>;

interface RowSignature {
  Args: {
    title?: string | null;
    meta?: string | null;
    tone?: string;
    state?: string | null;
  };
  Element: HTMLDivElement;
}

/** A ruled two-line row: bold title over grey meta, dot + text on the right. */
export const Row: TemplateOnlyComponent<RowSignature> = <template>
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
      font-size: 0.6875rem;
      color: var(--muted-foreground);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  </style>
</template>;

interface FactSignature {
  Args: { lead?: string; strong?: string | null; rest?: string | null };
  Element: HTMLParagraphElement;
}

/** The one fact line: "Next: **Quarterly service** · in 12 days". */
export const Fact: TemplateOnlyComponent<FactSignature> = <template>
  <span class='mt-fact' ...attributes>{{@lead}}
    <strong>{{@strong}}</strong>{{#if @rest}} · {{@rest}}{{/if}}</span>
  <style scoped>
    .mt-fact strong {
      font-weight: 700;
    }
  </style>
</template>;

interface SheetSignature {
  Blocks: { head: []; stats: []; main: []; side: [] };
  Element: HTMLElement;
}

/** The isolated layout: head, a joined stat strip, then main | side columns. */
export const Sheet: TemplateOnlyComponent<SheetSignature> = <template>
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
      font-size: 0.75rem;
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      overflow: hidden;
      --text-stat: 1.375rem;
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

interface BriefSignature {
  Args: { mark: string; title?: string | null; meta?: string | null };
  Blocks: { status: []; fact: []; default: [] };
  Element: HTMLElement;
}

/** The embedded layout: mark + name + meta, a dot line, one fact, ruled rows. */
export const Brief: TemplateOnlyComponent<BriefSignature> = <template>
  <article class='mt-brief' ...attributes>
    <header>
      <Mark @text={{@mark}} @size='md' />
      <div class='mt-brief-id'>
        <h3>{{@title}}</h3>
        {{#if @meta}}<p>{{@meta}}</p>{{/if}}
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
      font-size: 0.75rem;
      line-height: 1.4;
      color: var(--card-foreground);
      background-color: var(--card);
      --pretui-kv-label-font-size: 0.5625rem;
      --pretui-kv-label-letter-spacing: 0.13em;
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
      margin: 0;
      font-size: 0.8125rem;
      font-weight: 700;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    p {
      margin: 0;
      font-size: 0.6875rem;
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
      font-size: 0.75rem;
      color: var(--card-foreground);
    }
    .mt-brief-kv {
      border-top: 1px solid var(--border);
    }
  </style>
</template>;
