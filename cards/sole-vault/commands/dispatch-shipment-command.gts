import { Command } from '@cardstack/runtime-common';
import {
  CardDef,
  StringField,
  contains,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import { isCardOfType } from '../../../utils/card-type';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Order, canOrderTransition } from '../order';
import { toCalendarDay } from '../../collectibles/acquisition';
import { Shipment } from '../shipment';

export class DispatchShipmentInput extends CardDef {
  @field orderId = contains(StringField);
  @field carrier = contains(StringField);
  @field trackingNumber = contains(StringField);
  @field trackingUrl = contains(StringField);
  @field shippedFrom = contains(StringField);
  @field shippedTo = contains(StringField);
  // 'seller-to-auth' | 'auth-to-buyer' — the two-leg authentication-centre
  // route the spec describes. Freeform on purpose, same call as
  // `shipment.gts`'s own `leg` field: the block names no fixed vocabulary.
  @field leg = contains(StringField);
}

export class DispatchShipmentResult extends CardDef {
  @field shipmentId = contains(StringField);
  @field orderStatus = contains(StringField);
}

// Dispatch Shipment: the seller hands a parcel to a carrier. Creates the
// shipping leg for a paid order and moves the order to shipped.
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

    let order = await new GetCardCommand(this.toolContext).execute({
      cardId: orderId,
    });
    if (!isCardOfType(order, Order)) {
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

    // Saved into the order's own realm; without `realm`, SaveCard targets the
    // base realm and the write is refused.
    let realm = (order as any)?.[realmURL]?.href;
    // The order moves first, because that is the step its state machine can
    // refuse. If the shipment record then fails to save, the order goes back.
    let patchOrder = (attributes: Record<string, unknown>) =>
      new PatchCardInstanceCommand(this.toolContext, {
        cardType: Order,
      }).execute({ cardId: orderId, patch: { attributes } });
    await patchOrder({
      orderStatus: 'shipped',
      shippedAt: toCalendarDay(now),
      trackingNumber,
    });
    let saved: Shipment;
    try {
      saved = (await new SaveCardCommand(this.toolContext).execute({
        card: shipment,
        realm,
      })) as Shipment;
    } catch (e) {
      await patchOrder({
        orderStatus: order.orderStatus ?? null,
        shippedAt: order.shippedAt ? toCalendarDay(order.shippedAt) : null,
        trackingNumber: order.trackingNumber ?? null,
      });
      throw e;
    }

    let result = new DispatchShipmentResult();
    result.shipmentId = saved.id;
    result.orderStatus = 'shipped';
    return result;
  }
}
