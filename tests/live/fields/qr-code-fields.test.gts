import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import QRCodeField from '../../../fields/qr-code';

import { buildField, renderField } from '../../helpers/field-test-helpers';

export function runTests() {
  module('Rendering | qr-code fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('qr-code field renders embedded view with data', async function (assert) {
      await renderField(
        QRCodeField,
        buildField(QRCodeField, { data: 'https://cardstack.com' }),
      );

      assert.dom('[data-test-qr-svg]').exists('QR SVG is rendered');
    });

    test('qr-code field renders with no data', async function (assert) {
      await renderField(QRCodeField, buildField(QRCodeField, {}));

      assert
        .dom('[data-test-field-container]')
        .exists('field renders without data');
    });

    test('qr-code field renders with URL data', async function (assert) {
      await renderField(
        QRCodeField,
        buildField(QRCodeField, {
          data: 'https://example.com/some/path?query=value',
        }),
      );

      assert.dom('[data-test-qr-svg]').exists('QR SVG renders for URL');
    });

    test('qr-code field renders with plain text data', async function (assert) {
      await renderField(
        QRCodeField,
        buildField(QRCodeField, { data: 'Hello, World!' }),
      );

      assert.dom('[data-test-qr-svg]').exists('QR SVG renders for plain text');
    });
  });
}
