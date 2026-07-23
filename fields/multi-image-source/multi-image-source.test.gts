import { click, fillIn } from '@ember/test-helpers';
import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import ImageSourceField from '../image-source/image-source';
import MultiImageSourceField from './multi-image-source';

import {
  buildField,
  renderField,
} from '../../tests/helpers/field-test-helpers';

function urlImage(url: string) {
  return new ImageSourceField({ url, sourceMode: 'url' });
}

export function runTests() {
  module('Rendering | multi-image-source fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    // --- embedded ---

    test('multi-image-source field embedded renders every image in order', async function (assert) {
      await renderField(
        MultiImageSourceField,
        buildField(MultiImageSourceField, {
          images: [
            urlImage('https://example.com/one.jpg'),
            urlImage('https://example.com/two.jpg'),
          ],
        }),
      );

      assert
        .dom('[data-test-multi-image-source-embedded] img')
        .exists({ count: 2 }, 'both images render');
      assert
        .dom('[data-test-multi-image-source-embedded] li:first-child img')
        .hasAttribute('src', 'https://example.com/one.jpg', 'order preserved');
    });

    test('multi-image-source field embedded renders nothing when empty', async function (assert) {
      await renderField(
        MultiImageSourceField,
        buildField(MultiImageSourceField, { images: [] }),
      );

      assert
        .dom('[data-test-multi-image-source-embedded]')
        .doesNotExist('no list rendered without images');
    });

    // --- edit ---

    test('multi-image-source field edit shows the empty state when no images', async function (assert) {
      await renderField(
        MultiImageSourceField,
        buildField(MultiImageSourceField, { images: [] }),
        'edit',
      );

      assert
        .dom('[data-test-multi-image-source-edit]')
        .exists('edit root wrapper renders');
      assert
        .dom('[data-test-multi-image-source-link]')
        .exists('link-an-image panel shown');
      assert
        .dom('[data-test-multi-image-source-url-input]')
        .exists('url input present');
    });

    test('multi-image-source field edit shows hero and thumbnail strip', async function (assert) {
      await renderField(
        MultiImageSourceField,
        buildField(MultiImageSourceField, {
          images: [
            urlImage('https://example.com/one.jpg'),
            urlImage('https://example.com/two.jpg'),
          ],
        }),
        'edit',
      );

      assert
        .dom('[data-test-multi-image-source-hero] img')
        .hasAttribute(
          'src',
          'https://example.com/one.jpg',
          'first image is the highlighted hero by default',
        );
      assert
        .dom('[data-test-multi-image-source-remove]')
        .exists({ count: 2 }, 'each thumbnail has a remove button');
    });

    test('multi-image-source field edit clicking a thumbnail highlights it', async function (assert) {
      await renderField(
        MultiImageSourceField,
        buildField(MultiImageSourceField, {
          images: [
            urlImage('https://example.com/one.jpg'),
            urlImage('https://example.com/two.jpg'),
          ],
        }),
        'edit',
      );

      await click('.thumb:nth-child(2) [data-test-multi-image-source-thumb]');

      assert
        .dom('[data-test-multi-image-source-hero] img')
        .hasAttribute(
          'src',
          'https://example.com/two.jpg',
          'clicked thumbnail becomes the hero',
        );
      assert
        .dom('.thumb:nth-child(2) [aria-pressed="true"]')
        .exists('clicked thumbnail is marked selected');
    });

    test('multi-image-source field edit adds an image by url', async function (assert) {
      await renderField(
        MultiImageSourceField,
        buildField(MultiImageSourceField, {
          images: [urlImage('https://example.com/one.jpg')],
        }),
        'edit',
      );

      await fillIn(
        '[data-test-multi-image-source-url-input] input',
        'https://example.com/added.jpg',
      );
      await click('[data-test-multi-image-source-url-add]');

      assert.dom('.thumb').exists({ count: 2 }, 'new image joins the strip');
      assert
        .dom('[data-test-multi-image-source-hero] img')
        .hasAttribute(
          'src',
          'https://example.com/added.jpg',
          'newly added image auto-highlights',
        );
    });

    test('multi-image-source field edit removes an image', async function (assert) {
      await renderField(
        MultiImageSourceField,
        buildField(MultiImageSourceField, {
          images: [
            urlImage('https://example.com/one.jpg'),
            urlImage('https://example.com/two.jpg'),
          ],
        }),
        'edit',
      );

      await click('.thumb:nth-child(1) [data-test-multi-image-source-remove]');

      assert.dom('.thumb').exists({ count: 1 }, 'one thumbnail remains');
      assert
        .dom('[data-test-multi-image-source-hero] img')
        .hasAttribute(
          'src',
          'https://example.com/two.jpg',
          'hero falls back to the remaining image',
        );
    });

    test('multi-image-source field edit removing the last image returns to the empty state', async function (assert) {
      await renderField(
        MultiImageSourceField,
        buildField(MultiImageSourceField, {
          images: [urlImage('https://example.com/one.jpg')],
        }),
        'edit',
      );

      await click('[data-test-multi-image-source-remove]');

      assert
        .dom('[data-test-multi-image-source-hero]')
        .doesNotExist('hero cleared');
      assert
        .dom('[data-test-multi-image-source-link]')
        .exists('back to the empty state');
    });
  });
}
