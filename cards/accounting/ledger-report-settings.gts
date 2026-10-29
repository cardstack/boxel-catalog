// How a statement is read: its basis, its columns and what it's compared with. QuickBooks keeps one
// set of these on every report; here they sit on the report card, and the engine below turns the
// books' postings into the figures each setting asks for. Accrual totals by month come from the
// closed months' snapshots; cash basis and columns by class or customer need each posting, so they
// read the journal and the documents still posted as cards (invoices, bills, opening balances).
import { markDefinition } from '@cardstack/base';
import {
  FieldDef,
  field,
  contains,
  getRelationshipMembershipState,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import enumField from '@cardstack/base/enum';
import GlimmerComponent from '@glimmer/component';
import { Select } from '@cardstack/pretui/components/select';
import { journalPostings, seqText } from './ledger-journal';
import { RECEIVABLES, PAYABLES } from './ledger-settings';
import { partialNote } from './record-kit';

export const ReportBasisField = markDefinition(
  enumField(StringField, {
    displayName: 'Report basis',
    options: [
      { value: 'accrual', label: 'Accrual' },
      { value: 'cash', label: 'Cash' },
    ],
  }),
);
export const ReportColumnsField = markDefinition(
  enumField(StringField, {
    displayName: 'Report columns',
    options: [
      { value: 'total', label: 'Total only' },
      { value: 'month', label: 'Months' },
      { value: 'quarter', label: 'Quarters' },
      { value: 'class', label: 'Classes' },
      { value: 'party', label: 'Customer or vendor' },
    ],
  }),
);
export const ReportCompareField = markDefinition(
  enumField(StringField, {
    displayName: 'Report comparison',
    options: [
      { value: 'none', label: 'No comparison' },
      { value: 'previous-period', label: 'Previous period' },
      { value: 'previous-year', label: 'Previous year' },
    ],
  }),
);

export class ReportView extends FieldDef {
  static displayName = 'Report view';
  @field basis = contains(ReportBasisField); // empty reads as accrual
  @field columns = contains(ReportColumnsField); // empty reads as total only
  @field compare = contains(ReportCompareField); // empty reads as none
}

export interface ViewChoice {
  basis: 'accrual' | 'cash';
  columns: 'total' | 'month' | 'quarter' | 'class' | 'party';
  compare: 'none' | 'previous-period' | 'previous-year';
}
export const viewOf = (v: ReportView | undefined): ViewChoice => ({
  basis: v?.basis === 'cash' ? 'cash' : 'accrual',
  columns:
    (['month', 'quarter', 'class', 'party'] as const).find(
      (c) => c === v?.columns,
    ) ?? 'total',
  compare:
    (['previous-period', 'previous-year'] as const).find(
      (c) => c === v?.compare,
    ) ?? 'none',
});
export const isPlainView = (v: ViewChoice) =>
  v.basis === 'accrual' && v.columns === 'total' && v.compare === 'none';

// ── months ───────────────────────────────────────────────────────────────────
const shiftMonth = (ym: string, n: number) => {
  let [y, m] = ym.split('-').map(Number);
  let d = new Date(Date.UTC(y, m - 1 + n, 1));
  return d.toISOString().slice(0, 7);
};
/** Every month from one to another, inclusive (yyyy-mm). */
export function monthsBetween(from: string, to: string): string[] {
  let out: string[] = [];
  for (let m = from; m && m <= to && out.length < 240; m = shiftMonth(m, 1))
    out.push(m);
  return out;
}
/** The period a comparison reads: the same length just before, or the same months a year earlier. */
export function comparePeriod(
  from: string,
  to: string,
  compare: ViewChoice['compare'],
): { from: string; to: string; label: string } | undefined {
  if (!from || !to || compare === 'none') return undefined;
  if (compare === 'previous-year')
    return {
      from: shiftMonth(from, -12),
      to: shiftMonth(to, -12),
      label: 'Previous year',
    };
  let n = monthsBetween(from, to).length;
  return {
    from: shiftMonth(from, -n),
    to: shiftMonth(from, -1),
    label: 'Previous period',
  };
}
export const quarterOf = (ym: string) =>
  `${ym.slice(0, 4)} Q${Math.ceil(Number(ym.slice(5, 7)) / 3)}`;

// ── postings, as each basis reads them ──────────────────────────────────────
/** One posting line: debits less credits, with its date, class and the party of its document. */
export interface ReportEntry {
  date: string;
  account: string;
  net: number;
  cls: string;
  party: string;
  doc: string; // the document it came from
  kind: string; // the kind of document: a journal posting's kind, or invoice, bill, opening
}
interface LineLike {
  account?: string;
  debitMinor?: number;
  creditMinor?: number;
  date?: string;
  cls?: string;
  party?: string;
  doc?: string;
}
interface Sources {
  journal?: unknown[];
  invoices?: unknown[];
  bills?: unknown[];
  openings?: unknown[];
}
const entry = (
  l: LineLike,
  date: string,
  party: string,
  share = 1,
  doc = '',
  kind = '',
): ReportEntry => ({
  date,
  account: l.account ?? '',
  net: Math.round(((l.debitMinor ?? 0) - (l.creditMinor ?? 0)) * share),
  cls: l.cls ?? '',
  party: l.party || party,
  doc: l.doc || doc,
  kind,
});
// A posting's document, or its number in the journal when it has none (a journal entry, a schedule).
const docOf = (p: { source: string; month: string; seq: number }) =>
  p.source || seqText(p.month, p.seq);
const docLines = (d: any): LineLike[] =>
  ((d?.ledgerLines ?? []) as LineLike[]).filter(Boolean);

/** Every posting line, on the accrual basis: as each document posted it. */
export function accrualEntries(src: Sources): ReportEntry[] {
  let out: ReportEntry[] = [];
  for (let p of journalPostings(src.journal))
    for (let l of p.lines)
      out.push(entry(l, p.date, p.party, 1, docOf(p), p.kind));
  for (let [docs, partyKey] of [
    [src.invoices, 'customerId'],
    [src.bills, 'vendorId'],
    [src.openings, ''],
  ] as const)
    for (let d of (docs ?? []).filter(Boolean) as any[])
      for (let l of docLines(d))
        out.push(
          entry(
            l,
            l.date || d.date || '',
            partyKey ? d[partyKey] : '',
            1,
            d.docNo ?? d.billNo ?? (partyKey ? '' : 'Opening balances'),
            partyKey === 'customerId'
              ? 'invoice'
              : partyKey
                ? 'bill'
                : 'opening',
          ),
        );
  return out;
}

// What the cash basis leaves out: the documents that only move a receivable or payable. Their income
// and expense count instead when payments are applied to them.
const NOT_CASH = new Set(['credit-memo', 'write-off', 'vendor-credit', 'void']);

/**
 * Every posting line on the cash basis, as QuickBooks re-times it: an invoice's or bill's lines count
 * on the day a payment is applied to it, in the share that payment covers, and the documents that
 * only adjust what's owed (credit memos, write-offs, vendor credits, voids) don't count. Everything
 * else posts as it did.
 */
export function cashEntries(src: Sources): ReportEntry[] {
  let out: ReportEntry[] = [];
  let invoices = new Map(
    ((src.invoices ?? []).filter(Boolean) as any[]).map((d) => [d.docNo, d]),
  );
  let bills = new Map(
    ((src.bills ?? []).filter(Boolean) as any[]).map((d) => [
      `${d.vendorId}|${d.billNo}`,
      d,
    ]),
  );
  // A payment's share of what its document bought, rounded so the shares add up to the payment: the
  // last line takes what rounding the others left over.
  let paidShare = (
    doc: any,
    amountMinor: number,
    payDate: string,
    party: string,
  ) => {
    let total = doc.totalMinor ?? 0;
    // The receivable or payable line is what the payment settles; the rest is what it bought.
    let lines = docLines(doc).filter(
      (l) => l.account !== RECEIVABLES && l.account !== PAYABLES,
    );
    if (!total || !lines.length) return;
    let share = amountMinor / total,
      whole = lines.reduce(
        (n, l) => n + (l.debitMinor ?? 0) - (l.creditMinor ?? 0),
        0,
      ),
      target = Math.round(whole * share),
      sofar = 0;
    lines.forEach((l, i) => {
      let e = entry(
        l,
        payDate,
        party,
        share,
        doc.docNo ?? doc.billNo ?? '',
        doc.billNo ? 'bill' : 'invoice',
      );
      if (i === lines.length - 1) e.net = target - sofar;
      sofar += e.net;
      out.push(e);
    });
  };
  // journalPostings leaves out a reversed posting with its reversal, payment and all.
  for (let p of journalPostings(src.journal)) {
    if (NOT_CASH.has(p.kind)) continue;
    for (let l of p.lines)
      out.push(entry(l, p.date, p.party, 1, docOf(p), p.kind));
    for (let i of p.items) {
      if (p.kind === 'customer-payment') {
        let d = invoices.get(i.ref);
        if (d)
          paidShare(d, i.amountMinor ?? 0, p.date ?? '', d.customerId ?? '');
      } else if (p.kind === 'bill-payment') {
        let d = bills.get(`${p.party}|${i.ref}`);
        if (d) paidShare(d, i.amountMinor ?? 0, p.date ?? '', d.vendorId ?? '');
      }
    }
  }
  for (let d of (src.openings ?? []).filter(Boolean) as any[])
    for (let l of docLines(d))
      out.push(
        entry(l, l.date || d.date || '', '', 1, 'Opening balances', 'opening'),
      );
  return out;
}

/** Net per account for each column key, over entries dated within the months given. */
export function netByColumn(
  entries: ReportEntry[],
  from: string,
  to: string,
  columnOf: (e: ReportEntry) => string,
): Map<string, Map<string, number>> {
  let out = new Map<string, Map<string, number>>();
  for (let e of entries) {
    let m = e.date.slice(0, 7);
    if (!m || m < from || m > to) continue;
    let col = columnOf(e),
      byCol = out.get(e.account) ?? new Map<string, number>();
    byCol.set(col, (byCol.get(col) ?? 0) + e.net);
    out.set(e.account, byCol);
  }
  return out;
}

/** How a column groups an entry. */
export const columnKey =
  (columns: ViewChoice['columns']) =>
  (e: ReportEntry): string =>
    columns === 'month'
      ? e.date.slice(0, 7)
      : columns === 'quarter'
        ? quarterOf(e.date.slice(0, 7))
        : columns === 'class'
          ? e.cls || '(none)'
          : columns === 'party'
            ? e.party || '(none)'
            : 'total';

// ── reading the postings a report needs ─────────────────────────────────────
/** A report's posted documents, dated in the months it reads, newest first so a capped page drops the oldest. */
export const viewDocuments = () => ({
  filter: {
    every: [
      { eq: { status: 'posted' } },
      {
        range: { date: { gte: '$this.readFromDate', lte: '$this.readToDate' } },
      },
    ],
  },
  sort: [{ by: 'date', direction: 'desc' as const }],
  page: { size: 1000 },
});
export const POSTING_SOURCES = [
  'journal',
  'invoices',
  'bills',
  'openings',
] as const;
const SOURCE_NOUNS: Record<string, string> = {
  journal: 'journal months',
  invoices: 'invoices',
  bills: 'bills',
  openings: 'opening balances',
};
/** Whether a report's posting sources have loaded; reading this starts the loads. */
export function sourcesLoaded(
  card: object,
  fields: readonly string[] = POSTING_SOURCES,
) {
  fields.forEach((f) => (card as Record<string, unknown>)[f]);
  return fields.every(
    (f) => getRelationshipMembershipState(card as never, f as never).isLoaded,
  );
}
/** A note for each source read only to its page, since its figures are then incomplete. */
export function sourceNotes(
  card: object,
  fields: readonly string[] = POSTING_SOURCES,
) {
  return fields
    .map((f) => partialNote(card, f, SOURCE_NOUNS[f]))
    .filter(Boolean);
}

// ── the controls a statement shows above itself ─────────────────────────────
const BASIS = [
  { value: 'accrual', label: 'Accrual' },
  { value: 'cash', label: 'Cash' },
];
const COLUMNS = [
  { value: 'total', label: 'Total only' },
  { value: 'month', label: 'Months' },
  { value: 'quarter', label: 'Quarters' },
  { value: 'class', label: 'Classes' },
  { value: 'party', label: 'Customer or vendor' },
];
const COMPARE = [
  { value: 'none', label: 'No comparison' },
  { value: 'previous-period', label: 'Previous period' },
  { value: 'previous-year', label: 'Previous year' },
];

interface ControlsSignature {
  Args: {
    model: { view?: ReportView };
    // The choices this statement offers: cash basis, and which column groupings.
    cash?: boolean;
    columns?: ViewChoice['columns'][];
  };
}
/** Basis, columns and comparison for a statement, saved on its card. */
export class ReportViewControls extends GlimmerComponent<ControlsSignature> {
  get choice() {
    return viewOf(this.args.model.view);
  }
  get columnOptions() {
    let allowed = this.args.columns;
    return allowed
      ? COLUMNS.filter((c) => allowed.includes(c.value as never))
      : COLUMNS;
  }
  basisOptions = BASIS;
  compareOptions = COMPARE;
  choose = (key: keyof ViewChoice, value: string) => {
    this.args.model.view = new ReportView({ ...this.choice, [key]: value });
  };
  setBasis = (value: string) => this.choose('basis', value);
  setColumns = (value: string) => this.choose('columns', value);
  setCompare = (value: string) => this.choose('compare', value);
  <template>
    <div class='report-view' data-report-view>
      {{#if @cash}}<label class='report-view-choice'>Basis<Select
            @options={{this.basisOptions}}
            @value={{this.choice.basis}}
            @onChange={{this.setBasis}}
          /></label>{{/if}}
      {{#if this.columnOptions.length}}<label
          class='report-view-choice'
        >Columns<Select
            @options={{this.columnOptions}}
            @value={{this.choice.columns}}
            @onChange={{this.setColumns}}
          /></label>{{/if}}
      <label class='report-view-choice'>Compare with<Select
          @options={{this.compareOptions}}
          @value={{this.choice.compare}}
          @onChange={{this.setCompare}}
        /></label>
    </div>
    <style scoped>
      .report-view {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
        align-items: end;
      }
      .report-view-choice {
        display: grid;
        gap: var(--boxel-sp-4xs);
        min-width: 10rem;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
