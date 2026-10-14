import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import {
  statusField,
  canTransition,
  nextStatuses,
} from '../../fields/status/status';

export type OrderStatus =
  | 'pending-payment'
  | 'paid'
  | 'shipped'
  | 'authenticating'
  | 'delivered'
  | 'completed'
  | 'disputed'
  | 'refunded';

export const OrderStatusField = statusField({
  displayName: 'Order Status',
  icon: ReceiptIcon,
  options: [
    {
      value: 'pending-payment',
      label: 'Pending payment',
      hue: 'slate',
      meaning: 'Placed, but the buyer has not paid yet. Nothing is held.',
    },
    {
      value: 'paid',
      label: 'Paid',
      hue: 'blue',
      holds: true,
      meaning:
        'Funds are held in escrow. The seller owes a shipment; the platform owes a refund if anything fails.',
    },
    {
      value: 'shipped',
      label: 'Shipped',
      hue: 'purple',
      holds: true,
      meaning: 'In transit to the authentication centre, not to the buyer.',
    },
    {
      value: 'authenticating',
      label: 'Authenticating',
      hue: 'amber',
      holds: true,
      meaning:
        'Received and under inspection. The verdict decides whether this completes or refunds.',
    },
    {
      value: 'delivered',
      label: 'Delivered',
      hue: 'teal',
      holds: true,
      meaning: 'With the buyer, awaiting their confirmation.',
    },
    {
      value: 'completed',
      label: 'Completed',
      hue: 'green',
      terminal: true,
      holds: true,
      meaning: 'Buyer confirmed. Funds released to the seller.',
    },
    {
      value: 'disputed',
      label: 'Disputed',
      hue: 'orange',
      holds: true,
      meaning: 'Someone has raised a problem. Funds stay held until resolved.',
    },
    {
      value: 'refunded',
      label: 'Refunded',
      hue: 'red',
      terminal: true,
      holds: true,
      meaning: 'Money returned to the buyer. The item goes back to the seller.',
    },
  ],
  // The edges that are ABSENT carry as much meaning as the ones present:
  //
  //   * Nothing returns to `pending-payment`. Un-charging a card is a refund,
  //     which is its own terminal state with its own money movement.
  //   * `completed` leads nowhere. Once funds are released the platform no
  //     longer holds anything, so there is nothing left for this graph to move;
  //     a later problem is a new dispute record, not an edit to this one.
  //   * `refunded` leads nowhere for the same reason, in the other direction.
  //   * Authentication failure is `authenticating → refunded`, never
  //     `authenticating → delivered`. The spec is explicit: a failed legit check
  //     refunds the buyer and returns the item, so there must be no path that
  //     ships a fake onward.
  //   * Every money-holding state can reach `disputed`, because a problem can
  //     surface at any point while funds are held.
  transitions: {
    'pending-payment': ['paid', 'refunded'],
    paid: ['shipped', 'disputed', 'refunded'],
    shipped: ['authenticating', 'disputed', 'refunded'],
    authenticating: ['delivered', 'refunded', 'disputed'],
    delivered: ['completed', 'disputed'],
    disputed: ['completed', 'refunded'],
    completed: [],
    refunded: [],
  },
});

/** Re-exported so a command can ask permission without importing the field. */
export function canOrderTransition(from?: string | null, to?: string | null) {
  return canTransition(OrderStatusField, from, to);
}

/** What an action menu should offer for the current state. */
export function nextOrderStatuses(from?: string | null) {
  return nextStatuses(OrderStatusField, from);
}
