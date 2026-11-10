import {
  CardDef,
  field,
  contains,
  linksTo,
  StringField,
  Component,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import BooleanField from '@cardstack/base/boolean';
import MarkdownField from '@cardstack/base/markdown';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import {
  statusField,
  statusHue,
  statusOption,
} from '@cardstack/catalog/fields/status/status';
import MultiImageSourceField from '@cardstack/catalog/fields/multi-image-source/multi-image-source';
import TagIcon from '@cardstack/boxel-icons/tag';
import { CollectionItem } from './collection-item';
import { CollectibleProduct } from './collectible-product';
import { SellerProfile } from './seller-profile';
import { moneyText } from './money-format';
import { DotLabel } from '../hr/dot-enum-field';
import { FitTile } from '../shared/fit-tile';
import {
  SnAtom,
  SnEmbedded,
  SnKv,
  SnMark,
  SnRow,
  SnSection,
  SnSheet,
  SnStat,
  day,
} from './parts';

// Listing — one seller offering one owned item for sale. Every value a tile
// shows is an attribute (computed at index time), because prerendered fitted
// cannot resolve links.

export type ListingStatus = 'active' | 'sold' | 'cancelled' | 'expired';

// A status field, not a plain enum: it carries the transition graph, so a
// sold listing cannot be edited back to active.
export const ListingStatusField = statusField({
  displayName: 'Listing Status',
  options: [
    {
      value: 'active',
      label: 'Active',
      hue: 'green',
      meaning: 'Visible to buyers and accepting offers.',
    },
    {
      value: 'sold',
      label: 'Sold',
      hue: 'teal',
      terminal: true,
      holds: true,
      meaning: 'A buyer committed. The item is spoken for.',
    },
    {
      value: 'cancelled',
      label: 'Cancelled',
      hue: 'slate',
      terminal: true,
      holds: true,
      meaning: 'The seller pulled it. Nothing is owed either way.',
    },
    {
      value: 'expired',
      label: 'Expired',
      hue: 'amber',
      terminal: true,
      holds: true,
      meaning: 'Ran past its own expiry date without selling.',
    },
  ],
  // A sale is not reversible by editing a dropdown — unwinding one is a refund,
  // which is a command with money in it, not a status change. So `sold` leads
  // nowhere here. `cancelled` and `expired` may be relisted.
  transitions: {
    active: ['sold', 'cancelled', 'expired'],
    cancelled: ['active'],
    expired: ['active'],
    sold: [],
  },
});

export class Listing extends CardDef {
  static displayName = 'Listing';
  static icon = TagIcon;

  // The specific owned copy being sold.
  @field collectionItem = linksTo(() => CollectionItem, { searchable: true });

  // Denormalized link to the catalogue row, so "all listings for this SKU" is one
  // query rather than a walk through collectionItem.
  @field product = linksTo(() => CollectibleProduct, { searchable: true });

  @field price = contains(AmountWithCurrency);
  @field shippingPrice = contains(AmountWithCurrency);

  @field listingStatus = contains(ListingStatusField);
  @field shipsFrom = contains(StringField);
  @field photos = contains(MultiImageSourceField);
  @field listingNotes = contains(MarkdownField);

  // SellerProfile (a MarketplaceMember with a rating) rather than a bare
  // CardDef: it gives a listing row the seller's name, avatar and rating
  // without this card modelling a person.
  @field seller = linksTo(() => SellerProfile, { searchable: true });

  // Lifecycle as event facts, same rule as CollectionItem: store the date the
  // thing happened, derive any boolean from it.
  @field listedAt = contains(DateField);
  @field soldAt = contains(DateField);
  @field expiresAt = contains(DateField);

  // Denormalized for prerendered fitted; see the header note.
  @field productTitle = contains(StringField, {
    computeVia: function (this: Listing) {
      return (
        this.product?.displayTitle ??
        this.collectionItem?.itemTitle ??
        this.cardInfo?.name ??
        ''
      );
    },
  });

  @field variantLabel = contains(StringField, {
    computeVia: function (this: Listing) {
      return this.collectionItem?.variantLabel ?? '';
    },
  });

  @field conditionCode = contains(StringField, {
    computeVia: function (this: Listing) {
      return this.collectionItem?.condition?.code ?? '';
    },
  });

  // Boolean, matching `CollectionItem.verified`.
  @field verified = contains(BooleanField, {
    computeVia: function (this: Listing) {
      return Boolean(this.collectionItem?.verified);
    },
  });

  static isolated = class Isolated extends Component<typeof Listing> {
    <template>
      <SnSheet>
        <:mark><SnMark @src={{@model.photos.primaryUrl}} @text='Li' /></:mark>
        <:title>{{@model.cardTitle}}</:title>
        <:meta>{{metaLine @model}}</:meta>
        <:actions><DotLabel
            @hue={{statusHue ListingStatusField @model.listingStatus}}
            @label={{statusLabel @model.listingStatus}}
          /></:actions>
        <:stats>
          <SnStat
            @label='Asking'
            @hue='green'
            @value={{moneyText @model.price}}
            @hint={{shippingLine @model}}
          />
          <SnStat
            @label='Last value'
            @value={{moneyText @model.collectionItem.lastKnownValue}}
            @hint={{day @model.collectionItem.valuedOn}}
          />
          <SnStat
            @label='Retail'
            @value={{moneyText @model.product.retailPrice}}
            @hint={{day @model.product.releaseDate}}
          />
        </:stats>
        <:main>
          <SnSection @title='Notes' @text={{@model.listingNotes}} />
          <SnSection @title='Listing' @flush={{true}}><SnKv>
              <SnRow @label='Price' @value={{moneyText @model.price}} />
              <SnRow
                @label='Shipping'
                @value={{moneyText @model.shippingPrice}}
              />
              <SnRow @label='Ships from' @value={{@model.shipsFrom}} />
              <SnRow @label='Listed' @value={{day @model.listedAt}} />
              <SnRow @label='Sold' @value={{day @model.soldAt}} />
              <SnRow @label='Expires' @value={{day @model.expiresAt}} />
            </SnKv></SnSection>
        </:main>
        <:side>
          <SnSection @title='Linked' @flush={{true}}><SnKv>
              <SnRow @label='Seller'>{{#if @model.seller}}<@fields.seller
                    @format='atom'
                  />{{else}}—{{/if}}</SnRow>
              <SnRow @label='Item'>{{#if
                  @model.collectionItem
                }}<@fields.collectionItem
                    @format='atom'
                  />{{else}}—{{/if}}</SnRow>
              <SnRow @label='Product'>{{#if @model.product}}<@fields.product
                    @format='atom'
                  />{{else}}—{{/if}}</SnRow>
            </SnKv></SnSection>
          <SnSection @title='Details' @flush={{true}}><SnKv>
              <SnRow @label='Price' @value={{moneyText @model.price}} />
              <SnRow
                @label='Shipping'
                @value={{moneyText @model.shippingPrice}}
              />
              <SnRow @label='Size' @value={{@model.variantLabel}} />
              <SnRow @label='Condition' @value={{@model.conditionCode}} />
              <SnRow @label='Ships from' @value={{@model.shipsFrom}} />
              <SnRow @label='Listed' @value={{day @model.listedAt}} />
              <SnRow @label='Expires' @value={{expiry @model}} />
            </SnKv></SnSection>
        </:side>
      </SnSheet>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Listing> {
    <template>
      <SnEmbedded>
        <:mark><SnMark @src={{@model.photos.primaryUrl}} @text='Li' /></:mark>
        <:title>{{@model.cardTitle}}</:title>
        <:meta>{{metaLine @model}}</:meta>
        <:status><DotLabel
            @hue={{statusHue ListingStatusField @model.listingStatus}}
            @label={{statusLabel @model.listingStatus}}
          /></:status>
        <:default>
          <SnKv>
            <SnRow @label='Price' @value={{moneyText @model.price}} />
            <SnRow
              @label='Shipping'
              @value={{moneyText @model.shippingPrice}}
            />
            <SnRow @label='Size' @value={{@model.variantLabel}} />
            <SnRow @label='Condition' @value={{@model.conditionCode}} />
            <SnRow @label='Ships from' @value={{@model.shipsFrom}} />
            <SnRow @label='Listed' @value={{day @model.listedAt}} />
            <SnRow @label='Expires' @value={{expiry @model}} />
            <SnRow @label='Seller'>{{#if @model.seller}}<@fields.seller
                  @format='atom'
                />{{else}}—{{/if}}</SnRow>
            <SnRow @label='Item'>{{#if
                @model.collectionItem
              }}<@fields.collectionItem
                  @format='atom'
                />{{else}}—{{/if}}</SnRow>
          </SnKv>
        </:default>
      </SnEmbedded>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Listing> {
    <template>
      <FitTile>
        <:avatar><SnMark
            @src={{@model.photos.primaryUrl}}
            @text='Li'
            @size='lg'
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><DotLabel
            @hue={{statusHue ListingStatusField @model.listingStatus}}
            @label={{statusLabel @model.listingStatus}}
          /></:status>
        <:fact>{{moneyText @model.price}} · {{shippingLine @model}}</:fact>
        <:relations>{{#if @model.seller}}<@fields.seller
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
    </template>
  };

  static atom = class Atom extends Component<typeof Listing> {
    <template>
      <SnAtom>
        <:mark><SnMark
            @src={{@model.photos.primaryUrl}}
            @text='Li'
            @size='sm'
          /></:mark>
        <:default>{{@model.cardTitle}}</:default>
      </SnAtom>
    </template>
  };
}

function statusLabel(v?: string | null) {
  return statusOption(ListingStatusField, v)?.label ?? '—';
}

function metaLine(m: Partial<Listing>) {
  return (
    [m.productTitle, m.conditionCode, m.verified ? 'verified' : undefined]
      .filter(Boolean)
      .join(' · ') || '—'
  );
}

function shippingLine(m: Partial<Listing>) {
  return m.shippingPrice?.amount != null
    ? `+ ${moneyText(m.shippingPrice)} shipping`
    : 'shipping not set';
}

function expiry(m: Partial<Listing>) {
  return m.expiresAt ? day(m.expiresAt) : 'no expiry';
}

export default Listing;
