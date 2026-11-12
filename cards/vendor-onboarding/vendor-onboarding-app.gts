import {
  CardDef,
  Component,
  field,
  contains,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import { identifyCard } from '@cardstack/runtime-common';
import BuildingIcon from '@cardstack/boxel-icons/building-2';

import { VendorProfile } from '../procurement/vendor-profile';
import { Detail, Metric, RichFittedCard } from '../shared/rich-fitted-card';
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
    // The console's board counts, from one query that is not live: the tile
    // shows the numbers as of its last render.
    private profiles = (() => {
      let ref = identifyCard(VendorProfile);
      let query = ref ? { filter: { type: ref } } : undefined;
      let url = this.args.model?.[realmURL];
      let realms = url ? [url.href] : undefined;
      return this.args.context?.getCards(
        this,
        () => query,
        () => realms,
      );
    })();

    // Undefined while loading, so the metric and details render nothing.
    get s() {
      let q = this.profiles;
      if (!q || q.isLoading) return undefined;
      let all = (q.instances as VendorProfile[]).filter(Boolean);
      let stage = (p: VendorProfile) => p.status ?? 'intake';
      let waiting = all.filter((p) =>
        ['intake', 'under-review'].includes(stage(p)),
      ).length;
      let lapsed = all.filter((p) => !p.complianceOk).length;
      return {
        profiles: String(all.length),
        waiting: String(waiting),
        ready: String(all.filter((p) => stage(p) === 'approved').length),
        lapsed: String(lapsed),
        compliant: String(all.length - lapsed),
        fact: !all.length
          ? 'No vendor profiles yet'
          : !waiting && !lapsed
            ? 'Pipeline clear'
            : `${waiting} waiting on review · ${lapsed} with lapsed compliance`,
      };
    }

    <template>
      <RichFittedCard>
        <:avatar><BuildingIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>Vendor Onboarding</:title>
        <:subtitle>Procurement</:subtitle>
        <:metric>{{#if this.s}}<Metric
              @value={{this.s.profiles}}
              @label='Profiles'
            />{{/if}}</:metric>
        <:fact>{{if
            this.s
            this.s.fact
            'Intake, review, approve and onboard vendors'
          }}</:fact>
        <:details>{{#if this.s}}
            <Detail @label='Awaiting review' @value={{this.s.waiting}} />
            <Detail @label='Ready to onboard' @value={{this.s.ready}} />
            <Detail @label='Lapsed compliance' @value={{this.s.lapsed}} />
            <Detail @label='Compliant' @value={{this.s.compliant}} />
          {{/if}}</:details>
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
