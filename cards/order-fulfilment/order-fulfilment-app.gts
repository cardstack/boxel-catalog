import { OrderFulfilmentDesk } from './order-fulfilment-desk';
import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import { RichFittedCard } from '../shared/rich-fitted-card';
import PackageIcon from '@cardstack/boxel-icons/package';

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
    <template>
      <RichFittedCard>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>Order fulfilment</:subtitle>
        <:fact>{{if
            @model.cardInfo.summary
            @model.cardInfo.summary
            'Board · Inventory · Ship desk · In transit · Returns'
          }}</:fact>
      </RichFittedCard>
    </template>
  };
}

export default OrderFulfilmentApp;
