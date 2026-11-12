import {
  CardDef,
  Component,
  field,
  contains,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';

import { PurchaseRequisition } from '../procurement/purchase-requisition';
import { Rfq } from '../procurement/rfq';
import { PurchaseOrder } from '../procurement/purchase-order';
import { Invoice } from '../commerce/invoice';
import { Detail, Metric, RichFittedCard } from '../shared/rich-fitted-card';
import { RfqToPaymentConsole } from './rfq-to-payment-console';
import {
  awaitingReceiptPos,
  comparingRfqs,
  inApFlight,
  isApInvoice,
  openRequisitions,
  pendingApprovalPos,
} from './rfq-to-payment-data';

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
    // The console's station counts, one query per stage, not live: the tile
    // shows the numbers as of its last render. Vendor onboarding has its own
    // app and is not counted here.
    private query = (cls: typeof CardDef) => {
      let ref = identifyCard(cls);
      let query = ref ? { filter: { type: ref } } : undefined;
      let url = this.args.model?.[realmURL];
      let realms = url ? [url.href] : undefined;
      return this.args.context?.getCards(
        this,
        () => query,
        () => realms,
      );
    };
    private pos = this.query(PurchaseOrder);
    private requisitions = this.query(PurchaseRequisition);
    private rfqs = this.query(Rfq);
    private invoices = this.query(Invoice);
    private rows<T>(q: ReturnType<getCards> | undefined): T[] {
      return ((q?.instances ?? []) as T[]).filter(Boolean);
    }

    // Undefined while loading, so the metric and details render nothing.
    get s() {
      let lists = [this.pos, this.requisitions, this.rfqs, this.invoices];
      if (lists.some((q) => !q || q.isLoading)) return undefined;
      let pos = this.rows<PurchaseOrder>(this.pos);
      return {
        approvals: String(pendingApprovalPos(pos).length),
        receiving: String(awaitingReceiptPos(pos).length),
        requisitions: String(
          openRequisitions(this.rows<PurchaseRequisition>(this.requisitions))
            .length,
        ),
        rfqs: String(comparingRfqs(this.rows<Rfq>(this.rfqs)).length),
        match: String(
          inApFlight(this.rows<Invoice>(this.invoices).filter(isApInvoice))
            .length,
        ),
      };
    }

    <template>
      <RichFittedCard>
        <:avatar><ReceiptIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>RFQ to Payment</:title>
        <:subtitle>Procure-to-Pay console</:subtitle>
        <:metric>{{#if this.s}}<Metric
              @value={{this.s.approvals}}
              @label='Awaiting approval'
            />{{/if}}</:metric>
        <:fact>Requisition, quote, approve, receive and pay</:fact>
        <:details>{{#if this.s}}
            <Detail @label='Open requisitions' @value={{this.s.requisitions}} />
            <Detail @label='RFQs comparing' @value={{this.s.rfqs}} />
            <Detail @label='Awaiting receipt' @value={{this.s.receiving}} />
            <Detail @label='Match and pay' @value={{this.s.match}} />
          {{/if}}</:details>
      </RichFittedCard>
      <style scoped>
        .app-mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
