import { Component, StringField } from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import UserCheckIcon from '@cardstack/boxel-icons/user-check';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { Hue } from '@cardstack/catalog/components/state-pill';

/**
 * How one learner turned up to one live lesson. An enum, not a lifecycle —
 * nothing "transitions" from late to present; the instructor simply corrects
 * the mark. Which marks count as attended is a fact about the completion rule
 * (`countsAsAttended`), not about the enum.
 */
export const ATTENDANCE_STATUSES = [
  { value: 'present', label: 'Present' },
  { value: 'late', label: 'Late' },
  { value: 'absent', label: 'Absent' },
  { value: 'excused', label: 'Excused' },
];

export const ATTENDANCE_HUES: Record<string, Hue> = {
  present: 'green',
  late: 'amber',
  absent: 'red',
  excused: 'slate',
};

const Base = enumField(StringField, {
  displayName: 'Attendance Status',
  icon: UserCheckIcon,
  options: ATTENDANCE_STATUSES,
});

export class AttendanceStatusField extends Base {
  static displayName = 'Attendance Status';

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <StatePill
        @label={{attendanceLabel @model}}
        @hue={{attendanceHue @model}}
        @dot={{true}}
      />
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <StatePill
        @label={{attendanceLabel @model}}
        @hue={{attendanceHue @model}}
      />
    </template>
  };
}

export function attendanceLabel(v?: string | null): string {
  return ATTENDANCE_STATUSES.find((s) => s.value === v)?.label ?? 'Unmarked';
}

export function attendanceHue(v?: string | null): Hue {
  return ATTENDANCE_HUES[v ?? ''] ?? 'slate';
}

/** Present, late and excused all count toward the attendance requirement. */
export function countsAsAttended(v?: string | null): boolean {
  return v === 'present' || v === 'late' || v === 'excused';
}

export default AttendanceStatusField;
