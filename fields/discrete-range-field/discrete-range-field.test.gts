import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import DiscreteRangeField from './discrete-range-field';

import {
  buildField,
  renderField,
} from '../../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | discrete-range fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    const sampleRangeData = {
      startValue: 2,
      endValue: 8,
      min: 0,
      max: 10,
      interval: 1,
    };

    test('discrete-range field renders embedded view with values', async function (assert) {
      await renderField(
        DiscreteRangeField,
        buildField(DiscreteRangeField, sampleRangeData),
      );

      assert
        .dom('[data-test-discrete-range-embedded]')
        .exists('embedded view renders');
      assert
        .dom('[data-test-discrete-range-value]')
        .hasText('2 - 8', 'range start and end are displayed');
    });

    test('discrete-range field renders edit view', async function (assert) {
      await renderField(
        DiscreteRangeField,
        buildField(DiscreteRangeField, sampleRangeData),
        'edit',
      );

      assert.dom('[data-test-discrete-range-edit]').exists('edit view renders');
    });

    test('discrete-range field renders with no values', async function (assert) {
      await renderField(DiscreteRangeField, buildField(DiscreteRangeField, {}));

      assert
        .dom('[data-test-field-container]')
        .exists('field renders without crashing when no value supplied');
    });

    test('discrete-range field with single step interval renders', async function (assert) {
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
        .dom('[data-test-discrete-range-value]')
        .hasText('0 - 5', 'displays small range');
    });

    test('discrete-range field with larger step interval renders', async function (assert) {
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
        .dom('[data-test-discrete-range-value]')
        .hasText('0 - 50', 'displays large range');
    });
  });
}
