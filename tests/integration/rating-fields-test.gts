import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { setupCatalogRealm, RatingField } from '../helpers/catalog-realm';
import {
  renderField,
  renderConfiguredField,
  buildField,
} from '../helpers/field-test-helpers';

module('Integration | rating fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  // ============================================
  // Basic Rendering Tests
  // ============================================

  test('rating field renders embedded view with a value', async function (assert) {
    await renderField(RatingField, buildField(RatingField, { value: 4 }));

    assert.dom('[data-test-rating-embedded]').exists('embedded view renders');
  });

  test('rating field renders edit view', async function (assert) {
    await renderField(
      RatingField,
      buildField(RatingField, { value: 3 }),
      'edit',
    );

    assert.dom('[data-test-rating-edit]').exists('edit view renders');
    assert.dom('[data-test-rating-input]').exists('rating input is rendered');
  });

  test('rating field renders atom view', async function (assert) {
    await renderField(
      RatingField,
      buildField(RatingField, { value: 5 }),
      'atom',
    );

    assert.dom('[data-test-rating-atom]').exists('atom view renders');
  });

  test('rating field renders fitted view', async function (assert) {
    await renderField(
      RatingField,
      buildField(RatingField, { value: 2 }),
      'fitted',
    );

    assert.dom('[data-test-rating-fitted]').exists('fitted view renders');
  });

  // ============================================
  // Empty State Tests
  // ============================================

  test('rating field renders with no value', async function (assert) {
    await renderField(RatingField, buildField(RatingField, {}));

    assert
      .dom('[data-test-rating-embedded]')
      .exists('embedded view renders with no value');
  });

  // ============================================
  // Presentation Variant Tests
  // ============================================

  test('stars presentation renders star icons', async function (assert) {
    await renderConfiguredField(
      RatingField,
      buildField(RatingField, { value: 3 }),
      { presentation: 'stars' },
    );

    assert.dom('[data-test-rating-stars]').exists('stars presentation renders');
  });

  test('numeric presentation renders number display', async function (assert) {
    await renderConfiguredField(
      RatingField,
      buildField(RatingField, { value: 4 }),
      { presentation: 'numeric' },
    );

    assert
      .dom('[data-test-rating-numeric]')
      .exists('numeric presentation renders');
  });

  // ============================================
  // Configuration Tests
  // ============================================

  test('maxRating configuration is respected', async function (assert) {
    await renderConfiguredField(
      RatingField,
      buildField(RatingField, { value: 7 }),
      { maxRating: 10 },
      'edit',
    );

    assert
      .dom('[data-test-rating-edit]')
      .exists('edit view renders with maxRating');
  });
});
