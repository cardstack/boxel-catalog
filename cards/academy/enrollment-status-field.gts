import { markDefinition } from '@cardstack/base';
import UserCheckIcon from '@cardstack/boxel-icons/user-check';

import {
  statusField,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';

/**
 * A learner's standing on one cohort — a CONFIGURATION of the shared
 * `statusField` factory, which supplies the constrained dropdown, the pill
 * rendering and the transition guard. This module contributes only the
 * vocabulary and the legal moves.
 *
 * `completed` is written by Issue Certificate (or by an instructor closing a
 * cohort) and is terminal; a withdrawn learner may be re-activated because
 * "I dropped for a month and came back" is a real story a cohort tells.
 */
export const ENROLLMENT_STATUSES: StatusOption[] = [
  {
    value: 'invited',
    label: 'Invited',
    hue: 'slate',
    meaning: 'Has a seat but has not yet accepted or shown up.',
  },
  {
    value: 'active',
    label: 'Active',
    hue: 'teal',
    meaning: 'Taking the cohort. Counts toward capacity and attendance.',
  },
  {
    value: 'withdrawn',
    label: 'Withdrawn',
    hue: 'amber',
    meaning: 'Left before finishing. Seat is freed; work is kept.',
    holds: true,
  },
  {
    value: 'completed',
    label: 'Completed',
    hue: 'green',
    meaning: 'Met the completion rule. Eligible for a certificate.',
    terminal: true,
  },
];

export const EnrollmentStatusField = markDefinition(
  statusField({
    displayName: 'Enrollment Status',
    icon: UserCheckIcon,
    options: ENROLLMENT_STATUSES,
    transitions: {
      invited: ['active', 'withdrawn'],
      active: ['withdrawn', 'completed'],
      withdrawn: ['active'],
      completed: [],
    },
  }),
);

export default EnrollmentStatusField;
