import {
  Component,
  realmURL,
  getComponent,
  type BaseDefComponent,
} from '@cardstack/base/card-api';
import { tracked } from '@glimmer/tracking';
import type Owner from '@ember/owner';
import UserIcon from '@cardstack/boxel-icons/user';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { identifyCard, type Query } from '@cardstack/runtime-common';
import {
  statusHue,
  statusOption,
} from '@cardstack/catalog/fields/status/status';
import { PersonBase } from '../people/person-base';
import { OrderStatusField } from './order-status';
import { DotLabel } from '../hr/dot-enum-field';
import { RichFittedCard } from '../shared/rich-fitted-card';
import {
  SnAtom,
  SnEmbedded,
  SnKv,
  SnRow,
  SnSection,
  SnSheet,
  SnStat,
  day,
} from './parts';
import { formatMoney } from './money-format';
// Type-only: listing, order and offer all import this module, so the classes
// are loaded with dynamic imports to keep the module graph acyclic.
import type { Listing as ListingType } from './listing';
import type { Order as OrderType } from './order';
import type { MarketplaceOffer as OfferType } from './marketplace-offer';
import { IsoFrame } from '../shared/compact-sheet';

// A seller is a SellerProfile, which adds `rating`; one set of formats serves
// both roles and reads the role from that field.
function isSeller(m: unknown): boolean {
  return Boolean(m) && 'rating' in (m as object);
}

function ratingText(m: unknown): string {
  let r = (m as { rating?: number | null })?.rating;
  return r == null ? '' : `${r} / 5`;
}

function roleLine(m: Partial<MarketplaceMember>) {
  return [isSeller(m) ? 'Seller' : 'Buyer', m.email]
    .filter(Boolean)
    .join(' · ');
}

// The isolated landing page, exported so SellerProfile can extend it.
export class MarketplaceMemberIsolated<
  T extends typeof MarketplaceMember = typeof MarketplaceMember,
> extends Component<T> {
  @tracked private classes:
    | {
        Listing: typeof ListingType;
        Order: typeof OrderType;
        Offer: typeof OfferType;
      }
    | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    Promise.all([
      import('./listing.gts'),
      import('./order.gts'),
      import('./marketplace-offer.gts'),
    ]).then(([l, o, f]) => {
      this.classes = {
        Listing: l.Listing,
        Order: o.Order,
        Offer: f.MarketplaceOffer,
      };
    });
  }

  get realms() {
    let realmUrl = this.args.model?.[realmURL];
    return realmUrl ? [realmUrl.href] : [];
  }

  get seller() {
    return isSeller(this.args.model);
  }

  private query(on: () => unknown, path: () => string) {
    return this.args.context?.getCards(
      this,
      () => {
        let cls = on();
        let ref = cls ? identifyCard(cls as any) : undefined;
        let id = this.args.model?.id;
        if (!ref || !id) {
          return undefined;
        }
        let query: Query = {
          filter: { on: ref, every: [{ eq: { [path()]: id } }] },
        };
        return query;
      },
      () => this.realms,
      { isLive: true },
    );
  }

  private ordersQuery = this.query(
    () => this.classes?.Order,
    () => (this.seller ? 'seller.id' : 'buyer.id'),
  );
  private listingsQuery = this.query(
    () => (this.seller ? this.classes?.Listing : undefined),
    () => 'seller.id',
  );
  private offersQuery = this.query(
    () => this.classes?.Offer,
    () => 'offeredBy.id',
  );

  get orders(): OrderType[] {
    return (this.ordersQuery?.instances ?? []).filter(Boolean) as OrderType[];
  }
  get listings(): ListingType[] {
    return ((this.listingsQuery?.instances ?? []) as ListingType[]).filter(
      (l) => l?.listingStatus === 'active',
    );
  }
  get openOffers(): OfferType[] {
    return ((this.offersQuery?.instances ?? []) as OfferType[]).filter(
      (o) => o?.isOpen,
    );
  }

  get refundedLine() {
    let n = this.orders.filter((o) => o.orderStatus === 'refunded').length;
    return n ? `${n} refunded` : 'none refunded';
  }
  get spent() {
    let kept = this.orders.filter(
      (o) => o.orderStatus !== 'refunded' && o.total?.amount != null,
    );
    if (!kept.length) {
      return '';
    }
    let amount = kept.reduce((s, o) => s + (o.total?.amount ?? 0), 0);
    return formatMoney({ amount, currency: kept[0].total?.currency });
  }
  get offerLine() {
    let o = this.openOffers[0];
    return o ? formatMoney(o.amount) || 'open' : 'none open';
  }

  orderLabel = (o: OrderType) =>
    [o.reference, o.productTitle].filter(Boolean).join(' · ');
  orderValue = (o: OrderType) =>
    [day(o.placedAt), formatMoney(o.total)].filter(Boolean).join(' · ');
  listingLabel = (l: ListingType) => l.cardTitle ?? '';
  listingValue = (l: ListingType) =>
    [l.listedAt ? `Listed ${day(l.listedAt, true)}` : '', formatMoney(l.price)]
      .filter(Boolean)
      .join(' · ');

  <template>
    <IsoFrame>
      <SnSheet>
        <:mark><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @size={{22}}
            aria-hidden='true'
          /></:mark>
        <:title>{{@model.title}}</:title>
        <:meta>{{roleLine @model}}</:meta>
        <:actions>
          <DotLabel @hue='blue' @label={{if this.seller 'seller' 'buyer'}} />
          {{#if this.seller}}
            <DotLabel @label={{ratingText @model}} />
          {{/if}}
        </:actions>
        <:stats>
          {{#if this.seller}}
            <SnStat
              @label='Rating'
              @hue='green'
              @value={{ratingText @model}}
              @hint='buyer score'
            />
            <SnStat
              @label='Listings'
              @hue='blue'
              @value={{this.listings.length}}
              @hint='active'
            />
          {{/if}}
          <SnStat
            @label='Orders'
            @value={{this.orders.length}}
            @hint={{this.refundedLine}}
          />
          {{#unless this.seller}}
            <SnStat
              @label='Spent'
              @hue='green'
              @value={{this.spent}}
              @hint='net of refunds'
            />
            <SnStat
              @label='Open offers'
              @hue='blue'
              @value={{this.openOffers.length}}
              @hint={{this.offerLine}}
            />
          {{/unless}}
        </:stats>
        <:main>
          <SnSection @title='Contact' @flush={{true}}><SnKv>
              <SnRow @label='Email' @value={{@model.email}} />
              <SnRow @label='Phone' @value={{@model.phone}} />
            </SnKv></SnSection>
          {{#if this.seller}}
            <SnSection @title='Active listings' @flush={{true}}><SnKv>
                {{#each this.listings as |l|}}
                  <SnRow
                    @label={{this.listingLabel l}}
                    @value={{this.listingValue l}}
                    @hue='green'
                    @state='active'
                  />
                {{else}}
                  <SnRow @label='Listings' @value='none active' />
                {{/each}}
              </SnKv></SnSection>
          {{else}}
            <SnSection @title='Orders' @flush={{true}}><SnKv>
                {{#each this.orders as |o|}}
                  <SnRow
                    @label={{this.orderLabel o}}
                    @value={{this.orderValue o}}
                    @hue={{orderHue o}}
                    @state={{orderStateLabel o}}
                  />
                {{else}}
                  <SnRow @label='Orders' @value='none yet' />
                {{/each}}
              </SnKv></SnSection>
          {{/if}}
        </:main>
        <:side>
          <SnSection @title='Linked' @flush={{true}}><SnKv>
              {{#if this.seller}}
                {{#each this.listings as |l|}}
                  <SnRow @label='Listing'>{{#let (getComponent l) as |C|}}<C
                        @format='atom'
                      />{{/let}}</SnRow>
                {{else}}
                  <SnRow @label='Listing' />
                {{/each}}
              {{else}}
                {{#each this.orders as |o|}}
                  <SnRow
                    @label='Order'
                    @hue={{orderHue o}}
                    @state={{orderStateLabel o}}
                  >{{#let (getComponent o) as |C|}}<C
                        @format='atom'
                      />{{/let}}</SnRow>
                {{/each}}
                {{#each this.openOffers as |f|}}
                  <SnRow @label='Offer' @hue='blue' @state='open'>{{#let
                      (getComponent f)
                      as |C|
                    }}<C @format='atom' />{{/let}}</SnRow>
                {{/each}}
              {{/if}}
            </SnKv></SnSection>
          <SnSection @title='Details' @flush={{true}}><SnKv>
              {{#if this.seller}}
                <SnRow @label='Rating' @value={{ratingText @model}} />
              {{/if}}
              <SnRow @label='Email' @value={{@model.email}} />
              <SnRow
                @label='Phone'
                @value={{if @model.phone @model.phone 'not given'}}
              />
              {{#if this.seller}}
                <SnRow
                  @label='Active listings'
                  @value={{this.listings.length}}
                />
              {{/if}}
              <SnRow @label='Orders' @value={{this.orders.length}} />
              {{#unless this.seller}}
                <SnRow @label='Open offers' @value={{this.openOffers.length}} />
              {{/unless}}
            </SnKv></SnSection>
        </:side>
      </SnSheet>
    </IsoFrame>
  </template>
}

function orderHue(o: OrderType) {
  return statusHue(OrderStatusField, o.orderStatus);
}
function orderStateLabel(o: OrderType) {
  return statusOption(OrderStatusField, o.orderStatus)?.label ?? '—';
}

// MarketplaceMember — a marketplace person (a buyer, or anyone not
// specifically a seller). SellerProfile extends it with a rating.
export class MarketplaceMember extends PersonBase {
  static displayName = 'Marketplace Member';
  static icon = UserIcon;

  static isolated: BaseDefComponent = MarketplaceMemberIsolated;

  static embedded: BaseDefComponent = class Embedded extends Component<
    typeof MarketplaceMember
  > {
    <template>
      <SnEmbedded>
        <:mark><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @size={{22}}
            aria-hidden='true'
          /></:mark>
        <:title>{{@model.title}}</:title>
        <:meta>{{roleLine @model}}</:meta>
        <:status><DotLabel
            @hue='blue'
            @label={{if (isSeller @model) 'seller' 'buyer'}}
          /></:status>
        <:default>
          <SnKv>
            {{#if (isSeller @model)}}
              <SnRow @label='Rating' @value={{ratingText @model}} />
            {{/if}}
            <SnRow @label='Email' @value={{@model.email}} />
            <SnRow
              @label='Phone'
              @value={{if @model.phone @model.phone 'not given'}}
            />
          </SnKv>
        </:default>
      </SnEmbedded>
    </template>
  };

  static fitted: BaseDefComponent = class Fitted extends Component<
    typeof MarketplaceMember
  > {
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @size={{32}}
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{roleLine @model}}</:subtitle>
        <:status><DotLabel
            @hue='blue'
            @label={{if (isSeller @model) 'seller' 'buyer'}}
          /></:status>
        <:fact>{{if (isSeller @model) (ratingText @model) @model.phone}}</:fact>
      </RichFittedCard>
    </template>
  };

  static atom: BaseDefComponent = class Atom extends Component<
    typeof MarketplaceMember
  > {
    <template>
      <SnAtom>
        <:mark><Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @size={{16}}
            aria-hidden='true'
          /></:mark>
        <:default>{{@model.title}}</:default>
      </SnAtom>
    </template>
  };
}

export default MarketplaceMember;
