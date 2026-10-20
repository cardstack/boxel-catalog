// Registers as cards, each computed from the journal's postings (their facts and detail items) and
// tied to the general ledger through the closed months: fixed assets (and their register), the equipment loan, schedules (prepaids,
// deferred revenue, reversals), the sales tax agency, and payroll by quarter.
import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import {
  operation,
  bxl,
  instance,
  params,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { Invoice } from './ledger-sales';
import { agencyTaxOf } from './ledger-tax-codes';
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
import { IsoMonthField, IsoDateField } from './ledger-dates';

const sum = (xs: (number | undefined)[]) =>
  xs.reduce<number>((n, x) => n + (x ?? 0), 0);
const posted = { eq: { status: 'posted' } };

/**
 * What each sale dated between two days (yyyy-mm-dd, inclusive; either may be open) owes an agency:
 * invoices are cards, sales and refund receipts journal postings. A voided invoice counts only in a
 * period that ended before it was voided.
 */
export function salesOwedTo(
  invoices: (Invoice | undefined)[] | undefined,
  journal: unknown[] | undefined,
  agencyId: string,
  from = '',
  to = '',
) {
  let inRange = (d: string) => (!from || d >= from) && (!to || d <= to);
  let receipts = (kinds: string[], sign: number) =>
    journalPostings(journal, kinds)
      .filter((r) => inRange(r.date))
      .map((r) => {
        let owed = agencyTaxOf(
          {
            agencyId: r.fact('agencyId'),
            taxMinor: r.num('taxMinor'),
            taxLines: r.fact('taxLines') ? JSON.parse(r.fact('taxLines')) : [],
            lines: r.items,
          },
          agencyId,
        );
        return {
          taxableMinor: sign * owed.taxableMinor,
          taxMinor: sign * owed.taxMinor,
        };
      });
  return [
    ...(invoices ?? [])
      .filter(Boolean)
      .filter((d) => inRange(String(d!.date ?? '')))
      .filter((d) => !d!.voidDate || (!!to && String(d!.voidDate) > to))
      .map((d) => agencyTaxOf(d as any, agencyId)),
    ...receipts(['sales-receipt'], 1),
    ...receipts(['refund-receipt'], -1),
  ];
}

/** The sales tax payments made to an agency, from the journal's bank payments. */
export function paidTo(journal: unknown[] | undefined, agencyId: string) {
  return journalPostings(journal, ['bank-payment'])
    .filter((p) => p.fact('payee') === agencyId)
    .map((p) => ({ date: p.date, amountMinor: p.num('amountMinor') }));
}
const allMonths = { query: { page: { size: 240 } } };
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
  @field throughMonth = contains(IsoMonthField);
  @field assets = linksToMany(() => FixedAsset, {
    query: { page: { size: 200 } },
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
    query: { page: { size: 240 } },
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
      filter: {
        every: [
          posted,
          {
            any: [
              { eq: { agencyId: '$this.agencyId' } },
              { eq: { 'taxLines.agencyId': '$this.agencyId' } },
            ],
          },
        ],
      },
      page: { size: 500 },
    },
  });
  @field journal = linksToMany(() => JournalMonth, allMonths);
  @field closes = linksToMany(() => MonthClose, {
    query: { page: { size: 240 } },
  });
  @field filedThrough = contains(IsoDateField); // written only by markFiled, when a return is filed
  // The last day of the last closed month: what the general ledger's 2200 balance covers.
  @field closedThrough = contains(StringField, {
    computeVia: function (this: TaxAgency) {
      let m = (this.closes ?? [])
        .map((c) => String(c?.month ?? ''))
        .filter(Boolean)
        .sort()
        .at(-1);
      return m ? `${m}-31` : '';
    },
  });
  @field collectedMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      return sum(
        salesOwedTo(this.invoices, this.journal, this.agencyId ?? '').map(
          (s) => s.taxMinor,
        ),
      );
    },
  });
  @field taxableMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      return sum(
        salesOwedTo(this.invoices, this.journal, this.agencyId ?? '').map(
          (s) => s.taxableMinor,
        ),
      );
    },
  });
  @field paidMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      return sum(
        paidTo(this.journal, this.agencyId ?? '').map((p) => p.amountMinor),
      );
    },
  });
  // What it was owed at the last close, which is what 2200 in the closed months should hold.
  @field owedAtCloseMinor = contains(NumberField, {
    computeVia: function (this: TaxAgency) {
      let to = this.closedThrough ?? '';
      return (
        (this.openingOwedMinor ?? 0) +
        sum(
          salesOwedTo(
            this.invoices,
            this.journal,
            this.agencyId ?? '',
            '',
            to,
          ).map((s) => s.taxMinor),
        ) -
        sum(
          paidTo(this.journal, this.agencyId ?? '')
            .filter((p) => !to || p.date <= to)
            .map((p) => p.amountMinor),
        )
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
  /**
   * Refuse a sale dated in a period this agency's tax has been filed for. The desk sends it in the
   * same batch as the sale's post, for each agency the sale owes.
   */
  @operation static checkOpen = {
    base: 'transform',
    params: { date: StringField },
    transformations: bxl`
      assert(if .filedThrough == null then true else params("date") > .filedThrough end; "Sales tax for that date has been filed with this agency. Date the sale after the filed period, or correct it on the next return.");
      .filedThrough = .filedThrough;
    `,
  } satisfies OperationDeclaration;
  /** Lock a filed return's period. Sent in the same batch as the return's file. */
  @operation static markFiled = {
    base: 'transform',
    params: { periodStart: StringField, periodEnd: StringField },
    transformations: bxl`
      assert(if .filedThrough == null then true else params("periodStart") > .filedThrough end; "A return for part of that period has already been filed with this agency.");
      assert(params("periodEnd") >= params("periodStart"); "A return's period ends on or after it starts.");
      .filedThrough = params("periodEnd");
    `,
  } satisfies OperationDeclaration;
  /** Open a return for this agency's next period. */
  @operation static openReturn = {
    base: 'create',
    of: () => TaxReturn,
    params: { periodStart: StringField, periodEnd: StringField },
    fill: {
      agencyId: instance('agencyId'),
      periodStart: params('periodStart'),
      periodEnd: params('periodEnd'),
      status: 'open',
      adjustmentMinor: 0,
      paidMinor: 0,
    },
  } satisfies OperationDeclaration;
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
        ...(m.filedThrough
          ? [{ key: 'Filed through', value: day(m.filedThrough) }]
          : []),
        {
          key: 'Owed at the last close',
          value: money(m.owedAtCloseMinor),
        },
        tie('Owed at the last close', m.owedAtCloseMinor, m.glOwedMinor),
      ];
    }
    <template>
      <Sheet
        @eyebrow='Sales tax'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.owedMinor}}
        @figureLabel='Owed'
        @status={{if
          (eq0 @model.owedAtCloseMinor @model.glOwedMinor)
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

// ── sales tax returns ────────────────────────────────────────────────────────
export const TaxReturnStatusField = enumField(StringField, {
  displayName: 'Tax return status',
  options: [
    { value: 'open', label: 'Open' },
    { value: 'filed', label: 'Filed' },
    { value: 'paid', label: 'Paid' },
  ],
});

/**
 * One agency's sales tax for one period. While open, its figures come from that period's sales;
 * filing records them and locks the period with the agency, and payments against it come from the
 * bank payments made for it.
 */
export class TaxReturn extends CardDef {
  static displayName = 'Sales tax return';
  static icon = BookIcon;
  @field agencyId = contains(StringField);
  @field periodStart = contains(IsoDateField);
  @field periodEnd = contains(IsoDateField);
  @field status = contains(TaxReturnStatusField); // only file and markPaid move it
  @field adjustmentMinor = contains(NumberField); // a correction to an earlier period: more owed, or less
  @field adjustmentNote = contains(StringField);
  @field filedTaxableMinor = contains(NumberField); // written only by file
  @field filedTaxMinor = contains(NumberField); // written only by file
  @field filedOn = contains(IsoDateField);
  @field filedBy = contains(StringField);
  @field paidMinor = contains(NumberField); // written only by markPaid and unmarkPaid
  @field payments = containsMany(StringField); // the bank payments made for it
  @field invoices = linksToMany(() => Invoice, {
    query: {
      filter: {
        every: [
          posted,
          {
            any: [
              { eq: { agencyId: '$this.agencyId' } },
              { eq: { 'taxLines.agencyId': '$this.agencyId' } },
            ],
          },
        ],
      },
      page: { size: 500 },
    },
  });
  @field journal = linksToMany(() => JournalMonth, allMonths);
  @field taxableMinor = contains(NumberField, {
    computeVia: function (this: TaxReturn) {
      return this.status === 'open'
        ? sum(this.periodSales().map((s) => s.taxableMinor))
        : (this.filedTaxableMinor ?? 0);
    },
  });
  @field taxMinor = contains(NumberField, {
    computeVia: function (this: TaxReturn) {
      return this.status === 'open'
        ? sum(this.periodSales().map((s) => s.taxMinor))
        : (this.filedTaxMinor ?? 0);
    },
  });
  @field dueMinor = contains(NumberField, {
    computeVia: function (this: TaxReturn) {
      return (this.taxMinor ?? 0) + (this.adjustmentMinor ?? 0);
    },
  });
  @field openMinor = contains(NumberField, {
    computeVia: function (this: TaxReturn) {
      return (this.dueMinor ?? 0) - (this.paidMinor ?? 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: TaxReturn) {
      return `Sales tax ${this.agencyId ?? ''} · ${this.periodStart ?? ''} to ${this.periodEnd ?? ''}`;
    },
  });
  periodSales() {
    return salesOwedTo(
      this.invoices,
      this.journal,
      this.agencyId ?? '',
      this.periodStart ?? '',
      this.periodEnd ?? '',
    );
  }

  /** File it with the figures the filer saw; the desk sends the agency's markFiled in the same batch. */
  @operation static file = {
    base: 'transform',
    params: {
      taxableMinor: NumberField,
      taxMinor: NumberField,
      filedOn: StringField,
    },
    transformations: bxl`
      assert(.status == "open"; "Only an open return can be filed. This one is already filed.");
      assert([params("taxableMinor"), params("taxMinor"), .adjustmentMinor + 0 | floor] == [params("taxableMinor"), params("taxMinor"), .adjustmentMinor + 0]; "Amounts are in whole cents.");
      assert(params("filedOn") > .periodEnd; "A return is filed after its period ends.");
      .filedTaxableMinor = params("taxableMinor");
      .filedTaxMinor = params("taxMinor");
      .filedOn = params("filedOn");
      .filedBy = actor();
      .status = "filed";
    `,
  } satisfies OperationDeclaration;
  /** Record a payment against it. Sent in the same batch as the bank payment's post. */
  @operation static markPaid = {
    base: 'transform',
    params: { paymentNo: StringField, amountMinor: NumberField },
    transformations: bxl`
      assert(.status != "open"; "File the return before paying it.");
      assert(params("amountMinor") > 0; "A payment must be positive.");
      assert([.payments + [] | .[]] | all(. != params("paymentNo")); "That payment is already recorded on this return.");
      assert([.filedTaxMinor + .adjustmentMinor - .paidMinor - params("amountMinor")] | all(. >= 0); "That pays more than the return has open.");
      .paidMinor |= . + params("amountMinor");
      .payments = [.payments + [] | .[]] + [params("paymentNo")];
      .status = (if [.filedTaxMinor + .adjustmentMinor - .paidMinor] | all(. == 0) then "paid" else "filed" end);
    `,
  } satisfies OperationDeclaration;
  /** Take a payment back off it. Sent in the same batch as the payment's reversal. */
  @operation static unmarkPaid = {
    base: 'transform',
    params: { paymentNo: StringField, amountMinor: NumberField },
    transformations: bxl`
      assert([.payments + [] | .[]] | any(. == params("paymentNo")); "That payment isn't recorded on this return.");
      .paidMinor |= . - params("amountMinor");
      .payments = [.payments + [] | .[] | select(. != params("paymentNo"))];
      .status = "filed";
    `,
  } satisfies OperationDeclaration;

  static isolated = class extends Component<typeof TaxReturn> {
    get facts(): Fact[] {
      let m = this.args.model;
      return [
        { key: 'Agency', value: m.agencyId ?? '', mono: true },
        {
          key: 'Period',
          value: `${day(m.periodStart)} to ${day(m.periodEnd)}`,
        },
        { key: 'Taxable sales', value: money(m.taxableMinor) },
        { key: 'Tax collected', value: money(m.taxMinor) },
        ...((m.adjustmentMinor ?? 0)
          ? [
              {
                key: 'Adjustment',
                value: `${money(m.adjustmentMinor)}${m.adjustmentNote ? ' · ' + m.adjustmentNote : ''}`,
              },
            ]
          : []),
        { key: 'Due', value: money(m.dueMinor), strong: true },
        ...(m.filedOn
          ? [{ key: 'Filed', value: `${day(m.filedOn)} by ${m.filedBy ?? ''}` }]
          : []),
        { key: 'Paid', value: money(m.paidMinor) },
        ...((m.payments ?? []).length
          ? [{ key: 'Payments', value: (m.payments ?? []).join(', ') }]
          : []),
      ];
    }
    get note() {
      return this.args.model.status === 'open'
        ? "Open: its figures are this period's sales as they stand. Filing records them and locks the period with the agency."
        : undefined;
    }
    <template>
      <Sheet
        @eyebrow='Sales tax return'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.openMinor}}
        @figureLabel='Open'
        @status={{@model.status}}
        @note={{this.note}}
      ><Part @title='Return'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof TaxReturn> {
    <template>
      <Strip
        @eyebrow='Sales tax return'
        @title={{@model.cardTitle}}
        @figure={{money @model.dueMinor}}
        @meta={{@model.status}}
      />
    </template>
  };
  static fitted = class extends Component<typeof TaxReturn> {
    <template>
      <Fit
        @eyebrow='Sales tax return'
        @title={{@model.agencyId}}
        @figure={{money @model.dueMinor}}
        @meta={{@model.periodEnd}}
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
