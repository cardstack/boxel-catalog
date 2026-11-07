export {
  WO_STATUS_LABEL,
  ASSET_STATUS_LABEL,
  dot,
  woDot,
  assetDot,
  woLabel,
  assetLabel,
} from '../maintenance/components/status-dot';
import { mintIdentifier } from '@cardstack/catalog/fields/record-identifier/record-identifier-field';

export const SEQ_SLOT = /\{seq\d\}/;
export const MS_PER_DAY = 86_400_000;
export const HORIZON_DAYS = 14;

// LayoutControl forms, richest first; minWidth in rem.
const forms = (...list: [string, number][]) =>
  list.map(([name, minWidth]) => ({ name, minWidth }));
export const SEARCH_FORMS = forms(['field', 14], ['menu', 0]);
export const CHIP_FORMS = forms(['chips', 16], ['menu', 0]);
export const VIEW_FORMS = forms(['segments', 12], ['menu', 0]);
export const ADD_FORMS = forms(['label', 7], ['icon', 2]);

export function eq(a: unknown, b: unknown) {
  return a === b;
}

export function startOfDay(d: Date | string | number): number {
  let x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x.getTime();
}

export function daysOut(
  d: Date | string | null | undefined,
): number | undefined {
  if (!d) return undefined;
  return Math.round((startOfDay(d) - startOfDay(new Date())) / MS_PER_DAY);
}

const SHORT_DAY = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
});

// "3d late", "Today", "Oct 24": the due cell of a work order row.
export function dueText(d: Date | string | null | undefined): string {
  let n = daysOut(d);
  if (n == null) return '—';
  if (n < 0) return `${-n}d late`;
  if (n === 0) return 'Today';
  return SHORT_DAY.format(new Date(d!));
}

export function money(amount: number | null | undefined, currency = 'USD') {
  if (amount == null) return '—';
  try {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency,
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return String(amount);
  }
}

/**
 * The next identifier for a pattern: minted from the counter after `counter`,
 * skipping any value already in `taken`. `taken` holds the identifiers the
 * realm already carries, so a counter that fell behind (an edit, a second
 * desk) never re-issues one; the desk's own counter covers records too new to
 * be indexed yet.
 */
export function nextIdentifier(
  pattern: string | undefined,
  counter: number | undefined,
  taken: Iterable<string | undefined | null>,
  now: Date = new Date(),
): { value: string; seq: number } | undefined {
  // Without a sequence slot every mint is the same string.
  if (!SEQ_SLOT.test(pattern ?? '')) return undefined;
  let used = new Set<string>();
  for (let value of taken) {
    if (value) used.add(value);
  }
  let seq = Math.max(0, Math.floor(counter ?? 0)) + 1;
  // With N values taken, one of N + 1 candidates is free.
  for (let i = 0; i <= used.size; i++, seq++) {
    let value = mintIdentifier(pattern, seq, now);
    if (!used.has(value)) return { value, seq };
  }
  return undefined;
}
