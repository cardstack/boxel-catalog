// Month totals and the trial balance: the month's journal card (every write-once posting) plus the
// documents that stay cards (bills, invoices, the opening balances).
// Each kind of document is its own query-backed relationship. (A single query on the LedgerDocument
// base type resolved only some of its matches in the host, though the index returned them all, so
// the kinds are listed one by one; a new kind of document adds a relationship here.)
//
// (This module replaces MonthTotals and TrialBalanceReport in ledger-reports.gts and
// ledger-statements.gts; the realm's render pool keeps an old copy of a module it has loaded.)
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Bill, LedgerAccount } from './ledger-cards';
import { OpeningBalances } from './ledger-opening';
import { Invoice } from './ledger-sales';
import { JournalMonth } from './ledger-journal';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  day,
  partialNote,
  type Fact,
} from './record-kit';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import {
  operation,
  params,
  instance,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { MonthClose, ClosedTotal } from './ledger-close';

const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};
const eqMinor = (a: number | undefined, b: number | undefined) =>
  (a ?? 0) === (b ?? 0);
const postedIn = {
  filter: {
    every: [
      { eq: { status: 'posted' } },
      { range: { date: { gte: '$this.fromDate', lte: '$this.toDate' } } },
    ],
  },
};
type Lined = {
  ledgerLines?: (
    | { account?: string; debitMinor?: number; creditMinor?: number }
    | undefined
  )[];
};
const DOCS = ['invoices'] as const;

// ── month totals: what one month posted, per account ────────────────────────
export class AccountTotal extends FieldDef {
  @field account = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
}

export class MonthTotals extends CardDef {
  static displayName = 'Month totals';
  static icon = BookIcon;
  @field month = contains(StringField); // YYYY-MM
  @field fromDate = contains(StringField, {
    computeVia: function (this: MonthTotals) {
      return this.month ? `${this.month}-01` : '';
    },
  });
  @field toDate = contains(StringField, {
    computeVia: function (this: MonthTotals) {
      return this.month ? monthEnd(this.month) : '';
    },
  });
  @field bills = linksToMany(() => Bill, {
    query: { ...postedIn, page: { size: 1000 } },
  });
  @field openings = linksToMany(() => OpeningBalances, {
    query: { ...postedIn, page: { size: 10 } },
  });
  @field invoices = linksToMany(() => Invoice, {
    query: { ...postedIn, page: { size: 500 } },
  });
  @field journal = linksToMany(() => JournalMonth, {
    query: { filter: { eq: { month: '$this.month' } }, page: { size: 10 } },
  });
  @field totals = containsMany(AccountTotal, {
    computeVia: function (this: MonthTotals) {
      let by = new Map<
        string,
        { account: string; debitMinor: number; creditMinor: number }
      >();
      let docs = [
        ...(this.bills ?? []),
        ...(this.openings ?? []),
        ...DOCS.flatMap((f) => (this[f] ?? []) as unknown[]),
        ...(this.journal ?? []),
      ].filter(Boolean) as Lined[];
      for (let d of docs)
        for (let l of d.ledgerLines ?? []) {
          if (!l?.account) continue;
          let t = by.get(l.account) ?? {
            account: l.account,
            debitMinor: 0,
            creditMinor: 0,
          };
          t.debitMinor += l.debitMinor ?? 0;
          t.creditMinor += l.creditMinor ?? 0;
          by.set(l.account, t);
        }
      return [...by.values()]
        .sort((a, b) => a.account.localeCompare(b.account))
        .map((t) => new AccountTotal(t));
    },
  });
  @field billCount = contains(NumberField, {
    computeVia: function (this: MonthTotals) {
      return (this.bills ?? []).filter(Boolean).length;
    },
  });
  @field paymentCount = contains(NumberField, {
    computeVia: function (this: MonthTotals) {
      return (this.journal ?? [])
        .filter(Boolean)
        .reduce(
          (n, j) =>
            n +
            (j!.postings ?? []).filter((p) => p?.kind === 'bill-payment')
              .length,
          0,
        );
    },
  });
  @field postingCount = contains(NumberField, {
    computeVia: function (this: MonthTotals) {
      return (this.journal ?? [])
        .filter(Boolean)
        .reduce((n, j) => n + (j!.count ?? 0), 0);
    },
  });
  @field documentCount = contains(NumberField, {
    computeVia: function (this: MonthTotals) {
      return DOCS.reduce(
        (n, f) => n + ((this[f] ?? []) as unknown[]).filter(Boolean).length,
        0,
      );
    },
  });
  @field debitMinor = contains(NumberField, {
    computeVia: function (this: MonthTotals) {
      return (this.totals ?? []).reduce((n, t) => n + (t?.debitMinor ?? 0), 0);
    },
  });
  @field creditMinor = contains(NumberField, {
    computeVia: function (this: MonthTotals) {
      return (this.totals ?? []).reduce((n, t) => n + (t?.creditMinor ?? 0), 0);
    },
  });
  @field balanced = contains(BooleanField, {
    computeVia: function (this: MonthTotals) {
      return this.debitMinor === this.creditMinor;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: MonthTotals) {
      return `Month totals · ${this.month ?? ''}`;
    },
  });
  /** Issue the month at close: a MonthClose draft carrying these totals as stored fields. MonthClose.post checks they balance. */
  @operation static issue = {
    base: 'create',
    of: MonthClose,
    params: { totals: ClosedTotal },
    fill: {
      month: instance('month'),
      totals: params('totals'),
      status: 'draft',
    },
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof MonthTotals> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Period', value: `${day(m.fromDate)} – ${day(m.toDate)}` },
        { key: 'Bills posted', value: String(m.billCount ?? 0), strong: true },
        { key: 'Invoices posted', value: String(m.documentCount ?? 0) },
        {
          key: 'Journal postings',
          value: `${m.postingCount ?? 0} (${m.paymentCount ?? 0} bill payments)`,
        },
        { key: 'Debits', value: money(m.debitMinor) },
        { key: 'Credits', value: money(m.creditMinor) },
        { key: 'Balanced', value: m.balanced ? 'Yes' : 'No' },
      ];
    }
    get note() {
      return (
        ['bills', ...DOCS, 'journal']
          .map((f) => partialNote(this.args.model, f))
          .find(Boolean) ?? ''
      );
    }
    cols: Col[] = [
      { key: 'code', label: 'Account', kind: 'code' },
      { key: 'dr', label: 'Debits', kind: 'amount' },
      { key: 'cr', label: 'Credits', kind: 'amount' },
    ];
    get rows(): Line[] {
      let m = this.args.model;
      return [
        ...(m.totals ?? []).filter(Boolean).map((t) => ({
          key: t!.account ?? '',
          cells: { code: t!.account, dr: t!.debitMinor, cr: t!.creditMinor },
          data: {
            row: true,
            key: t!.account,
            dr: t!.debitMinor ?? 0,
            cr: t!.creditMinor ?? 0,
          },
        })),
        {
          key: 'total',
          role: 'total' as const,
          cells: { code: 'Total', dr: m.debitMinor, cr: m.creditMinor },
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Month totals'
        @title={{@model.month}}
        @figureMinor={{@model.debitMinor}}
        @figureLabel='Posted'
        @status={{if @model.balanced 'Balanced' 'Unbalanced'}}
        @note={{this.note}}
      >
        <Part @title='Period'><Facts @items={{this.facts}} /></Part>
        <Part @title='By account'>
          <StatementTable
            @label='Totals by account'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @density='compact'
          />
        </Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof MonthTotals> {
    <template>
      <Strip
        @eyebrow='Month totals'
        @title={{@model.month}}
        @figure={{money @model.debitMinor}}
        @meta='Posted debits'
      />
    </template>
  };
  static fitted = class extends Component<typeof MonthTotals> {
    <template>
      <Fit
        @eyebrow='Month'
        @title={{@model.month}}
        @figure={{money @model.debitMinor}}
        @meta='Posted'
      />
    </template>
  };
}

// ── trial balance: the months, added up ─────────────────────────────────────
export class TrialRow extends FieldDef {
  @field account = contains(StringField);
  @field name = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
}

export class TrialBalanceReport extends CardDef {
  static displayName = 'Trial balance';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field throughMonth = contains(StringField); // YYYY-MM
  @field months = linksToMany(() => MonthTotals, {
    query: {
      filter: { range: { month: { lte: '$this.throughMonth' } } },
      page: { size: 240 },
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  @field rows = containsMany(TrialRow, {
    computeVia: function (this: TrialBalanceReport) {
      let names = new Map(
        (this.accounts ?? [])
          .filter(Boolean)
          .map((a) => [a.code ?? '', a.name ?? '']),
      );
      let net = new Map<string, number>();
      for (let m of (this.months ?? []).filter(Boolean))
        for (let t of m.totals ?? [])
          if (t?.account)
            net.set(
              t.account,
              (net.get(t.account) ?? 0) +
                (t.debitMinor ?? 0) -
                (t.creditMinor ?? 0),
            );
      return [...net.entries()]
        .filter(([, v]) => v !== 0)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(
          ([account, v]) =>
            new TrialRow({
              account,
              name: names.get(account) ?? '',
              debitMinor: Math.max(0, v),
              creditMinor: Math.max(0, -v),
            }),
        );
    },
  });
  @field debitMinor = contains(NumberField, {
    computeVia: function (this: TrialBalanceReport) {
      return (this.rows ?? []).reduce((n, r) => n + (r?.debitMinor ?? 0), 0);
    },
  });
  @field creditMinor = contains(NumberField, {
    computeVia: function (this: TrialBalanceReport) {
      return (this.rows ?? []).reduce((n, r) => n + (r?.creditMinor ?? 0), 0);
    },
  });
  @field monthCount = contains(NumberField, {
    computeVia: function (this: TrialBalanceReport) {
      return (this.months ?? []).filter(Boolean).length;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: TrialBalanceReport) {
      return `Trial balance · through ${this.throughMonth ?? ''}`;
    },
  });

  static isolated = class extends Component<typeof TrialBalanceReport> {
    get note() {
      return `From ${this.args.model.monthCount ?? 0} month-totals cards: every posted document: opening balances, bills and payments, sales, inventory, payroll, bank and card activity, journal entries, schedules and depreciation.`;
    }
    cols: Col[] = [
      { key: 'code', label: 'No.', kind: 'code', width: '4.5rem' },
      { key: 'name', label: 'Account' },
      { key: 'dr', label: 'Debit', kind: 'amount' },
      { key: 'cr', label: 'Credit', kind: 'amount' },
    ];
    get rows(): Line[] {
      let m = this.args.model;
      return [
        ...(m.rows ?? []).filter(Boolean).map((r) => ({
          key: r!.account ?? '',
          cells: {
            code: r!.account,
            name: r!.name,
            dr: r!.debitMinor,
            cr: r!.creditMinor,
          },
          data: {
            row: true,
            key: r!.account,
            dr: r!.debitMinor ?? 0,
            cr: r!.creditMinor ?? 0,
          },
        })),
        {
          key: 'total',
          role: 'total' as const,
          cells: {
            code: '',
            name: 'Total',
            dr: m.debitMinor,
            cr: m.creditMinor,
          },
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Trial balance'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.debitMinor}}
        @figureLabel='Debits = credits'
        @status={{if
          (eqMinor @model.debitMinor @model.creditMinor)
          'Balanced'
          'Unbalanced'
        }}
        @note={{this.note}}
      >
        <Part @title='Accounts'>
          <StatementTable
            @label='Trial balance accounts'
            @columns={{this.cols}}
            @rows={{this.rows}}
          />
        </Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof TrialBalanceReport> {
    <template>
      <Strip
        @eyebrow='Trial balance'
        @title={{@model.cardTitle}}
        @figure={{money @model.debitMinor}}
        @meta='Debits = credits'
      />
    </template>
  };
  static fitted = class extends Component<typeof TrialBalanceReport> {
    <template>
      <Fit
        @eyebrow='Trial balance'
        @title={{@model.throughMonth}}
        @figure={{money @model.debitMinor}}
        @meta='Debits'
      />
    </template>
  };
}
