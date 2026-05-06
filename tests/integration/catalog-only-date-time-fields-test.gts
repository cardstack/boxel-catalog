import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import {
  setupCatalogRealm,
  TimePeriodField,
  RecurringPatternField,
} from '../helpers/catalog-realm';
import { renderField, buildField } from '../helpers/field-test-helpers';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

module('Integration | catalog-only date-time fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  test('recurring pattern summarizes the configured schedule', async function (assert) {
    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, {
        pattern: 'weekly',
        startDate: '2024-05-01',
        endDate: '2024-06-01',
      }),
    );
    assert
      .dom('[data-test-recurring-embedded]')
      .hasTextContaining(
        'Weekly',
        'recurring pattern summarizes the configured schedule',
      );
  });

  test('time-period field renders correctly', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Q2 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').exists();
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Q2 2024');

    await renderField(TimePeriodField, buildField(TimePeriodField, {}));
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining('No period set');

    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Q2 2024',
      }),
      'atom',
    );
    assert.dom('[data-test-time-period-atom]').exists();
    assert.dom('[data-test-time-period-atom]').hasTextContaining('Q2 2024');
  });

  test('time-period field recognizes calendar year format', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: '2024',
      }),
    );
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining('Calendar Year');
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('2024');
  });

  test('time-period field recognizes fiscal year format', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: '2023-2024',
      }),
    );
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining('Fiscal Year');
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining('2023-2024');

    // Short format
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: '2023-24',
      }),
    );
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining('Fiscal Year');
  });

  test('time-period field recognizes quarter format', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Q1 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Quarter');
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Q1 2024');

    // Reverse format
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: '2024 Q3',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Quarter');
  });

  test('time-period field recognizes month format', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'January 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Month');

    // Abbreviated
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Jan 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Month');

    // With period
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Feb. 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Month');
  });

  test('time-period field recognizes week format', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Week 12 2025',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Week');

    // Abbreviated format
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Wk12 2025',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Week');

    // Reverse format
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: '2025 Wk12',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Week');
  });

  test('time-period field recognizes session format', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Fall 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Session');

    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Spring 2025',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Session');

    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Summer 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Session');
  });

  test('time-period field recognizes session week format', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Wk4 Spring 2025',
      }),
    );
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining('Session Week');
  });

  test('time-period field auto-normalizes partial inputs with current year', async function (assert) {
    const currentYear = new Date().getFullYear().toString();

    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Q1',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Quarter');
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining(currentYear);

    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'March',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Month');
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining(currentYear);

    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Fall',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Session');
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining(currentYear);

    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Week 12',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Week');
    assert
      .dom('[data-test-time-period-embedded]')
      .hasTextContaining(currentYear);
  });

  test('time-period field displays date range for recognized formats', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Q2 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Apr');
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('Jun');

    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'May 2024',
      }),
    );
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('May 1');
    assert.dom('[data-test-time-period-embedded]').hasTextContaining('31');
  });

  test('time-period field edit mode allows custom input', async function (assert) {
    await renderField(
      TimePeriodField,
      buildField(TimePeriodField, {
        periodLabel: 'Q3 2024',
      }),
      'edit',
    );
    assert.dom('[data-test-time-period-input]').exists();
    assert.dom('[data-test-time-period-input]').hasValue('Q3 2024');
  });

  test('recurring pattern field displays pattern details', async function (assert) {
    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, {
        pattern: 'daily',
        startDate: '2024-05-01',
        endDate: '2024-05-31',
      }),
    );
    assert.dom('[data-test-recurring-embedded]').hasTextContaining('Daily');

    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, {
        pattern: 'monthly',
        startDate: '2024-05-01',
      }),
    );
    assert.dom('[data-test-recurring-embedded]').hasTextContaining('Monthly');

    await renderField(
      RecurringPatternField,
      buildField(RecurringPatternField, {
        pattern: 'custom',
        interval: 2,
        unit: 'days',
        startDate: '2024-05-01',
      }),
    );
    assert
      .dom('[data-test-recurring-embedded]')
      .hasTextContaining('Every 2 days');
  });
});
