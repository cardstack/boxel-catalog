import {
  statusField,
  canTransition,
  nextStatuses,
} from '@cardstack/catalog/fields/status/status';

// Payment Status — where an invoice's money stands, built on the catalog's
// `statusField` so the graph below says which moves are legal. Invoice also
// exports it under the invoice-side name `InvoiceStatusField`. `overdue` is deliberately NOT one of the stored options — it stays
// a derived field on Invoice (`isOverdue`/`displayStatus`), because overdue
// is what "unpaid past the due date" looks like, not a state anyone sets.
// Storing it would let a stored flag disagree with the dates it is derived
// from.

export const PaymentStatusField = statusField({
  displayName: 'Payment Status',
  options: [
    { value: 'draft', hue: 'slate', meaning: 'Not yet sent to the customer.' },
    { value: 'sent', hue: 'blue', meaning: 'Delivered, not yet opened.' },
    { value: 'viewed', hue: 'purple', meaning: 'Customer has opened it.' },
    {
      value: 'partial',
      hue: 'amber',
      meaning: 'Some payments recorded, balance remains.',
    },
    {
      value: 'paid',
      hue: 'green',
      terminal: true,
      holds: true,
      meaning: 'Fully paid. Nothing further happens on this record.',
    },
    {
      value: 'void',
      hue: 'red',
      terminal: true,
      holds: true,
      meaning: 'Cancelled. A correction is a new invoice, not an edit.',
    },
    // ---- AP (buy-side) leg — the one deliberate widening the Invoice
    // Status Spec documents. A VENDOR invoice arrives 'received' rather
    // than being drafted, runs the three-way match, and only a clean or
    // fully-resolved match can reach payment. Sell-side values and
    // transitions above are untouched.
    {
      value: 'received',
      hue: 'slate',
      meaning: "Vendor's invoice recorded, match not yet run.",
    },
    {
      value: 'matching',
      hue: 'blue',
      meaning: 'Being compared line-by-line against PO and receipts.',
    },
    {
      value: 'matched',
      hue: 'green',
      meaning: 'Every line clean within tolerance.',
    },
    {
      value: 'exception',
      hue: 'red',
      meaning:
        'At least one line has an unresolved variance — payment blocked.',
    },
    {
      value: 'approved-for-payment',
      hue: 'green',
      meaning: 'Match clean or all variances resolved; payment may proceed.',
    },
  ],
  transitions: {
    draft: ['sent', 'void'],
    sent: ['viewed', 'partial', 'paid', 'void'],
    viewed: ['partial', 'paid', 'void'],
    partial: ['paid', 'void'],
    received: ['matching', 'void'],
    matching: ['matched', 'exception', 'void'],
    exception: ['matching', 'void'],
    matched: ['approved-for-payment', 'void'],
    'approved-for-payment': ['partial', 'paid', 'void'],
  },
});

export { canTransition, nextStatuses };
