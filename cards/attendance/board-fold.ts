// Who is in, out, away or late today. A pure fold over the people a manager
// can read, so a template folds once per render.
import {
  clockMinutes,
  foldDays,
  isCheckedIn,
  localClock,
  openShiftStart,
  type PunchLike,
  type ScheduleLike,
} from './attendance-day';
import { LEAVE_TYPES, coversDay, dayKeyOf, type LeaveLike } from './leave-days';

export interface BoardPerson {
  id: string;
  name: string;
  userId: string;
  year?: string | null;
  punches: PunchLike[] | null | undefined;
  schedule: ScheduleLike | null | undefined;
}

export interface BoardEntry {
  id: string;
  name: string;
  detail: string;
}

export interface Board {
  in: BoardEntry[];
  out: BoardEntry[];
  expected: BoardEntry[];
  onLeave: BoardEntry[];
  notDue: BoardEntry[];
}

// A person has one record per year; only the latest counts. People without a
// userId stand alone, keyed by record id.
export function currentRecords<
  T extends { id: string; userId?: string | null; year?: string | null },
>(records: T[]): T[] {
  let latest = new Map<string, T>();
  for (let r of records) {
    let key = r.userId || r.id;
    let seen = latest.get(key);
    if (!seen || (r.year ?? '') > (seen.year ?? '')) {
      latest.set(key, r);
    }
  }
  return [...latest.values()];
}

function isWeekend(day: string): boolean {
  let [y, m, d] = day.split('-').map(Number);
  let weekday = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return weekday === 0 || weekday === 6;
}

// Someone is expected once the scheduled arrival plus grace has passed and
// they are neither in, nor done for the day, nor on approved leave. Weekends
// expect nobody.
export function foldBoard(
  people: BoardPerson[],
  leave: LeaveLike[],
  timezone: string,
  now = new Date(),
): Board {
  let board: Board = { in: [], out: [], expected: [], onLeave: [], notDue: [] };
  let clock = localClock(now, timezone);
  for (let p of currentRecords(people)) {
    let name = p.name || p.userId;
    if (isCheckedIn(p.punches, now)) {
      let start = openShiftStart(p.punches, now);
      let since = start ? localClock(start, timezone).label : '';
      board.in.push({ id: p.id, name, detail: `In since ${since}` });
      continue;
    }
    let away = leave.find(
      (l) =>
        l.userId === p.userId &&
        l.state === 'approved' &&
        coversDay(l, clock.day),
    );
    if (away) {
      let type =
        LEAVE_TYPES.find((t) => t.value === away.ptoType)?.label ?? 'Leave';
      board.onLeave.push({
        id: p.id,
        name,
        detail: `${type} until ${dayKeyOf(away.endDate)}`,
      });
      continue;
    }
    let today = foldDays(p.punches, p.schedule).find(
      (d) => d.key === clock.day,
    );
    if (today?.firstIn) {
      board.out.push({
        id: p.id,
        name,
        detail: `${today.firstIn} to ${today.lastOut || '…'}`,
      });
      continue;
    }
    let arrival = clockMinutes(p.schedule?.scheduledArrival);
    if (arrival === null || isWeekend(clock.day)) {
      continue;
    }
    let grace = p.schedule?.graceMinutes ?? 0;
    let due = p.schedule?.scheduledArrival ?? '';
    if (clock.minutes > arrival + grace) {
      board.expected.push({
        id: p.id,
        name,
        detail: `Due ${due} · ${clock.minutes - arrival} min late`,
      });
    } else {
      board.notDue.push({ id: p.id, name, detail: `Due ${due}` });
    }
  }
  return board;
}
