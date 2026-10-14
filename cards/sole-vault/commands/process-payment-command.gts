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
import { Payment } from '../payment';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import { currencyCode } from '../../collectibles/money-format';

export class ProcessPaymentInput extends CardDef {
  @field orderId = contains(StringField);
  @field processor = contains(StringField);
}

export class ProcessPaymentResult extends CardDef {
  @field paymentId = contains(StringField);
  @field orderStatus = contains(StringField);
}

// Process Payment: charges the buyer's escrow-held total.
//
// A SIMULATION, STATED PLAINLY. `order.gts`'s own header note says it: a
// realm cannot hold funds, so this records a `Payment` in the `captured`
// state directly rather than modelling `pending`→`authorized`→`captured` as
// a real processor round-trip. What matters for the escrow graph is the
// EFFECT — the order moves to `paid` and the total is now held — not a
// faithful simulation of a payment gateway's own async state machine.
export default class ProcessPaymentCommand extends Command<
  typeof ProcessPaymentInput,
  typeof ProcessPaymentResult
> {
  static actionVerb = 'Process payment';
  description =
    'Charge the order total and move the order from pending-payment to paid, recording a Payment.';

  async getInputType() {
    return ProcessPaymentInput;
  }

  protected async run(
    input: ProcessPaymentInput,
  ): Promise<ProcessPaymentResult> {
    let orderId = input.orderId?.trim();
    if (!orderId) {
      throw new Error('orderId is required');
    }

    let order = await new GetCardCommand(this.toolContext).execute({
      cardId: orderId,
    });
    if (!isCardOfType(order, Order)) {
      throw new Error(`Order not found: ${orderId}`);
    }
    if (!canOrderTransition(order.orderStatus, 'paid')) {
      throw new Error(
        `Order ${orderId} cannot move from ${order.orderStatus} to paid`,
      );
    }
    if (!order.total?.amount) {
      throw new Error(`Order ${orderId} has no total to charge`);
    }

    let now = new Date();
    let processorReference = `sim-pi-${Math.random().toString(36).slice(2, 10)}`;

    let payment = new Payment();
    payment.order = order;
    payment.amount = new AmountWithCurrency({
      amount: order.total.amount,
      currency: new CurrencyField({ code: currencyCode(order.total) }),
    });
    payment.paymentState = 'captured';
    payment.direction = 'charge';
    payment.processor = input.processor?.trim() || 'Simulated Processor';
    payment.processorReference = processorReference;
    payment.initiatedAt = now;
    payment.settledAt = now;

    // Saved into the order's own realm; without `realm`, SaveCard targets the
    // base realm and the write is refused.
    let realm = (order as any)?.[realmURL]?.href;
    // The order moves first, because that is the step its state machine can
    // refuse. If the payment record then fails to save, the order goes back.
    let patchOrder = (attributes: Record<string, unknown>) =>
      new PatchCardInstanceCommand(this.toolContext, {
        cardType: Order,
      }).execute({ cardId: orderId, patch: { attributes } });
    await patchOrder({
      orderStatus: 'paid',
      paidAt: toCalendarDay(now),
      paymentReference: processorReference,
    });
    let saved: Payment;
    try {
      saved = (await new SaveCardCommand(this.toolContext).execute({
        card: payment,
        realm,
      })) as Payment;
    } catch (e) {
      await patchOrder({
        orderStatus: order.orderStatus ?? null,
        paidAt: order.paidAt ? toCalendarDay(order.paidAt) : null,
        paymentReference: order.paymentReference ?? null,
      });
      throw e;
    }

    let result = new ProcessPaymentResult();
    result.paymentId = saved.id;
    result.orderStatus = 'paid';
    return result;
  }
}
