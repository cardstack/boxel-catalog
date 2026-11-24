// One person's punches folded into days, read off the organization's clock.
// Plain functions, so a template folds once per render instead of re-running a
// computed field per row.

export interface PunchLike {
  eventId?: string | null;
  kind?: string | null;
  direction?: string | null;
  punchedAt?: Date | string | null;
  assurance?: string | null;
  state?: string | null;
}

export interface ScheduleLike {
  timezone?: string | null;
  scheduledArrival?: string | null;
  scheduledDeparture?: string | null;
  graceMinutes?: number | null;
}

export type Verdict =
  | 'on-time'
  | 'late'
  | 'early'
  | 'late-early'
  | 'no-checkout'
  | 'none';

export interface FoldedDay {
  key: string;
  firstIn: string;
  lastOut: string;
  minutes: number;
  punchCount: number;
  lateBy: number;
  earlyBy: number;
  stillIn: boolean;
  verdict: Verdict;
}

// A punch counts once it is recorded, or once a manager approves the
// correction that asked for it.
export function countsTowardDays(p: PunchLike): boolean {
  if (!p?.direction) {
    return false;
  }
  if (p.kind === 'correction') {
    return p.state === 'approved';
  }
  return !p.state || p.state === 'recorded';
}

const clocks = new Map<string, Intl.DateTimeFormat>();

function clockFor(timezone: string): Intl.DateTimeFormat {
  let zone = timezone || 'UTC';
  let clock = clocks.get(zone);
  if (!clock) {
    try {
      clock = new Intl.DateTimeFormat('en-CA', {
        timeZone: zone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23',
      });
    } catch {
      clock = clockFor('UTC');
    }
    clocks.set(zone, clock);
  }
  return clock;
}

// The local day and time of an instant: "2026-11-23", "08:34", 514.
export function localClock(
  at: Date,
  timezone: string,
): { day: string; label: string; minutes: number } {
  let parts: Record<string, string> = {};
  for (let part of clockFor(timezone).formatToParts(at)) {
    parts[part.type] = part.value;
  }
  let hour = Number(parts.hour) % 24;
  let minute = Number(parts.minute);
  return {
    day: `${parts.year}-${parts.month}-${parts.day}`,
    label: `${String(hour).padStart(2, '0')}:${parts.minute}`,
    minutes: hour * 60 + minute,
  };
}

// Minutes past midnight for "08:30" or "8:30 AM"; null when unreadable.
export function clockMinutes(label: string | null | undefined): number | null {
  if (!label) {
    return null;
  }
  let text = String(label).trim().toLowerCase().replace(/\s+/g, '');
  let suffix = text.endsWith('am') ? 'am' : text.endsWith('pm') ? 'pm' : '';
  let time = suffix ? text.slice(0, -2) : text;
  let [h, m] = time.split(':').map(Number);
  if (!Number.isFinite(h) || !Number.isFinite(m)) {
    return null;
  }
  let hour = h % 24;
  if (suffix === 'pm' && hour < 12) {
    hour += 12;
  } else if (suffix === 'am' && hour === 12) {
    hour = 0;
  }
  return hour * 60 + m;
}

function instant(value: Date | string | null | undefined): Date | null {
  if (!value) {
    return null;
  }
  let at = value instanceof Date ? value : new Date(value);
  return Number.isNaN(at.getTime()) ? null : at;
}

interface Counted {
  at: Date;
  direction: string;
  corrected: boolean;
}

interface Shift {
  start: Date;
  lastIn: Date;
  end: Date | null;
  punches: number;
}

// A shift can run past midnight, so ins and outs are paired across the whole
// history, not within a day: an in opens a shift and the next out within 12
// hours closes it. A longer one counts nothing until a correction closes it,
// so a forgotten checkout isn't paid. A second in more than 30 minutes after
// the last one starts a new shift.
const MAX_SHIFT_MS = 12 * 60 * 60 * 1000;
const REPEAT_IN_MS = 30 * 60 * 1000;

function counted(punches: PunchLike[] | null | undefined): Counted[] {
  let list: Counted[] = [];
  for (let p of punches ?? []) {
    if (!countsTowardDays(p)) {
      continue;
    }
    let at = instant(p.punchedAt);
    if (at) {
      list.push({
        at,
        direction: String(p.direction),
        corrected: p.kind === 'correction',
      });
    }
  }
  return list.sort((a, b) => a.at.getTime() - b.at.getTime());
}

// Shifts in order, plus the outs that closed nothing.
function pairShifts(list: Counted[]): { shifts: Shift[]; strayOuts: Date[] } {
  let shifts: Shift[] = [];
  let strayOuts: Date[] = [];
  let open: Shift | null = null;
  for (let p of list) {
    // An approved correction may close a shift of any length: a manager has
    // confirmed when the person left.
    let capped = !(p.direction === 'out' && p.corrected);
    if (
      open &&
      capped &&
      p.at.getTime() - open.start.getTime() > MAX_SHIFT_MS
    ) {
      shifts.push(open);
      open = null;
    }
    if (
      open &&
      p.direction === 'in' &&
      p.at.getTime() - open.lastIn.getTime() > REPEAT_IN_MS
    ) {
      shifts.push(open);
      open = null;
    }
    if (p.direction === 'in') {
      if (open) {
        open.punches++;
        open.lastIn = p.at;
      } else {
        open = { start: p.at, lastIn: p.at, end: null, punches: 1 };
      }
    } else if (open) {
      shifts.push({ ...open, end: p.at, punches: open.punches + 1 });
      open = null;
    } else {
      strayOuts.push(p.at);
    }
  }
  if (open) {
    shifts.push(open);
  }
  return { shifts, strayOuts };
}

// Each shift belongs to the day it started on.
export function foldDays(
  punches: PunchLike[] | null | undefined,
  schedule: ScheduleLike | null | undefined,
): FoldedDay[] {
  let timezone = schedule?.timezone || 'UTC';
  let arrival = clockMinutes(schedule?.scheduledArrival);
  let departure = clockMinutes(schedule?.scheduledDeparture);
  let grace = schedule?.graceMinutes ?? 0;
  let { shifts, strayOuts } = pairShifts(counted(punches));

  let byDay = new Map<string, { shifts: Shift[]; strayOuts: Date[] }>();
  let bucket = (at: Date) => {
    let key = localClock(at, timezone).day;
    let entry = byDay.get(key) ?? { shifts: [], strayOuts: [] };
    byDay.set(key, entry);
    return entry;
  };
  for (let shift of shifts) {
    bucket(shift.start).shifts.push(shift);
  }
  for (let at of strayOuts) {
    bucket(at).strayOuts.push(at);
  }

  let days: FoldedDay[] = [];
  for (let [key, entry] of [...byDay.entries()].sort(([a], [b]) =>
    a.localeCompare(b),
  )) {
    let first = entry.shifts[0];
    let last = entry.shifts[entry.shifts.length - 1];
    let minutes = entry.shifts.reduce(
      (sum, s) =>
        s.end
          ? sum + Math.round((s.end.getTime() - s.start.getTime()) / 60000)
          : sum,
      0,
    );
    let firstLocal = first ? localClock(first.start, timezone) : undefined;
    let lastOutAt = last
      ? last.end
      : entry.strayOuts[entry.strayOuts.length - 1];
    let lastLocal = lastOutAt ? localClock(lastOutAt, timezone) : undefined;
    let sameDay = lastLocal?.day === key;
    let rawLate =
      firstLocal && arrival !== null ? firstLocal.minutes - arrival : null;
    // An out after midnight is never early.
    let rawEarly =
      first && lastLocal && sameDay && departure !== null
        ? departure - lastLocal.minutes
        : null;
    let late = rawLate !== null && rawLate > grace;
    let early = rawEarly !== null && rawEarly > grace;
    let stillIn = Boolean(last && !last.end);
    days.push({
      key,
      firstIn: firstLocal?.label ?? '',
      lastOut: lastLocal
        ? sameDay
          ? lastLocal.label
          : `${lastLocal.label} (next day)`
        : '',
      minutes,
      punchCount:
        entry.shifts.reduce((n, s) => n + s.punches, 0) +
        entry.strayOuts.length,
      lateBy: Math.max(0, rawLate ?? 0),
      earlyBy: Math.max(0, rawEarly ?? 0),
      stillIn,
      verdict: !first
        ? 'none'
        : late && early
          ? 'late-early'
          : late
            ? 'late'
            : early
              ? 'early'
              : stillIn
                ? 'no-checkout'
                : 'on-time',
    });
  }
  return days;
}

// The shift still open now, read from the same pairing the days use.
export function openShiftStart(
  punches: PunchLike[] | null | undefined,
  now = new Date(),
): Date | undefined {
  let { shifts } = pairShifts(counted(punches));
  let last = shifts[shifts.length - 1];
  if (
    last &&
    !last.end &&
    now.getTime() - last.start.getTime() < MAX_SHIFT_MS
  ) {
    return last.start;
  }
  return undefined;
}

export function isCheckedIn(
  punches: PunchLike[] | null | undefined,
  now = new Date(),
): boolean {
  return Boolean(openShiftStart(punches, now));
}

// Minutes since the open shift started, for someone still in.
export function openMinutes(
  punches: PunchLike[] | null | undefined,
  now = new Date(),
): number {
  let start = openShiftStart(punches, now);
  return start
    ? Math.max(0, Math.round((now.getTime() - start.getTime()) / 60000))
    : 0;
}

// A wall-clock time typed in the organization's zone ("2026-11-20T08:30"),
// as the instant it names there, whatever zone the device is in.
export function zonedToUtc(local: string, timezone: string): Date | null {
  let [datePart, timePart] = local.split('T');
  let [y, mo, d] = (datePart ?? '').split('-').map(Number);
  let [h, mi] = (timePart ?? '').split(':').map(Number);
  if (![y, mo, d, h, mi].every(Number.isFinite)) {
    return null;
  }
  let wanted = Date.UTC(y, mo - 1, d, h, mi);
  let typed = new Date(wanted);
  // Refuse a date that doesn't exist, such as Feb 31 or 25:99.
  if (
    typed.getUTCMonth() !== mo - 1 ||
    typed.getUTCDate() !== d ||
    typed.getUTCHours() !== h ||
    typed.getUTCMinutes() !== mi
  ) {
    return null;
  }
  let shownAt = (at: number) => {
    let shown = localClock(new Date(at), timezone);
    let [sy, sm, sd] = shown.day.split('-').map(Number);
    return Date.UTC(sy, sm - 1, sd, 0, shown.minutes);
  };
  let guess = wanted;
  // Two passes settle the zone offset, including across a DST change.
  for (let i = 0; i < 2; i++) {
    guess += wanted - shownAt(guess);
  }
  // A time the clocks skip on the spring-forward night: move it forward by
  // the gap, as a wall clock would read it.
  guess += wanted - shownAt(guess);
  return new Date(guess);
}

// The organization's today, as a day key.
export function todayKey(timezone: string | null | undefined): string {
  return localClock(new Date(), timezone || 'UTC').day;
}

export function minutesLabel(minutes: number): string {
  if (!minutes) {
    return '0m';
  }
  let h = Math.floor(minutes / 60);
  let m = minutes % 60;
  return h ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}m`;
}

export const VERDICT_LABEL: Record<Verdict, string> = {
  'on-time': 'On time',
  late: 'Late',
  early: 'Left early',
  'late-early': 'Late, left early',
  'no-checkout': 'No checkout',
  none: 'No check-in',
};
