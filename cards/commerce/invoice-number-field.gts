import { Component } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';

// Invoice number — the immutable document identity a customer quotes back
// at you. Like PO Number, the command that issues the invoice stamps it once
// and nothing recomputes it. The field renders in document style
// (mono, tabular) so an invoice number reads as a reference everywhere.
export class InvoiceNumberField extends StringField {
  static displayName = 'Invoice Number';

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='invoice-number'>{{@model}}</span>
      <style scoped>
        .invoice-number {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          letter-spacing: 0.02em;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='invoice-number'>{{@model}}</span>
      <style scoped>
        .invoice-number {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          letter-spacing: 0.02em;
          font-weight: 600;
          font-size: 0.8125rem;
        }
      </style>
    </template>
  };
}

// Year-scoped number for the command that issues an invoice. The tail is six
// random hex characters, so two invoices issued together don't collide.
export function nextInvoiceNumber(now: Date = new Date()): string {
  let tail = crypto.randomUUID().replace(/-/g, '').slice(0, 6).toUpperCase();
  return `INV-${now.getFullYear()}-${tail}`;
}

export default InvoiceNumberField;
