// The shared filter verb: predicate builders every list view composes
// instead of re-deriving. A filter never throws on a hole — an unloaded
// link or empty field simply doesn't match, it doesn't crash the list.

export type Predicate<T> = (item: T) => boolean;

// One string identity for matching, the same one `compareValues` sorts with
// (`sensitivity: 'base'`): case and accents both fold away.
function fold(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLocaleLowerCase();
}

/**
 * Case- and accent-insensitive "does any of these fields mention this?".
 * A needle of "cafe" matches "café". An empty needle passes everything through.
 */
export function textMatch<T>(
  needle: string | null | undefined,
  ...accessors: ((item: T) => unknown)[]
): Predicate<T> {
  let query = fold((needle ?? '').trim());
  if (!query) {
    return () => true;
  }
  return (item: T) =>
    accessors.some((accessor) => {
      let value = accessor(item);
      return (
        value !== null &&
        value !== undefined &&
        fold(String(value)).includes(query)
      );
    });
}

/**
 * Chip or facet filter: keep the items whose accessor yields one of `allowed`.
 * An empty selection passes everything through.
 *
 * Membership is by value, so the accessor must yield a primitive key — an id or
 * a name, not a linked card or a Date, which compare by reference and would
 * match nothing. For a `linksToMany` facet, read the key: `(t) => t.tag?.id`.
 */
export function oneOf<T>(
  allowed: readonly unknown[] | null | undefined,
  accessor: (item: T) => unknown,
): Predicate<T> {
  if (!allowed?.length) {
    return () => true;
  }
  let set = new Set(allowed);
  return (item: T) => set.has(accessor(item));
}

/**
 * Inclusive range on numbers or dates; either bound may be open.
 *
 * A range is a claim that the field has a value, so an item whose accessor
 * yields null or undefined is excluded even when both bounds are open. That is
 * deliberately unlike `textMatch` and `oneOf`, where an empty input passes
 * everything through.
 */
export function withinRange<T>(
  min: number | Date | null | undefined,
  max: number | Date | null | undefined,
  accessor: (item: T) => number | Date | null | undefined,
): Predicate<T> {
  let lo = min instanceof Date ? min.getTime() : min;
  let hi = max instanceof Date ? max.getTime() : max;
  return (item: T) => {
    let raw = accessor(item);
    if (raw === null || raw === undefined) {
      return false;
    }
    let value = raw instanceof Date ? raw.getTime() : raw;
    if (lo !== null && lo !== undefined && value < lo) return false;
    if (hi !== null && hi !== undefined && value > hi) return false;
    return true;
  };
}

/** AND-compose predicates, skipping holes in the item list. */
export default function filterBy<T>(
  items: readonly (T | null | undefined)[],
  ...predicates: Predicate<T>[]
): T[] {
  // `!= null`, not `filter(Boolean)`: the hole this skips is an unloaded
  // link, and Boolean would also drop 0, '' and false — silently losing
  // rows from any list of numbers or ids.
  let present = (items ?? []).filter((x) => x != null) as T[];
  return present.filter((item) => predicates.every((p) => p(item)));
}
