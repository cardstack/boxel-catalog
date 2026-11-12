import { markDefinition } from '@cardstack/base/mark-definition';
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
import { on } from '@ember/modifier';
import { tracked } from '@glimmer/tracking';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import { Button } from '@cardstack/pretui/components/button';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { RichFittedCard } from '../shared/rich-fitted-card';
import { FulfilmentLineItemField } from './fulfilment-line-item';
import {
  OrderStatusField,
  ORDER_PIPELINE,
  orderStatusStyle,
} from './order-status';
import { Warehouse } from './warehouse';
import { money } from './fulfilment-format';
import { IsoFrame } from '../shared/compact-sheet';

// Where the order came from. v1 enters orders by hand; the field exists now so
// that an integration later is a new option rather than a migration.
export const ORDER_SOURCES = [
  { value: 'manual', label: 'Manual entry' },
  { value: 'shopify', label: 'Shopify' },
  { value: 'woocommerce', label: 'WooCommerce' },
  { value: 'amazon', label: 'Amazon' },
  { value: 'api', label: 'API' },
];

export const OrderSourceField = markDefinition(
  enumField(StringField, {
    options: ORDER_SOURCES,
    displayName: 'Order Source',
  }),
);

export const PAYMENT_STATUSES = [
  { value: 'paid', label: 'Paid' },
  { value: 'pending', label: 'Pending' },
  { value: 'partial', label: 'Partially paid' },
  { value: 'refunded', label: 'Refunded' },
];

export const PaymentStatusField = markDefinition(
  enumField(StringField, {
    options: PAYMENT_STATUSES,
    displayName: 'Payment Status',
  }),
);

export const ORDER_PRIORITIES = [
  { value: 'normal', label: 'Normal' },
  { value: 'express', label: 'Express' },
  { value: 'rush', label: 'Rush' },
];

export const OrderPriorityField = markDefinition(
  enumField(StringField, {
    options: ORDER_PRIORITIES,
    displayName: 'Priority',
  }),
);

// Urgency is a status, so the priority pill takes the status hues.
const PRIORITY_HUE: Record<string, Hue> = {
  express: 'amber',
  rush: 'orange',
};

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
class FulfilmentOrderIsolated extends Component<typeof FulfilmentOrder> {
  @tracked busy = false;

  get model() {
    return this.args.model as FulfilmentOrder;
  }
  get stats() {
    return orderStats(this.model);
  }
  get totals() {
    return totalRows(this.model);
  }
  get canAct() {
    // No store means no persistence: a prerender or read-only surface shows
    // the order without buttons that would silently do nothing.
    return Boolean((this.args as any).context?.store && this.model?.id);
  }
  get nextStatus() {
    let i = ORDER_PIPELINE.indexOf(this.model.status ?? '');
    return i >= 0 ? ORDER_PIPELINE[i + 1] : undefined;
  }
  get nextLabel() {
    return `Move to ${orderStatusStyle(this.nextStatus).label.toLowerCase()}`;
  }
  get canHold() {
    let s = this.model.status;
    return (
      Boolean(s) &&
      !['on_hold', 'shipped', 'delivered', 'cancelled', 'returned'].includes(s!)
    );
  }

  setStatus = async (status: string | undefined) => {
    let store = (this.args as any).context?.store;
    if (!store || !status || this.busy) return;
    this.busy = true;
    try {
      await store.patch(this.model.id, { attributes: { status } });
    } finally {
      this.busy = false;
    }
  };
  advance = () => this.setStatus(this.nextStatus);
  hold = () => this.setStatus('on_hold');

  <template>
    <IsoFrame>
      <article class='ord'>
        <header class='ihead'>
          <div class='who'>
            <span class='mark' aria-hidden='true'>Or</span>
            <div class='id'>
              <h1 class='name'>{{@model.cardTitle}}</h1>
              <p class='meta'>{{metaLine @model}}</p>
            </div>
          </div>
          <div class='bar'>
            <span class='st' data-tone={{statusTone @model.status}}><span
                class='dot'
              ></span>{{statusText @model.status}}</span>
            {{#if @model.isExpress}}
              <span class='st' data-tone='bad'><span class='dot'></span>{{lower
                  @model.priorityLabel
                }}</span>
            {{/if}}
            {{#if @model.paymentStatus}}
              <span
                class='st'
                data-tone={{paymentTone @model.paymentStatus}}
              ><span class='dot'></span>{{lower
                  (paymentLabel @model.paymentStatus)
                }}</span>
            {{/if}}
            {{#if this.canAct}}
              {{#if this.nextStatus}}
                <Button
                  @tone='primary'
                  @appearance='accent'
                  @size='sm'
                  @busy={{this.busy}}
                  {{on 'click' this.advance}}
                >{{this.nextLabel}}</Button>
              {{/if}}
              {{#if this.canHold}}
                <Button
                  @tone='neutral'
                  @appearance='outlined'
                  @size='sm'
                  @disabled={{this.busy}}
                  {{on 'click' this.hold}}
                >Hold</Button>
              {{/if}}
            {{/if}}
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
          <h2>Line items</h2>
          {{#each @model.lineItems as |l|}}
            <div class='row'>
              <span class='lead'>
                <span class='strong'>{{l.productName}} × {{l.quantity}}</span>
                <span class='meta'>{{lineMeta l}}</span>
              </span>
              <span class='mono'>{{shippedText l}}</span>
            </div>
          {{else}}
            <p class='row meta'>No line items — add one before allocating.</p>
          {{/each}}
        </section>

        <section class='blk'>
          <h2>Totals</h2>
          <dl class='kv'>
            {{#each this.totals as |r|}}
              <dt class='cap'>{{r.k}}</dt>
              <dd>{{r.v}}</dd>
            {{/each}}
          </dl>
        </section>

        <section class='blk'>
          <h2>Customer</h2>
          <dl class='kv'>
            <dt class='cap'>Name</dt>
            <dd>{{dash @model.customerName}}</dd>
            <dt class='cap'>Email</dt>
            <dd>{{dash @model.customerEmail}}</dd>
            <dt class='cap'>Ship to</dt>
            <dd>{{addressLine @model.shippingAddress}}</dd>
            <dt class='cap'>Tags</dt>
            <dd>{{tagLine @model.tags}}</dd>
          </dl>
        </section>

        {{#if @model.notes}}
          <section class='blk'>
            <h2>Notes</h2>
            <div class='notes'><@fields.notes /></div>
          </section>
        {{/if}}

        <section class='blk'>
          <h2>Linked</h2>
          <dl class='kv'>
            <dt class='cap'>Warehouse</dt>
            <dd>{{#if @model.allocatedWarehouse}}<@fields.allocatedWarehouse
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</dd>
          </dl>
        </section>
      </article>
    </IsoFrame>
    <style scoped>
      .ord {
        container-type: inline-size;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.4;
        color: var(--card-foreground);
        background-color: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        overflow: hidden;
        --pretui-button-h: 1.625rem;
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
        grid-template-columns: repeat(4, minmax(0, 1fr));
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
        flex-wrap: wrap;
        align-items: baseline;
        column-gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .strong {
        font-weight: 600;
      }
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
        white-space: nowrap;
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
      .notes {
        padding: var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
      }
      @container (width < 560px) {
        .stats {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
    </style>
  </template>
}

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

  static isolated = FulfilmentOrderIsolated;

  static embedded = class Embedded extends Component<typeof FulfilmentOrder> {
    get rows() {
      return embRows(this.args.model as FulfilmentOrder);
    }
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>Or</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
          <span class='st' data-tone={{statusTone @model.status}}><span
              class='dot'
            ></span>{{statusText @model.status}}</span>
        </header>
        <dl class='kv'>
          {{#each this.rows as |r|}}
            <dt>{{r.k}}</dt>
            <dd>{{r.v}}</dd>
          {{/each}}
          <dt>Warehouse</dt>
          <dd>{{#if @model.allocatedWarehouse}}<@fields.allocatedWarehouse
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

  static atom = class Atom extends Component<typeof FulfilmentOrder> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Or</span>
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

  static fitted = class Fitted extends Component<typeof FulfilmentOrder> {
    <template>
      <RichFittedCard>
        <:avatar><span class='mark' aria-hidden='true'>Or</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span class='st' data-tone={{statusTone @model.status}}><span
              class='dot'
            ></span><span class='st-text'>{{statusText
                @model.status
              }}</span></span></:status>
        <:fact>{{money @model.total.amount @model.currencyCode}}
          ·
          {{itemsText @model}}</:fact>
        <:relations>{{#if @model.allocatedWarehouse}}<@fields.allocatedWarehouse
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </RichFittedCard>
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
          color: var(--card-foreground);
        }
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
          flex-shrink: 0;
          border-radius: 50%;
          background-color: var(--tone);
        }
      </style>
    </template>
  };
}

export default FulfilmentOrder;

// ── format helpers (tokens for tone, plain strings for text) ─────────────
type Tone = 'ok' | 'warn' | 'bad' | '';

function statusTone(status: string | undefined | null): Tone {
  if (status === 'delivered' || status === 'shipped') return 'ok';
  if (
    status === 'on_hold' ||
    status === 'awaiting_stock' ||
    status === 'cancelled' ||
    status === 'returned'
  )
    return 'bad';
  if (status === 'picking' || status === 'packing' || status === 'processing')
    return 'warn';
  return '';
}

function statusText(status: string | undefined | null) {
  return status ? orderStatusStyle(status).label.toLowerCase() : 'no status';
}

function paymentLabel(value: string | undefined | null) {
  return labelOf(PAYMENT_STATUSES, value ?? undefined);
}

function paymentTone(value: string | undefined | null): Tone {
  if (value === 'paid') return 'ok';
  if (value === 'pending' || value === 'partial') return 'warn';
  if (value === 'refunded') return 'bad';
  return '';
}

function lower(s: string | undefined | null) {
  return (s ?? '').toLowerCase();
}

function dash(v: unknown) {
  return v == null || v === '' ? '—' : String(v);
}

function day(d: Date | undefined | null) {
  return d
    ? d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        timeZone: 'UTC',
      })
    : '—';
}

function time(d: Date | undefined | null) {
  return d
    ? d.toLocaleTimeString('en-GB', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'UTC',
      })
    : '—';
}

function metaLine(m: Partial<FulfilmentOrder>) {
  return [m.customerName, m.shipToLabel].filter(Boolean).join(' · ') || '—';
}

function addressLine(a: FulfilmentOrder['shippingAddress'] | undefined) {
  if (!a) return '—';
  let city = [a.city, a.postalCode].filter(Boolean).join(' ');
  return (
    [a.addressLine1, a.addressLine2, city, a.country?.name]
      .filter(Boolean)
      .join(', ') || '—'
  );
}

function tagLine(tags: string[] | undefined | null) {
  return (tags ?? []).filter(Boolean).join(', ') || '—';
}

function itemsText(m: Partial<FulfilmentOrder>) {
  let lines = (m.lineItems ?? []).length;
  return `${m.itemCount ?? 0} across ${lines} ${lines === 1 ? 'line' : 'lines'}`;
}

function fulfilledCount(m: Partial<FulfilmentOrder>) {
  return (m.lineItems ?? []).reduce(
    (sum, l) => sum + (l?.quantityFulfilled ?? 0),
    0,
  );
}

function lineMeta(l: FulfilmentLineItemField) {
  let code = l.unitPrice?.currency?.code;
  let each = l.unitPrice?.amount;
  return [
    l.sku,
    each != null ? `${money(each, code)} each` : undefined,
    each != null ? money(each * (l.quantity ?? 0), code) : undefined,
  ]
    .filter(Boolean)
    .join(' · ');
}

function shippedText(l: FulfilmentLineItemField) {
  return `${l.quantityFulfilled ?? 0} / ${l.quantity ?? 0} shipped`;
}

function orderStats(m: FulfilmentOrder) {
  let code = m.currencyCode;
  let lines = (m.lineItems ?? []).length;
  let tax = m.tax?.amount;
  let s = orderStatusStyle(m.status);
  return [
    {
      label: 'Total',
      tone: '',
      value: money(m.total?.amount, code),
      meta: tax ? `incl. ${money(tax, code)} tax` : 'no tax',
    },
    {
      label: 'Items',
      tone: '',
      value: String(m.itemCount ?? 0),
      meta: `${lines} ${lines === 1 ? 'line' : 'lines'}`,
    },
    {
      label: 'Status',
      tone: statusTone(m.status),
      value: m.status ? s.label : '—',
      meta: m.isExpress
        ? `${lower(m.priorityLabel)} · ship today`
        : 'normal priority',
    },
    {
      label: 'Placed',
      tone: '',
      value: day(m.placedAt),
      meta: time(m.placedAt),
    },
  ];
}

function totalRows(m: FulfilmentOrder) {
  let code = m.currencyCode;
  return [
    { k: 'Subtotal', v: money(m.subtotal?.amount, code) },
    { k: 'Shipping', v: money(m.shippingCost?.amount, code) },
    { k: 'Tax', v: money(m.tax?.amount, code) },
    { k: 'Total', v: money(m.total?.amount, code) },
  ];
}

function embRows(m: FulfilmentOrder) {
  return [
    { k: 'Total', v: money(m.total?.amount, m.currencyCode) },
    { k: 'Items', v: itemsText(m) },
    { k: 'Fulfilled', v: `${fulfilledCount(m)} of ${m.itemCount ?? 0}` },
    { k: 'Priority', v: dash(m.priorityLabel) },
    { k: 'Payment', v: dash(paymentLabel(m.paymentStatus)) },
    { k: 'Source', v: dash(labelOf(ORDER_SOURCES, m.source)) },
  ];
}
