import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { Invoice } from '../../commerce/invoice';
import { statusPath } from '../../commerce/payment-status-field';
import {
  VarianceActionField,
  VARIANCE_ACTIONS,
  actionsFor,
  matchLines,
  resolutionFor,
} from '../three-way-match';

// Resolve Variance — records one human decision about one failing match
// line, on the invoice, permanently. Reason is REQUIRED: the resolution IS
// the audit line. Resolving does not recompute anything — the panel
// re-derives the match and treats a resolved line as no longer blocking;
// the invoice moves to `matching` so the ladder shows it is being worked.

export class ResolveVarianceInput extends CardDef {
  @field invoice = linksTo(() => Invoice, { searchable: true });
  @field lineNumber = contains(NumberField);
  @field action = contains(VarianceActionField);
  @field reason = contains(StringField);
}

export class ResolveVarianceResult extends CardDef {
  @field message = contains(StringField);
}

export default class ResolveVarianceCommand extends Command<
  typeof ResolveVarianceInput,
  typeof ResolveVarianceResult
> {
  static actionVerb = 'Resolve';
  static displayName = 'Resolve Variance';

  async getInputType() {
    return ResolveVarianceInput;
  }

  protected async run(
    input: ResolveVarianceInput,
  ): Promise<ResolveVarianceResult> {
    let { invoice, lineNumber, action, reason } = input;
    if (!invoice) {
      throw new Error('An invoice is required');
    }
    if (lineNumber == null) {
      throw new Error('A line number is required');
    }
    if (!VARIANCE_ACTIONS.includes(action ?? '')) {
      throw new Error('action must be accept, short-pay, or reject-line');
    }
    if (!reason?.trim()) {
      throw new Error(
        'A reason is required — the resolution is the audit line',
      );
    }
    if (invoice.id) {
      invoice = (await new GetCardCommand(this.commandContext).execute({
        cardId: invoice.id,
      })) as Invoice;
    }
    // A resolution puts the invoice (back) into matching, so only a status
    // the graph lets reach matching can take one: received, matching or
    // exception.
    let status = invoice.status ?? '';
    if (!statusPath(status, 'matching')) {
      throw new Error(
        `A "${status || 'unset'}" invoice has no open match to resolve — only one received, matching or in exception`,
      );
    }
    let po = invoice.purchaseOrder;
    let row = po
      ? matchLines(
          po.lineItems ?? [],
          po.receivedQuantities ?? [],
          invoice.lineItems ?? [],
        ).find((r) => r.lineNumber === lineNumber)
      : undefined;
    if (!row || row.state === 'clean') {
      throw new Error(`Line ${lineNumber} has no variance to resolve`);
    }
    if (!actionsFor(row.state).includes(action ?? '')) {
      throw new Error(
        `A ${row.state} cannot be short-paid: there is no PO price in the invoice's currency to pay instead`,
      );
    }
    let existing = (invoice.varianceResolutions ?? []).filter(Boolean);
    // A change of mind is a new decision appended to the record; the latest
    // one for a line stands, and the earlier ones stay as history.
    let superseded = resolutionFor(row, existing);

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: Invoice,
    }).execute({
      cardId: invoice.id,
      patch: {
        attributes: {
          status: 'matching',
          varianceResolutions: [
            ...existing.map((r) => ({
              lineNumber: r.lineNumber,
              lineKey: r.lineKey,
              variance: r.variance,
              action: r.action,
              reason: r.reason,
              resolvedAt: r.resolvedAt,
            })),
            {
              lineNumber,
              lineKey: row.key,
              variance: row.detail,
              action,
              reason,
              resolvedAt: new Date().toISOString(),
            },
          ],
        },
      },
    });

    return new ResolveVarianceResult({
      message: superseded
        ? `Line ${lineNumber} re-resolved (${action}, replacing ${superseded.action}): ${reason}`
        : `Line ${lineNumber} resolved (${action}): ${reason}`,
    });
  }
}
