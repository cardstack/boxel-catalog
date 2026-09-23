import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import DateField from '@cardstack/base/date';
import CalendarIcon from '@cardstack/boxel-icons/calendar';

import { Calendar, type CalendarEvent } from '../calendar';
import { stateColor } from '../state-pill';

export class CalendarExampleEvent extends FieldDef {
  static displayName = 'Calendar Example Event';

  @field title = contains(StringField);
  @field date = contains(DateField);
  @field kind = contains(StringField);
}

const KIND_COLORS = {
  meeting: stateColor('blue'),
  deadline: stateColor('red'),
  review: stateColor('amber'),
};

function toEvents(
  entries: CalendarExampleEvent[] | undefined,
  prefix: string,
): CalendarEvent[] {
  return (entries ?? [])
    .filter((e) => e?.title && e?.date)
    .map((e, i) => ({
      id: `${prefix}${i}`,
      title: e.title!,
      date: e.date!,
      kind: e.kind ?? undefined,
    }));
}

class CalendarExampleIsolated extends Component<typeof CalendarExample> {
  get events() {
    return toEvents(this.args.model?.events, 'e');
  }

  get projected() {
    return toEvents(this.args.model?.projected, 'p');
  }

  get initialDate() {
    return this.events[0]?.date;
  }

  // Weekends take no drops, so a chip dragged onto one snaps back.
  isWeekend = (date: Date) => date.getDay() === 0 || date.getDay() === 6;

  // Writes the new date onto the event so the example can be played with;
  // an app routes the move through its own command.
  reschedule = (event: CalendarEvent, newDate: Date) => {
    let index = Number(event.id?.slice(1));
    let entry = this.args.model?.events?.filter((e) => e?.title && e?.date)[
      index
    ];
    if (entry) {
      entry.date = newDate;
    }
  };

  <template>
    <div class='calendar-example'>
      <Calendar
        @events={{this.events}}
        @projected={{this.projected}}
        @kindColors={{KIND_COLORS}}
        @initialDate={{this.initialDate}}
        @onRescheduleEvent={{this.reschedule}}
        @isDisabledDate={{this.isWeekend}}
        @density={{true}}
      />
    </div>
    <style scoped>
      .calendar-example {
        padding: var(--boxel-sp);
      }
    </style>
  </template>
}

/**
 * A month of meetings, reviews and deadlines. One day holds five events so
 * the overflow toggle shows; projected check-ins render dashed; weekends
 * refuse drops; density tints the busy days; chips drag to reschedule.
 */
export class CalendarExample extends CardDef {
  static displayName = 'Calendar Example';
  static icon = CalendarIcon;

  @field events = containsMany(CalendarExampleEvent);
  @field projected = containsMany(CalendarExampleEvent);

  static isolated = CalendarExampleIsolated;
}
