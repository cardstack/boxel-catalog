import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { Booking } from '../../events/booking';
import CheckInBookingCommand from '../../events/check-in-booking';
import CreditPointsCommand from '../../loyalty/credit-points';
import { PointsTransaction } from '../../loyalty/loyalty-account';
import { tierMultiplier } from '../../loyalty/loyalty-tier-field';
import { Member, MemberTierField } from '../member';
import { Match } from '../match';

export class RecordAttendanceInput extends CardDef {
  @field booking = linksTo(Booking, { searchable: true });
  @field member = linksTo(Member, { searchable: true });
  @field realm = contains(StringField);
}

export class RecordAttendanceResult extends CardDef {
  @field booking = linksTo(Booking);
  @field transaction = linksTo(PointsTransaction);
  @field pointsAwarded = contains(NumberField);
  @field message = contains(StringField);
}

const HOME_POINTS = 50;
const AWAY_POINTS = 150;

/**
 * The turnstile scan, as the club runs it: check the booking in (the
 * block's one-time-use command), then credit attendance points at the
 * club's published rates — 50 home, 150 away, times the member's tier
 * multiplier. The rates and the multiplier are club arithmetic, which is
 * exactly why they live here and not in either block.
 */
export default class RecordAttendanceCommand extends Command<
  typeof RecordAttendanceInput,
  typeof RecordAttendanceResult
> {
  static actionVerb = 'Record Attendance';

  async getInputType() {
    return RecordAttendanceInput;
  }

  protected async run(
    input: RecordAttendanceInput,
  ): Promise<RecordAttendanceResult> {
    let { booking, member, realm } = input;
    if (!booking) throw new Error('A booking is required');
    if (!member) throw new Error('A member is required');
    if (!realm) throw new Error('A realm is required');

    let checkIn = await new CheckInBookingCommand(this.commandContext).execute({
      booking,
      realm,
    });

    if (member.id) {
      member = (await new GetCardCommand(this.commandContext).execute({
        cardId: member.id,
      })) as Member;
    }
    let checkedInBooking = (await new GetCardCommand(
      this.commandContext,
    ).execute({ cardId: checkIn.booking?.id ?? booking.id! })) as Booking;
    let match = checkedInBooking.event as Match | undefined;
    let base = match?.homeAway === 'Away' ? AWAY_POINTS : HOME_POINTS;
    let points = Math.round(
      base * tierMultiplier(MemberTierField, member.tier),
    );

    // Check-in is one-time-use, so a failed credit undoes it; otherwise the
    // booking reads as attended and could never be credited.
    let credit;
    try {
      credit = await new CreditPointsCommand(this.commandContext).execute({
        account: member,
        amount: points,
        reason: `Attended ${match?.cardTitle ?? 'a match'}`,
        source: 'Attendance',
        realm,
      });
    } catch (error) {
      await new PatchCardInstanceCommand(this.commandContext, {
        cardType: Booking,
      }).execute({
        cardId: checkedInBooking.id!,
        patch: { attributes: { checkedInAt: null } },
      });
      throw error;
    }

    return new RecordAttendanceResult({
      booking: checkIn.booking,
      transaction: credit.transaction,
      pointsAwarded: points,
      message: `${checkIn.message}; ${credit.message}`,
    });
  }
}
