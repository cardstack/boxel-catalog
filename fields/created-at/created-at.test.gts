import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import CreatedAtField from './created-at';

import { renderField } from '../../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | created-at fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('created-at field renders embedded view with a timestamp', async function (assert) {
      await renderField(CreatedAtField, new Date());

      assert.dom('[data-test-field-container] time').exists('stamp renders');
      assert
        .dom('[data-test-unset-marker]')
        .doesNotExist('no empty marker with a timestamp');
    });

    test('created-at field speaks its empty marker in embedded view', async function (assert) {
      await renderField(CreatedAtField, undefined);

      assert
        .dom('[data-test-unset-marker] [aria-hidden="true"]')
        .hasText('—', 'the dash is hidden from assistive tech');
      assert
        .dom('[data-test-unset-marker] [data-test-pretui-visually-hidden]')
        .hasText('No creation time', 'screen readers hear what is missing')
        .doesNotHaveAttribute('aria-hidden');
    });

    test('created-at field speaks its empty marker in atom view', async function (assert) {
      await renderField(CreatedAtField, undefined, 'atom');

      assert
        .dom('[data-test-unset-marker] [data-test-pretui-visually-hidden]')
        .hasText('No creation time');
    });
  });
}
