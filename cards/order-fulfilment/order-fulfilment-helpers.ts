import type { CardDef } from '@cardstack/base/card-api';
import { identifyCard } from '@cardstack/runtime-common';
import { htmlSafe } from '@ember/template';
import { orderStatusStyle } from '../fulfilment/order-status';
import type { BoardColumn } from '../../components/board';
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
  { key: 'board', label: 'Board' },
  { key: 'inventory', label: 'Inventory' },
  { key: 'ship', label: 'Ship desk' },
  { key: 'transit', label: 'In transit' },
  { key: 'returns', label: 'Returns' },
];

// A tracker-per-row list is expensive to draw, so the transit tab pages rather
// than rendering every shipment a realm holds.
export const TRANSIT_PAGE = 12;

export function pct(value: number | undefined) {
  return htmlSafe(`width: ${Math.min(100, Math.max(0, value ?? 0))}%`);
}

// Three views, same ids on every collection in the card. grid and list are two
// cell shapes over ONE renderer (the base realm's CardList, which draws
// prerendered fitted); only `table` is a different layer, rendering individual
// fields. `list` maps to CardList's own vocabulary word, `strip`.
//
// boxel-ui also offers a `card` option; it is deliberately NOT shipped here,
// because it renders the embedded template into a row envelope and clips.
export const VIEW_OPTIONS = [
  { value: 'grid', label: 'Grid' },
  { value: 'list', label: 'List' },
  { value: 'table', label: 'Table' },
];

// Our switcher id → CardList's `@viewOption` vocabulary.
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
  return htmlSafe(`--row-hue: ${value ?? 'var(--muted-foreground)'}`);
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
