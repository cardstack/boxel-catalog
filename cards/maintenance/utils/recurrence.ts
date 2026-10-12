/**
 * Rhythm math for the Facilities & Assets kit — the ONE place next-occurrence
 * dates are computed. Plan computeds, the Maintenance Calendar, the PM
 * generator and the Home runway all call `nextOccurrence`, so they can never
 * disagree.
 *
 * Works over the catalog `RecurringPatternField` data shape
 * (pattern / interval / daysOfWeek "0,1,..6" / dayOfMonth / monthOfYear /
 * startDate / endDate / occurrences) plus the kit's meter half. Pure: no
 * card instances, no writes, no `Date.toISOString()` on calendar days.
 */

export interface RecurringPatternData {
  pattern?: string | null; // none | daily | weekdays | weekly | biweekly | monthly | yearly | custom
  interval?: number | null;
  daysOfWeek?: string | null; // "1,3,5" — 0 = Sunday
  dayOfMonth?: number | null; // 1–31, -1 = last day
  monthOfYear?: number | null; // 1–12
  startDate?: Date | string | null;
  endDate?: Date | string | null;
  occurrences?: number | null;
}

export interface MaintenanceTriggerData {
  calendar?: RecurringPatternData | null;
  meterThreshold?: number | null;
  whicheverFirst?: boolean | null;
  leadDays?: number | null;
}

export interface NextOccurrence {
  /** Next calendar due date (local calendar day, midnight) — undefined when the rule is meter-only or exhausted. */
  dueDate?: Date;
  /** Meter value at which the next occurrence falls due — undefined when the rule has no meter half. */
  dueMeter?: number;
  /** Which half decided the answer when both exist. */
  decidedBy: 'calendar' | 'meter' | 'none';
  /** Days from `today` to `dueDate` (negative = overdue). */
  daysUntil?: number;
  /** Meter units remaining until `dueMeter` (negative = overdue). */
  meterRemaining?: number;
  /** True when either half is due or overdue as of today / current reading. */
  isDue: boolean;
  /** The date the generator should raise the work order (dueDate − leadDays). */
  generateOn?: Date;
}

const DAY_MS = 86_400_000;

export function toDay(
  value: Date | string | null | undefined,
): Date | undefined {
  if (value == null || value === '') return undefined;
  if (value instanceof Date) {
    if (isNaN(value.getTime())) return undefined;
    return new Date(value.getFullYear(), value.getMonth(), value.getDate());
  }
  let m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value));
  if (m) return new Date(+m[1], +m[2] - 1, +m[3]);
  let d = new Date(value);
  return isNaN(d.getTime())
    ? undefined
    : new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function addDays(day: Date, n: number): Date {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate() + n);
}

export function daysBetweenDays(from: Date, to: Date): number {
  return Math.round((toDay(to)!.getTime() - toDay(from)!.getTime()) / DAY_MS);
}

/** Calendar-day string YYYY-MM-DD in local time — never `toISOString`. */
export function dayKey(day: Date): string {
  let y = day.getFullYear();
  let m = String(day.getMonth() + 1).padStart(2, '0');
  let d = String(day.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function lastDayOfMonth(year: number, monthIndex: number): number {
  return new Date(year, monthIndex + 1, 0).getDate();
}

function clampDayOfMonth(
  year: number,
  monthIndex: number,
  dayOfMonth: number,
): Date {
  let last = lastDayOfMonth(year, monthIndex);
  let d =
    dayOfMonth === -1 || dayOfMonth > last ? last : Math.max(1, dayOfMonth);
  return new Date(year, monthIndex, d);
}

function parseDaysOfWeek(s?: string | null): number[] {
  if (!s) return [];
  return String(s)
    .split(',')
    .map((x) => parseInt(x.trim(), 10))
    .filter((n) => !isNaN(n) && n >= 0 && n <= 6)
    .sort((a, b) => a - b);
}

/**
 * The first occurrence strictly AFTER `anchor` (the last completion, or the
 * plan's start when nothing has been completed yet). Returns undefined when
 * the pattern is `none`, unset, or exhausted by endDate/occurrences.
 */
export function nextCalendarOccurrence(
  rule: RecurringPatternData | null | undefined,
  anchor: Date | string | null | undefined,
  completedCount = 0,
): Date | undefined {
  if (!rule || !rule.pattern || rule.pattern === 'none') return undefined;
  let start = toDay(rule.startDate);
  let from = toDay(anchor) ?? start;
  if (!from) return undefined;
  let interval = Math.max(1, Math.floor(rule.interval ?? 1));
  let candidate: Date | undefined;

  switch (rule.pattern) {
    case 'daily':
      candidate = addDays(from, interval);
      break;
    case 'weekdays': {
      let d = addDays(from, 1);
      while (d.getDay() === 0 || d.getDay() === 6) d = addDays(d, 1);
      candidate = d;
      break;
    }
    case 'weekly':
    case 'biweekly': {
      let weeks = rule.pattern === 'biweekly' ? 2 : interval;
      let days = parseDaysOfWeek(rule.daysOfWeek);
      if (days.length === 0) {
        candidate = addDays(from, 7 * weeks);
      } else {
        // next listed weekday after `from`, inside this week; else roll to the
        // first listed weekday `weeks` weeks on.
        let later = days.find((dow) => dow > from.getDay());
        if (later != null) {
          candidate = addDays(from, later - from.getDay());
        } else {
          let weekStart = addDays(from, -from.getDay());
          candidate = addDays(weekStart, 7 * weeks + days[0]);
        }
      }
      break;
    }
    case 'monthly': {
      let dom = rule.dayOfMonth ?? (start ?? from).getDate();
      let y = from.getFullYear();
      let m = from.getMonth();
      // try this month first (rule day after anchor), else +interval months
      let sameMonth = clampDayOfMonth(y, m, dom);
      if (sameMonth.getTime() > from.getTime() && !rule.dayOfMonth) {
        candidate = clampDayOfMonth(y, m + interval, dom);
      } else if (sameMonth.getTime() > from.getTime()) {
        candidate = sameMonth;
      } else {
        candidate = clampDayOfMonth(y, m + interval, dom);
      }
      break;
    }
    case 'yearly': {
      let base = start ?? from;
      let month = (rule.monthOfYear ?? base.getMonth() + 1) - 1;
      let dom = rule.dayOfMonth ?? base.getDate();
      let thisYear = clampDayOfMonth(from.getFullYear(), month, dom);
      candidate =
        thisYear.getTime() > from.getTime()
          ? thisYear
          : clampDayOfMonth(from.getFullYear() + interval, month, dom);
      break;
    }
    case 'custom':
    default:
      // RRULE parsing is out of scope for v1 — treated as "every `interval` days".
      candidate = addDays(from, interval);
  }

  if (!candidate) return undefined;
  let end = toDay(rule.endDate);
  if (end && candidate.getTime() > end.getTime()) return undefined;
  if (rule.occurrences && completedCount >= rule.occurrences) return undefined;
  return candidate;
}

/**
 * Both halves of a Maintenance Trigger resolved against today and the meter.
 * - `anchorDate`: last completion date (or plan start).
 * - `meterAtAnchor`: meter reading recorded at that completion.
 * - `meterNow`: the asset's current reading.
 */
export function nextOccurrence(
  trigger: MaintenanceTriggerData | null | undefined,
  anchorDate: Date | string | null | undefined,
  opts: {
    today?: Date;
    meterNow?: number | null;
    meterAtAnchor?: number | null;
    completedCount?: number;
  } = {},
): NextOccurrence {
  let today = toDay(opts.today ?? new Date())!;
  let result: NextOccurrence = { decidedBy: 'none', isDue: false };
  if (!trigger) return result;

  let dueDate = nextCalendarOccurrence(
    trigger.calendar,
    anchorDate,
    opts.completedCount ?? 0,
  );
  let threshold = trigger.meterThreshold ?? undefined;
  let dueMeter =
    threshold && threshold > 0 && opts.meterAtAnchor != null
      ? opts.meterAtAnchor + threshold
      : threshold &&
          threshold > 0 &&
          opts.meterNow != null &&
          opts.meterAtAnchor == null
        ? opts.meterNow + threshold
        : undefined;

  if (dueDate) {
    result.dueDate = dueDate;
    result.daysUntil = daysBetweenDays(today, dueDate);
  }
  if (dueMeter != null) {
    result.dueMeter = dueMeter;
    if (opts.meterNow != null) result.meterRemaining = dueMeter - opts.meterNow;
  }

  let calendarDue = result.daysUntil != null && result.daysUntil <= 0;
  let meterDue = result.meterRemaining != null && result.meterRemaining <= 0;

  if (dueDate && dueMeter != null) {
    if (trigger.whicheverFirst === false) {
      // both required: due only when both have arrived; calendar decides the date
      result.decidedBy = 'calendar';
      result.isDue = calendarDue && meterDue;
    } else {
      // whichever first (default when both halves exist)
      let meterWins =
        meterDue && !calendarDue
          ? true
          : meterDue && calendarDue
            ? (result.meterRemaining ?? 0) <= (result.daysUntil ?? 0)
            : false;
      result.decidedBy = meterWins ? 'meter' : 'calendar';
      result.isDue = calendarDue || meterDue;
    }
  } else if (dueDate) {
    result.decidedBy = 'calendar';
    result.isDue = calendarDue;
  } else if (dueMeter != null) {
    result.decidedBy = 'meter';
    result.isDue = meterDue;
  }

  if (result.dueDate) {
    result.generateOn = addDays(result.dueDate, -(trigger.leadDays ?? 0));
  }
  return result;
}

/** Every calendar occurrence inside [from, to], for projecting the runway. */
export function occurrencesBetween(
  rule: RecurringPatternData | null | undefined,
  anchor: Date | string | null | undefined,
  from: Date,
  to: Date,
  limit = 60,
): Date[] {
  let out: Date[] = [];
  let cursor: Date | string | null | undefined = anchor;
  let count = 0;
  for (let i = 0; i < limit; i++) {
    let next = nextCalendarOccurrence(rule, cursor, count);
    if (!next) break;
    if (next.getTime() > to.getTime()) break;
    if (next.getTime() >= toDay(from)!.getTime()) out.push(next);
    cursor = next;
    count++;
  }
  return out;
}

/** Human summary — "Every 90 days · or every 500 h (whichever first) · raise 14 d ahead". */
export function triggerSummary(
  trigger: MaintenanceTriggerData | null | undefined,
  unit?: string | null,
): string {
  if (!trigger) return 'No rhythm set';
  let parts: string[] = [];
  let c = trigger.calendar;
  if (c?.pattern && c.pattern !== 'none') {
    let n = Math.max(1, Math.floor(c.interval ?? 1));
    let label: string;
    switch (c.pattern) {
      case 'daily':
        label = n === 1 ? 'Every day' : `Every ${n} days`;
        break;
      case 'weekdays':
        label = 'Every weekday';
        break;
      case 'weekly':
        label = n === 1 ? 'Weekly' : `Every ${n} weeks`;
        break;
      case 'biweekly':
        label = 'Every 2 weeks';
        break;
      case 'monthly':
        label = n === 1 ? 'Monthly' : `Every ${n} months`;
        if (c.dayOfMonth === -1) label += ' (last day)';
        else if (c.dayOfMonth) label += ` (day ${c.dayOfMonth})`;
        break;
      case 'yearly':
        label = n === 1 ? 'Yearly' : `Every ${n} years`;
        break;
      default:
        label = `Every ${n} days`;
    }
    parts.push(label);
  }
  if (trigger.meterThreshold && trigger.meterThreshold > 0) {
    parts.push(
      `every ${trigger.meterThreshold.toLocaleString()} ${unit ?? 'units'}`,
    );
  }
  if (parts.length === 0) return 'No rhythm set';
  let s = parts.join(
    parts.length > 1 && trigger.whicheverFirst !== false ? ' or ' : ' and ',
  );
  if (parts.length > 1)
    s += trigger.whicheverFirst === false ? ' (both)' : ' (whichever first)';
  if (trigger.leadDays) s += ` · raise ${trigger.leadDays} d ahead`;
  return s;
}
