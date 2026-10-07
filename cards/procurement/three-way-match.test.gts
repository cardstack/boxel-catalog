import { module, test } from 'qunit';

import {
  matchLines,
  openVarianceCount,
  resolutionFor,
} from './three-way-match';
import { statusPath } from '../commerce/payment-status-field';

function line(description: string, quantity: number, amount: number) {
  return { description, quantity, unitPrice: { amount } };
}

export function runTests() {
  module('Unit | three-way match', function () {
    test('a line wrong on quantity and price reports both', function (assert) {
      let [row] = matchLines(
        [line('Chair', 10, 100)],
        [12],
        [line('Chair', 12, 150)],
      );
      assert.strictEqual(row.state, 'qty-and-price-variance');
      assert.strictEqual(
        row.detail,
        'invoiced 12, ordered 10; unit 150 vs PO 100',
      );
      assert.strictEqual(
        row.varianceAmount,
        12 * 150 - 10 * 100,
        'everything above 10 at the PO price',
      );
    });

    test('a price-only variance keeps its amount', function (assert) {
      let [row] = matchLines(
        [line('Chair', 12, 400)],
        [12],
        [line('Chair', 12, 425)],
      );
      assert.strictEqual(row.state, 'price-variance');
      assert.strictEqual(row.varianceAmount, 300);
    });

    test('a resolution follows its line when lines move, and lapses when the variance changes', function (assert) {
      let po = [line('Desk', 2, 300), line('Chair', 10, 100)];
      let received = [2, 10];
      let resolution = {
        lineNumber: 2,
        lineKey: 'chair',
        variance: 'unit 150 vs PO 100',
        action: 'accept',
      };

      let reordered = matchLines(
        po,
        received,
        [line('Chair', 10, 150), line('Desk', 2, 300)],
        [resolution],
      );
      assert.strictEqual(reordered[0].state, 'resolved', 'Chair, now line 1');
      assert.strictEqual(reordered[1].state, 'clean', 'Desk, now line 2');

      let repriced = matchLines(
        po,
        received,
        [line('Desk', 2, 300), line('Chair', 10, 180)],
        [resolution],
      );
      assert.strictEqual(
        repriced[1].state,
        'price-variance',
        'a new price needs a new decision',
      );
      assert.strictEqual(openVarianceCount(repriced), 1);
    });
  });

  module('Unit | three-way match identity and currency', function () {
    test('repeated descriptions get their own keys, so one decision resolves one line', function (assert) {
      let po = [line('Chair', 2, 100), line('Chair', 2, 100)];
      let inv = [line('Chair', 3, 100), line('Chair', 3, 100)];
      let rows = matchLines(po, [3, 3], inv, [
        {
          lineKey: 'chair',
          variance: 'invoiced 3, ordered 2',
          action: 'accept',
        },
      ]);
      assert.deepEqual(
        rows.map((r) => r.key),
        ['chair', 'chair#2'],
      );
      assert.deepEqual(
        rows.map((r) => r.state),
        ['resolved', 'qty-variance'],
      );
    });

    test('the latest decision for a line stands', function (assert) {
      let rows = matchLines(
        [line('Chair', 10, 100)],
        [10],
        [line('Chair', 10, 150)],
      );
      let decisions = [
        { lineKey: 'chair', action: 'accept' },
        { lineKey: 'chair', action: 'short-pay' },
      ];
      assert.strictEqual(
        resolutionFor(rows[0], decisions)?.action,
        'short-pay',
      );
    });

    test('lines in different currencies are never clean', function (assert) {
      let [row] = matchLines(
        [
          {
            description: 'Desk',
            quantity: 1,
            unitPrice: { amount: 300, currency: { code: 'USD' } },
          },
        ],
        [1],
        [
          {
            description: 'Desk',
            quantity: 1,
            unitPrice: { amount: 300, currency: { code: 'EUR' } },
          },
        ],
      );
      assert.strictEqual(row.state, 'currency-variance');
      assert.strictEqual(row.detail, 'invoiced in EUR, PO in USD');
    });
  });

  module('Unit | payment status path', function () {
    test('a received vendor invoice walks through the match to approval', function (assert) {
      assert.deepEqual(statusPath('received', 'approved-for-payment'), [
        'matching',
        'matched',
        'approved-for-payment',
      ]);
      assert.deepEqual(statusPath('exception', 'matching'), ['matching']);
      assert.deepEqual(
        statusPath('matched', 'exception'),
        ['matching', 'exception'],
        'a matched invoice whose documents changed can go back to exception',
      );
    });

    test('terminal and sell-side statuses have no path into the match', function (assert) {
      assert.strictEqual(statusPath('paid', 'matching'), undefined);
      assert.strictEqual(statusPath('sent', 'approved-for-payment'), undefined);
      assert.strictEqual(statusPath(undefined, 'matching'), undefined);
    });
  });
}
