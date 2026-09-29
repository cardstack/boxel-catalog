/** Whole days from `from` to `to` (default now); undefined when `from` is missing or unparseable. */
export function daysBetween(
  from?: Date | string | null,
  to?: Date | string | null,
): number | undefined {
  if (!from) {
    return undefined;
  }
  let start = new Date(from);
  let end = to ? new Date(to) : new Date();
  if (isNaN(start.getTime()) || isNaN(end.getTime())) {
    return undefined;
  }
  return Math.max(0, Math.round((end.getTime() - start.getTime()) / 86400000));
}

/**
 * How many of a linksToMany's entries are present. Deleting a card does not
 * rewrite the cards linking to it, so the dead reference survives: the slot
 * stays in the array, `length` is unchanged, and the entry reads as
 * `undefined`. Counting raw `.length` therefore reports members or skills
 * that are visibly no longer there.
 */
export function liveCount(links: unknown[] | null | undefined): number {
  return (links ?? []).filter(Boolean).length;
}

/** `$1,234` or, with `compact`, `$1k` — compact only kicks in at 1,000 so an hourly rate never collapses to `$0k`. */
export function formatMoney(
  n?: number | null,
  opts?: { compact?: boolean },
): string | undefined {
  if (n == null) {
    return undefined;
  }
  if (opts?.compact && Math.abs(n) >= 1000) {
    return `$${Math.round(n / 1000)}k`;
  }
  return `$${n.toLocaleString()}`;
}
