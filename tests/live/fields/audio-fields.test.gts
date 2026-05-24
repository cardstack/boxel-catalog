import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import AudioField from '../../../fields/audio';

import { buildField, renderField } from '../../helpers/field-test-helpers';

export function runTests() {
  module('Rendering | audio fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    const sampleAudioData = {
      url: 'http://localhost:4201/does-not-exist/audio/sample.mp3',
      filename: 'sample.mp3',
      mimeType: 'audio/mpeg',
      duration: 180,
      fileSize: 3145728,
      cardTitle: 'Test Track',
      artist: 'Test Artist',
    };

    const minimalAudioData = {
      url: 'http://localhost:4201/does-not-exist/audio/minimal.mp3',
      filename: 'minimal.mp3',
    };

    test('audio field renders embedded view with valid data', async function (assert) {
      await renderField(AudioField, buildField(AudioField, sampleAudioData));

      assert.dom('[data-test-audio-embedded]').exists('embedded view renders');
      assert
        .dom('[data-test-audio-title]')
        .hasText('Test Track', 'title is displayed');
      assert
        .dom('[data-test-audio-artist]')
        .hasText('Test Artist', 'artist is displayed');
      assert
        .dom('[data-test-audio-play-btn]')
        .exists('play button is rendered');
    });

    test('audio field renders atom view with valid data', async function (assert) {
      await renderField(
        AudioField,
        buildField(AudioField, sampleAudioData),
        'atom',
      );

      assert.dom('[data-test-audio-atom]').exists('atom view renders');
      assert
        .dom('[data-test-audio-atom]')
        .hasTextContaining('Test Track', 'displays title in atom view');
    });

    test('audio field atom view shows audio icon', async function (assert) {
      await renderField(
        AudioField,
        buildField(AudioField, sampleAudioData),
        'atom',
      );

      assert.dom('[data-test-audio-atom] svg').exists('audio icon is shown');
      assert
        .dom('[data-test-audio-atom]')
        .hasTextContaining('Test Track', 'title is shown');
    });

    test('audio field atom view shows displayTitle fallback', async function (assert) {
      await renderField(
        AudioField,
        buildField(AudioField, { url: 'test.mp3' }),
        'atom',
      );

      assert
        .dom('[data-test-audio-atom]')
        .hasTextContaining('Untitled Audio', 'fallback title shown');
    });

    test('audio field edit view shows metadata fields when audio is uploaded', async function (assert) {
      await renderField(
        AudioField,
        buildField(AudioField, sampleAudioData),
        'edit',
      );

      assert.dom('[data-test-audio-edit]').exists('edit view renders');
      assert
        .dom('[data-test-audio-uploaded-file]')
        .exists('uploaded file info shown');
    });

    test('audio field edit view shows upload prompt when no audio', async function (assert) {
      await renderField(AudioField, buildField(AudioField, {}), 'edit');

      assert
        .dom('[data-test-audio-upload-area]')
        .exists('upload prompt is shown');
    });

    test('audio field with minimal data still renders', async function (assert) {
      await renderField(AudioField, buildField(AudioField, minimalAudioData));

      assert.dom('[data-test-audio-embedded]').exists('player still renders');
      assert.dom('[data-test-audio-artist]').doesNotExist('no artist shown');
    });
  });
}
