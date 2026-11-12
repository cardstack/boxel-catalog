import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  type BaseDefComponent,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import PackageIcon from '@cardstack/boxel-icons/package';
import { IsoHead, IsoMark, IsoPage, Kv, Panel } from '../shared/compact-sheet';
import { RichFittedCard } from '../shared/rich-fitted-card';

// Product — the one thing a business buys, sells or stocks, identified by its
// SKU. Domain cards extend it with what their domain needs (fulfilment adds
// shipping and supply, accounting adds the ledger accounts it posts to), so
// every domain links to the same product.

export const ProductTypeField = markDefinition(
  enumField(StringField, {
    options: ['inventory', 'non-inventory', 'service'],
    displayName: 'Product Type',
  }),
);

export class Product extends CardDef {
  static displayName = 'Product';
  static icon = PackageIcon;

  @field sku = contains(StringField);
  @field productName = contains(StringField);
  @field productType = contains(ProductTypeField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Product) {
      return this.productName?.trim() || this.sku?.trim() || 'Untitled Product';
    },
  });

  static atom: BaseDefComponent = class Atom extends Component<typeof Product> {
    <template>
      <span class='product-atom'>
        <PackageIcon class='icon' width='14' height='14' />
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .product-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .icon {
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof Product
  > {
    <template>
      <div class='product-row'>
        <PackageIcon class='icon' width='20' height='20' />
        <div class='info'>
          <span class='name'>{{@model.cardTitle}}</span>
          <span class='meta'>
            {{#if @model.sku}}<span class='sku'>{{@model.sku}}</span>{{/if}}
            {{#if @model.productType}}<span>{{@model.productType}}</span>{{/if}}
          </span>
        </div>
      </div>
      <style scoped>
        .product-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .icon {
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .info {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          display: flex;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .sku {
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof Product
  > {
    <template>
      <RichFittedCard>
        <:avatar><PackageIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{@model.sku}}</:subtitle>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static isolated: BaseDefComponent = class Isolated extends Component<
    typeof Product
  > {
    get meta() {
      return [this.args.model.sku, this.args.model.productType]
        .filter(Boolean)
        .join(' · ');
    }
    get items() {
      return [
        { key: 'SKU', value: this.args.model.sku },
        { key: 'Type', value: this.args.model.productType },
      ];
    }
    <template>
      <IsoPage>
        <:head>
          <IsoHead @title={{@model.cardTitle}} @meta={{this.meta}}>
            <:mark><IsoMark><PackageIcon
                  width='16'
                  height='16'
                /></IsoMark></:mark>
          </IsoHead>
        </:head>
        <:main>
          <Panel @title='Details'><Kv @items={{this.items}} /></Panel>
        </:main>
      </IsoPage>
    </template>
  };
}
