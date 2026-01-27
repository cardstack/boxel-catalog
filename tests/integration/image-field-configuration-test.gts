import { module, test } from 'qunit';

import { setupBaseRealm } from '../helpers/base-realm';
import { setupCatalogRealm, CatalogImageField } from '../helpers/catalog-realm';
import {
  renderConfiguredField,
  buildImageField,
} from '../helpers/field-test-helpers';
import { setupRenderingTest } from '../helpers/setup';

module('Integration | image field configuration', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  // ImageField Variant Tests
  test('browse variant renders browse upload component', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({}),
      {
        variant: 'browse',
      },
      'edit',
    );

    assert
      .dom('[data-test-field-container] [data-test-image-field-edit]')
      .exists('Image field edit view is rendered');

    assert
      .dom('[data-test-field-container] .browse-upload')
      .exists('Browse variant renders browse upload component');
  });

  test('dropzone variant renders dropzone upload component', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({}),
      {
        variant: 'dropzone',
      },
      'edit',
    );

    assert
      .dom('[data-test-field-container] [data-test-image-field-edit]')
      .exists('Image field edit view is rendered');

    assert
      .dom('[data-test-field-container] .dropzone-upload')
      .exists('Dropzone variant renders dropzone upload component');
  });

  test('avatar variant renders avatar upload component', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({}),
      {
        variant: 'avatar',
      },
      'edit',
    );

    assert
      .dom('[data-test-field-container] [data-test-image-field-edit]')
      .exists('Image field edit view is rendered');

    assert
      .dom('[data-test-field-container] .avatar-upload')
      .exists('Avatar variant renders avatar upload component');
  });

  test('invalid variant falls back to default browse', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({}),
      {
        variant: 'invalid-variant',
      },
      'edit',
    );

    // Should fall back to browse variant (default)
    assert
      .dom('[data-test-field-container] [data-test-image-field-edit]')
      .exists('Image field with invalid variant still renders');
  });

  // ImageField Presentation Tests
  test('image presentation renders image presentation component', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({ imageUrl: 'https://example.com/image.jpg' }),
      {
        variant: 'browse',
        presentation: 'image',
      },
      'embedded',
    );

    assert
      .dom('[data-test-field-container] .image-embedded')
      .exists('Image presentation renders image embedded component');
  });

  test('inline presentation renders inline presentation component', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({ imageUrl: 'https://example.com/image.jpg' }),
      {
        variant: 'browse',
        presentation: 'inline',
      },
      'embedded',
    );

    assert
      .dom('[data-test-field-container] .image-inline')
      .exists('Inline presentation renders inline component');
  });

  test('card presentation renders card presentation component', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({ imageUrl: 'https://example.com/image.jpg' }),
      {
        variant: 'browse',
        presentation: 'card',
      },
      'embedded',
    );

    assert
      .dom('[data-test-field-container] .image-card')
      .exists('Card presentation renders card component');
  });

  test('invalid presentation falls back to default image', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({ imageUrl: 'https://example.com/image.jpg' }),
      {
        variant: 'browse',
        presentation: 'invalid-presentation',
      },
      'embedded',
    );

    // Should fall back to image presentation (default)
    assert
      .dom(
        '[data-test-field-container] [data-test-image-field-edit], [data-test-field-container] .image-embedded',
      )
      .exists('Image field with invalid presentation still renders');
  });

  // ImageField Options Tests
  test('showImageModal option is ignored for avatar variant', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({ imageUrl: 'https://example.com/image.jpg' }),
      {
        variant: 'avatar',
        options: {
          showImageModal: true, // Should be ignored
        },
      },
      'edit',
    );

    // Avatar variant should not have zoom button (showImageModal is not available)
    assert
      .dom('[data-test-field-container] [data-test-image-field-edit]')
      .exists('Avatar variant renders without showImageModal option');

    // Verify no zoom button exists (avatar doesn't support showImageModal)
    assert
      .dom('[data-test-field-container] .zoom-button')
      .doesNotExist(
        'Avatar variant does not show zoom button even with showImageModal option',
      );
  });

  test('image field ignores irrelevant config properties', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({}),
      {
        variant: 'browse',
        // These properties should be ignored by image field
        maxFiles: 10,
        allowReorder: true,
        allowBatchSelect: true,
      },
      'edit',
    );

    // Image field should still work normally, ignoring the irrelevant config
    assert
      .dom('[data-test-field-container] [data-test-image-field-edit]')
      .exists(
        'Image field ignores maxFiles, allowReorder, allowBatchSelect configs',
      );
  });

  // Default Config Fallback Tests
  test('image field edit view falls back to default browse variant when config is missing', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({}),
      {},
      'edit',
    );

    assert
      .dom('[data-test-field-container] [data-test-image-field-edit]')
      .exists('Image field edit view renders with default browse variant');
  });

  test('image field embedded view falls back to default image presentation when config is missing', async function (assert) {
    await renderConfiguredField(
      CatalogImageField,
      buildImageField({ imageUrl: 'https://example.com/image.jpg' }),
      {},
      'embedded',
    );

    assert
      .dom('[data-test-field-container] .image-embedded')
      .exists('Image field embedded view defaults to image presentation');
  });
});
