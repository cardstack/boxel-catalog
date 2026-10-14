import { module, test } from 'qunit';

import {
  dayKey,
  nextCalendarOccurrence,
  nextOccurrence,
} from '../../../cards/maintenance/utils/recurrence';

const day = (s: string) => {
  let [y, m, d] = s.split('-').map(Number);
  return new Date(y!, m! - 1, d!);
};
const key = (d: Date | undefined) => (d ? dayKey(d) : undefined);

export function runTests() {
  module('Catalog | maintenance - recurrence', function () {
    test('monthly on a fixed day stays in the anchor month when the day is ahead', function (assert) {
      let next = nextCalendarOccurrence(
        { pattern: 'monthly', interval: 1, dayOfMonth: 15 },
        '2026-03-10',
      );
      assert.strictEqual(key(next), '2026-03-15');
    });

    test('monthly on a fixed day clamps to the last day of a short month', function (assert) {
      let next = nextCalendarOccurrence(
        { pattern: 'monthly', interval: 1, dayOfMonth: 31 },
        '2026-01-31',
      );
      assert.strictEqual(key(next), '2026-02-28');
    });

    test('monthly on the last day (-1) lands on each month end', function (assert) {
      let next = nextCalendarOccurrence(
        { pattern: 'monthly', interval: 1, dayOfMonth: -1 },
        '2026-02-28',
      );
      assert.strictEqual(key(next), '2026-03-31');
    });

    test('monthly without a day repeats the start date’s day', function (assert) {
      let next = nextCalendarOccurrence(
        { pattern: 'monthly', interval: 1, startDate: '2026-01-20' },
        '2026-01-20',
      );
      assert.strictEqual(key(next), '2026-02-20');
    });

    test('a rule past its end date has no next occurrence', function (assert) {
      let next = nextCalendarOccurrence(
        { pattern: 'daily', interval: 1, endDate: '2026-05-10' },
        '2026-05-10',
      );
      assert.strictEqual(next, undefined);
    });

    test('a rule that has used its occurrences has no next occurrence', function (assert) {
      let rule = { pattern: 'weekly', interval: 1, occurrences: 3 };
      assert.ok(nextCalendarOccurrence(rule, '2026-05-01', 2));
      assert.strictEqual(
        nextCalendarOccurrence(rule, '2026-05-01', 3),
        undefined,
      );
    });

    test('whichever-first is due when the meter arrives before the calendar', function (assert) {
      let n = nextOccurrence(
        {
          calendar: { pattern: 'monthly', interval: 3, dayOfMonth: 1 },
          meterThreshold: 500,
          whicheverFirst: true,
        },
        '2026-06-01',
        { today: day('2026-07-01'), meterAtAnchor: 1000, meterNow: 1600 },
      );
      assert.strictEqual(key(n.dueDate), '2026-09-01');
      assert.strictEqual(n.dueMeter, 1500);
      assert.strictEqual(n.decidedBy, 'meter');
      assert.true(n.isDue);
    });

    test('both-required is not due until the calendar arrives too', function (assert) {
      let n = nextOccurrence(
        {
          calendar: { pattern: 'monthly', interval: 3, dayOfMonth: 1 },
          meterThreshold: 500,
          whicheverFirst: false,
        },
        '2026-06-01',
        { today: day('2026-07-01'), meterAtAnchor: 1000, meterNow: 1600 },
      );
      assert.strictEqual(n.decidedBy, 'calendar');
      assert.false(n.isDue);
    });

    test('a meter-only rule is due on its meter with no due date', function (assert) {
      let n = nextOccurrence({ meterThreshold: 500 }, undefined, {
        today: day('2026-07-01'),
        meterAtAnchor: 4000,
        meterNow: 4600,
      });
      assert.strictEqual(n.dueDate, undefined);
      assert.strictEqual(n.dueMeter, 4500);
      assert.strictEqual(n.meterRemaining, -100);
      assert.strictEqual(n.decidedBy, 'meter');
      assert.true(n.isDue);
    });

    test('lead days move the generate date ahead of the due date', function (assert) {
      let n = nextOccurrence(
        {
          calendar: { pattern: 'monthly', interval: 1, dayOfMonth: 20 },
          leadDays: 5,
        },
        '2026-07-01',
        { today: day('2026-07-01') },
      );
      assert.strictEqual(key(n.dueDate), '2026-07-20');
      assert.strictEqual(key(n.generateOn), '2026-07-15');
      assert.strictEqual(n.daysUntil, 19);
      assert.false(n.isDue);
    });
  });
}
