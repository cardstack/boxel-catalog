// The reports QuickBooks lists under sales, expenses and accounting: sales by customer and by
// product, expenses by vendor, and the general ledger. Each reads the same postings the report views
// do (ledger-report-settings), over a period of months, and takes a basis and a comparison where it
// makes sense.
import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Sheet, Part, Strip, Fit } from './record-kit';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import { IsoMonthField } from './ledger-dates';
import { settingsLink, settingsOf, fiscalYearStartOf } from './ledger-settings';
import { LedgerAccount, Bill, Item } from './ledger-cards';
import { Invoice } from './ledger-sales';
import { JournalMonth, journalPostings } from './ledger-journal';
import { OpeningBalances } from './ledger-opening';
import { MonthClose, netOf } from './ledger-close';
import {
  ReportView,
  ReportViewControls,
  viewOf,
  comparePeriod,
  accrualEntries,
  cashEntries,
  viewDocuments,
  sourcesLoaded,
  sourceNotes,
  type ReportEntry,
  type ViewChoice,
} from './ledger-report-settings';

const amountCol = (key: string, label: string): Col => ({
  key,
  label,
  kind: 'amount',
});
const changeCol: Col = {
  key: 'change',
  label: 'Change',
  kind: 'amount',
  sign: 'change',
};
// Whose name a posting's line is reported under: a sale's customer, a purchase's vendor. Other
// postings (a fulfillment's cost, payroll, a journal entry) carry a party that isn't one of those.
const CUSTOMER_KINDS = new Set([
  'invoice',
  'sales-receipt',
  'refund-receipt',
  'credit-memo',
  'write-off',
  'customer-payment',
  'void',
]);
const VENDOR_KINDS = new Set([
  'bill',
  'bill-payment',
  'card-charge',
  'vendor-credit',
  'bank-payment',
  'landed-cost',
  'void',
]);
const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};
const inMonths = (e: { date: string }, from: string, to: string) => {
  let m = e.date.slice(0, 7);
  return !!m && m >= from && m <= to;
};

/**
 * A report over a period of months, read from each posting: the journal months, and the invoices,
 * bills and opening balances still posted as cards. Those load only when the report is read.
 */
export class PostingsReport extends CardDef {
  static displayName = 'Postings report';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field fromMonth = contains(IsoMonthField);
  @field toMonth = contains(IsoMonthField);
  @field view = contains(ReportView);
  @field settings = settingsLink();
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  // The months it reads: its period, from a comparison's start, or on the cash basis from as far back
  // as the invoices and bills its payments settle.
  @field readFromMonth = contains(StringField, {
    computeVia: function (this: PostingsReport) {
      return this.readsFrom();
    },
  });
  @field readFromDate = contains(StringField, {
    computeVia: function (this: PostingsReport) {
      return `${this.readFromMonth ?? ''}-01`;
    },
  });
  @field readToDate = contains(StringField, {
    computeVia: function (this: PostingsReport) {
      return this.toMonth ? monthEnd(this.toMonth) : '';
    },
  });
  @field journal = linksToMany(() => JournalMonth, {
    query: {
      filter: {
        range: {
          month: { gte: '$this.readFromMonth', lte: '$this.toMonth' },
        },
      },
      page: { size: 240 },
    },
    eager: false,
  });
  @field invoices = linksToMany(() => Invoice, {
    query: viewDocuments(),
    eager: false,
  });
  @field bills = linksToMany(() => Bill, {
    query: viewDocuments(),
    eager: false,
  });
  @field openings = linksToMany(() => OpeningBalances, {
    query: { filter: { eq: { status: 'posted' } }, page: { size: 10 } },
    eager: false,
  });
  @field periodLabel = contains(StringField, {
    computeVia: function (this: PostingsReport) {
      return this.fromMonth === this.toMonth
        ? (this.fromMonth ?? '')
        : `${this.fromMonth ?? ''} to ${this.toMonth ?? ''}`;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PostingsReport) {
      if (this.cardInfo?.name) return this.cardInfo.name;
      let name = (this.constructor as typeof PostingsReport).displayName;
      return `${name} · ${this.periodLabel ?? ''}`;
    },
  });
  readsFrom() {
    let v = viewOf(this.view),
      from = this.fromMonth ?? '',
      cmp = comparePeriod(from, this.toMonth ?? '', v.compare);
    return v.basis === 'cash' ? '0000-01' : (cmp?.from ?? from);
  }
  /** Whether its sources have loaded; reading this starts the loads. */
  loaded() {
    return sourcesLoaded(this);
  }
  /** The postings on the view's basis. */
  entries(v: ViewChoice): ReportEntry[] {
    let src = {
      journal: this.journal,
      invoices: this.invoices,
      bills: this.bills,
      openings: this.openings,
    };
    return v.basis === 'cash' ? cashEntries(src) : accrualEntries(src);
  }
  sections() {
    return new Map(
      (this.accounts ?? [])
        .filter(Boolean)
        .map((a) => [
          a!.code ?? '',
          { name: a!.name ?? '', section: a!.section ?? '' },
        ]),
    );
  }
  /** A note for each source read only to its page. */
  cappedNote() {
    return sourceNotes(this).join(' ');
  }
}

// Amounts by party: income for sales, cost of goods and expenses for spending, each with any comparison.
function byParty(
  m: PostingsReport,
  sections: string[],
  sign: 1 | -1,
  none: string,
  kinds: Set<string>,
): { cols: Col[]; rows: Line[]; totalMinor: number } {
  let v = viewOf(m.view),
    from = m.fromMonth ?? '',
    to = m.toMonth ?? '',
    names = m.sections(),
    entries = m
      .entries(v)
      .filter((e) => sections.includes(names.get(e.account)?.section ?? ''));
  let sum = (a: string, b: string) => {
    let by = new Map<string, number>();
    for (let e of entries)
      if (inMonths(e, a, b)) {
        let party = (kinds.has(e.kind) && e.party) || none;
        by.set(party, (by.get(party) ?? 0) + sign * e.net);
      }
    return by;
  };
  let now = sum(from, to),
    cmp = comparePeriod(from, to, v.compare),
    before = cmp ? sum(cmp.from, cmp.to) : undefined;
  let parties = [...new Set([...now.keys(), ...(before?.keys() ?? [])])].sort(
    (a, b) => (now.get(b) ?? 0) - (now.get(a) ?? 0) || a.localeCompare(b),
  );
  let cells = (amount: number, earlier?: number) => ({
    amount,
    ...(before
      ? { compare: earlier ?? 0, change: amount - (earlier ?? 0) }
      : {}),
  });
  let total = [...now.values()].reduce((n, x) => n + x, 0);
  return {
    cols: [
      { key: 'party', label: 'Name' },
      amountCol('amount', 'Amount'),
      ...(cmp ? [amountCol('compare', cmp.label), changeCol] : []),
    ],
    rows: [
      ...parties.map((p) => ({
        key: p,
        cells: { party: p, ...cells(now.get(p) ?? 0, before?.get(p)) },
        data: { row: true, key: p },
      })),
      {
        key: 'total',
        role: 'total' as const,
        cells: {
          party: 'Total',
          ...cells(
            total,
            before
              ? [...before.values()].reduce((n, x) => n + x, 0)
              : undefined,
          ),
        },
      },
    ],
    totalMinor: total,
  };
}

class PartyReportView extends Component<typeof PostingsReport> {
  get loading() {
    return !(this.args.model as PostingsReport).loaded();
  }
  get table() {
    let m = this.args.model as PostingsReport;
    if (this.loading) return undefined;
    return m instanceof ExpensesByVendor
      ? byParty(m, ['cogs', 'expense'], 1, '(no vendor)', VENDOR_KINDS)
      : byParty(m, ['income'], -1, '(no customer)', CUSTOMER_KINDS);
  }
  get note() {
    let m = this.args.model as PostingsReport;
    return [
      viewOf(m.view).basis === 'cash'
        ? 'Cash basis: an invoice or bill counts when it is paid.'
        : 'From the postings in this period, closed or not.',
      m.cappedNote(),
    ]
      .filter(Boolean)
      .join(' ');
  }
  get eyebrow() {
    return (this.args.model.constructor as typeof PostingsReport).displayName;
  }
  <template>
    {{#let this.table as |table|}}<Sheet
        @eyebrow={{this.eyebrow}}
        @title={{@model.cardTitle}}
        @figureMinor={{if table table.totalMinor}}
        @figureLabel='Total'
        @note={{this.note}}
      >
        <Part @title='View'>
          <div class='period'>
            <label>From<@fields.fromMonth @format='edit' /></label>
            <label>To<@fields.toMonth @format='edit' /></label>
          </div>
          <ReportViewControls
            @model={{@model}}
            @cash={{true}}
            @columns={{this.noColumns}}
          />
        </Part>
        <Part @title='Report'>
          {{#if table}}<StatementTable
              @label={{this.eyebrow}}
              @columns={{table.cols}}
              @rows={{table.rows}}
            />{{else}}<p>Reading the period’s postings…</p>{{/if}}
        </Part>
      </Sheet>{{/let}}
    <style scoped>
      .period {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
        margin-bottom: var(--boxel-sp-sm);
      }
      .period label {
        display: grid;
        gap: var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
  noColumns: ViewChoice['columns'][] = [];
}

export class SalesByCustomer extends PostingsReport {
  static displayName = 'Sales by customer';
  static isolated = PartyReportView;
  static embedded = class extends Component<typeof SalesByCustomer> {
    <template>
      <Strip @eyebrow='Sales by customer' @title={{@model.cardTitle}} />
    </template>
  };
  static fitted = class extends Component<typeof SalesByCustomer> {
    <template>
      <Fit @eyebrow='Sales by customer' @title={{@model.periodLabel}} />
    </template>
  };
}

export class ExpensesByVendor extends PostingsReport {
  static displayName = 'Expenses by vendor';
  static isolated = PartyReportView;
  static embedded = class extends Component<typeof ExpensesByVendor> {
    <template>
      <Strip @eyebrow='Expenses by vendor' @title={{@model.cardTitle}} />
    </template>
  };
  static fitted = class extends Component<typeof ExpensesByVendor> {
    <template>
      <Fit @eyebrow='Expenses by vendor' @title={{@model.periodLabel}} />
    </template>
  };
}

// ── sales by product ────────────────────────────────────────────────────────
/**
 * Sales by product, on the accrual basis: invoice lines, plus sales receipts less refund receipts
 * from the journal, each with its quantity. A line with no product is a service or other income.
 */
export class SalesByItem extends PostingsReport {
  static displayName = 'Sales by product';
  @field items = linksToMany(() => Item, { query: { page: { size: 500 } } });
  // It reads invoices and the journal's receipts only.
  loaded() {
    return sourcesLoaded(this, ['journal', 'invoices']);
  }
  cappedNote() {
    return sourceNotes(this, ['journal', 'invoices']).join(' ');
  }
  rowsBySku() {
    let from = this.fromMonth ?? '',
      to = this.toMonth ?? '';
    let by = new Map<string, { qty: number; amount: number }>();
    let add = (sku: string | undefined, qty: number, amount: number) => {
      let k = sku || '(no product)',
        r = by.get(k) ?? { qty: 0, amount: 0 };
      r.qty += qty;
      r.amount += amount;
      by.set(k, r);
    };
    // A voided invoice counts on its date and comes back off in the month it was voided.
    for (let d of (this.invoices ?? []).filter(Boolean) as Invoice[]) {
      if (d.kind === 'opening') continue;
      let counts = [
        [String(d.date ?? ''), 1],
        ...(d.voidDate ? [[String(d.voidDate), -1]] : []),
      ] as [string, number][];
      for (let [date, sign] of counts)
        if (inMonths({ date }, from, to))
          for (let l of (d.lines ?? []).filter(Boolean))
            add(
              l!.sku ?? undefined,
              sign * (l!.qty ?? 0),
              sign * (l!.amountMinor ?? 0),
            );
    }
    for (let [kind, sign] of [
      ['sales-receipt', 1],
      ['refund-receipt', -1],
    ] as const)
      for (let r of journalPostings(this.journal, [kind]))
        if (inMonths(r, from, to))
          for (let i of r.items)
            add(i.sku, sign * (i.qty ?? 0), sign * (i.amountMinor ?? 0));
    return by;
  }
  static isolated = class extends Component<typeof SalesByItem> {
    get note() {
      return [
        'Accrual basis: invoices on their dates, and sales and refund receipts.',
        (this.args.model as SalesByItem).cappedNote(),
      ]
        .filter(Boolean)
        .join(' ');
    }
    get loading() {
      return !(this.args.model as PostingsReport).loaded();
    }
    get table(): { cols: Col[]; rows: Line[]; total: number } | undefined {
      let m = this.args.model as SalesByItem;
      if (this.loading) return undefined;
      return this.build(m);
    }
    build(m: SalesByItem): { cols: Col[]; rows: Line[]; total: number } {
      let names = new Map(
        (m.items ?? [])
          .filter(Boolean)
          .map((i) => [i!.sku ?? '', i!.productName ?? '']),
      );
      let by = m.rowsBySku(),
        skus = [...by.keys()].sort(
          (a, b) => by.get(b)!.amount - by.get(a)!.amount || a.localeCompare(b),
        ),
        total = [...by.values()].reduce((n, r) => n + r.amount, 0);
      return {
        cols: [
          { key: 'sku', label: 'SKU', kind: 'code' },
          { key: 'name', label: 'Product' },
          { key: 'qty', label: 'Quantity', kind: 'quantity', scale: 3 },
          amountCol('amount', 'Amount'),
        ],
        rows: [
          ...skus.map((k) => ({
            key: k,
            cells: {
              sku: k,
              name: names.get(k) ?? '',
              qty: by.get(k)!.qty,
              amount: by.get(k)!.amount,
            },
            data: { row: true, key: k },
          })),
          {
            key: 'total',
            role: 'total' as const,
            cells: { sku: '', name: 'Total', amount: total },
          },
        ],
        total,
      };
    }
    <template>
      {{#let this.table as |table|}}<Sheet
          @eyebrow='Sales by product'
          @title={{@model.cardTitle}}
          @figureMinor={{if table table.total}}
          @figureLabel='Total'
          @note={{this.note}}
        >
          <Part @title='Period'>
            <div class='period'>
              <label>From<@fields.fromMonth @format='edit' /></label>
              <label>To<@fields.toMonth @format='edit' /></label>
            </div>
          </Part>
          <Part @title='Report'>
            {{#if table}}<StatementTable
                @label='Sales by product'
                @columns={{table.cols}}
                @rows={{table.rows}}
              />{{else}}<p>Reading the period’s postings…</p>{{/if}}
          </Part>
        </Sheet>{{/let}}
      <style scoped>
        .period {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-sm);
        }
        .period label {
          display: grid;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
  static embedded = class extends Component<typeof SalesByItem> {
    <template>
      <Strip @eyebrow='Sales by product' @title={{@model.cardTitle}} />
    </template>
  };
  static fitted = class extends Component<typeof SalesByItem> {
    <template>
      <Fit @eyebrow='Sales by product' @title={{@model.periodLabel}} />
    </template>
  };
}

// ── general ledger ──────────────────────────────────────────────────────────
/**
 * Every posting in a period, account by account: the balance brought forward, each line with its
 * document and party, the running balance on the account's normal side, and the balance carried.
 */
export class GeneralLedger extends PostingsReport {
  static displayName = 'General ledger';
  @field account = contains(StringField); // one account's ledger, or every account when empty
  // The closed months before the period: the balances it brings forward, as the account register does.
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lt: '$this.fromMonth' } } },
      page: { size: 240 },
    },
  });
  static isolated = class extends Component<typeof GeneralLedger> {
    get loading() {
      return !(this.args.model as PostingsReport).loaded();
    }
    get table(): { cols: Col[]; rows: Line[] } | undefined {
      let m = this.args.model as GeneralLedger;
      if (this.loading) return undefined;
      return this.build(m);
    }
    get note() {
      let m = this.args.model as GeneralLedger;
      return [
        m.account
          ? 'One account; clear the account to see every one.'
          : 'Every account with a balance or a posting in the period. Balances brought forward come from the closed months.',
        m.cappedNote(),
      ]
        .filter(Boolean)
        .join(' ');
    }
    build(m: GeneralLedger): { cols: Col[]; rows: Line[] } {
      // The general ledger is on the accrual basis: every posting as it was made.
      let v = { ...viewOf(m.view), basis: 'accrual' as const },
        from = m.fromMonth ?? '',
        to = m.toMonth ?? '',
        names = m.sections(),
        only = m.account || '',
        fy = settingsOf(m).fiscalYearStart;
      let isPl = (account: string) =>
        ['income', 'cogs', 'expense'].includes(
          names.get(account)?.section ?? '',
        );
      // Brought forward from the closed months: balance accounts from the start, income and expense
      // accounts from the start of the period's fiscal year. Earlier years' income is equity.
      let yearStart = fiscalYearStartOf(from, fy);
      let closes = (m.closes ?? []).filter(Boolean) as MonthClose[];
      let before = new Map<string, number>();
      for (let [account, net] of netOf(closes))
        if (!isPl(account)) before.set(account, net);
      for (let [account, net] of netOf(
        closes.filter((c) => (c.month ?? '') >= yearStart),
      ))
        if (isPl(account)) before.set(account, net);
      let priorIncome = 0;
      for (let [account, net] of netOf(
        closes.filter((c) => (c.month ?? '') < yearStart),
      ))
        if (isPl(account)) priorIncome -= net;
      let during = new Map<string, ReportEntry[]>();
      for (let e of m.entries(v))
        if ((!only || e.account === only) && inMonths(e, from, to)) {
          let list = during.get(e.account) ?? [];
          list.push(e);
          during.set(e.account, list);
        }
      // Balances read on the account's normal side: credit-normal sections show credits as positive.
      let normal = (account: string) =>
        ['liability', 'equity', 'income'].includes(
          names.get(account)?.section ?? '',
        )
          ? -1
          : 1;
      let rows: Line[] = [];
      if (!only && priorIncome)
        rows.push(
          {
            key: 'h-prior',
            role: 'heading',
            cells: { date: 'Retained earnings' },
          },
          {
            key: 'b-prior',
            depth: 1,
            cells: { doc: 'Prior years’ income', balance: priorIncome },
          },
        );
      let accounts = [
        ...new Set([
          ...during.keys(),
          ...[...before]
            .filter(([a, n]) => n && (!only || a === only))
            .map(([a]) => a),
        ]),
      ].sort();
      for (let account of accounts) {
        let side = normal(account),
          balance = before.get(account) ?? 0;
        rows.push(
          {
            key: `h-${account}`,
            role: 'heading',
            cells: { date: `${account} ${names.get(account)?.name ?? ''}` },
          },
          {
            key: `b-${account}`,
            depth: 1,
            cells: { doc: 'Brought forward', balance: side * balance },
          },
        );
        let lines = [...(during.get(account) ?? [])].sort((a, b) =>
          a.date.localeCompare(b.date),
        );
        lines.forEach((e, i) => {
          // An income or expense account starts again at a new fiscal year inside the period.
          let mo = e.date.slice(0, 7);
          if (
            isPl(account) &&
            mo > from &&
            fiscalYearStartOf(mo, fy) === mo &&
            (i === 0 || lines[i - 1].date.slice(0, 7) !== mo)
          ) {
            balance = 0;
            rows.push({
              key: `fy-${account}-${mo}`,
              depth: 1,
              cells: { date: mo, doc: 'New fiscal year', balance: 0 },
            });
          }
          balance += e.net;
          rows.push({
            key: `${account}-${i}`,
            depth: 1,
            cells: {
              date: e.date,
              doc: e.doc,
              party: e.party,
              dr: e.net > 0 ? e.net : undefined,
              cr: e.net < 0 ? -e.net : undefined,
              balance: side * balance,
            },
          });
        });
        rows.push({
          key: `t-${account}`,
          role: 'subtotal',
          cells: { doc: 'Carried forward', balance: side * balance },
        });
      }
      return {
        cols: [
          { key: 'date', label: 'Date', width: '7rem' },
          { key: 'doc', label: 'Document', kind: 'code' },
          { key: 'party', label: 'Party' },
          amountCol('dr', 'Debit'),
          amountCol('cr', 'Credit'),
          amountCol('balance', 'Balance'),
        ],
        rows,
      };
    }
    <template>
      {{#let this.table as |table|}}<Sheet
          @eyebrow='General ledger'
          @title={{@model.cardTitle}}
          @note={{this.note}}
        >
          <Part @title='View'>
            <div class='period'>
              <label>From<@fields.fromMonth @format='edit' /></label>
              <label>To<@fields.toMonth @format='edit' /></label>
              <label>Account<@fields.account @format='edit' /></label>
            </div>
          </Part>
          <Part @title='Ledger'>
            {{#if table}}<StatementTable
                @label='General ledger'
                @columns={{table.cols}}
                @rows={{table.rows}}
              />{{else}}<p>Reading the period’s postings…</p>{{/if}}
          </Part>
        </Sheet>{{/let}}
      <style scoped>
        .period {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-sm);
          margin-bottom: var(--boxel-sp-sm);
        }
        .period label {
          display: grid;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
  static embedded = class extends Component<typeof GeneralLedger> {
    <template>
      <Strip @eyebrow='General ledger' @title={{@model.cardTitle}} />
    </template>
  };
  static fitted = class extends Component<typeof GeneralLedger> {
    <template>
      <Fit @eyebrow='General ledger' @title={{@model.periodLabel}} />
    </template>
  };
}
