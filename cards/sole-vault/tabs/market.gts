import GlimmerComponent from '@glimmer/component';
import { CollectionPanel } from '../../../components/collection-panel';
import { Listing } from '../../collectibles/listing';
import type { SoleVaultView } from '../sole-vault-app';

interface Signature {
  Args: {
    tracker: SoleVaultView;
    context: SoleVaultView['args']['context'];
  };
}

export class MarketTab extends GlimmerComponent<Signature> {
  <template>
    <section class='pane pane--market'>
      {{! @sortBy is REQUIRED here, not a tuning knob: the panel's
      default sort field is the legacy `title`, which cards no
      longer carry (it is `cardTitle` now) — and a sort naming a
      field the card does not have returns an EMPTY result on the
      prerendered grid/strip path, while the table's instances path
      tolerates it. That asymmetry rendered "No active listings
      yet" in grid view over the same three rows the table showed. }}
      <CollectionPanel
        @cardClass={{Listing}}
        @context={{@context}}
        @realms={{@tracker.realmHrefs}}
        @label='Active listings'
        @searchPlaceholder='Search active listings'
        @newLabel='Listing'
        @defaultView='grid'
        @sortBy='productTitle'
        @extraFilter={{@tracker.activeListingFilter}}
        @columns={{@tracker.listingColumns}}
      />
    </section>
    <style scoped>
      .pane {
        animation: stage-enter 240ms cubic-bezier(0.16, 1, 0.3, 1) both;
      }
      @media (prefers-reduced-motion: reduce) {
        .pane {
          animation: none;
        }
      }
    </style>
  </template>
}
