import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import AvatarField from '../../../fields/avatar';

import { buildField, renderField } from '../../helpers/field-test-helpers';

export function runTests() {
  module('Rendering | avatar fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

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

    test('avatar field renders embedded view', async function (assert) {
      await renderField(AvatarField, buildField(AvatarField, sampleAvatarData));

      assert.dom('[data-test-field-container]').exists('embedded view renders');
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

    test('avatar field renders with no attributes', async function (assert) {
      await renderField(AvatarField, buildField(AvatarField, {}));

      assert
        .dom('[data-test-field-container]')
        .exists('field renders without attributes (uses defaults)');
    });

    test('avatar field renders with different hair styles', async function (assert) {
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
        .exists('avatar field renders with curly hair');
    });

    test('avatar field renders with different skin tones', async function (assert) {
      await renderField(
        AvatarField,
        buildField(AvatarField, {
          ...sampleAvatarData,
          skinColor: 'DarkBrown',
        }),
      );

      assert
        .dom('[data-test-field-container]')
        .exists('avatar field renders with dark skin tone');
    });
  });
}
