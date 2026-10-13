import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';

import { formatMoneyDelta } from '../../../cards/collectibles/money-format';
import { computeCompletion } from '../../../cards/collectibles/completion-set';
import {
  ProductReturn,
  ReturnItemField,
} from '../../../cards/fulfilment/product-return';
import { FulfilmentProduct } from '../../../cards/fulfilment/fulfilment-product';

function amount(value: number, code: string) {
  return new AmountWithCurrency({
    amount: value,
    currency: new CurrencyField({ code }),
  });
}

function line(value: number, code: string, quantity = 1) {
  return new ReturnItemField({ quantity, unitPrice: amount(value, code) });
}

export function runTests() {
  module('Integration | Catalog | currency guards', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('formatMoneyDelta compares only amounts in one currency', function (assert) {
      let same = formatMoneyDelta(
        { amount: 180, currency: { code: 'USD' } },
        { amount: 200, currency: { code: 'usd' } },
      );
      assert.strictEqual(same?.direction, 'down');
      assert.strictEqual(same?.percent, '−10%');

      assert.strictEqual(
        formatMoneyDelta(
          { amount: 180, currency: { code: 'EUR' } },
          { amount: 200, currency: { code: 'USD' } },
        ),
        null,
        'no delta across currencies',
      );
    });

    test('a return priced in one currency totals and refunds', function (assert) {
      let rma = new ProductReturn({
        lineItems: [line(100, 'USD'), line(50, 'USD', 2)],
      });
      assert.false(rma.mixedCurrency);
      assert.strictEqual(rma.itemsValue?.amount, 200);
      assert.strictEqual(rma.currencyCode, 'USD');
    });

    test('a return priced in two currencies has no total or refund', function (assert) {
      let rma = new ProductReturn({
        lineItems: [line(100, 'USD'), line(100, 'GBP')],
      });
      assert.true(rma.mixedCurrency);
      assert.strictEqual(rma.itemsValue?.amount, undefined);
      assert.strictEqual(rma.restockingFee?.amount, undefined);
      assert.strictEqual(rma.refundAmount?.amount, undefined);
    });

    test('a product has no margin when cost and price differ in currency', function (assert) {
      let sameCurrency = new FulfilmentProduct({
        cost: amount(60, 'GBP'),
        price: amount(100, 'GBP'),
      });
      assert.strictEqual(sameCurrency.marginPercent, 40);

      let mixed = new FulfilmentProduct({
        cost: amount(60, 'USD'),
        price: amount(100, 'GBP'),
      });
      assert.strictEqual(mixed.marginPercent, undefined);
    });

    test('computeCompletion honours own-any and own-all', function (assert) {
      let products = [
        { id: 'p1', variants: ['9', '10'] },
        { id: 'p2', variants: [] },
      ];
      let owned = [
        { productId: 'p1', variant: '9' },
        { productId: 'p2', variant: null },
      ];
      assert.strictEqual(
        computeCompletion(products, owned, 'own-any').ownedCount,
        2,
      );
      let all = computeCompletion(products, owned, 'own-all');
      assert.strictEqual(all.ownedCount, 1);
      assert.deepEqual(all.missingProductIds, ['p1']);
      assert.strictEqual(
        computeCompletion(
          products,
          [...owned, { productId: 'p1', variant: ' 10 ' }],
          'own-all',
        ).ownedCount,
        2,
        'variant labels match after trimming',
      );
    });
  });
}
