import { statusField } from '@cardstack/catalog/fields/status/status';

// Only the cards' own operations move a status, so editing a card shows it rather than offering it.
function lifecycle(config: Parameters<typeof statusField>[0]) {
  let Status = statusField(config);
  return class Lifecycle extends Status {
    static edit = Status.embedded;
  };
}

// The lifecycles in the books. Only the cards' own operations move a status, so each graph is the
// moves those operations make.

export const DocumentStatusField = lifecycle({
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
  transitions: { draft: ['posted', 'journaled'] },
});

export const ReconciliationStatusField = lifecycle({
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

export const BankLineStatusField = lifecycle({
  displayName: 'Bank line status',
  options: [
    {
      value: 'for-review',
      label: 'For review',
      hue: 'amber',
      meaning:
        'Came in from the bank and is waiting to be matched, added or excluded.',
    },
    {
      value: 'matched',
      hue: 'green',
      terminal: true,
      meaning: 'Matched to something already in the books.',
    },
    {
      value: 'added',
      hue: 'teal',
      terminal: true,
      meaning: 'Added to the books as a new entry.',
    },
    {
      value: 'excluded',
      hue: 'slate',
      meaning:
        'Left out of the books, such as a duplicate or a personal charge.',
    },
  ],
  transitions: {
    'for-review': ['matched', 'added', 'excluded'],
    excluded: ['for-review'],
  },
});

export const MonthCloseStatusField = lifecycle({
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

export const JournalMonthStatusField = lifecycle({
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

export const YearCloseStatusField = lifecycle({
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
