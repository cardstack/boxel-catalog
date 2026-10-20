// Two of the workbooks books usually get exported for, kept as cards over the posted ledger:
//
//   Budget against actuals. A Budget holds each account's annual amount and how it spreads over the
//   year (=ROUND(annual × weight ÷ SUM(weights), 0), with December taking the rounding). The variance
//   report reads the closed months and sums the year to date with =SUMIF(month, "<=" & k, amounts).
//
//   Product and customer margin. Revenue comes from the posted invoices' and sales receipts' lines;
//   cost of goods from the fulfillments' FIFO draws on stock lots. Each group is =SUMIF(key, group,
//   values), and customers are ranked with =RANK.EQ and =PERCENTRANK.INC (RANK_EQ and PERCENTRANK_INC in BXL). The report
//   reconciles both totals to the profit and loss for the same months.
//
// The formulas run in BXL, the workspace's Excel-compatible formula engine.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { evaluateBxl } from '@cardstack/bxl';
import { LedgerAccount, Item } from './ledger-cards';
import { MonthClose } from './ledger-close';
import { Invoice, Customer } from './ledger-sales';
import { JournalMonth, journalPostings } from './ledger-journal';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  toneFor,
  percent,
  type Fact,
} from './record-kit';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';
import { IsoMonthField } from './ledger-dates';
import { settingsLink, settingsOf, fiscalYearStartOf } from './ledger-settings';

const SECTION: Record<string, string> = {
  income: 'income',
  cogs: 'cogs',
  expense: 'expense',
  other: 'expense',
};
const TITLE: Record<string, string> = {
  income: 'Income',
  cogs: 'Cost of goods sold',
  expense: 'Expenses',
};
const monthEnd = (ym: string) => {
  let [y, m] = ym.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
};
const sum = (xs: (number | undefined)[]) =>
  xs.reduce<number>((n, x) => n + (x ?? 0), 0);
const bxl = (src: string, input: unknown) => {
  try {
    return evaluateBxl(src, input).value as any;
  } catch {
    return undefined;
  }
};
const MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

// The Excel formulas, as BXL runs them.
export const FORMULAS = {
  spread: '. as $R | [$R.w[] | ROUND($R.annual * . / SUM($R.w), 0)]',
  ytd: '{ budget: SUMIF(.m, CONCAT("<=", .k), .b), actual: SUMIF(.m, CONCAT("<=", .k), .a) }',
  group:
    '. as $R | [$R.groups[] | { key: ., revenue: SUMIF($R.key, ., $R.rev), cost: SUMIF($R.key, ., $R.cost), qty: SUMIF($R.key, ., $R.qty) }]',
  rank: '. as $R | [$R.ys[] | RANK_EQ(., $R.ys)]',
  percentile: '. as $R | [$R.ys[] | PERCENTRANK_INC($R.ys, .)]',
};

// ── budget ──────────────────────────────────────────────────────────────────
export class BudgetLine extends FieldDef {
  static displayName = 'Budget line';
  @field account = contains(StringField);
  @field annualMinor = contains(NumberField);
  @field spread = contains(StringField); // 'seasonal' (the budget's weights) or 'even'
}
export class BudgetSpread extends FieldDef {
  @field account = contains(StringField);
  @field annualMinor = contains(NumberField);
  @field amounts = containsMany(NumberField); // twelve months, cents
}

/** Each account's annual amount, spread over the months with Excel's ROUND; December takes the rounding. */
export function spreadOf(annual: number, weights: number[]): number[] {
  let w =
    weights.length === 12 && weights.some((x) => x)
      ? weights
      : Array(12).fill(1);
  let out = (
    (bxl(FORMULAS.spread, { w, annual }) as number[]) ?? Array(12).fill(0)
  ).map((x) => Number(x) || 0);
  out[11] = annual - sum(out.slice(0, 11));
  return out;
}

export class Budget extends CardDef {
  static displayName = 'Budget';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field year = contains(StringField);
  @field name = contains(StringField);
  @field seasonality = containsMany(NumberField); // twelve weights for 'seasonal' lines
  @field lines = containsMany(BudgetLine);
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 100 } },
  });
  @field spreads = containsMany(BudgetSpread, {
    computeVia: function (this: Budget) {
      let w = (this.seasonality ?? []).map((x) => Number(x) || 0);
      return (this.lines ?? []).filter(Boolean).map(
        (l) =>
          new BudgetSpread({
            account: l!.account,
            annualMinor: l!.annualMinor ?? 0,
            amounts: spreadOf(
              l!.annualMinor ?? 0,
              l!.spread === 'even' ? [] : w,
            ),
          }),
      );
    },
  });
  @field netIncomeMinor = contains(NumberField, {
    computeVia: function (this: Budget) {
      let types = new Map(
        (this.accounts ?? [])
          .filter(Boolean)
          .map((a) => [a!.code ?? '', SECTION[a!.type ?? ''] ?? '']),
      );
      return sum(
        (this.lines ?? [])
          .filter(Boolean)
          .map(
            (l) =>
              (types.get(l!.account ?? '') === 'income' ? 1 : -1) *
              (l!.annualMinor ?? 0),
          ),
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Budget) {
      return this.name || `Budget ${this.year ?? ''}`;
    },
  });

  static isolated = class extends Component<typeof Budget> {
    get cols(): Col[] {
      return [
        { key: 'code', label: 'No.', kind: 'code', width: '4rem' },
        { key: 'name', label: 'Account' },
        ...MONTHS.map((m, i) => ({
          key: `m${i}`,
          label: m,
          kind: 'amount' as const,
          whole: true,
          priority: 'secondary' as const,
        })),
        { key: 'year', label: 'Year', kind: 'amount' },
      ];
    }
    get rows(): Line[] {
      let m = this.args.model,
        names = new Map(
          (m.accounts ?? []).filter(Boolean).map((a) => [a!.code ?? '', a!]),
        ),
        spreads = (m.spreads ?? []).filter(Boolean) as BudgetSpread[];
      let cellsOf = (amounts: number[], year: number) =>
        Object.fromEntries([
          ...amounts.map((x, i) => [`m${i}`, x]),
          ['year', year],
        ]);
      let net = Array(12).fill(0),
        netYear = 0,
        out: Line[] = [];
      for (let key of ['income', 'cogs', 'expense']) {
        let rows = spreads
          .filter(
            (sp) => SECTION[names.get(sp.account ?? '')?.type ?? ''] === key,
          )
          .sort((a, b) => (a.account ?? '').localeCompare(b.account ?? ''));
        let tot = Array(12).fill(0),
          totYear = sum(rows.map((sp) => sp.annualMinor)),
          sign = key === 'income' ? 1 : -1;
        out.push({
          key: `h-${key}`,
          role: 'heading',
          cells: { code: TITLE[key] },
        });
        for (let sp of rows) {
          let amounts = (sp.amounts ?? []).map((x) => Number(x) || 0);
          amounts.forEach((x, i) => (tot[i] += x));
          out.push({
            key: sp.account ?? '',
            depth: 1,
            cells: {
              code: sp.account,
              name: names.get(sp.account ?? '')?.name ?? '',
              ...cellsOf(amounts, sp.annualMinor ?? 0),
            },
          });
        }
        tot.forEach((x, i) => (net[i] += sign * x));
        netYear += sign * totYear;
        out.push({
          key: `t-${key}`,
          role: 'subtotal',
          cells: {
            code: '',
            name: `Total ${TITLE[key]}`,
            ...cellsOf(tot, totYear),
          },
        });
      }
      out.push({
        key: 'net',
        role: 'total',
        cells: { code: '', name: 'Net income', ...cellsOf(net, netYear) },
      });
      return out;
    }
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Year', value: m.year ?? '' },
        {
          key: 'Spread, per month',
          value:
            '=ROUND(annual × weight ÷ SUM(weights), 0); December takes the rounding',
        },
        ...((m.seasonality ?? []).length
          ? [
              {
                key: 'Seasonal weights',
                value: (m.seasonality ?? []).join(' · '),
              },
            ]
          : []),
        {
          key: 'Net income, budget',
          value: money(m.netIncomeMinor),
          strong: true,
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Budget'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.netIncomeMinor}}
        @figureLabel='Net income, budgeted'
        @note='Each account’s annual amount, spread across the year: evenly, or by the seasonal weights where a line asks for them.'
      >
        <Part @title='Summary'><Facts @items={{this.facts}} /></Part>
        <Part @title='By month'><StatementTable
            @label='Budget by account and month'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @density='compact'
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof Budget> {
    <template>
      <Strip
        @eyebrow='Budget'
        @title={{@model.cardTitle}}
        @figure={{money @model.netIncomeMinor}}
        @meta='Net income, budgeted'
      />
    </template>
  };
  static fitted = class extends Component<typeof Budget> {
    <template>
      <Fit
        @eyebrow='Budget'
        @title={{@model.year}}
        @figure={{money @model.netIncomeMinor}}
        @meta='Net income'
      />
    </template>
  };
}

// ── budget against actuals ──────────────────────────────────────────────────
export class VarianceRow extends FieldDef {
  @field section = contains(StringField);
  @field account = contains(StringField);
  @field name = contains(StringField);
  @field budgetMonthMinor = contains(NumberField);
  @field actualMonthMinor = contains(NumberField);
  @field budgetYtdMinor = contains(NumberField);
  @field actualYtdMinor = contains(NumberField);
  @field varianceMinor = contains(NumberField); // year to date; positive is favourable
  @field varianceBp = contains(NumberField); // variance ÷ budget, basis points
  @field budgetYearMinor = contains(NumberField);
  @field flag = contains(StringField); // 'unfavourable', 'favourable' or ''
}

export class BudgetVsActual extends CardDef {
  static displayName = 'Budget against actuals';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field asOfMonth = contains(IsoMonthField); // the last closed month compared, e.g. 2026-09
  @field thresholdPct = contains(NumberField); // flag a variance beyond this share of budget…
  @field thresholdMinor = contains(NumberField); // …and beyond this amount
  @field budget = linksTo(() => Budget);
  @field settings = settingsLink();
  @field fromMonth = contains(StringField, {
    computeVia: function (this: BudgetVsActual) {
      return this.asOfMonth
        ? fiscalYearStartOf(this.asOfMonth, settingsOf(this).fiscalYearStart)
        : '';
    },
  });
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: {
        range: { month: { gte: '$this.fromMonth', lte: '$this.asOfMonth' } },
      },
      page: { size: 24 },
    },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 100 } },
  });
  @field rows = containsMany(VarianceRow, {
    computeVia: function (this: BudgetVsActual) {
      let k = Number((this.asOfMonth ?? '').slice(5, 7)) || 0,
        pct = this.thresholdPct ?? 10,
        floor = this.thresholdMinor ?? 0;
      let types = new Map(
        (this.accounts ?? [])
          .filter(Boolean)
          .map((a) => [
            a!.code ?? '',
            { section: SECTION[a!.type ?? ''] ?? '', name: a!.name ?? '' },
          ]),
      );
      let actual = new Map<string, number[]>();
      for (let c of (this.closes ?? []).filter(Boolean)) {
        let mo = Number((c!.month ?? '').slice(5, 7));
        if (!mo) continue;
        for (let t of c!.totals ?? []) {
          let a = types.get(t?.account ?? '');
          if (!a?.section) continue;
          let s = actual.get(t!.account!) ?? Array(12).fill(0),
            v = (t!.debitMinor ?? 0) - (t!.creditMinor ?? 0);
          s[mo - 1] += a.section === 'income' ? -v : v;
          actual.set(t!.account!, s);
        }
      }
      let budget = new Map(
        ((this.budget?.spreads ?? []).filter(Boolean) as BudgetSpread[]).map(
          (s) => [
            s.account ?? '',
            (s.amounts ?? []).map((x) => Number(x) || 0),
          ],
        ),
      );
      let months = [...Array(12).keys()].map((i) => i + 1),
        out: VarianceRow[] = [];
      for (let account of new Set([...budget.keys(), ...actual.keys()])) {
        let t = types.get(account);
        if (!t?.section) continue;
        let b = budget.get(account) ?? Array(12).fill(0),
          a = actual.get(account) ?? Array(12).fill(0);
        let ytd = bxl(FORMULAS.ytd, { m: months, k, b, a }) ?? {
          budget: 0,
          actual: 0,
        };
        let bY = Number(ytd.budget) || 0,
          aY = Number(ytd.actual) || 0,
          v = t.section === 'income' ? aY - bY : bY - aY;
        let bp = bY ? Math.round((10000 * v) / Math.abs(bY)) : undefined;
        let flag =
          Math.abs(v) > floor && (bp == null || Math.abs(bp) > pct * 100)
            ? v < 0
              ? 'unfavourable'
              : 'favourable'
            : '';
        out.push(
          new VarianceRow({
            section: t.section,
            account,
            name: t.name,
            budgetMonthMinor: b[k - 1] ?? 0,
            actualMonthMinor: a[k - 1] ?? 0,
            budgetYtdMinor: bY,
            actualYtdMinor: aY,
            varianceMinor: v,
            varianceBp: bp,
            budgetYearMinor: sum(b),
            flag,
          }),
        );
      }
      return out.sort((x, y) =>
        (x.account ?? '').localeCompare(y.account ?? ''),
      );
    },
  });
  @field netBudgetYtdMinor = contains(NumberField, {
    computeVia: function (this: BudgetVsActual) {
      return net(this.rows, 'budgetYtdMinor');
    },
  });
  @field netActualYtdMinor = contains(NumberField, {
    computeVia: function (this: BudgetVsActual) {
      return net(this.rows, 'actualYtdMinor');
    },
  });
  @field flaggedCount = contains(NumberField, {
    computeVia: function (this: BudgetVsActual) {
      return (this.rows ?? []).filter((r) => r?.flag === 'unfavourable').length;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BudgetVsActual) {
      return `Budget against actuals · ${this.asOfMonth ?? ''}`;
    },
  });

  static isolated = class extends Component<typeof BudgetVsActual> {
    get facts(): Fact[] {
      let m = this.args.model,
        v = (m.netActualYtdMinor ?? 0) - (m.netBudgetYtdMinor ?? 0);
      return [
        { key: 'Budget', value: m.budget?.cardTitle ?? '' },
        {
          key: 'Year to date',
          value: `${m.fromMonth ?? ''} to ${m.asOfMonth ?? ''}`,
        },
        {
          key: 'Year to date, per account',
          value:
            '=SUMIF(months, "<=" & k, amounts), for the budget and the closed months',
        },
        {
          key: 'Flagged',
          value: `a variance beyond ${m.thresholdPct ?? 10}% of budget and ${money(m.thresholdMinor ?? 0)}`,
        },
        {
          key: 'Net income, budget to date',
          value: money(m.netBudgetYtdMinor),
        },
        {
          key: 'Net income, actual to date',
          value: money(m.netActualYtdMinor),
          strong: true,
        },
        {
          key: 'Variance',
          value: `${signed(v)} ${v >= 0 ? 'favourable' : 'unfavourable'}`,
        },
        { key: 'Accounts over budget', value: String(m.flaggedCount ?? 0) },
      ];
    }
    cols: Col[] = [
      { key: 'code', label: 'No.', kind: 'code', width: '4rem' },
      { key: 'name', label: 'Account' },
      { key: 'flag', label: 'Flag', kind: 'custom' },
      {
        key: 'bm',
        label: 'Month budget',
        kind: 'amount',
        priority: 'secondary',
      },
      {
        key: 'am',
        label: 'Month actual',
        kind: 'amount',
        priority: 'secondary',
      },
      { key: 'by', label: 'YTD budget', kind: 'amount' },
      { key: 'ay', label: 'YTD actual', kind: 'amount' },
      { key: 'v', label: 'Variance', kind: 'amount', sign: 'change' },
      { key: 'p', label: '%', kind: 'percent', scale: 4 },
      {
        key: 'yr',
        label: 'Year budget',
        kind: 'amount',
        priority: 'secondary',
      },
    ];
    get rows(): Line[] {
      let m = this.args.model,
        rows = (m.rows ?? []).filter(Boolean) as VarianceRow[],
        out: Line[] = [];
      for (let key of ['income', 'cogs', 'expense']) {
        let list = rows.filter((r) => r.section === key),
          tot = (f: keyof VarianceRow) => sum(list.map((r) => r[f] as number));
        out.push({
          key: `h-${key}`,
          role: 'heading',
          cells: { code: TITLE[key] },
        });
        out.push(
          ...list.map((r) => ({
            key: r.account ?? '',
            depth: 1,
            cells: {
              code: r.account,
              name: r.name,
              flag: r.flag,
              bm: r.budgetMonthMinor,
              am: r.actualMonthMinor,
              by: r.budgetYtdMinor,
              ay: r.actualYtdMinor,
              v: r.varianceMinor,
              p: r.varianceBp,
              yr: r.budgetYearMinor,
            },
            data: {
              row: true,
              key: r.account,
              dr: r.budgetYtdMinor ?? 0,
              cr: r.actualYtdMinor ?? 0,
            },
          })),
        );
        out.push({
          key: `t-${key}`,
          role: 'subtotal',
          cells: {
            code: '',
            name: `Total ${TITLE[key]}`,
            bm: tot('budgetMonthMinor'),
            am: tot('actualMonthMinor'),
            by: tot('budgetYtdMinor'),
            ay: tot('actualYtdMinor'),
            v: tot('varianceMinor'),
            yr: tot('budgetYearMinor'),
          },
        });
      }
      out.push({
        key: 'net',
        role: 'total',
        cells: {
          code: '',
          name: 'Net income',
          by: m.netBudgetYtdMinor,
          ay: m.netActualYtdMinor,
          v: (m.netActualYtdMinor ?? 0) - (m.netBudgetYtdMinor ?? 0),
        },
      });
      return out;
    }
    flag = (v: unknown) => String(v ?? '');
    <template>
      <Sheet
        @eyebrow='Budget against actuals'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.netActualYtdMinor}}
        @figureLabel='Net income, year to date'
        @note='The closed months against the budget, account by account. A positive variance is favourable: income above budget, or costs below it.'
      >
        <Part @title='Summary'><Facts @items={{this.facts}} /></Part>
        <Part @title='By account'>
          <StatementTable
            @label='Budget against actuals by account'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @zero='show'
          >
            <:cell as |value|>{{#if value}}<StatusChip
                  @value={{this.flag value}}
                  @tone={{toneFor (this.flag value)}}
                />{{/if}}</:cell>
          </StatementTable>
        </Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof BudgetVsActual> {
    <template>
      <Strip
        @eyebrow='Budget against actuals'
        @title={{@model.cardTitle}}
        @figure={{money @model.netActualYtdMinor}}
        @meta='Net income, year to date'
      />
    </template>
  };
  static fitted = class extends Component<typeof BudgetVsActual> {
    <template>
      <Fit
        @eyebrow='Budget'
        @title={{@model.asOfMonth}}
        @figure={{money @model.netActualYtdMinor}}
        @meta='Net income to date'
      />
    </template>
  };
}

function net(
  rows: (VarianceRow | undefined)[] | undefined,
  f: 'budgetYtdMinor' | 'actualYtdMinor',
) {
  return (rows ?? [])
    .filter(Boolean)
    .reduce(
      (n, r) =>
        n + (r!.section === 'income' ? 1 : -1) * ((r![f] as number) ?? 0),
      0,
    );
}

// ── product and customer margin ─────────────────────────────────────────────
export class MarginRow extends FieldDef {
  @field key = contains(StringField);
  @field name = contains(StringField);
  @field channel = contains(StringField);
  @field qty = contains(NumberField); // thousandths of a unit
  @field revenueMinor = contains(NumberField);
  @field costMinor = contains(NumberField);
  @field marginMinor = contains(NumberField);
  @field marginBp = contains(NumberField); // margin ÷ revenue, basis points
  @field rank = contains(NumberField); // RANK.EQ of margin % among customers: 1 = the highest
  @field rankPct = contains(NumberField); // PERCENTRANK.INC of margin % among customers, 0–100
}

const GROUP_NAMES: Record<string, string> = {
  '(credits)': 'Credits and allowances',
  '(no product)': 'Lines with no product',
};
const signed = (m: number | undefined) =>
  m ? `${m > 0 ? '+' : '−'}${money(Math.abs(m))}` : money(0);
const posted = (from: string, to: string) => ({
  filter: {
    every: [
      { eq: { status: 'posted' } },
      { range: { date: { gte: from, lte: to } } },
    ],
  },
  page: { size: 1000 },
});

export class MarginReport extends CardDef {
  static displayName = 'Product and customer margin';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field fromMonth = contains(IsoMonthField);
  @field toMonth = contains(IsoMonthField);
  @field fromDate = contains(StringField, {
    computeVia: function (this: MarginReport) {
      return this.fromMonth ? `${this.fromMonth}-01` : '';
    },
  });
  @field toDate = contains(StringField, {
    computeVia: function (this: MarginReport) {
      return this.toMonth ? monthEnd(this.toMonth) : '';
    },
  });
  @field invoices = linksToMany(() => Invoice, {
    query: posted('$this.fromDate', '$this.toDate'),
  });
  @field journal = linksToMany(() => JournalMonth, {
    query: {
      filter: {
        range: { month: { gte: '$this.fromMonth', lte: '$this.toMonth' } },
      },
      page: { size: 24 },
    },
  });
  @field customers = linksToMany(() => Customer, {
    query: { page: { size: 200 } },
  });
  @field items = linksToMany(() => Item, {
    query: { page: { size: 200 } },
  });
  @field accounts = linksToMany(() => LedgerAccount, {
    query: { page: { size: 100 } },
  });
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: {
        range: { month: { gte: '$this.fromMonth', lte: '$this.toMonth' } },
      },
      page: { size: 24 },
    },
  });

  // One flat table of facts, the way the workbook would hold them: a row per sale line (revenue), per
  // credit memo (negative revenue) and per fulfillment draw (cost), each tagged with its product,
  // customer and channel. Every group below is SUMIF over this table.
  get factTable() {
    let types = new Map(
      (this.accounts ?? [])
        .filter(Boolean)
        .map((a) => [a!.code ?? '', a!.type ?? '']),
    );
    let channel = new Map(
      (this.customers ?? [])
        .filter(Boolean)
        .map((c) => [c!.customerId ?? '', c!.channel ?? '']),
    );
    let rows: {
      sku: string;
      cust: string;
      chan: string;
      rev: number;
      cost: number;
      qty: number;
    }[] = [];
    let sale = (
      sku: string | undefined,
      cust: string,
      account: string | undefined,
      amount: number | undefined,
      qty: number | undefined,
    ) => {
      if (types.get(account ?? '') !== 'income') return;
      rows.push({
        sku: sku || '(no product)',
        cust,
        chan: channel.get(cust) ?? '',
        rev: amount ?? 0,
        cost: 0,
        qty: sku ? (qty ?? 0) : 0,
      });
    };
    // Invoices stay cards; sales receipts, credit memos and fulfillments are journal postings.
    for (let d of (this.invoices ?? []).filter(Boolean) as Invoice[]) {
      if (d.kind === 'opening') continue;
      for (let l of (d.lines ?? []).filter(Boolean))
        sale(l!.sku, d.customerId ?? '', l!.account, l!.amountMinor, l!.qty);
    }
    for (let r of journalPostings(this.journal, ['sales-receipt']))
      for (let i of r.items)
        sale(
          i.sku,
          r.fact('customerId') || r.party,
          i.account,
          i.amountMinor,
          i.qty,
        );
    for (let c of journalPostings(this.journal, ['credit-memo'])) {
      if (types.get(c.fact('account')) !== 'income') continue;
      let cust = c.fact('customerId') || c.party;
      rows.push({
        sku: '(credits)',
        cust,
        chan: channel.get(cust) ?? '',
        rev: -c.num('amountMinor'),
        cost: 0,
        qty: 0,
      });
    }
    for (let f of journalPostings(this.journal, ['fulfillment'])) {
      let cust = f.fact('customerId') || f.party;
      for (let d of f.items)
        rows.push({
          sku: d.sku ?? '',
          cust,
          chan: channel.get(cust) ?? '',
          rev: 0,
          cost: d.amountMinor ?? 0,
          qty: 0,
        });
    }
    return rows;
  }
  groupBy(
    key: 'sku' | 'cust' | 'chan',
    names: Map<string, string>,
    channels?: Map<string, string>,
  ) {
    let facts = this.factTable,
      groups = [...new Set(facts.map((r) => r[key]))].filter((g) => g !== '');
    let table = {
      groups,
      key: facts.map((r) => r[key]),
      rev: facts.map((r) => r.rev),
      cost: facts.map((r) => r.cost),
      qty: facts.map((r) => r.qty),
    };
    let sums =
      (bxl(FORMULAS.group, table) as {
        key: string;
        revenue: number;
        cost: number;
        qty: number;
      }[]) ?? [];
    let rows = sums.map((g) => {
      let rev = Number(g.revenue) || 0,
        cost = Number(g.cost) || 0;
      return new MarginRow({
        key: g.key,
        name: names.get(g.key) ?? GROUP_NAMES[g.key] ?? g.key,
        channel: channels?.get(g.key) ?? '',
        qty: Number(g.qty) || 0,
        revenueMinor: rev,
        costMinor: cost,
        marginMinor: rev - cost,
        marginBp:
          rev > 0 ? Math.round((10000 * (rev - cost)) / rev) : undefined,
      });
    });
    return rows.sort((a, b) => (b.marginMinor ?? 0) - (a.marginMinor ?? 0));
  }

  @field products = containsMany(MarginRow, {
    computeVia: function (this: MarginReport) {
      return this.groupBy(
        'sku',
        new Map(
          (this.items ?? [])
            .filter(Boolean)
            .map((i) => [i!.sku ?? '', i!.productName ?? '']),
        ),
      );
    },
  });
  @field customerRows = containsMany(MarginRow, {
    computeVia: function (this: MarginReport) {
      let cs = (this.customers ?? []).filter(Boolean);
      let rows = this.groupBy(
        'cust',
        new Map(cs.map((c) => [c!.customerId ?? '', c!.name ?? ''])),
        new Map(cs.map((c) => [c!.customerId ?? '', c!.channel ?? ''])),
      );
      let ranked = rows.filter((r) => r.marginBp != null),
        ys = ranked.map((r) => r.marginBp);
      let ranks = (bxl(FORMULAS.rank, { ys }) as number[]) ?? [],
        pcts = (bxl(FORMULAS.percentile, { ys }) as number[]) ?? [];
      ranked.forEach((r, i) => {
        let rank = Number(ranks[i]);
        if (rank) r.rank = rank;
        r.rankPct = Math.round((Number(pcts[i]) || 0) * 100);
      });
      return rows.sort((a, b) => (a.rank ?? 999) - (b.rank ?? 999));
    },
  });
  @field channels = containsMany(MarginRow, {
    computeVia: function (this: MarginReport) {
      return this.groupBy(
        'chan',
        new Map([
          ['wholesale', 'Wholesale'],
          ['retail', 'Retail and cafe'],
          ['dtc', 'Online, direct to consumer'],
        ]),
      );
    },
  });
  @field revenueMinor = contains(NumberField, {
    computeVia: function (this: MarginReport) {
      return sum((this.channels ?? []).map((r) => r?.revenueMinor));
    },
  });
  @field costMinor = contains(NumberField, {
    computeVia: function (this: MarginReport) {
      return sum((this.channels ?? []).map((r) => r?.costMinor));
    },
  });
  @field marginMinor = contains(NumberField, {
    computeVia: function (this: MarginReport) {
      return (this.revenueMinor ?? 0) - (this.costMinor ?? 0);
    },
  });
  // The same months on the profit and loss, so the report reconciles to the books.
  @field plIncomeMinor = contains(NumberField, {
    computeVia: function (this: MarginReport) {
      return plTotal(this, 'income');
    },
  });
  @field plCogsMinor = contains(NumberField, {
    computeVia: function (this: MarginReport) {
      return plTotal(this, 'cogs');
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: MarginReport) {
      return `Product and customer margin · ${this.fromMonth ?? ''}${this.toMonth && this.toMonth !== this.fromMonth ? ' to ' + this.toMonth : ''}`;
    },
  });

  static isolated = class extends Component<typeof MarginReport> {
    get facts(): Fact[] {
      let m = this.args.model,
        rev = m.revenueMinor ?? 0;
      return [
        { key: 'Revenue from sales documents', value: money(rev) },
        {
          key: 'Cost of goods from fulfillments (FIFO lot cost)',
          value: money(m.costMinor),
        },
        {
          key: 'Gross margin',
          value: `${money(m.marginMinor)} · ${percent(rev ? (m.marginMinor ?? 0) / rev : 0)}`,
          strong: true,
        },
        {
          key: 'Each group',
          value:
            '=SUMIF(Product, this product, Revenue), and the same for Cost; likewise by Customer and Channel',
        },
        {
          key: 'Customer rank',
          value: '=RANK.EQ(this margin %, Margin %): 1 is the highest margin',
        },
        {
          key: 'Percentile',
          value:
            '=PERCENTRANK.INC(Margin %, this margin %): 100 is the highest, 0 the lowest',
        },
      ];
    }
    get recon() {
      let m = this.args.model,
        otherIncome = (m.plIncomeMinor ?? 0) - (m.revenueMinor ?? 0),
        otherCost = (m.plCogsMinor ?? 0) - (m.costMinor ?? 0);
      return [
        {
          k: 'Income on the profit and loss',
          v: money(m.plIncomeMinor),
          raw: m.plIncomeMinor ?? 0,
        },
        {
          k: 'less revenue from sales documents',
          v: money(m.revenueMinor),
          raw: m.revenueMinor ?? 0,
        },
        {
          k: 'Income not from a sale (recognized from schedules)',
          v: money(otherIncome),
          raw: otherIncome,
          strong: true,
        },
        {
          k: 'Cost of goods sold on the profit and loss',
          v: money(m.plCogsMinor),
          raw: m.plCogsMinor ?? 0,
        },
        {
          k: 'less cost of goods from fulfillments',
          v: money(m.costMinor),
          raw: m.costMinor ?? 0,
        },
        {
          k: 'Cost not tied to a sale (counts, shrinkage, adjustments)',
          v: money(otherCost),
          raw: otherCost,
          strong: true,
        },
      ];
    }
    productCols: Col[] = [
      { key: 'name', label: 'Product' },
      { key: 'sku', label: 'SKU', kind: 'code', priority: 'secondary' },
      { key: 'units', label: 'Units', kind: 'quantity', scale: 3, digits: 0 },
      {
        key: 'price',
        label: 'Avg price',
        kind: 'amount',
        priority: 'secondary',
      },
      { key: 'rev', label: 'Revenue', kind: 'amount' },
      { key: 'cost', label: 'Cost', kind: 'amount' },
      { key: 'margin', label: 'Margin', kind: 'amount' },
      { key: 'pct', label: 'Margin %', kind: 'percent', scale: 4 },
    ];
    customerCols: Col[] = [
      { key: 'rank', label: 'Rank', kind: 'number', width: '4rem' },
      { key: 'name', label: 'Customer' },
      { key: 'channel', label: 'Channel', priority: 'secondary' },
      { key: 'pct', label: 'Margin %', kind: 'percent', scale: 4 },
      {
        key: 'pctile',
        label: 'Percentile',
        kind: 'number',
        priority: 'secondary',
      },
      { key: 'rev', label: 'Revenue', kind: 'amount' },
      { key: 'cost', label: 'Cost', kind: 'amount', priority: 'secondary' },
      { key: 'margin', label: 'Margin', kind: 'amount' },
    ];
    channelCols: Col[] = [
      { key: 'name', label: 'Channel' },
      { key: 'rev', label: 'Revenue', kind: 'amount' },
      { key: 'cost', label: 'Cost', kind: 'amount' },
      { key: 'margin', label: 'Margin', kind: 'amount' },
      { key: 'pct', label: 'Margin %', kind: 'percent', scale: 4 },
    ];
    reconCols: Col[] = [
      { key: 'name', label: 'Line' },
      { key: 'amount', label: 'Amount', kind: 'amount' },
    ];
    // Every group: its rows (carrying the verification hooks) and a total from the report itself.
    lines = (
      rows: (MarginRow | undefined)[] | undefined,
      group: string,
      label: string,
    ): Line[] => {
      let m = this.args.model,
        list = (rows ?? []).filter(Boolean) as MarginRow[];
      return [
        ...list.map((r) => ({
          key: r.key ?? '',
          cells: {
            name: r.name,
            sku: r.key,
            units: r.qty || undefined,
            price: r.qty
              ? Math.round(((r.revenueMinor ?? 0) * 1000) / r.qty)
              : undefined,
            rev: r.revenueMinor,
            cost: r.costMinor,
            margin: r.marginMinor,
            pct: r.marginBp,
            rank: r.rank,
            channel: r.channel,
            pctile: r.rankPct,
          },
          data: {
            row: true,
            group,
            key: r.key,
            dr: r.revenueMinor ?? 0,
            cr: r.costMinor ?? 0,
          },
        })),
        {
          key: 'total',
          role: 'total',
          cells: {
            name: label,
            rev: m.revenueMinor,
            cost: m.costMinor,
            margin: m.marginMinor,
            pct: m.revenueMinor
              ? Math.round((10000 * (m.marginMinor ?? 0)) / m.revenueMinor)
              : undefined,
          },
        },
      ];
    };
    get products() {
      return this.lines(this.args.model.products, 'sku', 'All products');
    }
    get customers() {
      return this.lines(this.args.model.customerRows, 'cust', 'All customers');
    }
    get channels() {
      return this.lines(this.args.model.channels, 'chan', 'All channels');
    }
    get reconRows(): Line[] {
      return this.recon.map((r) => ({
        key: r.k,
        role: r.strong ? ('subtotal' as const) : ('line' as const),
        cells: { name: r.k, amount: r.raw },
        data: { recon: r.k, total: r.raw },
      }));
    }
    <template>
      <Sheet
        @eyebrow='Margin'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.marginMinor}}
        @figureLabel='Gross margin from sales'
        @note='Revenue from each posted invoice and sales receipt line; cost from the fulfillment that shipped it, at the FIFO cost of the lots it drew. Grouped with SUMIF, ranked with RANK.EQ and PERCENTRANK.INC.'
      >
        <Part @title='Summary'><Facts @items={{this.facts}} /></Part>
        <Part @title='By product'><StatementTable
            @label='Margin by product'
            @columns={{this.productCols}}
            @rows={{this.products}}
          /></Part>
        <Part @title='By customer, ranked by margin %'><StatementTable
            @label='Margin by customer'
            @columns={{this.customerCols}}
            @rows={{this.customers}}
          /></Part>
        <Part @title='By channel'><StatementTable
            @label='Margin by channel'
            @columns={{this.channelCols}}
            @rows={{this.channels}}
          /></Part>
        <Part @title='Reconciled to the books'><StatementTable
            @label='Reconciliation to the profit and loss'
            @columns={{this.reconCols}}
            @rows={{this.reconRows}}
            @zero='show'
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof MarginReport> {
    <template>
      <Strip
        @eyebrow='Margin'
        @title={{@model.cardTitle}}
        @figure={{money @model.marginMinor}}
        @meta='Gross margin from sales'
      />
    </template>
  };
  static fitted = class extends Component<typeof MarginReport> {
    <template>
      <Fit
        @eyebrow='Margin'
        @title={{@model.toMonth}}
        @figure={{money @model.marginMinor}}
        @meta='Gross margin'
      />
    </template>
  };
}

function plTotal(r: MarginReport, section: 'income' | 'cogs') {
  let types = new Map(
    (r.accounts ?? [])
      .filter(Boolean)
      .map((a) => [a!.code ?? '', SECTION[a!.type ?? ''] ?? '']),
  );
  let n = 0;
  for (let c of (r.closes ?? []).filter(Boolean))
    for (let t of c!.totals ?? [])
      if (types.get(t?.account ?? '') === section)
        n += (t!.debitMinor ?? 0) - (t!.creditMinor ?? 0);
  return section === 'income' ? -n : n;
}
