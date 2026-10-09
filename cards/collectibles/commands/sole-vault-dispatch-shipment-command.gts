import { Command } from '@cardstack/runtime-common';
import {
  CardDef,
  StringField,
  contains,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Order, canOrderTransition } from '../sole-vault-order';
import { Shipment } from '../sole-vault-shipment';

export class DispatchShipmentInput extends CardDef {
  @field orderId = contains(StringField);
  @field carrier = contains(StringField);
  @field trackingNumber = contains(StringField);
  @field trackingUrl = contains(StringField);
  @field shippedFrom = contains(StringField);
  @field shippedTo = contains(StringField);
  // 'seller-to-auth' | 'auth-to-buyer': the two legs of the authentication-
  // centre route. Freeform on purpose, same call as
  // `shipment.gts`'s own `leg` field: the block names no fixed vocabulary.
  @field leg = contains(StringField);
}

export class DispatchShipmentResult extends CardDef {
  @field shipmentId = contains(StringField);
  @field orderStatus = contains(StringField);
}

// Dispatch Shipment (DS) — the seller hands a parcel to a carrier.
//
// It works on Sole Vault's Order and Shipment. The fulfilment cluster's own
// dispatch command patches a Fulfilment Order and quotes through a Carrier,
// which this marketplace does not have.
export default class DispatchShipmentCommand extends Command<
  typeof DispatchShipmentInput,
  typeof DispatchShipmentResult
> {
  static actionVerb = 'Dispatch shipment';
  description =
    'Create a shipment leg for a paid order, and move the order from paid to shipped.';

  async getInputType() {
    return DispatchShipmentInput;
  }

  protected async run(
    input: DispatchShipmentInput,
  ): Promise<DispatchShipmentResult> {
    let orderId = input.orderId?.trim();
    if (!orderId) {
      throw new Error('orderId is required');
    }
    let trackingNumber = input.trackingNumber?.trim();
    if (!trackingNumber) {
      throw new Error('trackingNumber is required');
    }

    let order = (await new GetCardCommand(this.toolContext).execute({
      cardId: orderId,
    })) as Order;
    if (!order) {
      throw new Error(`Order not found: ${orderId}`);
    }
    if (!canOrderTransition(order.orderStatus, 'shipped')) {
      throw new Error(
        `Order ${orderId} cannot move from ${order.orderStatus} to shipped`,
      );
    }

    let now = new Date();

    let shipment = new Shipment();
    shipment.order = order;
    shipment.leg = input.leg?.trim() || 'seller-to-auth';
    shipment.shipmentStatus = 'label-created';
    shipment.carrier = input.carrier?.trim() || '';
    shipment.trackingNumber = trackingNumber;
    shipment.trackingUrl = input.trackingUrl?.trim() || '';
    shipment.shippedFrom = input.shippedFrom?.trim() || '';
    shipment.shippedTo = input.shippedTo?.trim() || '';
    shipment.labelCreatedAt = now;

    // Save into the SOURCE card's own realm. Without `realm`, SaveCard
    // defaults to the base realm and the write 401s — verified live when a
    // ProcessPayment run tried to save its Payment to cardstack.com/base/.
    let realm = (order as any)?.[realmURL]?.href;
    let saved = (await new SaveCardCommand(this.toolContext).execute({
      card: shipment,
      realm,
    })) as Shipment;

    await new PatchCardInstanceCommand(this.toolContext, {
      cardType: Order,
    }).execute({
      cardId: orderId,
      patch: {
        attributes: {
          orderStatus: 'shipped',
          shippedAt: now.toISOString().slice(0, 10),
          trackingNumber,
        },
      },
    });

    let result = new DispatchShipmentResult();
    result.shipmentId = saved.id;
    result.orderStatus = 'shipped';
    return result;
  }
}
