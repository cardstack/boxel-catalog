import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateField from '@cardstack/base/date';
import AwardIcon from '@cardstack/boxel-icons/award';

import { LoyaltyAccount, PointsTransaction } from '../loyalty-account';
import { LoyaltyTierField, nextTier, tierOption } from '../loyalty-tier-field';
import { LoyaltyDashboard } from '../components/loyalty-dashboard';

// Usage page for the Loyalty Dashboard block. The consumer owns the ladder
// and the ledger, so this card resolves the tier and the next rung, picks
// the recent rows and states the expiry callout, and hands them over.
export class LoyaltyDashboardExample extends CardDef {
  static displayName = 'Loyalty Dashboard Example';
  static icon = AwardIcon;

  @field account = linksTo(() => LoyaltyAccount);
  @field recent = linksToMany(() => PointsTransaction);
  @field expiringPoints = contains(NumberField);
  @field expiringOn = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: LoyaltyDashboardExample) {
      return `Loyalty Dashboard — ${this.account?.cardTitle ?? 'no member'}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get tier() {
      return tierOption(LoyaltyTierField, this.args.model.account?.tier);
    }

    get next() {
      return nextTier(LoyaltyTierField, this.args.model.account?.tier);
    }

    <template>
      <div class='demo'>
        {{#if @model.account}}
          <LoyaltyDashboard
            @account={{@model.account}}
            @tier={{this.tier}}
            @nextTier={{this.next}}
            @transactions={{@model.recent}}
            @expiringPoints={{@model.expiringPoints}}
            @expiringOn={{@model.expiringOn}}
          />
        {{/if}}
      </div>
      <style scoped>
        .demo {
          padding: var(--boxel-sp-lg);
          max-width: 44rem;
        }
      </style>
    </template>
  };
}
