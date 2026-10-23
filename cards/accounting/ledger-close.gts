// Closing the books, card-native: a month is issued at close as a MonthClose card that keeps its
// account totals as stored fields (copied from the live month-totals card and checked to balance by
// the realm), bank and card statements are reconciled against the closed months, and the financial
// statements (trial balance, profit and loss, balance sheet) are computed from the closed months.
//
// The live MonthTotals card (ledger-months.gts) adds up every posted document each time it renders;
// a statement over a year of those is hundreds of live queries. A closed month is one small card, so
// a year's statements read twelve.
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
import {
  operation,
  params,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { LedgerAccount } from './ledger-cards';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  day,
  percent,
  type Fact,
} from './record-kit';
import { or } from '@cardstack/boxel-ui/helpers';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import { AccountTotal } from './ledger-document';
import {
  ReconciliationStatusField,
  MonthCloseStatusField,
} from './ledger-status';
import { IsoDateField, IsoMonthField } from './ledger-dates';
import { settingsLink, settingsOf, fiscalYearStartOf } from './ledger-settings';
import { JournalMonth } from './ledger-journal';
import { Invoice } from './ledger-sales';
import { Bill } from './ledger-cards';
import { OpeningBalances } from './ledger-opening';
import {
  ReportView,
  ReportViewControls,
  viewOf,
  isPlainView,
  monthsBetween,
  comparePeriod,
  quarterOf,
  accrualEntries,
  cashEntries,
  netByColumn,
  viewDocuments,
  sourcesLoaded,
  sourceNotes,
  columnKey,
  type ViewChoice,
} from './ledger-report-settings';

// Columns shared by the statements on this page.
const ACCOUNT_COLS: Col[] = [
  { key: 'code', label: 'No.', kind: 'code', width: '4.5rem' },
  { key: 'name', label: 'Account' },
];
const DR_CR_COLS: Col[] = [
  ...ACCOUNT_COLS,
  { key: 'dr', label: 'Debit', kind: 'amount' },
  { key: 'cr', label: 'Credit', kind: 'amount' },
];
const AMOUNT_COLS: Col[] = [
  ...ACCOUNT_COLS,
  { key: 'amount', label: 'Amount', kind: 'amount' },
];

const SECTION_TITLE: Record<string, string> = {
  income: 'Income',
  cogs: 'Cost of goods sold',
  expense: 'Expenses',
  asset: 'Assets',
  liability: 'Liabilities',
  equity: 'Equity',
};
const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};

type Net = Map<string, number>;
/** Debits less credits per account over closed months. */
export function netOf(closes: (MonthClose | undefined)[] | undefined): Net {
  let net: Net = new Map();
  for (let c of (closes ?? []).filter(Boolean))
    for (let t of c!.totals ?? [])
      if (t?.account)
        net.set(
          t.account,
          (net.get(t.account) ?? 0) +
            (t.debitMinor ?? 0) -
            (t.creditMinor ?? 0),
        );
  return net;
}
const chart = (accounts: (LedgerAccount | undefined)[] | undefined) =>
  new Map(
    (accounts ?? []).filter(Boolean).map((a) => [
      a!.code ?? '',
      {
        name: a!.name ?? '',
        type: a!.type ?? '',
        section: a!.section ?? '',
      },
    ]),
  );

// ── bank and card reconciliations ───────────────────────────────────────────
export class OutstandingItem extends FieldDef {
  static displayName = 'Outstanding item';
  @field ref = contains(StringField);
  @field amountMinor = contains(NumberField); // as the books carry it: a payment not yet cleared is negative
}

/** A posting ticked as on the statement: its journal key and its amount as the books carry it. */
export class ClearedItem extends FieldDef {
  static displayName = 'Cleared item';
  @field key = contains(StringField);
  @field date = contains(IsoDateField);
  @field amountMinor = contains(NumberField);
}

export class BankReconciliation extends CardDef {
  static displayName = 'Reconciliation';
  static icon = BookIcon;
  @field account = contains(StringField);
  @field side = contains(StringField); // debit for a bank account, credit for a card
  @field statementDate = contains(IsoDateField);
  @field endingBalanceMinor = contains(NumberField); // per the statement
  @field outstanding = containsMany(OutstandingItem); // on the books, not yet on the statement
  @field cleared = containsMany(ClearedItem); // ticked against the statement
  @field status = contains(ReconciliationStatusField);
  @field reconciledBy = contains(StringField);
  @field finishedBookMinor = contains(NumberField); // the book balance the reconciliation was finished against
  @field statementMonth = contains(StringField, {
    computeVia: function (this: BankReconciliation) {
      return (this.statementDate ?? '').slice(0, 7);
    },
  });
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.statementMonth' } } },
      page: { size: 240 },
    },
  });
  @field bookBalanceMinor = contains(NumberField, {
    computeVia: function (this: BankReconciliation) {
      let n = netOf(this.closes).get(this.account ?? '') ?? 0;
      return this.side === 'credit' ? -n : n;
    },
  });
  @field outstandingMinor = contains(NumberField, {
    computeVia: function (this: BankReconciliation) {
      return (this.outstanding ?? []).reduce(
        (n, o) => n + (o?.amountMinor ?? 0),
        0,
      );
    },
  });
  // Statement = books less what hasn't cleared yet.
  @field differenceMinor = contains(NumberField, {
    computeVia: function (this: BankReconciliation) {
      return (
        (this.endingBalanceMinor ?? 0) -
        ((this.bookBalanceMinor ?? 0) - (this.outstandingMinor ?? 0))
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BankReconciliation) {
      return `Reconciliation · ${this.account ?? ''} · ${this.statementDate ?? ''}`;
    },
  });

  /** Record what was ticked as cleared and what's left outstanding. The desk sends it with `finish`. */
  @operation static record = {
    base: 'transform',
    params: { cleared: ClearedItem, outstanding: OutstandingItem },
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "This reconciliation is already finished.");
      .cleared = params("cleared");
      .outstanding = params("outstanding");
    `,
  } satisfies OperationDeclaration;
  /** Reopen a finished reconciliation. Owner only: no policy can grant it. */
  @operation static undo = {
    base: 'transform',
    nonGrantable: true,
    transformations: bxl`
      assert(.status == "reconciled"; "Only a finished reconciliation can be reopened.");
      .status = "draft";
      .reconciledBy = null;
      .finishedBookMinor = null;
    `,
  } satisfies OperationDeclaration;

  /** Finish the reconciliation against the book balance the caller read from the closed months. The
   *  realm refuses unless statement = books − not yet cleared, to the cent, and keeps the book balance it
   *  was finished against, so a later look can tell if the books moved under it. */
  @operation static finish = {
    base: 'transform',
    params: { bookBalanceMinor: NumberField },
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "This reconciliation is already finished.");
      assert(.endingBalanceMinor != null; "Enter the statement's ending balance.");
      assert(params("bookBalanceMinor") != null; "Send the book balance this reconciliation is finished against.");
      assert([.endingBalanceMinor, 0 - params("bookBalanceMinor")] + [.outstanding[].amountMinor] | add | . == 0; "The statement doesn't agree with the books. The difference must be $0.00 before the reconciliation can be finished.");
      .finishedBookMinor = params("bookBalanceMinor");
      .status = "reconciled";
      .reconciledBy = actor();
    `,
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof BankReconciliation> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Account', value: m.account ?? '', strong: true },
        { key: 'Statement date', value: day(m.statementDate) },
        { key: 'Statement balance', value: money(m.endingBalanceMinor) },
        { key: 'Book balance', value: money(m.bookBalanceMinor) },
        ...(m.outstanding ?? []).filter(Boolean).map((o) => ({
          key: `Not yet cleared · ${o!.ref ?? ''}`,
          value: money(o!.amountMinor),
        })),
        { key: 'Difference', value: money(m.differenceMinor), strong: true },
        { key: 'Reconciled by', value: m.reconciledBy ?? '' },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Reconciliation'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.differenceMinor}}
        @figureLabel='Difference'
        @status={{if @model.reconciledBy 'Reconciled' 'Open'}}
      ><Part @title='Statement against the books'><div
            data-row
            data-key={{@model.cardTitle}}
            data-total={{@model.differenceMinor}}
            data-dr={{@model.bookBalanceMinor}}
          ><Facts @items={{this.facts}} /></div></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof BankReconciliation> {
    <template>
      <Strip
        @eyebrow='Reconciliation'
        @title={{@model.cardTitle}}
        @figure={{money @model.differenceMinor}}
        @meta='Difference'
      />
    </template>
  };
  static fitted = class extends Component<typeof BankReconciliation> {
    <template>
      <Fit
        @eyebrow='Reconciled'
        @title={{@model.statementDate}}
        @figure={{money @model.differenceMinor}}
        @meta={{@model.account}}
      />
    </template>
  };
}

// ── a closed month ──────────────────────────────────────────────────────────
export class MonthClose extends CardDef {
  static displayName = 'Closed month';
  static icon = BookIcon;
  @field month = contains(IsoMonthField); // YYYY-MM
  @field totals = containsMany(AccountTotal); // stored at close: the month's totals per account
  @field status = contains(MonthCloseStatusField);
  @field closedBy = contains(StringField);
  @field through = contains(StringField, {
    computeVia: function (this: MonthClose) {
      return this.month ? monthEnd(this.month) : '';
    },
  });
  @field fromDate = contains(StringField, {
    computeVia: function (this: MonthClose) {
      return this.month ? `${this.month}-01` : '';
    },
  });
  @field debitMinor = contains(NumberField, {
    computeVia: function (this: MonthClose) {
      return (this.totals ?? []).reduce((n, t) => n + (t?.debitMinor ?? 0), 0);
    },
  });
  @field creditMinor = contains(NumberField, {
    computeVia: function (this: MonthClose) {
      return (this.totals ?? []).reduce((n, t) => n + (t?.creditMinor ?? 0), 0);
    },
  });
  // What the close checklist reads: every month through this one, and this month's reconciliations.
  @field upTo = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.month' } } },
      page: { size: 240 },
    },
  });
  @field reconciliations = linksToMany(() => BankReconciliation, {
    query: {
      filter: {
        range: {
          statementDate: { gte: '$this.fromDate', lte: '$this.through' },
        },
      },
      page: { size: 20 },
    },
  });
  @field checks = containsMany(StringField, {
    computeVia: function (this: MonthClose) {
      let out: string[] = [],
        net = netOf(this.upTo),
        recs = (this.reconciliations ?? []).filter(
          Boolean,
        ) as BankReconciliation[];
      out.push(
        this.debitMinor === this.creditMinor
          ? 'pass · The month balances'
          : `FAIL · The month is out of balance by ${money((this.debitMinor ?? 0) - (this.creditMinor ?? 0))}`,
      );
      for (let account of ['1000', '2100']) {
        let r = recs.find((x) => x.account === account);
        out.push(
          !r
            ? `FAIL · ${account} is not reconciled through ${this.through}`
            : r.differenceMinor
              ? `FAIL · ${account} reconciliation is off by ${money(r.differenceMinor)}`
              : `pass · ${account} reconciled to the statement`,
        );
      }
      for (let [account, label] of [
        ['1230', 'Landed cost clearing'],
        ['3900', 'Opening balance equity'],
      ])
        out.push(
          net.get(account)
            ? `FAIL · ${label} (${account}) is ${money(net.get(account))}, not $0`
            : `pass · ${label} (${account}) is $0`,
        );
      return out;
    },
  });
  @field ready = contains(BooleanField, {
    computeVia: function (this: MonthClose) {
      return (this.checks ?? []).every((c) => (c ?? '').startsWith('pass'));
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: MonthClose) {
      return `Closed month · ${this.month ?? ''}`;
    },
  });

  /** Close the month: the realm checks the stored totals balance and stamps who closed it. */
  @operation static post = {
    base: 'transform',
    transformations: bxl`
      assert(if .status == null then true else .status == "draft" end; "This month is already closed.");
      assert((.totals | length) > 0; "A closed month needs its totals.");
      assert([.totals[].debitMinor, .totals[].creditMinor] | all(. >= 0); "Totals can't be negative.");
      assert([.totals[].debitMinor] + [.totals[].creditMinor | 0 - .] | add | . == 0; "The month's debits and credits must be equal.");
      .status = "closed";
      .closedBy = actor();
    `,
  } satisfies OperationDeclaration;
  /** Draft a reconciliation of a bank or card statement ending in this month; BankReconciliation.finish marks it done. */
  @operation static reconcile = {
    base: 'create',
    of: BankReconciliation,
    params: {
      account: StringField,
      side: StringField,
      statementDate: StringField,
      endingBalanceMinor: NumberField,
      outstanding: OutstandingItem,
    },
    fill: {
      account: params('account'),
      side: params('side'),
      statementDate: params('statementDate'),
      endingBalanceMinor: params('endingBalanceMinor'),
      outstanding: params('outstanding'),
      status: 'draft',
    },
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof MonthClose> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Through', value: day(m.through), strong: true },
        { key: 'Debits', value: money(m.debitMinor) },
        { key: 'Credits', value: money(m.creditMinor) },
        { key: 'Closed by', value: m.closedBy ?? 'Not closed' },
      ];
    }
    get checks() {
      return (this.args.model.checks ?? []).filter(Boolean).map((c) => ({
        ok: c!.startsWith('pass'),
        text: c!.replace(/^(pass|FAIL) · /, ''),
      }));
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
        @eyebrow='Closed month'
        @title={{@model.month}}
        @figureMinor={{@model.debitMinor}}
        @figureLabel='Posted'
        @status={{if
          @model.closedBy
          'Closed'
          (if @model.ready 'Ready to close' 'Not ready')
        }}
      >
        <Part @title='Close'><Facts @items={{this.facts}} /></Part>
        <Part @title='Checklist'><ul class='checks'>{{#each
              this.checks
              as |c|
            }}<li data-check={{if c.ok 'pass' 'fail'}}><span>{{if
                    c.ok
                    '✓'
                    '✕'
                  }}</span>{{c.text}}</li>{{/each}}</ul></Part>
        <Part @title='Totals as closed'>
          <StatementTable
            @label='Totals as closed'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @density='compact'
          />
        </Part>
      </Sheet>
      <style scoped>
        .checks {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: 0.35rem;
          font-size: 0.8125rem;
        }
        .checks li {
          display: flex;
          gap: 0.5rem;
        }
        .checks li[data-check='fail'] {
          color: var(--destructive);
        }
      </style>
    </template>
  };
  static embedded = class extends Component<typeof MonthClose> {
    <template>
      <Strip
        @eyebrow='Closed month'
        @title={{@model.month}}
        @figure={{money @model.debitMinor}}
        @meta={{@model.closedBy}}
      />
    </template>
  };
  static fitted = class extends Component<typeof MonthClose> {
    <template>
      <Fit
        @eyebrow='Closed'
        @title={{@model.month}}
        @figure={{money @model.debitMinor}}
        @meta='Posted'
      />
    </template>
  };
}

// ── statements over closed months ───────────────────────────────────────────
export class StatementRow extends FieldDef {
  @field section = contains(StringField);
  @field account = contains(StringField);
  @field name = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
  @field amountMinor = contains(NumberField); // on the section's normal side
}
const rowsFor = (
  net: Net,
  accounts: (LedgerAccount | undefined)[] | undefined,
  sections: string[],
) => {
  let names = chart(accounts),
    out: StatementRow[] = [];
  for (let [account, v] of net) {
    let a = names.get(account);
    if (!v || !a || !sections.includes(a.section)) continue;
    out.push(
      new StatementRow({
        section: a.section,
        account,
        name: a.name,
        debitMinor: Math.max(0, v),
        creditMinor: Math.max(0, -v),
        amountMinor: ['asset', 'cogs', 'expense'].includes(a.section) ? v : -v,
      }),
    );
  }
  return out.sort((x, y) => (x.account ?? '').localeCompare(y.account ?? ''));
};
const sumOf = (
  rows: (StatementRow | undefined)[] | undefined,
  section: string,
) =>
  (rows ?? [])
    .filter((r) => r?.section === section)
    .reduce((n, r) => n + (r!.amountMinor ?? 0), 0);
const incomeOf = (
  net: Net,
  accounts: (LedgerAccount | undefined)[] | undefined,
) => {
  let names = chart(accounts),
    n = 0;
  for (let [account, v] of net)
    if (
      ['income', 'cogs', 'expense'].includes(names.get(account)?.section ?? '')
    )
      n -= v;
  return n;
};

export class TrialBalance extends CardDef {
  static displayName = 'Trial balance';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field throughMonth = contains(IsoMonthField);
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.throughMonth' } } },
      page: { size: 240 },
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  @field view = contains(ReportView); // a comparison column; accrual only
  @field rows = containsMany(StatementRow, {
    computeVia: function (this: TrialBalance) {
      return rowsFor(netOf(this.closes), this.accounts, [
        'asset',
        'liability',
        'equity',
        'income',
        'cogs',
        'expense',
      ]);
    },
  });
  @field debitMinor = contains(NumberField, {
    computeVia: function (this: TrialBalance) {
      return (this.rows ?? []).reduce((n, r) => n + (r?.debitMinor ?? 0), 0);
    },
  });
  @field creditMinor = contains(NumberField, {
    computeVia: function (this: TrialBalance) {
      return (this.rows ?? []).reduce((n, r) => n + (r?.creditMinor ?? 0), 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: TrialBalance) {
      return `Trial balance · through ${this.throughMonth ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof TrialBalance> {
    noColumns: ViewChoice['columns'][] = [];
    // A comparison adds the balance at the earlier month's end, debit positive, and the change.
    get compared() {
      let m = this.args.model,
        through = m.throughMonth ?? '',
        cmp = comparePeriod(through, through, viewOf(m.view).compare);
      if (!cmp) return undefined;
      return {
        label: cmp.label,
        net: netOf(
          (m.closes ?? []).filter((c) => c && (c.month ?? '') <= cmp!.to),
        ),
      };
    }
    get cols(): Col[] {
      let c = this.compared;
      return c
        ? [...DR_CR_COLS, amountCol('compare', `${c.label} (debit)`), changeCol]
        : DR_CR_COLS;
    }
    get rows(): Line[] {
      let m = this.args.model,
        c = this.compared;
      let withCompare = (account: string, dr: number, cr: number) =>
        c
          ? {
              compare: c.net.get(account) ?? 0,
              change: dr - cr - (c.net.get(account) ?? 0),
            }
          : {};
      return [
        ...(m.rows ?? []).filter(Boolean).map((r) => ({
          key: r!.account ?? '',
          cells: {
            code: r!.account,
            name: r!.name,
            dr: r!.debitMinor,
            cr: r!.creditMinor,
            ...withCompare(
              r!.account ?? '',
              r!.debitMinor ?? 0,
              r!.creditMinor ?? 0,
            ),
          },
          data: {
            row: true,
            key: r!.account,
            dr: r!.debitMinor ?? 0,
            cr: r!.creditMinor ?? 0,
          },
        })),
        // An account with a balance only at the earlier month still shows, at nothing now.
        ...(c
          ? [...c.net]
              .filter(
                ([account, v]) =>
                  v &&
                  (m.accounts ?? []).some((x) => x?.code === account) &&
                  !(m.rows ?? []).some((r) => r?.account === account),
              )
              .sort(([a], [b]) => a.localeCompare(b))
              .map(([account, v]) => ({
                key: account,
                cells: {
                  code: account,
                  name: (m.accounts ?? []).find((x) => x?.code === account)
                    ?.name,
                  compare: v,
                  change: -v,
                },
              }))
          : []),
        {
          key: 'total',
          role: 'total' as const,
          cells: {
            code: '',
            name: 'Total',
            dr: m.debitMinor,
            cr: m.creditMinor,
            ...(c ? { compare: 0, change: 0 } : {}),
          },
        },
      ];
    }
    get note() {
      return `From ${(this.args.model.closes ?? []).filter(Boolean).length} closed months.`;
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
        <Part @title='View'><ReportViewControls
            @model={{@model}}
            @columns={{this.noColumns}}
          /></Part>
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
  static embedded = class extends Component<typeof TrialBalance> {
    <template>
      <Strip
        @eyebrow='Trial balance'
        @title={{@model.cardTitle}}
        @figure={{money @model.debitMinor}}
        @meta='Debits = credits'
      />
    </template>
  };
  static fitted = class extends Component<typeof TrialBalance> {
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
const eqMinor = (a: number | undefined, b: number | undefined) =>
  (a ?? 0) === (b ?? 0);
const MONTH_NAME = new Intl.DateTimeFormat('en-US', {
  month: 'long',
  year: 'numeric',
  timeZone: 'UTC',
});
const monthName = (ym: string | undefined) => {
  let d = new Date(`${ym}-15T00:00:00Z`);
  return Number.isNaN(d.getTime()) ? String(ym ?? '') : MONTH_NAME.format(d);
};
const SHORT_MONTH = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  year: 'numeric',
  timeZone: 'UTC',
});
const columnLabel = (columns: ViewChoice['columns'], key: string) =>
  columns === 'month'
    ? SHORT_MONTH.format(new Date(`${key}-15T00:00:00Z`))
    : key;
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

/**
 * A profit and loss read through its view: each account by column (months, quarters, classes, or
 * customer or vendor), a total, and any comparison, on the accrual or cash basis.
 */
function pnlByView(
  m: ProfitAndLoss,
  v: ViewChoice,
): { cols: Col[]; rows: Line[] } {
  let from = m.fromMonth ?? '',
    to = m.toMonth ?? '';
  let src = {
    journal: m.journal,
    invoices: m.invoices,
    bills: m.bills,
    openings: m.openings,
  };
  let entries = v.basis === 'cash' ? cashEntries(src) : accrualEntries(src);
  let names = chart(m.accounts);
  let main = netByColumn(entries, from, to, columnKey(v.columns));
  let keys =
    v.columns === 'month'
      ? monthsBetween(from, to)
      : v.columns === 'quarter'
        ? [...new Set(monthsBetween(from, to).map(quarterOf))]
        : v.columns === 'total'
          ? []
          : [
              ...new Set([...main.values()].flatMap((c) => [...c.keys()])),
            ].sort();
  let cmp = comparePeriod(from, to, v.compare);
  let before = cmp
    ? netByColumn(entries, cmp.from, cmp.to, () => '')
    : undefined;
  let side = (account: string, raw: number) =>
    names.get(account)?.section === 'income' ? -raw : raw;
  let totalOf = (byCol: Map<string, number> | undefined) =>
    [...(byCol?.values() ?? [])].reduce((n, x) => n + x, 0);
  // The cells of one account, or of a sum of accounts, on the section's normal side.
  let cells = (accounts: string[]) => {
    let c: Record<string, number> = {};
    for (let k of keys)
      c[`c:${k}`] = accounts.reduce(
        (n, a) => n + side(a, main.get(a)?.get(k) ?? 0),
        0,
      );
    c.total = accounts.reduce((n, a) => n + side(a, totalOf(main.get(a))), 0);
    if (before) {
      c.compare = accounts.reduce(
        (n, a) => n + side(a, totalOf(before!.get(a))),
        0,
      );
      c.change = c.total - c.compare;
    }
    return c;
  };
  // The accounts with a figure in some column, as the plain statement leaves out an account at nothing.
  let accountsIn = (section: string) =>
    [...new Set([...main.keys(), ...(before?.keys() ?? [])])]
      .filter((a) => names.get(a)?.section === section)
      .filter((a) => Object.values(cells([a])).some((x) => x !== 0))
      .sort();
  let rows: Line[] = [];
  let section = (key: string) => {
    let accounts = accountsIn(key);
    rows.push(
      { key: `h-${key}`, role: 'heading', cells: { code: SECTION_TITLE[key] } },
      ...accounts.map((a) => ({
        key: a,
        depth: 1,
        cells: { code: a, name: names.get(a)?.name ?? '', ...cells([a]) },
        data: { row: true, key: a },
      })),
      {
        key: `t-${key}`,
        role: 'subtotal',
        cells: {
          code: '',
          name: `Total ${SECTION_TITLE[key]}`,
          ...cells(accounts),
        },
      },
    );
    return accounts;
  };
  let income = section('income'),
    cogs = section('cogs');
  let combine = (plus: string[], minus: string[]) => {
    let p = cells(plus),
      n = cells(minus),
      out: Record<string, number> = {};
    for (let k of Object.keys(p)) out[k] = p[k] - n[k];
    return out;
  };
  rows.push({
    key: 'gross',
    role: 'subtotal',
    cells: { code: '', name: 'Gross profit', ...combine(income, cogs) },
  });
  let expense = section('expense');
  rows.push({
    key: 'net',
    role: 'total',
    cells: {
      code: '',
      name: 'Net income',
      ...combine(income, [...cogs, ...expense]),
    },
  });
  let cols: Col[] = [
    ...ACCOUNT_COLS,
    ...keys.map((k) => amountCol(`c:${k}`, columnLabel(v.columns, k))),
    amountCol('total', 'Total'),
    ...(cmp ? [amountCol('compare', cmp.label), changeCol] : []),
  ];
  return { cols, rows };
}

/** Balances on each section's normal side as of a month's end, with this and prior years' income. */
function balancesAt(
  closes: (MonthClose | undefined)[] | undefined,
  accounts: (LedgerAccount | undefined)[] | undefined,
  asOf: string,
  fiscalStartMonth: number,
) {
  let upTo = (closes ?? []).filter((c) => c && (c.month ?? '') <= asOf);
  let start = fiscalYearStartOf(asOf, fiscalStartMonth);
  let amounts = new Map<string, number>();
  for (let r of rowsFor(netOf(upTo), accounts, [
    'asset',
    'liability',
    'equity',
  ]))
    amounts.set(r.account ?? '', r.amountMinor ?? 0);
  return {
    amounts,
    netIncome: incomeOf(
      netOf(upTo.filter((c) => (c!.month ?? '') >= start)),
      accounts,
    ),
    priorIncome: incomeOf(
      netOf(upTo.filter((c) => (c!.month ?? '') < start)),
      accounts,
    ),
  };
}

/** A balance sheet read through its view: as of each month or quarter end, and any comparison. */
function balanceSheetByView(
  m: BalanceSheet,
  v: ViewChoice,
): { cols: Col[]; rows: Line[] } {
  let asOf = m.asOfMonth ?? '',
    fy = settingsOf(m).fiscalYearStart,
    names = chart(m.accounts);
  let start = fiscalYearStartOf(asOf, fy);
  let ends =
    v.columns === 'month'
      ? monthsBetween(start, asOf)
      : v.columns === 'quarter'
        ? monthsBetween(start, asOf).filter(
            (ym, i, all) =>
              ym === asOf || quarterOf(ym) !== quarterOf(all[i + 1] ?? ''),
          )
        : [];
  let cmp = comparePeriod(asOf, asOf, v.compare);
  let at = new Map(
    [...ends, asOf, ...(cmp ? [cmp.to] : [])].map((ym) => [
      ym,
      balancesAt(m.closes, m.accounts, ym, fy),
    ]),
  );
  let colsFor = (fn: (b: ReturnType<typeof balancesAt>) => number) => {
    let c: Record<string, number> = {};
    for (let ym of ends) c[`c:${ym}`] = fn(at.get(ym)!);
    c.total = fn(at.get(asOf)!);
    if (cmp) {
      c.compare = fn(at.get(cmp.to)!);
      c.change = c.total - c.compare;
    }
    return c;
  };
  let accountsIn = (section: string) =>
    [...new Set([...at.values()].flatMap((b) => [...b.amounts.keys()]))]
      .filter((a) => names.get(a)?.section === section)
      .sort();
  let sum = (accounts: string[]) => (b: ReturnType<typeof balancesAt>) =>
    accounts.reduce((n, a) => n + (b.amounts.get(a) ?? 0), 0);
  let rows: Line[] = [];
  let section = (
    key: string,
    extra: {
      n: string;
      f: (b: ReturnType<typeof balancesAt>) => number;
    }[] = [],
  ) => {
    let accounts = accountsIn(key);
    rows.push(
      { key: `h-${key}`, role: 'heading', cells: { code: SECTION_TITLE[key] } },
      ...accounts.map((a) => ({
        key: a,
        depth: 1,
        cells: {
          code: a,
          name: names.get(a)?.name ?? '',
          ...colsFor(sum([a])),
        },
        data: { row: true, key: a },
      })),
      ...extra.map((x) => ({
        key: x.n,
        depth: 1,
        cells: { code: '', name: x.n, ...colsFor(x.f) },
      })),
      {
        key: `t-${key}`,
        role: 'subtotal',
        cells: {
          code: '',
          name: `Total ${SECTION_TITLE[key]}`,
          ...colsFor(
            (b) => sum(accounts)(b) + extra.reduce((n, x) => n + x.f(b), 0),
          ),
        },
      },
    );
    return accounts;
  };
  section('asset');
  let liabilities = section('liability');
  let equityExtra = [
    {
      n: 'Prior years’ income',
      f: (b: ReturnType<typeof balancesAt>) => b.priorIncome,
    },
    {
      n: 'Net income this year',
      f: (b: ReturnType<typeof balancesAt>) => b.netIncome,
    },
  ];
  let equity = section('equity', equityExtra);
  rows.push({
    key: 'le',
    role: 'total',
    cells: {
      code: '',
      name: 'Total liabilities and equity',
      ...colsFor(
        (b) =>
          sum([...liabilities, ...equity])(b) + b.priorIncome + b.netIncome,
      ),
    },
  });
  let cols: Col[] = [
    ...ACCOUNT_COLS,
    ...ends
      .filter((ym) => ym !== asOf)
      .map((ym) =>
        amountCol(
          `c:${ym}`,
          SHORT_MONTH.format(new Date(`${ym}-15T00:00:00Z`)),
        ),
      ),
    amountCol('total', SHORT_MONTH.format(new Date(`${asOf}-15T00:00:00Z`))),
    ...(cmp ? [amountCol('compare', cmp.label), changeCol] : []),
  ];
  return { cols, rows };
}

export class ProfitAndLoss extends CardDef {
  static displayName = 'Profit and loss';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field fromMonth = contains(IsoMonthField);
  @field toMonth = contains(IsoMonthField);
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: {
        range: { month: { gte: '$this.fromMonth', lte: '$this.toMonth' } },
      },
      page: { size: 240 },
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  @field view = contains(ReportView);
  // The months a view reads: from the comparison's start, or on the cash basis from as far back as the
  // invoices and bills its payments settle, through the period's end.
  @field readFromMonth = contains(StringField, {
    computeVia: function (this: ProfitAndLoss) {
      let v = viewOf(this.view),
        from = this.fromMonth ?? '',
        cmp = comparePeriod(from, this.toMonth ?? '', v.compare);
      return v.basis === 'cash' ? '0000-01' : (cmp?.from ?? from);
    },
  });
  @field readFromDate = contains(StringField, {
    computeVia: function (this: ProfitAndLoss) {
      return `${this.readFromMonth ?? ''}-01`;
    },
  });
  @field readToDate = contains(StringField, {
    computeVia: function (this: ProfitAndLoss) {
      return this.toMonth ? monthEnd(this.toMonth) : '';
    },
  });
  // The postings themselves, read only when the view needs them, newest first so a capped page drops
  // the oldest.
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
  @field rows = containsMany(StatementRow, {
    computeVia: function (this: ProfitAndLoss) {
      return rowsFor(netOf(this.closes), this.accounts, [
        'income',
        'cogs',
        'expense',
      ]);
    },
  });
  @field incomeMinor = contains(NumberField, {
    computeVia: function (this: ProfitAndLoss) {
      return sumOf(this.rows, 'income');
    },
  });
  @field cogsMinor = contains(NumberField, {
    computeVia: function (this: ProfitAndLoss) {
      return sumOf(this.rows, 'cogs');
    },
  });
  @field expenseMinor = contains(NumberField, {
    computeVia: function (this: ProfitAndLoss) {
      return sumOf(this.rows, 'expense');
    },
  });
  @field grossProfitMinor = contains(NumberField, {
    computeVia: function (this: ProfitAndLoss) {
      return (this.incomeMinor ?? 0) - (this.cogsMinor ?? 0);
    },
  });
  @field netIncomeMinor = contains(NumberField, {
    computeVia: function (this: ProfitAndLoss) {
      return (this.grossProfitMinor ?? 0) - (this.expenseMinor ?? 0);
    },
  });
  // What the tiles' figure is: always the closed months' accrual net income, which a view doesn't change.
  @field figureNote = contains(StringField, {
    computeVia: function (this: ProfitAndLoss) {
      return isPlainView(viewOf(this.view))
        ? 'Net income'
        : 'Net income, closed months on accrual';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: ProfitAndLoss) {
      return this.fromMonth === this.toMonth
        ? `Profit and loss · ${this.fromMonth ?? ''}`
        : `Profit and loss · ${this.fromMonth ?? ''} to ${this.toMonth ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof ProfitAndLoss> {
    cols = AMOUNT_COLS;
    // Each account opens to its months, on the section's normal side, from the closed months.
    get byMonth(): Map<string, Line[]> {
      let m = this.args.model,
        side = new Map(
          (m.rows ?? [])
            .filter(Boolean)
            .map((r) => [r!.account ?? '', r!.section ?? '']),
        ),
        out = new Map<string, Line[]>();
      let closes = ((m.closes ?? []).filter(Boolean) as MonthClose[]).sort(
        (a, b) => (a.month ?? '').localeCompare(b.month ?? ''),
      );
      for (let c of closes)
        for (let t of c.totals ?? []) {
          let section = side.get(t?.account ?? '');
          if (!section) continue;
          let v = (t!.debitMinor ?? 0) - (t!.creditMinor ?? 0),
            amount = section === 'income' ? -v : v;
          if (!amount) continue;
          let list = out.get(t!.account!) ?? [];
          list.push({
            key: c.month ?? '',
            cells: { code: '', name: monthName(c.month), amount },
          });
          out.set(t!.account!, list);
        }
      return out;
    }
    expandLabel = (row: Line) =>
      `Show ${row.cells['name'] ?? row.key} by month`;
    // One statement: each section's lines and subtotal, gross profit, and net income double-ruled.
    get rows(): Line[] {
      let m = this.args.model,
        rows = (m.rows ?? []).filter(Boolean) as StatementRow[],
        months = this.byMonth;
      let section = (key: string, total: number | undefined): Line[] => [
        {
          key: `h-${key}`,
          role: 'heading',
          cells: { code: SECTION_TITLE[key] },
        },
        ...rows
          .filter((r) => r.section === key)
          .map((r) => ({
            key: r.account ?? '',
            depth: 1,
            cells: { code: r.account, name: r.name, amount: r.amountMinor },
            data: { row: true, key: r.account, total: r.amountMinor ?? 0 },
            children: months.get(r.account ?? ''),
          })),
        {
          key: `t-${key}`,
          role: 'subtotal',
          cells: {
            code: '',
            name: `Total ${SECTION_TITLE[key]}`,
            amount: total,
          },
        },
      ];
      return [
        ...section('income', m.incomeMinor),
        ...section('cogs', m.cogsMinor),
        {
          key: 'gross',
          role: 'subtotal',
          cells: { code: '', name: 'Gross profit', amount: m.grossProfitMinor },
        },
        ...section('expense', m.expenseMinor),
        {
          key: 'net',
          role: 'total',
          cells: { code: '', name: 'Net income', amount: m.netIncomeMinor },
        },
      ];
    }
    get choice() {
      return viewOf(this.args.model.view);
    }
    // The postings a view reads load on first read; until all four have, the table waits.
    get loading() {
      return (
        !isPlainView(this.choice) &&
        !sourcesLoaded(this.args.model as ProfitAndLoss)
      );
    }
    get viewed() {
      let m = this.args.model as ProfitAndLoss,
        v = this.choice;
      if (isPlainView(v) || this.loading) return undefined;
      let t = pnlByView(m, v);
      let net = t.rows.find((r) => r.key === 'net');
      return { ...t, net: (net?.cells['total'] as number | undefined) ?? 0 };
    }
    get viewNote() {
      let m = this.args.model as ProfitAndLoss;
      return [
        this.choice.basis === 'cash'
          ? 'Cash basis: an invoice or bill counts when a payment is applied to it, in the share paid; credit memos, write-offs and vendor credits only change what is owed, so they don’t count.'
          : 'From the postings in this period, closed or not.',
        // A source read only to its page leaves figures out, so the statement says which.
        ...sourceNotes(m),
      ]
        .filter(Boolean)
        .join(' ');
    }
    get facts(): Fact[] {
      let m = this.args.model,
        pct = m.incomeMinor
          ? ` · ${percent((m.grossProfitMinor ?? 0) / m.incomeMinor)} margin`
          : '';
      return [
        { key: 'Income', value: money(m.incomeMinor) },
        {
          key: 'Gross profit',
          value: `${money(m.grossProfitMinor)}${pct}`,
          strong: true,
        },
        { key: 'Expenses', value: money(m.expenseMinor) },
        { key: 'Net income', value: money(m.netIncomeMinor), strong: true },
      ];
    }
    <template>
      {{#let this.viewed as |viewed|}}<Sheet
          @eyebrow='Profit and loss'
          @title={{@model.cardTitle}}
          @figureMinor={{if
            viewed
            viewed.net
            (if this.loading undefined @model.netIncomeMinor)
          }}
          @figureLabel='Net income'
          @note={{if
            viewed
            this.viewNote
            (if
              this.loading
              'Reading the period’s postings…'
              'From the closed months in this period.'
            )
          }}
        >
          {{#unless (or viewed this.loading)}}<Part @title='Summary'><Facts
                @items={{this.facts}}
              /></Part>{{/unless}}
          <Part @title='View'><ReportViewControls
              @model={{@model}}
              @cash={{true}}
            /></Part>
          {{#if this.loading}}
            <Part @title='Statement'><p>Reading the period’s postings…</p></Part>
          {{else if viewed}}
            <Part @title='Statement'><StatementTable
                @label='Profit and loss'
                @columns={{viewed.cols}}
                @rows={{viewed.rows}}
              /></Part>
          {{else}}
            <Part @title='Statement'><StatementTable
                @label='Profit and loss'
                @columns={{this.cols}}
                @rows={{this.rows}}
                @expandLabel={{this.expandLabel}}
              /></Part>
          {{/if}}
        </Sheet>{{/let}}
    </template>
  };
  static embedded = class extends Component<typeof ProfitAndLoss> {
    <template>
      <Strip
        @eyebrow='Profit and loss'
        @title={{@model.cardTitle}}
        @figure={{money @model.netIncomeMinor}}
        @meta={{@model.figureNote}}
      />
    </template>
  };
  static fitted = class extends Component<typeof ProfitAndLoss> {
    <template>
      <Fit
        @eyebrow='P&L'
        @title={{@model.toMonth}}
        @figure={{money @model.netIncomeMinor}}
        @meta={{@model.figureNote}}
      />
    </template>
  };
}

export class BalanceSheet extends CardDef {
  static displayName = 'Balance sheet';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field asOfMonth = contains(IsoMonthField);
  @field settings = settingsLink();
  @field fiscalStart = contains(StringField, {
    computeVia: function (this: BalanceSheet) {
      return this.asOfMonth
        ? fiscalYearStartOf(this.asOfMonth, settingsOf(this).fiscalYearStart)
        : '';
    },
  });
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.asOfMonth' } } },
      page: { size: 240 },
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  @field view = contains(ReportView); // columns by month or quarter end, and a comparison; accrual only
  @field rows = containsMany(StatementRow, {
    computeVia: function (this: BalanceSheet) {
      return rowsFor(netOf(this.closes), this.accounts, [
        'asset',
        'liability',
        'equity',
      ]);
    },
  });
  @field netIncomeMinor = contains(NumberField, {
    computeVia: function (this: BalanceSheet) {
      let s = this.fiscalStart ?? '';
      return incomeOf(
        netOf((this.closes ?? []).filter((c) => c && (c.month ?? '') >= s)),
        this.accounts,
      );
    },
  });
  @field priorIncomeMinor = contains(NumberField, {
    computeVia: function (this: BalanceSheet) {
      let s = this.fiscalStart ?? '';
      return incomeOf(
        netOf((this.closes ?? []).filter((c) => c && (c.month ?? '') < s)),
        this.accounts,
      );
    },
  });
  @field assetsMinor = contains(NumberField, {
    computeVia: function (this: BalanceSheet) {
      return sumOf(this.rows, 'asset');
    },
  });
  @field liabilitiesMinor = contains(NumberField, {
    computeVia: function (this: BalanceSheet) {
      return sumOf(this.rows, 'liability');
    },
  });
  @field equityMinor = contains(NumberField, {
    computeVia: function (this: BalanceSheet) {
      return (
        sumOf(this.rows, 'equity') +
        (this.priorIncomeMinor ?? 0) +
        (this.netIncomeMinor ?? 0)
      );
    },
  });
  @field balanced = contains(BooleanField, {
    computeVia: function (this: BalanceSheet) {
      return (
        this.assetsMinor ===
        (this.liabilitiesMinor ?? 0) + (this.equityMinor ?? 0)
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BalanceSheet) {
      return `Balance sheet · ${this.asOfMonth ? monthEnd(this.asOfMonth) : ''}`;
    },
  });
  static isolated = class extends Component<typeof BalanceSheet> {
    cols = AMOUNT_COLS;
    columnChoices: ViewChoice['columns'][] = ['total', 'month', 'quarter'];
    // Accrual only: a basis stored on the card doesn't change it.
    get viewed() {
      let m = this.args.model as BalanceSheet,
        v = { ...viewOf(m.view), basis: 'accrual' as const };
      if (isPlainView(v) || !m.asOfMonth) return undefined;
      return balanceSheetByView(m, v);
    }
    get rows(): Line[] {
      let m = this.args.model,
        rows = (m.rows ?? []).filter(Boolean) as StatementRow[];
      let section = (
        key: string,
        total: number | undefined,
        extra: { n: string; m: number }[] = [],
      ): Line[] => [
        {
          key: `h-${key}`,
          role: 'heading',
          cells: { code: SECTION_TITLE[key] },
        },
        ...rows
          .filter((r) => r.section === key)
          .map((r) => ({
            key: r.account ?? '',
            depth: 1,
            cells: { code: r.account, name: r.name, amount: r.amountMinor },
            data: { row: true, key: r.account, total: r.amountMinor ?? 0 },
          })),
        ...extra
          .filter((x) => x.m)
          .map((x) => ({
            key: x.n,
            depth: 1,
            cells: { code: '', name: x.n, amount: x.m },
            data: { row: true, key: x.n, total: x.m },
          })),
        {
          key: `t-${key}`,
          role: 'subtotal',
          cells: {
            code: '',
            name: `Total ${SECTION_TITLE[key]}`,
            amount: total,
          },
        },
      ];
      return [
        ...section('asset', m.assetsMinor),
        ...section('liability', m.liabilitiesMinor),
        ...section('equity', m.equityMinor, [
          { n: 'Prior years’ income', m: m.priorIncomeMinor ?? 0 },
          { n: 'Net income this year', m: m.netIncomeMinor ?? 0 },
        ]),
        {
          key: 'le',
          role: 'total',
          cells: {
            code: '',
            name: 'Total liabilities and equity',
            amount: (m.liabilitiesMinor ?? 0) + (m.equityMinor ?? 0),
          },
        },
      ];
    }
    <template>
      {{#let this.viewed as |viewed|}}<Sheet
          @eyebrow='Balance sheet'
          @title={{@model.cardTitle}}
          @figureMinor={{@model.assetsMinor}}
          @figureLabel='Total assets'
          @status={{if @model.balanced 'Balanced' 'Unbalanced'}}
          @note='From the closed months through this one. This year’s income stays in equity until the year is closed.'
        >
          <Part @title='View'><ReportViewControls
              @model={{@model}}
              @columns={{this.columnChoices}}
            /></Part>
          <Part @title='Statement'><StatementTable
              @label='Balance sheet'
              @columns={{if viewed viewed.cols this.cols}}
              @rows={{if viewed viewed.rows this.rows}}
            /></Part>
        </Sheet>{{/let}}
    </template>
  };
  static embedded = class extends Component<typeof BalanceSheet> {
    <template>
      <Strip
        @eyebrow='Balance sheet'
        @title={{@model.cardTitle}}
        @figure={{money @model.assetsMinor}}
        @meta='Total assets'
      />
    </template>
  };
  static fitted = class extends Component<typeof BalanceSheet> {
    <template>
      <Fit
        @eyebrow='Balance sheet'
        @title={{@model.asOfMonth}}
        @figure={{money @model.assetsMinor}}
        @meta='Assets'
      />
    </template>
  };
}

export { AccountTotal as ClosedTotal };
