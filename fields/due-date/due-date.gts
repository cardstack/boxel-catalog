import { Component } from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import CalendarClockIcon from '@cardstack/boxel-icons/calendar-clock';
import { FormatDate } from '@cardstack/pretui/components/format-date';

import { StatePill, type Hue } from '../../components/state-pill';
import { UnsetMarker } from '../../components/unset-marker';
import { validDate } from '../../utils/valid-date';

/**
 * A calendar day something is expected by. The block states calendar facts,
 * how far away the day is and whether it has passed, and nothing else: it
 * cannot know the record completed, was paid, or was cancelled, so a consumer
 * whose lifecycle ends renders the raw date itself instead of mounting these
 * templates. Serializes exactly like DateField (`YYYY-MM-DD`), so an existing
 * `dueDate: DateField` upgrades in place.
 */
export type Dueness = 'overdue' | 'today' | 'soon' | 'later';

const SOON_DAYS = 7;

/** Whole calendar days from today; negative = past. Local calendar, not UTC instants. */
export function dueDays(value: Date | null | undefined): number | undefined {
  let date = validDate(value);
  if (!date) {
    return undefined;
  }
  let now = new Date();
  let today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  let due = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate());
  return Math.round((due - today) / 86400000);
}

export function dueness(value: Date | null | undefined): Dueness | undefined {
  let days = dueDays(value);
  if (days === undefined) {
    return undefined;
  }
  if (days < 0) {
    return 'overdue';
  }
  if (days === 0) {
    return 'today';
  }
  return days <= SOON_DAYS ? 'soon' : 'later';
}

const DUENESS_HUE: Record<Dueness, Hue> = {
  overdue: 'red',
  today: 'orange',
  soon: 'amber',
  later: 'slate',
};

function phrase(days: number): string {
  if (days < 0) {
    let n = -days;
    return n === 1 ? '1 day overdue' : `${n} days overdue`;
  }
  if (days === 0) {
    return 'due today';
  }
  if (days === 1) {
    return 'due tomorrow';
  }
  return `due in ${days} days`;
}

function shortDate(value: Date): string {
  return new Intl.DateTimeFormat(undefined, {
    day: 'numeric',
    month: 'short',
  }).format(value);
}

export class DueDateField extends DateField {
  static displayName = 'Due Date';
  static icon = CalendarClockIcon;

  static embedded = class Embedded extends Component<typeof this> {
    get days() {
      return dueDays(this.args.model);
    }
    get date() {
      return validDate(this.args.model);
    }
    get phrase() {
      return this.days === undefined ? undefined : phrase(this.days);
    }
    get hue() {
      let state = dueness(this.args.model);
      return state ? DUENESS_HUE[state] : undefined;
    }
    get isQuiet() {
      // A far-off date is information, not a signal: no pill fill.
      return dueness(this.args.model) === 'later';
    }
    <template>
      {{#if this.date}}
        <span class='due'>
          <FormatDate
            class='date'
            @date={{this.date}}
            @day='numeric'
            @month='short'
            @year='numeric'
          />
          <StatePill
            @label={{this.phrase}}
            @hue={{this.hue}}
            @chrome={{this.isQuiet}}
          />
        </span>
      {{else}}
        <UnsetMarker @label='No due date' />
      {{/if}}
      <style scoped>
        .due {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .date {
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get label() {
      let d = validDate(this.args.model);
      return d ? shortDate(d) : undefined;
    }
    get title() {
      let days = dueDays(this.args.model);
      return days === undefined ? undefined : phrase(days);
    }
    get hue() {
      let state = dueness(this.args.model);
      return state ? DUENESS_HUE[state] : undefined;
    }
    get isQuiet() {
      return dueness(this.args.model) === 'later';
    }
    <template>
      {{#if this.label}}
        <span title={{this.title}}>
          <StatePill
            @label={{this.label}}
            @hue={{this.hue}}
            @chrome={{this.isQuiet}}
          />
        </span>
      {{else}}
        <UnsetMarker @label='No due date' />
      {{/if}}
    </template>
  };
}

export default DueDateField;
