import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import DueDateField from './due-date';

import { renderField } from '../../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | due-date fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('due-date field renders embedded view with a date', async function (assert) {
      await renderField(DueDateField, new Date());

      assert.dom('[data-test-field-container] time').exists('date renders');
      assert
        .dom('[data-test-unset-marker]')
        .doesNotExist('no empty marker with a date');
    });

    test('due-date field speaks its empty marker in embedded view', async function (assert) {
      await renderField(DueDateField, undefined);

      assert
        .dom('[data-test-unset-marker] [aria-hidden="true"]')
        .hasText('—', 'the dash is hidden from assistive tech');
      assert
        .dom('[data-test-unset-marker] [data-test-pretui-visually-hidden]')
        .hasText('No due date', 'screen readers hear what is missing')
        .doesNotHaveAttribute('aria-hidden');
    });

    test('due-date field speaks its empty marker in atom view', async function (assert) {
      await renderField(DueDateField, undefined, 'atom');

      assert
        .dom('[data-test-unset-marker] [data-test-pretui-visually-hidden]')
        .hasText('No due date');
    });
  });
}
