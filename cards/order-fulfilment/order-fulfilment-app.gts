import { OrderFulfilmentDesk } from './order-fulfilment-desk';
import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import { FittedCard } from '@cardstack/boxel-ui/components';
import PackageIcon from '@cardstack/boxel-icons/package';

// Order Fulfilment — the app. It composes the blocks and owns nothing that a
// block should own: no hand-rolled board, no second status vocabulary, no
// bespoke tracking timeline. What it does own is the canvas, the five sections,
// and the domain decisions the blocks deliberately refused to make.
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
      <FittedCard class='fit' @titleTag='h3'>
        <:placeholder><PackageIcon
            class='glyph'
            role='presentation'
          /></:placeholder>
        <:eyebrow>Fulfilment</:eyebrow>
        <:title>{{@model.operationName}}</:title>
        <:subtitle>{{if
            @model.cardInfo.summary
            @model.cardInfo.summary
            'Board · Inventory · Ship · Transit · Returns'
          }}</:subtitle>
      </FittedCard>
      <style scoped>
        .glyph {
          width: 1.5rem;
          height: 1.5rem;
          color: var(--primary-ink);
        }
      </style>
    </template>
  };
}

export default OrderFulfilmentApp;
