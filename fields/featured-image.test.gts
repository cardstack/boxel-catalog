import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import FeaturedImageField from './featured-image';

import { buildField, renderField } from '../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | featured-image fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    const sampleImage = {
      imageUrl: 'https://example.com/photo.jpg',
      altText: 'A nice photo',
      caption: 'A nice photo',
      credit: 'Photographer X',
      size: 'actual',
      height: 100,
      width: 200,
    };

    test('featured-image field renders atom view as a background image when url is set', async function (assert) {
      await renderField(
        FeaturedImageField,
        buildField(FeaturedImageField, sampleImage),
        'atom',
      );

      assert
        .dom('[data-test-field-container] [role="img"]')
        .exists('atom renders a div with role="img"');
      assert
        .dom('[data-test-field-container] [role="img"]')
        .hasAttribute('aria-label', 'A nice photo');
    });

    test('featured-image field atom renders nothing when no imageUrl', async function (assert) {
      await renderField(
        FeaturedImageField,
        buildField(FeaturedImageField, { altText: 'no image' }),
        'atom',
      );

      assert
        .dom('[data-test-field-container] [role="img"]')
        .doesNotExist('no image rendered without url');
    });

    test('featured-image field renders embedded view with figure and figcaption', async function (assert) {
      await renderField(
        FeaturedImageField,
        buildField(FeaturedImageField, sampleImage),
      );

      assert.dom('figure').exists('embedded view renders a figure');
      assert.dom('img').exists('renders img for actual size');
      assert
        .dom('img')
        .hasAttribute('src', 'https://example.com/photo.jpg', 'img has src');
      assert.dom('img').hasAttribute('alt', 'A nice photo', 'img has alt text');
      assert.dom('figcaption').exists('caption section renders');
    });

    test('featured-image field embedded renders nothing when no imageUrl', async function (assert) {
      await renderField(
        FeaturedImageField,
        buildField(FeaturedImageField, { caption: 'no image' }),
      );

      assert.dom('figure').doesNotExist('no figure rendered without imageUrl');
    });

    test('featured-image field renders edit view with form fields', async function (assert) {
      await renderField(
        FeaturedImageField,
        buildField(FeaturedImageField, sampleImage),
        'edit',
      );

      assert.dom('[data-test-field-container]').exists('edit view renders');
    });
  });
}
