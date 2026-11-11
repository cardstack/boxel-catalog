// The library reports that list records rather than posting lines: open invoices, unpaid bills and
// collections from the documents' open amounts, inventory valuation detail from the stock lots, time
// by customer, and profit by project. Each reads the cards the desk's own registers read.
import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { identifyCard } from '@cardstack/runtime-common';
import type { CardContext, CardDef } from '@cardstack/base/card-api';
import { Button } from '@cardstack/pretui/components/button';
import { Input } from '@cardstack/pretui/components/input';
import { Field } from '@cardstack/pretui/components/field';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import { Callout } from '@cardstack/pretui/components/callout';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import { toHome } from './ledger-document';
import { days } from './record-kit';
import { LedgerAccount, Bill } from './ledger-cards';
import { Invoice, CustomerPayment, CreditMemo, WriteOff } from './ledger-sales';
import { BillPayment } from './ledger-payments';
import { VendorCredit } from './ledger-cash';
import { StockLot } from './ledger-stock';
import { TimeActivity } from './ledger-time';
import { JournalMonth, journalPostings } from './ledger-journal';
import { profitByProject } from './ledger-dimensions';
import { AllCards } from './all-cards';
import {
  SaveReportAs,
  reportBody,
  instancesOf,
  loadingOf,
  isMonth,
  focusOnInsert,
  thisMonth,
  downloadCsv,
  csvName,
  elementCsv,
} from './ledger-report-custom';
import type { SavedLike, SavedSettings } from './ledger-saved-report';

export interface ListTable {
  cols: Col[];
  rows: Line[];
  count: number;
  totalMinor: number;
}
const amount = (key: string, label: string): Col => ({
  key,
  label,
  kind: 'amount',
});

// ── open invoices, unpaid bills, collections ───────────────────────────────
export type OpenKind = 'open-invoices' | 'unpaid-bills' | 'collections';
export interface OpenDoc {
  number: string;
  date: string;
  due: string;
  party: string;
  totalMinor: number;
  openMinor: number;
}
/** An invoice's or bill's open amount, in the home currency, as the aging reports read it. */
export const openDocOf = (d: any): OpenDoc => ({
  number: d.docNo ?? d.billNo ?? '',
  date: d.date ?? '',
  due: d.due || d.date || '',
  party: d.customerId ?? d.vendorId ?? '',
  totalMinor: toHome(d.totalMinor, d.rateMicros),
  openMinor: toHome(d.openMinor, d.rateMicros),
});

/** Where a settlement applies: an invoice by its number, a bill by its vendor and number. */
export const invoiceKey = (invoiceNo: string) => `invoice:${invoiceNo}`;
export const billKey = (vendorId: string, billNo: string) =>
  `bill:${vendorId}|${billNo}`;
export interface SettlementSources {
  customerPayments?: any[];
  billPayments?: any[];
  credits?: any[]; // credit memos and write-offs: invoiceNo and amountMinor
  vendorCredits?: any[]; // vendorId, billNo and amountMinor
  journal?: any[];
}
/**
 * What was settled on each invoice and bill after a date, in the document's own currency: payments,
 * credits and write-offs dated after it. Added back to what is open now, it is what was open then.
 */
export function settledAfter(
  asOf: string,
  src: SettlementSources,
): Map<string, number> {
  let out = new Map<string, number>();
  let add = (key: string, amount: number | undefined) =>
    amount && out.set(key, (out.get(key) ?? 0) + amount);
  let later = (d: any) => (d?.date ?? '') > asOf && d?.status === 'posted';
  for (let p of (src.customerPayments ?? []).filter(later))
    for (let a of (p.applications ?? []).filter(Boolean))
      add(invoiceKey(a.invoiceNo ?? ''), a.amountMinor);
  for (let p of (src.billPayments ?? []).filter(later))
    for (let a of (p.applications ?? []).filter(Boolean))
      add(billKey(p.vendorId ?? '', a.billNo ?? ''), a.amountMinor);
  for (let c of (src.credits ?? []).filter(later))
    add(invoiceKey(c.invoiceNo ?? ''), c.amountMinor);
  for (let c of (src.vendorCredits ?? []).filter(later))
    add(billKey(c.vendorId ?? '', c.billNo ?? ''), c.amountMinor);
  for (let p of journalPostings(src.journal)) {
    if (p.date <= asOf) continue;
    if (p.kind === 'customer-payment')
      for (let i of p.items) add(invoiceKey(i.ref ?? ''), i.amountMinor);
    else if (p.kind === 'bill-payment')
      for (let i of p.items) add(billKey(p.party, i.ref ?? ''), i.amountMinor);
    else if (p.kind === 'credit-memo' || p.kind === 'write-off')
      add(
        invoiceKey(p.fact('invoiceNo')),
        p.num('amountMinor') || lineSum(p.lines, '1100', 'creditMinor'),
      );
    else if (p.kind === 'vendor-credit')
      add(
        billKey(p.party, p.fact('billNo')),
        p.num('amountMinor') || lineSum(p.lines, '2000', 'debitMinor'),
      );
  }
  // A payment made by the date but reversed after it had settled its invoice or bill on the date.
  // journalPostings leaves the pair out, and what is open now counts it again, so take it off.
  for (let m of (src.journal ?? []).filter(Boolean)) {
    let posts = (m.postings ?? []).filter(Boolean);
    for (let r of posts.filter(
      (r: any) => r.kind === 'reversal' && (r.date ?? '') > asOf,
    )) {
      let p = posts.find((p: any) => p.seq === r.reverses);
      if (!p || (p.date ?? '') > asOf) continue;
      for (let i of (p.items ?? []).filter(Boolean))
        if (p.kind === 'customer-payment')
          add(invoiceKey(i.ref ?? ''), -(i.amountMinor ?? 0));
        else if (p.kind === 'bill-payment')
          add(billKey(p.party ?? '', i.ref ?? ''), -(i.amountMinor ?? 0));
      // A credit or write-off reversed after the date had reduced its document on it, the same way.
      let fact = (k: string) =>
        String(
          ((p.facts ?? []) as any[]).find((f) => f?.key === k)?.value ?? '',
        );
      let amount = Number(fact('amountMinor')) || 0;
      if (p.kind === 'credit-memo' || p.kind === 'write-off')
        add(
          invoiceKey(fact('invoiceNo')),
          -(amount || lineSum(p.lines ?? [], '1100', 'creditMinor')),
        );
      else if (p.kind === 'vendor-credit')
        add(
          billKey(p.party ?? '', fact('billNo')),
          -(amount || lineSum(p.lines ?? [], '2000', 'debitMinor')),
        );
    }
  }
  return out;
}
const lineSum = (lines: any[], account: string, side: string) =>
  lines
    .filter((l) => l?.account === account)
    .reduce((n, l) => n + (l?.[side] ?? 0), 0);

/**
 * An invoice's or bill's open amount on a date: what is open now, plus what was settled after the
 * date. A document voided after the date was still open on it; one voided by then is left out.
 */
export function openDocAsOf(
  d: any,
  asOf: string,
  after: Map<string, number>,
): OpenDoc | undefined {
  if (d.voidDate && d.voidDate <= asOf) return undefined;
  let key = d.billNo
    ? billKey(d.vendorId ?? '', d.billNo)
    : invoiceKey(d.docNo ?? '');
  let base = d.voidDate ? (d.totalMinor ?? 0) : (d.openMinor ?? 0);
  return {
    ...openDocOf(d),
    openMinor: toHome(base + (after.get(key) ?? 0), d.rateMicros),
  };
}
/**
 * Each document still open on the date, by customer or vendor with a subtotal for each. Collections
 * keeps only the invoices past due.
 */
export function openDocumentsTable(
  docs: OpenDoc[],
  asOf: string,
  kind: OpenKind,
): ListTable {
  let open = docs.filter(
    (d) =>
      d.openMinor > 0 &&
      (!asOf || d.date <= asOf) &&
      (kind !== 'collections' || days(d.due, asOf) > 0),
  );
  let by = new Map<string, OpenDoc[]>();
  for (let d of open) by.set(d.party, [...(by.get(d.party) ?? []), d]);
  let rows: Line[] = [];
  for (let party of [...by.keys()].sort()) {
    let list = by
      .get(party)!
      .sort(
        (a, b) =>
          a.due.localeCompare(b.due) || a.number.localeCompare(b.number),
      );
    rows.push({ key: `h-${party}`, role: 'heading', cells: { number: party } });
    for (let d of list)
      rows.push({
        key: `${party}-${d.number}`,
        depth: 1,
        cells: {
          number: d.number,
          date: d.date,
          due: d.due,
          late: Math.max(0, days(d.due, asOf)),
          total: d.totalMinor,
          open: d.openMinor,
        },
        data: { openDoc: d.number },
      });
    rows.push({
      key: `s-${party}`,
      role: 'subtotal',
      cells: {
        number: `Total for ${party}`,
        open: list.reduce((n, d) => n + d.openMinor, 0),
      },
      data: { openSubtotal: party },
    });
  }
  let totalMinor = open.reduce((n, d) => n + d.openMinor, 0);
  rows.push({
    key: 'total',
    role: 'total',
    cells: { number: 'Total', open: totalMinor },
  });
  return {
    cols: [
      { key: 'number', label: 'No.', kind: 'code' },
      { key: 'date', label: 'Date', width: '7rem' },
      { key: 'due', label: 'Due', width: '7rem' },
      { key: 'late', label: 'Days past due', kind: 'number' },
      amount('total', 'Amount'),
      amount('open', 'Open balance'),
    ],
    rows,
    count: open.length,
    totalMinor,
  };
}

// ── inventory valuation detail ─────────────────────────────────────────────
export interface LotLine {
  sku: string;
  lot: string;
  received: string;
  remainingQty: number; // thousandths
  remainingCostMinor: number;
}
/** Every lot with stock left, by product: quantity, cost and unit cost, with a subtotal per product. */
export function lotsTable(lots: LotLine[]): ListTable {
  let held = lots.filter((l) => l.remainingQty > 0);
  let by = new Map<string, LotLine[]>();
  for (let l of held) by.set(l.sku, [...(by.get(l.sku) ?? []), l]);
  let rows: Line[] = [];
  for (let sku of [...by.keys()].sort()) {
    let list = by
      .get(sku)!
      .sort((a, b) => a.received.localeCompare(b.received));
    rows.push({ key: `h-${sku}`, role: 'heading', cells: { lot: sku } });
    for (let l of list)
      rows.push({
        key: `${sku}-${l.lot}`,
        depth: 1,
        cells: {
          lot: l.lot,
          received: l.received,
          qty: l.remainingQty,
          unit: l.remainingQty
            ? Math.round((l.remainingCostMinor * 1000) / l.remainingQty)
            : 0,
          value: l.remainingCostMinor,
        },
      });
    rows.push({
      key: `s-${sku}`,
      role: 'subtotal',
      cells: {
        lot: `Total for ${sku}`,
        qty: list.reduce((n, l) => n + l.remainingQty, 0),
        value: list.reduce((n, l) => n + l.remainingCostMinor, 0),
      },
      data: { lotSubtotal: sku },
    });
  }
  let totalMinor = held.reduce((n, l) => n + l.remainingCostMinor, 0);
  rows.push({
    key: 'total',
    role: 'total',
    cells: { lot: 'Total', value: totalMinor },
  });
  return {
    cols: [
      { key: 'lot', label: 'Lot', kind: 'code' },
      { key: 'received', label: 'Received', width: '7rem' },
      { key: 'qty', label: 'On hand', kind: 'quantity', scale: 3 },
      amount('unit', 'Unit cost'),
      amount('value', 'Value'),
    ],
    rows,
    count: held.length,
    totalMinor,
  };
}

// ── time by customer ────────────────────────────────────────────────────────
export interface TimeLine {
  date: string;
  customerId: string;
  worker: string;
  hours: number; // thousandths
  billable: boolean;
  billed: boolean;
  amountMinor: number;
}
/** Hours in the period by customer: billable, billed and the amount still to bill. */
export function timeTable(
  time: TimeLine[],
  from: string,
  to: string,
): ListTable {
  let kept = time.filter((t) => {
    let m = t.date.slice(0, 7);
    return (!from || m >= from) && (!to || m <= to);
  });
  let by = new Map<string, TimeLine[]>();
  for (let t of kept)
    by.set(t.customerId || '(none)', [
      ...(by.get(t.customerId || '(none)') ?? []),
      t,
    ]);
  let sum = (list: TimeLine[], f: (t: TimeLine) => number) =>
    list.reduce((n, t) => n + f(t), 0);
  let cells = (list: TimeLine[]) => ({
    hours: sum(list, (t) => t.hours),
    billable: sum(list, (t) => (t.billable ? t.hours : 0)),
    billed: sum(list, (t) => (t.billable && t.billed ? t.hours : 0)),
    unbilled: sum(list, (t) => (t.billable && !t.billed ? t.amountMinor : 0)),
  });
  let rows: Line[] = [...by.keys()].sort().map((c) => ({
    key: c,
    cells: { customer: c, ...cells(by.get(c)!) },
    data: { timeRow: c },
  }));
  let total = cells(kept);
  rows.push({
    key: 'total',
    role: 'total',
    cells: { customer: 'Total', ...total },
  });
  return {
    cols: [
      { key: 'customer', label: 'Customer' },
      { key: 'hours', label: 'Hours', kind: 'quantity', scale: 3, digits: 2 },
      {
        key: 'billable',
        label: 'Billable',
        kind: 'quantity',
        scale: 3,
        digits: 2,
      },
      { key: 'billed', label: 'Billed', kind: 'quantity', scale: 3, digits: 2 },
      amount('unbilled', 'Unbilled amount'),
    ],
    rows,
    count: kept.length,
    totalMinor: total.unbilled,
  };
}

// ── profit by project ──────────────────────────────────────────────────────
/** Income, costs, labor and profit per project, from the postings and the time on each project. */
export function projectTable(
  rows: ReturnType<typeof profitByProject>,
): ListTable {
  let sum = (f: 'incomeMinor' | 'costMinor' | 'laborMinor' | 'profitMinor') =>
    rows.reduce((n, r) => n + r[f], 0);
  return {
    cols: [
      { key: 'project', label: 'Project', kind: 'code' },
      amount('income', 'Income'),
      amount('cost', 'Costs'),
      amount('labor', 'Labor'),
      amount('profit', 'Profit'),
    ],
    rows: [
      ...rows.map((r) => ({
        key: r.project,
        cells: {
          project: r.project,
          income: r.incomeMinor,
          cost: r.costMinor,
          labor: r.laborMinor,
          profit: r.profitMinor,
        },
        data: { projectRow: r.project },
      })),
      {
        key: 'total',
        role: 'total' as const,
        cells: {
          project: 'Total',
          income: sum('incomeMinor'),
          cost: sum('costMinor'),
          labor: sum('laborMinor'),
          profit: sum('profitMinor'),
        },
      },
    ],
    count: rows.length,
    totalMinor: sum('profitMinor'),
  };
}

// ── the reports on the desk ─────────────────────────────────────────────────
export const LIST_REPORTS: Record<
  string,
  { label: string; note: string; asOf?: boolean }
> = {
  'open-invoices': {
    label: 'Open invoices',
    note: 'Every invoice with a balance on the date, by customer.',
    asOf: true,
  },
  'unpaid-bills': {
    label: 'Unpaid bills',
    note: 'Every bill with a balance on the date, by vendor.',
    asOf: true,
  },
  collections: {
    label: 'Collections',
    note: 'The invoices past due on the date, by customer, oldest due first.',
    asOf: true,
  },
  'inventory-detail': {
    label: 'Inventory valuation detail',
    note: 'Every lot with stock left, at its remaining FIFO cost, by product.',
  },
  'time-by-customer': {
    label: 'Time by customer',
    note: 'Hours worked in the period by customer, and what billable time is still to bill.',
  },
  'profit-by-project': {
    label: 'Profit by project',
    note: 'Income and costs posted to each project in the period, less its labor at cost.',
  },
};
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};

const notInventory = (kind: string) => kind !== 'inventory-detail';

interface ListSignature {
  Args: {
    context?: CardContext;
    realms: string[];
    refRealms?: string[];
    ledger?: CardDef;
    kind: string;
    saved?: SavedLike;
  };
}
/** A list report with its period or date, Save as and Export CSV. */
export class ListReport extends GlimmerComponent<ListSignature> {
  get def() {
    return LIST_REPORTS[this.args.kind] ?? LIST_REPORTS['open-invoices'];
  }
  @tracked fromMonth =
    this.args.saved?.fromMonth || `${thisMonth().slice(0, 4)}-01`;
  @tracked toMonth = this.args.saved?.toMonth || thisMonth();
  @tracked asOf =
    this.args.saved?.asOfMonth || new Date().toISOString().slice(0, 10);
  @tracked savedName = '';
  get kind() {
    return this.args.kind;
  }
  query = (type: typeof CardDef, extra: object[] = [], sortBy?: string) =>
    ({
      filter: {
        every: [{ type: identifyCard(type) }, ...extra],
      },
      ...(sortBy
        ? { sort: [{ by: sortBy, on: identifyCard(type), direction: 'desc' }] }
        : {}),
    }) as never;
  posted = (type: typeof CardDef) => [
    { on: identifyCard(type), eq: { status: 'posted' } },
  ];
  dated = (type: typeof CardDef, range: Record<string, string>) => ({
    on: identifyCard(type),
    range: { date: range },
  });
  get asOfMonth() {
    return this.asOf.slice(0, 7);
  }
  get periodRange() {
    return { gte: `${this.fromMonth}-01`, lte: monthEnd(this.toMonth) };
  }
  wants = (...kinds: string[]) => kinds.includes(this.kind);
  // Open documents: those dated by the report's date. A project report: those dated in its period.
  docsQuery = (type: typeof CardDef) => () =>
    this.wants('profit-by-project')
      ? this.query(
          type,
          [...this.posted(type), this.dated(type, this.periodRange)],
          'date',
        )
      : this.query(
          type,
          [...this.posted(type), this.dated(type, { lte: this.asOf })],
          'date',
        );
  // What was settled after the report's date, to add back to what is open now.
  laterQuery = (type: typeof CardDef) => () =>
    this.query(
      type,
      [...this.posted(type), this.dated(type, { gt: this.asOf })],
      'date',
    );
  // Nothing loads until the date or period is whole.
  get periodError() {
    if (this.def.asOf)
      return DATE.test(this.asOf) ? '' : 'Enter the date to report as of.';
    if (!notInventory(this.kind)) return '';
    if (!isMonth(this.fromMonth) || !isMonth(this.toMonth))
      return 'Enter a From and a To month.';
    if (this.fromMonth > this.toMonth)
      return 'The From month must come before the To month.';
    return '';
  }
  load = (fn: () => unknown, when: string[]) =>
    new AllCards(
      this.args.context,
      this,
      () =>
        (this.wants(...when) && !this.periodError ? fn() : undefined) as never,
      () => this.args.realms,
      { isLive: true },
    );
  invoiceData = this.load(this.docsQuery(Invoice), [
    'open-invoices',
    'collections',
    'profit-by-project',
  ]);
  billData = this.load(this.docsQuery(Bill), [
    'unpaid-bills',
    'profit-by-project',
  ]);
  customerPaymentData = this.load(this.laterQuery(CustomerPayment), [
    'open-invoices',
    'collections',
  ]);
  creditMemoData = this.load(this.laterQuery(CreditMemo), [
    'open-invoices',
    'collections',
  ]);
  writeOffData = this.load(this.laterQuery(WriteOff), [
    'open-invoices',
    'collections',
  ]);
  billPaymentData = this.load(this.laterQuery(BillPayment), ['unpaid-bills']);
  vendorCreditData = this.load(this.laterQuery(VendorCredit), ['unpaid-bills']);
  laterJournalData = this.load(
    () =>
      this.query(JournalMonth, [
        {
          on: identifyCard(JournalMonth),
          range: { month: { gte: this.asOfMonth } },
        },
      ]),
    ['open-invoices', 'collections', 'unpaid-bills'],
  );
  lotData = this.load(() => this.query(StockLot), ['inventory-detail']);
  timeData = this.load(
    () =>
      this.query(
        TimeActivity,
        [this.dated(TimeActivity, this.periodRange)],
        'date',
      ),
    ['time-by-customer', 'profit-by-project'],
  );
  journalData = this.load(
    () =>
      this.query(JournalMonth, [
        {
          on: identifyCard(JournalMonth),
          range: { month: { gte: this.fromMonth, lte: this.toMonth } },
        },
      ]),
    ['profit-by-project'],
  );
  accountData = new AllCards(
    this.args.context,
    this,
    () =>
      (this.wants('profit-by-project') && !this.periodError
        ? this.query(LedgerAccount)
        : undefined) as never,
    () => this.args.refRealms ?? this.args.realms,
    { isLive: true },
  );
  // The sources this report reads, each with what it holds.
  get sources(): [AllCards, string][] {
    let k = this.kind;
    if (k === 'unpaid-bills')
      return [
        [this.billData, 'bills'],
        [this.billPaymentData, 'later bill payments'],
        [this.vendorCreditData, 'later vendor credits'],
        [this.laterJournalData, 'journal months'],
      ];
    if (k === 'inventory-detail') return [[this.lotData, 'lots']];
    if (k === 'time-by-customer') return [[this.timeData, 'time entries']];
    if (k === 'profit-by-project')
      return [
        [this.invoiceData, 'invoices'],
        [this.billData, 'bills'],
        [this.journalData, 'journal months'],
        [this.timeData, 'time entries'],
        [this.accountData, 'accounts'],
      ];
    return [
      [this.invoiceData, 'invoices'],
      [this.customerPaymentData, 'later customer payments'],
      [this.creditMemoData, 'later credit memos'],
      [this.writeOffData, 'later write-offs'],
      [this.laterJournalData, 'journal months'],
    ];
  }
  get loading() {
    return !this.periodError && this.sources.some(([r]) => loadingOf(r));
  }
  get canExport() {
    return (
      !this.loading &&
      !this.periodError &&
      !this.capNote &&
      this.table.count > 0
    );
  }
  // A source that couldn't be read whole would leave records out, so the report shows no total.
  get capNote() {
    if (this.periodError || this.loading) return '';
    let failed = this.sources.filter(([r]) => !r.isComplete);
    return failed.length
      ? `This report couldn't read all of its ${failed.map(([, noun]) => noun).join(', ')}, so it shows no lines or totals. ${failed.some(([r]) => r.tooMany) ? 'Narrow the date or period.' : 'Reload to try again.'}`
      : '';
  }
  get table(): ListTable {
    let k = this.kind;
    if (this.periodError)
      return { cols: [], rows: [], count: 0, totalMinor: 0 };
    if (k === 'unpaid-bills' || k === 'open-invoices' || k === 'collections') {
      let after = settledAfter(this.asOf, {
        customerPayments: instancesOf(this.customerPaymentData),
        credits: [
          ...instancesOf(this.creditMemoData),
          ...instancesOf(this.writeOffData),
        ],
        billPayments: instancesOf(this.billPaymentData),
        vendorCredits: instancesOf(this.vendorCreditData),
        journal: instancesOf(this.laterJournalData),
      });
      return openDocumentsTable(
        instancesOf(k === 'unpaid-bills' ? this.billData : this.invoiceData)
          .map((d) => openDocAsOf(d, this.asOf, after))
          .filter((d): d is OpenDoc => !!d),
        this.asOf,
        k,
      );
    }
    if (k === 'inventory-detail')
      return lotsTable(
        instancesOf(this.lotData)
          .filter((l) => !l.retiredBy)
          .map((l) => ({
            sku: l.sku ?? '',
            lot: l.lot ?? '',
            received: l.received ?? '',
            remainingQty: l.remainingQty ?? 0,
            remainingCostMinor: l.remainingCostMinor ?? 0,
          })),
      );
    let time = instancesOf(this.timeData).map((t) => ({
      date: t.date ?? '',
      customerId: t.customerId ?? '',
      worker: t.worker ?? '',
      projectId: t.projectId ?? '',
      hours: t.hours ?? 0,
      costRateMinor: t.costRateMinor ?? 0,
      billable: !!t.billable,
      billed: !!t.billedInvoice,
      amountMinor: t.amountMinor ?? 0,
    }));
    if (k === 'time-by-customer')
      return timeTable(time, this.fromMonth, this.toMonth);
    let from = `${this.fromMonth}-01`,
      to = monthEnd(this.toMonth);
    return projectTable(
      profitByProject(
        {
          fromDate: from,
          toDate: to,
          accounts: instancesOf(this.accountData),
          journal: instancesOf(this.journalData),
          invoices: instancesOf(this.invoiceData).filter(
            (d) => d.date >= from && d.date <= to,
          ),
          bills: instancesOf(this.billData).filter(
            (d) => d.date >= from && d.date <= to,
          ),
          openings: [],
        },
        time.filter((t) => t.date >= from && t.date <= to),
      ),
    );
  }
  setFrom = (v: string) => (this.fromMonth = v);
  setTo = (v: string) => (this.toMonth = v);
  setAsOf = (v: string) => (this.asOf = v);
  settings = (): SavedSettings => ({
    fromMonth: this.def.asOf ? '' : this.fromMonth,
    toMonth: this.def.asOf ? '' : this.toMonth,
    asOfMonth: this.def.asOf ? this.asOf : '',
    basis: '',
    columns: '',
    compare: '',
    account: '',
    statement: '',
  });
  onSaved = (name: string) => (this.savedName = name);
  body: HTMLElement | undefined;
  setBody = (el: HTMLElement | undefined) => (this.body = el);
  exportCsv = () => {
    if (this.body) downloadCsv(csvName(this.title), elementCsv(this.body));
  };
  get title() {
    return this.args.saved?.name || this.def.label;
  }
  <template>
    <section
      class='list-report'
      data-report-body
      data-list-report={{@kind}}
      aria-busy={{if this.loading 'true'}}
    >
      <header class='head'>
        <div>
          {{#if @saved}}<h2
              tabindex='-1'
              {{focusOnInsert}}
            >{{this.title}}</h2>{{/if}}
          <p class='muted'>{{this.def.note}}</p>
        </div>
        <div class='actions' {{reportBody this.setBody}}>
          <span class='muted' role='status'>{{#if this.loading}}Loading report…{{else if
              this.savedName
            }}Saved as “{{this.savedName}}” in My reports.{{/if}}</span>
          <SaveReportAs
            @context={{@context}}
            @ledger={{@ledger}}
            @kind={{@kind}}
            @kindLabel={{this.def.label}}
            @settings={{this.settings}}
            @onSaved={{this.onSaved}}
          />
          {{#if this.canExport}}<Button
              @tone='neutral'
              @appearance='outlined'
              @size='s'
              {{on 'click' this.exportCsv}}
            >Export CSV</Button>{{/if}}
        </div>
      </header>
      <div class='controls'>
        {{#if this.def.asOf}}
          <Field @label='As of' @error={{this.periodError}}>
            <:default as |id|><Input
                @controlId={{id}}
                @type='date'
                @value={{this.asOf}}
                @onInput={{this.setAsOf}}
              /></:default>
          </Field>
        {{else if (notInventory @kind)}}
          <Field @label='From' @error={{this.periodError}}>
            <:default as |id|><Input
                @controlId={{id}}
                @type='month'
                @value={{this.fromMonth}}
                @onInput={{this.setFrom}}
              /></:default>
          </Field>
          <Field @label='To'>
            <:default as |id|><Input
                @controlId={{id}}
                @type='month'
                @value={{this.toMonth}}
                @onInput={{this.setTo}}
              /></:default>
          </Field>
        {{/if}}
      </div>
      {{#if this.capNote}}<Callout
          @tone='danger'
          @title='Incomplete'
          data-report-capped
        >{{this.capNote}}</Callout>{{/if}}
      {{#if this.periodError}}
        <EmptyState
          @size='s'
          @title={{if this.def.asOf 'Set the date' 'Set the period'}}
        />
      {{else if this.loading}}
        <Skeleton @height='6rem' />
      {{else if this.capNote}}{{else if this.table.count}}
        <StatementTable
          @label={{this.title}}
          @columns={{this.table.cols}}
          @rows={{this.table.rows}}
          @density='compact'
        />
      {{else}}
        <EmptyState
          @size='s'
          @title='Nothing to list'
          @message='No records match this report for the date or period chosen.'
        />
      {{/if}}
    </section>
    <style scoped>
      .list-report {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }
      .head {
        display: flex;
        flex-wrap: wrap;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
      }
      .actions,
      .controls {
        display: flex;
        flex-wrap: wrap;
        align-items: end;
        gap: var(--boxel-sp-xs);
      }
      .muted {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
