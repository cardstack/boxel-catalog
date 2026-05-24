import { module, test } from 'qunit';

import { getService } from '@universal-ember/test-support';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { buildField, renderField } from '../../helpers/field-test-helpers';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const realmURL: string = new URL('../../../', import.meta.url).href;

export function runTests() {
  module('Rendering | qr-code fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    let QRCodeField: any;

    hooks.beforeEach(async function () {
      const loader = getService('loader-service').loader;
      QRCodeField = (await loader.import(`${realmURL}fields/qr-code`)).default;
    });

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
