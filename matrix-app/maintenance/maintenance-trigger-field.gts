import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import RepeatIcon from '@cardstack/boxel-icons/repeat';
import RecurringPatternField from '@cardstack/catalog/fields/recurring-pattern/recurring-pattern';

import { triggerSummary } from './utils/recurrence';

/**
 * WHEN a repeating obligation falls due — a calendar rhythm, a usage
 * threshold, or both ("every 90 days or 500 running hours, whichever first").
 *
 * The calendar half IS the catalog's Recurring Pattern field (consumed, not
 * rebuilt); this field adds the meter half, the whichever-first rule and the
 * lead time the generator uses. All date math lives in
 * `utils/recurrence.ts` (`nextOccurrence`) — the Compute Next Occurrence
 * command exposes the same function — so a plan's computed, the calendar,
 * the runway and the generator can never disagree.
 *
 * Generic: a maintenance plan today; a contract obligation, a cohort
 * session or a duty rotation tomorrow.
 */
export class MaintenanceTriggerField extends FieldDef {
  static displayName = 'Maintenance Trigger';
  static icon = RepeatIcon;

  @field calendar = contains(RecurringPatternField);
  @field meterThreshold = contains(NumberField, {
    description:
      'Fire every N meter units (running hours, km, cycles). Leave empty for calendar-only.',
  });
  @field meterUnit = contains(StringField, {
    description: 'Display unit for the meter half — h, km, cycles.',
  });
  @field whicheverFirst = contains(BooleanField, {
    description:
      'When both halves exist: true = the earlier wins (default); false = both must arrive.',
  });
  @field leadDays = contains(NumberField, {
    description: 'Generate the work order this many days before the due date.',
  });

  @field summary = contains(StringField, {
    computeVia: function (this: MaintenanceTriggerField) {
      return triggerSummary(
        {
          calendar: this.calendar
            ? {
                pattern: this.calendar.pattern,
                interval: this.calendar.interval,
                daysOfWeek: this.calendar.daysOfWeek,
                dayOfMonth: this.calendar.dayOfMonth,
                monthOfYear: this.calendar.monthOfYear,
                startDate: this.calendar.startDate,
                endDate: this.calendar.endDate,
                occurrences: this.calendar.occurrences,
              }
            : undefined,
          meterThreshold: this.meterThreshold,
          whicheverFirst: this.whicheverFirst ?? true,
          leadDays: this.leadDays,
        },
        this.meterUnit,
      );
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='trigger'>
        <RepeatIcon class='trigger-icon' width='16' height='16' aria-hidden='true' />
        <span class='trigger-summary'>{{@model.summary}}</span>
      </div>
      <style scoped>
        .trigger {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          color: var(--foreground);
          font-size: var(--boxel-font-size-sm);
        }
        .trigger-icon {
          flex: none;
          color: var(--muted-foreground);
        }
        .trigger-summary {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='trigger-atom'>{{@model.summary}}</span>
      <style scoped>
        .trigger-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--foreground);
        }
      </style>
    </template>
  };
}

export default MaintenanceTriggerField;
