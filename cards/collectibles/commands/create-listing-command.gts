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
import { toCalendarDay } from '../acquisition';
import { isCardOfType } from '@cardstack/catalog/utils/card-type';
import { activeListingFor } from './active-listing';

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
//
// Only a SellerProfile can list: a Listing's seller links to one. Add To
// Collection accepts any MarketplaceMember, because owning doesn't require
// selling.
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

    let collectionItem = await new GetCardCommand(this.toolContext).execute({
      cardId: collectionItemId,
    });
    if (!collectionItem) {
      throw new Error(`CollectionItem not found: ${collectionItemId}`);
    }
    if (!isCardOfType(collectionItem, CollectionItem)) {
      throw new Error(`${collectionItemId} is not a Collection Item`);
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
    if (!isCardOfType(owner, SellerProfile)) {
      throw new Error(
        `CollectionItem ${collectionItemId}'s owner is not a Seller Profile, so it cannot be listed. Only a Seller Profile can sell; a Marketplace Member can only collect.`,
      );
    }
    let productId = linkedId(collectionItem, 'item');
    if (!productId) {
      throw new Error(
        `CollectionItem ${collectionItemId} has no product to list`,
      );
    }
    let product = await new GetCardCommand(this.toolContext).execute({
      cardId: productId,
    });
    if (!isCardOfType(product, CollectibleProduct)) {
      throw new Error(
        `CollectionItem ${collectionItemId}'s product ${productId} is not a Collectible Product, so it cannot be listed`,
      );
    }
    // Two signals, so neither index lag can let a second listing through: the
    // item's own `listedAt`, which this command writes and Close Listing
    // clears, catches a listing the index hasn't seen yet; the item's
    // listings, confirmed on their fetched cards, catch one whose `listedAt`
    // write was interrupted.
    if (collectionItem.listedAt) {
      throw new Error(
        `CollectionItem ${collectionItemId} is already for sale; close its listing first`,
      );
    }
    let realm = (collectionItem as any)?.[realmURL]?.href;
    let active = await activeListingFor(
      this.commandContext,
      collectionItemId,
      realm,
    );
    if (active) {
      throw new Error(
        `CollectionItem ${collectionItemId} is already for sale in ${active.id}`,
      );
    }

    let code = input.currency?.trim() || 'USD';
    let now = new Date();

    let listing = new Listing();
    listing.collectionItem = collectionItem;
    listing.product = product;
    // Each amount owns its own CurrencyField: a contained field instance
    // belongs to one parent.
    listing.price = new AmountWithCurrency({
      amount: input.price,
      currency: new CurrencyField({ code }),
    });
    listing.shippingPrice = new AmountWithCurrency({
      amount: input.shippingPrice ?? 0,
      currency: new CurrencyField({ code }),
    });
    listing.listingStatus = 'active';
    listing.shipsFrom = input.shipsFrom?.trim() || '';
    listing.seller = owner;
    listing.listedAt = now;

    // The item is marked listed first, and unmarked if the listing doesn't
    // save, so a failure leaves neither half behind.
    let patchItem = (listedAt: string | null) =>
      new PatchCardInstanceCommand(this.toolContext, {
        cardType: CollectionItem,
      }).execute({
        cardId: collectionItemId,
        patch: { attributes: { listedAt } },
      });
    await patchItem(toCalendarDay(now));
    let saved: Listing;
    try {
      // Save into the SOURCE card's own realm. Without `realm`, SaveCard
      // defaults to the base realm and the write 401s.
      saved = (await new SaveCardCommand(this.toolContext).execute({
        card: listing,
        realm,
      })) as Listing;
    } catch (e) {
      await patchItem(null);
      throw e;
    }

    let result = new CreateListingResult();
    result.listingId = saved.id;
    return result;
  }
}
