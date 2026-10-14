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
import { Listing } from '../collectibles/listing';
import { MarketplaceMember as SoleVaultPerson } from '../collectibles/marketplace-member';
import { SellerProfile } from '../collectibles/seller-profile';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import { tracked } from '@glimmer/tracking';
import { Field } from '@cardstack/pretui/components/field';
import { Accordion } from '@cardstack/pretui/components/accordion';
import { formatMoney } from '../collectibles/money-format';

// Order — one escrow-protected purchase of one Listing.
//
// This is the core of the marketplace:
// without it there is no checkout, so the marketplace can only be browsed.
//
// THE ESCROW GRAPH IS THE POINT. An order is not a record with a status string
// on it; it is a state machine holding someone's money. `statusField` carries the
// transition graph so the field can answer "may I?" rather than only "what are
// the choices?" — see `order-status.gts` for why each edge exists and,
// more importantly, why the missing edges are missing.
//
// MONEY IS FIVE SEPARATE AMOUNTS, NOT ONE. Item price, shipping, authentication
// fee and platform fee are each their own `AmountWithCurrency`, and the total is
// COMPUTED from them rather than stored. A stored total is the classic
// reconciliation bug: it survives a change to any component and then disagrees
// with the sum of its own parts, and nothing in the UI reveals which is right.
//
// FEES ARE SNAPSHOTS, NOT RATES. `platformFee` holds the money actually charged,
// not "3%". A rate re-derived at read time silently rewrites the history of every
// past order the day the rate changes — the buyer's receipt must not move.
//
// WHAT THIS BLOCK DOES NOT DO: charge anything. A realm cannot hold funds, so
// `Payment` is a RECORD of an external processor's state and the commands that
// move this graph are simulations. That is stated here rather than implied,
// because a card that looks like it takes money and does not is worse than one
// that never pretended.

import {
  OrderStatusField,
  canOrderTransition,
  nextOrderStatuses,
} from './order-status';
import { OrderIsolated } from './order-isolated';

export { OrderStatusField, canOrderTransition, nextOrderStatuses };
export type { OrderStatus } from './order-status';

class OrderEdit extends Component<typeof Order> {
  @tracked moneyOpen = true;
  @tracked timelineOpen = false;
  @tracked fulfilmentOpen = false;

  toggleMoney = () => (this.moneyOpen = !this.moneyOpen);
  toggleTimeline = () => (this.timelineOpen = !this.timelineOpen);
  toggleFulfilment = () => (this.fulfilmentOpen = !this.fulfilmentOpen);

  <template>
    <div class='o-edit'>
      <header class='oe-head'>
        <div class='oe-identity'>
          <Field @label='Reference'>
            <@fields.reference />
            <p class='oe-help'>Issued once, then quoted in emails and disputes —
              changing it breaks every reference to this order.</p>
          </Field>
          <Field @label='Status'>
            <@fields.orderStatus />
            <p class='oe-help'>Moves along a fixed graph. A failed
              authentication must refund, so there is no path from
              authenticating straight to delivered.</p>
          </Field>
        </div>

        <div class='oe-parties'>
          <Field @label='Listing'>
            <@fields.listing />
          </Field>
          <Field @label='Buyer'>
            <@fields.buyer />
          </Field>
          <Field @label='Seller'>
            <@fields.seller />
          </Field>
        </div>
      </header>

      <Accordion class='oe-sections' @displayContainer={{false}} as |A|>
        <A.Item
          @id='money'
          @isOpen={{this.moneyOpen}}
          @onClick={{this.toggleMoney}}
        >
          <:title>Money</:title>
          <:content>
            <div class='oe-body oe-grid-2'>
              <Field @label='Item price'>
                <@fields.price />
              </Field>
              <Field @label='Shipping'>
                <@fields.shippingPrice />
              </Field>
              <Field @label='Authentication fee'>
                <@fields.authFee />
              </Field>
              <Field @label='Platform fee'>
                <@fields.platformFee />
              </Field>
            </div>
            <p class='oe-note'>These are the amounts actually charged, not
              rates. The total is computed from them and is not editable — a
              stored total drifts from the sum of its own parts.</p>
          </:content>
        </A.Item>

        <A.Item
          @id='timeline'
          @isOpen={{this.timelineOpen}}
          @onClick={{this.toggleTimeline}}
        >
          <:title>Timeline</:title>
          <:content>
            <div class='oe-body oe-grid-3'>
              <Field @label='Placed'>
                <@fields.placedAt />
              </Field>
              <Field @label='Paid'>
                <@fields.paidAt />
              </Field>
              <Field @label='Shipped'>
                <@fields.shippedAt />
              </Field>
              <Field @label='Authenticated'>
                <@fields.authenticatedAt />
              </Field>
              <Field @label='Delivered'>
                <@fields.deliveredAt />
              </Field>
              <Field @label='Completed'>
                <@fields.completedAt />
              </Field>
            </div>
            <p class='oe-note'>These dates drive the escrow rail on the detail
              view, and “funds held” is derived from the status — neither is
              stored separately, so a date left blank shows as a step not yet
              reached.</p>
          </:content>
        </A.Item>

        <A.Item
          @id='fulfilment'
          @isOpen={{this.fulfilmentOpen}}
          @onClick={{this.toggleFulfilment}}
        >
          <:title>Fulfilment &amp; payment refs</:title>
          <:content>
            <div class='oe-body oe-grid-2'>
              <Field @label='Tracking number'>
                <@fields.trackingNumber />
                <p class='oe-help'>The summary reference. Per-leg tracking lives
                  on the Shipment cards, which is where an exception is actually
                  resolved.</p>
              </Field>
              <Field @label='Payment reference'>
                <@fields.paymentReference />
                <p class='oe-help'>The processor’s own id. This realm records
                  it; it never charges anything.</p>
              </Field>
            </div>
          </:content>
        </A.Item>
      </Accordion>
    </div>

    <style scoped>
      /* Rule 1: the edit format has NO host-provided container — the same law
         as isolated — so this root declares its own, NAMED, or every
         @container rule below is inert CSS. */
      .o-edit {
        container-type: inline-size;
        container-name: o-edit;
        --_raised: color-mix(in oklch, var(--card) 80%, var(--foreground) 20%);
        --_hairline: color-mix(in oklch, var(--border) 55%, transparent);

        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        height: 100%;
        overflow-y: auto;
        padding: 1.5rem;
        display: flex;
        flex-direction: column;
        gap: 1.5rem;
        box-sizing: border-box;

        scrollbar-color: var(--primary) var(--card);
      }
      .o-edit ::selection {
        background: var(--primary);
        color: var(--primary-foreground);
      }
      .o-edit *:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
      }
      .oe-head {
        display: flex;
        flex-direction: column;
        gap: 0.85rem;
        border-bottom: 1px solid var(--_hairline);
        padding-bottom: 1.25rem;
      }
      /* Content-sized, not 1fr 1fr: a reference code and a status select do
         not want the same width as each other. */
      .oe-identity {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        gap: 0.85rem;
      }
      .oe-parties {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 0.85rem;
      }
      .oe-body {
        padding: 0.6rem 0.35rem;
      }
      .oe-grid-2 {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 0.85rem;
      }
      .oe-grid-3 {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 0.85rem;
      }
      .oe-help,
      .oe-note {
        margin: 0.2rem 0 0;
        font-size: 0.75rem;
        line-height: 1.45;
        color: var(--muted-foreground);
      }
      .oe-note {
        padding: 0 0.35rem;
      }

      @container o-edit (width < 40rem) {
        .oe-identity,
        .oe-parties,
        .oe-grid-2,
        .oe-grid-3 {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

export class Order extends CardDef {
  static displayName = 'Order';
  static icon = ReceiptIcon;

  // Human-facing reference — 'SV-2024-1234' in the spec. A StringField and not
  // a computed one: it is issued once and then quoted in emails, support
  // threads and disputes, so it must never change because a field it derived
  // from changed.
  @field reference = contains(StringField);

  @field listing = linksTo(() => Listing, { searchable: true });
  @field buyer = linksTo(() => SoleVaultPerson, { searchable: true });
  // Narrowed to SellerProfile, not the plain SoleVaultPerson buyer uses one
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
      let sum = 0;
      let seen = false;
      for (let p of parts) {
        if (p?.amount != null) {
          sum += p.amount;
          seen = true;
        }
      }
      if (!seen) {
        return undefined;
      }
      // A REAL AmountWithCurrency instance, not a `{ amount, currency }`
      // literal. The index's searchable walker calls peekAtField on this
      // value, and a plain object throws "the card Object does not have a
      // field 'amount'" — which error-rows not just this Order but every
      // Payment/Shipment whose searchable `order` link walks into it.
      return new AmountWithCurrency({
        amount: sum,
        currency: this.price?.currency,
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

  // --- DENORMALIZED FOR PRERENDERED FITTED ---
  //
  // An Orders tab is a grid, a grid is prerendered fitted, and prerendered
  // fitted CANNOT resolve linksTo. A tile that reads `listing.productTitle`
  // directly renders blank — which is every tile in the tab, since the product
  // name is the tile's headline. These are resolved at INDEX time and stored in
  // the search document, so they are plain attributes by the time fitted runs.
  //
  // Defensive on purpose: every link here is optional and may be unloaded.
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

  // ISOLATED — the order's landing page.
  //
  // DOMAIN QUESTION: "where is my money, and what happens next?" Everyone who
  // opens an order — buyer, seller, support — wants those two things, and
  // neither is a field on this card:
  //
  //   * "where is my money" is the escrow state plus the Payment records that
  //     link TO this order — a reverse query.
  //   * "what happens next" is the shipment legs, also a reverse query, plus
  //     the transition graph's own answer for the current state.
  //
  // A version of this card that rendered its own fields tidily and answered
  // neither would pass every technical check and still be useless — which is
  // exactly the failure the domain-question rule exists to catch.
  //
  // Direction: Instrument, the family's operational register. Signature element:
  // the vault plaque (gold hairline over the headline figure) plus the same
  // lifecycle rail CollectionItem's provenance and AuthenticationRecord's
  // progress use. One mark reused across the family, not a new marquee per card.
  // EDIT — 17 editable fields, so grouping is not optional: a flat list in
  // declaration order would bury the reference behind four money fields and six
  // dates, and nothing would signal which of them someone actually touches.
  //
  // The identity row up top carries what is glanced at (reference, status), the
  // parties sit just below, and the money, timeline and fulfilment fields go
  // into independently collapsible sections. `total`, `fundsHeld`, `isPaid` and
  // the four denormalized strings are computed and deliberately absent.
  //
  // HELPER TEXT EARNS ITS PLACE HERE more than on most cards, because two things
  // about this form are genuinely counter-intuitive and both cost money if
  // guessed wrong: the fee fields are recorded amounts rather than rates, and
  // the status is a graph rather than a free dropdown.
  static edit = OrderEdit;

  static isolated = OrderIsolated;

  // FITTED — hand-rolled, and this is the one card in the family where that
  // fork is right rather than lazy.
  //
  // Order has NO image field, and its anchor is a FIGURE, not a title: the
  // reader scanning an Orders grid is looking for the amount and the state, not
  // the product name. FittedCard's slot model makes the title the loud element,
  // so bending it to put a 2× gold serif number in the footer would fight the
  // component the whole way. The isolated view already established the plaque
  // idiom for exactly this figure, so the tile reuses it.
  //
  // SLOT DISCIPLINE — four distinct facts, four slots, zero repeats:
  //   reference (head) · total (anchor) · productTitle (body) · status (meta)
  // Nothing is printed twice, and no slot is padded with a value already shown.
  static fitted = class Fitted extends Component<typeof Order> {
    get total() {
      return formatMoney(this.args.model?.total);
    }

    <template>
      <div class='fit'>
        <div class='r-head'>
          <ReceiptIcon
            class='glyph'
            width='14'
            height='14'
            aria-hidden='true'
          />
          {{#if @model.reference}}
            <span class='ref'>{{@model.reference}}</span>
          {{/if}}
        </div>

        <div class='r-body'>
          {{! THE ANCHOR — the total, decisively the loudest thing at every one
              of the 16 sizes. Data is all-or-nothing: a money value is never
              ellipsised, so this is nowrap and the whole row is hidden at the
              quanta where it cannot fit. }}
          <p class='total'>{{if this.total this.total '—'}}</p>
          <p class='title'>{{if
              @model.productTitle
              @model.productTitle
              'Unlinked listing'
            }}</p>
        </div>

        <div class='r-meta'>
          {{#if @model.orderStatus}}
            <@fields.orderStatus @format='atom' />
          {{/if}}
        </div>
      </div>

      <style scoped>
        /* NO container-type / container-name anywhere — the HOST wrapper
           declares `container-type: size; container-name: fitted-card`, and
           declaring one here would capture those queries and leave every rule
           below inert. */
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          /* Text rows are auto; only the body flexes. A fixed height on a text
             row under overflow:hidden is what shears type through the middle of
             its letters. */
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'body' 'meta';
          gap: 0.2rem;

          /* ONE type scale for the template, and the cap is on --_type-base
             ITSELF rather than per role. A per-role cqb cap never binds in a
             wide+short cell: cqb is tiny there, so the cap sits far above what
             the cqi term produces and the row shears anyway. Capping the base
             at 10cqb fixes every role at once, and tall cells are unchanged
             because the cqi term still governs there — min() only bites when
             the cell is short.
             Plain multipliers rather than pow(): the requirement is one derived
             scale with no stepped font-size blocks, and multipliers satisfy it
             without depending on CSS pow() support.
             (The skill's formula carries an aspect-ratio correction term; it is
             omitted here because CSS cannot compute an aspect ratio from
             container units, and the cqb cap is what actually prevents the
             shear.) */
          --_type-base: clamp(
            0.625rem,
            min(calc(0.1875rem + 2.1cqi + 1cqb), 10cqb),
            1.0625rem
          );

          background: var(--card);
          color: var(--foreground);
          font-family: var(--font-sans);
          padding: 0.5rem 0.75rem;
          box-sizing: border-box;
          /* The family's miniature vault plaque — inset gold edge, not a border,
             because the host draws the chrome. */
          box-shadow: inset 0.125rem 0 0 0 var(--primary);
          overflow: hidden;
        }

        .r-head {
          grid-area: head;
          min-height: 0;
          overflow: hidden;
          display: flex;
          align-items: center;
          gap: 0.4em;
        }
        /* Rule 2: the glyph identifies, it does not compete — and it is the
           card's OWN static icon, the same one its isolated view uses. */
        .glyph {
          color: var(--primary-ink);
          flex: none;
        }
        /* An order reference is quoted into support threads: mono, tabular, and
           never ellipsised. It is hidden whole at the narrowest quanta. */
        .ref {
          font-family:
            ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
          font-size: max(0.5625rem, calc(var(--_type-base) * 0.8));
          line-height: 1.25;
          font-variant-numeric: tabular-nums;
          letter-spacing: 0.04em;
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
        }

        .r-body {
          grid-area: body;
          min-height: 0;
          overflow: hidden;
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.1em;
        }
        /* THE ANCHOR: 1.75× the base, gold display serif — the same figure
           treatment as the isolated plaque and the money values on the sibling
           tiles. line-height 1.15 so descenders survive at the floor. */
        .total {
          margin: 0;
          font-family: 'Playfair Display', Georgia, serif;
          color: var(--primary-ink);
          font-size: calc(var(--_type-base) * 1.75);
          line-height: 1.15;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          letter-spacing: -0.01em;
          white-space: nowrap;
        }
        /* Quiet by contrast, so the figure wins by more than size alone. */
        .title {
          margin: 0;
          font-size: var(--_type-base);
          line-height: 1.25;
          font-weight: 600;
          color: var(--foreground);
          /* Clamped at a LINE boundary with an ellipsis — never half a letter. */
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 2;
          overflow: hidden;
        }

        .r-meta {
          grid-area: meta;
          min-height: 0;
          overflow: hidden;
          display: flex;
          align-items: center;
        }

        /* ---- quanta: structure and visibility only; the scale never steps ---- */

        /* Badge tier (h <= 50): the figure is the only survivor. For an order
           the amount is the identity — a status pill without a number tells the
           reader nothing they can act on. */
        @container fitted-card (height <= 3.125rem) {
          .fit {
            grid-template-rows: 1fr;
            padding: var(--boxel-sp-4xs) var(--boxel-sp-2xs);
          }
          .r-head,
          .r-meta {
            display: none;
          }
          .title {
            display: none;
          }
        }

        /* Strip tier (50–80): the status comes back, the product name does not —
           two text rows plus the figure would exceed the block budget. */
        @container fitted-card (height > 3.125rem) and (height <= 5rem) {
          .title {
            display: none;
          }
        }

        /* Thin body (80–130): one line of product name rather than two. */
        @container fitted-card (height > 5rem) and (height <= 8.125rem) {
          .title {
            -webkit-line-clamp: 1;
          }
        }

        /* Narrow cells: the reference is dropped WHOLE rather than truncated to
           a meaningless stub, and the glyph goes with it so the row does not sit
           there holding only decoration. */
        @container fitted-card (width <= 9.375rem) {
          .r-head {
            display: none;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Order> {
    get total() {
      return formatMoney(this.args.model?.total);
    }

    <template>
      <span class='o-atom'>
        <span class='o-ref'>{{if @model.reference @model.reference '—'}}</span>
        {{#if this.total}}<span class='o-total'>{{this.total}}</span>{{/if}}
      </span>
      <style scoped>
        .o-atom {
          display: inline-flex;
          align-items: baseline;
          gap: 0.3rem;
          font-family: var(--font-sans);
        }
        /* An order reference is quoted into support threads — mono, never cut. */
        .o-ref {
          font-family:
            ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
          font-weight: 600;
          white-space: nowrap;
        }
        .o-total {
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  // Row-shaped, for an Orders list. Trailing slots use an em-dash when empty so
  // a consumer's list column-aligns.
  static embedded = class Embedded extends Component<typeof Order> {
    get total() {
      return formatMoney(this.args.model?.total);
    }

    <template>
      <div class='o-row'>
        <span class='o-ref'>{{if @model.reference @model.reference '—'}}</span>
        <span class='o-title'>{{if
            @model.productTitle
            @model.productTitle
            'Unlinked listing'
          }}</span>
        <span class='o-status'>
          {{#if @model.orderStatus}}<@fields.orderStatus
              @format='atom'
            />{{else}}—{{/if}}
        </span>
        <span class='o-total'>{{if this.total this.total '—'}}</span>
      </div>
      <style scoped>
        /* Own inset — the host's CardContainer draws a boundary and adds NO
           padding, so without this the text sits flush against the pill. */
        .o-row {
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr) auto auto;
          gap: 0.75rem;
          align-items: center;
          padding: 0.5rem 0.75rem;
          background: var(--card);
          color: var(--foreground);
          font-family: var(--font-sans);
        }
        .o-ref {
          font-family:
            ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
          font-size: 0.75rem;
          font-weight: 600;
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .o-title {
          font-weight: 600;
          font-size: 0.875rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .o-total {
          font-family: 'Playfair Display', Georgia, serif;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          color: var(--primary-ink);
          white-space: nowrap;
        }
        @container (width < 31.25rem) {
          .o-row {
            grid-template-columns: minmax(0, 1fr) auto;
          }
          .o-ref,
          .o-status {
            display: none;
          }
        }
      </style>
    </template>
  };
}

export default Order;
