import { module, test } from 'qunit';

import { orderTotals, outstandingBalance } from './line-item-totals';

export function runTests() {
  module('Unit | line item totals', function () {
    test('orderTotals adds tax on the subtotal', function (assert) {
      let t = orderTotals(
        [{ quantity: 2, unitPrice: { amount: 50 } }],
        10,
      );
      assert.strictEqual(t.subtotal, 100);
      assert.strictEqual(t.total, 110);
    });

    test('outstandingBalance never goes below zero', function (assert) {
      let items = [{ quantity: 1, unitPrice: { amount: 40 } }];
      assert.strictEqual(
        outstandingBalance(items, [{ amount: { amount: 15 } }]),
        25,
      );
      assert.strictEqual(
        outstandingBalance(items, [{ amount: { amount: 90 } }]),
        0,
      );
    });
  });
}
