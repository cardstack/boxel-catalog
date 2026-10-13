import { Command } from '@cardstack/runtime-common';
import {
  CardDef,
  StringField,
  contains,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { CollectionItem } from '../collection-item';
import { Listing } from '../listing';
import { SellerProfile } from '../seller-profile';
import { CollectibleProduct } from '../collectible-product';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import { findCard } from '@cardstack/catalog/utils/find-card';
import { toCalendarDay } from '../acquisition';

export class CreateListingInput extends CardDef {
  @field collectionItemId = contains(StringField);
  @field price = contains(NumberField);
  @field currency = contains(StringField);
  @field shippingPrice = contains(NumberField);
  @field shipsFrom = contains(StringField);
}

export class CreateListingResult extends CardDef {
  @field listingId = contains(StringField);
}

// Create Listing (CL) — marks an owned copy for sale.
//
// THE COLLECTION ITEM'S `forSale` FLAG IS A COMPUTED READ OF `listedAt`, so
// this command writes `listedAt`, never a boolean — same rule
// `collection-item.gts`'s header applies to `verified`: a threshold flag is
// an event fact, and storing the boolean separately is how it drifts from
// the listing that actually caused it.
export default class CreateListingCommand extends Command<
  typeof CreateListingInput,
  typeof CreateListingResult
> {
  static actionVerb = 'Create listing';
  description =
    'List an owned collection item for sale at a given price, denormalizing the seller and product from it.';

  async getInputType() {
    return CreateListingInput;
  }

  protected async run(input: CreateListingInput): Promise<CreateListingResult> {
    let collectionItemId = input.collectionItemId?.trim();
    if (!collectionItemId) {
      throw new Error('collectionItemId is required');
    }
    if (input.price == null) {
      throw new Error('price is required');
    }

    let collectionItem = (await new GetCardCommand(this.toolContext).execute({
      cardId: collectionItemId,
    })) as CollectionItem;
    if (!collectionItem) {
      throw new Error(`CollectionItem not found: ${collectionItemId}`);
    }
    let ownerId = linkedId(collectionItem, 'owner');
    if (!ownerId) {
      throw new Error(
        `CollectionItem ${collectionItemId} has no owner to list as seller`,
      );
    }
    let owner = await new GetCardCommand(this.toolContext).execute({
      cardId: ownerId,
    });
    if (!(owner instanceof SellerProfile)) {
      throw new Error(
        `CollectionItem ${collectionItemId}'s owner is not a Seller Profile, so it cannot be listed`,
      );
    }
    let productId = linkedId(collectionItem, 'item');
    let product = productId
      ? await new GetCardCommand(this.toolContext).execute({
          cardId: productId,
        })
      : undefined;
    if (!(product instanceof CollectibleProduct)) {
      throw new Error(
        `CollectionItem ${collectionItemId} is not a Collectible Product, so it cannot be listed`,
      );
    }
    // An active Listing is what makes an item for sale. `forSale` on the item
    // follows it through Create Listing and Close Listing, but a listing whose
    // status was changed by hand leaves the flag behind, so the guard reads the
    // listings themselves. A closed listing does not block relisting.
    let realm = (collectionItem as any)?.[realmURL]?.href;
    let active = realm
      ? await findCard<Listing>(
          this.commandContext,
          Listing,
          { 'collectionItem.id': collectionItem.id, listingStatus: 'active' },
          realm,
        )
      : undefined;
    if (active) {
      throw new Error(
        `CollectionItem ${collectionItemId} is already for sale in ${active.id}`,
      );
    }

    let currency = new CurrencyField({ code: input.currency?.trim() || 'USD' });
    let now = new Date();

    let listing = new Listing();
    listing.collectionItem = collectionItem;
    listing.product = product;
    listing.price = new AmountWithCurrency({ amount: input.price, currency });
    listing.shippingPrice = new AmountWithCurrency({
      amount: input.shippingPrice ?? 0,
      currency,
    });
    listing.listingStatus = 'active';
    listing.shipsFrom = input.shipsFrom?.trim() || '';
    listing.seller = owner;
    listing.listedAt = now;

    // Save into the SOURCE card's own realm. Without `realm`, SaveCard
    // defaults to the base realm and the write 401s.
    let saved = (await new SaveCardCommand(this.toolContext).execute({
      card: listing,
      realm,
    })) as Listing;

    await new PatchCardInstanceCommand(this.toolContext, {
      cardType: CollectionItem,
    }).execute({
      cardId: collectionItemId,
      patch: { attributes: { listedAt: toCalendarDay(now) } },
    });

    let result = new CreateListingResult();
    result.listingId = saved.id;
    return result;
  }
}
