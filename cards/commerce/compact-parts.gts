// Helpers the commerce, crm and procurement fitted views share.

export interface CompactTag {
  label: string;
  tone?: 'neutral' | 'primary' | 'info' | 'success' | 'warning' | 'danger';
}

// A defined value for args typed without undefined; Pret UI renders '' as its empty placeholder.
export function orEmpty<T>(x: T | null | undefined): T | '' {
  return x ?? '';
}

export function fmtDate(d?: Date | string | null, year = true): string {
  if (!d) return '';
  let date = d instanceof Date ? d : new Date(d);
  if (Number.isNaN(date.getTime())) return '';
  return new Intl.DateTimeFormat('en-US', {
    month: 'short',
    day: 'numeric',
    year: year ? 'numeric' : undefined,
    timeZone: 'UTC',
  }).format(date);
}
