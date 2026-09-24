import {
  FieldDef,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import UrlField from '@cardstack/base/url';
import enumField from '@cardstack/base/enum';
import { dueDays } from '@cardstack/catalog/fields/due-date/due-date';
import { Component } from '@cardstack/base/card-api';

// The consent vocabulary — permission to use someone's data, and permission
// to reach them on a channel. Two fields, because they are two different
// permissions and conflating them is the most common modelling error here:
// someone can consent to marketing (the purpose) and still be uncontactable
// by email (the channel) because their address hard-bounced.
//
// Enum values are migrations. Never rename or remove one — instances carry
// these strings, and a renamed value silently reads as unset.

/**
 * The lawful basis for processing. Consent is only one of six, and treating
 * it as the only one is how a system ends up asking for permission it does
 * not need — which is itself a compliance problem, because asking implies
 * the person can say no.
 */
export const LawfulBasisField = enumField(StringField, {
  options: [
    { value: 'consent', label: 'Consent' },
    { value: 'contract', label: 'Performance of a contract' },
    { value: 'legal-obligation', label: 'Legal obligation' },
    { value: 'vital-interests', label: 'Vital interests' },
    { value: 'public-task', label: 'Public task' },
    { value: 'legitimate-interests', label: 'Legitimate interests' },
  ],
});

export const ConsentStatusField = enumField(StringField, {
  options: [
    { value: 'pending', label: 'Pending' },
    { value: 'granted', label: 'Granted' },
    { value: 'withdrawn', label: 'Withdrawn' },
    { value: 'expired', label: 'Expired' },
  ],
});

export const ChannelField = enumField(StringField, {
  options: [
    { value: 'email', label: 'Email' },
    { value: 'sms', label: 'SMS' },
    { value: 'phone', label: 'Phone' },
    { value: 'post', label: 'Post' },
    { value: 'push', label: 'Push notification' },
    { value: 'in-app', label: 'In-app' },
  ],
});

/**
 * Why a channel cannot be used, when the reason is not the person's choice.
 *
 * This is the distinction the whole family is built around: a hard bounce, a
 * spam complaint or a do-not-call listing stops delivery **without the person
 * having withdrawn anything**. Collapsing suppression into withdrawal loses
 * the ability to re-engage someone who simply changed their address, and
 * overstates how many people opted out.
 */
export const SuppressionReasonField = enumField(StringField, {
  options: [
    { value: 'hard-bounce', label: 'Hard bounce' },
    { value: 'spam-complaint', label: 'Spam complaint' },
    { value: 'do-not-contact-list', label: 'Do-not-contact list' },
    { value: 'invalid-address', label: 'Invalid address' },
    { value: 'manual', label: 'Suppressed manually' },
  ],
});

// ── Consent Grant ───────────────────────────────────────────────────────────

/**
 * One permission, for one purpose.
 *
 * ### Consent is per-purpose, never blanket
 *
 * A single `hasConsented` boolean on a person is the error this field exists
 * to prevent. Permission to send order updates is not permission to send
 * marketing, and a system that cannot tell them apart has to treat every
 * message as the most restricted kind — or send things it should not.
 *
 * ### `policyVersion` is what makes a grant auditable
 *
 * Consent is only valid for what the person was actually told. When the
 * privacy policy changes materially, consent to the old one is not consent to
 * the new one, and without recording which version was shown there is no way
 * to work out afterwards who needs re-asking.
 *
 * ### Withdrawal must be as easy as granting
 *
 * So `withdrawnAt` is a plain field, not a separate workflow — recording a
 * withdrawal is one write, the same as recording a grant.
 */
export class ConsentGrantField extends FieldDef {
  static displayName = 'Consent Grant';

  @field purpose = contains(StringField, {
    description:
      'What this permits, specifically: "product marketing", "usage analytics", "service notifications". Never "everything".',
  });
  @field lawfulBasis = contains(LawfulBasisField);
  @field status = contains(ConsentStatusField);

  @field grantedAt = contains(DateTimeField);
  @field withdrawnAt = contains(DateTimeField);
  @field expiresAt = contains(DateTimeField, {
    description: 'When this lapses. Blank means it does not expire on its own.',
  });

  @field capturedVia = contains(StringField, {
    description:
      'How it was obtained: signup form, double opt-in, phone call, import.',
  });
  @field policyVersion = contains(StringField, {
    description:
      'The privacy notice version the person was shown. A grant without one cannot be audited.',
  });
  @field evidenceUrl = contains(UrlField, {
    description: 'The proof — a form snapshot, a recording, an import record.',
  });
  @field note = contains(StringField);

  @field isActive = contains(BooleanField, {
    computeVia: function (this: ConsentGrantField) {
      if (this.status !== 'granted') {
        return false;
      }
      if (this.withdrawnAt) {
        return false;
      }
      if (this.expiresAt && new Date(this.expiresAt) <= new Date()) {
        return false;
      }
      return true;
    },
  });

  // Undefined, not a large number, when nothing expires — "does not expire"
  // and "expires in 9999 days" are different facts.
  @field daysUntilExpiry = contains(NumberField, {
    computeVia: function (this: ConsentGrantField) {
      return dueDays(this.expiresAt ?? undefined);
    },
  });

  // A grant under the `consent` basis with no recorded policy version is not
  // auditable — it cannot be shown what the person agreed to. Flagged rather
  // than rejected, because the fix is usually a re-ask, not a deletion.
  @field needsEvidence = contains(BooleanField, {
    computeVia: function (this: ConsentGrantField) {
      return this.lawfulBasis === 'consent' && !this.policyVersion;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    // 0 is "today", not falsy; a past date reads "expired" rather than a
    // negative count, whatever the stored status still says.
    get expiryLabel(): string | undefined {
      let days = this.args.model?.daysUntilExpiry;
      if (days === undefined || days === null) {
        return undefined;
      }
      if (days < 0) {
        return 'expired';
      }
      return days === 0 ? 'expires today' : `${days}d left`;
    }

    <template>
      <div class='grant'>
        <span class='purpose {{if @model.isActive "on" "off"}}'>
          {{if @model.purpose @model.purpose 'No purpose set'}}
        </span>
        <span class='meta'>
          {{@model.status}}
          {{#if @model.lawfulBasis}} · {{@model.lawfulBasis}}{{/if}}
          {{#if this.expiryLabel}}
            ·
            {{this.expiryLabel}}
          {{/if}}
        </span>
        {{#if @model.needsEvidence}}
          {{! A consent-based grant with no policy version cannot be
            audited — the fix is a re-ask, so this is surfaced not hidden. }}
          <span class='warn'>no policy version — not auditable</span>
        {{/if}}
      </div>
      <style scoped>
        .grant {
          display: flex;
          flex-direction: column;
          gap: 1px;
          color: var(--foreground, var(--boxel-dark));
        }
        .purpose {
          font: 600 var(--boxel-font-sm);
        }
        .purpose.off {
          color: var(--muted-foreground, var(--boxel-450));
          text-decoration: line-through;
        }
        .meta {
          font: var(--boxel-font-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .warn {
          font: var(--boxel-font-xs);
          color: var(--warning, #b7791f);
        }
      </style>
    </template>
  };
}

// ── Channel Consent ─────────────────────────────────────────────────────────

/**
 * Whether a channel may be used to reach someone.
 *
 * Separate from `ConsentGrantField` because the two fail independently.
 * Permission to market to someone (purpose) says nothing about whether their
 * email address still works (channel), and an address that hard-bounced is
 * unusable no matter what they agreed to.
 *
 * ### Double opt-in is recorded, not assumed
 *
 * `doubleOptInConfirmedAt` is separate from `optedInAt`: a signup that was
 * never confirmed is a *pending* channel, not a consented one. Systems that
 * treat the two as the same send to addresses nobody ever confirmed owning.
 */
export class ChannelConsentField extends FieldDef {
  static displayName = 'Channel Consent';

  @field channel = contains(ChannelField);
  @field status = contains(ConsentStatusField);

  @field optedInAt = contains(DateTimeField);
  @field optedOutAt = contains(DateTimeField);
  @field doubleOptInConfirmedAt = contains(DateTimeField, {
    description:
      'Separate from optedInAt. An unconfirmed signup is pending, not consented.',
  });

  // Suppression is not withdrawal — see SuppressionReasonField.
  @field suppressionReason = contains(SuppressionReasonField);
  @field suppressedAt = contains(DateTimeField);

  @field requiresDoubleOptIn = contains(BooleanField, {
    description:
      'Whether this channel’s policy demands a confirmation step, which varies by channel and jurisdiction.',
  });

  @field isSuppressed = contains(BooleanField, {
    computeVia: function (this: ChannelConsentField) {
      return Boolean(this.suppressionReason);
    },
  });

  @field isConfirmed = contains(BooleanField, {
    computeVia: function (this: ChannelConsentField) {
      if (!this.requiresDoubleOptIn) {
        return this.status === 'granted';
      }
      return Boolean(this.doubleOptInConfirmedAt);
    },
  });

  @field isContactable = contains(BooleanField, {
    computeVia: function (this: ChannelConsentField) {
      if (this.suppressionReason) {
        return false;
      }
      if (this.status !== 'granted' || this.optedOutAt) {
        return false;
      }
      if (this.requiresDoubleOptIn && !this.doubleOptInConfirmedAt) {
        return false;
      }
      return true;
    },
  });

  // The reason, in the order a person reading a support ticket needs it:
  // suppression first (it is the one they cannot fix by asking again).
  @field blockedReason = contains(StringField, {
    computeVia: function (this: ChannelConsentField) {
      if (this.suppressionReason) {
        return `Suppressed: ${this.suppressionReason}`;
      }
      if (this.optedOutAt) {
        return 'Opted out';
      }
      if (this.status !== 'granted') {
        return `Not granted (${this.status ?? 'unset'})`;
      }
      if (this.requiresDoubleOptIn && !this.doubleOptInConfirmedAt) {
        return 'Awaiting double opt-in confirmation';
      }
      return '';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='chan'>
        <span class='name {{if @model.isContactable "ok" "no"}}'>
          {{@model.channel}}
        </span>
        {{! blockedReason orders its causes by what the reader can act on —
          suppression first, because that is the one they cannot fix by
          asking again. }}
        <span class='why'>
          {{if @model.isContactable 'contactable' @model.blockedReason}}
        </span>
      </div>
      <style scoped>
        .chan {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xxs);
          color: var(--foreground, var(--boxel-dark));
        }
        .name {
          font: 600 var(--boxel-font-sm);
          text-transform: capitalize;
        }
        .name.no {
          color: var(--destructive, var(--boxel-danger));
        }
        .why {
          font: var(--boxel-font-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}
