// Month-grid arithmetic for a calendar view: which days to draw for a month,
// padded to whole weeks, and how to title it.

export function sameDay(a?: Date | null, b?: Date | null): boolean {
  if (!a || !b) {
    return false;
  }
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

export interface CalendarDay {
  date: Date;
  dayNumber: number;
  inMonth: boolean;
  isToday: boolean;
}

// 6 rows x 7 columns of days covering the cursor's month, weeks starting Sunday.
export function monthGrid(cursor: Date): CalendarDay[][] {
  let first = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  let start = new Date(first);
  start.setDate(first.getDate() - first.getDay());
  let today = new Date();
  let weeks: CalendarDay[][] = [];
  let day = new Date(start);
  for (let w = 0; w < 6; w++) {
    let week: CalendarDay[] = [];
    for (let d = 0; d < 7; d++) {
      week.push({
        date: new Date(day),
        dayNumber: day.getDate(),
        inMonth: day.getMonth() === cursor.getMonth(),
        isToday: sameDay(day, today),
      });
      day.setDate(day.getDate() + 1);
    }
    weeks.push(week);
  }
  return weeks;
}

export function monthTitle(cursor: Date): string {
  return cursor.toLocaleDateString('en-US', {
    month: 'long',
    year: 'numeric',
  });
}
