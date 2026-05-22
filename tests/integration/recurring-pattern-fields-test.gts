import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import {
  setupCatalogRealm,
  RecurringPatternField,
} from '../helpers/catalog-realm';
import { renderField, buildField } from '../helpers/field-test-helpers';

module('Integration | recurring pattern fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  const samplePatternData = {
    pattern: 'weekdays',
    startDate: '2026-01-01',
    endDate: '2026-12-31',
    daysOfWeek: '1,2,3,4,5',
    occurrences: 5,
  };

  // ============================================
  // Basic Rendering Tests
  // ============================================

  test('recurring pattern field renders embedded view', async function (assert) {
    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, samplePatternData),
    );

    assert
      .dom('[data-test-recurring-pattern-embedded]')
      .exists('embedded view renders');
  });

  test('recurring pattern field renders edit view', async function (assert) {
    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, samplePatternData),
      'edit',
    );

    assert
      .dom('[data-test-recurring-pattern-edit]')
      .exists('edit view renders');
  });

  test('recurring pattern field renders atom view', async function (assert) {
    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, samplePatternData),
      'atom',
    );

    assert
      .dom('[data-test-recurring-pattern-atom]')
      .exists('atom view renders');
  });

  // ============================================
  // Empty State Tests
  // ============================================

  test('recurring pattern renders with no data', async function (assert) {
    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, {}),
    );

    assert
      .dom('[data-test-recurring-pattern-embedded]')
      .exists('embedded view renders without data');
  });

  // ============================================
  // Pattern Type Tests
  // ============================================

  test('daily pattern renders correctly', async function (assert) {
    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, {
        ...samplePatternData,
        pattern: 'daily',
      }),
    );

    assert
      .dom('[data-test-recurring-pattern-embedded]')
      .exists('daily pattern renders');
  });

  test('weekly pattern renders correctly', async function (assert) {
    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, {
        ...samplePatternData,
        pattern: 'weekly',
        daysOfWeek: '1',
      }),
    );

    assert
      .dom('[data-test-recurring-pattern-embedded]')
      .exists('weekly pattern renders');
  });
});
