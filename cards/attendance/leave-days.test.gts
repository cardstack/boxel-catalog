import { module, test } from 'qunit';

import { leaveBalances, type LeaveLike } from './leave-days';

const YEAR = ['2026-01-01', '2026-12-31'] as const;

function leave(
  ptoType: string,
  startDate: string,
  endDate: string,
  state = 'approved',
): LeaveLike {
  return { userId: 'ada', ptoType, startDate, endDate, state };
}

function balance(requests: LeaveLike[], type = 'vacation', year = YEAR) {
  let allowances = { vacation: 10, sick: 5, personal: 2 };
  return leaveBalances(allowances, requests, year[0], year[1]).find(
    (b) => b.type === type,
  )!;
}

export function runTests() {
  module('Unit | leave balances', function () {
    test('days are counted inclusively per type', function (assert) {
      let vacation = balance([
        leave('vacation', '2026-03-02', '2026-03-04'),
        leave('sick', '2026-03-10', '2026-03-10'),
      ]);
      assert.strictEqual(vacation.used, 3);
      assert.strictEqual(vacation.remaining, 7);
      assert.strictEqual(
        balance([leave('sick', '2026-03-10', '2026-03-10')], 'sick').used,
        1,
      );
    });

    test('overlapping requests count a day once', function (assert) {
      let used = balance([
        leave('vacation', '2026-03-02', '2026-03-04'),
        leave('vacation', '2026-03-04', '2026-03-06'),
      ]).used;
      assert.strictEqual(used, 5);
    });

    test('only approved leave counts', function (assert) {
      let used = balance([
        leave('vacation', '2026-03-02', '2026-03-02', 'pending'),
        leave('vacation', '2026-03-03', '2026-03-03', 'declined'),
        leave('vacation', '2026-03-04', '2026-03-04'),
      ]).used;
      assert.strictEqual(used, 1);
    });

    test('leave counts toward the year it starts in', function (assert) {
      let used = balance([
        leave('vacation', '2025-12-31', '2026-01-02'),
        leave('vacation', '2026-12-30', '2027-01-02'),
        leave('vacation', '2027-01-01', '2027-01-01'),
      ]).used;
      assert.strictEqual(used, 4);
    });

    test('a year with no bounds counts everything', function (assert) {
      let [vacation] = leaveBalances({ vacation: 10 }, [
        leave('vacation', '2025-12-31', '2025-12-31'),
        leave('vacation', '2027-01-01', '2027-01-01'),
      ]);
      assert.strictEqual(vacation.used, 2);
    });

    test('a leap day is a day', function (assert) {
      let leap = ['2028-01-01', '2028-12-31'] as const;
      assert.strictEqual(
        balance(
          [leave('vacation', '2028-02-28', '2028-03-01')],
          'vacation',
          leap,
        ).used,
        3,
      );
      assert.strictEqual(
        balance([leave('vacation', '2026-02-28', '2026-03-01')]).used,
        2,
      );
    });

    test('a missing allowance is zero and an inverted range counts nothing', function (assert) {
      let [vacation] = leaveBalances(null, [
        leave('vacation', '2026-03-05', '2026-03-02'),
      ]);
      assert.strictEqual(vacation.allowed, 0);
      assert.strictEqual(vacation.used, 0);
    });
  });
}
