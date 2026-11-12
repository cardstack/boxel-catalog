import {
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import BooleanField from 'https://cardstack.com/base/boolean';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import PackageIcon from '@cardstack/boxel-icons/package';
// The catalog's image field rather than a bare url string: it accepts either a
// pasted URL or a file uploaded into the realm and resolves both to one
// `resolvedUrl`, so a consumer never has to know which way the photo arrived.
import ImageSourceField from '@cardstack/catalog/fields/image-source/image-source';
import ParcelDimensionsField from './parcel-dimensions';
import { FulfilmentVendor } from './fulfilment-vendor';
// Cyclic with inventory-stock.gts (it links TO this card), which ES modules
// tolerate because the binding is only read inside the constructor, never at
// module-evaluation time.
import { InventoryStock } from './inventory-stock';
import { money } from './fulfilment-format';
import { RichFittedCard, Media } from '../shared/rich-fitted-card';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import { Product } from '../commerce/product';
import { realmURL } from 'https://cardstack.com/base/card-api';
import type Owner from '@ember/owner';
import { IsoFrame } from '../shared/compact-sheet';

// A Product as fulfilment sees it: the base Product's SKU and name, plus the
// things you need to *move* an item (weight, box size, barcode, who supplies
// it), not the things you need to sell it.
export class FulfilmentProduct extends Product {
  static displayName = 'Product';
  static icon = PackageIcon;
  @field category = contains(StringField);
  @field barcode = contains(StringField);
  @field image = contains(ImageSourceField);

  // Second consumer for the parcel block: a product's shipping profile is the
  // same shape as a parcel's, so the packing station can pre-fill from it.
  @field shippingProfile = contains(ParcelDimensionsField);

  @field vendor = linksTo(() => FulfilmentVendor);
  @field vendorSku = contains(StringField);
  @field cost = contains(AmountWithCurrency);
  @field price = contains(AmountWithCurrency);

  @field isDropship = contains(BooleanField);
  @field isActive = contains(BooleanField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: FulfilmentProduct) {
      return this.productName?.length ? this.productName : 'Untitled Product';
    },
  });

  get marginPercent() {
    let cost = this.cost?.amount;
    let price = this.price?.amount;
    if (!cost || !price || price <= 0) {
      return undefined;
    }
    // A cost and a price in different currencies have no margin.
    let costCode = this.cost?.currency?.code?.trim().toUpperCase();
    let priceCode = this.price?.currency?.code?.trim().toUpperCase();
    if (costCode && priceCode && costCode !== priceCode) {
      return undefined;
    }
    return Math.round(((price - cost) / price) * 100);
  }

  static isolated = class Isolated extends Component<typeof FulfilmentProduct> {
    // The reason someone opens a product card in a fulfilment app is to find out
    // whether there is any. InventoryStock links TO the product, so the answer
    // is a reverse query rather than a field on this card.
    private stockQuery: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      this.stockQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(InventoryStock);
          let id = this.args.model?.id;
          if (!ref || !id) {
            return undefined;
          }
          return { filter: { on: ref, every: [{ eq: { 'product.id': id } }] } };
        },
        () => this.realms,
        { isLive: true },
      );
    }

    // A live query resolving AFTER first paint is why this card asserted "no
    // stock rows" about data it had not received. `getCards` publishes `isLoading`
    // and nothing here read it. Guarded on emptiness too, so a background
    // refresh of an already-populated list does not flash a skeleton.
    get isQueryLoading() {
      let q = this.stockQuery as any;
      return (
        Boolean(q?.isLoading) && !(q?.instances ?? []).filter(Boolean).length
      );
    }

    private get realms(): string[] | undefined {
      let url = (this.args.model as any)?.[realmURL];
      return url ? [url.href] : undefined;
    }

    // `getCards` returns a SearchResource, whose `errors` the exported duck type
    // omits — so it is reached by cast. Without reading it a failed query is
    // indistinguishable from an empty realm, and the section would assert
    // "there are none" when the truth is "we could not look".
    get queryError(): string | undefined {
      let entries = (this.stockQuery as any)?.errors as any[] | undefined;
      if (!entries?.length) {
        return undefined;
      }
      return entries[0]?.error?.message ?? 'The query failed.';
    }

    get stockRows(): any[] {
      return (this.stockQuery?.instances ?? []).filter(Boolean);
    }

    get totalAvailable() {
      return this.stockRows.reduce((n, r) => n + (r.quantityAvailable ?? 0), 0);
    }

    get stats() {
      return productStats(this.args.model as FulfilmentProduct);
    }
    get pricingRows() {
      return pricingRows(this.args.model as FulfilmentProduct);
    }
    get parcelRows() {
      return parcelRows(this.args.model as FulfilmentProduct);
    }
    get idRows() {
      return idRows(this.args.model as FulfilmentProduct);
    }

    <template>
      <IsoFrame>
        <article class='prod'>
          <header class='ihead'>
            <div class='who'>
              {{#if @model.image.resolvedUrl}}
                <img class='mark' src={{@model.image.resolvedUrl}} alt='' />
              {{else}}
                <span class='mark' aria-hidden='true'>Pr</span>
              {{/if}}
              <div class='id'>
                <h1 class='name'>{{@model.cardTitle}}</h1>
                <p class='meta'>{{metaLine @model}}</p>
              </div>
            </div>
            <div class='bar'>
              <span class='st' data-tone={{if @model.isActive 'ok'}}><span
                  class='dot'
                ></span>{{if @model.isActive 'active' 'inactive'}}</span>
              {{#if @model.isDropship}}
                <span class='st'><span class='dot'></span>dropship</span>
              {{/if}}
              <span class='st'><span class='dot'></span>{{money
                  @model.price.amount
                  @model.price.currency.code
                }}</span>
            </div>
          </header>

          <div class='stats'>
            {{#each this.stats as |s|}}
              <div class='stat'>
                <span class='st cap' data-tone={{s.tone}}><span
                    class='dot'
                  ></span>{{s.label}}</span>
                <span class='num'>{{s.value}}</span>
                <span class='meta'>{{s.meta}}</span>
              </div>
            {{/each}}
          </div>

          <section class='blk'>
            <h2>Pricing</h2>
            <dl class='kv'>
              {{#each this.pricingRows as |r|}}
                <dt class='cap'>{{r.k}}</dt>
                <dd>{{r.v}}</dd>
              {{/each}}
            </dl>
          </section>

          <section class='blk'>
            <h2>Shipping profile</h2>
            <dl class='kv'>
              {{#each this.parcelRows as |r|}}
                <dt class='cap'>{{r.k}}</dt>
                <dd>{{r.v}}</dd>
              {{/each}}
            </dl>
          </section>

          <section class='blk'>
            <h2>Identifiers</h2>
            <dl class='kv'>
              {{#each this.idRows as |r|}}
                <dt class='cap'>{{r.k}}</dt>
                <dd>{{r.v}}</dd>
              {{/each}}
            </dl>
          </section>

          <section class='blk'>
            <h2>Stock</h2>
            {{#if this.queryError}}
              <p class='row' role='alert'><span class='st' data-tone='bad'><span
                    class='dot'
                  ></span>Could not read stock:
                  {{this.queryError}}</span></p>
            {{else if this.isQueryLoading}}
              <p class='row meta'>Loading stock…</p>
            {{else}}
              {{#each this.stockRows as |row|}}
                <div class='row'>
                  <span class='lead'>
                    <span class='strong'>{{if
                        row.warehouseCode
                        row.warehouseCode
                        '—'
                      }}</span>
                    <span class='mono'>{{if
                        row.binLocation
                        row.binLocation
                        '—'
                      }}</span>
                  </span>
                  <span class='st' data-tone={{stockTone row}}><span
                      class='dot'
                    ></span>{{row.quantityAvailable}}
                    available</span>
                </div>
              {{else}}
                <p class='row meta'>No stock rows reference this product yet.</p>
              {{/each}}
            {{/if}}
          </section>

          <section class='blk'>
            <h2>Linked</h2>
            <dl class='kv'>
              <dt class='cap'>Vendor</dt>
              <dd>{{#if @model.vendor}}<@fields.vendor
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</dd>
            </dl>
          </section>
        </article>
      </IsoFrame>
      <style scoped>
        .prod {
          container-type: inline-size;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
        }
        .ihead {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs);
        }
        .who {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          width: 1.375rem;
          height: 1.375rem;
          border-radius: calc(var(--radius) * 0.6);
          background-color: var(--muted);
          object-fit: cover;
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .id {
          min-width: 0;
        }
        .name {
          margin: 0;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          letter-spacing: normal;
          text-transform: none;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .bar {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .st {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-weight: 600;
          --tone: var(--muted-foreground);
        }
        .st[data-tone='bad'] {
          --tone: var(--destructive);
        }
        .st[data-tone='warn'] {
          --tone: var(--warning);
        }
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          flex: none;
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: var(--tone);
        }
        .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          border-top: 1px solid var(--border);
          overflow: hidden;
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          padding: var(--boxel-sp-xs);
          border-right: 1px solid var(--border);
          border-bottom: 1px solid var(--border);
          margin-bottom: -1px;
        }
        .num {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          line-height: 1.15;
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .blk {
          border-top: 1px solid var(--border);
        }
        .blk h2 {
          margin: 0;
          padding: var(--boxel-sp-sm) var(--boxel-sp-xs) var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          min-height: 1.75rem;
          margin: 0;
          padding: 0 var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .lead {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .strong {
          font-weight: 600;
        }
        .mono {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .kv {
          display: grid;
          grid-template-columns: minmax(7rem, 9.5rem) minmax(0, 1fr);
          margin: 0;
        }
        .kv dt,
        .kv dd {
          display: flex;
          align-items: center;
          min-height: 1.75rem;
          margin: 0;
          border-top: 1px solid var(--border);
        }
        .kv dt {
          padding-left: var(--boxel-sp-xs);
        }
        .kv dd {
          padding: 0 var(--boxel-sp-xs);
          min-width: 0;
        }
        @container (width < 480px) {
          .stats {
            grid-template-columns: minmax(0, 1fr);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof FulfilmentProduct> {
    get rows() {
      return embRows(this.args.model as FulfilmentProduct);
    }
    <template>
      <article class='emb'>
        <header>
          {{#if @model.image.resolvedUrl}}
            <img class='mark' src={{@model.image.resolvedUrl}} alt='' />
          {{else}}
            <span class='mark' aria-hidden='true'>Pr</span>
          {{/if}}
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
          <span class='st' data-tone={{if @model.isActive 'ok'}}><span
              class='dot'
            ></span>{{if @model.isActive 'active' 'inactive'}}</span>
        </header>
        <dl class='kv'>
          {{#each this.rows as |r|}}
            <dt>{{r.k}}</dt>
            <dd>{{r.v}}</dd>
          {{/each}}
          <dt>Vendor</dt>
          <dd>{{#if @model.vendor}}<@fields.vendor
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</dd>
        </dl>
      </article>
      <style scoped>
        .emb {
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          color: var(--card-foreground);
          background-color: var(--card);
        }
        header {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs);
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          width: 1.375rem;
          height: 1.375rem;
          border-radius: calc(var(--radius) * 0.6);
          background-color: var(--muted);
          object-fit: cover;
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h3 {
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .st {
          flex: none;
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-weight: 600;
          --tone: var(--muted-foreground);
        }
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: var(--tone);
        }
        .kv {
          display: grid;
          grid-template-columns: 7.5rem minmax(0, 1fr);
          margin: 0;
        }
        .kv dt,
        .kv dd {
          display: flex;
          align-items: center;
          min-height: 1.75rem;
          margin: 0;
          border-top: 1px solid var(--border);
        }
        .kv dt {
          padding-left: var(--boxel-sp-xs);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kv dd {
          padding: 0 var(--boxel-sp-xs);
          min-width: 0;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof FulfilmentProduct> {
    <template>
      <span class='atom'>
        {{#if @model.image.resolvedUrl}}
          <img class='mark' src={{@model.image.resolvedUrl}} alt='' />
        {{else}}
          <span class='mark' aria-hidden='true'>Pr</span>
        {{/if}}
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          min-width: 0;
          max-width: 100%;
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          color: var(--card-foreground);
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          width: 1rem;
          height: 1rem;
          border-radius: calc(var(--radius) * 0.5);
          background-color: var(--muted);
          object-fit: cover;
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof FulfilmentProduct> {
    <template>
      <RichFittedCard>
        <:media><Media @src={{@model.image.resolvedUrl}} @alt=''><PackageIcon
              width='40%'
              height='40%'
            /></Media></:media>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span class='st' data-tone={{if @model.isActive 'ok'}}><span
              class='dot'
            ></span><span class='st-text'>{{if
                @model.isActive
                'active'
                'inactive'
              }}</span></span></:status>
        <:fact>{{money @model.price.amount @model.price.currency.code}}
          ·
          {{marginText @model}}
          margin</:fact>
        <:relations>{{#if @model.vendor}}<@fields.vendor
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </RichFittedCard>
      <style scoped>
        .st {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          min-width: 0;
          max-width: 100%;
          font-weight: 600;
          white-space: nowrap;
          --tone: var(--muted-foreground);
        }
        .st-text {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          width: 0.4375rem;
          height: 0.4375rem;
          flex-shrink: 0;
          border-radius: 50%;
          background-color: var(--tone);
        }
      </style>
    </template>
  };
}

export default FulfilmentProduct;

// ── format helpers (tokens for tone, plain strings for text) ─────────────
function metaLine(m: Partial<FulfilmentProduct>) {
  return [m.sku, m.category].filter(Boolean).join(' · ') || '—';
}

function dash(v: unknown) {
  return v == null || v === '' ? '—' : String(v);
}

function kg(n: number | null | undefined) {
  return n == null ? '—' : `${Math.round(n * 100) / 100} kg`;
}

function marginAmount(m: Partial<FulfilmentProduct>) {
  if (m.marginPercent == null) return '—';
  return money(
    (m.price?.amount ?? 0) - (m.cost?.amount ?? 0),
    m.price?.currency?.code,
  );
}

function marginText(m: Partial<FulfilmentProduct>) {
  return m.marginPercent == null ? '—' : `${m.marginPercent}%`;
}

function stockTone(row: InventoryStock) {
  if (row.isOutOfStock) return 'bad';
  if (row.isLowStock) return 'warn';
  return 'ok';
}

function productStats(m: FulfilmentProduct) {
  let p = m.shippingProfile;
  return [
    {
      label: 'Price',
      tone: '',
      value: money(m.price?.amount, m.price?.currency?.code),
      meta: `cost ${money(m.cost?.amount, m.cost?.currency?.code)}`,
    },
    {
      label: 'Margin',
      tone: m.marginPercent == null ? '' : m.marginPercent > 0 ? 'ok' : 'bad',
      value: marginText(m),
      meta: m.marginPercent == null ? '—' : `${marginAmount(m)} per unit`,
    },
    {
      label: 'Billable',
      tone: '',
      value: kg(p?.billableWeight),
      meta: p?.isVolumetric
        ? `volumetric${p.dimDivisor ? `, ÷ ${p.dimDivisor}` : ''}`
        : 'actual weight',
    },
  ];
}

function pricingRows(m: FulfilmentProduct) {
  return [
    { k: 'Price', v: money(m.price?.amount, m.price?.currency?.code) },
    { k: 'Cost', v: money(m.cost?.amount, m.cost?.currency?.code) },
    {
      k: 'Margin',
      v:
        m.marginPercent == null ? '—' : `${marginAmount(m)} (${marginText(m)})`,
    },
    { k: 'Dropship', v: m.isDropship ? 'Yes' : 'No' },
  ];
}

function parcelRows(m: FulfilmentProduct) {
  let p = m.shippingProfile;
  return [
    { k: 'Dimensions', v: p?.sizeLabel ?? '—' },
    { k: 'Weight', v: kg(p?.weight) },
    { k: 'Volumetric weight', v: kg(p?.volumetricWeight) },
    { k: 'Billable weight', v: kg(p?.billableWeight) },
  ];
}

function idRows(m: FulfilmentProduct) {
  return [
    { k: 'SKU', v: dash(m.sku) },
    { k: 'Barcode', v: dash(m.barcode) },
    { k: 'Vendor SKU', v: dash(m.vendorSku) },
    { k: 'Category', v: dash(m.category) },
  ];
}

function embRows(m: FulfilmentProduct) {
  let p = m.shippingProfile;
  return [
    { k: 'Price', v: money(m.price?.amount, m.price?.currency?.code) },
    { k: 'Cost', v: money(m.cost?.amount, m.cost?.currency?.code) },
    {
      k: 'Margin',
      v:
        m.marginPercent == null ? '—' : `${marginAmount(m)} · ${marginText(m)}`,
    },
    { k: 'Barcode', v: dash(m.barcode) },
    { k: 'Vendor SKU', v: dash(m.vendorSku) },
    { k: 'Parcel', v: p?.sizeLabel ?? '—' },
    { k: 'Weight', v: kg(p?.weight) },
    { k: 'Billable', v: kg(p?.billableWeight) },
  ];
}
