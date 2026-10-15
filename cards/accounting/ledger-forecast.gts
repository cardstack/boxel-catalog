// A profit and loss forecast taken part-way through the year, with Excel's own functions.
// For each income, cost and expense account, the closed months so far are the known values; the
// rest of the year is projected with FORECAST(month, actuals, months) (a least-squares line, the
// same as Excel's FORECAST / FORECAST.LINEAR), or with AVERAGE(actuals) as a run rate. The formulas
// run in BXL, the workspace's Excel-compatible formula engine. When later months are closed too,
// the card puts the forecast beside what actually happened.
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
import BookIcon from '@cardstack/boxel-icons/book-open';
import { evaluateBxl } from '@cardstack/bxl';
import { LedgerAccount } from './ledger-cards';
import { MonthClose } from './ledger-close';
import { Sheet, Part, Facts, Strip, Fit, money, type Fact } from './record-kit';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';

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
// The two methods, as the Excel formulas they are. `$R.ys` are the actual months, `$R.xs` their month numbers.
const FORMULA: Record<string, string> = {
  FORECAST: '. as $R | [range($R.from; 13) | FORECAST(.; $R.ys; $R.xs)]',
  AVERAGE: '. as $R | [range($R.from; 13) | AVERAGE($R.ys)]',
};

export class ForecastRow extends FieldDef {
  @field section = contains(StringField);
  @field account = contains(StringField);
  @field name = contains(StringField);
  @field actualMinor = contains(NumberField); // year to date, closed months
  @field forecastMinor = contains(NumberField); // the rest of the year, projected
  @field fullYearMinor = contains(NumberField); // actual + forecast
  @field trendMinor = contains(NumberField); // SLOPE: change per month
  @field outcomeMinor = contains(NumberField); // the whole year as it closed, when it has
}

export class PnlForecast extends CardDef {
  static displayName = 'Profit and loss forecast';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field asOfMonth = contains(StringField); // the last closed month the forecast uses, e.g. 2026-06
  @field method = contains(StringField); // FORECAST (linear trend) or AVERAGE (run rate)
  @field fromMonth = contains(StringField, {
    computeVia: function (this: PnlForecast) {
      return this.asOfMonth ? `${this.asOfMonth.slice(0, 4)}-01` : '';
    },
  });
  @field toMonth = contains(StringField, {
    computeVia: function (this: PnlForecast) {
      return this.asOfMonth ? `${this.asOfMonth.slice(0, 4)}-12` : '';
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
    query: { filter: {}, page: { size: 100 } },
  });
  @field rows = containsMany(ForecastRow, {
    computeVia: function (this: PnlForecast) {
      let asOf = this.asOfMonth ?? '',
        k = Number(asOf.slice(5, 7)) || 0,
        method = FORMULA[this.method ?? ''] ? this.method! : 'FORECAST';
      let types = new Map(
        (this.accounts ?? [])
          .filter(Boolean)
          .map((a) => [
            a!.code ?? '',
            { section: SECTION[a!.type ?? ''] ?? '', name: a!.name ?? '' },
          ]),
      );
      // Each P&L account's amount per month, on its normal side (income as a credit, costs as a debit).
      let byAccount = new Map<string, number[]>();
      for (let c of (this.closes ?? []).filter(Boolean)) {
        let m = Number((c!.month ?? '').slice(5, 7));
        if (!m) continue;
        for (let t of c!.totals ?? []) {
          let a = types.get(t?.account ?? '');
          if (!a?.section) continue;
          let series = byAccount.get(t!.account!) ?? Array(12).fill(0),
            v = (t!.debitMinor ?? 0) - (t!.creditMinor ?? 0);
          series[m - 1] += a.section === 'income' ? -v : v;
          byAccount.set(t!.account!, series);
        }
      }
      let closed = new Set(
        (this.closes ?? [])
          .filter(Boolean)
          .map((c) => Number((c!.month ?? '').slice(5, 7))),
      );
      let fullYearClosed = [...Array(12).keys()].every((i) =>
        closed.has(i + 1),
      );
      let out: ForecastRow[] = [];
      for (let [account, series] of byAccount) {
        let a = types.get(account)!,
          ys = series.slice(0, k),
          xs = ys.map((_, i) => i + 1);
        if (!ys.some((y) => y)) continue;
        let rest: number[] = [],
          slope = 0;
        try {
          rest =
            (evaluateBxl(FORMULA[method], { ys, xs, from: k + 1 })
              .value as number[]) ?? [];
          slope =
            ys.length > 1
              ? Number(evaluateBxl('SLOPE(.ys, .xs)', { ys, xs }).value) || 0
              : 0;
        } catch {
          rest = [];
        }
        let actual = ys.reduce((n, y) => n + y, 0),
          forecast = Math.round(rest.reduce((n, y) => n + (Number(y) || 0), 0));
        out.push(
          new ForecastRow({
            section: a.section,
            account,
            name: a.name,
            actualMinor: actual,
            forecastMinor: forecast,
            fullYearMinor: actual + forecast,
            trendMinor: Math.round(slope),
            outcomeMinor: fullYearClosed
              ? series.reduce((n, y) => n + y, 0)
              : undefined,
          }),
        );
      }
      return out.sort((x, y) =>
        (x.account ?? '').localeCompare(y.account ?? ''),
      );
    },
  });
  @field netActualMinor = contains(NumberField, {
    computeVia: function (this: PnlForecast) {
      return net(this.rows, 'actualMinor');
    },
  });
  @field netForecastMinor = contains(NumberField, {
    computeVia: function (this: PnlForecast) {
      return net(this.rows, 'fullYearMinor');
    },
  });
  @field netOutcomeMinor = contains(NumberField, {
    computeVia: function (this: PnlForecast) {
      return (this.rows ?? []).some((r) => r?.outcomeMinor != null)
        ? net(this.rows, 'outcomeMinor')
        : undefined;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PnlForecast) {
      return `P&L forecast · ${this.asOfMonth ?? ''} · ${this.method === 'AVERAGE' ? 'run rate' : 'trend'}`;
    },
  });

  static isolated = class extends Component<typeof PnlForecast> {
    get method() {
      return this.args.model.method === 'AVERAGE' ? 'AVERAGE' : 'FORECAST';
    }
    get k() {
      return Number((this.args.model.asOfMonth ?? '').slice(5, 7)) || 0;
    }
    get formula() {
      return this.method === 'AVERAGE'
        ? `=SUM(actuals) + ${12 - this.k} × AVERAGE(actuals)`
        : `=SUM(actuals) + SUM(FORECAST({${this.k + 1}…12}, actuals, {1…${this.k}}))`;
    }
    get facts(): Fact[] {
      let m = this.args.model,
        out: Fact[] = [
          {
            key: 'Closed months used',
            value: `${this.k} (through ${m.asOfMonth ?? ''})`,
          },
          { key: 'Formula, per account', value: this.formula },
          { key: 'Net income so far', value: money(m.netActualMinor) },
          {
            key: 'Net income forecast for the year',
            value: money(m.netForecastMinor),
            strong: true,
          },
        ];
      if (m.netOutcomeMinor != null)
        out.push(
          {
            key: 'Net income as the year closed',
            value: money(m.netOutcomeMinor),
          },
          {
            key: 'Forecast error',
            value: `${money((m.netForecastMinor ?? 0) - (m.netOutcomeMinor ?? 0))} (${pct(m.netForecastMinor, m.netOutcomeMinor)})`,
          },
        );
      return out;
    }
    get hasOutcome() {
      return this.args.model.netOutcomeMinor != null;
    }
    get cols(): Col[] {
      return [
        { key: 'code', label: 'No.', kind: 'code', width: '4.5rem' },
        { key: 'name', label: 'Account' },
        { key: 'actual', label: 'Actual to date', kind: 'amount' },
        {
          key: 'trend',
          label: 'Trend a month',
          kind: 'amount',
          sign: 'change',
          priority: 'secondary',
        },
        { key: 'fy', label: 'Full year (forecast)', kind: 'amount' },
        ...(this.hasOutcome
          ? [
              { key: 'out', label: 'As closed', kind: 'amount' as const },
              {
                key: 'err',
                label: 'Error',
                kind: 'percent' as const,
                priority: 'secondary' as const,
              },
            ]
          : []),
      ];
    }
    get rows(): Line[] {
      let rows = (this.args.model.rows ?? []).filter(Boolean) as ForecastRow[],
        m = this.args.model;
      let section = (key: string): Line[] => {
        let list = rows.filter((r) => r.section === key),
          sum = (f: keyof ForecastRow) =>
            list.reduce((n, r) => n + ((r[f] as number) ?? 0), 0);
        return [
          { key: `h-${key}`, role: 'heading', cells: { code: TITLE[key] } },
          ...list.map((r) => ({
            key: r.account ?? '',
            depth: 1,
            cells: {
              code: r.account,
              name: r.name,
              actual: r.actualMinor,
              trend: r.trendMinor,
              fy: r.fullYearMinor,
              out: r.outcomeMinor,
              err: r.outcomeMinor
                ? ((r.fullYearMinor ?? 0) - r.outcomeMinor) /
                  Math.abs(r.outcomeMinor)
                : undefined,
            },
            data: {
              row: true,
              key: r.account,
              total: r.fullYearMinor ?? 0,
              dr: r.outcomeMinor ?? 0,
            },
          })),
          {
            key: `t-${key}`,
            role: 'subtotal',
            cells: {
              code: '',
              name: `Total ${TITLE[key]}`,
              actual: sum('actualMinor'),
              fy: sum('fullYearMinor'),
              out: this.hasOutcome ? sum('outcomeMinor') : undefined,
            },
          },
        ];
      };
      return [
        ...section('income'),
        ...section('cogs'),
        ...section('expense'),
        {
          key: 'net',
          role: 'total',
          cells: {
            code: '',
            name: 'Net income',
            actual: m.netActualMinor,
            fy: m.netForecastMinor,
            out: m.netOutcomeMinor ?? undefined,
          },
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Forecast'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.netForecastMinor}}
        @figureLabel='Net income, full year (forecast)'
        @note='Each account’s closed months are the known values; the formula projects the rest of the year. Excel functions, evaluated by BXL.'
      >
        <Part @title='Summary'><Facts @items={{this.facts}} /></Part>
        <Part @title='Forecast by account'><StatementTable
            @label='Profit and loss forecast'
            @columns={{this.cols}}
            @rows={{this.rows}}
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PnlForecast> {
    <template>
      <Strip
        @eyebrow='P&L forecast'
        @title={{@model.cardTitle}}
        @figure={{money @model.netForecastMinor}}
        @meta='Net income, full year'
      />
    </template>
  };
  static fitted = class extends Component<typeof PnlForecast> {
    <template>
      <Fit
        @eyebrow='Forecast'
        @title={{@model.asOfMonth}}
        @figure={{money @model.netForecastMinor}}
        @meta='Net income'
      />
    </template>
  };
}

function net(
  rows: (ForecastRow | undefined)[] | undefined,
  f: 'actualMinor' | 'fullYearMinor' | 'outcomeMinor',
) {
  return (rows ?? [])
    .filter(Boolean)
    .reduce(
      (n, r) =>
        n + (r!.section === 'income' ? 1 : -1) * ((r![f] as number) ?? 0),
      0,
    );
}
const pct = (a: number | undefined, b: number | undefined) =>
  b ? `${((((a ?? 0) - b) / Math.abs(b)) * 100).toFixed(1)}%` : '';
