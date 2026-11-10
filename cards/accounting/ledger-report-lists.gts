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
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import { toHome } from './ledger-document';
import { days } from './record-kit';
import { LedgerAccount, Bill } from './ledger-cards';
import { Invoice } from './ledger-sales';
import { StockLot } from './ledger-stock';
import { TimeActivity } from './ledger-time';
import { JournalMonth } from './ledger-journal';
import { OpeningBalances } from './ledger-opening';
import { profitByProject } from './ledger-dimensions';
import {
  SaveReportAs,
  reportBody,
  instancesOf,
  loadingOf,
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
  query = (type: typeof CardDef, extra: object[] = [], size = 1000) =>
    ({
      filter: {
        every: [{ type: identifyCard(type) }, ...extra],
      },
      page: { size },
    }) as never;
  posted = (type: typeof CardDef) => [
    { on: identifyCard(type), eq: { status: 'posted' } },
  ];
  wants = (...kinds: string[]) => kinds.includes(this.kind);
  invoiceData = this.args.context?.getCards(
    this,
    () =>
      this.wants('open-invoices', 'collections', 'profit-by-project')
        ? this.query(Invoice, this.posted(Invoice))
        : undefined,
    () => this.args.realms,
    { isLive: true },
  );
  billData = this.args.context?.getCards(
    this,
    () =>
      this.wants('unpaid-bills', 'profit-by-project')
        ? this.query(Bill, this.posted(Bill))
        : undefined,
    () => this.args.realms,
    { isLive: true },
  );
  lotData = this.args.context?.getCards(
    this,
    () => (this.wants('inventory-detail') ? this.query(StockLot) : undefined),
    () => this.args.realms,
    { isLive: true },
  );
  timeData = this.args.context?.getCards(
    this,
    () =>
      this.wants('time-by-customer', 'profit-by-project')
        ? this.query(TimeActivity)
        : undefined,
    () => this.args.realms,
    { isLive: true },
  );
  journalData = this.args.context?.getCards(
    this,
    () =>
      this.wants('profit-by-project')
        ? this.query(JournalMonth, [
            {
              on: identifyCard(JournalMonth),
              range: { month: { gte: this.fromMonth, lte: this.toMonth } },
            },
          ])
        : undefined,
    () => this.args.realms,
    { isLive: true },
  );
  openingData = this.args.context?.getCards(
    this,
    () =>
      this.wants('profit-by-project')
        ? this.query(OpeningBalances, this.posted(OpeningBalances), 10)
        : undefined,
    () => this.args.realms,
    { isLive: true },
  );
  accountData = this.args.context?.getCards(
    this,
    () =>
      this.wants('profit-by-project')
        ? this.query(LedgerAccount, [], 500)
        : undefined,
    () => this.args.refRealms ?? this.args.realms,
    { isLive: true },
  );
  get loading() {
    let used =
      this.kind === 'unpaid-bills'
        ? [this.billData]
        : this.kind === 'inventory-detail'
          ? [this.lotData]
          : this.kind === 'time-by-customer'
            ? [this.timeData]
            : this.kind === 'profit-by-project'
              ? [
                  this.invoiceData,
                  this.billData,
                  this.journalData,
                  this.timeData,
                ]
              : [this.invoiceData];
    return used.some(loadingOf);
  }
  get table(): ListTable {
    let k = this.kind;
    if (k === 'unpaid-bills' || k === 'open-invoices' || k === 'collections')
      return openDocumentsTable(
        instancesOf(k === 'unpaid-bills' ? this.billData : this.invoiceData)
          .filter((d) => !d.voidDate)
          .map(openDocOf),
        this.asOf,
        k,
      );
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
    <section class='list-report' data-report-body data-list-report={{@kind}}>
      <header class='head'>
        <div>
          <h2>{{this.title}}</h2>
          <p class='muted'>{{this.def.note}}</p>
        </div>
        <div class='actions' {{reportBody this.setBody}}>
          {{#if this.savedName}}<span class='muted'>Saved as “{{this.savedName}}”
              in My reports.</span>{{/if}}
          <SaveReportAs
            @context={{@context}}
            @ledger={{@ledger}}
            @kind={{@kind}}
            @kindLabel={{this.def.label}}
            @settings={{this.settings}}
            @onSaved={{this.onSaved}}
          />
          <Button
            @tone='neutral'
            @appearance='outlined'
            @size='s'
            data-test-export-csv
            {{on 'click' this.exportCsv}}
          >Export CSV</Button>
        </div>
      </header>
      <div class='controls'>
        {{#if this.def.asOf}}
          <Field @label='As of'>
            <:default as |id|><Input
                @controlId={{id}}
                @type='date'
                @value={{this.asOf}}
                @onInput={{this.setAsOf}}
              /></:default>
          </Field>
        {{else if (notInventory @kind)}}
          <Field @label='From'>
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
      {{#if this.loading}}
        <Skeleton @height='6rem' />
      {{else if this.table.count}}
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
      h2 {
        margin: 0;
        font-family: var(--font-serif);
        font-size: var(--boxel-font-size-lg);
      }
      .actions,
      .controls {
        display: flex;
        flex-wrap: wrap;
        align-items: end;
        gap: var(--boxel-sp-xs);
      }
      .muted {
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
