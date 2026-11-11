import type { CardDef } from '@cardstack/base/card-api';
import { identifyCard } from '@cardstack/runtime-common';
import { htmlSafe } from '@ember/template';
import { orderStatusStyle } from '../fulfilment/order-status';
import { SHIPMENT_PIPELINE } from '../fulfilment/shipment-status';
import type { BoardColumn } from '@cardstack/catalog/components/board';
import type { FulfilmentOrder } from '../fulfilment/fulfilment-order';
import type { InventoryStock } from '../fulfilment/inventory-stock';
import type { ProductReturn } from '../fulfilment/product-return';

// The app declares the domain; the blocks stay neutral. These columns are the
// fulfilment pipeline — the board block itself has no idea what "packing"
// means, which is what lets the same block run a returns board or a purchase
// order board without a fork.
export const BOARD_COLUMNS: BoardColumn[] = [
  'pending',
  'processing',
  'picking',
  'packing',
  'shipped',
]
  .map((value) => orderStatusStyle(value))
  .map((s) => ({ key: s.value, label: s.label, color: s.hue }));

export const TABS = [
  {
    key: 'board',
    label: 'Board',
    sub: 'Drag an order to move it along the pipeline.',
  },
  {
    key: 'inventory',
    label: 'Inventory',
    sub: 'Stock rows across every warehouse.',
  },
  {
    key: 'ship',
    label: 'Ship desk',
    sub: 'Packed orders become parcels, then get a rate and a carrier.',
  },
  {
    key: 'transit',
    label: 'In transit',
    sub: 'Every shipment on the road, delivered, or needing attention.',
  },
  { key: 'returns', label: 'Returns', sub: 'Returns from request to refund.' },
];

// LayoutControl forms, richest first; minWidth in rem.
const forms = (...list: [string, number][]) =>
  list.map(([name, minWidth]) => ({ name, minWidth }));
export const SEARCH_FORMS = forms(['field', 14], ['menu', 0]);
export const CHIP_FORMS = forms(['chips', 16], ['menu', 0]);
export const VIEW_FORMS = forms(['segments', 12], ['menu', 0]);
export const ADD_FORMS = forms(['label', 7], ['icon', 2]);

// A tracker-per-row list is expensive to draw, so the transit tab pages rather
// than rendering every shipment a realm holds.
export const TRANSIT_PAGE = 12;

// Three views over one collection. grid and list are cell shapes over the
// base realm's CardList; table renders individual fields.
export const VIEW_OPTIONS = [
  { value: 'grid', label: 'Grid' },
  { value: 'list', label: 'List' },
  { value: 'table', label: 'Table' },
];

// The view value mapped to CardList's `@viewOption` name.
export const VIEW_OPTION: Record<string, string> = {
  list: 'strip',
  grid: 'grid',
};

export function byType(klass: typeof CardDef) {
  let ref = identifyCard(klass);
  return ref ? { filter: { type: ref } } : undefined;
}

export function eq(a: unknown, b: unknown) {
  return a === b;
}

export function lt(a: number | undefined, b: number) {
  return (a ?? 0) < b;
}

export function hue(value: string | undefined) {
  return htmlSafe(`--dot: ${value || 'var(--muted-foreground)'}`);
}

export function stockHue(row: InventoryStock) {
  return hue(
    row.isOutOfStock
      ? 'var(--destructive)'
      : row.isLowStock
        ? 'var(--warning)'
        : undefined,
  );
}

// Share of the shipment pipeline a parcel has covered, for the progress bar.
export function shipmentProgress(status: string | undefined) {
  let at = SHIPMENT_PIPELINE.indexOf(status ?? '');
  return at < 0 ? 0 : ((at + 1) / SHIPMENT_PIPELINE.length) * 100;
}

export function plural(count: number | undefined, word: string) {
  let n = count ?? 0;
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

export function chipOptions(
  badges: { id: string; label: string; count: number }[],
) {
  return badges.map((b) => ({ value: b.id, label: b.label, count: b.count }));
}

// Collection blocks hand rows back as CardDef; these name the concrete card.
export const asOrder = (card: CardDef) => card as FulfilmentOrder;
export const asStock = (card: CardDef) => card as InventoryStock;
export const asReturn = (card: CardDef) => card as ProductReturn;

export function isNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}
