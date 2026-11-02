// Accord record kit: the shared frames every record card (event, document, observation,
// payroll run, import evidence) composes, so the brand lives in one stylesheet.
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import Component from '@glimmer/component';
import { cached } from '@glimmer/tracking';
import { mayBeLiveRender } from '@cardstack/base/render-context';
import {
  getRelationshipMembershipState,
  type CardContext,
  type ViewCardFn,
} from '@cardstack/base/card-api';
import { codeRef, realmURL } from '@cardstack/runtime-common';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import {
  Descriptions,
  type DescriptionsItem,
} from '@cardstack/pretui/components/descriptions';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import {
  StatementTable,
  type StatementColumn,
  type StatementRow,
} from './components/statement-table';

export const STAR =
  'M32 2C33.6 21.4 36.4 26.6 50 30C36.4 33.4 33.6 38.6 32 62C30.4 38.6 27.6 33.4 14 30C27.6 26.6 30.4 21.4 32 2Z';
// The Accord symbol: two brackets held by one rule, an 8-unit square-ended stroke on a 64 grid. Never filled.
export const ACCORD = 'M28 8H8V56 M36 56H56V8 M20 32H44';
/** The Accord symbol in the current text colour. Size it with width/height on the class. */
export const AccordMark: TemplateOnlyComponent<{ Element: SVGSVGElement }> =
  <template>
    <svg viewBox='0 0 64 64' aria-hidden='true' ...attributes><path
        d={{ACCORD}}
        fill='none'
        stroke='currentColor'
        stroke-width='8'
        stroke-linecap='butt'
        stroke-linejoin='miter'
      /></svg>
  </template>;
export type Tone =
  | 'neutral'
  | 'success'
  | 'warning'
  | 'attention'
  | 'info'
  | 'danger';
// What each status *means*, once for the whole app; StatusChip draws it. A status not listed here
// would otherwise get a colour hashed from its label.
export const STATUS_TONE: Record<string, Tone> = {
  Draft: 'neutral',
  Void: 'neutral',
  Voided: 'neutral',
  Posted: 'info',
  Open: 'info',
  open: 'info',
  Running: 'info',
  'On hand': 'info',
  Corrected: 'info',
  Evidence: 'info',
  '1099': 'info',
  Required: 'info',
  Partial: 'warning',
  'Part paid': 'warning',
  Unpaid: 'warning',
  Undeposited: 'warning',
  'Ready to close': 'warning',
  Missing: 'warning',
  Paid: 'success',
  Matched: 'success',
  Added: 'success',
  Active: 'success',
  Balanced: 'success',
  Deposited: 'success',
  Reconciled: 'success',
  Closed: 'success',
  closed: 'success',
  Sealed: 'success',
  sealed: 'success',
  'Signed off': 'success',
  Complete: 'success',
  'In service': 'success',
  'Ties to the ledger': 'success',
  'Ties to cash': 'success',
  'All checks pass': 'success',
  'On file': 'success',
  favourable: 'success',
  'Needs review': 'attention',
  'For review': 'attention',
  'Not ready': 'attention',
  Reversal: 'attention',
  Overdue: 'attention',
  Unbalanced: 'danger',
  'Does not tie': 'danger',
  'Out of balance': 'danger',
  unfavourable: 'danger',
  'Written off': 'neutral',
  Reversed: 'neutral',
  'Used up': 'neutral',
  Disposed: 'neutral',
  'No 1099': 'neutral',
  Excluded: 'neutral',
  Inactive: 'neutral',
  'Below threshold': 'neutral',
  journaled: 'neutral',
};
export const toneFor = (status: string | undefined): Tone => {
  const s = status ?? '';
  return (
    STATUS_TONE[s] ??
    (s.startsWith('Draft')
      ? 'neutral'
      : s.startsWith('Duplicate')
        ? 'info'
        : s.startsWith('Out of balance')
          ? 'danger'
          : s.startsWith('Accepted') || s.startsWith('Recognized')
            ? 'success'
            : 'neutral')
  );
};
const DATE = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  timeZone: 'UTC',
});
export const day = (value: unknown) => {
  if (!value) return '';
  const d =
    value instanceof Date
      ? value
      : new Date(
          String(value).length === 10 ? `${value}T00:00:00Z` : String(value),
        );
  return Number.isNaN(d.getTime()) ? String(value) : DATE.format(d);
};
// Whole days from one ISO date to another.
export const days = (from: string, to: string) =>
  Math.round(
    (Date.parse(to + 'T00:00:00Z') - Date.parse(from + 'T00:00:00Z')) / 864e5,
  );
const PERCENT = new Intl.NumberFormat('en-US', {
  style: 'percent',
  minimumFractionDigits: 1,
  maximumFractionDigits: 1,
});
// A ratio (0.25) as a percentage to one decimal (25.0%).
export const percent = (ratio: number) => PERCENT.format(ratio);
// Says so when a query-backed relationship holds only its first page of matches.
export const partialNote = (card: object, field: string, noun?: string) => {
  try {
    let s = getRelationshipMembershipState(
      card as never,
      field as never,
    ) as any;
    return s?.isPartial
      ? `Showing ${s.membership?.length ?? '?'} of ${s.totalMatchCount}${noun ? ` ${noun}` : ''} — the report's page is too small.`
      : '';
  } catch {
    return '';
  }
};
// Money is integer cents everywhere. A negative is set in parentheses, the accounting sign.
const MONEY = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  currencySign: 'accounting',
});
export const money = (cents: number | null | undefined) =>
  MONEY.format((cents ?? 0) / 100);
const major = (minor: number | null | undefined) =>
  minor == null ? undefined : minor / 100;
const isNum = (v: unknown) => typeof v === 'number' && Number.isFinite(v);
interface MoneySig {
  Args: { minor: number | null | undefined; whole?: boolean; change?: boolean };
  Element: HTMLSpanElement;
}
/** An amount in cents, set by the kit's FormatNumber: accounting negatives, or a sign on a change. */
export const Money: TemplateOnlyComponent<MoneySig> = <template>
  <FormatNumber
    @value={{major @minor}}
    @style='currency'
    @currency='USD'
    @currencySign={{if @change 'standard' 'accounting'}}
    @signDisplay={{if @change 'exceptZero' 'auto'}}
    @maximumFractionDigits={{if @whole 0 2}}
    @minimumFractionDigits={{if @whole 0 2}}
    ...attributes
  />
</template>;

interface SheetSig {
  /** @figureMinor is the statement figure in cents (set by Money); @figure is for anything else, such as a count */
  Args: {
    eyebrow: string;
    title?: string;
    meta?: string;
    figure?: string;
    figureMinor?: number;
    figureLabel?: string;
    status?: string;
    note?: string;
  };
  Blocks: { default: [] };
  Element: HTMLElement;
}
/** Isolated frame: masthead with the Accord symbol, serif title, one statement figure, then the body. */
export const Sheet: TemplateOnlyComponent<SheetSig> = <template>
  <article class='ns-sheet' ...attributes>
    <div class='head'>
      <div class='id'>
        <p class='eyebrow'><AccordMark />{{@eyebrow}}</p>
        <h1>{{@title}}</h1>
        {{#if @meta}}<p class='meta'>{{@meta}}</p>{{/if}}
      </div>
      <div class='figure'>
        {{#if @status}}<StatusChip
            @value={{@status}}
            @tone={{toneFor @status}}
          />{{/if}}
        {{#if (isNum @figureMinor)}}<p class='fig'><Money
              @minor={{@figureMinor}}
            /></p><p class='eyebrow'>{{@figureLabel}}</p>
        {{else if @figure}}<p class='fig'>{{@figure}}</p><p
            class='eyebrow'
          >{{@figureLabel}}</p>{{/if}}
      </div>
    </div>
    <div class='body'>{{yield}}</div>
    {{#if @note}}<p class='note'>{{@note}}</p>{{/if}}
  </article>
  <style scoped>
    .ns-sheet {
      container: ns-sheet / inline-size;
      padding: 2.25rem 2.5rem 2rem;
      display: grid;
      gap: 1.75rem;
      min-width: 0;
    }
    .head {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 2rem;
      align-items: end;
      padding-bottom: 1.25rem;
      border-bottom: 1px solid var(--foreground);
    }
    .eyebrow {
      margin: 0;
      display: flex;
      gap: 0.45rem;
      align-items: center;
      font-family: var(--font-sans);
      font-size: 0.75rem;
      font-weight: 600;
      line-height: 1.33;
      letter-spacing: var(--track-eyebrow, 0.06em);
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .eyebrow svg {
      width: 0.85rem;
      height: 0.85rem;
      color: var(--foreground);
      flex: none;
    }
    h1 {
      font-family: var(--font-serif);
      font-size: 2rem;
      font-weight: 400;
      line-height: 1.25;
      letter-spacing: -0.01em;
      margin: 0.5rem 0 0.4rem;
      overflow-wrap: break-word;
      min-width: 0;
    }
    .meta {
      margin: 0;
      color: var(--muted-foreground);
      font-size: 0.875rem;
    }
    .figure {
      display: grid;
      justify-items: end;
      gap: 0.35rem;
      text-align: end;
    }
    .fig {
      margin: 0.25rem 0 0;
      font-family: var(--font-mono);
      font-size: 2rem;
      font-weight: 500;
      line-height: 1.1;
      letter-spacing: -0.02em;
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
    }
    .body {
      display: grid;
      gap: 1.5rem;
      min-width: 0;
    }
    .note {
      margin: 0;
      padding-top: 0.9rem;
      border-top: 1px solid var(--border);
      font-size: 0.75rem;
      line-height: 1.5;
      color: var(--muted-foreground);
      max-width: 62ch;
    }
    @container ns-sheet (max-width: 34rem) {
      .head {
        grid-template-columns: minmax(0, 1fr);
      }
      .figure {
        justify-items: start;
        text-align: start;
      }
      h1 {
        font-size: 1.75rem;
      }
      .fig {
        font-size: 2rem;
      }
    }
    @container ns-sheet (max-width: 30rem) {
      .ns-sheet {
        padding: 1.25rem;
      }
    }
  </style>
</template>;

interface PartSig {
  Args: { title: string };
  Blocks: { default: [] };
  Element: HTMLElement;
}
/** A titled band inside a Sheet: eyebrow heading on a hairline. */
export const Part: TemplateOnlyComponent<PartSig> = <template>
  <section class='ns-part' ...attributes><h2>{{@title}}</h2>{{yield}}</section>
  <style scoped>
    .ns-part {
      display: grid;
      gap: 0.6rem;
      min-width: 0;
    }
    h2 {
      margin: 0;
      padding-bottom: 0.4rem;
      border-bottom: 1px solid var(--border);
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-sm);
      font-weight: 600;
      line-height: 1.43;
      color: var(--foreground);
    }
  </style>
</template>;

/** A labelled value. `strong` sets it as a figure; `mono` marks a machine value (a number, a code). */
export interface Fact {
  key: string;
  value: string;
  strong?: boolean;
  mono?: boolean;
}
interface FactsSig {
  Args: { items: Fact[] };
  Element: HTMLDivElement;
}
type FactItem = DescriptionsItem & { strong?: boolean };
const factItems = (facts: Fact[] | undefined): FactItem[] =>
  (facts ?? []).filter(Boolean).map((f, i) => ({
    key: `${i}:${f.key}`,
    label: f.key,
    value: f.value,
    mono: f.mono,
    strong: f.strong,
  }));
const isStrong = (item: DescriptionsItem) => !!(item as FactItem).strong;
/** Label/value pairs on Pret UI Descriptions, which folds its columns to the space it has; a strong fact is set as a figure. */
export const Facts: TemplateOnlyComponent<FactsSig> = <template>
  <Descriptions
    @items={{factItems @items}}
    @layout='vertical'
    @columns={{4}}
    @size='s'
    @placeholder=''
    ...attributes
  >
    <:value as |item|>{{#if (isStrong item)}}<span
          class='ns-figure'
        >{{item.value}}</span>{{else}}{{item.value}}{{/if}}</:value>
  </Descriptions>
  <style scoped>
    .ns-figure {
      font-family: var(--font-mono);
      font-size: 1.375rem;
      font-weight: 500;
      line-height: 1.15;
      font-variant-numeric: tabular-nums;
    }
  </style>
</template>;

interface PostLine {
  accountCode?: string;
  accountName?: string;
  detail?: string;
  debitMinor?: number;
  creditMinor?: number;
}
interface LinesSig {
  Args: {
    lines: (PostLine | undefined)[] | undefined;
    label?: string;
    // The card the lines belong to, and the host's context: with them, each code links to its account.
    owner?: object;
    context?: CardContext;
    viewCard?: ViewCardFn;
  };
  Element: HTMLDivElement;
}
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;
const LINE_COLS: StatementColumn[] = [
  { key: 'code', label: 'No.', kind: 'code', width: '4.5rem' },
  { key: 'account', label: 'Account' },
  { key: 'dr', label: 'Debit', kind: 'amount', width: '8.5rem' },
  { key: 'cr', label: 'Credit', kind: 'amount', width: '8.5rem' },
];
/** The double-entry table on StatementTable: account, debit, credit, a ruled total, and the balance check as a status. */
export class Lines extends Component<LinesSig> {
  cols = LINE_COLS;
  get lines() {
    return (this.args.lines ?? []).filter(Boolean) as PostLine[];
  }
  get codes() {
    return [
      ...new Set(this.lines.map((l) => l.accountCode).filter(Boolean)),
    ] as string[];
  }
  // One lookup for the accounts on screen, made only for someone looking at the card: the indexer's
  // render of a document doesn't search for them.
  accountData = this.args.context?.getCards(
    this,
    () => {
      if (!this.codes.length || !mayBeLiveRender()) return undefined;
      let type = codeRef(here, './ledger-cards', 'LedgerAccount');
      return {
        filter: {
          every: [
            { type },
            { on: type, any: this.codes.map((code) => ({ eq: { code } })) },
          ],
        },
        page: { size: Math.max(this.codes.length, 1) },
      } as never;
    },
    () => {
      let r = (this.args.owner as any)?.[realmURL]?.href;
      return r ? [r] : [];
    },
    { isLive: true },
  );
  @cached
  get accounts(): Map<string, any> {
    return new Map(
      (((this.accountData as any)?.instances ?? []) as any[])
        .filter(Boolean)
        .map((a) => [a.code, a]),
    );
  }
  get selectable() {
    return this.args.viewCard ? this.openAccount : undefined;
  }
  openAccount = (row: StatementRow) => {
    let a = this.accounts.get(String(row.cells?.code ?? ''));
    if (a) this.args.viewCard?.(a, 'isolated');
  };
  get debit() {
    return this.lines.reduce((n, l) => n + (l.debitMinor ?? 0), 0);
  }
  get credit() {
    return this.lines.reduce((n, l) => n + (l.creditMinor ?? 0), 0);
  }
  get balanced() {
    return this.debit === this.credit;
  }
  get status() {
    return this.balanced
      ? 'Balanced'
      : `Out of balance by ${money(Math.abs(this.debit - this.credit))}`;
  }
  get rows(): StatementRow[] {
    let accounts = this.accounts;
    return [
      ...this.lines.map((l, i) => ({
        key: `${i}`,
        selectable: accounts.has(l.accountCode ?? ''),
        cells: {
          code: l.accountCode,
          account: [
            accounts.get(l.accountCode ?? '')?.name,
            l.accountName,
            l.detail,
          ]
            .filter(Boolean)
            .join(' · '),
          dr: l.debitMinor || null,
          cr: l.creditMinor || null,
        },
      })),
      {
        key: 'total',
        role: 'total' as const,
        cells: { code: '', account: 'Total', dr: this.debit, cr: this.credit },
      },
    ];
  }
  <template>
    <div class='ns-lines' ...attributes>
      <StatementTable
        @label={{if @label @label 'Posts to the ledger'}}
        @columns={{this.cols}}
        @rows={{this.rows}}
        @framed={{false}}
        @onRowSelect={{this.selectable}}
        @selectColumn='code'
      />
      <p class='ns-balance'><StatusChip
          @value={{this.status}}
          @tone={{if this.balanced 'success' 'danger'}}
        /></p>
    </div>
    <style scoped>
      .ns-lines {
        display: grid;
        gap: 0.5rem;
        min-width: 0;
      }
      .ns-balance {
        margin: 0;
      }
    </style>
  </template>
}
interface StripSig {
  Args: {
    eyebrow: string;
    title?: string;
    meta?: string;
    figure?: string;
    figureNote?: string;
    status?: string;
  };
  Element: HTMLElement;
}
/** Embedded frame: a ledger row with a serif title and a mono figure. */
export const Strip: TemplateOnlyComponent<StripSig> = <template>
  <article class='ns-strip' ...attributes>
    <div class='l'>
      <p class='eyebrow'>{{@eyebrow}}</p>
      <p class='t'>{{@title}}</p>
      {{#if @meta}}<p class='m'>{{@meta}}</p>{{/if}}
    </div>
    <div class='r'>
      {{#if @figure}}<p class='f'>{{@figure}}</p>{{/if}}
      {{#if @figureNote}}<p class='m'>{{@figureNote}}</p>{{/if}}
      {{#if @status}}<StatusChip
          @value={{@status}}
          @tone={{toneFor @status}}
        />{{/if}}
    </div>
  </article>
  <style scoped>
    .ns-strip {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto;
      gap: 1rem;
      align-items: start;
      padding: 0.9rem 1.1rem;
      min-width: 0;
    }
    .eyebrow {
      margin: 0;
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-2xs);
      font-weight: 600;
      line-height: 1.3;
      letter-spacing: var(--track-eyebrow, 0.06em);
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .t {
      margin: 0.2rem 0 0;
      font-family: var(--font-serif);
      font-size: var(--boxel-font-size-md);
      font-weight: 400;
      line-height: 1.2;
      overflow-wrap: break-word;
      min-width: 0;
    }
    .m {
      margin: 0.2rem 0 0;
      font-size: 0.75rem;
      color: var(--muted-foreground);
    }
    .r {
      display: grid;
      justify-items: end;
      gap: 0.3rem;
      text-align: end;
    }
    .f {
      margin: 0;
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size);
      font-weight: 500;
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
    }
  </style>
</template>;

interface FitSig {
  Args: { eyebrow: string; title?: string; figure?: string; meta?: string };
  Element: HTMLElement;
}
/** Fitted frame. Badge: title only; strip: title + figure; tile/card: everything. */
export const Fit: TemplateOnlyComponent<FitSig> = <template>
  <div class='ns-fit' ...attributes>
    <p class='eyebrow'><AccordMark /><span>{{@eyebrow}}</span></p>
    <p class='t'>{{@title}}</p>
    {{#if @figure}}<p class='f'>{{@figure}}</p>{{/if}}
    {{#if @meta}}<p class='m'>{{@meta}}</p>{{/if}}
  </div>
  <style scoped>
    .ns-fit {
      height: 100%;
      display: grid;
      grid-template-rows: auto minmax(0, 1fr) auto auto;
      gap: 0.25rem;
      padding: 0.7rem 0.8rem;
      overflow: hidden;
    }
    .eyebrow {
      margin: 0;
      display: flex;
      gap: 0.35rem;
      align-items: center;
      min-width: 0;
      font-family: var(--font-sans);
      font-size: var(--boxel-font-size-2xs);
      font-weight: 600;
      line-height: 1.2;
      letter-spacing: var(--track-eyebrow, 0.06em);
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .eyebrow span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .eyebrow svg {
      width: 0.75rem;
      height: 0.75rem;
      flex: none;
      color: var(--foreground);
    }
    .t {
      margin: 0;
      font-family: var(--font-serif);
      font-size: clamp(0.875rem, 9cqi, 1.35rem);
      font-weight: 400;
      line-height: 1.15;
      overflow: hidden;
      display: -webkit-box;
      -webkit-line-clamp: 3;
      -webkit-box-orient: vertical;
    }
    .f {
      margin: 0;
      font-family: var(--font-mono);
      font-size: clamp(0.8rem, 8cqi, 1.1rem);
      font-weight: 500;
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .m {
      margin: 0;
      font-size: 0.6875rem;
      color: var(--muted-foreground);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    @container fitted-card (max-height: 80px) {
      .ns-fit {
        grid-template-columns: minmax(0, 1fr) auto;
        grid-template-rows: 1fr;
        align-items: center;
        padding: 0.4rem 0.6rem;
      }
      .eyebrow,
      .m {
        display: none;
      }
      .t {
        -webkit-line-clamp: 1;
      }
    }
    @container fitted-card (max-width: 150px) and (max-height: 80px) {
      .f {
        display: none;
      }
    }
    @container fitted-card (min-height: 81px) and (max-height: 140px) {
      .m {
        display: none;
      }
      .t {
        -webkit-line-clamp: 2;
      }
    }
  </style>
</template>;
