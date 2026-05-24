import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import GeoPointField from '../../../fields/geo-point';
import GeoSearchPointField from '../../../fields/geo-search-point';

import { buildField, renderField } from '../../helpers/field-test-helpers';

export function runTests() {
  module('Rendering | geo fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    // ============================================
    // Geo Point Tests
    // ============================================

    test('geo-point field renders embedded view with coordinates', async function (assert) {
      await renderField(
        GeoPointField,
        buildField(GeoPointField, { lat: 1.3521, lon: 103.8198 }),
      );

      assert
        .dom('[data-test-field-container]')
        .exists('embedded view renders with coordinates');
    });

    test('geo-point field renders edit view', async function (assert) {
      await renderField(
        GeoPointField,
        buildField(GeoPointField, { lat: 1.3521, lon: 103.8198 }),
        'edit',
      );

      assert.dom('[data-test-field-container]').exists('edit view renders');
    });

    test('geo-point field renders with no coordinates', async function (assert) {
      await renderField(GeoPointField, buildField(GeoPointField, {}));

      assert
        .dom('[data-test-field-container]')
        .exists('field renders without coordinates');
    });

    // ============================================
    // Geo Search Point Tests
    // ============================================

    test('geo-search-point field renders embedded view', async function (assert) {
      await renderField(
        GeoSearchPointField,
        buildField(GeoSearchPointField, { searchKey: 'Singapore' }),
      );

      assert.dom('.geo-search-point-embedded').exists('embedded view renders');
    });

    test('geo-search-point field renders edit view', async function (assert) {
      await renderField(
        GeoSearchPointField,
        buildField(GeoSearchPointField, { searchKey: 'Singapore' }),
        'edit',
      );

      assert.dom('[data-test-field-container]').exists('edit view renders');
    });

    test('geo-search-point field renders with no search key', async function (assert) {
      await renderField(
        GeoSearchPointField,
        buildField(GeoSearchPointField, {}),
      );

      assert
        .dom('[data-test-field-container]')
        .exists('field renders without search key');
    });
  });
}
