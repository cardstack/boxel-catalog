import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import { Command, getField } from '@cardstack/runtime-common';
import { loaded } from '@cardstack/catalog/cards/service-desk/record-helpers';
import { displayTitle } from '@cardstack/catalog/cards/service-desk/record-helpers';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

export class CancelInput extends CardDef {
  @field card = linksTo(CardDef, {
    searchable: true,
    description:
      'An in-flight process record carrying a `status` field with a "cancelled" value (e.g. an Escalation).',
  });
  @field reason = contains(StringField, {
    description: 'Required. "Cancelled" without a why is a deleted fact.',
  });
}

export class CancelResult extends CardDef {
  @field message = contains(StringField);
}

const TERMINAL = new Set(['resolved', 'cancelled', 'closed', 'complete']);

/**
 * The generic terminator for in-flight process records: writes
 * `status: 'cancelled'` plus the required reason, and refuses records that
 * are already terminal. NEVER a delete — a cancelled escalation stays
 * readable forever, which is what lets "cancelled twice, why?" be a query.
 *
 * Domain-neutral: the command checks shape (`status` exists,
 * `cancelledReason` accepted), not type. The consumer decides which of its
 * records are cancellable by giving them that shape.
 */
export default class CancelCommand extends Command<
  typeof CancelInput,
  typeof CancelResult
> {
  static actionVerb = 'Cancel';
  static displayName = 'Cancel';

  async getInputType() {
    return CancelInput;
  }

  protected async run(input: CancelInput): Promise<CancelResult> {
    let card = await loaded(this.commandContext, input.card);
    if (!card) {
      throw new Error('card is required');
    }
    if (!input.reason?.trim()) {
      throw new Error(
        'Refused: a cancellation must say why (reason is required).',
      );
    }
    if (!getField(card, 'status') || !getField(card, 'cancelledReason')) {
      throw new Error(
        `${displayTitle(card, 'This card')} has no status and cancelledReason fields — Cancel only terminates process records that can record why.`,
      );
    }
    let status = (card as any).status as string | undefined;
    if (status && TERMINAL.has(String(status).toLowerCase())) {
      throw new Error(
        `${displayTitle(card, 'This record')} is already ${status} — a terminal record stays as it ended.`,
      );
    }
    (card as any).status = 'cancelled';
    (card as any).cancelledReason = input.reason;
    await new SaveCardCommand(this.commandContext).execute({ card } as any);
    return new CancelResult({
      message: `${displayTitle(card, 'Record')} cancelled: ${input.reason}`,
    });
  }
}
