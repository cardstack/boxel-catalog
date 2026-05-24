import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import RecurringPatternField from '../../../fields/recurring-pattern';

import { buildField, renderField } from '../../helpers/field-test-helpers';

export function runTests() {
  module('Rendering | recurring-pattern fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    const samplePatternData = {
      pattern: 'weekdays',
      startDate: '2026-01-01',
      endDate: '2026-12-31',
      daysOfWeek: '1,2,3,4,5',
      occurrences: 5,
    };

    test('recurring-pattern field renders embedded view', async function (assert) {
      await renderField(
        RecurringPatternField,
        buildField(RecurringPatternField, samplePatternData),
      );

      assert
        .dom('[data-test-recurring-embedded]')
        .exists('embedded view renders');
    });

    test('recurring-pattern field renders edit view', async function (assert) {
      await renderField(
        RecurringPatternField,
        buildField(RecurringPatternField, samplePatternData),
        'edit',
      );

      assert.dom('[data-test-field-container]').exists('edit view renders');
    });

    test('recurring-pattern field renders with no data', async function (assert) {
      await renderField(
        RecurringPatternField,
        buildField(RecurringPatternField, {}),
      );

      assert
        .dom('[data-test-recurring-embedded]')
        .exists('embedded view renders without data');
    });

    test('recurring-pattern field renders daily correctly', async function (assert) {
      await renderField(
        RecurringPatternField,
        buildField(RecurringPatternField, {
          ...samplePatternData,
          pattern: 'daily',
        }),
      );

      assert
        .dom('[data-test-recurring-embedded]')
        .exists('recurring-pattern field renders daily');
    });

    test('recurring-pattern field renders weekly correctly', async function (assert) {
      await renderField(
        RecurringPatternField,
        buildField(RecurringPatternField, {
          ...samplePatternData,
          pattern: 'weekly',
          daysOfWeek: '1',
        }),
      );

      assert
        .dom('[data-test-recurring-embedded]')
        .exists('recurring-pattern field renders weekly');
    });
  });
}
