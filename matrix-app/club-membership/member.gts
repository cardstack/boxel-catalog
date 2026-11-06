import { contains, field } from '@cardstack/base/card-api';
import UsersIcon from '@cardstack/boxel-icons/users';
import { codeRef } from '@cardstack/runtime-common';

import { LoyaltyAccount } from '../loyalty/loyalty-account';
import { loyaltyTierField } from '../loyalty/loyalty-tier-field';

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const moduleURL: string = import.meta.url;

/**
 * The club's ladder. Multipliers are the published earning rates the
 * points arithmetic quotes; Legend is invitation-only so no upgrade prompt
 * ever offers it — consumers check `invitable` before rendering one.
 */
export const MemberTierField = loyaltyTierField({
  displayName: 'Membership Tier',
  options: [
    {
      value: 'Bronze',
      hue: 'orange',
      multiplier: 1,
      meaning: 'Free registration — general sale access',
    },
    {
      value: 'Silver',
      hue: 'slate',
      multiplier: 1.5,
      meaning: 'Paid member — priority window after Gold',
    },
    {
      value: 'Gold',
      hue: 'amber',
      multiplier: 2,
      meaning: 'Season ticket holder — first priority',
    },
    {
      value: 'Legend',
      hue: 'purple',
      multiplier: 3,
      meaning: 'Invitation only',
      invitable: false,
    },
  ],
});

/**
 * A club member IS a loyalty account — the club's only specialization is
 * its own ladder. Everything else (member number, holder, ledger-maintained
 * balances, membership status) is consumed unchanged from the block.
 */
export class Member extends LoyaltyAccount {
  static displayName = 'Member';
  static icon = UsersIcon;
  // A member's match bookings show on the account page (Linked + Bookings stat).
  static bookingRef = codeRef(moduleURL, '../events/booking', 'Booking');

  @field tier = contains(MemberTierField);
}
