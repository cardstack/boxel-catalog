import { module, test } from 'qunit';

import { getService } from '@universal-ember/test-support';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { buildField, renderField } from '../../helpers/field-test-helpers';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const realmURL: string = new URL('../../../', import.meta.url).href;

export function runTests() {
  module('Rendering | geo fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    let GeoPointField: any;
    let GeoSearchPointField: any;

    hooks.beforeEach(async function () {
      const loader = getService('loader-service').loader;
      [GeoPointField, GeoSearchPointField] = await Promise.all([
        loader
          .import(`${realmURL}fields/geo-point`)
          .then((m: any) => m.default),
        loader
          .import(`${realmURL}fields/geo-search-point`)
          .then((m: any) => m.default),
      ]);
    });

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
