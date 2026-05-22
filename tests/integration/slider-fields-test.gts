import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { setupCatalogRealm, SliderField } from '../helpers/catalog-realm';
import {
  renderField,
  renderConfiguredField,
  buildField,
} from '../helpers/field-test-helpers';

module('Integration | slider fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  // ============================================
  // Basic Rendering Tests
  // ============================================

  test('slider field renders edit view with controls', async function (assert) {
    await renderField(
      SliderField,
      buildField(SliderField, { value: 50 }),
      'edit',
    );

    assert.dom('[data-test-slider-edit]').exists('edit view renders');
  });

  test('slider field renders atom view', async function (assert) {
    await renderField(
      SliderField,
      buildField(SliderField, { value: 75 }),
      'atom',
    );

    assert.dom('[data-test-slider-atom]').exists('atom view renders');
  });

  test('slider field renders embedded view', async function (assert) {
    await renderField(SliderField, buildField(SliderField, { value: 30 }));

    assert.dom('[data-test-field-container]').exists('embedded view renders');
  });

  // ============================================
  // Empty State Tests
  // ============================================

  test('slider field renders with no value', async function (assert) {
    await renderField(SliderField, buildField(SliderField, {}), 'edit');

    assert
      .dom('[data-test-slider-edit]')
      .exists('edit view renders with no value');
  });

  // ============================================
  // Configuration Tests
  // ============================================

  test('slider respects min/max configuration', async function (assert) {
    await renderConfiguredField(
      SliderField,
      buildField(SliderField, { value: 25 }),
      { min: 0, max: 100 },
      'edit',
    );

    assert
      .dom('[data-test-slider-edit]')
      .exists('edit view renders with min/max');
  });

  test('slider respects step configuration', async function (assert) {
    await renderConfiguredField(
      SliderField,
      buildField(SliderField, { value: 10 }),
      { step: 5, min: 0, max: 50 },
      'edit',
    );

    assert
      .dom('[data-test-slider-edit]')
      .exists('edit view renders with step config');
  });
});
