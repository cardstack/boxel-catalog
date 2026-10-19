// The year: a statement of cash flows (indirect method) over closed months, and the year-end close.
// Both read the closed months (ledger-close.gts); the conversion entry (the opening balances) is the
// starting position, not a cash flow.
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
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { LedgerAccount, ACCOUNT_TYPES } from './ledger-cards';
import { OpeningBalances } from './ledger-opening';
import { MonthClose, netOf } from './ledger-close';
import { Sheet, Part, Facts, Strip, Fit, money, type Fact } from './record-kit';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import { YearCloseStatusField } from './ledger-status';

const prevMonth = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`;
};

export class CashFlowLine extends FieldDef {
  @field section = contains(StringField); // operating, investing, financing
  @field account = contains(StringField);
  @field label = contains(StringField);
  @field amountMinor = contains(NumberField); // cash in positive, cash out negative
}

export class CashFlowStatement extends CardDef {
  static displayName = 'Statement of cash flows';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field fromMonth = contains(StringField);
  @field toMonth = contains(StringField);
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.toMonth' } } },
      page: { size: 240 },
    },
  });
  @field openings = linksToMany(() => OpeningBalances, {
    query: { filter: { eq: { status: 'posted' } }, page: { size: 10 } },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  // Each account's change over the period (debits less credits), with the conversion entry taken out:
  // the opening balances are where the period starts, not something that happened in it.
  @field lines = containsMany(CashFlowLine, {
    computeVia: function (this: CashFlowStatement) {
      let from = this.fromMonth ?? '',
        to = this.toMonth ?? '';
      let during = netOf(
        (this.closes ?? []).filter(
          (c) => c && (c.month ?? '') >= from && (c.month ?? '') <= to,
        ),
      );
      for (let o of (this.openings ?? []).filter(
        (o) =>
          o &&
          (o.date ?? '').slice(0, 7) >= from &&
          (o.date ?? '').slice(0, 7) <= to,
      ))
        for (let l of o!.ledgerLines ?? [])
          if (l?.account)
            during.set(
              l.account,
              (during.get(l.account) ?? 0) -
                ((l.debitMinor ?? 0) - (l.creditMinor ?? 0)),
            );
      let types = new Map(
        (this.accounts ?? [])
          .filter(Boolean)
          .map((a) => [
            a!.code ?? '',
            { type: a!.type ?? '', name: a!.name ?? '' },
          ]),
      );
      let out: CashFlowLine[] = [],
        income = 0;
      for (let [account, net] of during) {
        let t = types.get(account),
          section = ACCOUNT_TYPES[t?.type ?? '']?.cashFlow ?? 'operating';
        if (!net || section === 'cash') continue;
        if (section === 'income') {
          income -= net;
          continue;
        }
        out.push(
          new CashFlowLine({
            section,
            account,
            label: t?.name ?? account,
            amountMinor: -net,
          }),
        );
      }
      return [
        new CashFlowLine({
          section: 'operating',
          account: '',
          label: 'Net income',
          amountMinor: income,
        }),
        ...out.sort((a, b) => (a.account ?? '').localeCompare(b.account ?? '')),
      ];
    },
  });
  @field operatingMinor = contains(NumberField, {
    computeVia: function (this: CashFlowStatement) {
      return (this.lines ?? [])
        .filter((l) => l?.section === 'operating')
        .reduce((n, l) => n + (l!.amountMinor ?? 0), 0);
    },
  });
  @field investingMinor = contains(NumberField, {
    computeVia: function (this: CashFlowStatement) {
      return (this.lines ?? [])
        .filter((l) => l?.section === 'investing')
        .reduce((n, l) => n + (l!.amountMinor ?? 0), 0);
    },
  });
  @field financingMinor = contains(NumberField, {
    computeVia: function (this: CashFlowStatement) {
      return (this.lines ?? [])
        .filter((l) => l?.section === 'financing')
        .reduce((n, l) => n + (l!.amountMinor ?? 0), 0);
    },
  });
  @field cashAccounts = containsMany(StringField, {
    computeVia: function (this: CashFlowStatement) {
      return (this.accounts ?? [])
        .filter((a) => a?.type === 'bank')
        .map((a) => a!.code ?? '');
    },
  });
  @field beginCashMinor = contains(NumberField, {
    computeVia: function (this: CashFlowStatement) {
      let from = this.fromMonth ?? '',
        before = netOf(
          (this.closes ?? []).filter(
            (c) => c && (c.month ?? '') <= prevMonth(from),
          ),
        );
      let n = (this.cashAccounts ?? []).reduce(
        (s, a) => s + (before.get(a ?? '') ?? 0),
        0,
      );
      for (let o of (this.openings ?? []).filter(
        (o) =>
          o &&
          (o.date ?? '').slice(0, 7) >= from &&
          (o.date ?? '').slice(0, 7) <= (this.toMonth ?? ''),
      ))
        for (let l of o!.ledgerLines ?? [])
          if ((this.cashAccounts ?? []).includes(l?.account ?? ''))
            n += (l!.debitMinor ?? 0) - (l!.creditMinor ?? 0);
      return n;
    },
  });
  @field endCashMinor = contains(NumberField, {
    computeVia: function (this: CashFlowStatement) {
      let all = netOf(this.closes);
      return (this.cashAccounts ?? []).reduce(
        (s, a) => s + (all.get(a ?? '') ?? 0),
        0,
      );
    },
  });
  @field ties = contains(BooleanField, {
    computeVia: function (this: CashFlowStatement) {
      return (
        (this.beginCashMinor ?? 0) +
          (this.operatingMinor ?? 0) +
          (this.investingMinor ?? 0) +
          (this.financingMinor ?? 0) ===
        this.endCashMinor
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: CashFlowStatement) {
      return `Cash flows · ${this.fromMonth ?? ''} to ${this.toMonth ?? ''}`;
    },
  });

  static isolated = class extends Component<typeof CashFlowStatement> {
    cols: Col[] = [
      { key: 'code', label: 'No.', kind: 'code', width: '4.5rem' },
      { key: 'name', label: 'Line' },
      { key: 'amount', label: 'Amount', kind: 'amount' },
    ];
    // One statement: each activity's lines and net cash, then the change in cash and cash at the end.
    get rows(): Line[] {
      let m = this.args.model,
        lines = (m.lines ?? []).filter(Boolean) as CashFlowLine[];
      let s = (
        key: string,
        title: string,
        total: number | undefined,
      ): Line[] => [
        { key: `h-${key}`, role: 'heading', cells: { code: title } },
        ...lines
          .filter((l) => l.section === key)
          .map((l, i) => ({
            key: `${key}-${l.account || l.label || i}`,
            depth: 1,
            cells: { code: l.account, name: l.label, amount: l.amountMinor },
          })),
        {
          key: `t-${key}`,
          role: 'subtotal',
          cells: {
            code: '',
            name: `Net cash from ${title.toLowerCase()}`,
            amount: total,
          },
        },
      ];
      return [
        {
          key: 'begin',
          role: 'subtotal',
          cells: {
            code: '',
            name: 'Cash at the start',
            amount: m.beginCashMinor,
          },
        },
        ...s('operating', 'Operating activities', m.operatingMinor),
        ...s('investing', 'Investing activities', m.investingMinor),
        ...s('financing', 'Financing activities', m.financingMinor),
        {
          key: 'end',
          role: 'total',
          cells: { code: '', name: 'Cash at the end', amount: m.endCashMinor },
        },
      ];
    }
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Cash at the start', value: money(m.beginCashMinor) },
        { key: 'From operations', value: money(m.operatingMinor) },
        { key: 'From investing', value: money(m.investingMinor) },
        { key: 'From financing', value: money(m.financingMinor) },
        { key: 'Cash at the end', value: money(m.endCashMinor), strong: true },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Statement of cash flows'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.endCashMinor}}
        @figureLabel='Cash at the end'
        @status={{if @model.ties 'Ties to cash' 'Does not tie'}}
        @note='Indirect method, from the closed months: net income, then each balance sheet account’s change. The opening balances are the starting position.'
      >
        <Part @title='Summary'><div
            data-row
            data-key='summary'
            data-total={{@model.endCashMinor}}
            data-dr={{@model.beginCashMinor}}
          ><Facts @items={{this.facts}} /></div></Part>
        <Part @title='Statement'><StatementTable
            @label='Statement of cash flows'
            @columns={{this.cols}}
            @rows={{this.rows}}
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof CashFlowStatement> {
    <template>
      <Strip
        @eyebrow='Cash flows'
        @title={{@model.cardTitle}}
        @figure={{money @model.endCashMinor}}
        @meta='Cash at the end'
      />
    </template>
  };
  static fitted = class extends Component<typeof CashFlowStatement> {
    <template>
      <Fit
        @eyebrow='Cash flows'
        @title={{@model.toMonth}}
        @figure={{money @model.endCashMinor}}
        @meta='Ending cash'
      />
    </template>
  };
}

// ── the year-end close ──────────────────────────────────────────────────────
export class YearClose extends CardDef {
  static displayName = 'Year-end close';
  static icon = BookIcon;
  @field year = contains(NumberField);
  @field fromMonth = contains(StringField, {
    computeVia: function (this: YearClose) {
      return this.year ? `${this.year}-01` : '';
    },
  });
  @field toMonth = contains(StringField, {
    computeVia: function (this: YearClose) {
      return this.year ? `${this.year}-12` : '';
    },
  });
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: {
        range: { month: { gte: '$this.fromMonth', lte: '$this.toMonth' } },
      },
      page: { size: 24 },
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 500 } },
  });
  @field status = contains(YearCloseStatusField);
  @field signedOffBy = contains(StringField);
  @field monthsClosed = contains(NumberField, {
    computeVia: function (this: YearClose) {
      return (this.closes ?? []).filter((c) => c?.closedBy).length;
    },
  });
  @field netIncomeMinor = contains(NumberField, {
    computeVia: function (this: YearClose) {
      let types = new Map(
        (this.accounts ?? [])
          .filter(Boolean)
          .map((a) => [a!.code ?? '', a!.type ?? '']),
      );
      let n = 0;
      for (let [account, net] of netOf(this.closes))
        if (ACCOUNT_TYPES[types.get(account) ?? '']?.cashFlow === 'income')
          n -= net;
      return n;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: YearClose) {
      return `Year-end close · ${this.year ?? ''}`;
    },
  });
  /** Sign off the year. The months must already be closed; this records who signed off. */
  @operation static signOff = {
    base: 'transform',
    transformations: bxl`
      assert(.status == "open"; "This year is already signed off.");
      .status = "signed off";
      .signedOffBy = actor();
    `,
  } satisfies OperationDeclaration;
  static isolated = class extends Component<typeof YearClose> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        {
          key: 'Months closed',
          value: `${m.monthsClosed ?? 0} of 12`,
          strong: true,
        },
        {
          key: 'Net income for the year',
          value: money(m.netIncomeMinor),
          strong: true,
        },
        { key: 'Signed off by', value: m.signedOffBy ?? 'Not yet' },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Year-end close'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.netIncomeMinor}}
        @figureLabel='Net income'
        @status={{if @model.signedOffBy 'Signed off' 'Open'}}
        @note='Next year this income rolls into retained earnings on the balance sheet.'
      ><Part @title='Year'><div
            data-row
            data-key={{@model.year}}
            data-total={{@model.netIncomeMinor}}
            data-qty={{@model.monthsClosed}}
          ><Facts @items={{this.facts}} /></div></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof YearClose> {
    <template>
      <Strip
        @eyebrow='Year-end close'
        @title={{@model.cardTitle}}
        @figure={{money @model.netIncomeMinor}}
        @meta='Net income'
      />
    </template>
  };
  static fitted = class extends Component<typeof YearClose> {
    get yearLabel() {
      return this.args.model.year == null ? '' : String(this.args.model.year);
    }
    <template>
      <Fit
        @eyebrow='Year close'
        @title={{this.yearLabel}}
        @figure={{money @model.netIncomeMinor}}
        @meta='Net income'
      />
    </template>
  };
}
