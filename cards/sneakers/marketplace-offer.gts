import { markDefinition } from '@cardstack/base/mark-definition';
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
import { AlertDialog } from '@cardstack/pretui/components/alert-dialog';
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
import { IsoFrame } from '../shared/compact-sheet';

// Offer — a price proposed on a listing. A counter is a new Offer linked back
// through `counterTo`, so what each party offered stays on record.

export type OfferStatus =
  | 'open'
  | 'countered'
  | 'accepted'
  | 'declined'
  | 'withdrawn'
  | 'expired';

export const OfferStatusField = markDefinition(
  statusField({
    displayName: 'Offer Status',
    icon: HandshakeIcon,
    options: [
      {
        value: 'open',
        label: 'Open',
        hue: 'blue',
        meaning:
          'Awaiting the other side. The only state that needs an answer.',
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
  }),
);

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
      <IsoFrame>
        <SnSheet>
          <:mark><SnMark @text='Of' /></:mark>
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
              {{! Both answers are final, so each asks first. }}
              <AlertDialog
                @title='Accept this offer?'
                @description='The offer is marked accepted. An accepted offer cannot be changed.'
                @confirmLabel='Accept offer'
                @tone='primary'
                @onConfirm={{this.accept}}
              >
                <:trigger as |_isOpen toggle|>
                  <Button
                    @tone='primary'
                    @appearance='accent'
                    @size='s'
                    {{on 'click' toggle}}
                  >Accept</Button>
                </:trigger>
              </AlertDialog>
              <AlertDialog
                @title='Decline this offer?'
                @description='The offer is marked declined. A declined offer cannot be reopened.'
                @confirmLabel='Decline offer'
                @onConfirm={{this.decline}}
              >
                <:trigger as |_isOpen toggle|>
                  <Button
                    @tone='danger'
                    @appearance='outlined'
                    @size='s'
                    {{on 'click' toggle}}
                  >Decline</Button>
                </:trigger>
              </AlertDialog>
            {{/if}}
          </:actions>
          <:stats>
            <SnStat
              @label='Offer'
              @hue='blue'
              @value={{moneyText @model.amount}}
              @hint={{ofAsking @model}}
            />
            <SnStat
              @label='Asking'
              @value={{moneyText @model.listingPrice}}
              @hint={{shippingLine @model}}
            />
            <SnStat
              @label='Expires'
              @hue='amber'
              @value={{day @model.expiresAt true}}
              @hint={{windowLine @model}}
            />
          </:stats>
          <:main>
            <SnSection @title='Message' @text={{@model.message}} />
            <SnSection @title='Offer' @flush={{true}}><SnKv>
                <SnRow @label='Amount' @value={{moneyText @model.amount}} />
                <SnRow
                  @label='Listing price'
                  @value={{moneyText @model.listingPrice}}
                />
                <SnRow @label='Offered' @value={{day @model.offeredAt}} />
                <SnRow @label='Expires' @value={{day @model.expiresAt}} />
                <SnRow @label='Responded' @value={{day @model.respondedAt}} />
                <SnRow @label='Counter to'>{{#if
                    @model.counterTo
                  }}<@fields.counterTo @format='atom' />{{else}}—{{/if}}</SnRow>
              </SnKv></SnSection>
          </:main>
          <:side>
            <SnSection @title='Linked' @flush={{true}}><SnKv>
                <SnRow @label='From'>{{#if @model.offeredBy}}<@fields.offeredBy
                      @format='atom'
                    />{{else}}—{{/if}}</SnRow>
                <SnRow @label='Listing'>{{#if @model.listing}}<@fields.listing
                      @format='atom'
                    />{{else}}—{{/if}}</SnRow>
              </SnKv></SnSection>
            <SnSection @title='Details' @flush={{true}}><SnKv>
                <SnRow @label='Offer' @value={{moneyText @model.amount}} />
                <SnRow
                  @label='Asking'
                  @value={{moneyText @model.listingPrice}}
                />
                <SnRow @label='Gap' @value={{gap @model}} />
                <SnRow @label='Offered' @value={{day @model.offeredAt}} />
                <SnRow @label='Expires' @value={{day @model.expiresAt}} />
                <SnRow @label='Responded' @value={{responded @model}} />
              </SnKv></SnSection>
          </:side>
        </SnSheet>
      </IsoFrame>
    </template>
  };

  static embedded = class Embedded extends Component<typeof MarketplaceOffer> {
    <template>
      <SnEmbedded>
        <:mark><SnMark @text='Of' /></:mark>
        <:title>{{offerTitle @model}}</:title>
        <:meta>{{metaLine @model}}</:meta>
        <:status><DotLabel
            @hue={{statusHue OfferStatusField @model.offerStatus}}
            @label={{statusLabel @model.offerStatus}}
          /></:status>
        <:default>
          <SnKv>
            <SnRow @label='Offer' @value={{moneyText @model.amount}} />
            <SnRow @label='Asking' @value={{moneyText @model.listingPrice}} />
            <SnRow @label='Gap' @value={{gap @model}} />
            <SnRow @label='Offered' @value={{day @model.offeredAt}} />
            <SnRow @label='Expires' @value={{day @model.expiresAt}} />
            <SnRow @label='Responded' @value={{responded @model}} />
            <SnRow @label='From'>{{#if @model.offeredBy}}<@fields.offeredBy
                  @format='atom'
                />{{else}}—{{/if}}</SnRow>
            <SnRow @label='Listing'>{{#if @model.listing}}<@fields.listing
                  @format='atom'
                />{{else}}—{{/if}}</SnRow>
          </SnKv>
        </:default>
      </SnEmbedded>
    </template>
  };

  static fitted = class Fitted extends Component<typeof MarketplaceOffer> {
    <template>
      <FitTile>
        <:avatar><SnMark @text='Of' @size='lg' /></:avatar>
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
      <SnAtom>
        <:mark><SnMark @text='Of' @size='sm' /></:mark>
        <:default>{{offerTitle @model}}</:default>
      </SnAtom>
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
