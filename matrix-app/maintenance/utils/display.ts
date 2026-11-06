// Cards usually title through a computed `cardTitle`; base `title` is often
// unset. One fallback chain, used by every command message and row label.
export function displayTitle(card: any, fallback = 'untitled'): string {
  return (card?.cardTitle as string) || (card?.title as string) || fallback;
}

// A collection's search box: lowercase the query, join the given fields into
// one haystack, substring-match.
export function matchesSearch(
  query: string,
  ...fields: (string | null | undefined)[]
): boolean {
  let q = query.trim().toLowerCase();
  if (!q) return true;
  return fields
    .map((f) => f ?? '')
    .join(' ')
    .toLowerCase()
    .includes(q);
}
