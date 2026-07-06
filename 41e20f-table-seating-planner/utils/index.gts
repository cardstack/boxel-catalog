interface Option {
  value: string;
  label: string;
}

export const TABLE_SHAPES: Option[] = [
  { value: 'round', label: 'Round' },
  { value: 'oval', label: 'Oval' },
  { value: 'rect', label: 'Rectangle' },
  { value: 'square', label: 'Square' },
  { value: 'curved', label: 'Curved' },
  { value: 'section', label: 'Seating' },
  { value: 'seat', label: 'Seat' },
];

export const SEATING_STYLES: Option[] = [
  { value: 'around', label: 'Around' },
  { value: 'opposite', label: 'Opposite' },
  { value: 'top', label: 'Top' },
  { value: 'bottom', label: 'Bottom' },
  { value: 'left', label: 'Left' },
  { value: 'right', label: 'Right' },
];

export const FIXTURE_KINDS: Option[] = [
  { value: 'plant', label: 'Plant' },
  { value: 'tree', label: 'Tree' },
  { value: 'balloon', label: 'Balloon arch' },
  { value: 'stage', label: 'Stage' },
  { value: 'projector', label: 'Projector' },
  { value: 'red-carpet', label: 'Red carpet' },
  { value: 'dance-floor', label: 'Dance floor' },
  { value: 'arch', label: 'Ceremony arch' },
  { value: 'cake', label: 'Cake table' },
  { value: 'bar', label: 'Bar' },
  { value: 'curved-wall', label: 'Curved wall' },
  { value: 'rect-decor', label: 'Rectangle' },
  { value: 'round-decor', label: 'Circle' },
];

export const FOCAL_FIXTURE_KINDS = ['stage', 'arch', 'red-carpet'];

export const FIXTURE_PATTERNS: Option[] = [
  { value: 'solid', label: 'Solid' },
  { value: 'outline', label: 'Outline' },
  { value: 'soft', label: 'Soft' },
];

interface GuestCategory extends Option {
  color: string;
}

export const GUEST_CATEGORIES: GuestCategory[] = [
  { value: 'brides-family', label: "Bride's Family", color: '#e8879c' },
  { value: 'grooms-family', label: "Groom's Family", color: '#e3b968' },
  { value: 'close-friend', label: 'Close Friend', color: '#74b18d' },
  { value: 'friends', label: 'Friends', color: '#93c7a4' },
  { value: 'college', label: 'College', color: '#b79bd4' },
  { value: 'colleagues', label: 'Colleagues', color: '#9cabde' },
  { value: 'others', label: 'Others', color: '#a89a92' },
];

const GUEST_CATEGORY_MAP: Record<string, GuestCategory> = Object.fromEntries(
  GUEST_CATEGORIES.map((c) => [c.value, c]),
);

export function categoryLabel(value: string | null | undefined): string {
  return (value && GUEST_CATEGORY_MAP[value]?.label) || '';
}

export function categoryColor(value: string | null | undefined): string {
  return (value && GUEST_CATEGORY_MAP[value]?.color) || '#c5a35c';
}

export const TABLE_SHAPE_LABELS: Record<string, string> = Object.fromEntries(
  TABLE_SHAPES.map((o) => [o.value, o.label]),
);
export const SEATING_STYLE_LABELS: Record<string, string> = Object.fromEntries(
  SEATING_STYLES.map((o) => [o.value, o.label]),
);
export const FIXTURE_KIND_LABELS: Record<string, string> = Object.fromEntries(
  FIXTURE_KINDS.map((o) => [o.value, o.label]),
);

const FIXTURE_GOLD = '#c5a35c';

export const FIXTURE_DEFAULTS: Record<
  string,
  { width: number; height: number; color: string }
> = {
  plant: { width: 70, height: 70, color: FIXTURE_GOLD },
  tree: { width: 110, height: 110, color: FIXTURE_GOLD },
  balloon: { width: 220, height: 90, color: FIXTURE_GOLD },
  stage: { width: 260, height: 140, color: FIXTURE_GOLD },
  projector: { width: 80, height: 90, color: FIXTURE_GOLD },
  'red-carpet': { width: 80, height: 300, color: FIXTURE_GOLD },
  'dance-floor': { width: 240, height: 240, color: FIXTURE_GOLD },
  arch: { width: 160, height: 120, color: FIXTURE_GOLD },
  cake: { width: 90, height: 90, color: FIXTURE_GOLD },
  bar: { width: 240, height: 80, color: FIXTURE_GOLD },
  'curved-wall': { width: 180, height: 180, color: FIXTURE_GOLD },
  'rect-decor': { width: 160, height: 100, color: FIXTURE_GOLD },
  'round-decor': { width: 120, height: 120, color: FIXTURE_GOLD },
};

export function initialsOf(name: string | null | undefined): string {
  if (!name) return '·';
  let parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '·';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

export function shortTableLabel(name: string | null | undefined): string {
  if (!name) return 'T';
  let m = name.match(/(\d+)\s*$/);
  if (m) return m[1];
  return name.trim().slice(0, 2);
}

export interface SeatPoint {
  x: number; // 0..1 fraction of the table box width
  y: number; // 0..1 fraction of the table box height
}

export type SeatOrder =
  | 'lr-tb' // rows, left→right, top→bottom (reading order — default)
  | 'rl-tb' // rows, right→left, top→bottom
  | 'lr-bt' // rows, left→right, bottom→top (front row = bottom)
  | 'snake' // rows, zig-zag (L→R then R→L), top→bottom
  | 'col-lr' // columns, top→bottom, left→right
  | 'col-rl'; // columns, top→bottom, right→left

export const SEAT_ORDERS: { value: SeatOrder; label: string }[] = [
  { value: 'lr-tb', label: 'Across rows →' },
  { value: 'rl-tb', label: 'Across rows ←' },
  { value: 'lr-bt', label: 'Rows, bottom-up' },
  { value: 'snake', label: 'Snake ⇄' },
  { value: 'col-lr', label: 'Down cols ↓ (L→R)' },
  { value: 'col-rl', label: 'Down cols ↓ (R→L)' },
];

export function sectionSeatPoints(
  rows: number,
  cols: number,
  order: SeatOrder = 'lr-tb',
): SeatPoint[] {
  let R = Math.max(1, Math.floor(rows || 0));
  let C = Math.max(1, Math.floor(cols || 0));
  let lo = 0.5 / C;
  let along = (k: number, n: number) =>
    n === 1 ? 0.5 : lo + (k / (n - 1)) * (1 - 2 * lo);
  let X = (c: number) => along(c, C);
  let Y = (r: number) =>
    R === 1 ? 0.5 : 0.5 / R + (r / (R - 1)) * (1 - 1 / R);
  let pts: SeatPoint[] = [];
  let push = (r: number, c: number) => pts.push({ x: X(c), y: Y(r) });
  switch (order) {
    case 'rl-tb':
      for (let r = 0; r < R; r++) for (let c = C - 1; c >= 0; c--) push(r, c);
      break;
    case 'lr-bt':
      for (let r = R - 1; r >= 0; r--) for (let c = 0; c < C; c++) push(r, c);
      break;
    case 'snake':
      for (let r = 0; r < R; r++) {
        if (r % 2 === 0) for (let c = 0; c < C; c++) push(r, c);
        else for (let c = C - 1; c >= 0; c--) push(r, c);
      }
      break;
    case 'col-lr':
      for (let c = 0; c < C; c++) for (let r = 0; r < R; r++) push(r, c);
      break;
    case 'col-rl':
      for (let c = C - 1; c >= 0; c--) for (let r = 0; r < R; r++) push(r, c);
      break;
    case 'lr-tb':
    default:
      for (let r = 0; r < R; r++) for (let c = 0; c < C; c++) push(r, c);
  }
  return pts;
}

export function sectionSize(
  rows: number,
  cols: number,
): { w: number; h: number } {
  const SEAT = 34;
  let R = Math.max(1, Math.floor(rows || 0));
  let C = Math.max(1, Math.floor(cols || 0));
  return { w: Math.max(80, C * SEAT), h: Math.max(60, R * SEAT) };
}

export function seatPoints(
  shape: string,
  style: string,
  count: number,
): SeatPoint[] {
  let n = Math.max(0, Math.floor(count));
  if (n === 0) return [];
  let pts: SeatPoint[] = [];

  if (shape === 'seat') return [{ x: 0.5, y: 0.5 }];

  if (shape === 'round') {
    for (let i = 0; i < n; i++) {
      let a = (i / n) * Math.PI * 2 - Math.PI / 2;
      pts.push({
        x: 0.5 + Math.cos(a) * 0.5,
        y: 0.5 + Math.sin(a) * 0.5,
      });
    }
    return pts;
  }

  if (shape === 'square') {
    let perSide = [0, 0, 0, 0]; // top, right, bottom, left
    for (let i = 0; i < n; i++) perSide[i % 4]++;
    let lo = 0.12;
    let hi = 0.88;
    let along = (k: number, total: number) =>
      lo + ((k + 1) / (total + 1)) * (hi - lo);
    let edges: ('top' | 'right' | 'bottom' | 'left')[] = [
      'top',
      'right',
      'bottom',
      'left',
    ];
    for (let e = 0; e < 4; e++) {
      let total = perSide[e];
      for (let k = 0; k < total; k++) {
        let t = along(k, total);
        if (edges[e] === 'top') pts.push({ x: t, y: -0.02 });
        else if (edges[e] === 'right') pts.push({ x: 1.02, y: t });
        else if (edges[e] === 'bottom') pts.push({ x: t, y: 1.02 });
        else pts.push({ x: -0.02, y: t });
      }
    }
    return pts;
  }

  if (shape === 'curved') {
    let cy = 0.785;
    let r = 0.57;
    for (let i = 0; i < n; i++) {
      let f = n === 1 ? 0.5 : i / (n - 1);
      let ang = 0.92 * Math.PI - 0.84 * Math.PI * f; // ~0.92π … 0.08π
      pts.push({ x: 0.5 + r * Math.cos(ang), y: cy - r * Math.sin(ang) });
    }
    return pts;
  }

  if (style === 'one-side' || style === 'top') {
    for (let i = 0; i < n; i++) {
      let t = n === 1 ? 0.5 : i / (n - 1);
      pts.push({ x: 0.08 + t * 0.84, y: -0.02 });
    }
    return pts;
  }
  if (style === 'bottom') {
    for (let i = 0; i < n; i++) {
      let t = n === 1 ? 0.5 : i / (n - 1);
      pts.push({ x: 0.08 + t * 0.84, y: 1.02 });
    }
    return pts;
  }
  if (style === 'left') {
    for (let i = 0; i < n; i++) {
      let t = n === 1 ? 0.5 : i / (n - 1);
      pts.push({ x: -0.02, y: 0.08 + t * 0.84 });
    }
    return pts;
  }
  if (style === 'right') {
    for (let i = 0; i < n; i++) {
      let t = n === 1 ? 0.5 : i / (n - 1);
      pts.push({ x: 1.02, y: 0.08 + t * 0.84 });
    }
    return pts;
  }

  if (style === 'opposite') {
    let top = Math.ceil(n / 2);
    let bottom = n - top;
    for (let i = 0; i < top; i++) {
      let t = top === 1 ? 0.5 : i / (top - 1);
      pts.push({ x: 0.08 + t * 0.84, y: -0.02 });
    }
    for (let i = 0; i < bottom; i++) {
      let t = bottom === 1 ? 0.5 : i / (bottom - 1);
      pts.push({ x: 0.08 + t * 0.84, y: 1.02 });
    }
    return pts;
  }

  if (shape === 'oval') {
    for (let i = 0; i < n; i++) {
      let a = (i / n) * Math.PI * 2 - Math.PI / 2;
      pts.push({ x: 0.5 + Math.cos(a) * 0.5, y: 0.5 + Math.sin(a) * 0.5 });
    }
    return pts;
  }

  let top = Math.min(n, Math.ceil(n * 0.36));
  let bottom = Math.min(n - top, Math.ceil(n * 0.36));
  let sides = n - top - bottom;
  let right = Math.ceil(sides / 2);
  let left = sides - right;
  let push = (
    edge: 'top' | 'bottom' | 'left' | 'right',
    k: number,
    total: number,
  ) => {
    let t = total === 1 ? 0.5 : k / (total - 1);
    if (edge === 'top') pts.push({ x: 0.08 + t * 0.84, y: -0.02 });
    else if (edge === 'bottom') pts.push({ x: 0.08 + t * 0.84, y: 1.02 });
    else if (edge === 'left') pts.push({ x: -0.02, y: 0.18 + t * 0.64 });
    else pts.push({ x: 1.02, y: 0.18 + t * 0.64 });
  };
  for (let i = 0; i < top; i++) push('top', i, top);
  for (let i = 0; i < right; i++) push('right', i, right);
  for (let i = 0; i < bottom; i++) push('bottom', i, bottom);
  for (let i = 0; i < left; i++) push('left', i, left);
  return pts;
}
