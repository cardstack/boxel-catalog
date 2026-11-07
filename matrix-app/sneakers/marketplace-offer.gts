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
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import {
  statusField,
  canTransition,
  nextStatuses,
  statusHue,
  statusOption,
} from '@cardstack/catalog/fields/status/status';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/pretui/components/button';
import HandshakeIcon from '@cardstack/boxel-icons/handshake';
import { Listing } from './listing';
import { MarketplaceMember } from './marketplace-member';
import {
  currencyCode,
  formatMoney,
  formatMoneyDelta,
  moneyText,
} from './money-format';
import { DotLabel } from '../hr/dot-enum-field';
import { FitTile } from '../shared/fit-tile';
import {
  CbAtom,
  CbEmbedded,
  CbKv,
  CbMark,
  CbRow,
  CbSection,
  CbSheet,
  CbStat,
  day,
} from './cb-parts';

// Offer — a price proposed on a listing. A counter is a new Offer linked back
// through `counterTo`, so what each party offered stays on record.

export type OfferStatus =
  | 'open'
  | 'countered'
  | 'accepted'
  | 'declined'
  | 'withdrawn'
  | 'expired';

export const OfferStatusField = statusField({
  displayName: 'Offer Status',
  icon: HandshakeIcon,
  options: [
    {
      value: 'open',
      label: 'Open',
      hue: 'blue',
      meaning: 'Awaiting the other side. The only state that needs an answer.',
    },
    {
      value: 'countered',
      label: 'Countered',
      hue: 'purple',
      terminal: true,
      holds: true,
      meaning:
        'Answered with a different price. This offer is closed; the counter is its own card.',
    },
    {
      value: 'accepted',
      label: 'Accepted',
      hue: 'green',
      terminal: true,
      holds: true,
      meaning: 'Agreed. An Order should now exist at this amount.',
    },
    {
      value: 'declined',
      label: 'Declined',
      hue: 'red',
      terminal: true,
      holds: true,
      meaning: 'Refused outright, with no counter.',
    },
    {
      value: 'withdrawn',
      label: 'Withdrawn',
      hue: 'slate',
      terminal: true,
      holds: true,
      meaning: 'Pulled by the party who made it, before an answer.',
    },
    {
      value: 'expired',
      label: 'Expired',
      hue: 'amber',
      terminal: true,
      holds: true,
      meaning: 'Ran past its own expiry without an answer.',
    },
  ],
  // `open` is the only live state: a counter, an acceptance or a refusal
  // closes this card, and re-offering is a new offer.
  transitions: {
    open: ['countered', 'accepted', 'declined', 'withdrawn', 'expired'],
    countered: [],
    accepted: [],
    declined: [],
    withdrawn: [],
    expired: [],
  },
});

export function canOfferTransition(from?: string | null, to?: string | null) {
  return canTransition(OfferStatusField, from, to);
}

export function nextOfferStatuses(from?: string | null) {
  return nextStatuses(OfferStatusField, from);
}

export class MarketplaceOffer extends CardDef {
  static displayName = 'Marketplace Offer';
  static icon = HandshakeIcon;

  @field listing = linksTo(() => Listing, { searchable: true });

  // Who made THIS offer. On a counter this is the seller, which is why the
  // field is `offeredBy` rather than `buyer` — the roles swap down the chain.
  @field offeredBy = linksTo(() => MarketplaceMember, { searchable: true });

  @field amount = contains(AmountWithCurrency);
  @field offerStatus = contains(OfferStatusField);

  // The negotiation spine. Null = an opening offer.
  @field counterTo = linksTo(() => MarketplaceOffer, { searchable: true });

  @field message = contains(StringField);

  @field offeredAt = contains(DateField);
  @field respondedAt = contains(DateField);
  @field expiresAt = contains(DateField);

  @field isOpen = contains(BooleanField, {
    computeVia: function (this: MarketplaceOffer) {
      return this.offerStatus === 'open';
    },
  });

  // A counter is identifiable without loading the chain — cheap, and a tile
  // needs it.
  @field isCounter = contains(BooleanField, {
    computeVia: function (this: MarketplaceOffer) {
      return this.counterTo != null;
    },
  });

  // --- denormalized for prerendered fitted (cannot resolve linksTo) ---
  @field productTitle = contains(StringField, {
    computeVia: function (this: MarketplaceOffer) {
      return this.listing?.productTitle ?? this.cardInfo?.name ?? '';
    },
  });

  @field offeredByName = contains(StringField, {
    computeVia: function (this: MarketplaceOffer) {
      return this.offeredBy?.title ?? '';
    },
  });

  // Asking price at index time; the comparison is computed at render time so
  // a re-price never leaves a stale gap.
  @field listingPrice = contains(AmountWithCurrency, {
    computeVia: function (this: MarketplaceOffer) {
      return this.listing?.price;
    },
  });

  static isolated = class Isolated extends Component<typeof MarketplaceOffer> {
    // Answering patches this offer only; a counter is a new card, so it has
    // no button here.
    respond = (to: 'accepted' | 'declined') => {
      let m = this.args.model as MarketplaceOffer;
      if (!canOfferTransition(m.offerStatus, to)) {
        return;
      }
      m.offerStatus = to;
      m.respondedAt = new Date();
    };
    accept = () => this.respond('accepted');
    decline = () => this.respond('declined');

    <template>
      <CbSheet>
        <:mark><CbMark @text='Of' /></:mark>
        <:title>{{offerTitle @model}}</:title>
        <:meta>{{metaLine @model}}</:meta>
        <:actions>
          <DotLabel
            @hue={{statusHue OfferStatusField @model.offerStatus}}
            @label={{statusLabel @model.offerStatus}}
          />
          {{#if @model.expiresAt}}
            <DotLabel @label={{expiresLine @model}} />
          {{/if}}
          {{#if @model.isOpen}}
            <Button
              @variant='primary'
              @size='sm'
              {{on 'click' this.accept}}
            >Accept</Button>
            <Button
              @variant='outline'
              @size='sm'
              {{on 'click' this.decline}}
            >Decline</Button>
          {{/if}}
        </:actions>
        <:stats>
          <CbStat
            @label='Offer'
            @hue='blue'
            @value={{moneyText @model.amount}}
            @meta={{ofAsking @model}}
          />
          <CbStat
            @label='Asking'
            @value={{moneyText @model.listingPrice}}
            @meta={{shippingLine @model}}
          />
          <CbStat
            @label='Expires'
            @hue='amber'
            @value={{day @model.expiresAt true}}
            @meta={{windowLine @model}}
          />
        </:stats>
        <:main>
          <CbSection @title='Message' @text={{@model.message}} />
          <CbSection @title='Offer'>
            <CbRow @label='Amount' @value={{moneyText @model.amount}} />
            <CbRow
              @label='Listing price'
              @value={{moneyText @model.listingPrice}}
            />
            <CbRow @label='Offered' @value={{day @model.offeredAt}} />
            <CbRow @label='Expires' @value={{day @model.expiresAt}} />
            <CbRow @label='Responded' @value={{day @model.respondedAt}} />
            <CbRow @label='Counter to'>{{#if
                @model.counterTo
              }}<@fields.counterTo @format='atom' />{{else}}—{{/if}}</CbRow>
          </CbSection>
        </:main>
        <:side>
          <CbSection @title='Linked'>
            <CbRow @label='From'>{{#if @model.offeredBy}}<@fields.offeredBy
                  @format='atom'
                />{{else}}—{{/if}}</CbRow>
            <CbRow @label='Listing'>{{#if @model.listing}}<@fields.listing
                  @format='atom'
                />{{else}}—{{/if}}</CbRow>
          </CbSection>
          <CbSection @title='Details'>
            <CbRow @label='Offer' @value={{moneyText @model.amount}} />
            <CbRow @label='Asking' @value={{moneyText @model.listingPrice}} />
            <CbRow @label='Gap' @value={{gap @model}} />
            <CbRow @label='Offered' @value={{day @model.offeredAt}} />
            <CbRow @label='Expires' @value={{day @model.expiresAt}} />
            <CbRow @label='Responded' @value={{responded @model}} />
          </CbSection>
        </:side>
      </CbSheet>
    </template>
  };

  static embedded = class Embedded extends Component<typeof MarketplaceOffer> {
    <template>
      <CbEmbedded>
        <:mark><CbMark @text='Of' /></:mark>
        <:title>{{offerTitle @model}}</:title>
        <:meta>{{metaLine @model}}</:meta>
        <:status><DotLabel
            @hue={{statusHue OfferStatusField @model.offerStatus}}
            @label={{statusLabel @model.offerStatus}}
          /></:status>
        <:default>
          <CbKv>
            <CbRow @label='Offer' @value={{moneyText @model.amount}} />
            <CbRow @label='Asking' @value={{moneyText @model.listingPrice}} />
            <CbRow @label='Gap' @value={{gap @model}} />
            <CbRow @label='Offered' @value={{day @model.offeredAt}} />
            <CbRow @label='Expires' @value={{day @model.expiresAt}} />
            <CbRow @label='Responded' @value={{responded @model}} />
            <CbRow @label='From'>{{#if @model.offeredBy}}<@fields.offeredBy
                  @format='atom'
                />{{else}}—{{/if}}</CbRow>
            <CbRow @label='Listing'>{{#if @model.listing}}<@fields.listing
                  @format='atom'
                />{{else}}—{{/if}}</CbRow>
          </CbKv>
        </:default>
      </CbEmbedded>
    </template>
  };

  static fitted = class Fitted extends Component<typeof MarketplaceOffer> {
    <template>
      <FitTile>
        <:avatar><CbMark @text='Of' @size='lg' /></:avatar>
        <:title>{{offerTitle @model}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><DotLabel
            @hue={{statusHue OfferStatusField @model.offerStatus}}
            @label={{statusLabel @model.offerStatus}}
          /></:status>
        <:fact>{{moneyText @model.amount}}
          · asking
          {{moneyText @model.listingPrice}}
          ·
          {{expiresLine @model}}</:fact>
        <:relations>{{#if @model.offeredBy}}<@fields.offeredBy
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
    </template>
  };

  static atom = class Atom extends Component<typeof MarketplaceOffer> {
    <template>
      <CbAtom>
        <:mark><CbMark @text='Of' @size='sm' /></:mark>
        <:default>{{offerTitle @model}}</:default>
      </CbAtom>
    </template>
  };
}

function statusLabel(v?: string | null) {
  return statusOption(OfferStatusField, v)?.label ?? '—';
}

function offerTitle(m: Partial<MarketplaceOffer>) {
  let amt = formatMoney(m.amount);
  let what = m.productTitle || 'listing';
  return amt ? `Offer ${amt} — ${what}` : `Offer — ${what}`;
}

// "84% of asking", or nothing when the two are not comparable.
function ofAsking(m: Partial<MarketplaceOffer>) {
  let a = m.amount?.amount;
  let b = m.listingPrice?.amount;
  if (
    a == null ||
    !b ||
    currencyCode(m.amount) !== currencyCode(m.listingPrice)
  ) {
    return '';
  }
  return `${Math.round((a / b) * 100)}% of asking`;
}

function metaLine(m: Partial<MarketplaceOffer>) {
  return (
    [m.offeredByName, ofAsking(m), m.isCounter ? 'counter' : undefined]
      .filter(Boolean)
      .join(' · ') || '—'
  );
}

function gap(m: Partial<MarketplaceOffer>) {
  return formatMoneyDelta(m.amount, m.listingPrice)?.text ?? '—';
}

function shippingLine(m: Partial<MarketplaceOffer>) {
  let s = m.listing?.shippingPrice;
  return s?.amount != null ? `+ ${moneyText(s)} shipping` : '';
}

function expiresLine(m: Partial<MarketplaceOffer>) {
  return m.expiresAt ? `expires ${day(m.expiresAt, true)}` : 'no expiry';
}

function windowLine(m: Partial<MarketplaceOffer>) {
  if (!m.expiresAt || !m.offeredAt) {
    return '';
  }
  let days = Math.round(
    (m.expiresAt.getTime() - m.offeredAt.getTime()) / 86400000,
  );
  return `${days} days from offer`;
}

function responded(m: Partial<MarketplaceOffer>) {
  return m.respondedAt ? day(m.respondedAt) : 'not yet';
}

export default MarketplaceOffer;
