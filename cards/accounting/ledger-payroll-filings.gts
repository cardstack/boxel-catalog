// One agency's payroll filing for one period: the 941, the NYS-45, the 940, the disability and paid
// family leave remittance, or the year's W-2s and W-3. While open its figures come from the
// period's standing runs; filing records them and locks the period with the agency, and payments
// against it come from the bank payments made for it. Nothing is e-filed.
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
import enumField from '@cardstack/base/enum';
import BookIcon from '@cardstack/boxel-icons/book-open';
import {
  operation,
  bxl,
  instance,
  params,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import { JournalMonth, journalPostings } from './ledger-journal';
import { PayrollRun } from './ledger-cash';
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
import { IsoDateField } from './ledger-dates';
import { standingRuns } from './payroll-calc';
import { formFigures, type FormFigures } from './payroll-forms';

export const PayrollFilingStatusField = enumField(StringField, {
  displayName: 'Payroll filing status',
  options: [
    { value: 'open', label: 'Open' },
    { value: 'filed', label: 'Filed' },
    { value: 'paid', label: 'Paid' },
  ],
});

/** What filing checks before it records the figures. */
export const FILE_CHECKS = `
      assert(.status == "open"; "Only an open filing can be filed. This one is already filed.");
      assert(params("filedOn") > .periodEnd; "A filing is filed after its period ends.");
      assert(params("dueMinor") >= 0; "What a filing says is due can't be negative.");
      assert([params("dueMinor") | floor] == [params("dueMinor")]; "Amounts are in whole cents.");`;

export class FilingLine extends FieldDef {
  static displayName = 'Form line';
  @field key = contains(StringField);
  @field label = contains(StringField);
  @field amountMinor = contains(NumberField);
  @field employeeId = contains(StringField);
}

export class PayrollFiling extends CardDef {
  static displayName = 'Payroll filing';
  static icon = BookIcon;
  @field agencyId = contains(StringField);
  @field form = contains(StringField);
  @field periodStart = contains(IsoDateField);
  @field periodEnd = contains(IsoDateField);
  @field status = contains(PayrollFilingStatusField); // only file and markPaid move it
  @field filedLines = containsMany(FilingLine); // written only by file
  @field filedDueMinor = contains(NumberField); // written only by file
  @field filedOn = contains(IsoDateField);
  @field filedBy = contains(StringField);
  @field paidMinor = contains(NumberField); // written only by markPaid and unmarkPaid
  @field payments = containsMany(StringField); // the bank payments made for it
  @field fromMonth = contains(StringField, {
    computeVia: function (this: PayrollFiling) {
      return (this.periodStart ?? '').slice(0, 7);
    },
  });
  @field toMonth = contains(StringField, {
    computeVia: function (this: PayrollFiling) {
      return (this.periodEnd ?? '').slice(0, 7);
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
  @field runs = linksToMany(() => PayrollRun, {
    query: {
      filter: {
        range: {
          date: { gte: '$this.periodStart', lte: '$this.periodEnd' },
        },
      },
      page: { size: 500 },
    },
  });
  @field lines = containsMany(FilingLine, {
    computeVia: function (this: PayrollFiling) {
      return this.status === 'open'
        ? this.figures().lines.map((l) => new FilingLine(l))
        : (this.filedLines ?? []).filter(Boolean);
    },
  });
  @field dueMinor = contains(NumberField, {
    computeVia: function (this: PayrollFiling) {
      return this.status === 'open'
        ? this.figures().dueMinor
        : (this.filedDueMinor ?? 0);
    },
  });
  @field openMinor = contains(NumberField, {
    computeVia: function (this: PayrollFiling) {
      return (this.dueMinor ?? 0) - (this.paidMinor ?? 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PayrollFiling) {
      return `${this.form ?? 'Payroll filing'} · ${this.periodStart ?? ''} to ${this.periodEnd ?? ''}`;
    },
  });

  /** The period's figures as they stand, from its standing runs. */
  figures(): FormFigures {
    let posts = journalPostings(this.journal, ['payroll']);
    let checks = standingRuns(
      (this.runs ?? []) as (PayrollRun | undefined)[],
      new Set(posts.map((p) => p.source)),
    ).flatMap((r) =>
      (r.paychecks ?? []).filter(Boolean).map((p) => ({
        employeeId: p!.employeeId,
        name: p!.name,
        grossMinor: p!.grossMinor,
        fitWagesMinor: p!.fitWagesMinor,
        fitMinor: p!.fitMinor,
        ssWagesMinor: p!.ssWagesMinor,
        ssMinor: p!.ssMinor,
        medicareWagesMinor: p!.medicareWagesMinor,
        medicareMinor: p!.medicareMinor,
        addlMedicareMinor: p!.addlMedicareMinor,
        stateWagesMinor: p!.stateWagesMinor,
        stateMinor: p!.stateMinor,
        deductions: (p!.deductions ?? []).filter(Boolean).map((d) => ({
          kind: d!.kind,
          amountMinor: d!.amountMinor,
        })),
      })),
    );
    return formFigures(
      this.agencyId ?? '',
      posts,
      checks,
      this.periodStart ?? '',
      this.periodEnd ?? '',
    );
  }

  /** File it with the figures the filer saw; the desk sends the agency's markFiled in the same batch. */
  @operation static file = {
    base: 'transform',
    params: {
      lines: FilingLine,
      dueMinor: NumberField,
      filedOn: StringField,
    },
    transformations: {
      $bxl: `${FILE_CHECKS}
      .filedLines = params("lines");
      .filedDueMinor = params("dueMinor");
      .filedOn = params("filedOn");
      .filedBy = actor();
      .status = (if params("dueMinor") == 0 then "paid" else "filed" end);
    `,
    },
  } as OperationDeclaration;
  /** Record a payment against it. Sent in the same batch as the bank payment's post. */
  @operation static markPaid = {
    base: 'transform',
    params: { paymentNo: StringField, amountMinor: NumberField },
    transformations: bxl`
      assert(.status != "open"; "File this period before paying it.");
      assert(params("amountMinor") > 0; "A payment must be positive.");
      assert([.payments + [] | .[]] | all(. != params("paymentNo")); "That payment is already recorded on this filing.");
      assert([.filedDueMinor - .paidMinor - params("amountMinor")] | all(. >= 0); "That pays more than this period has open.");
      .paidMinor |= . + params("amountMinor");
      .payments = [.payments + [] | .[]] + [params("paymentNo")];
      .status = (if [.filedDueMinor - .paidMinor] | all(. == 0) then "paid" else "filed" end);
    `,
  } satisfies OperationDeclaration;
  /** Take a payment back off it. Sent in the same batch as the payment's reversal. */
  @operation static unmarkPaid = {
    base: 'transform',
    params: { paymentNo: StringField, amountMinor: NumberField },
    transformations: bxl`
      assert([.payments + [] | .[]] | any(. == params("paymentNo")); "That payment isn't recorded on this filing.");
      .paidMinor |= . - params("amountMinor");
      .payments = [.payments + [] | .[] | select(. != params("paymentNo"))];
      .status = "filed";
    `,
  } satisfies OperationDeclaration;
  /** Open this agency's filing for its next period. */
  @operation static openNext = {
    base: 'create',
    of: () => PayrollFiling,
    params: { periodStart: StringField, periodEnd: StringField },
    fill: {
      agencyId: instance('agencyId'),
      form: instance('form'),
      periodStart: params('periodStart'),
      periodEnd: params('periodEnd'),
      status: 'open',
      paidMinor: 0,
    },
  } satisfies OperationDeclaration;

  facts(): Fact[] {
    return [
      { key: 'Agency', value: this.agencyId ?? '', mono: true },
      {
        key: 'Period',
        value: `${day(this.periodStart)} to ${day(this.periodEnd)}`,
      },
      ...(this.lines ?? []).filter(Boolean).map((l) => ({
        key: `${l!.key} · ${l!.label}`,
        value:
          l!.key === '1' ? String(l!.amountMinor ?? 0) : money(l!.amountMinor),
      })),
      { key: 'Due', value: money(this.dueMinor), strong: true },
      ...(this.filedOn
        ? [
            {
              key: 'Filed',
              value: `${day(this.filedOn)} by ${this.filedBy ?? ''}`,
            },
          ]
        : []),
      { key: 'Paid', value: money(this.paidMinor) },
      ...((this.payments ?? []).length
        ? [{ key: 'Payments', value: (this.payments ?? []).join(', ') }]
        : []),
    ];
  }
  static isolated = class extends Component<typeof PayrollFiling> {
    get facts() {
      return this.args.model.facts?.() ?? [];
    }
    get note() {
      return this.args.model.status === 'open'
        ? "Open: its figures are this period's runs as they stand. Filing records them and locks the period with the agency. The form is generated for someone to file; nothing is e-filed."
        : undefined;
    }
    <template>
      <Sheet
        @eyebrow='Payroll filing'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.openMinor}}
        @figureLabel='Open'
        @status={{@model.status}}
        @note={{this.note}}
      ><Part @title='Form'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PayrollFiling> {
    <template>
      <Strip
        @eyebrow='Payroll filing'
        @title={{@model.cardTitle}}
        @figure={{money @model.dueMinor}}
        @meta={{@model.status}}
      />
    </template>
  };
  static fitted = class extends Component<typeof PayrollFiling> {
    <template>
      <Fit
        @eyebrow='Payroll filing'
        @title={{@model.agencyId}}
        @figure={{money @model.dueMinor}}
        @meta={{@model.periodEnd}}
      />
    </template>
  };
}
