import { Command } from '@cardstack/runtime-common';
import {
  CardDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import { isCardOfType } from '../../../utils/card-type';
import { linkedId } from '../../../utils/linked-id';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { Order, canOrderTransition } from '../order';
import { toCalendarDay } from '../../collectibles/acquisition';
import { Shipment, canShipmentTransition } from '../shipment';

export class MarkDeliveredInput extends CardDef {
  @field shipmentId = contains(StringField);
}

export class MarkDeliveredResult extends CardDef {
  @field shipmentId = contains(StringField);
  @field orderId = contains(StringField);
  @field orderStatus = contains(StringField);
}

// Mark Delivered: a carrier scan lands this leg, and the order moves by which
// leg it was. A `to-authenticator` delivery means the item reached the
// authentication centre, so the order moves `shipped` → `authenticating`. A
// `to-buyer` delivery means the buyer has it, so the order moves
// `authenticating` → `delivered`.
//
// No command moves an order from `delivered` to `completed`: that is the buyer
// confirming receipt, which a carrier scan is not.
export default class MarkDeliveredCommand extends Command<
  typeof MarkDeliveredInput,
  typeof MarkDeliveredResult
> {
  static actionVerb = 'Mark delivered';
  description =
    'Record a shipment leg as delivered and advance the order status appropriately for that leg.';

  async getInputType() {
    return MarkDeliveredInput;
  }

  protected async run(input: MarkDeliveredInput): Promise<MarkDeliveredResult> {
    let shipmentId = input.shipmentId?.trim();
    if (!shipmentId) {
      throw new Error('shipmentId is required');
    }

    let shipment = await new GetCardCommand(this.toolContext).execute({
      cardId: shipmentId,
    });
    if (!isCardOfType(shipment, Shipment)) {
      throw new Error(`Shipment not found: ${shipmentId}`);
    }
    if (!canShipmentTransition(shipment.shipmentStatus, 'delivered')) {
      throw new Error(
        `Shipment ${shipmentId} cannot move from ${shipment.shipmentStatus} to delivered`,
      );
    }

    let now = new Date();
    let patchShipment = (attributes: Record<string, unknown>) =>
      new PatchCardInstanceCommand(this.toolContext, {
        cardType: Shipment,
      }).execute({ cardId: shipmentId, patch: { attributes } });
    await patchShipment({
      shipmentStatus: 'delivered',
      deliveredAt: toCalendarDay(now),
    });

    let result = new MarkDeliveredResult();
    result.shipmentId = shipmentId;

    let orderId = linkedId(shipment, 'order');
    if (!orderId) {
      // A shipment with no order is a real state: nothing more to advance.
      return result;
    }
    result.orderId = orderId;

    // If the order cannot be read or written, the shipment goes back, so the
    // two never disagree about where the parcel is.
    let nextOrderStatus =
      shipment.leg === 'to-buyer' ? 'delivered' : 'authenticating';
    try {
      let order = await new GetCardCommand(this.toolContext).execute({
        cardId: orderId,
      });
      if (!isCardOfType(order, Order)) {
        throw new Error(`Order not found: ${orderId}`);
      }
      if (!canOrderTransition(order.orderStatus, nextOrderStatus)) {
        // The leg is still recorded; the order does not move (for example a
        // second scan on an order that has already advanced).
        result.orderStatus = order.orderStatus ?? undefined;
        return result;
      }
      await new PatchCardInstanceCommand(this.toolContext, {
        cardType: Order,
      }).execute({
        cardId: orderId,
        patch: {
          attributes:
            nextOrderStatus === 'authenticating'
              ? { orderStatus: 'authenticating' }
              : { orderStatus: 'delivered', deliveredAt: toCalendarDay(now) },
        },
      });
    } catch (e) {
      await patchShipment({
        shipmentStatus: shipment.shipmentStatus ?? null,
        deliveredAt: shipment.deliveredAt
          ? toCalendarDay(shipment.deliveredAt)
          : null,
      });
      throw e;
    }

    result.orderStatus = nextOrderStatus;
    return result;
  }
}
