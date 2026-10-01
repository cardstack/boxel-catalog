// Canvas geometry for the dashboard wall. Tile rects are stored in px in the
// dashboard's layoutJson (they are model data, not styling) and always snap
// to a 16px grid.

export const RESIZE_DIRS = ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw'];

export interface TileRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

// resize/data controls only make sense on our own ChartCards; any other
// linked card is just rendered
export function isChart(card: any): boolean {
  return typeof card?.chartKind === 'string';
}

export const GRID = 16;
export const MIN_TILE_W = 240;
export const MIN_TILE_H = 180;

export function snap(value: number): number {
  return Math.round(value / GRID) * GRID;
}

// unplaced card (e.g. the AI just linked one): flow into a 2-per-row default
export function defaultRect(index: number): TileRect {
  return {
    x: GRID + (index % 2) * 452,
    y: GRID + Math.floor(index / 2) * 356,
    w: 436,
    h: 340,
  };
}
