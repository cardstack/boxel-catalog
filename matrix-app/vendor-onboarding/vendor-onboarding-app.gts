import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import BuildingIcon from '@cardstack/boxel-icons/building-2';

import { FitTile } from '../shared/fit-tile';
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
      <FitTile>
        <:title>Vendor Onboarding</:title>
        <:subtitle>Procurement</:subtitle>
        <:fact>Intake, review, approve and onboard vendors</:fact>
      </FitTile>
    </template>
  };
}
