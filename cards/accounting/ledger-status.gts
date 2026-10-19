import { statusField } from '@cardstack/catalog/fields/status/status';

// The lifecycles in the books. Only the cards' own operations move a status, so each graph is the
// moves those operations make.

export const DocumentStatusField = statusField({
  displayName: 'Document status',
  options: [
    {
      value: 'draft',
      hue: 'slate',
      meaning: 'Entered but not posted. It changes nothing in the books.',
    },
    {
      value: 'posted',
      hue: 'green',
      terminal: true,
      meaning: 'In the books. A correction is a reversal or a void.',
    },
    {
      value: 'journaled',
      hue: 'teal',
      terminal: true,
      meaning:
        'Posted into a journal month, which holds its lines; this card is the record of it.',
    },
  ],
  transitions: { draft: ['posted'] },
});

export const ReconciliationStatusField = statusField({
  displayName: 'Reconciliation status',
  options: [
    {
      value: 'draft',
      hue: 'slate',
      meaning: 'Items are still being ticked off against the statement.',
    },
    {
      value: 'reconciled',
      hue: 'green',
      terminal: true,
      meaning: 'The books agree with the bank statement at its end date.',
    },
  ],
  transitions: { draft: ['reconciled'] },
});

export const MonthCloseStatusField = statusField({
  displayName: 'Close status',
  options: [
    {
      value: 'draft',
      hue: 'slate',
      meaning: "The month's totals, not yet checked and closed.",
    },
    {
      value: 'closed',
      hue: 'green',
      terminal: true,
      meaning: 'Every check passed. Reports read these totals.',
    },
  ],
  transitions: { draft: ['closed'] },
});

export const JournalMonthStatusField = statusField({
  displayName: 'Month status',
  options: [
    {
      value: 'open',
      hue: 'blue',
      meaning: 'Entries can post into this month.',
    },
    {
      value: 'closed',
      hue: 'amber',
      meaning: 'Nothing new posts. Sealing it makes that final.',
    },
    {
      value: 'sealed',
      hue: 'green',
      terminal: true,
      meaning: 'Final. Corrections post as reversals in an open month.',
    },
  ],
  transitions: { open: ['closed'], closed: ['sealed'] },
});

export const YearCloseStatusField = statusField({
  displayName: 'Year status',
  options: [
    {
      value: 'open',
      hue: 'blue',
      meaning: 'The year is still being reviewed.',
    },
    {
      value: 'signed off',
      hue: 'green',
      terminal: true,
      meaning: 'Reviewed and signed. Its statements are final.',
    },
  ],
  transitions: { open: ['signed off'] },
});
