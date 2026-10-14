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
        <RepeatIcon class='trigger-icon' />
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
          width: 1rem;
          height: 1rem;
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

  static edit = class Edit extends Component<typeof this> {
    <template>
      <div class='trigger-edit'>
        <section class='trigger-half'>
          <h4 class='trigger-h'>Calendar rhythm</h4>
          <@fields.calendar />
        </section>
        <section class='trigger-half'>
          <h4 class='trigger-h'>Usage rhythm</h4>
          <div class='trigger-grid'>
            <label class='trigger-l'>Every <@fields.meterThreshold /></label>
            <label class='trigger-l'>Unit <@fields.meterUnit /></label>
          </div>
          <label class='trigger-l trigger-check'>
            <@fields.whicheverFirst />
            <span>Whichever comes first (off = both must arrive)</span>
          </label>
        </section>
        <section class='trigger-half'>
          <h4 class='trigger-h'>Lead time</h4>
          <label class='trigger-l'>Raise the work order
            <@fields.leadDays />
            days before it is due</label>
        </section>
        <p class='trigger-summary-line'>{{@model.summary}}</p>
      </div>
      <style scoped>
        .trigger-edit {
          display: grid;
          gap: var(--boxel-sp);
        }
        .trigger-half {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .trigger-h {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .trigger-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
          gap: var(--boxel-sp-xs);
        }
        .trigger-l {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
          flex-wrap: wrap;
        }
        .trigger-check {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .trigger-summary-line {
          margin: 0;
          padding-top: var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
      </style>
    </template>
  };
}

export default MaintenanceTriggerField;
