import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { AudioDef } from 'https://cardstack.com/base/audio-file-def';

import AudioField from './audio';

import {
  buildField,
  renderField,
} from '../../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | audio fields', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    // The audio source is a `linksTo(AudioDef)`. We construct a stub AudioDef
    // pointing at a URL that does not actually exist — the inner <audio>
    // element will 404, but every FieldDef-level rendering path still
    // resolves correctly via the `url` / `displayTitle` compute shims.
    // `id` is required: linksTo→FileDef validation rejects targets without one.
    const stubAudio = (overrides: Record<string, unknown> = {}) =>
      new AudioDef({
        id: 'http://localhost:4201/does-not-exist/audio/sample.mp3',
        url: 'http://localhost:4201/does-not-exist/audio/sample.mp3',
        name: 'sample.mp3',
        contentType: 'audio/mpeg',
        ...overrides,
      });

    test('audio field renders embedded view with valid data', async function (assert) {
      await renderField(
        AudioField,
        buildField(AudioField, {
          file: stubAudio(),
          cardTitle: 'Test Track',
          artist: 'Test Artist',
        }),
      );

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

    test('audio field embedded view shows placeholder without a linked file', async function (assert) {
      await renderField(AudioField, buildField(AudioField, {}));

      assert
        .dom('[data-test-audio-placeholder]')
        .exists('placeholder is shown without a linked file');
      assert
        .dom('[data-test-audio-embedded]')
        .doesNotExist('no player rendered without a source');
    });

    test('audio field atom view shows displayTitle when a file is linked', async function (assert) {
      await renderField(
        AudioField,
        buildField(AudioField, {
          file: stubAudio(),
          cardTitle: 'Test Track',
        }),
        'atom',
      );

      assert.dom('[data-test-audio-atom]').exists('atom view renders');
      assert
        .dom('[data-test-audio-atom]')
        .hasTextContaining('Test Track', 'cardTitle drives the atom label');
      assert.dom('[data-test-audio-atom] svg').exists('audio icon is shown');
    });

    test('audio field atom view falls back to "Untitled Audio" when title is missing', async function (assert) {
      // Stub file with an empty name so the displayTitle chain
      // (cardTitle → file.name → 'Untitled Audio') exhausts to the fallback.
      await renderField(
        AudioField,
        buildField(AudioField, { file: stubAudio({ name: '' }) }),
        'atom',
      );

      assert
        .dom('[data-test-audio-atom]')
        .hasTextContaining('Untitled Audio', 'displayTitle fallback is shown');
    });

    test('audio field atom view renders nothing without a linked file', async function (assert) {
      await renderField(
        AudioField,
        buildField(AudioField, { cardTitle: 'Lonely Title' }),
        'atom',
      );

      assert
        .dom('[data-test-audio-atom]')
        .doesNotExist('atom is empty without a resolved url');
    });

    test('audio field fitted view shows placeholder without a linked file', async function (assert) {
      await renderField(AudioField, buildField(AudioField, {}), 'fitted');

      assert
        .dom('[data-test-audio-fitted-placeholder]')
        .exists('fitted placeholder shown when no resolved url');
    });

    test('audio field edit view renders editor wrapper', async function (assert) {
      await renderField(
        AudioField,
        buildField(AudioField, {
          cardTitle: 'Edit Track',
          artist: 'Edit Artist',
        }),
        'edit',
      );

      assert
        .dom('[data-test-audio-edit]')
        .exists('edit wrapper renders so users can link a file');
    });
  });
}
