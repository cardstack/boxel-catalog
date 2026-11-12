import { OrderFulfilmentDesk } from './order-fulfilment-desk';
import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  realmURL,
} from '@cardstack/base/card-api';
import type { getCards } from '@cardstack/runtime-common';
import { Detail, Metric, RichFittedCard } from '../shared/rich-fitted-card';
import PackageIcon from '@cardstack/boxel-icons/package';
import { FulfilmentOrder } from '../fulfilment/fulfilment-order';
import { Shipment } from '../fulfilment/shipment';
import { isShipmentException } from '../fulfilment/shipment-status';
import { byType } from './order-fulfilment-helpers';

export class OrderFulfilmentApp extends CardDef {
  static displayName = 'Order Fulfilment';
  static icon = PackageIcon;
  // Five columns of board, a stock table with six numeric columns, and a rate
  // comparison that splits in two — none of them survive a narrow stack. The
  // app asks for the full width rather than degrading into a single column.
  static prefersWideFormat = true;

  @field operationName = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: OrderFulfilmentApp) {
      return this.operationName?.length
        ? this.operationName
        : 'Order Fulfilment';
    },
  });

  static isolated = OrderFulfilmentDesk;

  static embedded = class Embedded extends Component<
    typeof OrderFulfilmentApp
  > {
    <template>
      <div class='app-emb'>
        <span class='app-name'>{{@model.operationName}}</span>
        <span class='app-sub'>Order fulfilment workspace</span>
      </div>
      <style scoped>
        .app-emb {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
        }
        .app-name {
          font-weight: 700;
          color: var(--foreground);
        }
        .app-sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof OrderFulfilmentApp> {
    <template>
      <span class='app-atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .app-atom {
          font-weight: 600;
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof OrderFulfilmentApp> {
    // The desk's board counts, from the order and shipment queries, not live:
    // the tile shows the numbers as of its last render.
    private query = (cls: typeof CardDef) => {
      let query = byType(cls);
      let url = this.args.model?.[realmURL];
      let realms = url ? [url.href] : undefined;
      return this.args.context?.getCards(
        this,
        () => query,
        () => realms,
      );
    };
    private orders = this.query(FulfilmentOrder);
    private shipments = this.query(Shipment);
    private rows<T>(q: ReturnType<getCards> | undefined): T[] {
      return ((q?.instances ?? []) as T[]).filter(Boolean);
    }

    // Undefined while loading, so the metric and details render nothing.
    get s() {
      if ([this.orders, this.shipments].some((q) => !q || q.isLoading)) {
        return undefined;
      }
      let orders = this.rows<FulfilmentOrder>(this.orders);
      let shipments = this.rows<Shipment>(this.shipments);
      let status = (o: FulfilmentOrder) => o.status ?? '';
      let attention = shipments.filter(
        (s) =>
          isShipmentException(s.status) ||
          (s.isLate && s.status !== 'delivered'),
      );
      return {
        toFulfil: String(
          orders.filter((o) =>
            ['pending', 'processing', 'picking', 'packing'].includes(status(o)),
          ).length,
        ),
        express: String(
          orders.filter(
            (o) =>
              o.isExpress && !['delivered', 'cancelled'].includes(status(o)),
          ).length,
        ),
        inTransit: String(
          shipments.filter(
            (s) => s.status === 'in_transit' || s.status === 'out_for_delivery',
          ).length,
        ),
        attention: String(attention.length),
      };
    }

    <template>
      <RichFittedCard>
        <:avatar><PackageIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Order fulfilment</:subtitle>
        <:metric>{{#if this.s}}<Metric
              @value={{this.s.toFulfil}}
              @label='To fulfil'
            />{{/if}}</:metric>
        <:details>{{#if this.s}}
            <Detail @label='Needs attention' @value={{this.s.attention}} />
            <Detail @label='Express' @value={{this.s.express}} />
            <Detail @label='In transit' @value={{this.s.inTransit}} />
          {{/if}}</:details>
        <:fact>{{if
            @model.cardInfo.summary
            @model.cardInfo.summary
            'Board · Inventory · Ship desk · In transit · Returns'
          }}</:fact>
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

export default OrderFulfilmentApp;
