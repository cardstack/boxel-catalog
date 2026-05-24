import { module, test } from 'qunit';

import { getService } from '@universal-ember/test-support';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import {
  buildField,
  renderConfiguredField,
  renderField,
} from '../../helpers/field-test-helpers';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const realmURL: string = new URL('../../../', import.meta.url).href;

export function runTests() {
  module('Rendering | rating fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    let RatingField: any;

    hooks.beforeEach(async function () {
      const loader = getService('loader-service').loader;
      RatingField = (await loader.import(`${realmURL}fields/rating`)).default;
    });

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
