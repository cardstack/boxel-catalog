// "Dana Oyelaran" → "DO": the two-letter mark atoms and record heads show.
export function initials(name?: string | null): string {
  let parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  return (
    (
      (parts[0]?.[0] ?? '') +
      (parts.length > 1 ? parts[parts.length - 1]![0] : '')
    ).toUpperCase() || '?'
  );
}
