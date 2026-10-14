import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { compareCells } from '../../../components/collection-panel';

export function runTests() {
  module('Integration | Catalog | collection panel sort', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('numbers sort by value, not as text', function (assert) {
      let sorted = [100, 9, 20, 10].sort(compareCells);
      assert.deepEqual(sorted, [9, 10, 20, 100]);
    });

    test('money sorts by amount', function (assert) {
      let sorted = [{ amount: 100 }, { amount: 9.5 }, { amount: 20 }].sort(
        compareCells,
      );
      assert.deepEqual(
        sorted.map((m) => m.amount),
        [9.5, 20, 100],
      );
    });

    test('text sorts with embedded numbers in order', function (assert) {
      let sorted = ['US 10', 'US 9', 'US 11'].sort(compareCells);
      assert.deepEqual(sorted, ['US 9', 'US 10', 'US 11']);
    });

    test('dates sort chronologically', function (assert) {
      let a = new Date('2026-09-01');
      let b = new Date('2026-01-01');
      assert.deepEqual([a, b].sort(compareCells), [b, a]);
    });
  });
}
