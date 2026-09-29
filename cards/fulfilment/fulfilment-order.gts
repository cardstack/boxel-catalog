import {
  CardDef,
  Component,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import DatetimeField from 'https://cardstack.com/base/datetime';
import AddressField from 'https://cardstack.com/base/address';
import EmailField from 'https://cardstack.com/base/email';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import CurrencyField from 'https://cardstack.com/base/currency';
import enumField from 'https://cardstack.com/base/enum';
import MarkdownField from 'https://cardstack.com/base/markdown';
import { htmlSafe } from '@ember/template';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import Clock from '@cardstack/boxel-icons/clock';
import FileText from '@cardstack/boxel-icons/file-text';
import List from '@cardstack/boxel-icons/list';
import MapPin from '@cardstack/boxel-icons/map-pin';
import { FulfilmentLineItemField } from './fulfilment-line-item';
import {
  OrderStatusField,
  ORDER_PIPELINE,
  orderStatusStyle,
  orderProgress,
} from './order-status';
import { Warehouse } from './warehouse';
import StatusChip from './fulfilment-status-chip';
import { money } from './fulfilment-format';
import { Money, lifecycleSteps } from './fulfilment-ui';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { StepList } from '@cardstack/pretui/components/step-list';
import { Token } from '@cardstack/pretui/components/token';
import { eq } from '@cardstack/boxel-ui/helpers';

// Where the order came from. v1 enters orders by hand; the field exists now so
// that an integration later is a new option rather than a migration.
export const ORDER_SOURCES = [
  { value: 'manual', label: 'Manual entry' },
  { value: 'shopify', label: 'Shopify' },
  { value: 'woocommerce', label: 'WooCommerce' },
  { value: 'amazon', label: 'Amazon' },
  { value: 'api', label: 'API' },
];

export const OrderSourceField = enumField(StringField, {
  options: ORDER_SOURCES,
  displayName: 'Order Source',
});

export const PAYMENT_STATUSES = [
  { value: 'paid', label: 'Paid' },
  { value: 'pending', label: 'Pending' },
  { value: 'partial', label: 'Partially paid' },
  { value: 'refunded', label: 'Refunded' },
];

export const PaymentStatusField = enumField(StringField, {
  options: PAYMENT_STATUSES,
  displayName: 'Payment Status',
});

export const ORDER_PRIORITIES = [
  { value: 'normal', label: 'Normal' },
  { value: 'express', label: 'Express' },
  { value: 'rush', label: 'Rush' },
];

export const OrderPriorityField = enumField(StringField, {
  options: ORDER_PRIORITIES,
  displayName: 'Priority',
});

// Urgency is a status, so the priority pill takes the status hues.
const PRIORITY_HUE: Record<string, Hue> = {
  express: 'amber',
  rush: 'orange',
};

const TIMELINE_FACTS = [
  { key: 'Placed', value: 'placedAt' },
  { key: 'Fulfilled', value: 'fulfilledAt' },
  { key: 'Source', value: 'source' },
];

function labelOf(options: { value: string; label: string }[], value?: string) {
  return options.find((o) => o.value === value)?.label ?? value ?? '';
}

// Order (Or) — what the customer bought, and how far it has got.
//
// Money is computed, never stored: subtotal comes from the lines, total from
// subtotal plus shipping plus tax. A stored total is a number that can disagree
// with the rows above it, and eventually does.
//
// `fulfilledAt` is an event fact — the datetime the order first completed,
// written once by the FulfilOrder command. "Is it fulfilled" is then a question
// about that date rather than a second flag that can drift out of step.
export class FulfilmentOrder extends CardDef {
  static displayName = 'Order';
  static icon = ReceiptIcon;

  @field orderNumber = contains(StringField);
  @field source = contains(OrderSourceField);
  @field externalId = contains(StringField);

  @field customerName = contains(StringField);
  @field customerEmail = contains(EmailField);
  @field shippingAddress = contains(AddressField);
  @field billingAddress = contains(AddressField);

  @field lineItems = containsMany(FulfilmentLineItemField);

  @field shippingCost = contains(AmountWithCurrency);
  @field tax = contains(AmountWithCurrency);

  @field status = contains(OrderStatusField);
  @field paymentStatus = contains(PaymentStatusField);
  @field priority = contains(OrderPriorityField);

  @field allocatedWarehouse = linksTo(() => Warehouse);
  @field notes = contains(MarkdownField);
  @field tags = containsMany(StringField);

  @field placedAt = contains(DatetimeField);
  @field fulfilledAt = contains(DatetimeField);

  @field subtotal = contains(AmountWithCurrency, {
    computeVia: function (this: FulfilmentOrder) {
      let result = new AmountWithCurrency();
      let currency = new CurrencyField();
      currency.code = this.currencyCode ?? 'USD';
      result.currency = currency;
      result.amount = (this.lineItems ?? []).reduce(
        (sum, line) =>
          sum + (line?.unitPrice?.amount ?? 0) * (line?.quantity ?? 0),
        0,
      );
      return result;
    },
  });

  @field total = contains(AmountWithCurrency, {
    computeVia: function (this: FulfilmentOrder) {
      let result = new AmountWithCurrency();
      let currency = new CurrencyField();
      currency.code = this.currencyCode ?? 'USD';
      result.currency = currency;
      result.amount =
        (this.subtotal?.amount ?? 0) +
        (this.shippingCost?.amount ?? 0) +
        (this.tax?.amount ?? 0);
      return result;
    },
  });

  @field itemCount = contains(NumberField, {
    computeVia: function (this: FulfilmentOrder) {
      return (this.lineItems ?? []).reduce(
        (sum, line) => sum + (line?.quantity ?? 0),
        0,
      );
    },
  });

  // The order's currency is whatever its first priced line says. One order, one
  // currency — mixed-currency orders are explicitly out of scope for v1.
  @field currencyCode = contains(StringField, {
    computeVia: function (this: FulfilmentOrder) {
      let line = (this.lineItems ?? []).find(
        (l) => l?.unitPrice?.currency?.code,
      );
      return line?.unitPrice?.currency?.code;
    },
  });

  @field warehouseCode = contains(StringField, {
    computeVia: function (this: FulfilmentOrder) {
      return this.allocatedWarehouse?.code;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: FulfilmentOrder) {
      return this.orderNumber?.length ? this.orderNumber : 'Untitled Order';
    },
  });

  get statusStyle() {
    return orderStatusStyle(this.status);
  }

  get progress() {
    return Math.round(orderProgress(this.status) * 100);
  }

  get isExpress() {
    return this.priority === 'express' || this.priority === 'rush';
  }

  get priorityLabel() {
    return labelOf(ORDER_PRIORITIES, this.priority);
  }

  get priorityHue(): Hue {
    return PRIORITY_HUE[this.priority ?? ''] ?? 'slate';
  }

  get isFulfilled() {
    return this.fulfilledAt != null;
  }

  get shipToLabel() {
    let a = this.shippingAddress;
    if (!a) {
      return undefined;
    }
    return [a.city, a.postalCode].filter(Boolean).join(' ') || a.country?.name;
  }

  get lineSummary() {
    return (this.lineItems ?? []).slice(0, 3);
  }

  static isolated = class Isolated extends Component<typeof FulfilmentOrder> {
    get lifecycle() {
      return lifecycleSteps(
        ORDER_PIPELINE,
        (value) => orderStatusStyle(value).label,
        ORDER_PIPELINE.indexOf(this.args.model?.status ?? ''),
      );
    }

    get paymentLabel() {
      return labelOf(PAYMENT_STATUSES, this.args.model?.paymentStatus);
    }

    // The totals block as KeyValue rows: every line is a formatted string.
    get totalsFacts() {
      let model = this.args.model;
      let code = model?.currencyCode;
      let shipping = model?.shippingCost?.amount;
      let tax = model?.tax?.amount;
      return [
        { key: 'Subtotal', value: money(model?.subtotal?.amount, code) },
        { key: 'Shipping', value: shipping ? money(shipping, code) : '—' },
        { key: 'Tax', value: tax ? money(tax, code) : '—' },
        { key: 'Total', value: money(model?.total?.amount, code) },
      ];
    }

    <template>
      <article class='ord'>
        {{#if @model.isExpress}}
          <div class='flash' aria-hidden='true'></div>
        {{/if}}

        <header class='hd'>
          <div class='hd-id'>
            <span class='eyebrow'>Order</span>
            <h1 class='num'>{{@model.orderNumber}}</h1>
            <p class='cust'>
              {{if @model.customerName @model.customerName 'No customer name'}}
              {{#if @model.shipToLabel}}<span class='to'>→
                  {{@model.shipToLabel}}</span>{{/if}}
            </p>
          </div>
          <div class='hd-state'>
            <StatusChip
              @label={{@model.statusStyle.label}}
              @hue={{@model.statusStyle.hue}}
              @size='base'
            />
            {{#if @model.isExpress}}
              <StatePill
                @label={{@model.priorityLabel}}
                @hue={{@model.priorityHue}}
              />
            {{/if}}
          </div>
        </header>

        {{! Pret UI StepList, track variant: one bar per happy-path stage with
            its caption. An order that has left the path (on hold, cancelled,
            returned) shows every stage upcoming. }}
        <StepList
          class='track'
          @steps={{this.lifecycle}}
          @variant='track'
          @label='Order progress'
        />

        <div class='stats'>
          <Stat
            class='stat'
            @label='Items'
            @value={{if @model.itemCount @model.itemCount 0}}
          />
          <Stat
            class='stat'
            @label='Total'
            @value={{money @model.total.amount @model.currencyCode}}
            @roll={{false}}
          />
          <Stat
            class='stat stat-sm'
            @label='Warehouse'
            @value={{if
              @model.warehouseCode
              @model.warehouseCode
              'Not allocated'
            }}
            @roll={{false}}
          />
          <Stat
            class='stat stat-sm'
            @label='Payment'
            @value={{this.paymentLabel}}
            @roll={{false}}
          />
        </div>

        <section class='sec'>
          <h2><List class='sec-icon' role='presentation' />Line items</h2>
          {{#if @model.lineItems.length}}
            <div class='li-head'>
              <span>Item</span><span>Qty</span><span>Unit</span><span
              >Total</span>
            </div>
            <@fields.lineItems @format='embedded' />
            <KeyValue class='totals' @items={{this.totalsFacts}} />
          {{else}}
            <EmptyState
              class='empty'
              @texture={{false}}
              @title='No line items'
              @message='An order with no lines cannot be picked — add at least one before allocating.'
            />
          {{/if}}
        </section>

        <div class='cols'>
          <section class='sec'>
            <h2><MapPin class='sec-icon' role='presentation' />Ship to</h2>
            <@fields.shippingAddress @format='embedded' />
          </section>
          <section class='sec'>
            <h2><Clock class='sec-icon' role='presentation' />Timeline</h2>
            <KeyValue class='kv' @items={{TIMELINE_FACTS}}>
              <:value as |item|>
                {{#if (eq item.value 'placedAt')}}
                  <@fields.placedAt @format='atom' />
                {{else if (eq item.value 'fulfilledAt')}}
                  {{#if @model.fulfilledAt}}<@fields.fulfilledAt
                      @format='atom'
                    />{{else}}Not yet{{/if}}
                {{else}}
                  <@fields.source @format='atom' />
                {{/if}}
              </:value>
            </KeyValue>
          </section>
        </div>

        {{#if @model.notes}}
          <section class='sec'>
            <h2><FileText class='sec-icon' role='presentation' />Notes</h2>
            <@fields.notes />
          </section>
        {{/if}}
      </article>

      <style scoped>
        .ord {
          /* Type scale, mapped to the house 1.333 modular scale rather than the
             28 hand-picked rem values these cards used to carry — 44 of which
             fell below 12px, under the smallest token the design system has. */
          --t-micro: var(--boxel-font-size-xs);
          --t-sm: var(--boxel-font-size-sm);
          --t-body: var(--boxel-font-size);
          --t-lg: var(--boxel-font-size-lg);
          --t-xl: var(--boxel-font-size-xl);
          /* Isolated gets NO container from the host — every ancestor up to the
             panel is `container-type: normal`, so an `@container` rule here is
             inert until this declares its own. `inline-size`, not `size`: the
             card scrolls, and `size` needs a definite block size. */
          container-type: inline-size;
          container-name: card-iso;

          /* ONE panel primitive. Every full-width tinted block on this card —
             section, note, alert, callout — takes its ground, inset and radius
             from here, because a background makes spacing VISIBLE: while
             sections were separated by whitespace alone, a note padded
             `sp-sm` and a section padded `sp-lg` looked the same. Tint them
             both and their text edges no longer line up down the page, and
             every gap between them reads as a mis-registration rather than a
             rhythm. The inset is the thing that must agree; the tint only
             exposed it. */
          --panel-bg: color-mix(in oklch, var(--foreground) 3%, transparent);
          --panel-pad: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          --panel-radius: var(--radius);
          /* The ONE vertical rhythm. It used to be `margin-top` on `.sec` plus a
             `.cols .sec { margin-top: 0 }` override for the side-by-side case —
             two mechanisms for one relationship, and `.cols` itself had neither,
             so the measured gap above a two-column group was 0px while the gap
             above a stacked section was 28.4px. A tinted panel colliding with
             the text above it is what that 0 looks like. */
          --panel-gap: var(--boxel-sp-xl);
          --ful-rule: color-mix(in oklch, var(--foreground) 12%, transparent);
          /* Named because no semantic token expresses it: the tear line down a
             shipping label. */
          --ful-perf: color-mix(in oklch, var(--foreground) 22%, transparent);

          position: relative;
          display: flex;
          flex-direction: column;
          gap: var(--panel-gap);
          height: 100%;
          overflow-y: auto;
          padding: var(--boxel-sp-lg);
        }
        /* Express orders get a rail down the left edge — the physical
           equivalent of the coloured tape a picker looks for. */
        .flash {
          position: absolute;
          inset: 0 auto 0 0;
          width: 0.25rem;
          background: repeating-linear-gradient(
            -45deg,
            var(--ful-perf) 0 0.375rem,
            transparent 0.375rem 0.75rem
          );
        }
        .hd {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp);
          justify-content: space-between;
          align-items: flex-start;
          padding-bottom: var(--boxel-sp);
          border-bottom: 0.125rem dashed var(--ful-perf);
        }
        .eyebrow {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .num {
          margin: 0.125rem 0 0;
          font-family: var(--font-mono);
          font-size: var(--t-xl);
          line-height: 1;
          letter-spacing: -0.01em;
        }
        .cust {
          margin: 0.5rem 0 0;
          font-size: var(--t-sm);
          color: var(--muted-foreground);
        }
        .to {
          margin-left: 0.375rem;
        }
        .hd-state {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        /* Pret UI StepList, track variant. Captions sit at the micro size.
           The track draws its markers with no disc, so the current number
           and the bars read the ink tokens: the stock current marker is
           --primary-foreground (1.50:1 on the dark panel) and the stock
           current bar is --primary (1.22:1 on the light panel). */
        .track {
          --text-ui: var(--t-micro);
          --pretui-step-current-marker-fg: var(--primary-ink);
          --pretui-step-current-bar: var(--primary-ink);
          --pretui-step-complete-marker-fg: var(--success-ink);
          --pretui-step-complete-bar: var(--success-ink);
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(7.5rem, 1fr));
          gap: var(--boxel-sp);
        }
        /* Pret UI Stat: the knob keeps the figures at the old sizes. */
        .stat {
          --text-stat: var(--t-lg);
        }
        .stat-sm {
          --text-stat: var(--t-sm);
        }
        .sec {
          /* A surface, not just a gap. Sections were told apart only by spacing,
             and their headings were 12px uppercase muted — pixel-identical to
             every table column label on the card, so "where does a section
             start" had no answer. The ground is mixed toward --foreground so it
             follows the theme in both modes rather than being a grey. */
          padding: var(--panel-pad);
          border-radius: var(--panel-radius);
          background-color: var(--panel-bg);
        }
        .sec h2 {
          /* The section heading is now the loudest uppercase thing on the card:
             --foreground against the column labels' --muted-foreground. Weight
             alone (500 vs 400) was not a readable difference. */
          display: flex;
          align-items: center;
          gap: 0.4375rem;
          margin: 0 0 var(--boxel-sp-xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--foreground);
        }
        .li-head {
          display: grid;
          grid-template-columns: minmax(0, 1fr) 3rem 5.5rem 6rem;
          gap: var(--boxel-sp-xs);
          padding-bottom: 0.25rem;
          border-bottom: 1px solid var(--border);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .li-head span:nth-child(n + 2) {
          text-align: right;
        }
        /* Pret UI KeyValue for the totals, right-aligned under the lines
           with the grand total set heavier above a rule. */
        .sec .totals {
          --text-ui: var(--t-sm);
          --text-ui-md: var(--t-sm);
          --space-6: var(--boxel-sp-lg);
          justify-content: end;
          grid-template-columns: 6rem 6rem;
          margin-top: var(--boxel-sp-sm);
          padding-top: var(--boxel-sp-xs);
          border-top: 1px dashed var(--ful-perf);
        }
        .totals :deep(dd) {
          justify-content: flex-end;
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
        }
        .totals :deep(dt:last-of-type),
        .totals :deep(dd:last-of-type) {
          padding-top: 0.25rem;
          border-top: 1px solid var(--border);
          font-size: var(--t-body);
          font-weight: 800;
        }
        .totals :deep(dt:last-of-type) {
          color: var(--foreground);
        }
        .cols {
          display: grid;
          gap: var(--boxel-sp-lg);
          grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
        }
        /* Pret UI KeyValue: label and value sizes and the column gap. */
        .kv {
          --text-ui: var(--t-micro);
          --text-ui-md: var(--t-sm);
          --space-6: 1.25rem;
        }
        /* Pret UI EmptyState, compact: no texture, 1rem padding, and the
           title at the body size. */
        .empty {
          --space-9: 1rem;
          --space-6: 1rem;
          --text-heading: var(--boxel-font-size);
        }

        /* Section icons: one size, one muted colour, everywhere. They make the
           card scannable by shape; they must never compete with the heading. */
        h2 .sec-icon {
          width: max(0.875rem, 1em);
          height: max(0.875rem, 1em);
          flex: 0 0 auto;
          color: var(--muted-foreground);
        }

        /* One collapse stop. The card is rendered in a resizable stack panel, so
           this fires when a second card opens beside it — not only on a phone. */
        @container card-iso (width < 720px) {
          .cols,
          .grid,
          .two {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof FulfilmentOrder> {
    <template>
      <div class='o-emb'>
        <span class='o-num'>{{#if @model.orderNumber}}<Token
              class='o-token'
              @value={{@model.orderNumber}}
            />{{/if}}</span>
        <span class='o-cust'>{{if
            @model.customerName
            @model.customerName
            '—'
          }}</span>
        <span class='o-status'><StatusChip
            @label={{@model.statusStyle.label}}
            @hue={{@model.statusStyle.hue}}
          /></span>
        <span class='o-slot'>{{@model.itemCount}} items</span>
        <Money
          class='o-slot o-total'
          @amount={{@model.total.amount}}
          @code={{@model.currencyCode}}
        />
      </div>

      <style scoped>
        /* A CardDef's embedded template must supply its OWN inset. The host wraps
           a linksTo render in a CardContainer that draws a rounded boundary and
           deliberately adds no padding — field-component.gts:513 says so in as
           many words, because padding there would move the container-query
           breakpoints the card reasons about. With none on either side the text
           sits flush against the pill, which is what "Northline Supply" looked
           like inside Supplied by. FieldDef embeddeds get no boundary and so
           never showed this. */
        .o-emb {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr) auto 5rem 5.5rem;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: 0.88rem;
        }
        .o-num {
          min-width: 0;
        }
        /* Pret UI Token for the order number, on the primary ink. */
        .o-num .o-token {
          --pretui-token-hue: var(--primary-ink);
          --text-body: calc(0.88rem + 3.5px);
          margin-inline: 0;
          max-width: 100%;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .o-cust {
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .o-slot {
          text-align: right;
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          font-size: 0.78rem;
          color: var(--muted-foreground);
        }
        .o-total {
          font-size: 0.9rem;
          font-weight: 700;
          color: var(--foreground);
        }
        @container (width < 430px) {
          .o-emb {
            grid-template-columns: 7rem minmax(0, 1fr) 5.5rem;
          }
          .o-status,
          .o-slot:not(.o-total) {
            display: none;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof FulfilmentOrder> {
    <template>
      <span class='o-atom'>{{@model.orderNumber}}</span>
      <style scoped>
        .o-atom {
          font-family: var(--font-mono);
          font-size: 0.85em;
          font-weight: 700;
        }
      </style>
    </template>
  };

  // The shipping label. Hand-rolled rather than a FittedCard because the card
  // has a visual world of its own — perforated edge, status dot, priority
  // hatching — and bending FittedCard's slots around it would cost more than
  // building it.
  //
  // Progressive across the size spectrum: badge = number + status dot; strip
  // adds items and total; tile adds the customer and destination; card adds the
  // first three SKUs and the warehouse.
  static fitted = class Fitted extends Component<typeof FulfilmentOrder> {
    <template>
      <article class='fit {{if @model.isExpress "is-express"}}'>
        <div class='r-head'>
          <div class='hd-row'>
            <span class='dot' style={{dotStyle @model.statusStyle.hue}}></span>
            <span class='num'>{{@model.orderNumber}}</span>
          </div>
          <span class='status'>{{@model.statusStyle.label}}</span>
        </div>

        <div class='r-body'>
          <p class='cust'>{{if @model.customerName @model.customerName ''}}</p>
          {{#if @model.shipToLabel}}
            <p class='dest'>{{@model.shipToLabel}}</p>
          {{/if}}
          <ul class='lines'>
            {{#each @model.lineSummary as |line|}}
              <li><span class='q'>{{line.quantity}}×</span>{{line.sku}}</li>
            {{/each}}
          </ul>
        </div>

        <div class='r-meta'>
          <span class='items'>{{@model.itemCount}} items</span>
          <span class='wh'>{{if
              @model.warehouseCode
              @model.warehouseCode
              ''
            }}</span>
          <Money
            class='total'
            @amount={{@model.total.amount}}
            @code={{@model.currencyCode}}
          />
        </div>
      </article>

      <style scoped>
        .fit {
          --type-ratio: 1.24;
          --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
          /* The block-axis budget. `--type-base` is driven mostly by `cqi`, which
             is huge in a wide, short cell (a 691x105 strip gave 15px, and the
             25px number it produced needed a 30px line box in a row that only
             had 22px — a 12px shear straight through the digits). Capping the
             SCALE against `cqb` fixes every role at once, where capping each
             display role individually did not: in a tall cell the cqi term still
             governs, so tiles are unchanged. */
          --type-base: clamp(
            0.625rem,
            min(calc(0.1875rem + 2.1cqi + 1cqb - 0.6 * var(--ar)), 10cqb),
            1.0625rem
          );
          --meta-size: max(
            0.6875rem,
            calc(var(--type-base) / var(--type-ratio))
          );
          --glyph-size: max(0.6875rem, min(3cqi, 14cqb));
          /* The identifier is a VALUE, so it must render in full. It is capped
             against the inline axis as well as the block axis so a real order /
             RMA / SKU always fits its box — the ellipsis below is a safety net
             for a pathological identifier, not a truncation strategy. */
          --num-size: max(
            0.6875rem,
            min(
              calc(var(--type-base) * pow(var(--type-ratio), 2)),
              26cqb,
              7.5cqi
            )
          );
          --pad: clamp(0.375rem, calc(0.125rem + 1.7cqi), 0.875rem);
          --perf: color-mix(in oklch, var(--card-foreground) 20%, transparent);

          position: relative;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'body' 'meta';
          gap: 0.1875rem;
          padding: var(--pad);
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        /* The hatched rail reads as priority tape at every size, which is what
           keeps the card's identity alive down at badge. */
        .is-express::before {
          content: '';
          position: absolute;
          inset: 0 auto 0 0;
          width: 0.1875rem;
          background: repeating-linear-gradient(
            -45deg,
            var(--perf) 0 0.25rem,
            transparent 0.25rem 0.5rem
          );
        }
        .r-head,
        .r-body,
        .r-meta {
          overflow: hidden;
          min-height: 0;
        }
        .r-head {
          grid-area: head;
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 0.375rem;
        }
        .r-body {
          grid-area: body;
        }
        .r-meta {
          grid-area: meta;
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 0.375rem;
          padding-top: 0.1875rem;
          border-top: 1px dashed var(--perf);
          font-family: var(--font-mono);
          font-size: var(--meta-size);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        .hd-row {
          display: flex;
          align-items: center;
          gap: 0.3125rem;
          min-width: 0;
        }
        .dot {
          flex: none;
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: color-mix(
            in oklch,
            var(--st-hue, var(--muted-foreground)) 72%,
            transparent
          );
        }
        .num {
          font-family: var(--font-mono);
          font-size: var(--num-size);
          font-weight: 800;
          line-height: 1.2;
          letter-spacing: -0.01em;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .status {
          font-size: var(--meta-size);
          font-weight: 700;
          white-space: nowrap;
          color: var(--muted-foreground);
        }
        .cust {
          margin: 0.125rem 0 0;
          font-size: var(--type-base);
          font-weight: 600;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 1;
          overflow: hidden;
        }
        .dest {
          margin: 0.0625rem 0 0;
          font-size: var(--meta-size);
          color: var(--muted-foreground);
          display: -webkit-box;
          -webkit-box-orient: vertical;
          -webkit-line-clamp: 1;
          overflow: hidden;
        }
        .lines {
          margin: 0.3125rem 0 0;
          padding: 0;
          list-style: none;
          display: grid;
          gap: 0.0625rem;
          font-family: var(--font-mono);
          font-size: var(--meta-size);
          color: var(--muted-foreground);
        }
        .lines li {
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .q {
          font-weight: 700;
          margin-right: 0.25rem;
          color: var(--card-foreground);
        }
        .total {
          font-weight: 800;
          color: var(--card-foreground);
        }

        /* Badge: number + status dot only. */
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: auto;
          }
          .r-body,
          .r-meta {
            display: none;
          }
        }
        /* Strip: meta row returns, body still out. */
        @container fitted-card (50px < height <= 80px) {
          .r-body {
            display: none;
          }
          .wh {
            display: none;
          }
        }
        /* Thin tile: customer and destination, but no line list yet. */
        @container fitted-card (80px < height <= 130px) {
          .lines {
            display: none;
          }
        }
        /* Full card: everything, including the first three SKUs. */
        @container fitted-card (height > 170px) {
          .lines {
            gap: 0.125rem;
          }
        }
        @container fitted-card (width <= 150px) {
          .status,
          .wh {
            display: none;
          }
        }
        @container fitted-card (width <= 110px) {
          .items {
            display: none;
          }
        }
      </style>
    </template>
  };
}

function dotStyle(hue: string | undefined) {
  return htmlSafe(`--st-hue: ${hue ?? 'var(--muted-foreground)'}`);
}

export default FulfilmentOrder;
