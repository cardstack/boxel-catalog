import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { setupCatalogRealm, AvatarField } from '../helpers/catalog-realm';
import { renderField, buildField } from '../helpers/field-test-helpers';

module('Integration | avatar fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  const sampleAvatarData = {
    topType: 'ShortHairShortFlat',
    accessoriesType: 'Blank',
    hairColor: 'BrownDark',
    facialHairType: 'Blank',
    clotheType: 'BlazerShirt',
    eyeType: 'Default',
    eyebrowType: 'Default',
    mouthType: 'Smile',
    skinColor: 'Light',
  };

  // ============================================
  // Basic Rendering Tests
  // ============================================

  test('avatar field renders embedded view', async function (assert) {
    await renderField(AvatarField, buildField(AvatarField, sampleAvatarData));

    assert.dom('[data-test-field-container]').exists('embedded view renders');
  });

  test('avatar field renders atom view', async function (assert) {
    await renderField(
      AvatarField,
      buildField(AvatarField, sampleAvatarData),
      'atom',
    );

    assert.dom('[data-test-field-container]').exists('atom view renders');
  });

  test('avatar field renders edit view with creator UI', async function (assert) {
    await renderField(
      AvatarField,
      buildField(AvatarField, sampleAvatarData),
      'edit',
    );

    assert
      .dom('[data-test-field-container]')
      .exists('edit view renders with creator UI');
  });

  // ============================================
  // Empty State Tests
  // ============================================

  test('avatar field renders with no attributes', async function (assert) {
    await renderField(AvatarField, buildField(AvatarField, {}));

    assert
      .dom('[data-test-field-container]')
      .exists('field renders without attributes (uses defaults)');
  });

  // ============================================
  // Attribute Variation Tests
  // ============================================

  test('avatar renders with different hair styles', async function (assert) {
    await renderField(
      AvatarField,
      buildField(AvatarField, {
        ...sampleAvatarData,
        topType: 'LongHairCurly',
        hairColor: 'Blonde',
      }),
    );

    assert
      .dom('[data-test-field-container]')
      .exists('avatar renders with curly hair');
  });

  test('avatar renders with different skin tones', async function (assert) {
    await renderField(
      AvatarField,
      buildField(AvatarField, {
        ...sampleAvatarData,
        skinColor: 'DarkBrown',
      }),
    );

    assert
      .dom('[data-test-field-container]')
      .exists('avatar renders with dark skin tone');
  });
});
