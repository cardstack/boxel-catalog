import { Component, StringField } from 'https://cardstack.com/base/card-api';
import enumField from 'https://cardstack.com/base/enum';
import ClipboardListIcon from '@cardstack/boxel-icons/clipboard-list';
import StatusChip, { type StatusStyle } from './fulfilment-status-chip';

// Order Status (OS) — the order's lifecycle, and the colour language that goes
// with it. The hues are exported from the same module that owns the enum so a
// board, a pill and an app all read one source instead of three copies.
//
// Hues are theme tokens (status tokens for meaning, chart tokens for plain
// lifecycle steps), so a linked theme recolours them in light and dark.
export const ORDER_STATUSES: StatusStyle[] = [
  { value: 'pending', label: 'Pending', hue: 'var(--chart-4)' },
  { value: 'processing', label: 'Processing', hue: 'var(--warning)' },
  {
    value: 'awaiting_stock',
    label: 'Awaiting Stock',
    hue: 'var(--destructive)',
  },
  { value: 'on_hold', label: 'On Hold', hue: 'var(--muted-foreground)' },
  { value: 'picking', label: 'Picking', hue: 'var(--attention)' },
  { value: 'packing', label: 'Packing', hue: 'var(--chart-1)' },
  { value: 'shipped', label: 'Shipped', hue: 'var(--chart-2)' },
  { value: 'delivered', label: 'Delivered', hue: 'var(--success)' },
  { value: 'cancelled', label: 'Cancelled', hue: 'var(--muted-foreground)' },
  { value: 'returned', label: 'Returned', hue: 'var(--chart-5)' },
];

// The stages an order passes through on the happy path, in order. Anything not
// listed here (on hold, cancelled, returned) is an exit, not a stage — which is
// why progress is measured against this list and not against ORDER_STATUSES.
export const ORDER_PIPELINE = [
  'pending',
  'processing',
  'picking',
  'packing',
  'shipped',
  'delivered',
];

export function orderStatusStyle(value?: string | null): StatusStyle {
  return (
    ORDER_STATUSES.find((s) => s.value === value) ?? {
      value: value ?? '',
      label: value ? value.replace(/_/g, ' ') : 'No status',
      hue: '',
    }
  );
}

// How far along the happy path this order is, 0–1. An order that has left the
// path (cancelled, on hold) reports 0 rather than a misleading fraction.
export function orderProgress(value?: string | null): number {
  let i = ORDER_PIPELINE.indexOf(value ?? '');
  if (i < 0) {
    return 0;
  }
  return (i + 1) / ORDER_PIPELINE.length;
}

const OrderStatusEnum = enumField(StringField, {
  options: ORDER_STATUSES.map((s) => ({ value: s.value, label: s.label })),
  displayName: 'Order Status',
  icon: ClipboardListIcon,
});

export class OrderStatusField extends OrderStatusEnum {
  static displayName = 'Order Status';
  static icon = ClipboardListIcon;

  static atom = class Atom extends Component<typeof OrderStatusField> {
    get style() {
      return orderStatusStyle(this.args.model as unknown as string);
    }
    <template>
      <StatusChip @label={{this.style.label}} @hue={{this.style.hue}} />
    </template>
  };

  static embedded = class Embedded extends Component<typeof OrderStatusField> {
    get style() {
      return orderStatusStyle(this.args.model as unknown as string);
    }
    <template>
      <StatusChip
        @label={{this.style.label}}
        @hue={{this.style.hue}}
        @size='base'
      />
    </template>
  };
}

export default OrderStatusField;
