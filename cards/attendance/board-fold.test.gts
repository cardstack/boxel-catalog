import { module, test } from 'qunit';

import { currentRecords, foldBoard, type BoardPerson } from './board-fold';
import type { LeaveLike } from './leave-days';

// A Wednesday; the 28th is a Saturday.
const SCHEDULE = {
  timezone: 'UTC',
  scheduledArrival: '09:00',
  scheduledDeparture: '17:00',
  graceMinutes: 10,
};
const at = (time: string, day = '2026-11-25') => new Date(`${day}T${time}:00Z`);

function person(
  userId: string,
  punches: BoardPerson['punches'] = [],
  extra: Partial<BoardPerson> = {},
): BoardPerson {
  return {
    id: `rec-${userId}-${extra.year ?? ''}`,
    name: userId,
    userId,
    punches,
    schedule: SCHEDULE,
    ...extra,
  };
}

const punch = (direction: string, time: string) => ({
  direction,
  punchedAt: at(time),
});

const ids = (entries: { id: string }[]) => entries.map((e) => e.id);

export function runTests() {
  module('Unit | today board fold', function () {
    test('people land in the group that matches their day', function (assert) {
      let people = [
        person('in', [punch('in', '08:55')]),
        person('left', [punch('in', '08:00'), punch('out', '08:30')]),
        person('late'),
        person('away'),
      ];
      let leave: LeaveLike[] = [
        {
          userId: 'away',
          ptoType: 'vacation',
          startDate: '2026-11-24',
          endDate: '2026-11-26',
          state: 'approved',
        },
      ];
      let board = foldBoard(people, leave, 'UTC', at('09:30'));
      assert.deepEqual(ids(board.in), ['rec-in-']);
      assert.deepEqual(ids(board.out), ['rec-left-']);
      assert.deepEqual(ids(board.expected), ['rec-late-']);
      assert.strictEqual(board.expected[0].detail, 'Due 09:00 · 30 min late');
      assert.deepEqual(ids(board.onLeave), ['rec-away-']);
      assert.strictEqual(board.onLeave[0].detail, 'Vacation until 2026-11-26');
    });

    test('inside the grace window nobody is expected yet', function (assert) {
      let board = foldBoard([person('early')], [], 'UTC', at('09:05'));
      assert.deepEqual(ids(board.notDue), ['rec-early-']);
      assert.strictEqual(board.expected.length, 0);
    });

    test('weekends expect nobody', function (assert) {
      let board = foldBoard(
        [person('late')],
        [],
        'UTC',
        at('12:00', '2026-11-28'),
      );
      assert.strictEqual(board.expected.length, 0);
      assert.strictEqual(board.notDue.length, 0);
    });

    test('pending and expired leave does not put anyone away', function (assert) {
      let leave: LeaveLike[] = [
        {
          userId: 'late',
          ptoType: 'vacation',
          startDate: '2026-11-25',
          endDate: '2026-11-25',
          state: 'pending',
        },
        {
          userId: 'late',
          ptoType: 'vacation',
          startDate: '2026-11-20',
          endDate: '2026-11-24',
          state: 'approved',
        },
      ];
      let board = foldBoard([person('late')], leave, 'UTC', at('09:30'));
      assert.strictEqual(board.onLeave.length, 0);
      assert.deepEqual(ids(board.expected), ['rec-late-']);
    });

    test('a person with a record for two years appears once, from the latest', function (assert) {
      let old = person('ada', [], { year: '2025' });
      let current = person('ada', [punch('in', '08:55')], { year: '2026' });
      let board = foldBoard([old, current], [], 'UTC', at('09:30'));
      assert.deepEqual(ids(board.in), [current.id]);
      assert.strictEqual(board.expected.length, 0);

      let reversed = foldBoard([current, old], [], 'UTC', at('09:30'));
      assert.deepEqual(ids(reversed.in), [current.id]);
      assert.strictEqual(reversed.expected.length, 0);
    });
  });

  module('Unit | current attendance records', function () {
    test('keeps the latest year per person in first-seen order', function (assert) {
      let records = [
        { id: 'a25', userId: 'ada', year: '2025' },
        { id: 'b26', userId: 'bob', year: '2026' },
        { id: 'a26', userId: 'ada', year: '2026' },
        { id: 'b25', userId: 'bob', year: '2025' },
      ];
      assert.deepEqual(
        currentRecords(records).map((r) => r.id),
        ['a26', 'b26'],
      );
    });

    test('records without a userId stand alone', function (assert) {
      let records = [
        { id: 'x', userId: '', year: '2026' },
        { id: 'y', userId: null, year: '2026' },
      ];
      assert.strictEqual(currentRecords(records).length, 2);
    });
  });
}
