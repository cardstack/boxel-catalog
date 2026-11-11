// A cron expression in plain words, for people reading an automation. The
// summary is one short phrase (`0 7 * * MON` is "Every Monday at 7:00 AM"),
// and where the expression names several times, days or months, they are
// listed in groups rather than joined into a long sentence: `30 8,12,18 * * *`
// is "3 times a day" with the three times listed. It covers the shapes people
// write (steps, lists and ranges of minutes and hours, days of the week, days
// of the month, months) and returns undefined for anything it can't put
// plainly, so a view falls back to the expression alone. Display only: whether
// an expression is valid, and when it fires, is the server's to decide.

export interface CronDescriptionGroup {
  // Leads into the list as part of a sentence: "at these times", "on these
  // days". Lower case, so a view can join several with "and".
  label: string;
  items: string[];
}

export interface CronDescription {
  summary: string;
  groups: CronDescriptionGroup[];
}

const MACROS: Record<string, string> = {
  '@yearly': '0 0 1 1 *',
  '@annually': '0 0 1 1 *',
  '@monthly': '0 0 1 * *',
  '@weekly': '0 0 * * 0',
  '@daily': '0 0 * * *',
  '@midnight': '0 0 * * *',
  '@hourly': '0 * * * *',
};

const MONTHS = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const DAYS = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];
const MONTH_NAMES = MONTHS.map((m) => m.slice(0, 3).toUpperCase());
const DAY_NAMES = DAYS.map((d) => d.slice(0, 3).toUpperCase());

interface Parsed {
  any: boolean; // `*`
  step?: number; // `*/n`
  values: number[]; // every value the field names, sorted
}

function parseField(
  field: string,
  min: number,
  max: number,
  names?: string[],
): Parsed | undefined {
  if (field === '*') {
    return { any: true, values: [] };
  }
  let stepMatch = /^\*\/(\d+)$/.exec(field);
  if (stepMatch) {
    let step = Number(stepMatch[1]);
    return step > 0 ? { any: false, step, values: [] } : undefined;
  }
  let value = (token: string): number | undefined => {
    let index = names?.indexOf(token.toUpperCase()) ?? -1;
    let n = index >= 0 ? index + (min === 1 ? 1 : 0) : Number(token);
    if (names === DAY_NAMES && n === 7) {
      n = 0;
    }
    return Number.isInteger(n) && n >= min && n <= max ? n : undefined;
  };
  let values = new Set<number>();
  for (let part of field.split(',')) {
    let range = /^([A-Za-z0-9]+)-([A-Za-z0-9]+)$/.exec(part);
    if (range) {
      let from = value(range[1]);
      let to = value(range[2]);
      // Sunday is both 0 and 7, so a range of days that ends on Sunday
      // (FRI-SUN, 5-7) runs up to 7 and wraps back to 0.
      if (names === DAY_NAMES && to === 0 && from !== undefined && from > 0) {
        to = 7;
      }
      if (from === undefined || to === undefined || to < from) {
        return undefined;
      }
      for (let n = from; n <= to; n++) {
        values.add(names === DAY_NAMES ? n % 7 : n);
      }
    } else {
      let n = value(part);
      if (n === undefined) {
        return undefined;
      }
      values.add(n);
    }
  }
  return { any: false, values: [...values].sort((a, b) => a - b) };
}

function ordinal(n: number): string {
  let tens = n % 100;
  let suffix =
    tens >= 11 && tens <= 13
      ? 'th'
      : (({ 1: 'st', 2: 'nd', 3: 'rd' } as Record<number, string>)[n % 10] ??
        'th');
  return `${n}${suffix}`;
}

function clock(hour: number, minute: number): string {
  if (minute === 0 && hour === 0) {
    return 'midnight';
  }
  if (minute === 0 && hour === 12) {
    return 'noon';
  }
  let h = hour % 12 === 0 ? 12 : hour % 12;
  return `${h}:${String(minute).padStart(2, '0')} ${hour < 12 ? 'AM' : 'PM'}`;
}

function pastTheHour(minute: number): string {
  return minute === 0 ? 'On the hour' : `${minute} minutes past the hour`;
}

function times(n: number, unit: 'an hour' | 'a day'): string {
  return n === 2 ? `Twice ${unit}` : `${n} times ${unit}`;
}

// A run of three or more consecutive values reads as a range.
function isRun(values: number[]): boolean {
  return (
    values.length > 2 &&
    values.every((v, i) => i === 0 || v === values[i - 1] + 1)
  );
}

// Days of the week as a run of three or more, starting wherever the run
// starts, so one that passes the end of the week (5, 6, 0) still counts.
function weekRun(values: number[]): number[] | undefined {
  for (let i = 0; i < values.length; i++) {
    let rotated = [...values.slice(i), ...values.slice(0, i)];
    if (
      rotated.length > 2 &&
      rotated.every((v, j) => j === 0 || v === (rotated[j - 1] + 1) % 7)
    ) {
      return rotated;
    }
  }
  return undefined;
}

// Within a day: `phrase` repeats through the day ("Every 5 minutes"), or is
// the time it fires at ("at 7:00 AM"); several times are listed instead.
interface TimeOfDay {
  repeats: boolean;
  phrase: string;
  list?: CronDescriptionGroup;
}

function describeTime(minute: Parsed, hour: Parsed): TimeOfDay | undefined {
  let window = (from: number, to: number, m0: number, m1: number) =>
    `from ${clock(from, m0)} to ${clock(to, m1)}`;
  if (minute.any || minute.step) {
    let every = minute.any ? 'Every minute' : `Every ${minute.step} minutes`;
    if (hour.any) {
      return { repeats: true, phrase: every };
    }
    if (!hour.step && isRun(hour.values)) {
      let hs = hour.values;
      return {
        repeats: true,
        phrase: `${every} ${window(hs[0], hs[hs.length - 1], 0, 59)}`,
      };
    }
    return undefined;
  }
  let minutes = minute.values;
  let pastList =
    minutes.length > 1
      ? {
          label: 'at these points in each hour',
          items: minutes.map(pastTheHour),
        }
      : undefined;
  let hourly = (prefix: string) =>
    minutes.length === 1
      ? minutes[0] === 0
        ? prefix
        : `${prefix}, ${pastTheHour(minutes[0]).toLowerCase()}`
      : `${prefix}, ${times(minutes.length, 'an hour').toLowerCase()}`;
  if (hour.any) {
    return {
      repeats: true,
      phrase:
        minutes.length > 1
          ? times(minutes.length, 'an hour')
          : hourly('Every hour'),
      list: pastList,
    };
  }
  if (hour.step) {
    return {
      repeats: true,
      phrase: hourly(`Every ${hour.step} hours`),
      list: pastList,
    };
  }
  let hours = hour.values;
  if (isRun(hours)) {
    return {
      repeats: true,
      phrase: hourly(
        `Every hour ${window(hours[0], hours[hours.length - 1], minutes[0], minutes[0])}`,
      ),
      list: pastList,
    };
  }
  let all: string[] = [];
  for (let h of hours) {
    for (let m of minutes) {
      all.push(clock(h, m));
    }
  }
  if (all.length === 1) {
    return { repeats: false, phrase: `at ${all[0]}` };
  }
  return {
    repeats: false,
    phrase: times(all.length, 'a day').toLowerCase(),
    list: { label: 'at these times', items: all },
  };
}

// Which days: `phrase` names them when one phrase does ("Every Monday",
// "Weekdays"); several are listed instead, and `phrase` counts them.
interface Days {
  everyDay: boolean;
  phrase: string;
  // The days as a trailing qualifier: "on weekdays", "on Mondays".
  qualifier: string;
  list?: CronDescriptionGroup;
}

function describeDays(dom: Parsed, dow: Parsed): Days | undefined {
  if (dom.step || dow.step) {
    return undefined;
  }
  let weekdayItems = (values: number[]) => values.map((d) => DAYS[d]);
  let dayOfWeek = (): Days => {
    let values = dow.values;
    let key = values.join(',');
    if (key === '1,2,3,4,5') {
      return { everyDay: false, phrase: 'Weekdays', qualifier: 'on weekdays' };
    }
    if (key === '0,6') {
      return { everyDay: false, phrase: 'Weekends', qualifier: 'on weekends' };
    }
    if (values.length === 7) {
      return { everyDay: true, phrase: 'Every day', qualifier: '' };
    }
    // The week wraps, so Friday, Saturday and Sunday are a run too.
    let run = weekRun(values);
    if (run) {
      let range = `${DAYS[run[0]]} through ${DAYS[run[run.length - 1]]}`;
      return { everyDay: false, phrase: range, qualifier: range };
    }
    if (values.length === 1) {
      return {
        everyDay: false,
        phrase: `Every ${DAYS[values[0]]}`,
        qualifier: `on ${DAYS[values[0]]}s`,
      };
    }
    let count = `${values.length} days a week`;
    return {
      everyDay: false,
      phrase: count,
      qualifier: count,
      list: { label: 'on these days', items: weekdayItems(values) },
    };
  };
  let dayOfMonth = (): Days => {
    let values = dom.values;
    if (values.length === 1) {
      let day = `the ${ordinal(values[0])} of the month`;
      return { everyDay: false, phrase: `On ${day}`, qualifier: `on ${day}` };
    }
    let count = `${values.length} days a month`;
    return {
      everyDay: false,
      phrase: count,
      qualifier: count,
      list: {
        label: 'on these days of the month',
        items: values.map((d) => ordinal(d)),
      },
    };
  };
  if (dom.any && dow.any) {
    return { everyDay: true, phrase: 'Every day', qualifier: '' };
  }
  if (dom.any) {
    return dayOfWeek();
  }
  if (dow.any) {
    return dayOfMonth();
  }
  // Both day fields restricted: a day matches if either does.
  return {
    everyDay: false,
    phrase: 'On any of these days',
    qualifier: 'on any of these days',
    list: {
      label: 'on any of these days',
      items: [
        ...dom.values.map((d) => `${ordinal(d)} of the month`),
        ...weekdayItems(dow.values),
      ],
    },
  };
}

function describeMonths(month: Parsed): CronDescriptionGroup | undefined {
  if (month.any) {
    return undefined;
  }
  let values = month.values;
  return {
    label: 'in these months',
    items: isRun(values)
      ? [
          `${MONTHS[values[0] - 1]} through ${MONTHS[values[values.length - 1] - 1]}`,
        ]
      : values.map((m) => MONTHS[m - 1]),
  };
}

export function describeCron(
  expression: string | null | undefined,
): CronDescription | undefined {
  if (typeof expression !== 'string') {
    return undefined;
  }
  let source = expression.trim();
  let expanded = MACROS[source.toLowerCase()] ?? source;
  let fields = expanded.split(/\s+/);
  if (fields.length !== 5) {
    return undefined;
  }
  let minute = parseField(fields[0], 0, 59);
  let hour = parseField(fields[1], 0, 23);
  let dom = parseField(fields[2], 1, 31);
  let month = parseField(fields[3], 1, 12, MONTH_NAMES);
  let dow = parseField(fields[4], 0, 7, DAY_NAMES);
  if (!minute || !hour || !dom || !month || !dow || month.step) {
    return undefined;
  }
  let time = describeTime(minute, hour);
  let days = describeDays(dom, dow);
  if (!time || !days) {
    return undefined;
  }
  let lower = (text: string) => text.charAt(0).toLowerCase() + text.slice(1);
  let upper = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);
  let months = describeMonths(month);
  // One day in one month reads as a date: "On January 1st".
  if (
    months?.items.length === 1 &&
    month.values.length === 1 &&
    dom.values.length === 1 &&
    dow.any &&
    !time.repeats &&
    !time.list
  ) {
    return {
      summary: `On ${MONTHS[month.values[0] - 1]} ${ordinal(dom.values[0])} ${time.phrase}`,
      groups: [],
    };
  }
  let summary: string;
  if (time.repeats) {
    summary = days.everyDay ? time.phrase : `${time.phrase}, ${days.qualifier}`;
  } else if (days.everyDay) {
    summary = time.list ? upper(time.phrase) : `Every day ${time.phrase}`;
  } else if (days.list) {
    summary = `${upper(time.phrase)}, ${lower(days.phrase)}`;
  } else {
    summary = time.list
      ? `${days.phrase}, ${time.phrase}`
      : `${days.phrase} ${time.phrase}`;
  }
  let groups = [time.list, days.list, months].filter(
    (g): g is CronDescriptionGroup => Boolean(g),
  );
  return { summary, groups };
}

// What's wrong with an expression, in words, for an editor to show as the
// author types; undefined when nothing it can see is wrong. It catches the
// common slips (not five fields, firing more often than every
// `minimumMinutes`) and leaves anything subtler to the server, which decides.
export function cronProblem(
  expression: string | null | undefined,
  minimumMinutes = 5,
): string | undefined {
  if (typeof expression !== 'string' || expression.trim() === '') {
    return 'Enter when it runs, such as 0 7 * * MON';
  }
  let source = expression.trim();
  let fields = (MACROS[source.toLowerCase()] ?? source).split(/\s+/);
  if (fields.length !== 5) {
    return 'A cron expression has five fields: minute, hour, day of the month, month and day of the week';
  }
  let minute = parseField(fields[0], 0, 59);
  let hour = parseField(fields[1], 0, 23);
  if (!minute || !hour) {
    return undefined;
  }
  let tooOften = `It can run at most once every ${minimumMinutes} minutes`;
  if (minute.any || (minute.step && minute.step < minimumMinutes)) {
    return tooOften;
  }
  let minutes = minute.step
    ? Array.from(
        { length: Math.ceil(60 / minute.step) },
        (_, i) => i * minute.step!,
      )
    : minute.values;
  for (let i = 1; i < minutes.length; i++) {
    if (minutes[i] - minutes[i - 1] < minimumMinutes) {
      return tooOften;
    }
  }
  // The last minute of one hour and the first of the next.
  let hours = hour.any
    ? Array.from({ length: 24 }, (_, i) => i)
    : hour.step
      ? Array.from(
          { length: Math.ceil(24 / hour.step) },
          (_, i) => i * hour.step!,
        )
      : hour.values;
  let wraps = hours.some((h) => hours.includes(h + 1));
  if (wraps && 60 - minutes[minutes.length - 1] + minutes[0] < minimumMinutes) {
    return tooOften;
  }
  return undefined;
}
