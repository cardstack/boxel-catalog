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
  getRelationshipMembershipState,
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
import { LedgerAccount, Bill, Item } from './ledger-cards';
import { Invoice } from './ledger-sales';
import { JournalMonth, journalPostings } from './ledger-journal';
import { OpeningBalances } from './ledger-opening';
import {
  ReportView,
  ReportViewControls,
  viewOf,
  comparePeriod,
  accrualEntries,
  cashEntries,
  type ReportEntry,
  type ViewChoice,
} from './ledger-report-settings';

const posted = { filter: { eq: { status: 'posted' } }, page: { size: 1000 } };
const SOURCES = ['journal', 'invoices', 'bills', 'openings'] as const;
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
// A table is worked out once per set of inputs, however often the template reads it. A loaded
// relationship can fill in place, so its length counts as an input.
const tables = new WeakMap<object, { inputs: unknown[]; value: unknown }>();
function memoTable<T>(
  owner: object,
  m: PostingsReport,
  extra: unknown[],
  work: () => T,
): T {
  let v = viewOf(m.view);
  let inputs = [
    v.basis,
    v.columns,
    v.compare,
    m.fromMonth,
    m.toMonth,
    ...extra,
    ...[m.journal, m.invoices, m.bills, m.openings, m.accounts].flatMap(
      (xs) => [xs, (xs ?? []).length],
    ),
  ];
  let hit = tables.get(owner);
  if (
    hit &&
    hit.inputs.length === inputs.length &&
    hit.inputs.every((x, i) => x === inputs[i])
  )
    return hit.value as T;
  let value = work();
  tables.set(owner, { inputs, value });
  return value;
}
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
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  @field journal = linksToMany(() => JournalMonth, {
    query: { page: { size: 240 } },
    eager: false,
  });
  @field invoices = linksToMany(() => Invoice, { query: posted, eager: false });
  @field bills = linksToMany(() => Bill, { query: posted, eager: false });
  @field openings = linksToMany(() => OpeningBalances, {
    query: { filter: { eq: { status: 'posted' } }, page: { size: 10 } },
    eager: false,
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PostingsReport) {
      let name = (this.constructor as typeof PostingsReport).displayName;
      return this.fromMonth === this.toMonth
        ? `${name} · ${this.fromMonth ?? ''}`
        : `${name} · ${this.fromMonth ?? ''} to ${this.toMonth ?? ''}`;
    },
  });
  /** Whether every source has loaded; reading this starts the loads. */
  sourcesLoaded() {
    SOURCES.forEach((f) => this[f]);
    return SOURCES.every(
      (f) => getRelationshipMembershipState(this, f).isLoaded,
    );
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
  /** A note when the first page of invoices or bills is all that was read. */
  cappedNote() {
    let capped = (['invoices', 'bills'] as const).filter(
      (f) => getRelationshipMembershipState(this, f).isPartial,
    );
    return capped.length
      ? `Only the first 1,000 ${capped.join(' and ')} were read.`
      : '';
  }
}

// Amounts by party: income for sales, cost of goods and expenses for spending, each with any comparison.
function byParty(
  m: PostingsReport,
  sections: string[],
  sign: 1 | -1,
  none: string,
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
      if (inMonths(e, a, b))
        by.set(e.party || none, (by.get(e.party || none) ?? 0) + sign * e.net);
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
    return !(this.args.model as PostingsReport).sourcesLoaded();
  }
  get table() {
    let m = this.args.model as PostingsReport;
    if (this.loading) return undefined;
    return memoTable(this, m, [], () =>
      m instanceof ExpensesByVendor
        ? byParty(m, ['cogs', 'expense'], 1, '(no vendor)')
        : byParty(m, ['income'], -1, '(no customer)'),
    );
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
    <Sheet
      @eyebrow={{this.eyebrow}}
      @title={{@model.cardTitle}}
      @figureMinor={{if this.table this.table.totalMinor}}
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
        {{#if this.table}}<StatementTable
            @label={{this.eyebrow}}
            @columns={{this.table.cols}}
            @rows={{this.table.rows}}
          />{{else}}<p>Reading the period’s postings…</p>{{/if}}
      </Part>
    </Sheet>
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
      <Fit @eyebrow='Sales by customer' @title={{@model.toMonth}} />
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
      <Fit @eyebrow='Expenses by vendor' @title={{@model.toMonth}} />
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
    for (let d of (this.invoices ?? []).filter(Boolean) as Invoice[]) {
      if (
        d.kind === 'opening' ||
        !inMonths({ date: String(d.date ?? '') }, from, to)
      )
        continue;
      for (let l of (d.lines ?? []).filter(Boolean))
        add(l!.sku ?? undefined, l!.qty ?? 0, l!.amountMinor ?? 0);
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
    get loading() {
      return !this.args.model.sourcesLoaded?.();
    }
    get table(): { cols: Col[]; rows: Line[]; total: number } | undefined {
      let m = this.args.model as SalesByItem;
      if (this.loading) return undefined;
      return memoTable(this, m, [m.items, (m.items ?? []).length], () =>
        this.build(m),
      );
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
      <Sheet
        @eyebrow='Sales by product'
        @title={{@model.cardTitle}}
        @figureMinor={{if this.table this.table.total}}
        @figureLabel='Total'
        @note='Accrual basis: invoices on their dates, and sales and refund receipts.'
      >
        <Part @title='Period'>
          <div class='period'>
            <label>From<@fields.fromMonth @format='edit' /></label>
            <label>To<@fields.toMonth @format='edit' /></label>
          </div>
        </Part>
        <Part @title='Report'>
          {{#if this.table}}<StatementTable
              @label='Sales by product'
              @columns={{this.table.cols}}
              @rows={{this.table.rows}}
            />{{else}}<p>Reading the period’s postings…</p>{{/if}}
        </Part>
      </Sheet>
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
      <Fit @eyebrow='Sales by product' @title={{@model.toMonth}} />
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
  static isolated = class extends Component<typeof GeneralLedger> {
    get loading() {
      return !this.args.model.sourcesLoaded?.();
    }
    get table(): { cols: Col[]; rows: Line[] } | undefined {
      let m = this.args.model as GeneralLedger;
      if (this.loading) return undefined;
      return memoTable(this, m, [m.account], () => this.build(m));
    }
    build(m: GeneralLedger): { cols: Col[]; rows: Line[] } {
      let v = viewOf(m.view),
        from = m.fromMonth ?? '',
        to = m.toMonth ?? '',
        names = m.sections(),
        only = m.account || '';
      let entries = m.entries(v).filter((e) => !only || e.account === only);
      let before = new Map<string, number>(),
        during = new Map<string, ReportEntry[]>();
      for (let e of entries) {
        let mo = e.date.slice(0, 7);
        if (mo && mo < from)
          before.set(e.account, (before.get(e.account) ?? 0) + e.net);
        else if (inMonths(e, from, to))
          during.set(e.account, [...(during.get(e.account) ?? []), e]);
      }
      // Balances read on the account's normal side: credit-normal sections show credits as positive.
      let normal = (account: string) =>
        ['liability', 'equity', 'income'].includes(
          names.get(account)?.section ?? '',
        )
          ? -1
          : 1;
      let rows: Line[] = [];
      for (let account of [...during.keys()].sort()) {
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
        let lines = [...during.get(account)!].sort((a, b) =>
          a.date.localeCompare(b.date),
        );
        lines.forEach((e, i) => {
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
    noColumns: ViewChoice['columns'][] = [];
    <template>
      <Sheet
        @eyebrow='General ledger'
        @title={{@model.cardTitle}}
        @note={{if
          @model.account
          'One account; clear the account to see every one.'
          'Every account with a posting in the period.'
        }}
      >
        <Part @title='View'>
          <div class='period'>
            <label>From<@fields.fromMonth @format='edit' /></label>
            <label>To<@fields.toMonth @format='edit' /></label>
            <label>Account<@fields.account @format='edit' /></label>
          </div>
          <ReportViewControls
            @model={{@model}}
            @cash={{true}}
            @columns={{this.noColumns}}
          />
        </Part>
        <Part @title='Ledger'>
          {{#if this.table}}<StatementTable
              @label='General ledger'
              @columns={{this.table.cols}}
              @rows={{this.table.rows}}
            />{{else}}<p>Reading the period’s postings…</p>{{/if}}
        </Part>
      </Sheet>
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
      <Fit @eyebrow='General ledger' @title={{@model.toMonth}} />
    </template>
  };
}
