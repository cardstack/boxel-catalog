// Payroll on the books' side: the tax tables paychecks are worked out from, the agencies the taxes
// are owed to, and each employee's pay setup, linked to their HR Employee card. HR stays the record
// of who someone is; the books own how they're paid. Contractors stay vendors, paid by bill.
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import BookIcon from '@cardstack/boxel-icons/book-open';
import {
  operation,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import UserIcon from '@cardstack/boxel-icons/user';
import { Employee } from '../hr/employee';
import { Sheet, Part, Facts, Strip, Fit, money, type Fact } from './record-kit';
import { IsoDateField } from './ledger-dates';
import { PERIODS, PAYROLL_LIABILITIES, type PaySchedule } from './payroll-calc';

export const DEMO_TAX_NOTE =
  'Demo figures entered by hand, not tax advice. A payroll tax service would replace these tables behind the same lookup.';

const pct = (ratePpm: number | undefined) =>
  `${((ratePpm ?? 0) / 10000).toLocaleString('en-US', { maximumFractionDigits: 4 })}%`;

export const FilingStatusField = enumField(StringField, {
  displayName: 'Filing status',
  options: [
    { value: 'single', label: 'Single' },
    { value: 'married', label: 'Married filing jointly' },
    { value: 'head', label: 'Head of household' },
  ],
});
export const PayScheduleField = enumField(StringField, {
  displayName: 'Pay schedule',
  options: [
    { value: 'weekly', label: 'Weekly' },
    { value: 'biweekly', label: 'Every two weeks' },
    { value: 'semimonthly', label: 'Twice a month' },
    { value: 'monthly', label: 'Monthly' },
  ],
});
export const PayTypeField = enumField(StringField, {
  displayName: 'Pay type',
  options: [
    { value: 'salary', label: 'Salary' },
    { value: 'hourly', label: 'Hourly' },
  ],
});
export const DeductionKindField = enumField(StringField, {
  displayName: 'Deduction kind',
  options: [
    { value: 'retirement', label: 'Pre-tax retirement (401(k))' },
    { value: 'section125', label: 'Pre-tax benefits (section 125)' },
    { value: 'posttax', label: 'After tax' },
  ],
});

// ── tax tables ───────────────────────────────────────────────────────────────
export class TaxBracket extends FieldDef {
  static displayName = 'Tax bracket';
  @field filingStatus = contains(StringField);
  @field overMinor = contains(NumberField); // annual wages the rate starts above
  @field ratePpm = contains(NumberField);
}
export class StatusAmount extends FieldDef {
  static displayName = 'Amount by filing status';
  @field filingStatus = contains(StringField);
  @field amountMinor = contains(NumberField);
}

/** One tax's figures for one year, effective from a date. */
export class PayrollTaxTable extends CardDef {
  static displayName = 'Payroll tax table';
  static icon = BookIcon;
  @field tax = contains(StringField); // federal-income, social-security, medicare, futa, ny-income, ny-suta, ny-sdi, ny-pfl
  @field label = contains(StringField);
  @field year = contains(NumberField); // the year the figures come from
  @field effectiveFrom = contains(IsoDateField);
  @field agencyId = contains(StringField); // who the tax is owed to
  @field ratePpm = contains(NumberField); // the employee's rate
  @field employerRatePpm = contains(NumberField);
  @field wageBaseMinor = contains(NumberField);
  @field thresholdMinor = contains(NumberField);
  @field extraRatePpm = contains(NumberField);
  @field weeklyCapMinor = contains(NumberField);
  @field annualCapMinor = contains(NumberField);
  @field allowanceMinor = contains(NumberField);
  @field brackets = containsMany(TaxBracket);
  @field statusAmounts = containsMany(StatusAmount);
  @field source = contains(StringField); // where the figures were read from
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PayrollTaxTable) {
      return `${this.label ?? this.tax ?? 'Tax table'} · ${this.year ?? ''} figures`;
    },
  });

  facts(): Fact[] {
    let f: Fact[] = [
      { key: 'Tax', value: this.tax ?? '', mono: true },
      { key: 'Figures from', value: String(this.year ?? '') },
      { key: 'Effective from', value: this.effectiveFrom ?? '' },
      { key: 'Owed to', value: this.agencyId ?? '', mono: true },
    ];
    if (this.ratePpm)
      f.push({ key: 'Employee rate', value: pct(this.ratePpm) });
    if (this.employerRatePpm)
      f.push({ key: 'Employer rate', value: pct(this.employerRatePpm) });
    if (this.wageBaseMinor)
      f.push({ key: 'Wage base', value: money(this.wageBaseMinor) });
    if (this.thresholdMinor)
      f.push({
        key: `Extra ${pct(this.extraRatePpm)} above`,
        value: money(this.thresholdMinor),
      });
    if (this.weeklyCapMinor)
      f.push({ key: 'Most a week', value: money(this.weeklyCapMinor) });
    if (this.annualCapMinor)
      f.push({ key: 'Most a year', value: money(this.annualCapMinor) });
    if (this.allowanceMinor)
      f.push({ key: 'Per allowance', value: money(this.allowanceMinor) });
    for (let s of (this.statusAmounts ?? []).filter(Boolean))
      f.push({
        key: `Deduction · ${s!.filingStatus}`,
        value: money(s!.amountMinor),
      });
    for (let b of (this.brackets ?? []).filter(Boolean))
      f.push({
        key: `${b!.filingStatus} over ${money(b!.overMinor)}`,
        value: pct(b!.ratePpm),
      });
    if (this.source) f.push({ key: 'Source', value: this.source });
    return f;
  }

  static isolated = class extends Component<typeof PayrollTaxTable> {
    get facts() {
      return this.args.model.facts?.() ?? [];
    }
    <template>
      <Sheet
        @eyebrow='Payroll tax table'
        @title={{@model.cardTitle}}
        @meta={{@model.agencyId}}
        @note={{DEMO_TAX_NOTE}}
      ><Part @title='Figures'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PayrollTaxTable> {
    <template>
      <Strip
        @eyebrow='Tax table'
        @title={{@model.cardTitle}}
        @meta={{@model.effectiveFrom}}
      />
    </template>
  };
  static fitted = class extends Component<typeof PayrollTaxTable> {
    <template>
      <Fit
        @eyebrow='Tax table'
        @title={{@model.label}}
        @meta={{@model.effectiveFrom}}
      />
    </template>
  };
}

// ── agencies ─────────────────────────────────────────────────────────────────
/** Who payroll taxes are owed to, the liability account they wait in, and the form filed with it. */
export class PayrollAgency extends CardDef {
  static displayName = 'Payroll tax agency';
  static icon = BookIcon;
  @field agencyId = contains(StringField);
  @field name = contains(StringField);
  @field form = contains(StringField); // 941, 940, NYS-45, W-2…
  @field frequency = contains(StringField); // quarterly or annual
  @field liabilityAccount = contains(StringField);
  @field taxes = containsMany(StringField); // the tax keys it collects
  @field filedThrough = contains(IsoDateField); // written only by markFiled, when a filing is filed
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PayrollAgency) {
      return this.name ?? this.agencyId ?? 'Payroll tax agency';
    },
  });
  /** Refuse a payroll run dated in a period filed with this agency. Sent in the run's posting batch. */
  @operation static checkOpen = {
    base: 'transform',
    params: { date: StringField },
    transformations: bxl`
      assert(if .filedThrough == null then true else params("date") > .filedThrough end; "Payroll for that date has been filed with this agency. Date the run after the filed period; a correction goes in the next period.");
      .filedThrough = .filedThrough;
    `,
  } satisfies OperationDeclaration;
  /** Lock a filed period. Sent in the same batch as the filing's file. */
  @operation static markFiled = {
    base: 'transform',
    params: { periodStart: StringField, periodEnd: StringField },
    transformations: bxl`
      assert(if .filedThrough == null then true else params("periodStart") > .filedThrough end; "A filing for part of that period has already been filed with this agency.");
      assert(params("periodEnd") >= params("periodStart"); "A filing's period ends on or after it starts.");
      .filedThrough = params("periodEnd");
    `,
  } satisfies OperationDeclaration;
  facts(): Fact[] {
    return [
      { key: 'Agency', value: this.agencyId ?? '', mono: true },
      ...(this.filedThrough
        ? [{ key: 'Filed through', value: this.filedThrough }]
        : []),
      { key: 'Files', value: `${this.form ?? ''} · ${this.frequency ?? ''}` },
      { key: 'Liability account', value: this.liabilityAccount ?? '' },
      { key: 'Taxes', value: (this.taxes ?? []).join(', ') },
    ];
  }
  static isolated = class extends Component<typeof PayrollAgency> {
    get facts() {
      return this.args.model.facts?.() ?? [];
    }
    <template>
      <Sheet
        @eyebrow='Payroll tax agency'
        @title={{@model.cardTitle}}
        @meta={{@model.form}}
      ><Part @title='Agency'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PayrollAgency> {
    <template>
      <Strip
        @eyebrow='Payroll agency'
        @title={{@model.cardTitle}}
        @meta={{@model.form}}
      />
    </template>
  };
  static fitted = class extends Component<typeof PayrollAgency> {
    <template>
      <Fit
        @eyebrow='Payroll agency'
        @title={{@model.agencyId}}
        @meta={{@model.form}}
      />
    </template>
  };
}

// ── pay setup ────────────────────────────────────────────────────────────────
export class PayDeduction extends FieldDef {
  static displayName = 'Deduction';
  @field label = contains(StringField);
  @field kind = contains(DeductionKindField);
  @field amountMinor = contains(NumberField); // each paycheck
  @field ratePpm = contains(NumberField); // or a share of gross
  @field account = contains(StringField); // the liability it's owed onward on
}

/** How the books pay one employee. */
export class PaySetup extends CardDef {
  static displayName = 'Pay setup';
  static icon = UserIcon;
  @field employee = linksTo(() => Employee);
  @field employeeId = contains(StringField);
  @field name = contains(StringField); // as the paycheck shows it
  @field active = contains(BooleanField);
  @field payType = contains(PayTypeField);
  @field annualSalaryMinor = contains(NumberField); // empty: the HR card's salary
  @field hourlyRateMinor = contains(NumberField);
  @field defaultHoursMilli = contains(NumberField); // hours a period when no time is recorded
  @field schedule = contains(PayScheduleField);
  @field expenseAccount = contains(StringField);
  @field cls = contains(StringField);
  @field workState = contains(StringField);
  @field filingStatus = contains(FilingStatusField);
  @field allowances = contains(NumberField); // state withholding allowances
  @field federalCreditsMinor = contains(NumberField); // annual dependent credits (W-4 step 3)
  @field extraWithholdingMinor = contains(NumberField); // each paycheck (W-4 step 4c)
  @field deductions = containsMany(PayDeduction);
  @field salaryMinor = contains(NumberField, {
    computeVia: function (this: PaySetup) {
      if (this.payType !== 'salary') return undefined;
      if (this.annualSalaryMinor) return this.annualSalaryMinor;
      let hr = (this.employee as { salary?: number } | undefined)?.salary;
      return typeof hr === 'number' ? Math.round(hr * 100) : undefined;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PaySetup) {
      return `Pay · ${this.name ?? this.employeeId ?? ''}`;
    },
  });

  /** The plain shape the paycheck calculation reads. */
  calcInput() {
    return {
      employeeId: this.employeeId,
      name: this.name,
      payType: this.payType,
      annualSalaryMinor: this.salaryMinor,
      hourlyRateMinor: this.hourlyRateMinor,
      schedule: this.schedule,
      expenseAccount: this.expenseAccount,
      cls: this.cls,
      filingStatus: this.filingStatus,
      allowances: this.allowances,
      federalCreditsMinor: this.federalCreditsMinor,
      extraWithholdingMinor: this.extraWithholdingMinor,
      deductions: (this.deductions ?? []).filter(Boolean).map((d) => ({
        label: d!.label,
        kind: d!.kind,
        amountMinor: d!.amountMinor,
        ratePpm: d!.ratePpm,
        account: d!.account,
      })),
    };
  }
  /** Gross for one period: salary over the schedule's periods, or the rate times the usual hours. */
  periodGrossMinor() {
    let periods = PERIODS[this.schedule as PaySchedule];
    if (!periods) return 0;
    return this.payType === 'hourly'
      ? Math.round(
          ((this.hourlyRateMinor ?? 0) * (this.defaultHoursMilli ?? 0)) / 1000,
        )
      : Math.round((this.salaryMinor ?? 0) / periods);
  }
  facts(): Fact[] {
    return [
      { key: 'Employee', value: this.employeeId ?? '', mono: true },
      { key: 'Status', value: this.active === false ? 'Inactive' : 'Active' },
      {
        key: 'Pay',
        value:
          this.payType === 'hourly'
            ? `${money(this.hourlyRateMinor)} an hour`
            : `${money(this.salaryMinor)} a year`,
        strong: true,
      },
      { key: 'Schedule', value: this.schedule ?? '' },
      {
        key: 'Wages post to',
        value: `${this.expenseAccount ?? ''}${this.cls ? ' · ' + this.cls : ''}`,
      },
      { key: 'Work state', value: this.workState ?? '' },
      { key: 'Filing status', value: this.filingStatus ?? '' },
      { key: 'State allowances', value: String(this.allowances ?? 0) },
      ...((this.federalCreditsMinor ?? 0)
        ? [{ key: 'Dependent credits', value: money(this.federalCreditsMinor) }]
        : []),
      ...((this.extraWithholdingMinor ?? 0)
        ? [
            {
              key: 'Extra withholding',
              value: money(this.extraWithholdingMinor),
            },
          ]
        : []),
      ...(this.deductions ?? []).filter(Boolean).map((d) => ({
        key: `${d!.label ?? 'Deduction'} (${d!.kind ?? ''})`,
        value: `${d!.ratePpm ? pct(d!.ratePpm) : money(d!.amountMinor)} → ${d!.account ?? ''}`,
      })),
    ];
  }
  static isolated = class extends Component<typeof PaySetup> {
    get facts() {
      return this.args.model.facts?.() ?? [];
    }
    get gross() {
      return this.args.model.periodGrossMinor?.() ?? 0;
    }
    <template>
      <Sheet
        @eyebrow='Pay setup'
        @title={{@model.name}}
        @meta={{@model.employee.role}}
        @figureMinor={{this.gross}}
        @figureLabel='Gross a period'
        @status={{if @model.active 'Active' 'Inactive'}}
      ><Part @title='How they are paid'><Facts
            @items={{this.facts}}
          /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof PaySetup> {
    get gross() {
      return money(this.args.model.periodGrossMinor?.() ?? 0);
    }
    <template>
      <Strip
        @eyebrow='Pay setup'
        @title={{@model.name}}
        @figure={{this.gross}}
        @meta={{@model.schedule}}
      />
    </template>
  };
  static fitted = class extends Component<typeof PaySetup> {
    get gross() {
      return money(this.args.model.periodGrossMinor?.() ?? 0);
    }
    <template>
      <Fit
        @eyebrow='Pay setup'
        @title={{@model.name}}
        @figure={{this.gross}}
        @meta={{@model.schedule}}
      />
    </template>
  };
}

// ── paychecks ────────────────────────────────────────────────────────────────
export class PaycheckDeduction extends FieldDef {
  static displayName = 'Paycheck deduction';
  @field label = contains(StringField);
  @field kind = contains(StringField);
  @field account = contains(StringField);
  @field amountMinor = contains(NumberField);
}
/** One employee's paycheck in a run: gross, each tax and deduction, net, and the wages each tax is on. */
export class Paycheck extends FieldDef {
  static displayName = 'Paycheck';
  @field employeeId = contains(StringField);
  @field name = contains(StringField);
  @field expenseAccount = contains(StringField);
  @field cls = contains(StringField);
  @field hoursMilli = contains(NumberField);
  @field grossMinor = contains(NumberField);
  @field deductions = containsMany(PaycheckDeduction);
  @field fitWagesMinor = contains(NumberField);
  @field fitMinor = contains(NumberField);
  @field ssWagesMinor = contains(NumberField);
  @field ssMinor = contains(NumberField);
  @field medicareWagesMinor = contains(NumberField);
  @field medicareMinor = contains(NumberField);
  @field addlMedicareMinor = contains(NumberField);
  @field stateWagesMinor = contains(NumberField);
  @field stateMinor = contains(NumberField);
  @field sdiMinor = contains(NumberField);
  @field pflMinor = contains(NumberField);
  @field netMinor = contains(NumberField);
  @field erSsMinor = contains(NumberField);
  @field erMedicareMinor = contains(NumberField);
  @field futaWagesMinor = contains(NumberField);
  @field futaMinor = contains(NumberField);
  @field sutaWagesMinor = contains(NumberField);
  @field sutaMinor = contains(NumberField);
  @field ytdGrossMinor = contains(NumberField);
  @field ytdNetMinor = contains(NumberField);
}

/** A paycheck's stub: gross, each tax, each deduction, net and the year to date. */
export const stubFacts = (p: {
  grossMinor?: number;
  hoursMilli?: number | null;
  fitMinor?: number;
  ssMinor?: number;
  medicareMinor?: number;
  addlMedicareMinor?: number;
  stateMinor?: number;
  sdiMinor?: number;
  pflMinor?: number;
  netMinor?: number;
  ytdGrossMinor?: number;
  ytdNetMinor?: number;
  deductions?: ({ label?: string; amountMinor?: number } | undefined)[];
}): Fact[] => [
  {
    key: 'Gross',
    value: `${money(p.grossMinor)}${p.hoursMilli ? ` · ${p.hoursMilli / 1000} h` : ''}`,
    strong: true,
  },
  ...(p.deductions ?? []).filter(Boolean).map((d) => ({
    key: d!.label ?? 'Deduction',
    value: money(d!.amountMinor),
  })),
  { key: 'Federal income tax', value: money(p.fitMinor) },
  { key: 'Social Security', value: money(p.ssMinor) },
  {
    key: 'Medicare',
    value: money((p.medicareMinor ?? 0) + (p.addlMedicareMinor ?? 0)),
  },
  { key: 'NY income tax', value: money(p.stateMinor) },
  { key: 'NY disability', value: money(p.sdiMinor) },
  { key: 'NY paid family leave', value: money(p.pflMinor) },
  { key: 'Net pay', value: money(p.netMinor), strong: true },
  { key: 'Gross, year to date', value: money(p.ytdGrossMinor) },
  { key: 'Net, year to date', value: money(p.ytdNetMinor) },
];

const SUMMED: [string, string][] = [
  [
    'withholdingMinor',
    '[.fitMinor, .ssMinor, .medicareMinor, .addlMedicareMinor, .stateMinor, .sdiMinor, .pflMinor] | add',
  ],
  ['deductionsMinor', '[.deductions[].amountMinor] + [0] | add'],
  [
    'employerTaxMinor',
    '[.erSsMinor, .erMedicareMinor, .futaMinor, .sutaMinor] | add',
  ],
  ['netMinor', '.netMinor'],
  ['fitMinor', '.fitMinor'],
  ['ssWagesMinor', '.ssWagesMinor'],
  ['ssTaxMinor', '[.ssMinor, .erSsMinor] | add'],
  ['medicareWagesMinor', '.medicareWagesMinor'],
  [
    'medicareTaxMinor',
    '[.medicareMinor, .erMedicareMinor, .addlMedicareMinor] | add',
  ],
  ['stateWagesMinor', '.stateWagesMinor'],
  ['stateTaxMinor', '.stateMinor'],
  ['sdiPflMinor', '[.sdiMinor, .pflMinor] | add'],
  ['futaWagesMinor', '.futaWagesMinor'],
  ['futaMinor', '.futaMinor'],
  ['sutaWagesMinor', '.sutaWagesMinor'],
  ['sutaMinor', '.sutaMinor'],
];
const ifPaychecks = (cond: string) =>
  `if (.paychecks | length) == 0 then true else (${cond}) end`;
const AMOUNTS =
  '.grossMinor, .netMinor, .fitMinor, .ssMinor, .medicareMinor, .addlMedicareMinor, .stateMinor, .sdiMinor, .pflMinor, .erSsMinor, .erMedicareMinor, .futaMinor, .sutaMinor, .deductions[].amountMinor';
/**
 * The checks a run with paychecks adds to its post: each paycheck adds up, its amounts are whole
 * cents and not negative, the run's totals are the sums of its paychecks, and every account it
 * posts to is in the chart.
 */
export const PAYCHECK_CHECKS = `
      assert(${ifPaychecks(`[.paychecks[] | ${AMOUNTS}] | all(. >= 0)`)}; "Paycheck amounts can't be negative.");
      assert(${ifPaychecks(`[.paychecks[] | ${AMOUNTS} | floor] == [.paychecks[] | ${AMOUNTS}]`)}; "Paycheck amounts are in whole cents.");
      assert(${ifPaychecks(`[.paychecks[] | .grossMinor == ([.netMinor, .fitMinor, .ssMinor, .medicareMinor, .addlMedicareMinor, .stateMinor, .sdiMinor, .pflMinor] + [.deductions[].amountMinor] | add)] | all(. == true)`)}; "Each paycheck's gross must equal its net plus its taxes and deductions.");
      assert(${ifPaychecks(`([.paychecks[].grossMinor] | add) == ([.wages[].amountMinor] + [0] | add)`)}; "A payroll run's wages must equal its paychecks' gross.");
      assert(${ifPaychecks(`[${SUMMED.map(([f, e]) => `(.${f} + 0) == ([.paychecks[] | (${e})] + [0] | add)`).join(', ')}] | all(. == true)`)}; "A payroll run's totals must be the sums of its paychecks.");
      assert(${ifPaychecks(`if realmConfig().chart == null then true else ((${JSON.stringify(Object.values(PAYROLL_LIABILITIES).map((l) => l.account))} + [.paychecks[].deductions[].account]) - realmConfig().chart | length == 0) end`)}; "An account a paycheck posts to isn't in the chart of accounts. Add it to the chart, then post.");`;
