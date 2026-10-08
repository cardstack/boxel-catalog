import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Notification } from '../notification';
import {
  ConsentGrantField,
  ChannelConsentField,
} from '@cardstack/catalog/fields/consent/consent-vocabulary';

export class NotifyParticipantInput extends CardDef {
  @field recipientRef = contains(StringField);
  @field subject = contains(StringField);
  @field body = contains(StringField);
  @field severity = contains(StringField);
  @field dedupeKey = contains(StringField, {
    description: 'Stable per event. Required — see the readMe.',
  });
  @field subjectCard = linksTo(() => CardDef);
  @field actionUrl = contains(StringField);
  @field actionLabel = contains(StringField);
  @field expiresAt = contains(DateTimeField);

  // Consent travels with the request rather than being looked up, so the
  // command stays a pure decision-and-write and the caller owns where the
  // records came from.
  @field grants = containsMany(ConsentGrantField);
  @field channels = containsMany(ChannelConsentField);
  @field purpose = contains(StringField, {
    description:
      'The purpose this notification serves. Required when consent records are supplied.',
  });
  @field channel = contains(StringField);

  // Already-sent keys, so the caller can enforce dedupe without this command
  // querying anything.
  @field existingKeys = containsMany(StringField);
}

export class NotifyParticipantResult extends CardDef {
  @field sent = contains(BooleanField);
  @field skipped = contains(BooleanField);
  @field reason = contains(StringField);
  @field notification = linksTo(() => Notification);
}

/**
 * Tell one participant one thing, once.
 *
 * ### Three gates, in this order
 *
 * 1. **Dedupe.** If `dedupeKey` is already in `existingKeys`, this is a
 *    retry and nothing is written. Checked first because it is the cheapest
 *    and because a retry should never re-run a consent check that might now
 *    answer differently.
 * 2. **Consent.** When grants are supplied, a missing or inactive grant for
 *    the purpose stops the send. Default deny — absence of a grant is not
 *    consent.
 * 3. **Channel.** A suppressed or unconfirmed channel stops the send even
 *    when the purpose is permitted, because a bounced address is unusable
 *    whatever the person agreed to.
 *
 * ### Skipped is not failed
 *
 * A dedupe hit and a consent block both return `sent: false, skipped: true`
 * with a reason, rather than throwing. Both are **correct outcomes** — the
 * system did the right thing. Throwing would make a caller's retry logic
 * treat "we already told them" as an error to retry, which produces exactly
 * the duplicate the dedupe was there to prevent.
 *
 * A missing `dedupeKey` **does** throw, because that is a programming
 * mistake: without it the command cannot promise "once", and silently
 * sending would break the guarantee its name implies.
 *
 * ### Consent is optional input, not optional behaviour
 *
 * Omit the grants and the consent gate is skipped — which is right for a
 * system notice that carries no consent question (a password reset, a
 * security alert). Supply them and the gate is enforced. What is not
 * possible is supplying them and having them ignored.
 */
export class NotifyParticipantCommand extends Command<
  typeof NotifyParticipantInput,
  typeof NotifyParticipantResult
> {
  static actionVerb = 'Notify';
  static displayName = 'Notify Participant';

  async getInputType() {
    return NotifyParticipantInput;
  }

  protected async run(
    input: NotifyParticipantInput,
  ): Promise<NotifyParticipantResult> {
    let key = input.dedupeKey?.trim();
    if (!key) {
      throw new Error(
        'dedupeKey is required. Without it this command cannot promise "once", and a retried job would send duplicates.',
      );
    }
    if (!input.recipientRef?.trim()) {
      throw new Error('recipientRef is required.');
    }

    // 1 — dedupe, before anything that could answer differently on a retry.
    if ((input.existingKeys ?? []).includes(key)) {
      return new NotifyParticipantResult({
        sent: false,
        skipped: true,
        reason: `Already notified for “${key}”. This is a retry, not a new event.`,
      });
    }

    // 2 — consent, when records were supplied.
    let grants = input.grants ?? [];
    if (grants.length) {
      let purpose = input.purpose?.trim().toLowerCase();
      if (!purpose) {
        throw new Error(
          'purpose is required when consent records are supplied — consent is per-purpose.',
        );
      }
      let now = new Date();
      let active = grants.find((g) => {
        if (g?.purpose?.trim().toLowerCase() !== purpose) {
          return false;
        }
        if (g.withdrawnAt && new Date(g.withdrawnAt) <= now) {
          return false;
        }
        if (g.expiresAt && new Date(g.expiresAt) <= now) {
          return false;
        }
        if (g.lawfulBasis === 'consent' || !g.lawfulBasis) {
          return g.status === 'granted';
        }
        return true;
      });
      if (!active) {
        return new NotifyParticipantResult({
          sent: false,
          skipped: true,
          reason: `No active permission for “${input.purpose}”. Default deny.`,
        });
      }
    }

    // 3 — channel.
    if (input.channel) {
      let ch = (input.channels ?? []).find((c) => c?.channel === input.channel);
      if (!ch || !ch.isContactable) {
        return new NotifyParticipantResult({
          sent: false,
          skipped: true,
          reason: ch
            ? ch.blockedReason ||
              `The ${input.channel} channel is not contactable.`
            : `No record for the ${input.channel} channel. Default deny.`,
        });
      }
    }

    let notification = new Notification({
      recipientRef: input.recipientRef,
      subject: input.subject,
      body: input.body,
      severity: input.severity ?? 'info',
      dedupeKey: key,
      createdAt: new Date(),
      expiresAt: input.expiresAt,
      actionUrl: input.actionUrl,
      actionLabel: input.actionLabel,
      subjectCard: input.subjectCard,
    });

    await new SaveCardCommand(this.commandContext).execute({
      card: notification,
    } as any);

    return new NotifyParticipantResult({
      sent: true,
      skipped: false,
      notification,
      reason: `Notified ${input.recipientRef} — “${input.subject ?? key}”.`,
    });
  }
}

export default NotifyParticipantCommand;
