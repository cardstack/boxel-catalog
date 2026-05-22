import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import {
  setupCatalogRealm,
  DiscreteRangeField,
} from '../helpers/catalog-realm';
import { renderField, buildField } from '../helpers/field-test-helpers';

module('Integration | discrete range fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  const sampleRangeData = {
    startValue: 2,
    endValue: 8,
    min: 0,
    max: 10,
    interval: 1,
  };

  // ============================================
  // Basic Rendering Tests
  // ============================================

  test('discrete range field renders embedded view', async function (assert) {
    await renderField(
      DiscreteRangeField,
      buildField(DiscreteRangeField, sampleRangeData),
    );

    assert.dom('[data-test-field-container]').exists('embedded view renders');
  });

  test('discrete range field renders edit view', async function (assert) {
    await renderField(
      DiscreteRangeField,
      buildField(DiscreteRangeField, sampleRangeData),
      'edit',
    );

    assert.dom('[data-test-field-container]').exists('edit view renders');
  });

  test('discrete range field renders atom view', async function (assert) {
    await renderField(
      DiscreteRangeField,
      buildField(DiscreteRangeField, sampleRangeData),
      'atom',
    );

    assert.dom('[data-test-field-container]').exists('atom view renders');
  });

  // ============================================
  // Empty State Tests
  // ============================================

  test('discrete range field renders with no values', async function (assert) {
    await renderField(DiscreteRangeField, buildField(DiscreteRangeField, {}));

    assert
      .dom('[data-test-field-container]')
      .exists('field renders without values');
  });

  // ============================================
  // Range Value Tests
  // ============================================

  test('discrete range with single step interval renders', async function (assert) {
    await renderField(
      DiscreteRangeField,
      buildField(DiscreteRangeField, {
        startValue: 0,
        endValue: 5,
        min: 0,
        max: 10,
        interval: 1,
      }),
    );

    assert
      .dom('[data-test-field-container]')
      .exists('range with interval renders');
  });

  test('discrete range with larger step interval renders', async function (assert) {
    await renderField(
      DiscreteRangeField,
      buildField(DiscreteRangeField, {
        startValue: 0,
        endValue: 50,
        min: 0,
        max: 100,
        interval: 10,
      }),
    );

    assert
      .dom('[data-test-field-container]')
      .exists('range with large interval renders');
  });
});
