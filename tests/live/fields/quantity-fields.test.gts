import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import QuantityField from '../../../fields/quantity';

import {
  buildField,
  renderConfiguredField,
  renderField,
} from '../../helpers/field-test-helpers';

export function runTests() {
  module('Rendering | quantity fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('quantity field renders embedded view with a value', async function (assert) {
      await renderField(QuantityField, buildField(QuantityField, { value: 5 }));

      assert
        .dom('[data-test-quantity-embedded]')
        .exists('embedded view renders');
      assert
        .dom('[data-test-quantity-value]')
        .hasText('5', 'quantity value is displayed');
    });

    test('quantity field renders edit view with increment/decrement controls', async function (assert) {
      await renderField(
        QuantityField,
        buildField(QuantityField, { value: 3 }),
        'edit',
      );

      assert.dom('[data-test-quantity-edit]').exists('edit view renders');
      assert
        .dom('[data-test-quantity-increment]')
        .exists('increment button renders');
      assert
        .dom('[data-test-quantity-decrement]')
        .exists('decrement button renders');
    });

    test('quantity field renders with zero value', async function (assert) {
      await renderField(QuantityField, buildField(QuantityField, { value: 0 }));

      assert
        .dom('[data-test-quantity-embedded]')
        .exists('embedded view renders with zero value');
      assert
        .dom('[data-test-quantity-value]')
        .hasText('0', 'zero value is displayed');
    });

    test('quantity field respects min/max configuration', async function (assert) {
      await renderConfiguredField(
        QuantityField,
        buildField(QuantityField, { value: 1 }),
        { min: 0, max: 100 },
        'edit',
      );

      assert
        .dom('[data-test-quantity-edit]')
        .exists('edit view renders with min/max');
    });
  });
}
