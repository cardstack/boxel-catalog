// Time worked for customers: who worked, on what, for how long, at what rate, and whether it's billed.
// Time posts nothing itself. Billable time becomes invoice lines, and the invoice and the time it
// bills are written in one batch, so time can't be billed twice; the desk's void puts it back.
import { CardDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import ClockIcon from '@cardstack/boxel-icons/clock';
import {
  operation,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
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

const hoursText = (milli: number | undefined) =>
  `${((milli ?? 0) / 1000).toLocaleString('en-US', { maximumFractionDigits: 3 })} h`;

export const timeState = (t: { billable?: boolean; billedInvoice?: string }) =>
  t.billedInvoice
    ? 'Billed'
    : t.billable === false
      ? 'Not billable'
      : 'Unbilled';

type BillableTime = {
  id?: string;
  worker?: string;
  description?: string;
  date?: string;
  serviceSku?: string;
  hours?: number;
  rateMinor?: number;
  projectId?: string;
};

/** An invoice line per activity, at its service and rate, naming the activity it bills. */
export const timeInvoiceLines = (
  acts: BillableTime[],
  incomeAccount: (sku: string | undefined) => string | undefined,
) =>
  acts.map((t) => ({
    sku: t.serviceSku,
    description: `${t.worker}: ${t.description || 'time'} (${t.date})`,
    qty: t.hours,
    priceMinor: t.rateMinor,
    amountMinor: Math.round(((t.rateMinor ?? 0) * (t.hours ?? 0)) / 1000),
    account: incomeAccount(t.serviceSku) || '4000',
    taxCode: null,
    cls: null,
    loc: null,
    project: t.projectId || null,
    timeId: t.id,
  }));

export class TimeActivity extends CardDef {
  static displayName = 'Time activity';
  static icon = ClockIcon;
  @field date = contains(IsoDateField);
  @field workerKind = contains(StringField); // employee or vendor
  @field worker = contains(StringField); // who worked: an employee or vendor ID
  @field customerId = contains(StringField);
  @field projectId = contains(StringField);
  @field serviceSku = contains(StringField); // the service item it bills as
  @field hours = contains(NumberField); // thousandths of an hour
  @field rateMinor = contains(NumberField); // billed per hour
  @field costRateMinor = contains(NumberField); // what an hour costs, for project profitability
  @field billable = contains(BooleanField);
  @field description = contains(StringField);
  @field billedInvoice = contains(StringField); // written only by markBilled and unmarkBilled
  @field enteredBy = contains(StringField);
  @field amountMinor = contains(NumberField, {
    computeVia: function (this: TimeActivity) {
      return Math.round(((this.rateMinor ?? 0) * (this.hours ?? 0)) / 1000);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: TimeActivity) {
      return `${this.worker ?? ''} · ${this.customerId ?? ''} · ${this.date ?? ''}`;
    },
  });

  /** Record the invoice that bills this time. The desk sends it in the batch that creates the invoice. */
  @operation static markBilled = {
    base: 'transform',
    params: { docNo: StringField },
    transformations: bxl`
      assert(.billable != false; "This time isn't billable.");
      assert(.billedInvoice == null; "This time is already billed.");
      assert(params("docNo") != null; "Name the invoice that bills this time.");
      .billedInvoice = params("docNo");
    `,
  } satisfies OperationDeclaration;
  /** Put time back to unbilled, when the invoice that billed it is voided or its line comes off the draft. */
  @operation static unmarkBilled = {
    base: 'transform',
    params: { docNo: StringField },
    transformations: bxl`
      assert(.billedInvoice == params("docNo"); "This time isn't billed by that invoice.");
      .billedInvoice = null;
    `,
  } satisfies OperationDeclaration;

  facts(): Fact[] {
    return [
      { key: 'Date', value: day(this.date) },
      { key: 'Who', value: `${this.worker ?? ''} (${this.workerKind ?? ''})` },
      { key: 'Customer', value: this.customerId ?? '' },
      ...(this.projectId ? [{ key: 'Project', value: this.projectId }] : []),
      { key: 'Service', value: this.serviceSku ?? '', mono: true },
      { key: 'Hours', value: hoursText(this.hours) },
      { key: 'Rate', value: money(this.rateMinor) },
      { key: 'Amount', value: money(this.amountMinor), strong: true },
      ...(this.description
        ? [{ key: 'Description', value: this.description }]
        : []),
      { key: 'Status', value: timeState(this) },
      ...(this.billedInvoice
        ? [{ key: 'Billed on', value: this.billedInvoice, mono: true }]
        : []),
    ];
  }

  static isolated = class extends Component<typeof TimeActivity> {
    get facts(): Fact[] {
      return this.args.model.facts?.() ?? [];
    }
    get state() {
      return timeState(this.args.model);
    }
    <template>
      <Sheet
        @eyebrow='Time activity'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.amountMinor}}
        @figureLabel='Billable'
        @status={{this.state}}
      ><Part @title='Time'><Facts @items={{this.facts}} /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof TimeActivity> {
    get meta() {
      return hoursText(this.args.model.hours);
    }
    <template>
      <Strip
        @eyebrow='Time'
        @title={{@model.cardTitle}}
        @figure={{money @model.amountMinor}}
        @meta={{this.meta}}
      />
    </template>
  };
  static fitted = class extends Component<typeof TimeActivity> {
    <template>
      <Fit
        @eyebrow='Time'
        @title={{@model.worker}}
        @figure={{money @model.amountMinor}}
        @meta={{@model.date}}
      />
    </template>
  };
}
