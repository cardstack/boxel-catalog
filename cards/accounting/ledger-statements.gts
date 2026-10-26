// Open invoices (accounts receivable aging), computed from the posted Invoice cards.
// (Month totals and the trial balance are in ledger-months.gts.)
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
import { Invoice } from './ledger-sales';
import { MonthClose } from './ledger-close';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  days,
  partialNote,
  type Fact,
} from './record-kit';
import { toHome } from './ledger-document';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';

// ── open invoices (AR aging) ────────────────────────────────────────────────
export class ReceivableRow extends FieldDef {
  @field customerId = contains(StringField);
  @field invoices = contains(NumberField);
  @field currentMinor = contains(NumberField);
  @field d30Minor = contains(NumberField);
  @field d60Minor = contains(NumberField);
  @field d90Minor = contains(NumberField);
  @field over90Minor = contains(NumberField);
  @field totalMinor = contains(NumberField);
}

export class OpenInvoicesReport extends CardDef {
  static displayName = 'Open invoices';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field asOf = contains(StringField); // YYYY-MM-DD
  @field invoices = linksToMany(() => Invoice, {
    query: {
      filter: {
        every: [
          { eq: { status: 'posted' } },
          { range: { date: { lte: '$this.asOf' } } },
        ],
      },
      page: { size: 1000 },
    },
  });
  @field rows = containsMany(ReceivableRow, {
    computeVia: function (this: OpenInvoicesReport) {
      let asOf = this.asOf ?? '9999-12-31',
        by = new Map<string, any>();
      for (let i of (this.invoices ?? []).filter(Boolean)) {
        // In the home currency: a document in another currency at the rate it was booked at.
        let open = toHome(i.openMinor, i.rateMicros);
        if (open <= 0) continue;
        let r = by.get(i.customerId ?? '') ?? {
          customerId: i.customerId ?? '',
          invoices: 0,
          currentMinor: 0,
          d30Minor: 0,
          d60Minor: 0,
          d90Minor: 0,
          over90Minor: 0,
          totalMinor: 0,
        };
        let late = days(i.due || i.date || asOf, asOf);
        let bucket =
          late <= 0
            ? 'currentMinor'
            : late <= 30
              ? 'd30Minor'
              : late <= 60
                ? 'd60Minor'
                : late <= 90
                  ? 'd90Minor'
                  : 'over90Minor';
        r[bucket] += open;
        r.totalMinor += open;
        r.invoices++;
        by.set(r.customerId, r);
      }
      return [...by.values()]
        .sort((a, b) => b.totalMinor - a.totalMinor)
        .map((r) => new ReceivableRow(r));
    },
  });
  @field totalOpenMinor = contains(NumberField, {
    computeVia: function (this: OpenInvoicesReport) {
      return (this.rows ?? []).reduce((n, r) => n + (r?.totalMinor ?? 0), 0);
    },
  });
  // The aging must tie to its control account: 1100 as the closed months carry it, through the as-of month.
  @field asOfMonth = contains(StringField, {
    computeVia: function (this: OpenInvoicesReport) {
      return (this.asOf ?? '').slice(0, 7);
    },
  });
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.asOfMonth' } } },
      page: { size: 240 },
    },
  });
  @field closedThrough = contains(StringField, {
    computeVia: function (this: OpenInvoicesReport) {
      return (
        (this.closes ?? [])
          .filter(Boolean)
          .map((c) => c!.month ?? '')
          .sort()
          .at(-1) ?? ''
      );
    },
  });
  @field glMinor = contains(NumberField, {
    computeVia: function (this: OpenInvoicesReport) {
      let n = 0;
      for (let c of (this.closes ?? []).filter(Boolean))
        for (let t of c!.totals ?? [])
          if (t?.account === '1100') {
            n += (t.debitMinor ?? 0) - (t.creditMinor ?? 0);
          }
      return n;
    },
  });
  @field differenceMinor = contains(NumberField, {
    computeVia: function (this: OpenInvoicesReport) {
      return (this.totalOpenMinor ?? 0) - (this.glMinor ?? 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: OpenInvoicesReport) {
      return `Open invoices · as of ${this.asOf ?? ''}`;
    },
  });

  static isolated = class extends Component<typeof OpenInvoicesReport> {
    get note() {
      return (
        partialNote(this.args.model, 'invoices') ||
        'Open is each posted invoice less the payments, credits and write-offs applied to it.'
      );
    }
    get tieWord() {
      return this.args.model.differenceMinor === 0
        ? 'Ties to the ledger'
        : 'Does not tie';
    }
    get tieTone() {
      return this.args.model.differenceMinor === 0 ? 'success' : 'danger';
    }
    get tieFacts(): Fact[] {
      let m = this.args.model,
        late = (m.closedThrough ?? '') < (m.asOfMonth ?? '');
      return [
        {
          key: `Accounts receivable (1100), closed months${m.closedThrough ? ' through ' + m.closedThrough : ''}`,
          value: money(m.glMinor),
        },
        { key: 'Open on the invoices', value: money(m.totalOpenMinor) },
        { key: 'Difference', value: money(m.differenceMinor), strong: true },
        ...(late
          ? [
              {
                key: 'Provisional',
                value: `${m.asOfMonth} isn't closed yet, so the ledger figure stops at ${m.closedThrough || 'the opening'}.`,
              },
            ]
          : []),
      ];
    }
    cols: Col[] = [
      { key: 'who', label: 'Customer', kind: 'code' },
      { key: 'n', label: 'Invoices', kind: 'number', priority: 'secondary' },
      { key: 'cur', label: 'Current', kind: 'amount' },
      { key: 'd30', label: '1–30', kind: 'amount' },
      { key: 'd60', label: '31–60', kind: 'amount', priority: 'secondary' },
      { key: 'd90', label: '61–90', kind: 'amount', priority: 'secondary' },
      { key: 'o90', label: 'Over 90', kind: 'amount' },
      { key: 'total', label: 'Total', kind: 'amount' },
    ];
    get rows(): Line[] {
      let m = this.args.model,
        rows = (m.rows ?? []).filter(Boolean),
        sum = (
          f:
            | 'currentMinor'
            | 'd30Minor'
            | 'd60Minor'
            | 'd90Minor'
            | 'over90Minor'
            | 'totalMinor',
        ) => rows.reduce((n, r) => n + ((r as any)[f] ?? 0), 0);
      return [
        ...rows.map((r) => ({
          key: r!.customerId ?? '',
          cells: {
            who: r!.customerId,
            n: r!.invoices,
            cur: r!.currentMinor,
            d30: r!.d30Minor,
            d60: r!.d60Minor,
            d90: r!.d90Minor,
            o90: r!.over90Minor,
            total: r!.totalMinor,
          },
          data: {
            row: true,
            key: r!.customerId,
            total: r!.totalMinor ?? 0,
            bills: r!.invoices,
          },
        })),
        {
          key: 'total',
          role: 'total' as const,
          cells: {
            who: 'Total',
            cur: sum('currentMinor'),
            d30: sum('d30Minor'),
            d60: sum('d60Minor'),
            d90: sum('d90Minor'),
            o90: sum('over90Minor'),
            total: sum('totalMinor'),
          },
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Accounts receivable aging'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.totalOpenMinor}}
        @figureLabel='Open'
        @note={{this.note}}
      >
        <Part @title='By customer'>
          <StatementTable
            @label='Receivables by customer'
            @columns={{this.cols}}
            @rows={{this.rows}}
          />
        </Part>
        <Part @title='Against the ledger'>
          <div
            class='tie'
            data-tie
            data-gl={{@model.glMinor}}
            data-diff={{@model.differenceMinor}}
          ><span class='tie-chip'><StatusChip
                @value={{this.tieWord}}
                @tone={{this.tieTone}}
              /></span><Facts @items={{this.tieFacts}} /></div>
        </Part>
      </Sheet>
      <style scoped>
        .tie {
          display: grid;
          gap: 0.6rem;
          min-width: 0;
        }
        .tie-chip {
          justify-self: start;
        }
      </style>
    </template>
  };
  static embedded = class extends Component<typeof OpenInvoicesReport> {
    <template>
      <Strip
        @eyebrow='Open invoices'
        @title={{@model.cardTitle}}
        @figure={{money @model.totalOpenMinor}}
        @meta='Accounts receivable aging'
      />
    </template>
  };
  static fitted = class extends Component<typeof OpenInvoicesReport> {
    <template>
      <Fit
        @eyebrow='Open invoices'
        @title={{@model.asOf}}
        @figure={{money @model.totalOpenMinor}}
        @meta='AR aging'
      />
    </template>
  };
}
