import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import DatetimeField from 'https://cardstack.com/base/datetime';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/pretui/components/button';
import PackageIcon from '@cardstack/boxel-icons/package';
import { RichFittedCard } from '../shared/rich-fitted-card';
import TrackingNumberField from './tracking-number';
import ParcelDimensionsField from './parcel-dimensions';
import DeliveryWindowField from './delivery-window';
import { FulfilmentLineItemField } from './fulfilment-line-item';
import {
  ShipmentStatusField,
  shipmentStatusStyle,
  isShipmentException,
} from './shipment-status';
import { FulfilmentOrder } from './fulfilment-order';
import { Warehouse } from './warehouse';
import { Carrier } from './carrier';
import { IsoFrame } from '../shared/compact-sheet';

// One scan on the package's journey. Carriers emit these; we store them
// verbatim rather than collapsing them into the status, because the sequence is
// what a customer service conversation is actually about.
export class TrackingEventField extends FieldDef {
  static displayName = 'Tracking Event';

  @field occurredAt = contains(DatetimeField);
  @field statusCode = contains(StringField);
  @field statusDescription = contains(StringField);
  @field location = contains(StringField);
  @field isDelivered = contains(BooleanField);

  static embedded = class Embedded extends Component<
    typeof TrackingEventField
  > {
    <template>
      <div class='ev'>
        <span class='ev-when'><@fields.occurredAt @format='atom' /></span>
        <span class='ev-desc'>{{@model.statusDescription}}</span>
        <span class='ev-where'>{{if @model.location @model.location '—'}}</span>
      </div>

      <style scoped>
        .ev {
          display: grid;
          grid-template-columns: 10rem minmax(0, 1fr) 9rem;
          gap: var(--boxel-sp-xs);
          font-size: 0.82rem;
          padding: 0.1875rem 0;
        }
        .ev-when {
          font-family: var(--font-mono);
          color: var(--muted-foreground);
        }
        .ev-desc {
          font-weight: 600;
          color: var(--foreground);
        }
        .ev-where {
          text-align: right;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof TrackingEventField> {
    <template>
      <span class='ev-atom'>{{@model.statusDescription}}</span>
      <style scoped>
        .ev-atom {
          font-size: 0.85em;
        }
      </style>
    </template>
  };
}

// Shipment (Sh) — a physical package.
//
// Kept separate from the order on purpose. One order becomes two shipments when
// stock sits in two warehouses; two orders become one when a customer buys
// twice in a morning. Neither is expressible if shipment is a set of fields on
// the order.
//
// The carrier's name, tracking URL pattern and dimensional divisor are
// SNAPSHOTTED onto the shipment when the label is created, not read through the
// link. A carrier renaming a service two years from now must not rewrite what
// happened on a package that already arrived.
class ShipmentIsolated extends Component<typeof Shipment> {
  get model() {
    return this.args.model as Shipment;
  }
  get stats() {
    return stats(this.model);
  }
  get events() {
    return sortedEvents(this.model);
  }
  get parcelRows() {
    return parcelRows(this.model);
  }
  get offPath() {
    let s = this.model.status;
    return s === 'exception' || s === 'returned_to_sender';
  }
  // Re-shipping and raising a return both start from the order, so both
  // actions open it.
  openOrder = () => {
    let order = this.model.order;
    if (order) this.args.viewCard?.(order as any);
  };

  <template>
    <IsoFrame>
      <article class='shp'>
        <header class='ihead'>
          <div class='who'>
            <span class='mark' aria-hidden='true'>Sh</span>
            <div class='id'>
              <h1 class='name'>{{if
                  @model.shipmentNumber
                  @model.shipmentNumber
                  'Untitled shipment'
                }}</h1>
              <p class='meta'>{{metaLine @model}}</p>
            </div>
          </div>
          <div class='bar'>
            <span class='st' data-tone={{statusTone @model.status}}><span
                class='dot'
              ></span>{{statusText @model}}</span>
            <span class='st'><span class='dot'></span>{{if
                @model.isDropship
                'dropship'
                'warehouse'
              }}</span>
            {{#if @model.order}}
              {{#if this.offPath}}
                <Button
                  @variant='primary'
                  @size='sm'
                  {{on 'click' this.openOrder}}
                >Re-ship</Button>
                <Button
                  @variant='outline'
                  @size='sm'
                  {{on 'click' this.openOrder}}
                >Open return</Button>
              {{else}}
                <Button
                  @variant='outline'
                  @size='sm'
                  {{on 'click' this.openOrder}}
                >Open order</Button>
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
          <h2>Tracking</h2>
          {{#each this.events as |e|}}
            <div class='row'>
              <span class='lead'>
                <span class='st' data-tone={{eventTone e.statusCode}}><span
                    class='dot'
                  ></span></span>
                <span class='strong'>{{e.statusDescription}}</span>
                <span class='meta mono-ish'>{{eventMeta e}}</span>
              </span>
              <span class='mono'>{{e.statusCode}}</span>
            </div>
          {{else}}
            <p class='row meta'>No scans yet</p>
          {{/each}}
        </section>

        <section class='blk'>
          <h2>Parcel</h2>
          <dl class='kv'>
            {{#each this.parcelRows as |r|}}
              <dt class='cap'>{{r.k}}</dt>
              <dd>{{r.v}}</dd>
            {{/each}}
          </dl>
        </section>

        <section class='blk'>
          <h2>Line items</h2>
          {{#each @model.lineItems as |l|}}
            <div class='row'>
              <span class='lead'>
                <span class='strong'>{{l.productName}} × {{l.quantity}}</span>
                <span class='meta'>{{lineMeta l}}</span>
              </span>
              <span class='mono'>{{if
                  @model.isDropship
                  'dropship'
                  l.quantityFulfilled
                }}</span>
            </div>
          {{else}}
            <p class='row meta'>—</p>
          {{/each}}
        </section>

        <section class='blk'>
          <h2>Linked</h2>
          <dl class='kv'>
            <dt class='cap'>Order</dt>
            <dd>{{#if @model.order}}<@fields.order
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</dd>
            <dt class='cap'>Origin</dt>
            <dd>{{#if @model.originWarehouse}}<@fields.originWarehouse
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</dd>
            <dt class='cap'>Carrier</dt>
            <dd>{{#if @model.carrier}}<@fields.carrier
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</dd>
          </dl>
        </section>
      </article>
    </IsoFrame>
    <style scoped>
      .shp {
        container-type: inline-size;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        line-height: 1.4;
        color: var(--foreground);
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
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
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
        font-size: 0.5625rem;
        font-weight: 700;
        color: var(--foreground);
      }
      .id {
        min-width: 0;
      }
      .name {
        margin: 0;
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-sm);
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
        font-size: 0.5625rem;
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
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
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
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-2xs);
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
      .lead .st {
        align-self: center;
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
      @container (width < 560px) {
        .stats {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
    </style>
  </template>
}

export class Shipment extends CardDef {
  static displayName = 'Shipment';
  static icon = PackageIcon;

  @field shipmentNumber = contains(StringField);
  @field order = linksTo(() => FulfilmentOrder);
  @field originWarehouse = linksTo(() => Warehouse);
  @field carrier = linksTo(() => Carrier);

  @field lineItems = containsMany(FulfilmentLineItemField);
  @field parcel = contains(ParcelDimensionsField);
  @field trackingNumber = contains(TrackingNumberField);
  @field deliveryWindow = contains(DeliveryWindowField);
  @field trackingEvents = containsMany(TrackingEventField);

  @field serviceLevel = contains(StringField);
  @field carrierName = contains(StringField);
  @field shippingCost = contains(AmountWithCurrency);
  @field customerPaid = contains(AmountWithCurrency);
  @field labelUrl = contains(StringField);

  @field status = contains(ShipmentStatusField);
  @field shippedAt = contains(DatetimeField);
  @field deliveredAt = contains(DatetimeField);
  @field proofOfDelivery = contains(StringField);
  @field isDropship = contains(BooleanField);

  @field orderNumber = contains(StringField, {
    computeVia: function (this: Shipment) {
      return this.order?.orderNumber;
    },
  });

  @field originCode = contains(StringField, {
    computeVia: function (this: Shipment) {
      return this.originWarehouse?.code;
    },
  });

  @field itemCount = contains(NumberField, {
    computeVia: function (this: Shipment) {
      return (this.lineItems ?? []).reduce(
        (sum, l) => sum + (l?.quantity ?? 0),
        0,
      );
    },
  });

  // Margin on the shipping line: what the customer paid minus what the carrier
  // charged. Negative is the number worth seeing, which is why it is computed
  // rather than left for someone to work out per package.
  @field shippingMargin = contains(NumberField, {
    computeVia: function (this: Shipment) {
      let paid = this.customerPaid?.amount;
      let cost = this.shippingCost?.amount;
      if (paid == null || cost == null) {
        return undefined;
      }
      return Math.round((paid - cost) * 100) / 100;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Shipment) {
      return this.shipmentNumber?.length
        ? this.shipmentNumber
        : 'Untitled Shipment';
    },
  });

  get statusStyle() {
    return shipmentStatusStyle(this.status);
  }

  get isException() {
    return isShipmentException(this.status);
  }

  // Before dispatch there is no snapshot yet, so fall back to the linked
  // carrier's current name. After dispatch the snapshot wins — which is the
  // whole point of taking one.
  get carrierLabel() {
    return this.carrierName ?? this.carrier?.carrierName;
  }

  // Losing money on the shipping line is the number a small business wants
  // flagged, not buried in a column of similar-looking figures.
  get isMarginNegative() {
    return this.shippingMargin != null && this.shippingMargin < 0;
  }

  // Late is derived, not stored: the promise and the actual are both already
  // here, so a stored flag would only be a third thing to keep in step.
  get isLate() {
    let promised = this.deliveryWindow?.latest;
    if (!promised) {
      return false;
    }
    let actual = this.deliveredAt;
    if (actual) {
      return actual.getTime() > promised.getTime();
    }
    return this.status !== 'delivered' && Date.now() > promised.getTime();
  }

  get latestEvent() {
    let events = (this.trackingEvents ?? []).filter(Boolean);
    if (!events.length) {
      return undefined;
    }
    return [...events].sort(
      (a, b) => (a.occurredAt?.getTime() ?? 0) - (b.occurredAt?.getTime() ?? 0),
    )[events.length - 1];
  }

  static isolated = ShipmentIsolated;

  static embedded = class Embedded extends Component<typeof Shipment> {
    get rows() {
      return embRows(this.args.model as Shipment);
    }
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>Sh</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
          <span class='st' data-tone={{statusTone @model.status}}><span
              class='dot'
            ></span>{{statusText @model}}</span>
        </header>
        <dl class='kv'>
          {{#each this.rows as |r|}}
            <dt>{{r.k}}</dt>
            <dd>{{r.v}}</dd>
          {{/each}}
        </dl>
        <dl class='kv'>
          <dt>Order</dt>
          <dd>{{#if @model.order}}<@fields.order
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</dd>
          <dt>Origin</dt>
          <dd>{{#if @model.originWarehouse}}<@fields.originWarehouse
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</dd>
        </dl>
      </article>
      <style scoped>
        .emb {
          font-family: var(--font-sans);
          font-size: 0.75rem;
          line-height: 1.4;
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.625rem;
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
          font-size: 0.5625rem;
          font-weight: 700;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h3 {
          margin: 0;
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .st {
          flex: none;
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
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
          padding-left: 0.625rem;
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kv dd {
          padding: 0 0.625rem;
          min-width: 0;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Shipment> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Sh</span>
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          max-width: 100%;
          font-size: 0.6875rem;
          font-weight: 600;
          color: var(--foreground);
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
          font-size: 0.5rem;
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

  static fitted = class Fitted extends Component<typeof Shipment> {
    <template>
      <RichFittedCard>
        <:avatar><span class='mark' aria-hidden='true'>Sh</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span class='st' data-tone={{statusTone @model.status}}><span
              class='dot'
            ></span><span class='st-text'>{{statusText
                @model
              }}</span></span></:status>
        <:fact>{{@model.trackingNumber.number}} · {{windowLabel @model}}</:fact>
        <:relations>{{#if @model.order}}<@fields.order
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}{{#if @model.carrier}}<@fields.carrier
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
          margin-right: 0.5rem;
          border-radius: calc(var(--radius) * 0.6);
          background-color: var(--muted);
          font-family: var(--font-mono);
          font-size: 0.6875rem;
          font-weight: 700;
          color: var(--foreground);
        }
        .st {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
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

// ── format helpers (tokens for tone, plain strings for text) ─────────────
type Tone = 'ok' | 'warn' | 'bad' | '';

function statusTone(status: string | undefined): Tone {
  if (status === 'delivered') return 'ok';
  if (status === 'exception' || status === 'returned_to_sender') return 'bad';
  if (status === 'out_for_delivery') return 'warn';
  return '';
}

function eventTone(code: string | undefined | null): Tone {
  if (code === 'RTS') return 'bad';
  if (code === 'EX' || code === 'EXC') return 'warn';
  if (code === 'DL' || code === 'OK') return 'ok';
  return '';
}

function day(d: Date | undefined | null) {
  return d
    ? d.toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
        timeZone: 'UTC',
      })
    : undefined;
}

function dayTime(d: Date | undefined | null) {
  if (!d) return '—';
  let t = d.toLocaleTimeString('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'UTC',
  });
  return `${day(d)}, ${t}`;
}

function money(amount: number | null | undefined, code?: string) {
  if (amount == null) return '—';
  let s = new Intl.NumberFormat('en-GB', {
    style: 'currency',
    currency: code || 'GBP',
  }).format(Math.abs(amount));
  return amount < 0 ? `−${s}` : s;
}

function kg(n: number | null | undefined) {
  return n == null ? '—' : `${Math.round(n * 100) / 100} kg`;
}

function windowLabel(m: Partial<Shipment>) {
  let { earliest: e, latest: l } = m.deliveryWindow ?? ({} as any);
  if (!e && !l) return '—';
  if (!e || !l) return day(e ?? l)!;
  let a = day(e)!;
  let b = day(l)!;
  if (a === b) return a;
  return e.getUTCMonth() === l.getUTCMonth()
    ? `${a}–${l.getUTCDate()}`
    : `${a} – ${b}`;
}

function cityOf(m: Partial<Shipment>) {
  return m.order?.shippingAddress?.city;
}

function metaLine(m: Partial<Shipment>) {
  let carrier = [m.carrierLabel, m.serviceLevel].filter(Boolean).join(' ');
  let who = [m.order?.customerName, cityOf(m)].filter(Boolean).join(', ');
  return [carrier, who].filter(Boolean).join(' · ') || '—';
}

function statusText(m: Partial<Shipment>) {
  return m.status ? m.status.replace(/_/g, ' ') : 'not shipped';
}

function sortedEvents(m: Shipment) {
  return (m.trackingEvents ?? [])
    .filter(Boolean)
    .slice()
    .sort(
      (a, b) => (b.occurredAt?.getTime() ?? 0) - (a.occurredAt?.getTime() ?? 0),
    );
}

function stats(m: Shipment) {
  let words = statusText(m).split(' ');
  let first = words[0] ?? '';
  let last = m.latestEvent?.occurredAt ?? m.deliveredAt ?? m.shippedAt;
  let rest = [words.slice(1).join(' '), day(last)].filter(Boolean).join(', ');
  let code = m.customerPaid?.currency?.code ?? m.shippingCost?.currency?.code;
  let p = m.parcel;
  let commitment = m.deliveryWindow?.commitment ?? m.serviceLevel;
  return [
    {
      label: 'Status',
      tone: statusTone(m.status),
      value: first.charAt(0).toUpperCase() + first.slice(1),
      meta: rest || '—',
    },
    {
      label: 'Margin',
      tone: m.isMarginNegative ? 'bad' : m.shippingMargin ? 'ok' : '',
      value: money(m.shippingMargin, code),
      meta:
        m.customerPaid?.amount === 0
          ? 'free shipping to customer'
          : `customer paid ${money(m.customerPaid?.amount, code)}`,
    },
    {
      label: 'Billable',
      tone: '',
      value: kg(p?.billableWeight),
      meta: p?.isVolumetric
        ? `volumetric beats ${kg(p.weight)}`
        : 'actual weight',
    },
    {
      label: 'Window',
      tone: m.isLate ? 'warn' : '',
      value: windowLabel(m),
      meta:
        [commitment, m.isLate ? 'missed' : undefined]
          .filter(Boolean)
          .join(', ') || '—',
    },
  ];
}

function parcelRows(m: Shipment) {
  let p = m.parcel;
  return [
    { k: 'Dimensions', v: p?.sizeLabel ?? '—' },
    { k: 'Weight', v: kg(p?.weight) },
    {
      k: 'Volumetric weight',
      v:
        p?.volumetricWeight == null
          ? '—'
          : `${kg(p.volumetricWeight)}${p.dimDivisor ? ` (÷ ${p.dimDivisor})` : ''}`,
    },
    { k: 'Billable weight', v: kg(p?.billableWeight) },
  ];
}

function embRows(m: Shipment) {
  let code = m.customerPaid?.currency?.code ?? m.shippingCost?.currency?.code;
  return [
    { k: 'Tracking', v: m.trackingNumber?.number ?? '—' },
    { k: 'Window', v: windowLabel(m) },
    { k: 'Shipped', v: dayTime(m.shippedAt) },
    { k: 'Shipping cost', v: money(m.shippingCost?.amount, code) },
    { k: 'Customer paid', v: money(m.customerPaid?.amount, code) },
    { k: 'Margin', v: money(m.shippingMargin, code) },
    { k: 'Parcel', v: m.parcel?.sizeLabel ?? '—' },
    { k: 'Billable weight', v: kg(m.parcel?.billableWeight) },
  ];
}

function lineMeta(l: FulfilmentLineItemField) {
  return [l.sku, money(l.unitPrice?.amount, l.unitPrice?.currency?.code)]
    .filter(Boolean)
    .join(' · ');
}

function eventMeta(e: TrackingEventField) {
  return [dayTime(e.occurredAt), e.location].filter(Boolean).join(' · ');
}

export default Shipment;
