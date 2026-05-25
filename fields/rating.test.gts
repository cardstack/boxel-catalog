import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import RatingField from './rating';

import {
  buildField,
  renderConfiguredField,
  renderField,
} from '../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | rating fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('rating field renders embedded view with a value', async function (assert) {
      await renderField(RatingField, buildField(RatingField, { value: 4 }));

      assert.dom('[data-test-rating-embedded]').exists('embedded view renders');
    });

    test('rating field renders edit view', async function (assert) {
      await renderField(
        RatingField,
        buildField(RatingField, { value: 3 }),
        'edit',
      );

      assert.dom('[data-test-rating-edit]').exists('edit view renders');
    });

    test('rating field renders with no value', async function (assert) {
      await renderField(RatingField, buildField(RatingField, {}));

      assert
        .dom('[data-test-rating-embedded]')
        .exists('embedded view renders with no value');
    });

    test('rating field respects maxRating configuration', async function (assert) {
      await renderConfiguredField(
        RatingField,
        buildField(RatingField, { value: 7 }),
        { maxRating: 10 },
        'edit',
      );

      assert
        .dom('[data-test-rating-edit]')
        .exists('edit view renders with maxRating');
    });
  });
}
