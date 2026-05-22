import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { setupCatalogRealm, QRCodeField } from '../helpers/catalog-realm';
import { renderField, buildField } from '../helpers/field-test-helpers';

module('Integration | qr-code fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  // ============================================
  // Basic Rendering Tests
  // ============================================

  test('qr-code field renders embedded view with data', async function (assert) {
    await renderField(
      QRCodeField,
      buildField(QRCodeField, { data: 'https://cardstack.com' }),
    );

    assert.dom('[data-test-qr-svg]').exists('QR SVG is rendered');
  });

  test('qr-code field renders edit view', async function (assert) {
    await renderField(
      QRCodeField,
      buildField(QRCodeField, { data: 'https://cardstack.com' }),
      'edit',
    );

    assert.dom('[data-test-field-container]').exists('edit view renders');
  });

  test('qr-code field renders atom view', async function (assert) {
    await renderField(
      QRCodeField,
      buildField(QRCodeField, { data: 'https://cardstack.com' }),
      'atom',
    );

    assert.dom('[data-test-field-container]').exists('atom view renders');
  });

  // ============================================
  // Empty State Tests
  // ============================================

  test('qr-code field renders with no data', async function (assert) {
    await renderField(QRCodeField, buildField(QRCodeField, {}));

    assert
      .dom('[data-test-field-container]')
      .exists('field renders without data');
  });

  // ============================================
  // Data Encoding Tests
  // ============================================

  test('qr-code renders with URL data', async function (assert) {
    await renderField(
      QRCodeField,
      buildField(QRCodeField, {
        data: 'https://example.com/some/path?query=value',
      }),
    );

    assert.dom('[data-test-qr-svg]').exists('QR SVG renders for URL');
  });

  test('qr-code renders with plain text data', async function (assert) {
    await renderField(
      QRCodeField,
      buildField(QRCodeField, { data: 'Hello, World!' }),
    );

    assert.dom('[data-test-qr-svg]').exists('QR SVG renders for plain text');
  });
});
