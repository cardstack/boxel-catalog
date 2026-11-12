import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import ShieldIcon from '@cardstack/boxel-icons/shield-half';

import { RichFittedCard } from '../shared/rich-fitted-card';
import { ClubConsole } from './club-console';

// A club's front office in one card: a season dashboard, each member's
// loyalty ledger, the fixture calendar and the match-day bookings. The
// club's own arithmetic (tier rates, attendance points) lives in its
// Record Attendance command.
export class ClubMembership extends CardDef {
  static displayName = 'Club Membership';
  static icon = ShieldIcon;
  static prefersWideFormat = true;

  @field clubName = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ClubMembership) {
      return this.clubName?.trim()?.length
        ? `${this.clubName} — Membership`
        : 'Club Membership';
    },
  });

  static isolated = ClubConsole;

  static fitted = class Fitted extends Component<typeof ClubMembership> {
    <template>
      <RichFittedCard>
        <:title>{{if
            @model.clubName
            @model.clubName
            'Club Membership'
          }}</:title>
        <:subtitle>Membership &amp; Ticketing</:subtitle>
        <:fact>Members, fixtures and match-day bookings</:fact>
      </RichFittedCard>
    </template>
  };
}
