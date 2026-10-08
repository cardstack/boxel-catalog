import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import { Command, getField } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

// Reject Request — the symmetric half of approval, domain-neutral: any
// request-shaped card (a PO pending approval, a service request, an offer)
// can be sent back. A reason is REQUIRED — an unexplained rejection is
// unactionable for the requester and useless in an audit — and the card's
// document identity (its number) is never touched: a rejected PO keeps its
// number. The block stays neutral about lifecycles: the consumer names the
// status the card returns to, because only the domain knows whether "back"
// means draft, rejected, or needs-work.

export class RejectRequestInput extends CardDef {
  @field target = linksTo(() => CardDef, { searchable: true });
  @field reason = contains(StringField);
  @field returnToStatus = contains(StringField, {
    description:
      "The status the card returns to, from the card's own lifecycle (for example declined, draft or needs-work)",
  });
  @field reasonField = contains(StringField, {
    description:
      'The field on the card that records the reason (default: rejectionReason, when the card declares it)',
  });
}

export class RejectRequestResult extends CardDef {
  @field message = contains(StringField);
}

export default class RejectRequestCommand extends Command<
  typeof RejectRequestInput,
  typeof RejectRequestResult
> {
  static actionVerb = 'Reject';
  static displayName = 'Reject Request';

  async getInputType() {
    return RejectRequestInput;
  }

  protected async run(input: RejectRequestInput): Promise<RejectRequestResult> {
    let { target, reason, returnToStatus, reasonField } = input;
    if (!target) {
      throw new Error('A request card is required');
    }
    if (!reason?.trim()) {
      throw new Error(
        'A reason is required — an unexplained rejection is unactionable for the requester',
      );
    }
    let next = returnToStatus?.trim();
    if (!next) {
      throw new Error(
        'A status to return to is required — only the card’s own lifecycle knows what "sent back" means',
      );
    }
    if (target.id) {
      target = (await new GetCardCommand(this.commandContext).execute({
        cardId: target.id,
      })) as CardDef;
    }
    if (!getField(target, 'status')) {
      throw new Error('This card has no status field to send back');
    }
    let current = (target as any).status;
    if (current === next) {
      throw new Error(`This request is already "${next}"`);
    }
    let reasonName = reasonField?.trim() || 'rejectionReason';
    let storesReason = Boolean(getField(target, reasonName));
    if (reasonField?.trim() && !storesReason) {
      throw new Error(`This card has no ${reasonName} field for the reason`);
    }

    // Mutate-and-save (the ApproveChainStepCommand idiom): the target's
    // concrete type is unknown here, so the fields are checked by name above.
    (target as any).status = next;
    if (storesReason) {
      (target as any)[reasonName] = reason;
    }
    await new SaveCardCommand(this.commandContext).execute({
      card: target,
    } as any);

    return new RejectRequestResult({
      message: storesReason
        ? `Rejected → ${next}. Reason recorded in ${reasonName}: ${reason}`
        : `Rejected → ${next}. The card has no reason field, so the reason is only in this result: ${reason}`,
    });
  }
}
