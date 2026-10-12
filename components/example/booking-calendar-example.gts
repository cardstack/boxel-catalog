import {
  CardDef,
  Component,
  FieldDef,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';

import {
  BookingCalendar,
  type BookingCalendarEvent,
} from '../booking-calendar';
import { stateColor } from '../state-pill';
import { toDate } from '../../fields/effective-period/effective-period-field';

const KIND_COLORS = {
  class: stateColor('blue'),
  workshop: stateColor('purple'),
};

export class BookableSessionField extends FieldDef {
  static displayName = 'Bookable Session';

  @field title = contains(StringField);
  @field date = contains(DateField);
  @field kind = contains(StringField);
  @field capacity = contains(NumberField);
  @field booked = contains(NumberField);
}

/**
 * A month of bookable sessions on the Booking Calendar: some with places
 * left, one nearly full and one sold out, so every availability state shows.
 */
export class BookingCalendarExample extends CardDef {
  static displayName = 'Booking Calendar Example';

  @field title = contains(StringField);
  @field sessions = containsMany(BookableSessionField);

  static isolated = class Isolated extends Component<typeof this> {
    get events(): BookingCalendarEvent[] {
      return (this.args.model.sessions ?? []).flatMap((s) => {
        let date = toDate(s?.date);
        return date && s?.title
          ? [
              {
                title: s.title,
                date,
                kind: s.kind ?? undefined,
                capacity: s.capacity ?? undefined,
                booked: s.booked ?? undefined,
              },
            ]
          : [];
      });
    }

    get firstDate(): Date | undefined {
      let dates = this.events.map((e) => e.date.getTime());
      return dates.length ? new Date(Math.min(...dates)) : undefined;
    }

    <template>
      <article class='bookings'>
        <h1>{{@model.title}}</h1>
        <BookingCalendar
          @events={{this.events}}
          @kindColors={{KIND_COLORS}}
          @initialDate={{this.firstDate}}
        />
      </article>
      <style scoped>
        .bookings {
          display: grid;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          color: var(--foreground);
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
        }
      </style>
    </template>
  };
}
