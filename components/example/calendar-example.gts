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

class CalendarExampleIsolated extends Component<typeof CalendarExample> {
  get events(): CalendarEvent[] {
    return (this.args.model?.events ?? [])
      .filter((e) => e?.title && e?.date)
      .map((e, i) => ({
        id: String(i),
        title: e.title!,
        date: e.date!,
        kind: e.kind ?? undefined,
      }));
  }

  get initialDate() {
    return this.events[0]?.date;
  }

  <template>
    <div class='calendar-example'>
      <Calendar
        @events={{this.events}}
        @kindColors={{KIND_COLORS}}
        @initialDate={{this.initialDate}}
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
 * A month of dated events of three kinds, so the calendar's chip colours and
 * several events on one day are visible together.
 */
export class CalendarExample extends CardDef {
  static displayName = 'Calendar Example';
  static icon = CalendarIcon;

  @field events = containsMany(CalendarExampleEvent);

  static isolated = CalendarExampleIsolated;
}
