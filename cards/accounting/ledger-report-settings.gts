// How a statement is read: its basis, its columns and what it's compared with. QuickBooks keeps one
// set of these on every report; here they sit on the report card, and the engine below turns the
// books' postings into the figures each setting asks for. Accrual totals by month come from the
// closed months' snapshots; cash basis and columns by class or customer need each posting, so they
// read the journal and the documents still posted as cards (invoices, bills, opening balances).
import { FieldDef, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import enumField from '@cardstack/base/enum';
import GlimmerComponent from '@glimmer/component';
import { Select } from '@cardstack/pretui/components/select';
import { journalPostings } from './ledger-journal';
import { RECEIVABLES, PAYABLES } from './ledger-settings';

export const ReportBasisField = enumField(StringField, {
  displayName: 'Report basis',
  options: [
    { value: 'accrual', label: 'Accrual' },
    { value: 'cash', label: 'Cash' },
  ],
});
export const ReportColumnsField = enumField(StringField, {
  displayName: 'Report columns',
  options: [
    { value: 'total', label: 'Total only' },
    { value: 'month', label: 'Months' },
    { value: 'quarter', label: 'Quarters' },
    { value: 'class', label: 'Classes' },
    { value: 'party', label: 'Customer or vendor' },
  ],
});
export const ReportCompareField = enumField(StringField, {
  displayName: 'Report comparison',
  options: [
    { value: 'none', label: 'No comparison' },
    { value: 'previous-period', label: 'Previous period' },
    { value: 'previous-year', label: 'Previous year' },
  ],
});

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
}
interface LineLike {
  account?: string;
  debitMinor?: number;
  creditMinor?: number;
  date?: string;
  cls?: string;
  party?: string;
}
interface Sources {
  journal?: unknown[];
  invoices?: unknown[];
  bills?: unknown[];
  openings?: unknown[];
}
const entry = (l: LineLike, date: string, party: string, share = 1) => ({
  date,
  account: l.account ?? '',
  net: Math.round(((l.debitMinor ?? 0) - (l.creditMinor ?? 0)) * share),
  cls: l.cls ?? '',
  party: l.party || party,
});
const docLines = (d: any): LineLike[] =>
  ((d?.ledgerLines ?? []) as LineLike[]).filter(Boolean);

/** Every posting line, on the accrual basis: as each document posted it. */
export function accrualEntries(src: Sources): ReportEntry[] {
  let out: ReportEntry[] = [];
  for (let p of journalPostings(src.journal))
    for (let l of p.lines) out.push(entry(l, p.date ?? '', p.party ?? ''));
  for (let [docs, partyKey] of [
    [src.invoices, 'customerId'],
    [src.bills, 'vendorId'],
    [src.openings, ''],
  ] as const)
    for (let d of (docs ?? []).filter(Boolean) as any[])
      for (let l of docLines(d))
        out.push(entry(l, l.date || d.date || '', partyKey ? d[partyKey] : ''));
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
      let e = entry(l, payDate, party, share);
      if (i === lines.length - 1) e.net = target - sofar;
      sofar += e.net;
      out.push(e);
    });
  };
  // journalPostings leaves out a reversed posting with its reversal, payment and all.
  for (let p of journalPostings(src.journal)) {
    if (NOT_CASH.has(p.kind)) continue;
    for (let l of p.lines) out.push(entry(l, p.date ?? '', p.party ?? ''));
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
    for (let l of docLines(d)) out.push(entry(l, l.date || d.date || '', ''));
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
