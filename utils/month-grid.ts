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

// Rows x 7 columns of days covering the cursor's month, padded to whole weeks
// that start Sunday, or Monday with `weekStart: 'mon'`. Six rows by default;
// `trim` drops trailing rows that fall wholly outside the month.
export function monthGrid(
  cursor: Date,
  weekStart: 'sun' | 'mon' = 'sun',
  trim = false,
): CalendarDay[][] {
  let first = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  let start = new Date(first);
  let offset = weekStart === 'mon' ? (first.getDay() + 6) % 7 : first.getDay();
  start.setDate(first.getDate() - offset);
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
  if (trim) {
    weeks = weeks.filter((week) => week.some((d) => d.inMonth));
  }
  return weeks;
}

export function monthTitle(cursor: Date): string {
  return cursor.toLocaleDateString('en-US', {
    month: 'long',
    year: 'numeric',
  });
}
