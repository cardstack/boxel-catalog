import {
  Component,
  FieldDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import enumField from '@cardstack/base/enum';
import CalendarEventIcon from '@cardstack/boxel-icons/calendar-event';

export const RELEASE_MODES = [
  { value: 'on_start', label: 'On cohort start' },
  { value: 'offset_days', label: 'Days after start' },
  { value: 'on_date', label: 'On a fixed date' },
  { value: 'manual', label: 'Manual release' },
];

export const ReleaseModeField = enumField(StringField, {
  displayName: 'Release Mode',
  options: RELEASE_MODES,
});

/**
 * When a module becomes visible to a cohort.
 *
 * A rule is a *plan*; the release itself is an event recorded on the Cohort
 * (`releases[]`, written by the Release Module command). The two are kept
 * apart on purpose: the plan says "week 3", the event says "released Tuesday
 * 09:14 by Dana", and a module that the instructor releases early does not
 * rewrite the plan.
 */
export class ReleaseRuleField extends FieldDef {
  static displayName = 'Release Rule';
  static icon = CalendarEventIcon;

  @field mode = contains(ReleaseModeField);
  @field offsetDays = contains(NumberField, {
    description: 'Used when mode is "Days after start".',
  });
  @field releaseDate = contains(DateField, {
    description: 'Used when mode is "On a fixed date".',
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='release-rule'>{{describeReleaseRule @model}}</span>
      <style scoped>
        .release-rule {
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground, var(--boxel-dark));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='release-rule-atom'>{{describeReleaseRule @model}}</span>
      <style scoped>
        .release-rule-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export function describeReleaseRule(
  rule: Partial<ReleaseRuleField> | null | undefined,
): string {
  switch (rule?.mode) {
    case 'on_start':
      return 'Releases on cohort start';
    case 'offset_days':
      return `Releases ${rule.offsetDays ?? 0} days after start`;
    case 'on_date':
      return rule.releaseDate
        ? `Releases ${new Date(rule.releaseDate).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}`
        : 'Releases on a fixed date (unset)';
    case 'manual':
      return 'Released manually';
    default:
      return 'Released manually';
  }
}

/**
 * The planned release moment for a cohort that starts on `cohortStart`.
 * `undefined` means "only when an instructor releases it".
 */
export function plannedReleaseDate(
  rule: Partial<ReleaseRuleField> | null | undefined,
  cohortStart: Date | string | null | undefined,
): Date | undefined {
  if (!rule) return undefined;
  if (rule.mode === 'on_date') {
    return rule.releaseDate ? new Date(rule.releaseDate) : undefined;
  }
  if (!cohortStart) return undefined;
  let start = new Date(cohortStart);
  if (rule.mode === 'on_start') return start;
  if (rule.mode === 'offset_days') {
    return new Date(start.getTime() + (rule.offsetDays ?? 0) * 86_400_000);
  }
  return undefined;
}

export default ReleaseRuleField;
