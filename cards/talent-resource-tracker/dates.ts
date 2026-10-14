// Whole calendar days from `from` to `to` (today when omitted), never negative.
// Date-only values are read as local days, so the count doesn't shift by the
// viewer's UTC offset.
function toLocalDay(value: Date | string): Date {
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    let [y, m, d] = value.split("-").map(Number);
    return new Date(y, m - 1, d);
  }
  let date = new Date(value);
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

export function daysBetween(
  from?: Date | string | null,
  to?: Date | string | null,
): number | undefined {
  if (!from) {
    return undefined;
  }
  let start = toLocalDay(from);
  let end = toLocalDay(to ?? new Date());
  if (isNaN(start.getTime()) || isNaN(end.getTime())) {
    return undefined;
  }
  return Math.max(0, Math.round((end.getTime() - start.getTime()) / 86400000));
}
