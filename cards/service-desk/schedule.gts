import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from 'https://cardstack.com/base/card-api';
import DateField from 'https://cardstack.com/base/date';
import TimeField from 'https://cardstack.com/base/time';
import BooleanField from 'https://cardstack.com/base/boolean';
import enumField from 'https://cardstack.com/base/enum';
import CalendarCogIcon from '@cardstack/boxel-icons/calendar-cog';
import { Stat } from '@cardstack/pretui/components/stat';
import type { BusinessSchedule, DayWindow } from './utils/sla';
import { Chip } from '@cardstack/pretui/components/chip';
import { Avatar as PretAvatar } from '@cardstack/pretui/components/avatar';
import { FitTile } from '../shared/fit-tile';
import { FittedExtras } from '../procurement/vendor';
import {
  RecCard,
  RecHead,
  RecStats,
  RecBody,
  RecBlock,
  RecRow,
  RecLine,
} from './components/record';
import { IsoFrame } from '../shared/compact-sheet';

export const WEEKDAYS = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
] as const;

const SHORT_DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// 'Mon, Tue, Wed, Thu, Fri' is five things to read; 'Mon–Fri' is one. Only a
// genuinely contiguous run collapses — a Mon/Wed/Fri schedule stays listed, or
// the summary would claim the desk is open on days it is closed.
function contractDays(days: string[]): string {
  let indices = days
    .map((d) => WEEKDAYS.indexOf(d as never))
    .filter((i) => i >= 0)
    .sort((a, b) => a - b);
  if (!indices.length) {
    return '';
  }
  let contiguous = indices.every(
    (index, position) => position === 0 || index === indices[position - 1]! + 1,
  );
  if (contiguous && indices.length > 2) {
    return `${SHORT_DAYS[indices[0]!]}–${SHORT_DAYS[indices[indices.length - 1]!]}`;
  }
  return indices.map((i) => SHORT_DAYS[i]).join(', ');
}

const WeekdayField = enumField(StringField, {
  displayName: 'Weekday',
  options: WEEKDAYS as unknown as string[],
});

/** '09:00' → 540. Anything unparseable is treated as midnight. */
export function minutesOfClock(value?: string | null): number {
  let match = /^(\d{1,2}):(\d{2})$/.exec((value ?? '').trim());
  if (!match) {
    return 0;
  }
  let hours = Math.min(24, Math.max(0, Number(match[1])));
  let minutes = Math.min(59, Math.max(0, Number(match[2])));
  return hours * 60 + minutes;
}

/**
 * A DateField value as its 'YYYY-MM-DD' calendar day. DateField reads and
 * writes local calendar days, so the local getters give the day as entered;
 * the result is compared against `zonedParts().isoDate`.
 */
export function isoDay(at: Date): string {
  let month = String(at.getMonth() + 1).padStart(2, '0');
  let day = String(at.getDate()).padStart(2, '0');
  return `${at.getFullYear()}-${month}-${day}`;
}

/** Read the clock string out of a TimeField, with an em dash for "unset". */
function clockOf(time?: { value?: string | null } | null): string {
  return time?.value?.trim() || '—';
}

export function clockOfMinutes(minutes: number): string {
  let m = Math.max(0, Math.min(24 * 60, Math.round(minutes)));
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

/** One day's opening window. A day with no window never ticks. */
export class DayWindowField extends FieldDef {
  static displayName = 'Working Hours';
  static icon = CalendarCogIcon;

  @field day = contains(WeekdayField);
  // Base `TimeField`, not a raw string with an 'HH:MM' description. It already
  // owns the 24-hour picker, the locale-aware display and the validation this
  // field would otherwise restate — and restating it is how two spellings of
  // the same clock value end up in one realm.
  @field opensAt = contains(TimeField);
  @field closesAt = contains(TimeField);

  @field title = contains(StringField, {
    computeVia: function (this: DayWindowField) {
      if (!this.day) {
        return 'Unset day';
      }
      return `${this.day} ${clockOf(this.opensAt)}–${clockOf(this.closesAt)}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='dw'>
        <span class='dw-day'>{{@model.day}}</span>
        <span
          class='dw-hours'
        >{{@model.opensAt.value}}–{{@model.closesAt.value}}</span>
      </span>
      <style scoped>
        .dw {
          display: inline-flex;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
        .dw-day {
          font-weight: 600;
          color: var(--foreground);
        }
        .dw-hours {
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  // The three controls are the fields' own edit templates. TimeField already
  // renders the 24-hour picker and writes back through the model, so the
  // hand-wired BoxelInput pair this replaced was the same control built a
  // second time.
}

/**
 * When the SLA clock is allowed to run.
 *
 * A ticket raised at 4:55pm on Friday against a four-hour target is not late
 * on Saturday morning — this card is what makes that true, and it is the piece
 * that separates a real helpdesk from a countdown widget.
 */
export class Schedule extends CardDef {
  static displayName = 'Business Hours';
  static icon = CalendarCogIcon;

  @field name = contains(StringField);
  @field timeZone = contains(StringField, {
    description: 'IANA zone, e.g. Asia/Kuala_Lumpur',
  });
  @field windows = containsMany(DayWindowField);
  @field holidays = containsMany(DateField);
  @field isDefault = contains(BooleanField);

  @field title = contains(StringField, {
    computeVia: function (this: Schedule) {
      return this.name?.trim() || 'Untitled schedule';
    },
  });

  // Denormalized for fitted and for queue rows: a prerendered view cannot walk
  // `windows`, and even where it can, 'Mon–Fri 09:00–17:00' is what a person
  // actually wants to read.
  @field summary = contains(StringField, {
    computeVia: function (this: Schedule) {
      let open = (this.windows ?? []).filter((w) => w?.day);
      if (!open.length) {
        return 'Always on';
      }
      let byHours = new Map<string, string[]>();
      for (let w of open) {
        let key = `${w.opensAt?.value ?? '00:00'}–${w.closesAt?.value ?? '24:00'}`;
        byHours.set(key, [...(byHours.get(key) ?? []), w.day!]);
      }
      return [...byHours.entries()]
        .map(([hours, days]) => `${contractDays(days)} ${hours}`)
        .join(', ');
    },
  });

  // The fitted footer does not repeat `summary`, which the body already shows.
  // Whether this is the schedule new queues inherit is the one fact about a
  // Schedule that nothing else on the card states, so the footer carries it. Both
  // branches return text: an empty footer at 14 of 16 sizes is its own defect.
  @field defaultLabel = contains(StringField, {
    computeVia: function (this: Schedule) {
      return this.isDefault ? 'Default schedule' : 'Alternate schedule';
    },
  });

  @field holidayCount = contains(StringField, {
    computeVia: function (this: Schedule) {
      let n = (this.holidays ?? []).filter(Boolean).length;
      return n === 1 ? '1 holiday' : `${n} holidays`;
    },
  });

  /**
   * The plain shape `utils/sla` works in. Deliberately a getter, not a field:
   * commands read it at the moment they compute a deadline, and nothing about
   * it is worth storing twice.
   */
  get businessSchedule(): BusinessSchedule {
    let windows: DayWindow[] = (this.windows ?? [])
      .filter((w) => w?.day)
      .map((w) => ({
        day: WEEKDAYS.indexOf(w.day as never),
        openMinutes: minutesOfClock(w.opensAt?.value),
        closeMinutes: minutesOfClock(w.closesAt?.value),
      }))
      .filter((w) => w.day >= 0);
    return {
      timeZone: this.timeZone?.trim() || 'UTC',
      windows,
      holidays: (this.holidays ?? [])
        .filter(Boolean)
        .map((d) => isoDay(d as Date)),
    };
  }

  static isolated = class Isolated extends Component<typeof this> {
    // Minutes between two 'HH:MM' times; anything unparseable counts as 0.
    private mins(t: unknown): number {
      let m = /^(\d{1,2}):(\d{2})/.exec(clockOf(t as any) ?? '');
      return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
    }
    get open() {
      return (this.args.model?.windows ?? []).filter(
        (w) => w && this.mins(w.closesAt) > this.mins(w.opensAt),
      );
    }
    get hoursPerWeek() {
      let total = this.open.reduce(
        (n, w) => n + this.mins(w.closesAt) - this.mins(w.opensAt),
        0,
      );
      return `${Math.round(total / 6) / 10}h`;
    }
    get dayHint() {
      let n = new Set(this.open.map((w) => w.day)).size;
      return `${n} working ${n === 1 ? 'day' : 'days'}`;
    }
    get days() {
      const WEEK = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      let byDay = new Map(this.open.map((w) => [w.day, w]));
      return WEEK.map((day) => {
        let w = byDay.get(day as any);
        return {
          day,
          hours: w
            ? `${clockOf(w.opensAt as any)}–${clockOf(w.closesAt as any)}`
            : 'closed',
        };
      });
    }
    get holidayList() {
      return (this.args.model?.holidays ?? [])
        .filter(Boolean)
        .map((d) => new Date(d as any))
        .sort((a, b) => a.getTime() - b.getTime())
        .map((d) => ({
          date: d.toLocaleDateString('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
          }),
          weekday: d.toLocaleDateString('en-US', { weekday: 'long' }),
        }));
    }
    get holidayTotal() {
      return (this.args.model?.holidays ?? []).filter(Boolean).length;
    }
    get nextHoliday() {
      let now = Date.now();
      let next = (this.args.model?.holidays ?? [])
        .map((d) => (d ? new Date(d as any) : undefined))
        .filter((d): d is Date => !!d && d.getTime() >= now)
        .sort((a, b) => a.getTime() - b.getTime())[0];
      return next
        ? `next ${next.toLocaleDateString('en-GB', { month: 'short', day: 'numeric' })}`
        : 'none ahead';
    }
    get zoneShort() {
      let z = this.args.model?.timeZone ?? '';
      if (!z.includes('/')) return z || '—';
      let city = z.split('/').pop() ?? '';
      return (
        city
          .split('_')
          .map((w) => w[0] ?? '')
          .join('')
          .toUpperCase() || '—'
      );
    }
    <template>
      <IsoFrame>
        <RecCard @inset={{true}}>
          <RecHead @mark='BH' @title={{@model.title}} @sub={{@model.summary}}>
            <:status>{{#if @model.isDefault}}<Chip
                  @appearance='plain'
                  @tone='info'
                >default</Chip>{{/if}}<Chip
                @appearance='plain'
              >{{this.holidayTotal}} holidays</Chip></:status>
          </RecHead>
          <RecStats>
            <Stat
              @label='Hours / week'
              @tone='neutral'
              @value={{this.hoursPerWeek}}
              @hint={{this.dayHint}}
              @roll={{false}}
            />
            <Stat
              @label='Holidays'
              @tone='neutral'
              @value={{this.holidayTotal}}
              @hint={{this.nextHoliday}}
              @roll={{false}}
            />
            <Stat
              @label='Time zone'
              @tone='neutral'
              @value={{this.zoneShort}}
              @hint={{@model.timeZone}}
              @roll={{false}}
            />
          </RecStats>
          <RecBody>
            <:main>
              <RecBlock @title='Working hours'>
                {{#each this.days as |d|}}
                  <RecLine><:default><b>{{d.day}}</b></:default><:end><span
                        class='mono dim'
                      >{{d.hours}}</span></:end></RecLine>
                {{/each}}
              </RecBlock>
              <RecBlock @title='Holidays'>
                {{#each this.holidayList as |h|}}
                  <RecLine><:default><span
                        class='mono'
                      >{{h.date}}</span></:default><:end><span
                        class='dim'
                      >{{h.weekday}}</span></:end></RecLine>
                {{else}}
                  <RecLine><span class='dim'>No holidays.</span></RecLine>
                {{/each}}
              </RecBlock>
            </:main>
            <:side>
              <RecBlock @title='Details'>
                <RecRow @label='Time zone'>{{if
                    @model.timeZone
                    @model.timeZone
                    '—'
                  }}</RecRow>
                {{#each this.days as |d|}}
                  <RecRow @label={{d.day}} @mono={{true}}>{{d.hours}}</RecRow>
                {{/each}}
                <RecRow
                  @label='Hours / week'
                  @mono={{true}}
                >{{this.hoursPerWeek}}</RecRow>
                <RecRow
                  @label='Holidays'
                  @mono={{true}}
                >{{this.holidayTotal}}</RecRow>
                <RecRow @label='Next holiday'>{{this.nextHoliday}}</RecRow>
                <RecRow @label='Default'>{{if
                    @model.isDefault
                    'Yes'
                    'No'
                  }}</RecRow>
              </RecBlock>
            </:side>
          </RecBody>
        </RecCard>
      </IsoFrame>
      <style scoped>
        .mono {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
        }
        .dim {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <RecCard>
        <RecHead @mark='BH' @title={{@model.title}} @sub={{@model.summary}}>
          <:status>{{#if @model.isDefault}}<Chip
                @appearance='plain'
                @tone='info'
              >default</Chip>{{/if}}{{#if @model.holidayCount}}<Chip
                @appearance='plain'
              >{{@model.holidayCount}}</Chip>{{/if}}</:status>
        </RecHead>
        <RecRow @label='Time zone'>{{if
            @model.timeZone
            @model.timeZone
            '—'
          }}</RecRow>
        <RecRow @label='Open' @mono={{true}}>{{if
            @model.summary
            @model.summary
            '—'
          }}</RecRow>
        <RecRow @label='Holidays' @mono={{true}}>{{if
            @model.holidayCount
            @model.holidayCount
            '—'
          }}</RecRow>
      </RecCard>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>BH</span>
        <span class='nm'>{{@model.title}}</span>
        {{#if @model.timeZone}}<Chip
            @appearance='plain'
          >{{@model.timeZone}}</Chip>{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.3125rem;
          min-inline-size: 0;
          max-inline-size: 100%;
          font-size: 0.75rem;
        }
        .mark {
          flex: none;
          display: grid;
          place-items: center;
          inline-size: 1rem;
          block-size: 1rem;
          border: 1px solid var(--border);
          font: 600 0.5625rem/1 var(--font-mono);
          color: var(--muted-foreground);
        }
        .nm {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    // Whole ruled rows the tall fitted sizes add under the FitTile.
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Time zone', value: String((m as any)?.timeZone ?? '') || '—' },
        { key: 'Open', value: String((m as any)?.summary ?? '') || '—' },
        {
          key: 'Holidays',
          value: String((m as any)?.holidayCount ?? '') || '—',
        },
        {
          key: 'Default',
          value: String((m as any)?.defaultLabel ?? '') || '—',
        },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar><PretAvatar
                @name='BH'
                @shape='square'
                @size={{32}}
              /></:avatar>
            <:title>{{@model.title}}</:title>
            <:subtitle>{{@model.timeZone}}</:subtitle>
            <:status>{{#if @model.isDefault}}<Chip
                  @appearance='plain'
                  @tone='info'
                >default</Chip>{{/if}}</:status>
            <:fact>{{@model.summary}}</:fact>
          </FitTile>
        </:default>
      </FittedExtras>
    </template>
  };
}
