import {
  CardDef,
  contains,
  containsMany,
  field,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import { Command } from '@cardstack/runtime-common';

import {
  ConsentGrantField,
  ChannelConsentField,
} from '@cardstack/catalog/fields/consent/consent-vocabulary';

export class ValidateConsentInput extends CardDef {
  @field grants = containsMany(ConsentGrantField);
  @field channels = containsMany(ChannelConsentField);
  @field purpose = contains(StringField, {
    description: 'The specific purpose being checked. Required.',
  });
  @field channel = contains(StringField, {
    description:
      'Which channel the message would go out on. Omit to check the purpose alone.',
  });
  @field asOf = contains(DateTimeField, {
    description:
      'Evaluate as at this moment rather than now — for auditing a decision that was already made.',
  });
}

export class ValidateConsentResult extends CardDef {
  @field allowed = contains(BooleanField);
  // Which half said no. A caller that only gets a boolean cannot tell whether
  // to re-ask for permission or to collect a new email address, and those are
  // completely different remedies.
  @field blockedBy = contains(StringField, {
    description: "'purpose' | 'channel' | '' when allowed.",
  });
  @field reason = contains(StringField);
  @field lawfulBasis = contains(StringField, {
    description: 'The basis that permitted it, when allowed.',
  });
}

/**
 * Why a channel could not be used at `at`, or undefined when it could. Each
 * event counts only once it has happened; an event with no date falls back to
 * the channel's current state, conservatively.
 */
function channelBlockedAt(
  ch: ChannelConsentField,
  at: Date,
): string | undefined {
  let before = (d?: Date | null) => Boolean(d) && new Date(d!) <= at;
  if (ch.suppressionReason && (!ch.suppressedAt || before(ch.suppressedAt))) {
    return ch.blockedReason || 'Suppressed';
  }
  if (before(ch.optedOutAt)) {
    return 'Opted out';
  }
  let optedIn = ch.optedInAt ? before(ch.optedInAt) : ch.status === 'granted';
  if (!optedIn) {
    return ch.optedInAt
      ? `Not opted in to the ${ch.channel} channel at that time`
      : ch.blockedReason || `The ${ch.channel} channel is not contactable.`;
  }
  if (ch.requiresDoubleOptIn && !before(ch.doubleOptInConfirmedAt)) {
    return 'Double opt-in not confirmed at that time';
  }
  return undefined;
}

/**
 * Decide whether a specific message, for a specific purpose, on a specific
 * channel, may be sent.
 *
 * ### Default deny
 *
 * Absence of a grant is not consent. A person with no record at all is
 * **not** contactable, and this command says so rather than falling through
 * to permissive. Any consent check that defaults to allow is worse than no
 * check, because it produces a confident wrong answer.
 *
 * ### Two independent gates
 *
 * The **purpose** gate asks whether processing for this reason is lawful. The
 * **channel** gate asks whether this route may be used. Both must pass, and
 * the result names which one failed — a caller that only learns "no" cannot
 * tell whether to re-ask for permission or to collect a new address, and
 * those are completely different remedies.
 *
 * ### Consent is not the only basis
 *
 * A grant under `contract` or `legal-obligation` is valid without anyone
 * having opted in — a service notice about an order does not need marketing
 * consent. Requiring `status === 'granted'` for every basis would block
 * messages an organisation is actually obliged to send.
 *
 * The channel gate still applies: a lawful basis does not make a bounced
 * address deliverable.
 *
 * ### `asOf` exists for auditing
 *
 * "Was this send lawful at the time?" is a different question from "may we
 * send now", and a system that can only answer the second cannot defend the
 * first.
 */
export class ValidateConsentCommand extends Command<
  typeof ValidateConsentInput,
  typeof ValidateConsentResult
> {
  static actionVerb = 'Validate';
  static displayName = 'Validate Consent';

  async getInputType() {
    return ValidateConsentInput;
  }

  protected async run(
    input: ValidateConsentInput,
  ): Promise<ValidateConsentResult> {
    if (!input.purpose?.trim()) {
      throw new Error(
        'purpose is required — consent is per-purpose, and a blanket check has no meaningful answer.',
      );
    }

    let at = input.asOf ? new Date(input.asOf) : new Date();
    let purpose = input.purpose.trim().toLowerCase();

    let activeAt = (g: ConsentGrantField): boolean => {
      if (g.withdrawnAt && new Date(g.withdrawnAt) <= at) {
        return false;
      }
      if (g.expiresAt && new Date(g.expiresAt) <= at) {
        return false;
      }
      // `consent` is the only basis that needs an affirmative grant. The
      // others are lawful because of the relationship, not the opt-in.
      if (g.lawfulBasis === 'consent' || !g.lawfulBasis) {
        // Without a grant date, only the current status can answer.
        if (!g.grantedAt) {
          return g.status === 'granted';
        }
        if (new Date(g.grantedAt) > at) {
          return false;
        }
        // A grant since withdrawn or expired was still active at `at` when
        // its dates say so; one whose end has no date cannot be placed in
        // time, so it does not count.
        if (g.status === 'withdrawn') return Boolean(g.withdrawnAt);
        if (g.status === 'expired') return Boolean(g.expiresAt);
        return g.status === 'granted';
      }
      return true;
    };

    let match = (input.grants ?? []).find(
      (g) => g?.purpose?.trim().toLowerCase() === purpose && activeAt(g),
    );

    if (!match) {
      let existed = (input.grants ?? []).some(
        (g) => g?.purpose?.trim().toLowerCase() === purpose,
      );
      return new ValidateConsentResult({
        allowed: false,
        blockedBy: 'purpose',
        reason: existed
          ? `A grant for “${input.purpose}” exists but is not active as at ${at.toISOString()} — withdrawn, expired, or never granted.`
          : `No grant recorded for “${input.purpose}”. Absence of a grant is not consent.`,
      });
    }

    if (input.channel) {
      let ch = (input.channels ?? []).find((c) => c?.channel === input.channel);
      if (!ch) {
        return new ValidateConsentResult({
          allowed: false,
          blockedBy: 'channel',
          reason: `No record for the ${input.channel} channel. Default deny.`,
          lawfulBasis: match.lawfulBasis,
        });
      }
      let channelBlock = channelBlockedAt(ch, at);
      if (channelBlock) {
        return new ValidateConsentResult({
          allowed: false,
          blockedBy: 'channel',
          reason: channelBlock,
          lawfulBasis: match.lawfulBasis,
        });
      }
    }

    return new ValidateConsentResult({
      allowed: true,
      blockedBy: '',
      lawfulBasis: match.lawfulBasis,
      reason: `Permitted for “${input.purpose}”${
        input.channel ? ` on ${input.channel}` : ''
      } under ${match.lawfulBasis ?? 'consent'}.`,
    });
  }
}

export default ValidateConsentCommand;
