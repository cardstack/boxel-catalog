import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import AddressField from 'https://cardstack.com/base/address';
import EmailField from 'https://cardstack.com/base/email';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import FactoryIcon from '@cardstack/boxel-icons/building-factory';
import { CompoundAtom } from './fulfilment-ui';
import { money } from './fulfilment-format';
import { FitTile } from '../shared/fit-tile';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
// Cyclic with fulfilment-product.gts (it links to this vendor); the binding is
// only read inside the constructor, never at module evaluation.
import { FulfilmentProduct } from './fulfilment-product';

// Vendor (Ve) — a supplier. Two jobs, and it matters that they are separate:
// restocking your own shelves (lead time, minimum order), and dropshipping
// straight to your customer (supported or not, and what the fee is).
//
// A vendor that does not support dropship still restocks; a vendor that only
// dropships has no lead time worth recording. Both are valid cards.
export class FulfilmentVendor extends CardDef {
  static displayName = 'Vendor';
  static icon = FactoryIcon;

  @field code = contains(StringField);
  @field vendorName = contains(StringField);
  @field contactEmail = contains(EmailField);
  @field contactPhone = contains(StringField);
  @field address = contains(AddressField);

  @field leadTimeDays = contains(NumberField);
  @field minimumOrder = contains(AmountWithCurrency);

  @field supportsDropship = contains(BooleanField);
  @field dropshipFee = contains(AmountWithCurrency);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: FulfilmentVendor) {
      return this.vendorName?.length ? this.vendorName : 'Untitled Vendor';
    },
  });

  get leadTimeLabel() {
    let d = this.leadTimeDays;
    if (d == null) {
      return undefined;
    }
    return d === 1 ? '1 day lead' : `${d} day lead`;
  }

  // Vendor Workspace (VW): everything you need before placing a restock or
  // handing a dropship order over, on one surface.
  static isolated = class Isolated extends Component<typeof FulfilmentVendor> {
    // "What do we buy from them" is the question, and the answer lives on the
    // products pointing at this vendor.
    private productQuery: ReturnType<getCards> | undefined;

    constructor(owner: Owner, args: any) {
      super(owner, args);
      this.productQuery = this.args.context?.getCards(
        this,
        () => {
          let ref = identifyCard(FulfilmentProduct);
          let id = this.args.model?.id;
          if (!ref || !id) {
            return undefined;
          }
          return { filter: { on: ref, every: [{ eq: { 'vendor.id': id } }] } };
        },
        () => this.realms,
        { isLive: true },
      );
    }

    // A live query resolving AFTER first paint is why this card asserted "no
    // products" about data it had not received. `getCards` publishes `isLoading`
    // and nothing here read it. Guarded on emptiness too, so a background
    // refresh of an already-populated list does not flash a skeleton.
    get isQueryLoading() {
      let q = this.productQuery as any;
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
    // Rows name real cards; opening them is the next step of the task, and a
    // <button> gets the keyboard path and focus ring for free.
    open = (card: any) => {
      this.args.viewCard?.(card, 'isolated');
    };

    get queryError(): string | undefined {
      let entries = (this.productQuery as any)?.errors as any[] | undefined;
      if (!entries?.length) {
        return undefined;
      }
      return entries[0]?.error?.message ?? 'The query failed.';
    }

    get products(): any[] {
      return (this.productQuery?.instances ?? []).filter(Boolean);
    }

    <template>
      <article class='ven'>
        <header class='ihead'>
          <div class='who'>
            <span class='mark' aria-hidden='true'>{{initials
                @model.vendorName
              }}</span>
            <div class='id'>
              <h1 class='name'>{{@model.cardTitle}}</h1>
              <p class='meta'>{{metaLine @model}}</p>
            </div>
          </div>
          <div class='bar'>
            {{#if @model.leadTimeDays}}
              <span class='st'><span class='dot'></span>{{@model.leadTimeDays}}
                d lead</span>
            {{/if}}
            <span class='st' data-tone={{if @model.supportsDropship 'ok'}}><span
                class='dot'
              ></span>{{if
                @model.supportsDropship
                'dropship'
                'no dropship'
              }}</span>
          </div>
        </header>

        <div class='stats'>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Lead time</span>
            <span class='num'>{{daysText @model.leadTimeDays}}</span>
            <span class='meta'>from order to dock</span>
          </div>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Minimum order</span>
            <span class='num'>{{amountOr @model.minimumOrder 0}}</span>
            <span class='meta'>per purchase order</span>
          </div>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Products</span>
            <span class='num'>{{this.products.length}}</span>
            <span class='meta'>supplied by this vendor</span>
          </div>
        </div>

        <section class='blk'>
          <h2>Terms</h2>
          <dl class='kv'>
            <dt class='cap'>Lead time</dt>
            <dd>{{daysText @model.leadTimeDays}}</dd>
            <dt class='cap'>Minimum order</dt>
            <dd class='mono'>{{amountOr @model.minimumOrder 2}}</dd>
            <dt class='cap'>Supports dropship</dt>
            <dd>{{if @model.supportsDropship 'Yes' 'No'}}</dd>
            {{#if @model.supportsDropship}}
              <dt class='cap'>Dropship fee</dt>
              <dd class='mono'>{{amountOr @model.dropshipFee 2}}</dd>
            {{/if}}
          </dl>
        </section>

        <section class='blk'>
          <h2>Contact</h2>
          <dl class='kv'>
            <dt class='cap'>Email</dt>
            <dd>{{dash @model.contactEmail}}</dd>
            <dt class='cap'>Phone</dt>
            <dd>{{dash @model.contactPhone}}</dd>
            <dt class='cap'>Address</dt>
            <dd>{{addressLine @model}}</dd>
          </dl>
        </section>

        <section class='blk'>
          <h2>Products</h2>
          {{#if this.queryError}}
            <p class='row meta'>Could not read this vendor's products:
              {{this.queryError}}</p>
          {{else if this.isQueryLoading}}
            <p class='row meta'>Loading…</p>
          {{else}}
            <ul class='rows'>
              {{#each this.products as |p|}}
                <li>
                  <button
                    type='button'
                    class='row'
                    {{on 'click' (fn this.open p)}}
                  >
                    <span class='lead'>
                      <span class='strong'>{{p.cardTitle}}</span>
                      <span class='meta'>{{productMeta p}}</span>
                    </span>
                    <span class='mono'>{{amountOr p.price 2}}</span>
                  </button>
                </li>
              {{else}}
                <li class='row meta'>No products from this vendor yet</li>
              {{/each}}
            </ul>
          {{/if}}
        </section>
      </article>

      <style scoped>
        .ven {
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
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
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
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
          color: var(--foreground);
        }
        .id {
          min-width: 0;
        }
        .name {
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
          gap: var(--boxel-sp-5xs);
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
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          min-width: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .stat + .stat {
          border-left: 1px solid var(--border);
        }
        .stat .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .num {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          line-height: 1.1;
          font-variant-numeric: tabular-nums;
        }
        @container (max-width: 30rem) {
          .stats {
            grid-template-columns: minmax(0, 1fr);
          }
          .stat + .stat {
            border-left: 0;
            border-top: 1px solid var(--border);
          }
        }
        .blk h2 {
          margin: 0;
          padding: var(--boxel-sp-sm) var(--boxel-sp-sm) var(--boxel-sp-4xs);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          letter-spacing: normal;
          text-transform: none;
        }
        .row {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          width: 100%;
          min-height: 1.75rem;
          margin: 0;
          padding: 0 var(--boxel-sp-sm);
          border: 0;
          border-top: 1px solid var(--border);
          background: none;
          color: inherit;
          font-family: inherit;
          font-size: inherit;
          font-weight: inherit;
          line-height: inherit;
          text-align: start;
        }
        button.row {
          cursor: pointer;
        }
        @media (hover: hover) {
          button.row:hover {
            background-color: var(--muted);
          }
        }
        button.row:focus-visible {
          outline: 2px solid var(--ring);
          outline-offset: -2px;
        }
        .rows {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .lead {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .lead .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .strong {
          flex: none;
          font-weight: 600;
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
          padding-left: var(--boxel-sp-sm);
        }
        .kv dd {
          padding: 0 var(--boxel-sp-sm);
          min-width: 0;
          overflow-wrap: break-word;
          min-width: 0;
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof FulfilmentVendor> {
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>{{initials
              @model.vendorName
            }}</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
          {{#if @model.leadTimeDays}}
            <span class='st'><span class='dot'></span>{{@model.leadTimeDays}}
              d lead</span>
          {{/if}}
        </header>
        <dl class='kv'>
          <dt>Lead time</dt>
          <dd>{{daysText @model.leadTimeDays}}</dd>
          <dt>Minimum order</dt>
          <dd class='mono'>{{amountOr @model.minimumOrder 2}}</dd>
          <dt>Dropship</dt>
          <dd>{{if @model.supportsDropship 'Yes' 'No'}}</dd>
          <dt>Email</dt>
          <dd>{{dash @model.contactEmail}}</dd>
          <dt>Phone</dt>
          <dd>{{dash @model.contactPhone}}</dd>
          <dt>Address</dt>
          <dd>{{shortAddress @model}}</dd>
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
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .mark {
          flex: none;
          display: inline-grid;
          place-items: center;
          width: 1.375rem;
          height: 1.375rem;
          border-radius: calc(var(--radius) * 0.6);
          background-color: var(--muted);
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
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
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
          gap: var(--boxel-sp-5xs);
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
          padding-left: var(--boxel-sp-sm);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kv dd {
          padding: 0 var(--boxel-sp-sm);
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof FulfilmentVendor> {
    <template>
      <CompoundAtom
        @mark={{initials @model.vendorName}}
        @name={{if @model.vendorName @model.vendorName @model.code}}
      />
    </template>
  };

  static fitted = class Fitted extends Component<typeof FulfilmentVendor> {
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>{{initials
              @model.vendorName
            }}</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span
            class='st'
            data-tone={{if @model.supportsDropship 'ok'}}
          ><span class='dot'></span><span class='st-text'>{{if
                @model.supportsDropship
                'dropship'
                'no dropship'
              }}</span></span></:status>
        <:fact>{{daysText @model.leadTimeDays}}
          lead · min
          {{amountOr @model.minimumOrder 0}}</:fact>
      </FitTile>
      <style scoped>
        .mark {
          display: inline-grid;
          place-items: center;
          width: 2rem;
          height: 2rem;
          margin-right: var(--boxel-sp-xs);
          border-radius: calc(var(--radius) * 0.6);
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 700;
          color: var(--foreground);
        }
        .st {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          min-width: 0;
          max-width: 100%;
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
        .st-text {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

function dash(v: unknown) {
  return v == null || v === '' ? '—' : String(v);
}

function initials(name: string | undefined) {
  let words = (name ?? '').split(/\s+/).filter(Boolean);
  return words
    .slice(0, 2)
    .map((w) => w[0])
    .join('')
    .toUpperCase();
}

function daysText(d: number | undefined) {
  return d == null ? '—' : d === 1 ? '1 day' : `${d} days`;
}

// `digits` 0 for a stat headline (£250), 2 for a ruled value (£250.00).
function amountOr(a: AmountWithCurrency | undefined, digits: number) {
  let amount = a?.amount;
  if (amount == null) return '—';
  let code = (a as any)?.currency?.code ?? 'GBP';
  if (digits) return money(amount, code);
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency: code,
    maximumFractionDigits: 0,
  }).format(amount);
}

function metaLine(m: Partial<FulfilmentVendor>) {
  let a = m.address;
  let place = [a?.city, a?.postalCode].filter(Boolean).join(' ');
  return [m.code, place].filter(Boolean).join(' · ') || '—';
}

function shortAddress(m: Partial<FulfilmentVendor>) {
  let a = m.address;
  return [a?.addressLine1, a?.city].filter(Boolean).join(', ') || '—';
}

function addressLine(m: Partial<FulfilmentVendor>) {
  let a = m.address;
  let country = (a?.country as any)?.name;
  return (
    [
      a?.addressLine1,
      a?.addressLine2,
      [a?.city, a?.postalCode].filter(Boolean).join(' '),
      country,
    ]
      .filter(Boolean)
      .join(', ') || '—'
  );
}

function productMeta(p: any) {
  return [p?.sku, p?.category].filter(Boolean).join(' · ') || '—';
}

export default FulfilmentVendor;
