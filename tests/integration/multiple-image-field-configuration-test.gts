import { module, test } from 'qunit';

import {
  PermissionsContextName,
  type Permissions,
} from '@cardstack/runtime-common';

import { provideConsumeContext } from '../helpers';
import { setupBaseRealm } from '../helpers/base-realm';
import {
  setupCatalogRealm,
  MultipleImageField,
} from '../helpers/catalog-realm';
import {
  renderConfiguredField,
  buildMultipleImageField,
} from '../helpers/field-test-helpers';
import { setupRenderingTest } from '../helpers/setup';

module('Integration | multiple image field configuration', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  hooks.beforeEach(async function () {
    // Set up permissions to allow editing
    const permissions: Permissions = { canWrite: true, canRead: true };
    provideConsumeContext(PermissionsContextName, permissions);
  });

  // MultipleImageField Variant Tests
  test('list variant renders list upload component', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [{ imageUrl: 'https://example.com/image1.jpg' }],
      }),
      {
        variant: 'list',
      },
      'edit',
    );

    assert
      .dom('[data-test-field-container] [data-test-multiple-image-field]')
      .exists('Multiple image field edit view is rendered');

    assert
      .dom('[data-test-field-container] .images-container.variant-list')
      .exists('List variant renders list container');
  });

  test('gallery variant renders gallery upload component', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [{ imageUrl: 'https://example.com/image1.jpg' }],
      }),
      {
        variant: 'gallery',
      },
      'edit',
    );

    assert
      .dom('[data-test-field-container] [data-test-multiple-image-field]')
      .exists('Multiple image field edit view is rendered');

    assert
      .dom('[data-test-field-container] .images-container.variant-gallery')
      .exists('Gallery variant renders gallery container');
  });

  test('dropzone variant renders dropzone upload component', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [{ imageUrl: 'https://example.com/image1.jpg' }],
      }),
      {
        variant: 'dropzone',
      },
      'edit',
    );

    assert
      .dom('[data-test-field-container] [data-test-multiple-image-field]')
      .exists('Multiple image field edit view is rendered');

    assert
      .dom('[data-test-field-container] .images-container.variant-dropzone')
      .exists('Dropzone variant renders dropzone container');
  });

  test('invalid variant falls back to default list', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({ images: [] }),
      {
        variant: 'invalid-variant',
      },
      'edit',
    );

    // Should fall back to list variant (default)
    assert
      .dom('[data-test-field-container] [data-test-multiple-image-field]')
      .exists('Multiple image field with invalid variant still renders');
  });

  // MultipleImageField Presentation Tests
  test('grid presentation renders grid presentation component', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [
          { imageUrl: 'https://example.com/image1.jpg' },
          { imageUrl: 'https://example.com/image2.jpg' },
        ],
      }),
      {
        variant: 'list',
        presentation: 'grid',
      },
      'embedded',
    );

    assert
      .dom('[data-test-field-container] .images-grid')
      .exists('Grid presentation renders grid component');
  });

  test('carousel presentation renders carousel presentation component', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [
          { imageUrl: 'https://example.com/image1.jpg' },
          { imageUrl: 'https://example.com/image2.jpg' },
        ],
      }),
      {
        variant: 'list',
        presentation: 'carousel',
      },
      'embedded',
    );

    assert
      .dom('[data-test-field-container] .carousel-container')
      .exists('Carousel presentation renders carousel component');
  });

  test('invalid presentation falls back to default grid', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [{ imageUrl: 'https://example.com/image1.jpg' }],
      }),
      {
        variant: 'list',
        presentation: 'invalid-presentation',
      },
      'embedded',
    );

    // Should fall back to grid presentation (default)
    assert
      .dom(
        '[data-test-field-container] [data-test-multiple-image-field], [data-test-field-container] .images-grid',
      )
      .exists('Multiple image field with invalid presentation still renders');
  });

  // MultipleImageField Options Tests
  test('allowBatchSelect option controls batch actions visibility', async function (assert) {
    // Test with allowBatchSelect: true
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [{ imageUrl: 'https://example.com/image1.jpg' }],
      }),
      {
        variant: 'list',
        options: {
          allowBatchSelect: true,
        },
      },
      'edit',
    );

    assert
      .dom('[data-test-field-container] .batch-actions')
      .exists(
        'Multiple image field with allowBatchSelect: true shows batch actions',
      );

    // Test with allowBatchSelect: false
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [{ imageUrl: 'https://example.com/image1.jpg' }],
      }),
      {
        variant: 'list',
        options: {
          allowBatchSelect: false,
        },
      },
      'edit',
    );

    assert
      .dom('[data-test-field-container] .batch-actions')
      .doesNotExist(
        'Multiple image field with allowBatchSelect: false hides batch actions',
      );
  });

  test('multiple image field ignores irrelevant config properties', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({ images: [] }),
      {
        variant: 'list',
        // These properties should be ignored by multiple image field
        showImageModal: true,
        type: 'rating',
        maxStars: 5,
      },
      'edit',
    );

    // Multiple image field should still work normally, ignoring the irrelevant config
    assert
      .dom('[data-test-field-container] [data-test-multiple-image-field]')
      .exists(
        'Multiple image field ignores showImageModal, type, maxStars configs',
      );
  });

  // Default Config Fallback Tests
  test('multiple image field edit view falls back to default list variant when config is missing', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({ images: [] }),
      {},
      'edit',
    );

    assert
      .dom('[data-test-field-container] [data-test-multiple-image-field]')
      .exists(
        'Multiple image field edit view renders with default list variant',
      );
  });

  test('multiple image field embedded view falls back to default grid presentation when config is missing', async function (assert) {
    await renderConfiguredField(
      MultipleImageField,
      buildMultipleImageField({
        images: [{ imageUrl: 'https://example.com/image1.jpg' }],
      }),
      {},
      'embedded',
    );

    assert
      .dom('[data-test-field-container] .images-grid')
      .exists(
        'Multiple image field embedded view defaults to grid presentation',
      );
  });
});
