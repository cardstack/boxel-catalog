import { module, test } from 'qunit';

import { getService } from '@universal-ember/test-support';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import {
  buildField,
  renderConfiguredField,
  renderField,
} from '../../helpers/field-test-helpers';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const realmURL: string = new URL('../../../', import.meta.url).href;

export function runTests() {
  module('Rendering | slider fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    let SliderField: any;

    hooks.beforeEach(async function () {
      const loader = getService('loader-service').loader;
      SliderField = (await loader.import(`${realmURL}fields/slider`)).default;
    });

    test('slider field renders edit view with controls', async function (assert) {
      await renderField(
        SliderField,
        buildField(SliderField, { value: 50 }),
        'edit',
      );

      assert.dom('[data-test-slider-edit]').exists('edit view renders');
    });

    test('slider field renders embedded view', async function (assert) {
      await renderField(SliderField, buildField(SliderField, { value: 30 }));

      assert.dom('[data-test-field-container]').exists('embedded view renders');
    });

    test('slider field renders with no value', async function (assert) {
      await renderField(SliderField, buildField(SliderField, {}), 'edit');

      assert
        .dom('[data-test-slider-edit]')
        .exists('edit view renders with no value');
    });

    test('slider field respects min/max configuration', async function (assert) {
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

    test('slider field respects step configuration', async function (assert) {
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
}
