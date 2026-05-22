import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { setupCatalogRealm, QuantityField } from '../helpers/catalog-realm';
import {
  renderField,
  renderConfiguredField,
  buildField,
} from '../helpers/field-test-helpers';

module('Integration | quantity fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  // ============================================
  // Basic Rendering Tests
  // ============================================

  test('quantity field renders embedded view with a value', async function (assert) {
    await renderField(QuantityField, buildField(QuantityField, { value: 5 }));

    assert.dom('[data-test-quantity-embedded]').exists('embedded view renders');
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

  test('quantity field renders atom view', async function (assert) {
    await renderField(
      QuantityField,
      buildField(QuantityField, { value: 10 }),
      'atom',
    );

    assert.dom('[data-test-quantity-atom]').exists('atom view renders');
  });

  test('quantity field renders fitted view', async function (assert) {
    await renderField(
      QuantityField,
      buildField(QuantityField, { value: 2 }),
      'fitted',
    );

    assert.dom('[data-test-quantity-fitted]').exists('fitted view renders');
  });

  // ============================================
  // Empty State Tests
  // ============================================

  test('quantity field renders with zero value', async function (assert) {
    await renderField(QuantityField, buildField(QuantityField, { value: 0 }));

    assert
      .dom('[data-test-quantity-embedded]')
      .exists('embedded view renders with zero value');
    assert
      .dom('[data-test-quantity-value]')
      .hasText('0', 'zero value is displayed');
  });

  // ============================================
  // Unit Configuration Tests
  // ============================================

  test('quantity field displays unit when configured', async function (assert) {
    await renderConfiguredField(
      QuantityField,
      buildField(QuantityField, { value: 5 }),
      { unit: 'kg' },
    );

    assert.dom('[data-test-quantity-unit]').hasText('kg', 'unit is displayed');
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
