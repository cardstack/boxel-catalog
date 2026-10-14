import { Command } from '@cardstack/runtime-common';
import {
  CardDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { CollectionItem } from '../collection-item';
import { Listing, ListingStatusField } from '../listing';
import { canTransition } from '@cardstack/catalog/fields/status/status';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import { isCardOfType } from '@cardstack/catalog/utils/card-type';

const OUTCOMES = ['sold', 'cancelled', 'expired'] as const;
type Outcome = (typeof OUTCOMES)[number];

export class CloseListingInput extends CardDef {
  @field listingId = contains(StringField);
  @field outcome = contains(StringField, {
    description: "How the listing ended: 'sold', 'cancelled' or 'expired'.",
  });
}

export class CloseListingResult extends CardDef {
  @field listingId = contains(StringField);
  @field outcome = contains(StringField);
}

// Close Listing ends an active listing and takes its item off sale.
//
// The item's `forSale` is a computed read of `listedAt`, which Create Listing
// writes. This command is the other half: it moves the Listing out of
// `active` and clears `listedAt` on the item, so the item stops showing as for
// sale and can be listed again. Running it again on a listing that is already
// closed with the same outcome only re-clears `listedAt`.
export default class CloseListingCommand extends Command<
  typeof CloseListingInput,
  typeof CloseListingResult
> {
  static actionVerb = 'Close listing';
  description =
    'End an active listing as sold, cancelled or expired, and take its collection item off sale.';

  async getInputType() {
    return CloseListingInput;
  }

  protected async run(input: CloseListingInput): Promise<CloseListingResult> {
    let listingId = input.listingId?.trim();
    if (!listingId) {
      throw new Error('listingId is required');
    }
    let outcome = input.outcome?.trim() as Outcome;
    if (!OUTCOMES.includes(outcome)) {
      throw new Error(`outcome must be one of ${OUTCOMES.join(', ')}`);
    }

    let listing = await new GetCardCommand(this.toolContext).execute({
      cardId: listingId,
    });
    if (!listing) {
      throw new Error(`Listing not found: ${listingId}`);
    }
    if (!isCardOfType(listing, Listing)) {
      throw new Error(`${listingId} is not a Listing`);
    }

    let current = listing.listingStatus;
    if (current !== outcome) {
      if (!canTransition(ListingStatusField, current, outcome)) {
        throw new Error(
          `Listing ${listingId} is ${current ?? 'unset'} and cannot become ${outcome}`,
        );
      }
      await new PatchCardInstanceCommand(this.toolContext, {
        cardType: Listing,
      }).execute({
        cardId: listingId,
        patch: { attributes: { listingStatus: outcome } },
      });
    }

    let itemId = linkedId(listing, 'collectionItem');
    if (itemId) {
      await new PatchCardInstanceCommand(this.toolContext, {
        cardType: CollectionItem,
      }).execute({
        cardId: itemId,
        patch: { attributes: { listedAt: null } },
      });
    }

    let result = new CloseListingResult();
    result.listingId = listingId;
    result.outcome = outcome;
    return result;
  }
}
