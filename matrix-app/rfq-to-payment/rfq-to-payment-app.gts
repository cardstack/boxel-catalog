import {
  CardDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';

import { FitTile } from '../shared/fit-tile';
import { RfqToPaymentConsole } from './rfq-to-payment-console';

// RFQ to Payment: the buyer's Procure-to-Pay console. It live-queries every
// stage of the chain (requisition → RFQ → PO → receipt → vendor invoice),
// shows them as a stat strip whose tiles open pre-filtered lists, and keeps
// every status transition on its owning card's command.
export class RfqToPaymentApp extends CardDef {
  static displayName = 'RFQ to Payment';
  static prefersWideFormat = true;
  static icon = ReceiptIcon;

  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'RFQ to Payment';
    },
  });

  static isolated = RfqToPaymentConsole;

  static fitted = class Fitted extends Component<typeof RfqToPaymentApp> {
    <template>
      <FitTile>
        <:title>RFQ to Payment</:title>
        <:subtitle>Procure-to-Pay console</:subtitle>
        <:fact>Requisition, quote, approve, receive and pay</:fact>
      </FitTile>
    </template>
  };
}
