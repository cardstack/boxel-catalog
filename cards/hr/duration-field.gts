import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import { BoxelInput, BoxelSelect } from '@cardstack/boxel-ui/components';
import { not } from '@cardstack/boxel-ui/helpers';
import ClockIcon from '@cardstack/boxel-icons/clock';

export type DurationUnit =
  | 'minutes'
  | 'hours'
  | 'days'
  | 'weeks'
  | 'months'
  | 'years';

export const DURATION_UNITS: DurationUnit[] = [
  'minutes',
  'hours',
  'days',
  'weeks',
  'months',
  'years',
];

// Pick the unit that reads naturally for a span measured in days. A tenure of
// 1303 days is technically correct and useless — nobody thinks in four-digit
// day counts. Short spans stay in days because that IS how recruiters talk
// about them ("31 days to hire").
const DAYS_PER_UNIT: Record<DurationUnit, number> = {
  minutes: 1 / (24 * 60),
  hours: 1 / 24,
  days: 1,
  weeks: 7,
  months: 30,
  years: 365,
};

export function normalizedDuration(days?: number | null):
  | {
      value: number;
      unit: DurationUnit;
    }
  | undefined {
  if (days == null || !Number.isFinite(days)) {
    return undefined;
  }
  if (days >= 365) {
    return { value: Math.round((days / 365) * 10) / 10, unit: 'years' };
  }
  if (days >= 60) {
    return { value: Math.round((days / 30) * 10) / 10, unit: 'months' };
  }
  return { value: Math.round(days), unit: 'days' };
}

export function durationInDays(
  value?: number | null,
  unit?: string | null,
): number {
  if (value == null || !Number.isFinite(value)) {
    return 0;
  }
  let perUnit = DAYS_PER_UNIT[(unit ?? 'days') as DurationUnit] ?? 1;
  return value * perUnit;
}

export function durationLabel(
  value?: number | null,
  unit?: string | null,
): string {
  if (value == null || !Number.isFinite(value)) {
    return '—';
  }
  let u = (unit ?? 'days') as DurationUnit;
  let rounded = Math.round(value * 10) / 10;
  let singular: Record<DurationUnit, string> = {
    minutes: 'min',
    hours: rounded === 1 ? 'hour' : 'hours',
    days: rounded === 1 ? 'day' : 'days',
    weeks: rounded === 1 ? 'week' : 'weeks',
    months: rounded === 1 ? 'month' : 'months',
    years: rounded === 1 ? 'year' : 'years',
  };
  return `${rounded} ${singular[u]}`;
}

export function durationAtomLabel(
  value?: number | null,
  unit?: string | null,
): string {
  if (value == null || !Number.isFinite(value)) {
    return '—';
  }
  let abbrev: Record<DurationUnit, string> = {
    minutes: 'm',
    hours: 'h',
    days: 'd',
    weeks: 'w',
    months: 'mo',
    years: 'y',
  };
  let rounded = Math.round(value * 10) / 10;
  return `${rounded}${abbrev[(unit ?? 'days') as DurationUnit] ?? 'd'}`;
}

export class DurationField extends FieldDef {
  static displayName = 'Duration (single unit)';
  static icon = ClockIcon;

  @field value = contains(NumberField);
  @field unit = contains(StringField, {
    description: 'One of: minutes, hours, days, weeks, months, years',
  });

  @field label = contains(StringField, {
    computeVia: function (this: DurationField) {
      return durationLabel(this.value, this.unit);
    },
  });

  static edit = class Edit extends Component<typeof this> {
    units = DURATION_UNITS;

    get selectedUnit(): DurationUnit {
      return (this.args.model.unit as DurationUnit) ?? 'days';
    }

    setValue = (val: string) => {
      let parsed = parseFloat(val);
      this.args.model.value = Number.isFinite(parsed) ? parsed : undefined;
      if (!this.args.model.unit) {
        this.args.model.unit = 'days';
      }
    };

    setUnit = (unit: DurationUnit | null) => {
      if (!unit) {
        return;
      }
      this.args.model.unit = unit;
    };

    <template>
      <div class='duration-edit'>
        <BoxelInput
          class='duration-value'
          @type='number'
          @value={{@model.value}}
          @onInput={{this.setValue}}
          @disabled={{not @canEdit}}
        />
        <BoxelSelect
          class='duration-unit'
          @options={{this.units}}
          @selected={{this.selectedUnit}}
          @onChange={{this.setUnit}}
          @disabled={{not @canEdit}}
          as |unit|
        >
          {{unit}}
        </BoxelSelect>
      </div>
      <style scoped>
        .duration-edit {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .duration-value {
          max-width: 8rem;
        }
        .duration-unit {
          min-width: 7rem;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get label() {
      return durationLabel(this.args.model.value, this.args.model.unit);
    }

    <template>
      <span class='duration-pill'>
        <ClockIcon class='duration-icon' role='presentation' />
        {{this.label}}
      </span>
      <style scoped>
        .duration-pill {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
          border-radius: var(--boxel-border-radius-sm);
          border: 1px solid var(--border, var(--boxel-200));
          background: var(--muted, var(--boxel-100));
          color: var(--foreground, var(--boxel-dark));
          font-weight: 500;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.2;
        }
        .duration-icon {
          width: 0.875em;
          height: 0.875em;
          flex: none;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get label() {
      return durationAtomLabel(this.args.model.value, this.args.model.unit);
    }

    <template>
      <span class='duration-atom'>{{this.label}}</span>
      <style scoped>
        .duration-atom {
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
          line-height: 1;
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}
