import { module, skip, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import GeoPointField from './geo-point';

import {
  buildField,
  renderField,
} from '../../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | geo-point fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    skip('geo-point field renders embedded view with coordinates', async function (assert) {
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
  });
}
