import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';

import { FittedCard } from '@cardstack/boxel-ui/components';

import { RfqToPaymentConsole } from './rfq-to-payment-console';

// RFQ to Payment: the buyer's Procure-to-Pay console. It composes the
// procurement blocks: it live-queries every stage of the chain,
// narrates it as a flow rail (Requisitions → RFQs → Approvals → Receiving)
// whose stations click through to pre-filtered lists, renders budgets
// through ProcurementBudget's own embedded format (the dual-segment
// commitment bar), and keeps every status transition on its owning command —
// no drag-to-approve here, deliberately. Prerender gets a static shell.
export class RfqToPaymentApp extends CardDef {
  static displayName = 'RFQ to Payment';
  static prefersWideFormat = true;

  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'RFQ to Payment';
    },
  });

  static isolated = RfqToPaymentConsole;

  // Identity-bearing fitted — same command-band world as its sibling app,
  // with the P2P rail as the family glyph. Static (prerender-safe), anchor
  // typographic, type scale capped against cqb so no quantum can shear.
  static fitted = class Fitted extends Component<typeof RfqToPaymentApp> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow><span class='eyebrow'>Procurement</span></:eyebrow>
        <:title>RFQ to Payment</:title>
        <:subtitle>Requisition, quote, approve, receive and pay</:subtitle>
      </FittedCard>
      <style scoped>
        .eyebrow {
          color: var(--primary-ink);
        }
      </style>
    </template>
  };
}
