import { statusField } from '@cardstack/catalog/fields/status/status';

/**
 * Membership standing: Active is the working state, Lapsed is recoverable
 * neglect (renewal missed, points frozen by program rules), Closed is a
 * deliberate end that can still be reopened by re-enrolment.
 */
export const MembershipStatusField = statusField({
  displayName: 'Membership Status',
  options: [
    { value: 'Active', hue: 'green', meaning: 'In good standing' },
    {
      value: 'Lapsed',
      hue: 'amber',
      meaning: 'Renewal missed — recoverable',
      holds: true,
    },
    {
      value: 'Closed',
      hue: 'slate',
      meaning: 'Deliberately ended',
      terminal: true,
      holds: true,
    },
  ],
  transitions: {
    Active: ['Lapsed', 'Closed'],
    Lapsed: ['Active', 'Closed'],
    Closed: ['Active'],
  },
});

export default MembershipStatusField;
