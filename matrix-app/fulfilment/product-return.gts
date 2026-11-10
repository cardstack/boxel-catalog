import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DatetimeField from '@cardstack/base/datetime';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import MarkdownField from '@cardstack/base/markdown';
import { htmlSafe } from '@ember/template';
import RotateIcon from '@cardstack/boxel-icons/rotate-ccw';
import { FulfilmentOrder } from './fulfilment-order';
import { Shipment } from './shipment';
import { type StatusStyle } from './fulfilment-status-chip';
import { money } from './fulfilment-format';
import { CompoundAtom } from './fulfilment-ui';
import { FitTile } from '../shared/fit-tile';

// Each status reads a theme token, so a linked theme restyles them; the
// lifecycle steps without a status meaning take the chart hues.
export const RETURN_STATUSES: StatusStyle[] = [
  { value: 'requested', label: 'Requested', hue: 'var(--chart-4)' },
  { value: 'approved', label: 'Approved', hue: 'var(--chart-2)' },
  { value: 'denied', label: 'Denied', hue: 'var(--destructive)' },
  { value: 'in_transit', label: 'In Transit', hue: 'var(--attention)' },
  { value: 'received', label: 'Received', hue: 'var(--chart-1)' },
  { value: 'inspecting', label: 'Inspecting', hue: 'var(--warning)' },
  { value: 'restocked', label: 'Restocked', hue: 'var(--success)' },
  { value: 'disposed', label: 'Disposed', hue: 'var(--muted-foreground)' },
  { value: 'refunded', label: 'Refunded', hue: 'var(--primary)' },
  { value: 'exchanged', label: 'Exchanged', hue: 'var(--chart-3)' },
];

export function returnStatusStyle(value?: string | null): StatusStyle {
  return (
    RETURN_STATUSES.find((s) => s.value === value) ?? {
      value: value ?? '',
      label: value ? value.replace(/_/g, ' ') : 'No status',
      hue: '',
    }
  );
}

export const ReturnStatusField = enumField(StringField, {
  options: RETURN_STATUSES.map((s) => ({ value: s.value, label: s.label })),
  displayName: 'Return Status',
});

// Why it came back, and what the policy says about it. `restockable` and
// `restockingFeeRate` live on this table rather than in the refund code, so a
// change of returns policy is an edit to one list.
export const RETURN_REASONS = [
  {
    value: 'wrong_item',
    label: 'Wrong item received',
    restockable: true,
    feeRate: 0,
  },
  {
    value: 'damaged_shipping',
    label: 'Damaged in shipping',
    restockable: false,
    feeRate: 0,
  },
  {
    value: 'defective',
    label: 'Defective product',
    restockable: false,
    feeRate: 0,
  },
  {
    value: 'changed_mind',
    label: 'Changed mind',
    restockable: true,
    feeRate: 0.15,
  },
  {
    value: 'wrong_size',
    label: 'Wrong size or fit',
    restockable: true,
    feeRate: 0,
  },
  {
    value: 'not_as_described',
    label: 'Not as described',
    restockable: true,
    feeRate: 0,
  },
  {
    value: 'arrived_late',
    label: 'Arrived too late',
    restockable: true,
    feeRate: 0,
  },
];

export function returnReason(value?: string | null) {
  return RETURN_REASONS.find((r) => r.value === value);
}

// A fee is waived when the fault was ours. Encoding that here — rather than
// leaving it to whoever processes the return — is what makes two people
// processing the same return produce the same refund.
export function isOurFault(value?: string | null) {
  return (
    value === 'wrong_item' ||
    value === 'damaged_shipping' ||
    value === 'defective' ||
    value === 'not_as_described' ||
    value === 'arrived_late'
  );
}

export const ReturnReasonField = enumField(StringField, {
  options: RETURN_REASONS.map((r) => ({ value: r.value, label: r.label })),
  displayName: 'Return Reason',
});

export const ITEM_CONDITIONS = [
  { value: 'new', label: 'As new' },
  { value: 'good', label: 'Good' },
  { value: 'damaged', label: 'Damaged' },
  { value: 'defective', label: 'Defective' },
];

export const ItemConditionField = enumField(StringField, {
  options: ITEM_CONDITIONS,
  displayName: 'Condition',
});

// What happens to the unit now. Only `restock` puts stock back — the others all
// remove it from sellable inventory in different ways, and the difference
// matters to the numbers at the end of the month.
export const DISPOSITIONS = [
  { value: 'restock', label: 'Restock (A grade)' },
  { value: 'refurbish', label: 'Refurbish' },
  { value: 'liquidate', label: 'Liquidate' },
  { value: 'dispose', label: 'Dispose' },
  { value: 'return_to_vendor', label: 'Return to vendor' },
];

export const DispositionField = enumField(StringField, {
  options: DISPOSITIONS,
  displayName: 'Disposition',
});

export const REFUND_METHODS = [
  { value: 'original', label: 'Original payment method' },
  { value: 'store_credit', label: 'Store credit' },
  { value: 'exchange', label: 'Exchange' },
];

export const RefundMethodField = enumField(StringField, {
  options: REFUND_METHODS,
  displayName: 'Refund Method',
});

export class ReturnItemField extends FieldDef {
  static displayName = 'Return Item';

  @field sku = contains(StringField);
  @field productName = contains(StringField);
  @field quantity = contains(NumberField);
  @field unitPrice = contains(AmountWithCurrency);
  @field itemCondition = contains(ItemConditionField);
  @field disposition = contains(DispositionField);
  @field inspectionNotes = contains(StringField);

  @field lineValue = contains(AmountWithCurrency, {
    computeVia: function (this: ReturnItemField) {
      let result = new AmountWithCurrency();
      let currency = new CurrencyField();
      currency.code = this.unitPrice?.currency?.code ?? 'USD';
      result.currency = currency;
      result.amount = (this.unitPrice?.amount ?? 0) * (this.quantity ?? 0);
      return result;
    },
  });

  get returnsToStock() {
    return this.disposition === 'restock';
  }

  static embedded = class Embedded extends Component<typeof ReturnItemField> {
    <template>
      <div class='ri'>
        <span class='lead'>
          <span class='strong'>{{if
              @model.productName
              @model.productName
              'Unnamed item'
            }}
            ×
            {{if @model.quantity @model.quantity '—'}}</span>
          <span class='meta'>{{itemMeta @model}}</span>
        </span>
        {{#if @model.disposition}}
          <span
            class='st'
            data-tone={{dispositionTone @model.disposition}}
          ><span class='dot'></span>{{dispositionWord
              @model.disposition
            }}</span>
        {{/if}}
      </div>
      <style scoped>
        .ri {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          min-height: 1.75rem;
          padding: 0 var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
          font-size: var(--boxel-font-size-xs);
        }
        .lead {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .strong {
          flex: none;
          font-weight: 600;
          color: var(--foreground);
        }
        .meta {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
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
        .st[data-tone='ok'] {
          --tone: var(--success);
        }
        .dot {
          width: 0.4375rem;
          height: 0.4375rem;
          border-radius: 50%;
          background-color: var(--tone);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof ReturnItemField> {
    <template>
      <span class='ri-atom'>{{@model.quantity}}× {{@model.sku}}</span>
      <style scoped>
        .ri-atom {
          font-family: var(--font-mono);
          font-size: 0.85em;
        }
      </style>
    </template>
  };
}

// Product Return — the RMA, from request to refund.
//
// The refund is computed from the items and the policy, never typed in. Two
// people processing the same return get the same number, and the arithmetic is
// visible on the card rather than in someone's head.
export class ProductReturn extends CardDef {
  static displayName = 'Product Return';
  static icon = RotateIcon;

  @field rmaNumber = contains(StringField);
  @field order = linksTo(() => FulfilmentOrder);
  @field originalShipment = linksTo(() => Shipment);
  @field customerName = contains(StringField);

  @field status = contains(ReturnStatusField);
  @field reason = contains(ReturnReasonField);
  @field reasonDetails = contains(StringField);
  @field lineItems = containsMany(ReturnItemField);

  @field returnLabelUrl = contains(StringField);
  @field returnTrackingNumber = contains(StringField);
  @field refundMethod = contains(RefundMethodField);
  @field notes = contains(MarkdownField);

  // Event facts. Each is written once, when the thing happened; the RMA's
  // progress is a question about which of them are set.
  @field requestedAt = contains(DatetimeField);
  @field receivedAt = contains(DatetimeField);
  @field inspectedAt = contains(DatetimeField);
  @field completedAt = contains(DatetimeField);

  @field itemsValue = contains(AmountWithCurrency, {
    computeVia: function (this: ProductReturn) {
      // Lines in different currencies have no total; adding them would give
      // a figure in neither.
      if (this.mixedCurrency) {
        return undefined;
      }
      let result = new AmountWithCurrency();
      let currency = new CurrencyField();
      currency.code = this.currencyCode ?? 'USD';
      result.currency = currency;
      result.amount = (this.lineItems ?? []).reduce(
        (sum, l) => sum + (l?.unitPrice?.amount ?? 0) * (l?.quantity ?? 0),
        0,
      );
      return result;
    },
  });

  @field restockingFee = contains(AmountWithCurrency, {
    computeVia: function (this: ProductReturn) {
      let result = new AmountWithCurrency();
      let currency = new CurrencyField();
      currency.code = this.currencyCode ?? 'USD';
      result.currency = currency;
      let rate = isOurFault(this.reason)
        ? 0
        : (returnReason(this.reason)?.feeRate ?? 0);
      let items = this.itemsValue?.amount;
      if (items == null) {
        return undefined;
      }
      result.amount = Math.round(items * rate * 100) / 100;
      return result;
    },
  });

  @field refundAmount = contains(AmountWithCurrency, {
    computeVia: function (this: ProductReturn) {
      let result = new AmountWithCurrency();
      let currency = new CurrencyField();
      currency.code = this.currencyCode ?? 'USD';
      result.currency = currency;
      let items = this.itemsValue?.amount;
      if (items == null) {
        return undefined;
      }
      result.amount =
        Math.round((items - (this.restockingFee?.amount ?? 0)) * 100) / 100;
      return result;
    },
  });

  @field mixedCurrency = contains(BooleanField, {
    computeVia: function (this: ProductReturn) {
      // A line with no code is valued in USD by `lineValue`, so it counts as
      // USD here too.
      let codes = new Set(
        (this.lineItems ?? []).map(
          (l) => l?.unitPrice?.currency?.code?.trim().toUpperCase() || 'USD',
        ),
      );
      return codes.size > 1;
    },
  });

  @field currencyCode = contains(StringField, {
    computeVia: function (this: ProductReturn) {
      let line = (this.lineItems ?? []).find(
        (l) => l?.unitPrice?.currency?.code,
      );
      return line?.unitPrice?.currency?.code;
    },
  });

  @field orderNumber = contains(StringField, {
    computeVia: function (this: ProductReturn) {
      return this.order?.orderNumber;
    },
  });

  @field itemCount = contains(NumberField, {
    computeVia: function (this: ProductReturn) {
      return (this.lineItems ?? []).reduce(
        (sum, l) => sum + (l?.quantity ?? 0),
        0,
      );
    },
  });

  // The statuses that mean "this RMA is finished". Exported so a consumer
  // filters by the same list the card computes from.
  static CLOSED_STATUSES = ['refunded', 'exchanged', 'denied'];

  // Open vs closed as a FIELD, not a getter: a consumer filtering a grid through
  // a realm query cannot see a getter, so a getter here would let a grid and a
  // table disagree about which returns are open.
  @field lifecycleState = contains(StringField, {
    computeVia: function (this: ProductReturn) {
      return ProductReturn.CLOSED_STATUSES.includes(this.status ?? '')
        ? 'closed'
        : 'open';
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: ProductReturn) {
      return this.rmaNumber?.length ? this.rmaNumber : 'Untitled Return';
    },
  });

  get statusStyle() {
    return returnStatusStyle(this.status);
  }

  get reasonLabel() {
    return returnReason(this.reason)?.label ?? 'No reason given';
  }

  get feeWaived() {
    return isOurFault(this.reason);
  }

  get restockingLines() {
    return (this.lineItems ?? []).filter((l) => l?.disposition === 'restock');
  }

  get isInspected() {
    return this.inspectedAt != null;
  }

  static isolated = class Isolated extends Component<typeof ProductReturn> {
    <template>
      <article class='ret'>
        <header class='ihead'>
          <div class='who'>
            <span class='mark' aria-hidden='true'>Rt</span>
            <div class='id'>
              <h1 class='name'>{{@model.cardTitle}}</h1>
              <p class='meta'>{{metaLine @model}}</p>
            </div>
          </div>
          <div class='bar'>
            <span class='st' style={{dotStyle @model.statusStyle.hue}}><span
                class='dot'
              ></span>{{lower @model.statusStyle.label}}</span>
            <span class='st'><span
                class='dot'
              ></span>{{@model.lifecycleState}}</span>
          </div>
        </header>

        <div class='stats four'>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Refund</span>
            <span class='num'>{{amt @model.refundAmount}}</span>
            <span class='meta'>{{refundMethodLabel @model.refundMethod}}</span>
          </div>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Items</span>
            <span class='num'>{{if @model.itemCount @model.itemCount 0}}</span>
            <span class='meta'>{{itemNames @model}}</span>
          </div>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Restocking fee</span>
            <span class='num'>{{amt @model.restockingFee}}</span>
            <span class='meta'>{{if
                @model.feeWaived
                'our fault'
                'per returns policy'
              }}</span>
          </div>
          <div class='stat'>
            <span class='st cap'><span class='dot'></span>Requested</span>
            <span class='num'>{{monthDay @model.requestedAt}}</span>
            <span class='meta'>{{year @model.requestedAt}}</span>
          </div>
        </div>

        <section class='blk'>
          <h2>Reason</h2>
          <p class='row'>{{if
              @model.reasonDetails
              @model.reasonDetails
              @model.reasonLabel
            }}</p>
        </section>

        <section class='blk'>
          <h2>Items</h2>
          {{#if @model.lineItems.length}}
            <@fields.lineItems @format='embedded' />
          {{else}}
            <p class='row meta'>No items on this return</p>
          {{/if}}
        </section>

        <section class='blk'>
          <h2>Timeline</h2>
          <dl class='kv'>
            <dt class='cap'>Requested</dt>
            <dd class='mono'>{{stamp @model.requestedAt}}</dd>
            <dt class='cap'>Received</dt>
            <dd class='mono'>{{stamp @model.receivedAt}}</dd>
            <dt class='cap'>Inspected</dt>
            <dd class='mono'>{{stamp @model.inspectedAt}}</dd>
            <dt class='cap'>Completed</dt>
            <dd class='mono'>{{stamp @model.completedAt}}</dd>
          </dl>
        </section>

        <section class='blk'>
          <h2>Linked</h2>
          <dl class='kv'>
            <dt class='cap'>Order</dt>
            <dd>{{#if @model.order}}<@fields.order
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</dd>
            <dt class='cap'>Shipment</dt>
            <dd>{{#if @model.originalShipment}}<@fields.originalShipment
                  @format='atom'
                  @displayContainer={{false}}
                />{{else}}—{{/if}}</dd>
          </dl>
        </section>
      </article>

      <style scoped>
        .ret {
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
        .stats.four {
          grid-template-columns: repeat(4, minmax(0, 1fr));
        }
        .st[style] {
          --tone: var(--st-hue);
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

  static embedded = class Embedded extends Component<typeof ProductReturn> {
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>Rt</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine @model}}</p>
          </div>
          <span class='st' style={{dotStyle @model.statusStyle.hue}}><span
              class='dot'
            ></span>{{lower @model.statusStyle.label}}</span>
        </header>
        <dl class='kv'>
          <dt>Refund</dt>
          <dd class='mono'>{{amt @model.refundAmount}}</dd>
          <dt>Items value</dt>
          <dd class='mono'>{{amt @model.itemsValue}}</dd>
          <dt>Restocking fee</dt>
          <dd class='mono'>{{amt @model.restockingFee}}</dd>
          <dt>Items</dt>
          <dd class='mono'>{{if @model.itemCount @model.itemCount 0}}</dd>
          <dt>Return tracking</dt>
          <dd class='mono'>{{dash @model.returnTrackingNumber}}</dd>
          <dt>Received</dt>
          <dd>{{day @model.receivedAt}}</dd>
          <dt>Order</dt>
          <dd>{{#if @model.order}}<@fields.order
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</dd>
          <dt>Shipment</dt>
          <dd>{{#if @model.originalShipment}}<@fields.originalShipment
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
        .st[style] {
          --tone: var(--st-hue);
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

  static atom = class Atom extends Component<typeof ProductReturn> {
    <template><CompoundAtom @mark='Rt' @name={{@model.cardTitle}} /></template>
  };

  static fitted = class Fitted extends Component<typeof ProductReturn> {
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>Rt</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><span
            class='st'
            style={{dotStyle @model.statusStyle.hue}}
          ><span class='dot'></span><span class='st-text'>{{lower
                @model.statusStyle.label
              }}</span></span></:status>
        <:fact>{{amt @model.refundAmount}}
          refund ·
          {{if @model.itemCount @model.itemCount 0}}
          items</:fact>
        <:relations>{{#if @model.order}}<@fields.order
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
      <style scoped>
        .st[style] {
          --tone: var(--st-hue);
        }
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

function dotStyle(hue: string | undefined) {
  return htmlSafe(`--st-hue: ${hue || 'var(--muted-foreground)'}`);
}

function dash(v: unknown) {
  return v == null || v === '' ? '—' : String(v);
}

function lower(s: string | undefined) {
  return s ? s.toLowerCase() : '—';
}

function amt(a: AmountWithCurrency | undefined) {
  return a?.amount == null ? '—' : money(a.amount, a.currency?.code ?? 'USD');
}

function metaLine(m: Partial<ProductReturn>) {
  return [m?.customerName, m?.reasonLabel].filter(Boolean).join(' · ') || '—';
}

function refundMethodLabel(v: string | undefined) {
  return (
    REFUND_METHODS.find((r) => r.value === v)?.label.toLowerCase() ??
    'no refund method'
  );
}

function itemNames(m: Partial<ProductReturn>) {
  return (
    (m?.lineItems ?? [])
      .map((l) => l?.productName)
      .filter(Boolean)
      .join(', ') || '—'
  );
}

function itemMeta(l: Partial<ReturnItemField>) {
  let value =
    l?.lineValue?.amount != null
      ? money(l.lineValue.amount, l.lineValue.currency?.code ?? 'USD')
      : undefined;
  return [l?.sku, value, l?.inspectionNotes].filter(Boolean).join(' · ') || '—';
}

function dispositionTone(v: string | undefined) {
  return v === 'restock' ? 'ok' : v === 'dispose' ? 'bad' : undefined;
}

function dispositionWord(v: string | undefined) {
  return v ? v.replace(/_/g, ' ') : '—';
}

function asDate(d: Date | string | null | undefined) {
  if (!d) return undefined;
  let date = d instanceof Date ? d : new Date(d);
  return isNaN(date.getTime()) ? undefined : date;
}

function monthDay(d: Date | undefined) {
  return (
    asDate(d)?.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    }) ?? '—'
  );
}

function year(d: Date | undefined) {
  return asDate(d)?.getFullYear().toString() ?? '';
}

function day(d: Date | undefined) {
  return (
    asDate(d)?.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    }) ?? '—'
  );
}

function stamp(d: Date | undefined) {
  let date = asDate(d);
  if (!date) return '—';
  let time = date.toLocaleTimeString('en-GB', {
    hour: '2-digit',
    minute: '2-digit',
  });
  return `${day(date)}, ${time}`;
}

export default ProductReturn;
