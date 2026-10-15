// Registers as cards, each computed from the journal's postings (their facts and detail items) and
// tied to the general ledger through the closed months: fixed assets (and their register), the equipment loan, schedules (prepaids,
// deferred revenue, reversals), the sales tax agency, and payroll by quarter.
import {
  CardDef,
  Component,
  field,
  contains,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Invoice } from './ledger-sales';
import { JournalMonth, journalPostings } from './ledger-journal';
import { MonthClose, netOf } from './ledger-close';
import {
  Sheet,
  Part,
  Facts,
  Strip,
  Fit,
  money,
  day,
  type Fact,
} from './record-kit';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from './components/statement-table';

const sum = (xs: (number | undefined)[]) =>
  xs.reduce<number>((n, x) => n + (x ?? 0), 0);
const posted = { eq: { status: 'posted' } };
const allMonths = { query: { filter: {}, page: { size: 240 } } };
const tie = (
  label: string,
  card: number | undefined,
  gl: number | undefined,
): Fact => ({
  key: `${label} (general ledger)`,
  value: `${money(gl)}${(card ?? 0) === (gl ?? 0) ? ' · ties' : ' · does not tie'}`,
});

// ── fixed assets ─────────────────────────────────────────────────────────────
export class FixedAsset extends CardDef {
  static displayName = 'Fixed asset';
  static icon = BookIcon;
  @field assetId = contains(StringField);
  @field name = contains(StringField);
  @field serial = contains(StringField);
  @field loc = contains(StringField);
  @field inService = contains(StringField);
  @field lifeMonths = contains(NumberField);
  @field costMinor = contains(NumberField);
  @field salvageMinor = contains(NumberField);
  @field openingAccumulatedMinor = contains(NumberField); // depreciation taken before these books
  @field journal = linksToMany(() => JournalMonth, allMonths);
  @field takenMinor = contains(NumberField, {
    computeVia: function (this: FixedAsset) {
      return sum(
        journalPostings(this.journal, ['depreciation']).flatMap((r) =>
          r.items
            .filter((a) => a.label === this.assetId)
            .map((a) => a.amountMinor),
        ),
      );
    },
  });
  @field disposalProceedsMinor = contains(NumberField, {
    computeVia: function (this: FixedAsset) {
      return (
        journalPostings(this.journal, ['disposal'])
          .find((d) => d.fact('asset') === this.assetId)
          ?.num('proceedsMinor') ?? 0
      );
    },
  });
  @field accumulatedMinor = contains(NumberField, {
    computeVia: function (this: FixedAsset) {
      return (this.openingAccumulatedMinor ?? 0) + (this.takenMinor ?? 0);
    },
  });
  @field disposedOn = contains(StringField, {
    computeVia: function (this: FixedAsset) {
      return (
        journalPostings(this.journal, ['disposal']).find(
          (d) => d.fact('asset') === this.assetId,
        )?.date ?? ''
      );
    },
  });
  @field bookValueMinor = contains(NumberField, {
    computeVia: function (this: FixedAsset) {
      return this.disposedOn
        ? 0
        : (this.costMinor ?? 0) - (this.accumulatedMinor ?? 0);
    },
  });
  @field monthlyMinor = contains(NumberField, {
    computeVia: function (this: FixedAsset) {
      return this.lifeMonths
        ? Math.round(
            ((this.costMinor ?? 0) - (this.salvageMinor ?? 0)) /
              this.lifeMonths,
          )
        : 0;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: FixedAsset) {
      return this.name ?? this.assetId ?? 'Fixed asset';
    },
  });
  static isolated = class extends Component<typeof FixedAsset> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Asset', value: m.assetId ?? '', strong: true, mono: true },
        ...(m.serial ? [{ key: 'Serial', value: m.serial }] : []),
        { key: 'In service', value: day(m.inService) },
        {
          key: 'Life',
          value: `${m.lifeMonths ?? 0} months · ${money(m.monthlyMinor)} a month`,
        },
        { key: 'Cost', value: money(m.costMinor) },
        {
          key: 'Depreciation before these books',
          value: money(m.openingAccumulatedMinor),
        },
        { key: 'Depreciation this year', value: money(m.takenMinor) },
        { key: 'Accumulated', value: money(m.accumulatedMinor), strong: true },
        ...(m.disposedOn
          ? [
              {
                key: 'Disposed',
                value: `${day(m.disposedOn)} for ${money(m.disposalProceedsMinor)}`,
              },
            ]
          : []),
      ];
    }
    <template>
      <Sheet
        @eyebrow='Fixed asset'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.bookValueMinor}}
        @figureLabel='Book value'
        @status={{if @model.disposedOn 'Disposed' 'In service'}}
      ><Part @title='Asset'><div
            data-row
            data-key={{@model.assetId}}
            data-total={{@model.accumulatedMinor}}
            data-dr={{@model.bookValueMinor}}
          ><Facts @items={{this.facts}} /></div></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof FixedAsset> {
    <template>
      <Strip
        @eyebrow='Fixed asset'
        @title={{@model.cardTitle}}
        @figure={{money @model.bookValueMinor}}
        @meta='Book value'
      />
    </template>
  };
  static fitted = class extends Component<typeof FixedAsset> {
    <template>
      <Fit
        @eyebrow='Asset'
        @title={{@model.cardTitle}}
        @figure={{money @model.bookValueMinor}}
        @meta={{@model.assetId}}
      />
    </template>
  };
}

export class FixedAssetRegister extends CardDef {
  static displayName = 'Fixed asset register';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field throughMonth = contains(StringField);
  @field assets = linksToMany(() => FixedAsset, {
    query: { filter: {}, page: { size: 200 } },
  });
  @field closes = linksToMany(() => MonthClose, {
    query: {
      filter: { range: { month: { lte: '$this.throughMonth' } } },
      page: { size: 240 },
    },
  });
  @field costMinor = contains(NumberField, {
    computeVia: function (this: FixedAssetRegister) {
      return sum(
        (this.assets ?? [])
          .filter((a) => a && !a.disposedOn)
          .map((a) => a!.costMinor),
      );
    },
  });
  @field accumulatedMinor = contains(NumberField, {
    computeVia: function (this: FixedAssetRegister) {
      return sum(
        (this.assets ?? [])
          .filter((a) => a && !a.disposedOn)
          .map((a) => a!.accumulatedMinor),
      );
    },
  });
  @field glCostMinor = contains(NumberField, {
    computeVia: function (this: FixedAssetRegister) {
      return netOf(this.closes).get('1500') ?? 0;
    },
  });
  @field glAccumulatedMinor = contains(NumberField, {
    computeVia: function (this: FixedAssetRegister) {
      return -(netOf(this.closes).get('1510') ?? 0);
    },
  });
  @field ties = contains(BooleanField, {
    computeVia: function (this: FixedAssetRegister) {
      return (
        this.costMinor === this.glCostMinor &&
        this.accumulatedMinor === this.glAccumulatedMinor
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: FixedAssetRegister) {
      return `Fixed asset register · ${this.throughMonth ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof FixedAssetRegister> {
    cols: Col[] = [
      { key: 'id', label: 'Asset', kind: 'code' },
      { key: 'name', label: 'Name' },
      { key: 'cost', label: 'Cost', kind: 'amount' },
      { key: 'acc', label: 'Accumulated', kind: 'amount' },
      { key: 'nbv', label: 'Book value', kind: 'amount' },
      { key: 'status', label: 'Status', priority: 'secondary' },
    ];
    get rows(): Line[] {
      let m = this.args.model,
        live = (m.assets ?? []).filter((a) => a && !a.disposedOn);
      return [
        ...(m.assets ?? []).filter(Boolean).map((a) => ({
          key: a!.assetId ?? '',
          cells: {
            id: a!.assetId,
            name: a!.name,
            cost: a!.costMinor,
            acc: a!.accumulatedMinor,
            nbv: a!.bookValueMinor,
            status: a!.disposedOn ? `Disposed ${a!.disposedOn}` : 'In service',
          },
          data: {
            row: true,
            key: a!.assetId,
            total: a!.accumulatedMinor ?? 0,
          },
        })),
        {
          key: 'total',
          role: 'total' as const,
          cells: {
            id: '',
            name: 'In service',
            cost: m.costMinor,
            acc: m.accumulatedMinor,
            nbv: sum(live.map((a) => a!.bookValueMinor)),
          },
        },
      ];
    }
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Cost in service', value: money(m.costMinor), strong: true },
        tie('Cost', m.costMinor, m.glCostMinor),
        {
          key: 'Accumulated depreciation',
          value: money(m.accumulatedMinor),
          strong: true,
        },
        tie('Accumulated', m.accumulatedMinor, m.glAccumulatedMinor),
      ];
    }
    <template>
      <Sheet
        @eyebrow='Fixed assets'
        @title={{@model.cardTitle}}
        @figureMinor={{sub @model.costMinor @model.accumulatedMinor}}
        @figureLabel='Net book value'
        @status={{if @model.ties 'Ties to the ledger' 'Does not tie'}}
      >
        <Part @title='Register'><Facts @items={{this.facts}} /></Part>
        <Part @title='Assets'><StatementTable
            @label='Fixed assets'
            @columns={{this.cols}}
            @rows={{this.rows}}
            @zero='show'
          /></Part>
      </Sheet>
    </template>
  };
  static embedded = class extends Component<typeof FixedAssetRegister> {
    <template>
      <Strip
        @eyebrow='Fixed assets'
        @title={{@model.cardTitle}}
        @figure={{money @model.costMinor}}
        @meta='Cost in service'
      />
    </template>
  };
  static fitted = class extends Component<typeof FixedAssetRegister> {
    <template>
      <Fit
        @eyebrow='Fixed assets'
        @title={{@model.throughMonth}}
        @figure={{money @model.costMinor}}
        @meta='Cost'
      />
    </template>
  };
}
const sub = (a: number | undefined, b: number | undefined) =>
  (a ?? 0) - (b ?? 0);

// ── the loan ─────────────────────────────────────────────────────────────────
export class Loan extends CardDef {
  static displayName = 'Loan';
  static icon = BookIcon;
  @field loanId = contains(StringField);
  @field lender = contains(StringField);
  @field account = contains(StringField);
  @field openedOn = contains(StringField);
  @field openingBalanceMinor = contains(NumberField);
  @field ratePpm = contains(NumberField);
  @field paymentMinor = contains(NumberField);
  @field journal = linksToMany(() => JournalMonth, allMonths);
  @field paymentCount = contains(NumberField, {
    computeVia: function (this: Loan) {
      return journalPostings(this.journal, ['loan-payment']).filter(
        (p) => p.fact('loan') === this.loanId,
      ).length;
    },
  });
  @field closes = linksToMany(() => MonthClose, {
    query: { filter: {}, page: { size: 240 } },
  });
  @field principalPaidMinor = contains(NumberField, {
    computeVia: function (this: Loan) {
      return sum(
        journalPostings(this.journal, ['loan-payment'])
          .filter((p) => p.fact('loan') === this.loanId)
          .map((p) => p.num('principalMinor')),
      );
    },
  });
  @field interestPaidMinor = contains(NumberField, {
    computeVia: function (this: Loan) {
      return sum(
        journalPostings(this.journal, ['loan-payment'])
          .filter((p) => p.fact('loan') === this.loanId)
          .map((p) => p.num('interestMinor')),
      );
    },
  });
  @field balanceMinor = contains(NumberField, {
    computeVia: function (this: Loan) {
      return (this.openingBalanceMinor ?? 0) - (this.principalPaidMinor ?? 0);
    },
  });
  @field glBalanceMinor = contains(NumberField, {
    computeVia: function (this: Loan) {
      return -(netOf(this.closes).get(this.account ?? '') ?? 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Loan) {
      return this.lender ?? this.loanId ?? 'Loan';
    },
  });
  static isolated = class extends Component<typeof Loan> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Loan', value: m.loanId ?? '', strong: true, mono: true },
        {
          key: 'Opened with',
          value: `${money(m.openingBalanceMinor)} on ${day(m.openedOn)}`,
        },
        { key: 'Rate', value: `${(m.ratePpm ?? 0) / 10000}%` },
        { key: 'Payment', value: `${money(m.paymentMinor)} a month` },
        { key: 'Payments made', value: String(m.paymentCount ?? 0) },
        { key: 'Principal repaid', value: money(m.principalPaidMinor) },
        { key: 'Interest paid', value: money(m.interestPaidMinor) },
        tie('Balance', m.balanceMinor, m.glBalanceMinor),
      ];
    }
    <template>
      <Sheet
        @eyebrow='Loan'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.balanceMinor}}
        @figureLabel='Balance'
        @status={{if
          (eq0 @model.balanceMinor @model.glBalanceMinor)
          'Ties to the ledger'
          'Does not tie'
        }}
      ><Part @title='Loan'><div
            data-row
            data-key={{@model.loanId}}
            data-total={{@model.balanceMinor}}
            data-dr={{@model.glBalanceMinor}}
          ><Facts @items={{this.facts}} /></div></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof Loan> {
    <template>
      <Strip
        @eyebrow='Loan'
        @title={{@model.cardTitle}}
        @figure={{money @model.balanceMinor}}
        @meta='Balance'
      />
    </template>
  };
  static fitted = class extends Component<typeof Loan> {
    <template>
      <Fit
        @eyebrow='Loan'
        @title={{@model.loanId}}
        @figure={{money @model.balanceMinor}}
        @meta='Balance'
      />
    </template>
  };
}
const eq0 = (a: number | undefined, b: number | undefined) =>
  (a ?? 0) === (b ?? 0);

// ── schedules ────────────────────────────────────────────────────────────────
export class Schedule extends CardDef {
  static displayName = 'Schedule';
  static icon = BookIcon;
  @field scheduleId = contains(StringField);
  @field kind = contains(StringField); // prepaid, deferred, reversal
  @field memo = contains(StringField);
  @field periods = contains(NumberField);
  @field totalMinor = contains(NumberField); // what the whole schedule releases
  @field journal = linksToMany(() => JournalMonth, allMonths);
  @field postedCount = contains(NumberField, {
    computeVia: function (this: Schedule) {
      return journalPostings(this.journal, ['scheduled']).filter(
        (e) => e.fact('schedule') === this.scheduleId,
      ).length;
    },
  });
  @field releasedMinor = contains(NumberField, {
    computeVia: function (this: Schedule) {
      return sum(
        journalPostings(this.journal, ['scheduled'])
          .filter((e) => e.fact('schedule') === this.scheduleId)
          .flatMap((e) => e.lines.map((l) => l.debitMinor)),
      );
    },
  });
  @field remainingMinor = contains(NumberField, {
    computeVia: function (this: Schedule) {
      return (this.totalMinor ?? 0) - (this.releasedMinor ?? 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Schedule) {
      return `Schedule ${this.scheduleId ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof Schedule> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        {
          key: 'Schedule',
          value: m.scheduleId ?? '',
          strong: true,
          mono: true,
        },
        { key: 'Kind', value: m.kind ?? '' },
        {
          key: 'Periods posted',
          value: `${m.postedCount ?? 0} of ${m.periods ?? 0}`,
        },
        { key: 'Released', value: money(m.releasedMinor) },
        {
          key: 'Still to release',
          value: money(m.remainingMinor),
          strong: true,
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Schedule'
        @title={{@model.cardTitle}}
        @meta={{@model.memo}}
        @figureMinor={{@model.remainingMinor}}
        @figureLabel='Remaining'
        @status={{if @model.remainingMinor 'Running' 'Complete'}}
      ><Part @title='Schedule'><div
            data-row
            data-key={{@model.scheduleId}}
            data-total={{@model.postedCount}}
            data-dr={{@model.releasedMinor}}
          ><Facts @items={{this.facts}} /></div></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof Schedule> {
    <template>
      <Strip
        @eyebrow='Schedule'
        @title={{@model.cardTitle}}
        @figure={{money @model.remainingMinor}}
        @meta={{@model.kind}}
      />
    </template>
  };
  static fitted = class extends Component<typeof Schedule> {
    <template>
      <Fit
        @eyebrow='Schedule'
        @title={{@model.scheduleId}}
        @figure={{money @model.remainingMinor}}
        @meta={{@model.kind}}
      />
    </template>
  };
}

// ── sales tax ────────────────────────────────────────────────────────────────
export class TaxAgency extends CardDef {
  static displayName = 'Tax agency';
  static icon = BookIcon;
  @field agencyId = contains(StringField);
  @field name = contains(StringField);
  @field state = contains(StringField);
  @field ratePpm = contains(NumberField);
  @field frequency = contains(StringField);
  @field openingOwedMinor = contains(NumberField); // owed at conversion
  @field invoices = linksToMany(() => Invoice, {
    query: {
      filter: { every: [posted, { eq: { agencyId: '$this.agencyId' } }] },
      page: { size: 500 },
    },
  });
  @field journal = linksToMany(() => JournalMonth, allMonths);
  @field closes = linksToMany(() => MonthClose, {
    query: { filter: {}, page: { size: 240 } },
  });
  @field collectedMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      return (
        sum((this.invoices ?? []).filter(Boolean).map((d) => d!.taxMinor)) +
        sum(
          journalPostings(this.journal, ['sales-receipt'])
            .filter((r) => r.fact('agencyId') === this.agencyId)
            .map((r) => r.num('taxMinor')),
        )
      );
    },
  });
  @field taxableMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      return (
        sum(
          (this.invoices ?? [])
            .filter(Boolean)
            .flatMap((d) => (d!.lines ?? []).map((l) => l?.amountMinor)),
        ) +
        sum(
          journalPostings(this.journal, ['sales-receipt'])
            .filter((r) => r.fact('agencyId') === this.agencyId)
            .flatMap((r) => r.items.map((i) => i.amountMinor)),
        )
      );
    },
  });
  @field paidMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      return sum(
        journalPostings(this.journal, ['bank-payment'])
          .filter((p) => p.fact('payee') === this.agencyId)
          .map((p) => p.num('amountMinor')),
      );
    },
  });
  @field owedMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      return (
        (this.openingOwedMinor ?? 0) +
        (this.collectedMinor ?? 0) -
        (this.paidMinor ?? 0)
      );
    },
  });
  @field glOwedMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      return -(netOf(this.closes).get('2200') ?? 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: TaxAgency) {
      return this.name ?? this.agencyId ?? 'Tax agency';
    },
  });
  static isolated = class extends Component<typeof TaxAgency> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Agency', value: m.agencyId ?? '', strong: true },
        { key: 'Rate', value: `${(m.ratePpm ?? 0) / 10000}%` },
        { key: 'Files', value: m.frequency ?? '' },
        { key: 'Owed at conversion', value: money(m.openingOwedMinor) },
        { key: 'Taxable sales', value: money(m.taxableMinor) },
        { key: 'Tax collected', value: money(m.collectedMinor) },
        { key: 'Paid', value: money(m.paidMinor) },
        tie('Owed', m.owedMinor, m.glOwedMinor),
      ];
    }
    <template>
      <Sheet
        @eyebrow='Sales tax'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.owedMinor}}
        @figureLabel='Owed'
        @status={{if
          (eq0 @model.owedMinor @model.glOwedMinor)
          'Ties to the ledger'
          'Does not tie'
        }}
      ><Part @title='Liability'><div
            data-row
            data-key={{@model.agencyId}}
            data-total={{@model.owedMinor}}
            data-dr={{@model.glOwedMinor}}
            data-cr={{@model.collectedMinor}}
          ><Facts @items={{this.facts}} /></div></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof TaxAgency> {
    <template>
      <Strip
        @eyebrow='Tax agency'
        @title={{@model.cardTitle}}
        @figure={{money @model.owedMinor}}
        @meta='Owed'
      />
    </template>
  };
  static fitted = class extends Component<typeof TaxAgency> {
    <template>
      <Fit
        @eyebrow='Sales tax'
        @title={{@model.agencyId}}
        @figure={{money @model.owedMinor}}
        @meta='Owed'
      />
    </template>
  };
}

// ── payroll by quarter ──────────────────────────────────────────────────────
export class PayrollQuarter extends CardDef {
  static displayName = 'Payroll quarter';
  static icon = BookIcon;
  @field year = contains(NumberField);
  @field quarter = contains(NumberField);
  @field fromDate = contains(StringField, {
    computeVia: function (this: PayrollQuarter) {
      return this.year && this.quarter
        ? `${this.year}-${String(this.quarter * 3 - 2).padStart(2, '0')}-01`
        : '';
    },
  });
  @field toDate = contains(StringField, {
    computeVia: function (this: PayrollQuarter) {
      if (!this.year || !this.quarter) return '';
      let m = this.quarter * 3;
      return new Date(Date.UTC(this.year, m, 0)).toISOString().slice(0, 10);
    },
  });
  @field fromMonth = contains(StringField, {
    computeVia: function (this: PayrollQuarter) {
      return (this.fromDate ?? '').slice(0, 7);
    },
  });
  @field toMonth = contains(StringField, {
    computeVia: function (this: PayrollQuarter) {
      return (this.toDate ?? '').slice(0, 7);
    },
  });
  @field journal = linksToMany(() => JournalMonth, {
    query: {
      filter: {
        range: { month: { gte: '$this.fromMonth', lte: '$this.toMonth' } },
      },
      page: { size: 12 },
    },
  });
  @field runCount = contains(NumberField, {
    computeVia: function (this: PayrollQuarter) {
      return journalPostings(this.journal, ['payroll']).length;
    },
  });
  @field grossMinor = contains(NumberField, {
    computeVia: function (this: PayrollQuarter) {
      return sum(
        journalPostings(this.journal, ['payroll']).flatMap((r) =>
          r.items.map((w) => w.amountMinor),
        ),
      );
    },
  });
  @field withholdingMinor = contains(NumberField, {
    computeVia: function (this: PayrollQuarter) {
      return sum(
        journalPostings(this.journal, ['payroll']).map((r) =>
          r.num('withholdingMinor'),
        ),
      );
    },
  });
  @field employerTaxMinor = contains(NumberField, {
    computeVia: function (this: PayrollQuarter) {
      return sum(
        journalPostings(this.journal, ['payroll']).map((r) =>
          r.num('employerTaxMinor'),
        ),
      );
    },
  });
  @field netMinor = contains(NumberField, {
    computeVia: function (this: PayrollQuarter) {
      return sum(
        journalPostings(this.journal, ['payroll']).map((r) =>
          r.num('netMinor'),
        ),
      );
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PayrollQuarter) {
      return `Payroll · ${this.year ?? ''} Q${this.quarter ?? ''}`;
    },
  });
  static isolated = class extends Component<typeof PayrollQuarter> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Period', value: `${day(m.fromDate)} – ${day(m.toDate)}` },
        { key: 'Payroll runs', value: String(m.runCount ?? 0) },
        { key: 'Gross wages', value: money(m.grossMinor), strong: true },
        { key: 'Withheld', value: money(m.withholdingMinor) },
        { key: 'Employer taxes', value: money(m.employerTaxMinor) },
        { key: 'Net pay', value: money(m.netMinor) },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Payroll'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.grossMinor}}
        @figureLabel='Gross wages'
      ><Part @title='Quarter'><div
            data-row
            data-key='{{@model.year}}-Q{{@model.quarter}}'
            data-total={{@model.grossMinor}}
            data-dr={{@model.withholdingMinor}}
            data-cr={{@model.employerTaxMinor}}
            data-qty={{@model.runCount}}
          ><Facts @items={{this.facts}} /></div></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PayrollQuarter> {
    <template>
      <Strip
        @eyebrow='Payroll'
        @title={{@model.cardTitle}}
        @figure={{money @model.grossMinor}}
        @meta='Gross wages'
      />
    </template>
  };
  static fitted = class extends Component<typeof PayrollQuarter> {
    <template>
      <Fit
        @eyebrow='Payroll'
        @title={{@model.cardTitle}}
        @figure={{money @model.grossMinor}}
        @meta='Gross'
      />
    </template>
  };
}
