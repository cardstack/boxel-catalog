// Recurring transactions: a template holds an invoice, bill or journal entry, and its schedule says
// when the next one is due. Running it creates the draft and moves the template on, in one batch; the
// draft's number is the template ID and the run date, so one run can't make two.
import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import RepeatIcon from '@cardstack/boxel-icons/repeat';
import {
  operation,
  bxl,
  type OperationDeclaration,
} from '@cardstack/base/operations';
import RecurringPatternField from '@cardstack/catalog/fields/recurring-pattern/recurring-pattern';
import {
  nextCalendarOccurrence,
  dayKey,
} from '@cardstack/catalog/cards/maintenance/utils/recurrence';
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
import { SaleLine } from './ledger-sales';
import { BillLine } from './ledger-cards';
import { EntryLine } from './ledger-cash';

export const TEMPLATE_KINDS: Record<string, string> = {
  invoice: 'Invoice',
  bill: 'Bill',
  journal: 'Journal entry',
};

/** The date a template runs next: its `nextDate`, or its schedule's start before its first run. */
export function dueDateOf(t: {
  nextDate?: string;
  runCount?: number;
  schedule?: { startDate?: unknown };
}): string {
  if (t.nextDate) return t.nextDate;
  if (t.runCount) return '';
  let start = t.schedule?.startDate as unknown;
  return start instanceof Date
    ? dayKey(start)
    : typeof start === 'string'
      ? start.slice(0, 10)
      : '';
}

/**
 * The run after `date`, by the template's schedule, or empty when the schedule has run out. Plain
 * dates in and out (yyyy-mm-dd), so the desk can work out what an operation can't: BXL has no
 * calendar arithmetic.
 */
export function nextRunAfter(
  schedule: RecurringPatternField | undefined,
  date: string,
  runCount: number,
): string {
  let next = nextCalendarOccurrence(schedule as never, date, runCount);
  return next ? dayKey(next) : '';
}

export class RecurringTemplate extends CardDef {
  static displayName = 'Recurring template';
  static icon = RepeatIcon;
  @field templateId = contains(StringField);
  @field name = contains(StringField);
  @field docKind = contains(StringField); // invoice, bill or journal
  @field party = contains(StringField); // the customer ID for an invoice, the vendor ID for a bill
  @field type = contains(StringField); // scheduled, reminder or unscheduled, as QuickBooks has them
  @field schedule = contains(RecurringPatternField);
  @field daysInAdvance = contains(NumberField); // a scheduled run creates its draft this many days early
  @field nextDate = contains(IsoDateField); // empty: the schedule has run out, or it's unscheduled
  @field lastRunDate = contains(IsoDateField);
  @field runCount = contains(NumberField); // every run, scheduled or by hand
  @field scheduledRuns = contains(NumberField); // the runs the schedule counts toward its limit
  @field paused = contains(BooleanField);
  @field memo = contains(StringField);
  @field taxCode = contains(StringField); // an invoice's tax code
  @field saleLines = containsMany(SaleLine); // an invoice's lines
  @field billLines = containsMany(BillLine); // a bill's lines
  @field entryLines = containsMany(EntryLine); // a journal entry's lines
  @field preparer = contains(StringField); // a journal entry's preparer
  @field totalMinor = contains(NumberField, {
    computeVia: function (this: RecurringTemplate) {
      let lines =
        this.docKind === 'journal'
          ? (this.entryLines ?? []).map((l) => l?.debitMinor ?? 0)
          : (
              (this.docKind === 'bill' ? this.billLines : this.saleLines) ?? []
            ).map((l) => l?.amountMinor ?? 0);
      return lines.reduce((n, a) => n + a, 0);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: RecurringTemplate) {
      return this.name || this.templateId || 'Recurring template';
    },
  });

  /** Mark a scheduled or reminder run done and move to the next date, which the caller works out from
   *  the schedule. The desk sends it with the run's draft. */
  @operation static advance = {
    base: 'transform',
    params: { runDate: StringField, nextDate: StringField },
    transformations: bxl`
      assert(.paused != true; "This template is paused. Resume it to run it.");
      assert(.type != "unscheduled"; "An unscheduled template runs by hand; use ran.");
      assert(if .nextDate == null then true else params("runDate") == .nextDate end; "That run isn't the one due. Reload the template and run what's due.");
      assert(if params("nextDate") == null then true else params("nextDate") > params("runDate") end; "The next run must come after this one.");
      .lastRunDate = params("runDate");
      .nextDate = params("nextDate");
      .runCount |= if . == null then 1 else . + 1 end;
      .scheduledRuns |= if . == null then 1 else . + 1 end;
    `,
  } satisfies OperationDeclaration;
  /** Record a run made by hand, without moving the schedule. */
  @operation static ran = {
    base: 'transform',
    params: { runDate: StringField },
    transformations: bxl`
      assert(.paused != true; "This template is paused. Resume it to run it.");
      assert(if .lastRunDate == null then true else params("runDate") != .lastRunDate end; "This template already ran on that day.");
      .lastRunDate = params("runDate");
      .runCount |= if . == null then 1 else . + 1 end;
    `,
  } satisfies OperationDeclaration;
  @operation static pause = {
    base: 'transform',
    transformations: bxl`
      assert(.paused != true; "This template is already paused.");
      .paused = true;
    `,
  } satisfies OperationDeclaration;
  @operation static resume = {
    base: 'transform',
    transformations: bxl`
      assert(.paused == true; "This template isn't paused.");
      .paused = false;
    `,
  } satisfies OperationDeclaration;

  facts(): Fact[] {
    return [
      { key: 'Creates', value: TEMPLATE_KINDS[this.docKind ?? ''] ?? '' },
      ...(this.party ? [{ key: 'For', value: this.party }] : []),
      { key: 'Type', value: this.type ?? '' },
      ...(this.nextDate ? [{ key: 'Next', value: day(this.nextDate) }] : []),
      ...(this.daysInAdvance
        ? [{ key: 'Days in advance', value: String(this.daysInAdvance) }]
        : []),
      ...(this.lastRunDate
        ? [{ key: 'Last run', value: day(this.lastRunDate) }]
        : []),
      { key: 'Runs so far', value: String(this.runCount ?? 0) },
      { key: 'Amount', value: money(this.totalMinor), strong: true },
      ...(this.paused ? [{ key: 'Paused', value: 'Yes' }] : []),
    ];
  }

  static isolated = class extends Component<typeof RecurringTemplate> {
    get facts(): Fact[] {
      return this.args.model.facts?.() ?? [];
    }
    <template>
      <Sheet
        @eyebrow='Recurring template'
        @title={{@model.cardTitle}}
        @figureMinor={{@model.totalMinor}}
        @figureLabel='Each run'
        @status={{if @model.paused 'Paused' 'Active'}}
      ><Part @title='The template'><Facts @items={{this.facts}} /></Part><Part
          @title='Schedule'
        ><@fields.schedule @format='embedded' /></Part></Sheet>
    </template>
  };
  static embedded = class extends Component<typeof RecurringTemplate> {
    <template>
      <Strip
        @eyebrow='Recurring'
        @title={{@model.cardTitle}}
        @figure={{money @model.totalMinor}}
        @meta={{@model.nextDate}}
      />
    </template>
  };
  static fitted = class extends Component<typeof RecurringTemplate> {
    <template>
      <Fit
        @eyebrow='Recurring'
        @title={{@model.cardTitle}}
        @figure={{money @model.totalMinor}}
        @meta={{@model.nextDate}}
      />
    </template>
  };
}
