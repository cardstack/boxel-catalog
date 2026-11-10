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

// Product — the one thing a business buys, sells or stocks, identified by its
// SKU. Domain cards extend it with what their domain needs (fulfilment adds
// shipping and supply, accounting adds the ledger accounts it posts to), so
// every domain links to the same product.

export const ProductTypeField = enumField(StringField, {
  options: ['inventory', 'non-inventory', 'service'],
  displayName: 'Product Type',
});

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
      <div class='fitted'>
        <PackageIcon class='icon' width='20' height='20' />
        <div class='info'>
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.sku}}<span class='sku'>{{@model.sku}}</span>{{/if}}
        </div>
      </div>
      <style scoped>
        .fitted {
          container-type: size;
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          width: 100%;
          height: 100%;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          overflow: hidden;
        }
        .icon {
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .info {
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
        }
        .name {
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sku {
          font-size: var(--boxel-font-size-xs);
          font-family: var(--font-mono);
          color: var(--muted-foreground);
        }
        @container (max-height: 3rem) {
          .sku {
            display: none;
          }
        }
      </style>
    </template>
  };

  static isolated: BaseDefComponent = class Isolated extends Component<
    typeof Product
  > {
    <template>
      <article class='product'>
        <header>
          <PackageIcon class='icon' width='32' height='32' />
          <div>
            <h1>{{@model.cardTitle}}</h1>
            {{#if @model.productType}}
              <span class='type'>{{@model.productType}}</span>
            {{/if}}
          </div>
        </header>
        <dl>
          <dt>SKU</dt>
          <dd class='sku'>{{if @model.sku @model.sku 'Not set'}}</dd>
          <dt>Type</dt>
          <dd>{{if @model.productType @model.productType 'Not set'}}</dd>
        </dl>
      </article>
      <style scoped>
        .product {
          padding: var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
        }
        .icon {
          color: var(--muted-foreground);
        }
        .type {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        dl {
          display: grid;
          grid-template-columns: max-content 1fr;
          gap: var(--boxel-sp-xs) var(--boxel-sp-lg);
          margin: 0;
          font-size: var(--boxel-font-size-sm);
        }
        dt {
          color: var(--muted-foreground);
        }
        dd {
          margin: 0;
        }
        .sku {
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };
}
