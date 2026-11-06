export const TABS = [
  // The desk: notice deadlines, awaiting signature, open deviations (Legal
  // Home block). First because it is the screen the contracts manager opens
  // in the morning.
  { key: 'home', label: 'Home' },
  { key: 'repository', label: 'Repository' },
  // One contract, clause by clause, with its ceremony — Contract Workspace +
  // Signature Block View blocks over whichever contract was picked.
  { key: 'workspace', label: 'Workspace' },
  { key: 'approvals', label: 'Approvals' },
  { key: 'obligations', label: 'Obligations' },
  { key: 'compliance', label: 'Compliance' },
  { key: 'clauses', label: 'Clauses' },
  { key: 'signatories', label: 'Signatories' },
  { key: 'renewals', label: 'Renewals' },
  { key: 'templates', label: 'Templates' },
  { key: 'requests', label: 'Requests' },
  { key: 'audit', label: 'Audit' },
];

/** Renewal urgency band, in days to the notice deadline. */
export const NOTICE_WINDOW_DAYS = 90;

/** A person's display name: stored `name` first, computed `cardTitle` second. */
export function personLabelOrUndefined(e: any): string | undefined {
  if (!e) return undefined;
  let n = typeof e.name === 'string' ? e.name.trim() : '';
  if (n) return n;
  let t = typeof e.cardTitle === 'string' ? e.cardTitle.trim() : '';
  return t || undefined;
}
export function personLabel(e: any): string {
  return personLabelOrUndefined(e) ?? 'Unnamed';
}

/**
 * Who reviews a contract that matches no rule.
 *
 * A named constant rather than an inline string so the fallback is visible in
 * one place and can become a policy card later without hunting for it.
 */
export const DEFAULT_REVIEWER = 'Legal';

/**
 * Bars are scaled against the LARGEST band, not against the total.
 *
 * Scaling to the total is the obvious choice and it is wrong here: with three
 * statuses holding one contract each, every bar would render at 33% and the
 * chart would say nothing that the three identical numbers beside it did not.
 * Scaling to the max makes the biggest band a full bar and every other band a
 * readable fraction of it, which is the comparison the reader actually wants.
 */
export function scaleBands<T extends { count: number }>(
  rows: T[],
): (T & { pct: number })[] {
  let max = Math.max(0, ...rows.map((r) => r.count));
  return rows.map((r) => ({
    ...r,
    pct: max ? Math.round((r.count / max) * 100) : 0,
  }));
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

/** `14 Jul 2027`, not `Wed Jul 14 2027 00:00:00 GMT+0800`. */
export function formatDay(v: unknown): string {
  if (!v) return '—';
  let d = toLocalDate(v);
  if (Number.isNaN(d.getTime())) return String(v);
  // NOT toISOString(): it converts to UTC first, which renders a local date a
  // day early or late depending on the offset — the Acme term end showed
  // 2027-07-13 for a contract ending 2027-07-14. On a notice deadline that is
  // a missed obligation, not a formatting nit.
  return d.toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

/** `out for signature` -> `Out for signature`. */
export function humanise(v: unknown): string {
  if (v === null || v === undefined || v === '') return '—';
  let t = String(v).replace(/[_-]+/g, ' ').trim();
  return t.charAt(0).toUpperCase() + t.slice(1);
}

/** A timestamp's local calendar day, or '' when there is none. */
export function formatStamp(v: unknown): string {
  return v ? formatDay(v).replace('—', '') : '';
}

/**
 * The index of the step a contract's chain is waiting on, or -1 when none is
 * open. It reads the steps' decisions, like the chain's computed
 * `currentStepIndex`, because a live-query row does not always carry computed
 * fields. A step with no decision yet counts as pending.
 */
export function openStepIndex(c: any): number {
  let steps = (c?.approvalChain?.steps ?? []).filter(Boolean);
  return steps.findIndex(
    (st: any) => (st?.decision ?? 'pending') === 'pending',
  );
}

/** The step a contract is currently sitting on, or undefined if none is open. */
export function openStep(c: any): any {
  let idx = openStepIndex(c);
  return idx < 0
    ? undefined
    : (c?.approvalChain?.steps ?? []).filter(Boolean)[idx];
}

/** Status colour, carried as dot + text (never colour alone). */
export type Tone = 'bad' | 'warn' | 'ok' | 'info' | 'neutral';

/** The shared legal modules speak in hues; the app draws tones. */
export function hueTone(hue?: string | null): Tone {
  switch (hue) {
    case 'red':
      return 'bad';
    case 'orange':
    case 'amber':
      return 'warn';
    case 'green':
      return 'ok';
    case 'blue':
      return 'info';
    default:
      return 'neutral';
  }
}

export function riskTone(grade?: string | null): Tone {
  return grade === 'critical' || grade === 'high'
    ? 'bad'
    : grade === 'medium'
      ? 'warn'
      : grade === 'low'
        ? 'ok'
        : 'neutral';
}

/** Days left on a notice: red inside a month, amber inside the window. */
export function noticeTone(days?: number | null): Tone {
  if (typeof days !== 'number') return 'neutral';
  return days <= 30 ? 'bad' : days <= NOTICE_WINDOW_DAYS ? 'warn' : 'neutral';
}

/** Initials for an avatar mark. */
export function initials(name?: string | null): string {
  return (name ?? '')
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join('');
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
