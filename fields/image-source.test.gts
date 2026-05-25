import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import ImageSourceField from './image-source';

import { buildField, renderField } from '../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | image-source fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    // --- embedded ---

    test('image-source field embedded renders img when url is set', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, {
          url: 'https://images.pexels.com/photos/414171/pexels-photo-414171.jpeg',
          sourceMode: 'url',
        }),
      );

      assert
        .dom('[data-test-image-source-embedded]')
        .exists('embedded view renders img element');
      assert
        .dom('[data-test-image-source-embedded]')
        .hasAttribute(
          'src',
          'https://images.pexels.com/photos/414171/pexels-photo-414171.jpeg',
          'img src matches resolved url',
        );
    });

    test('image-source field embedded renders nothing when no data', async function (assert) {
      await renderField(ImageSourceField, buildField(ImageSourceField, {}));

      assert
        .dom('[data-test-image-source-embedded]')
        .doesNotExist('no img rendered without url or file');
    });

    // --- edit ---

    test('image-source field edit renders editor', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, {
          url: 'https://example.com/photo.jpg',
          sourceMode: 'url',
        }),
        'edit',
      );

      assert
        .dom('[data-test-image-source-edit]')
        .exists('edit root wrapper renders');
      assert
        .dom('[data-test-image-source-editor]')
        .exists('editor component renders');
    });

    test('image-source field edit defaults to file tab when no sourceMode or url', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, {}),
        'edit',
      );

      assert
        .dom('[data-test-image-source-file-tab]')
        .hasAttribute('aria-selected', 'true', 'file tab active by default');
      assert
        .dom('[data-test-image-source-url-tab]')
        .hasAttribute('aria-selected', 'false', 'url tab inactive');
      assert
        .dom('[data-test-image-source-file-panel]')
        .exists('file panel shown');
    });

    test('image-source field edit shows url tab active when sourceMode is url', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, {
          url: 'https://example.com/photo.jpg',
          sourceMode: 'url',
        }),
        'edit',
      );

      assert
        .dom('[data-test-image-source-url-tab]')
        .hasAttribute('aria-selected', 'true', 'url tab active');
      assert
        .dom('[data-test-image-source-url-panel]')
        .exists('url panel shown');
    });

    test('image-source field edit url panel shows preview when url is set', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, {
          url: 'https://example.com/photo.jpg',
          sourceMode: 'url',
        }),
        'edit',
      );

      assert
        .dom('[data-test-image-source-url-preview]')
        .exists('url preview renders when url is set');
    });

    test('image-source field edit url panel shows empty state when no url', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, { sourceMode: 'url' }),
        'edit',
      );

      assert
        .dom('[data-test-image-source-url-preview]')
        .doesNotExist('no preview when url is empty');
      assert
        .dom('[data-test-image-source-url-input]')
        .exists('url input present');
    });

    test('image-source field edit shows file picker when sourceMode is file and no file linked', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, { sourceMode: 'file' }),
        'edit',
      );

      assert
        .dom('[data-test-image-source-file-panel]')
        .exists('file panel renders');
      assert
        .dom('[data-test-image-source-file-field]')
        .exists('file picker shown when no file linked');
    });
  });
}
