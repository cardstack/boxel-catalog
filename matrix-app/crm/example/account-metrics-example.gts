import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import GaugeIcon from '@cardstack/boxel-icons/gauge';

import { Account } from '../account';
import { AccountMetrics } from '../components/account-metrics';

// Usage page for the Account Metrics block: one account's revenue health,
// read live from the invoices and subscriptions in its realm.
export class AccountMetricsExample extends CardDef {
  static displayName = 'Account Metrics Example';
  static icon = GaugeIcon;

  @field account = linksTo(() => Account);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AccountMetricsExample) {
      return `Account Metrics — ${this.account?.name ?? 'no account'}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <div class='demo'>
        <h2>{{if @model.account.name @model.account.name 'No account'}}</h2>
        <AccountMetrics @account={{@model.account}} @context={{@context}} />
      </div>
      <style scoped>
        .demo {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp);
        }
        h2 {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
