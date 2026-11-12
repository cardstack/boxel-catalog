// The one set of tone, date and money helpers the contract-execution app and
// the compact legal/audit cards share. Pret UI's tone names, so a tone passes
// straight to a Pret UI component.

export type Tone = 'success' | 'info' | 'warning' | 'danger' | 'neutral';

/** low → green, medium → orange, high and critical → red. */
export function riskTone(level?: string | null): Tone {
  return level === 'low'
    ? 'success'
    : level === 'medium'
      ? 'warning'
      : level === 'high' || level === 'critical'
        ? 'danger'
        : 'neutral';
}

/** The shared legal modules speak in hues; the cards draw tones. */
export function hueTone(hue?: string | null): Tone {
  switch (hue) {
    case 'red':
      return 'danger';
    case 'orange':
    case 'amber':
      return 'warning';
    case 'green':
      return 'success';
    case 'blue':
      return 'info';
    default:
      return 'neutral';
  }
}

export function dash(v?: string | null): string {
  return v && String(v).trim().length ? String(v) : '—';
}

/** `out for signature` -> `Out for signature`; empty -> an em dash. */
export function humanise(v: unknown): string {
  if (v === null || v === undefined || v === '') return '—';
  let t = String(v).replace(/[_-]+/g, ' ').trim();
  return t.charAt(0).toUpperCase() + t.slice(1);
}

export function cap(s?: string | null): string {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : '—';
}

/** "$100k" / "$48,000": the stat strip's short money. */
export function shortMoney(amount?: number | null, code?: string | null) {
  if (typeof amount !== 'number') return '—';
  let sym = !code || code === 'USD' ? '$' : `${code} `;
  if (amount >= 100_000 && amount % 1000 === 0) {
    return `${sym}${(amount / 1000).toLocaleString('en-US')}k`;
  }
  return `${sym}${amount.toLocaleString('en-US')}`;
}

/** "USD 100,000": the details rows' money. */
export function longMoney(amount?: number | null, code?: string | null) {
  if (typeof amount !== 'number') return '—';
  return `${code ?? 'USD'} ${amount.toLocaleString('en-US')}`;
}

/** `$4.82M`, `€310k`: money short enough for a stat tile. */
export function compactMoney(amount: number, code?: string): string {
  try {
    return new Intl.NumberFormat('en-US', {
      style: code ? 'currency' : 'decimal',
      currency: code || undefined,
      notation: 'compact',
      maximumFractionDigits: 2,
    }).format(amount);
  } catch {
    return String(amount);
  }
}

/**
 * A value as a local Date. A date-only string ('2027-07-14') is that local
 * calendar day; `new Date()` would read it as UTC midnight and land on the
 * previous day west of Greenwich.
 */
export function toLocalDate(v: unknown): Date {
  if (v instanceof Date) return v;
  let m = typeof v === 'string' ? v.match(/^(\d{4})-(\d{2})-(\d{2})$/) : null;
  return m ? new Date(+m[1], +m[2] - 1, +m[3]) : new Date(v as any);
}

/** `14 Jul 2027`. Local calendar day, not toISOString (which shifts by UTC). */
export function formatDay(v: unknown): string {
  if (!v) return '—';
  let d = toLocalDate(v);
  if (Number.isNaN(d.getTime())) return String(v);
  return d.toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

/** `14 Jul 2027, 11:40` */
export function formatDateTime(v: unknown): string {
  if (!v) return '';
  let d = toLocalDate(v);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  });
}

/** A timestamp's local calendar day, or '' when there is none. */
export function formatStamp(v: unknown): string {
  return v ? formatDay(v).replace('—', '') : '';
}

/** ["4 Feb", "2026"]: a stat value and its grey line. */
export function dayAndYear(v: unknown): [string, string] {
  if (!v) return ['—', ''];
  let d = toLocalDate(v);
  if (Number.isNaN(d.getTime())) return ['—', ''];
  return [
    d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }),
    String(d.getFullYear()),
  ];
}

/** An ISO calendar day for exports. */
export function isoDate(v: unknown): string {
  if (!v) return '';
  let d = v instanceof Date ? v : new Date(v as any);
  return Number.isNaN(d.getTime()) ? '' : d.toISOString();
}
