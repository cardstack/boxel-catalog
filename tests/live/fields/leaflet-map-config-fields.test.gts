import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import LeafletMapConfigField from '../../../fields/leaflet-map-config-field';

import { buildField, renderField } from '../../helpers/field-test-helpers';

export function runTests() {
  module('Rendering | leaflet-map-config fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('leaflet-map-config field atom shows custom tileserver when configured', async function (assert) {
      await renderField(
        LeafletMapConfigField,
        buildField(LeafletMapConfigField, {
          tileserverUrl: 'https://tile.example.com/{z}/{x}/{y}.png',
        }),
        'atom',
      );

      assert
        .dom('.map-config-display .config-info')
        .hasText(
          'Custom tileserver: https://tile.example.com/{z}/{x}/{y}.png',
          'custom tileserver URL is displayed',
        );
    });

    test('leaflet-map-config field atom falls back to default when no tileserver set', async function (assert) {
      await renderField(
        LeafletMapConfigField,
        buildField(LeafletMapConfigField, {}),
        'atom',
      );

      assert
        .dom('.map-config-display .config-info')
        .hasText(
          'Default map settings',
          'default message when no tileserver configured',
        );
    });

    test('leaflet-map-config field embedded renders the edit template', async function (assert) {
      await renderField(
        LeafletMapConfigField,
        buildField(LeafletMapConfigField, {
          tileserverUrl: 'https://tile.example.com/{z}/{x}/{y}.png',
        }),
      );

      assert.dom('.edit-template').exists('embedded uses edit template');
      assert
        .dom('.section-title')
        .hasText('Map Configuration', 'section title is shown');
    });
  });
}
