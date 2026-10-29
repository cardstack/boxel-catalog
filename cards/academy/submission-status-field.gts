import { markDefinition } from '@cardstack/base';
import FileCheckIcon from '@cardstack/boxel-icons/file-check';

import {
  statusField,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';

/**
 * Where one submission sits in the hand-in → feedback loop. Configured over
 * the shared `statusField` factory; the loop is deliberately small because
 * every extra state is another thing a learner has to decode on a Friday
 * night. `returned` means "the grader wants another version", and a
 * resubmission is a NEW Submission card (version n+1), not a status reset.
 */
export const SUBMISSION_STATUSES: StatusOption[] = [
  {
    value: 'not_submitted',
    label: 'Not submitted',
    hue: 'slate',
    meaning: 'A draft exists but nothing has been handed in.',
  },
  {
    value: 'submitted',
    label: 'Submitted',
    hue: 'blue',
    meaning: 'Handed in and waiting for a grader.',
  },
  {
    value: 'returned',
    label: 'Returned',
    hue: 'amber',
    meaning: 'Sent back with feedback; a new version is expected.',
  },
  {
    value: 'graded',
    label: 'Graded',
    hue: 'green',
    meaning: 'Scored against the rubric. Counts toward completion.',
    terminal: true,
  },
];

export const SubmissionStatusField = markDefinition(
  statusField({
    displayName: 'Submission Status',
    icon: FileCheckIcon,
    options: SUBMISSION_STATUSES,
    transitions: {
      not_submitted: ['submitted'],
      submitted: ['returned', 'graded'],
      returned: ['submitted'],
      graded: ['returned'],
    },
  }),
);

export default SubmissionStatusField;
