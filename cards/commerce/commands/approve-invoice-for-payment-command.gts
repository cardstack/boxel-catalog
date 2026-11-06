import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { Invoice } from '../invoice';
import { statusPath } from '../payment-status-field';
import {
  matchLines,
  openVarianceCount,
} from '../../procurement/three-way-match';

// Approve Invoice for Payment — the control accounts payable exists for:
// there is NO path to payment around an open variance. The command re-runs
// the match itself (never trusting the panel's display) and refuses unless
// every failing line carries a stored resolution. On success the invoice
// moves to `approved-for-payment`, and is paid through linked Payment
// records — no parallel payment model.

export class ApproveInvoiceForPaymentInput extends CardDef {
  @field invoice = linksTo(() => Invoice, { searchable: true });
}

export class ApproveInvoiceForPaymentResult extends CardDef {
  @field message = contains(StringField);
}

export default class ApproveInvoiceForPaymentCommand extends Command<
  typeof ApproveInvoiceForPaymentInput,
  typeof ApproveInvoiceForPaymentResult
> {
  static actionVerb = 'Approve for Payment';
  static displayName = 'Approve Invoice for Payment';

  async getInputType() {
    return ApproveInvoiceForPaymentInput;
  }

  protected async run(
    input: ApproveInvoiceForPaymentInput,
  ): Promise<ApproveInvoiceForPaymentResult> {
    let { invoice } = input;
    if (!invoice) {
      throw new Error('An invoice is required');
    }
    if (invoice.id) {
      invoice = (await new GetCardCommand(this.commandContext).execute({
        cardId: invoice.id,
      })) as Invoice;
    }
    let po = invoice.purchaseOrder;
    if (!po) {
      throw new Error(
        'This invoice names no purchase order — a vendor invoice cannot be approved without the match',
      );
    }
    // Only a vendor invoice in the match flow can be approved: approval has
    // to pass through 'matched', and a draft, sent, paid or void invoice has
    // no path there.
    let status = invoice.status ?? '';
    let path = statusPath(status, 'approved-for-payment');
    if (!path?.includes('matched') && status !== 'matched') {
      throw new Error(
        `A "${status || 'unset'}" invoice cannot be approved for payment — only a vendor invoice in the match flow`,
      );
    }

    // Re-run the match here — the guard trusts the documents, not the UI.
    let rows = matchLines(
      po.lineItems ?? [],
      po.receivedQuantities ?? [],
      invoice.lineItems ?? [],
      invoice.varianceResolutions ?? [],
    );
    let open = openVarianceCount(rows);
    if (open > 0) {
      // Record the exception where the graph allows it; an invoice already in
      // exception stays there.
      for (let next of statusPath(status, 'exception') ?? []) {
        await new PatchCardInstanceCommand(this.commandContext, {
          cardType: Invoice,
        }).execute({
          cardId: invoice.id,
          patch: { attributes: { status: next } },
        });
      }
    }
    if (open > 0) {
      throw new Error(
        `${open} open variance${open === 1 ? '' : 's'} — resolve each line (with a reason) before payment can be approved`,
      );
    }

    // Walk the status graph rather than jumping to the end of it.
    for (let next of path ?? []) {
      await new PatchCardInstanceCommand(this.commandContext, {
        cardType: Invoice,
      }).execute({
        cardId: invoice.id,
        patch: { attributes: { status: next } },
      });
    }

    let resolvedCount = rows.filter((r) => r.state === 'resolved').length;
    return new ApproveInvoiceForPaymentResult({
      message:
        resolvedCount > 0
          ? `Match closed with ${resolvedCount} resolved variance${resolvedCount === 1 ? '' : 's'} — approved for payment.`
          : 'Match clean — approved for payment.',
    });
  }
}
