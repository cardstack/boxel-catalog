import { Command } from '@cardstack/runtime-common';
import {
  CardDef,
  StringField,
  contains,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import { currencyCode } from '../../collectibles/money-format';
import { MarketplaceMember } from '../../collectibles/marketplace-member';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import { isCardOfType } from '../../../utils/card-type';
import { linkedId } from '../../../utils/linked-id';
import { SellerProfile } from '../../collectibles/seller-profile';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Listing } from '../../collectibles/listing';
import { toCalendarDay } from '../../collectibles/acquisition';
import { Order } from '../order';

export class PlaceOrderInput extends CardDef {
  @field listingId = contains(StringField);
  @field buyerId = contains(StringField);
}

export class PlaceOrderResult extends CardDef {
  @field orderId = contains(StringField);
  @field reference = contains(StringField);
}

// Place Order: a buyer commits to a listing.
//
// FEES ARE SNAPSHOTS, PICKED HERE, NOT A RATE RE-DERIVED LATER. The auth fee
// and platform-fee percentage are the checkout's own numbers, applied once at
// order-creation time (a flat $10
// authentication fee, a 3% platform fee) — see `order.gts`'s header note on
// why `Order.platformFee` holds the money actually charged, never "3%".
//
// LISTING GOES `sold` HERE, NOT ON PAYMENT. `ListingStatusField`'s own
// `active` meaning is "visible to buyers and accepting offers"; `sold` means
// "a buyer committed — the item is spoken for". That commitment happens the
// moment an order is placed, before money moves, which is why this command —
// not ProcessPayment — is the one that flips it.
// `AmountWithCurrency.amount` is a decimal figure in the currency's own major
// unit (dollars, not cents — see `money-format.ts`'s header note on why this
// realm never scales to minor units), so $10.00 is the literal number 10.
const AUTH_FEE_AMOUNT = 10; // $10.00, flat
const PLATFORM_FEE_RATE = 0.03; // 3%

export default class PlaceOrderCommand extends Command<
  typeof PlaceOrderInput,
  typeof PlaceOrderResult
> {
  static actionVerb = 'Place order';
  description =
    'Create an order from an active listing, snapshotting price and fees, and mark the listing sold.';

  async getInputType() {
    return PlaceOrderInput;
  }

  protected async run(input: PlaceOrderInput): Promise<PlaceOrderResult> {
    let listingId = input.listingId?.trim();
    let buyerId = input.buyerId?.trim();
    if (!listingId) {
      throw new Error('listingId is required');
    }
    if (!buyerId) {
      throw new Error('buyerId is required');
    }

    let listing = await new GetCardCommand(this.toolContext).execute({
      cardId: listingId,
    });
    if (!isCardOfType(listing, Listing)) {
      throw new Error(`Listing not found: ${listingId}`);
    }
    if (listing.listingStatus !== 'active') {
      throw new Error(
        `Listing ${listingId} is not active (status: ${listing.listingStatus}) — cannot place an order against it`,
      );
    }
    if (!listing.price?.amount || !listing.price?.currency) {
      throw new Error(`Listing ${listingId} has no price set`);
    }
    let sellerId = linkedId(listing, 'seller');
    if (!sellerId) {
      throw new Error(`Listing ${listingId} has no seller`);
    }

    let code = currencyCode(listing.price);
    // Each amount gets its own currency: a contained field belongs to one
    // parent.
    let money = (amount: number) =>
      new AmountWithCurrency({ amount, currency: new CurrencyField({ code }) });
    let priceAmount = listing.price.amount;
    let shippingAmount = listing.shippingPrice?.amount ?? 0;
    let authFeeAmount = AUTH_FEE_AMOUNT;
    // Rounded to the nearest cent, not the nearest dollar — `amount` carries
    // two decimal places.
    let platformFeeAmount =
      Math.round(priceAmount * PLATFORM_FEE_RATE * 100) / 100;

    let now = new Date();
    let reference = `SV-${now.getFullYear()}-${now
      .getTime()
      .toString(36)
      .toUpperCase()}`;

    let order = new Order();
    order.reference = reference;
    order.listing = listing;
    let buyer = await new GetCardCommand(this.toolContext).execute({
      cardId: buyerId,
    });
    if (!isCardOfType(buyer, MarketplaceMember)) {
      throw new Error(`Buyer not found: ${buyerId}`);
    }
    order.buyer = buyer;
    let seller = await new GetCardCommand(this.toolContext).execute({
      cardId: sellerId,
    });
    if (!isCardOfType(seller, SellerProfile)) {
      throw new Error(`Seller not found: ${sellerId}`);
    }
    order.seller = seller;
    // Real AmountWithCurrency instances, not `{ amount, currency }` literals
    // — a plain object throws when the searchable walker's peekAtField
    // reaches it (see order.gts's `total` computeVia for the same note).
    order.price = money(priceAmount);
    order.shippingPrice = money(shippingAmount);
    order.authFee = money(authFeeAmount);
    order.platformFee = money(platformFeeAmount);
    order.orderStatus = 'pending-payment';
    order.placedAt = now;

    let realm = listing[realmURL]?.href;
    // The listing is marked sold first, so a second buyer cannot order it. If
    // the order then fails to save, the listing goes back on sale.
    let patchListing = (attributes: Record<string, unknown>) =>
      new PatchCardInstanceCommand(this.toolContext, {
        cardType: Listing,
      }).execute({ cardId: listingId, patch: { attributes } });
    await patchListing({ listingStatus: 'sold', soldAt: toCalendarDay(now) });
    let saved: Order;
    try {
      saved = (await new SaveCardCommand(this.toolContext).execute({
        card: order,
        realm,
      })) as Order;
    } catch (e) {
      await patchListing({
        listingStatus: listing.listingStatus ?? null,
        soldAt: listing.soldAt ? toCalendarDay(listing.soldAt) : null,
      });
      throw e;
    }

    let result = new PlaceOrderResult();
    result.orderId = saved.id;
    result.reference = reference;
    return result;
  }
}
