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
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';

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

const SECTION: Record<string, string> = {
  bank: 'asset',
  ar: 'asset',
  asset: 'asset',
  inventory: 'asset',
  clearing: 'asset',
  fixed: 'asset',
  contra: 'asset',
  ap: 'liability',
  cc: 'liability',
  liability: 'liability',
  longterm: 'liability',
  equity: 'equity',
  income: 'income',
  cogs: 'cogs',
  expense: 'expense',
  other: 'expense',
};
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

export class ClosedTotal extends FieldDef {
  static displayName = 'Account total';
  @field account = contains(StringField);
  @field debitMinor = contains(NumberField);
  @field creditMinor = contains(NumberField);
}
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
        section: SECTION[a!.type ?? ''] ?? '',
      },
    ]),
  );

// ── bank and card reconciliations ───────────────────────────────────────────
export class OutstandingItem extends FieldDef {
  static displayName = 'Outstanding item';
  @field ref = contains(StringField);
  @field amountMinor = contains(NumberField); // as the books carry it: a payment not yet cleared is negative
}

export class BankReconciliation extends CardDef {
  static displayName = 'Reconciliation';
  static icon = BookIcon;
  @field account = contains(StringField);
  @field side = contains(StringField); // debit for a bank account, credit for a card
  @field statementDate = contains(StringField);
  @field endingBalanceMinor = contains(NumberField); // per the statement
  @field outstanding = containsMany(OutstandingItem); // on the books, not yet on the statement
  @field status = contains(StringField); // draft → reconciled
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

  /** Finish the reconciliation against the book balance the caller read from the closed months. The
   *  realm refuses unless statement = books − not yet cleared, to the cent, and keeps the book balance it
   *  was finished against, so a later look can tell if the books moved under it. */
  @operation static finish = {
    base: 'transform',
    params: { bookBalanceMinor: NumberField },
    transformations: bxl`
      assert(.status == "draft"; "This reconciliation is already finished.");
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
  @field month = contains(StringField); // YYYY-MM
  @field totals = containsMany(ClosedTotal); // stored at close: the month's totals per account
  @field status = contains(StringField); // draft → closed
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
      assert(.status == "draft"; "This month is already closed.");
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
  @field throughMonth = contains(StringField);
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.throughMonth' } } },
      page: { size: 240 },
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
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
    cols = DR_CR_COLS;
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

export class ProfitAndLoss extends CardDef {
  static displayName = 'Profit and loss';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field fromMonth = contains(StringField);
  @field toMonth = contains(StringField);
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
      <Sheet
        @eyebrow='Profit and loss'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.netIncomeMinor}}
        @figureLabel='Net income'
        @note='From the closed months in this period.'
      >
        <Part @title='Summary'><Facts @items={{this.facts}} /></Part>
        <Part @title='Statement'><StatementTable
            @label='Profit and loss'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @expandLabel={{this.expandLabel}}
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof ProfitAndLoss> {
    <template>
      <Strip
        @eyebrow='Profit and loss'
        @title={{@model.cardTitle}}
        @figure={{money @model.netIncomeMinor}}
        @meta='Net income'
      />
    </template>
  };
  static fitted = class extends Component<typeof ProfitAndLoss> {
    <template>
      <Fit
        @eyebrow='P&L'
        @title={{@model.toMonth}}
        @figure={{money @model.netIncomeMinor}}
        @meta='Net income'
      />
    </template>
  };
}

export class BalanceSheet extends CardDef {
  static displayName = 'Balance sheet';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field asOfMonth = contains(StringField);
  @field fiscalStart = contains(StringField, {
    computeVia: function (this: BalanceSheet) {
      return this.asOfMonth ? `${this.asOfMonth.slice(0, 4)}-01` : '';
    },
  }); // the fiscal year starts in January
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.asOfMonth' } } },
      page: { size: 240 },
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
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
      <Sheet
        @eyebrow='Balance sheet'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.assetsMinor}}
        @figureLabel='Total assets'
        @status={{if @model.balanced 'Balanced' 'Unbalanced'}}
        @note='From the closed months through this one. This year’s income stays in equity until the year is closed.'
      >
        <Part @title='Statement'><StatementTable
            @label='Balance sheet'
            @columns={{this.cols}}
            @rows={{this.rows}}
          /></Part>
      </Sheet>
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
