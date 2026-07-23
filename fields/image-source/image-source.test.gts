import { click, fillIn } from '@ember/test-helpers';
import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import ImageSourceField from './image-source';

import {
  buildField,
  renderField,
} from '../../tests/helpers/field-test-helpers';

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

    test('image-source field edit shows the empty state when no url or file', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, {}),
        'edit',
      );

      assert
        .dom('[data-test-image-source-preview]')
        .doesNotExist('no hero preview without an image');
      assert
        .dom('[data-test-image-source-file-field]')
        .exists('link-an-image panel shown');
      assert
        .dom('[data-test-image-source-url-input]')
        .exists('url input present');
    });

    test('image-source field edit shows the hero preview when url is set', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, {
          url: 'https://example.com/photo.jpg',
          sourceMode: 'url',
        }),
        'edit',
      );

      assert
        .dom('[data-test-image-source-preview] img')
        .hasAttribute(
          'src',
          'https://example.com/photo.jpg',
          'hero shows the resolved image',
        );
      assert
        .dom('[data-test-image-source-remove]')
        .exists('remove button present on the hero');
    });

    test('image-source field edit adds an image by url', async function (assert) {
      // sourceMode alone yields a real (still image-less) field instance —
      // buildField({}) returns undefined, which renders but cannot be edited
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, { sourceMode: 'file' }),
        'edit',
      );

      await fillIn(
        '[data-test-image-source-url-input] input',
        'https://example.com/added.jpg',
      );
      await click('[data-test-image-source-url-add]');

      assert
        .dom('[data-test-image-source-preview] img')
        .hasAttribute(
          'src',
          'https://example.com/added.jpg',
          'added url becomes the hero image',
        );
    });

    test('image-source field edit remove returns to the empty state', async function (assert) {
      await renderField(
        ImageSourceField,
        buildField(ImageSourceField, {
          url: 'https://example.com/photo.jpg',
          sourceMode: 'url',
        }),
        'edit',
      );

      await click('[data-test-image-source-remove]');

      assert
        .dom('[data-test-image-source-preview]')
        .doesNotExist('hero cleared after remove');
      assert
        .dom('[data-test-image-source-file-field]')
        .exists('back to the empty state');
    });
  });
}
