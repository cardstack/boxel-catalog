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
  let [time, suffix] = String(label).trim().toLowerCase().split(/\s+/);
  let [h, m] = (time ?? '').split(':').map(Number);
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

export function foldDays(
  punches: PunchLike[] | null | undefined,
  schedule: ScheduleLike | null | undefined,
): FoldedDay[] {
  let timezone = schedule?.timezone || 'UTC';
  let arrival = clockMinutes(schedule?.scheduledArrival);
  let departure = clockMinutes(schedule?.scheduledDeparture);
  let grace = schedule?.graceMinutes ?? 0;

  let byDay = new Map<
    string,
    { at: Date; direction: string; local: ReturnType<typeof localClock> }[]
  >();
  for (let p of punches ?? []) {
    if (!countsTowardDays(p)) {
      continue;
    }
    let at = instant(p.punchedAt);
    if (!at) {
      continue;
    }
    let local = localClock(at, timezone);
    let list = byDay.get(local.day) ?? [];
    list.push({ at, direction: String(p.direction), local });
    byDay.set(local.day, list);
  }

  let days: FoldedDay[] = [];
  for (let [key, list] of [...byDay.entries()].sort(([a], [b]) =>
    a.localeCompare(b),
  )) {
    list.sort((a, b) => a.at.getTime() - b.at.getTime());
    let minutes = 0;
    let open: Date | null = null;
    for (let p of list) {
      if (p.direction === 'in' && !open) {
        open = p.at;
      } else if (p.direction === 'out' && open) {
        minutes += Math.max(
          0,
          Math.round((p.at.getTime() - open.getTime()) / 60000),
        );
        open = null;
      }
    }
    let first = list.find((p) => p.direction === 'in');
    let stillIn = list[list.length - 1].direction === 'in';
    let outs = list.filter((p) => p.direction === 'out');
    let last = stillIn ? undefined : outs[outs.length - 1];
    let rawLate =
      first && arrival !== null ? first.local.minutes - arrival : null;
    let rawEarly =
      last && departure !== null ? departure - last.local.minutes : null;
    let late = rawLate !== null && rawLate > grace;
    let early = rawEarly !== null && rawEarly > grace;
    days.push({
      key,
      firstIn: first?.local.label ?? '',
      lastOut: last?.local.label ?? '',
      minutes,
      punchCount: list.length,
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
              : !last
                ? 'no-checkout'
                : 'on-time',
    });
  }
  return days;
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
