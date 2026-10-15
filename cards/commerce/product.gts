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
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
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
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
          font-size: 0.875rem;
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
          gap: 0.125rem;
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          display: flex;
          gap: 0.5rem;
          font-size: 0.75rem;
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
          gap: 0.5rem;
          width: 100%;
          height: 100%;
          padding: 0.5rem 0.75rem;
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
          gap: 0.125rem;
        }
        .name {
          font-size: 0.875rem;
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sku {
          font-size: 0.75rem;
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
          padding: 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: 0.75rem;
        }
        .icon {
          color: var(--muted-foreground);
        }
        h1 {
          margin: 0;
          font-size: 1.25rem;
          font-weight: 600;
        }
        .type {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
        dl {
          display: grid;
          grid-template-columns: max-content 1fr;
          gap: 0.5rem 1.5rem;
          margin: 0;
          font-size: 0.875rem;
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
