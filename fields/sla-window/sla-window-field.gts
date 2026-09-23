import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import ClockIcon from '@cardstack/boxel-icons/clock';

import {
  DayWindowField,
  WEEKDAYS,
  minutesOfClock,
} from '@cardstack/catalog/cards/service-desk/schedule';

/**
 * The business-hours window an SLA clock runs in: timezone, working windows,
 * holidays. Pure calendar DATA — every bit of arithmetic lives in
 * `utils/sla.ts` (`addBusinessMinutes`, `businessMinutesBetween`), which this
 * field feeds via `businessSchedule`, the same shape the Schedule card
 * produces (`{ timeZone, windows: [{day, openMinutes, closeMinutes}],
 * holidays }`).
 *
 * Why a FieldDef when the Schedule CARD already exists: an applied SLA must
 * keep the window it was promised under, frozen at apply time — a later edit
 * to the shared Schedule must not silently rewrite history. Embedding the
 * window on the SLA record is what makes "as of" answerable a year later.
 * `DayWindowField` itself is reused from `schedule.gts`, so the two never
 * drift in shape.
 */
export class SlaWindowField extends FieldDef {
  static displayName = 'SLA Window';
  static icon = ClockIcon;

  @field timeZone = contains(StringField, {
    description: 'IANA zone, e.g. Asia/Kuala_Lumpur.',
  });
  @field windows = containsMany(DayWindowField);
  @field holidays = containsMany(DateField);

  @field title = contains(StringField, {
    computeVia: function (this: SlaWindowField) {
      let n = this.windows?.length ?? 0;
      if (n === 0) return 'Always on (24/7)';
      return `${n} window${n === 1 ? '' : 's'} · ${this.timeZone ?? 'UTC'}`;
    },
  });

  /**
   * The `utils/sla.ts` schedule shape. Empty `windows` means "always on" —
   * callers should fall back to ALWAYS_ON when this returns undefined.
   */
  get businessSchedule() {
    let windows = (this.windows ?? [])
      .filter((w) => w?.day)
      .map((w) => ({
        day: WEEKDAYS.indexOf(w.day as (typeof WEEKDAYS)[number]),
        openMinutes: minutesOfClock(w.opensAt as unknown as string),
        closeMinutes: minutesOfClock(w.closesAt as unknown as string) || 1440,
      }))
      .filter((w) => w.day >= 0);
    if (!windows.length) {
      return undefined;
    }
    return {
      timeZone: this.timeZone || 'UTC',
      windows,
      holidays: (this.holidays ?? [])
        .filter(Boolean)
        .map((d) => new Date(d as unknown as string | Date)),
    };
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='window'>
        <span class='window-tz'>{{if
            @model.timeZone
            @model.timeZone
            'UTC'
          }}</span>
        {{#if @model.windows.length}}
          <div class='window-days'><@fields.windows /></div>
        {{else}}
          <span class='window-always'>Always on — clock never pauses for hours</span>
        {{/if}}
        {{#if @model.holidays.length}}
          <span class='window-holidays'>{{@model.holidays.length}}
            holiday(s) excluded</span>
        {{/if}}
      </div>
      <style scoped>
        .window {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          font-size: var(--boxel-font-size-sm);
        }
        .window-tz {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .window-days {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
        }
        .window-always,
        .window-holidays {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='window-atom'>{{@model.title}}</span>
      <style scoped>
        .window-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

export default SlaWindowField;
