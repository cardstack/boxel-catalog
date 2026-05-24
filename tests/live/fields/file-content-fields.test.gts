import { module, test } from 'qunit';

import { getService } from '@universal-ember/test-support';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { buildField, renderField } from '../../helpers/field-test-helpers';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const realmURL: string = new URL('../../../', import.meta.url).href;

export function runTests() {
  module('Rendering | file-content fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    let FileContentField: any;

    hooks.beforeEach(async function () {
      const loader = getService('loader-service').loader;
      FileContentField = (await loader.import(`${realmURL}fields/file-content`))
        .FileContentField;
    });

    const sampleFile = {
      filename: 'example.ts',
      contents: 'line 1\nline 2\nline 3',
    };

    test('file-content field renders atom view with filename', async function (assert) {
      await renderField(
        FileContentField,
        buildField(FileContentField, sampleFile),
        'atom',
      );

      assert.dom('.file-atom').exists('atom view renders');
      assert
        .dom('.file-atom-name')
        .hasText('example.ts', 'filename is displayed');
    });

    test('file-content field atom falls back to "Untitled" when filename missing', async function (assert) {
      await renderField(
        FileContentField,
        buildField(FileContentField, { contents: 'something' }),
        'atom',
      );

      assert
        .dom('.file-atom-name')
        .hasText('Untitled', 'fallback name shown when filename absent');
    });

    test('file-content field renders embedded view with filename, line count, and preview', async function (assert) {
      await renderField(
        FileContentField,
        buildField(FileContentField, sampleFile),
      );

      assert.dom('.file-embedded').exists('embedded view renders');
      assert.dom('.file-name').hasText('example.ts', 'filename shown');
      assert
        .dom('.line-badge')
        .hasText('3 lines', 'line count badge shows pluralised count');
      assert
        .dom('.file-preview')
        .hasText('line 1\nline 2\nline 3', 'preview shows file contents');
    });

    test('file-content field embedded uses singular form for one line', async function (assert) {
      await renderField(
        FileContentField,
        buildField(FileContentField, {
          filename: 'a.txt',
          contents: 'just one',
        }),
      );

      assert
        .dom('.line-badge')
        .hasText('1 line', 'line count is singular when only one line');
    });

    test('file-content field embedded omits preview when contents empty', async function (assert) {
      await renderField(
        FileContentField,
        buildField(FileContentField, { filename: 'empty.txt' }),
      );

      assert.dom('.file-name').hasText('empty.txt');
      assert
        .dom('.file-preview')
        .doesNotExist('preview not rendered for empty file');
    });
  });
}
