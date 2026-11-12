import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import BuildingIcon from '@cardstack/boxel-icons/building-2';

import { RichFittedCard } from '../shared/rich-fitted-card';
import { VendorOnboardingConsole } from './vendor-onboarding-console';

// The buyer's intake console: every Vendor Profile on a vetting pipeline,
// with the review queue, lapsed credentials and the procurement records that
// follow onboarding (vendors, RFQs, purchase orders, goods receipts).
export class VendorOnboardingApp extends CardDef {
  static displayName = 'Vendor Onboarding';
  static prefersWideFormat = true;
  static icon = BuildingIcon;

  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'Vendor Onboarding';
    },
  });

  static isolated = VendorOnboardingConsole;

  static fitted = class Fitted extends Component<typeof VendorOnboardingApp> {
    <template>
      <RichFittedCard>
        <:avatar><BuildingIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>Vendor Onboarding</:title>
        <:subtitle>Procurement</:subtitle>
        <:fact>Intake, review, approve and onboard vendors</:fact>
      </RichFittedCard>
      <style scoped>
        .app-mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
