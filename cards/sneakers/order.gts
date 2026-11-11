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
import CurrencyField from '@cardstack/base/currency';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import {
  statusHue,
  statusOption,
} from '@cardstack/catalog/fields/status/status';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import { Listing } from './listing';
import { MarketplaceMember as SneakerCollectionPerson } from './marketplace-member';
import { SellerProfile } from './seller-profile';
import { currencyCode, moneyText } from './money-format';
import {
  OrderStatusField,
  canOrderTransition,
  nextOrderStatuses,
  type OrderStatus,
} from './order-status';
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

// Order — one escrow-protected purchase of one Listing. The status is a
// graph (see order-status.gts), the total is computed from four snapshot
// amounts, and fees are the money charged, never a rate. This realm moves no
// money: status changes here only record what happened.

export { OrderStatusField, canOrderTransition, nextOrderStatuses };
export type { OrderStatus } from './order-status';

export class Order extends CardDef {
  static displayName = 'Order';
  static icon = ReceiptIcon;

  // Human-facing reference — 'SV-2024-1234' in the spec. A StringField and not
  // a computed one: it is issued once and then quoted in emails, support
  // threads and disputes, so it must never change because a field it derived
  // from changed.
  @field reference = contains(StringField);

  @field listing = linksTo(() => Listing, { searchable: true });
  @field buyer = linksTo(() => SneakerCollectionPerson, { searchable: true });
  // Narrowed to SellerProfile, not the plain SneakerCollectionPerson buyer uses one
  // line up — a seller carries a rating, a buyer does not.
  @field seller = linksTo(() => SellerProfile, { searchable: true });

  // --- money, as four snapshots + one computed total ---
  @field price = contains(AmountWithCurrency);
  @field shippingPrice = contains(AmountWithCurrency);
  @field authFee = contains(AmountWithCurrency);
  @field platformFee = contains(AmountWithCurrency);

  @field orderStatus = contains(OrderStatusField);

  // --- lifecycle as event facts, same rule as the rest of this family: store
  // the date the thing happened, derive every boolean from it. ---
  @field placedAt = contains(DateField);
  @field paidAt = contains(DateField);
  @field shippedAt = contains(DateField);
  @field authenticatedAt = contains(DateField);
  @field deliveredAt = contains(DateField);
  @field completedAt = contains(DateField);

  @field trackingNumber = contains(StringField);

  // The processor's own reference. Deliberately a plain string: this realm does
  // not model a card, a token or a balance, and pretending otherwise would
  // invite someone to treat it as authoritative.
  @field paymentReference = contains(StringField);

  // TOTAL IS COMPUTED. Currency comes from `price` — mixing currencies inside
  // one order is not a sum, it is a bug, so the code is taken from the item
  // price and the components are added as bare amounts.
  @field total = contains(AmountWithCurrency, {
    computeVia: function (this: Order) {
      let parts = [
        this.price,
        this.shippingPrice,
        this.authFee,
        this.platformFee,
      ];
      let present = parts.filter((p) => p?.amount != null);
      if (!present.length) {
        return undefined;
      }
      // No total across currencies: a mixed order has no single amount.
      let code = currencyCode(present[0]);
      if (present.some((p) => currencyCode(p) !== code)) {
        return undefined;
      }
      let sum = present.reduce((acc, p) => acc + (p?.amount ?? 0), 0);
      // A real AmountWithCurrency instance: the index's searchable walker
      // reads fields off it, which a plain object literal does not have.
      return new AmountWithCurrency({
        amount: sum,
        currency: new CurrencyField({ code }),
      });
    },
  });

  // Escrow is holding money in every state the graph marks `holds`, minus the
  // two terminals. Derived, so it cannot disagree with the status.
  @field fundsHeld = contains(BooleanField, {
    computeVia: function (this: Order) {
      let s = this.orderStatus;
      return (
        s === 'paid' ||
        s === 'shipped' ||
        s === 'authenticating' ||
        s === 'delivered' ||
        s === 'disputed'
      );
    },
  });

  @field isPaid = contains(BooleanField, {
    computeVia: function (this: Order) {
      return this.paidAt != null;
    },
  });

  // Denormalized for prerendered fitted, which cannot resolve links.
  @field productTitle = contains(StringField, {
    computeVia: function (this: Order) {
      return this.listing?.productTitle ?? this.cardInfo?.name ?? '';
    },
  });

  @field sellerName = contains(StringField, {
    computeVia: function (this: Order) {
      return this.seller?.title ?? '';
    },
  });

  @field buyerName = contains(StringField, {
    computeVia: function (this: Order) {
      return this.buyer?.title ?? '';
    },
  });

  @field conditionCode = contains(StringField, {
    computeVia: function (this: Order) {
      return this.listing?.conditionCode ?? '';
    },
  });

  static isolated = class Isolated extends Component<typeof Order> {
    // Moves the graph permits, minus the refund, which moves money and has
    // no command in this app.
    get moves() {
      let from = this.args.model?.orderStatus;
      if (!from) {
        return [];
      }
      return nextOrderStatuses(from).filter((n) => n.value !== 'refunded');
    }

    move = (to: string) => {
      let m = this.args.model as Order;
      if (!canOrderTransition(m.orderStatus, to)) {
        return;
      }
      m.orderStatus = to;
      let stamp = STAMPS[to as OrderStatus];
      if (stamp && !m[stamp]) {
        m[stamp] = new Date();
      }
    };

    <template>
      <IsoFrame>
        <SnSheet>
          <:mark><SnMark @text='Or' /></:mark>
          <:title>{{orderTitle @model}}</:title>
          <:meta>{{metaLine @model}}</:meta>
          <:actions>
            <DotLabel
              @hue={{statusHue OrderStatusField @model.orderStatus}}
              @label={{statusLabel @model.orderStatus}}
            />
            {{#if @model.fundsHeld}}
              <DotLabel @hue='blue' @label='funds held' />
            {{/if}}
            {{#each this.moves as |n i|}}
              <Button
                @tone={{if i 'neutral' 'primary'}}
                @appearance={{if i 'outlined' 'accent'}}
                @size='s'
                {{on 'click' (fn this.move n.value)}}
              >Mark {{lower n.label}}</Button>
            {{/each}}
          </:actions>
          <:stats>
            <SnStat
              @label='Total'
              @hue='blue'
              @value={{moneyText @model.total}}
              @hint='price + shipping + fees'
            />
            <SnStat
              @label='Status'
              @hue={{statusHue OrderStatusField @model.orderStatus}}
              @value={{statusLabel @model.orderStatus}}
              @hint={{statusMeta @model.orderStatus}}
            />
            <SnStat
              @label='Placed'
              @value={{day @model.placedAt true}}
              @hint={{paidLine @model}}
            />
            <SnStat
              @label='Payout'
              @hue='green'
              @value={{payout @model}}
              @hint='after fees, on release'
            />
          </:stats>
          <:main>
            <SnSection @title='Timeline' @flush={{true}}><SnKv>
                {{#each (timeline @model) as |s|}}
                  <SnRow
                    @label={{s.label}}
                    @value={{s.value}}
                    @hue={{s.hue}}
                    @state={{s.state}}
                  />
                {{/each}}
              </SnKv></SnSection>
            <SnSection @title='Price breakdown' @flush={{true}}><SnKv>
                <SnRow @label='Price' @value={{moneyText @model.price}} />
                <SnRow
                  @label='Shipping'
                  @value={{moneyText @model.shippingPrice}}
                />
                <SnRow
                  @label='Authentication fee'
                  @value={{moneyText @model.authFee}}
                />
                <SnRow
                  @label='Platform fee'
                  @value={{moneyText @model.platformFee}}
                />
                <SnRow @label='Total'><strong>{{moneyText
                      @model.total
                    }}</strong></SnRow>
              </SnKv></SnSection>
          </:main>
          <:side>
            <SnSection @title='Linked' @flush={{true}}><SnKv>
                <SnRow @label='Buyer'>{{#if @model.buyer}}<@fields.buyer
                      @format='atom'
                    />{{else}}—{{/if}}</SnRow>
                <SnRow @label='Seller'>{{#if @model.seller}}<@fields.seller
                      @format='atom'
                    />{{else}}—{{/if}}</SnRow>
                <SnRow @label='Listing'>{{#if @model.listing}}<@fields.listing
                      @format='atom'
                    />{{else}}—{{/if}}</SnRow>
              </SnKv></SnSection>
            <SnSection @title='Details' @flush={{true}}><SnKv>
                <SnRow @label='Total' @value={{moneyText @model.total}} />
                <SnRow @label='Price' @value={{moneyText @model.price}} />
                <SnRow
                  @label='Shipping'
                  @value={{moneyText @model.shippingPrice}}
                />
                <SnRow @label='Auth fee' @value={{moneyText @model.authFee}} />
                <SnRow
                  @label='Platform fee'
                  @value={{moneyText @model.platformFee}}
                />
                <SnRow @label='Placed' @value={{day @model.placedAt}} />
                <SnRow @label='Shipped' @value={{day @model.shippedAt}} />
                <SnRow @label='Tracking' @value={{@model.trackingNumber}} />
                <SnRow
                  @label='Payment ref'
                  @value={{@model.paymentReference}}
                />
              </SnKv></SnSection>
          </:side>
        </SnSheet>
      </IsoFrame>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Order> {
    <template>
      <SnEmbedded>
        <:mark><SnMark @text='Or' /></:mark>
        <:title>{{orderTitle @model}}</:title>
        <:meta>{{metaLine @model}}</:meta>
        <:status><DotLabel
            @hue={{statusHue OrderStatusField @model.orderStatus}}
            @label={{statusLabel @model.orderStatus}}
          /></:status>
        <:default>
          <SnKv>
            <SnRow @label='Total' @value={{moneyText @model.total}} />
            <SnRow @label='Price' @value={{moneyText @model.price}} />
            <SnRow
              @label='Shipping'
              @value={{moneyText @model.shippingPrice}}
            />
            <SnRow @label='Auth fee' @value={{moneyText @model.authFee}} />
            <SnRow
              @label='Platform fee'
              @value={{moneyText @model.platformFee}}
            />
            <SnRow @label='Placed' @value={{day @model.placedAt}} />
            <SnRow @label='Shipped' @value={{day @model.shippedAt}} />
            <SnRow @label='Tracking' @value={{@model.trackingNumber}} />
            <SnRow @label='Buyer'>{{#if @model.buyer}}<@fields.buyer
                  @format='atom'
                />{{else}}—{{/if}}</SnRow>
            <SnRow @label='Seller'>{{#if @model.seller}}<@fields.seller
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

  static fitted = class Fitted extends Component<typeof Order> {
    <template>
      <FitTile>
        <:avatar><SnMark @text='Or' @size='lg' /></:avatar>
        <:title>{{orderTitle @model}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><DotLabel
            @hue={{statusHue OrderStatusField @model.orderStatus}}
            @label={{statusLabel @model.orderStatus}}
          /></:status>
        <:fact>{{moneyText @model.total}}
          · payout
          {{payout @model}}
          · placed
          {{day @model.placedAt true}}</:fact>
        <:relations>{{#if @model.buyer}}<@fields.buyer
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}{{#if @model.seller}}<@fields.seller
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
    </template>
  };

  static atom = class Atom extends Component<typeof Order> {
    <template>
      <SnAtom>
        <:mark><SnMark @text='Or' @size='sm' /></:mark>
        <:default>{{orderTitle @model}}</:default>
      </SnAtom>
    </template>
  };
}

type DateKey =
  | 'paidAt'
  | 'shippedAt'
  | 'authenticatedAt'
  | 'deliveredAt'
  | 'completedAt';

// The event date a move records, set only when not already known.
const STAMPS: Partial<Record<OrderStatus, DateKey>> = {
  paid: 'paidAt',
  shipped: 'shippedAt',
  delivered: 'deliveredAt',
  completed: 'completedAt',
};

const STATUS_META: Record<OrderStatus, string> = {
  'pending-payment': 'awaiting payment',
  paid: 'funds in escrow',
  shipped: 'to the auth centre',
  authenticating: 'at the auth centre',
  delivered: 'with the buyer',
  completed: 'funds released',
  disputed: 'funds held',
  refunded: 'returned to the buyer',
};

// The timeline step each status is working on.
const IN_PROGRESS: Partial<Record<OrderStatus, string>> = {
  'pending-payment': 'paid',
  paid: 'shipped',
  shipped: 'authenticated',
  authenticating: 'authenticated',
  delivered: 'completed',
};

function statusLabel(v?: string | null) {
  return statusOption(OrderStatusField, v)?.label ?? '—';
}

function statusMeta(v?: string | null) {
  return STATUS_META[v as OrderStatus] ?? '';
}

function lower(s: string) {
  return s.toLowerCase();
}

function orderTitle(m: Partial<Order>) {
  return m.reference || m.cardTitle || 'Untitled order';
}

function metaLine(m: Partial<Order>) {
  return [m.productTitle, m.conditionCode].filter(Boolean).join(' · ') || '—';
}

function paidLine(m: Partial<Order>) {
  if (!m.paidAt) {
    return 'not paid';
  }
  return day(m.paidAt) === day(m.placedAt)
    ? 'paid same day'
    : `paid ${day(m.paidAt, true)}`;
}

// What the seller receives on release: the item price less the platform fee.
function payout(m: Partial<Order>) {
  let p = m.price?.amount;
  if (p == null) {
    return '—';
  }
  return moneyText({
    amount: p - (m.platformFee?.amount ?? 0),
    currency: m.price?.currency,
  });
}

function timeline(m: Partial<Order>) {
  let current = IN_PROGRESS[m.orderStatus as OrderStatus];
  let step = (
    key: string,
    label: string,
    date: Date | undefined | null,
    extra?: string | null,
    waiting = '—',
  ) => {
    if (date) {
      return {
        label,
        value: [day(date), extra].filter(Boolean).join(' · '),
        hue: 'green' as const,
        state: 'done',
      };
    }
    let active = key === current;
    return {
      label,
      value: active ? waiting : '—',
      hue: active ? ('amber' as const) : undefined,
      state: active ? 'in progress' : 'next',
    };
  };
  return [
    step('placed', 'Placed', m.placedAt),
    step('paid', 'Paid', m.paidAt, m.paymentReference, 'awaiting payment'),
    step(
      'shipped',
      'Shipped to authenticator',
      m.shippedAt,
      m.trackingNumber,
      'awaiting shipment',
    ),
    step(
      'authenticated',
      'Authenticated',
      m.authenticatedAt,
      undefined,
      'awaiting verdict',
    ),
    step('delivered', 'Delivered', m.deliveredAt),
    step('completed', 'Completed', m.completedAt, undefined, 'awaiting buyer'),
  ];
}

export default Order;
