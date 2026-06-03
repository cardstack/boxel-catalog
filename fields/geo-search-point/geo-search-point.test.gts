import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import GeoSearchPointField from './geo-search-point';

import {
  buildField,
  renderField,
} from '../../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | geo-search-point fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

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
