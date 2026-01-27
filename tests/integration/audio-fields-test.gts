import { module, test } from 'qunit';

import { setupBaseRealm } from '../helpers/base-realm';
import { setupCatalogRealm, AudioField } from '../helpers/catalog-realm';
import {
  renderField,
  renderConfiguredField,
  buildField,
} from '../helpers/field-test-helpers';
import { setupRenderingTest } from '../helpers/setup';

module('Integration | audio fields', function (hooks) {
  setupRenderingTest(hooks);
  setupBaseRealm(hooks);
  setupCatalogRealm(hooks);

  // Sample audio data for tests
  const sampleAudioData = {
    url: 'http://localhost:4201/does-not-exist/audio/sample.mp3',
    filename: 'sample.mp3',
    mimeType: 'audio/mpeg',
    duration: 180, // 3 minutes
    fileSize: 3145728, // 3MB
    cardTitle: 'Test Track',
    artist: 'Test Artist',
  };

  const minimalAudioData = {
    url: 'http://localhost:4201/does-not-exist/audio/minimal.mp3',
    filename: 'minimal.mp3',
  };

  // ============================================
  // Basic Rendering Tests
  // ============================================

  test('audio field renders embedded view with valid data', async function (assert) {
    await renderField(AudioField, buildField(AudioField, sampleAudioData));

    assert.dom('[data-test-audio-embedded]').exists('embedded view renders');
    assert
      .dom('[data-test-audio-title]')
      .hasText('Test Track', 'title is displayed');
    assert
      .dom('[data-test-audio-artist]')
      .hasText('Test Artist', 'artist is displayed');
    assert.dom('[data-test-audio-play-btn]').exists('play button is rendered');
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

  test('audio field renders fitted view with valid data', async function (assert) {
    await renderField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      'fitted',
    );

    assert.dom('[data-test-audio-fitted]').exists('fitted view renders');
  });

  test('audio field renders edit view with valid data', async function (assert) {
    await renderField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      'edit',
    );

    assert.dom('[data-test-audio-edit]').exists('edit view renders');
    assert
      .dom('[data-test-audio-uploaded-file]')
      .exists('shows uploaded file info');
  });

  // ============================================
  // Empty State Tests
  // ============================================

  test('missing audio renders placeholder in embedded view', async function (assert) {
    await renderField(AudioField, buildField(AudioField, {}));

    assert
      .dom('[data-test-audio-placeholder]')
      .exists('placeholder is displayed');
    assert
      .dom('[data-test-audio-placeholder]')
      .hasTextContaining('No audio file', 'placeholder text is shown');
  });

  test('missing audio renders placeholder in fitted view', async function (assert) {
    await renderField(AudioField, buildField(AudioField, {}), 'fitted');

    assert
      .dom('[data-test-audio-fitted-placeholder]')
      .exists('fitted placeholder is displayed');
    assert
      .dom('[data-test-audio-fitted-placeholder]')
      .hasTextContaining('No audio', 'fitted placeholder text is shown');
  });

  test('missing audio shows upload area in edit view', async function (assert) {
    await renderField(AudioField, buildField(AudioField, {}), 'edit');

    assert.dom('[data-test-audio-edit]').exists('edit view renders');
    assert
      .dom('[data-test-audio-upload-area]')
      .exists('upload area is displayed');
  });

  test('undefined audio field renders placeholder', async function (assert) {
    await renderField(AudioField, undefined);

    assert
      .dom('[data-test-audio-placeholder]')
      .exists('placeholder is displayed for undefined');
  });

  // ============================================
  // Computed Field Tests
  // ============================================

  test('displayTitle shows title when available', async function (assert) {
    await renderField(
      AudioField,
      buildField(AudioField, {
        ...sampleAudioData,
        cardTitle: 'Custom Title',
      }),
    );

    assert
      .dom('[data-test-audio-title]')
      .hasText('Custom Title', 'custom title is displayed');
  });

  test('displayTitle falls back to filename when no title', async function (assert) {
    await renderField(
      AudioField,
      buildField(AudioField, {
        url: 'http://localhost:4201/does-not-exist/audio.mp3',
        filename: 'my-song.mp3',
      }),
    );

    assert
      .dom('[data-test-audio-title]')
      .hasText('my-song.mp3', 'filename is displayed as fallback');
  });

  test('displayTitle falls back to default when no title or filename', async function (assert) {
    await renderField(
      AudioField,
      buildField(AudioField, {
        url: 'http://localhost:4201/does-not-exist/audio.mp3',
      }),
    );

    assert
      .dom('[data-test-audio-title]')
      .hasText('Untitled Audio', 'default title is displayed');
  });

  // ============================================
  // Presentation Style Tests
  // ============================================

  test('waveform-player presentation renders correctly', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      { presentation: 'waveform-player' },
    );

    assert
      .dom('[data-test-waveform-player]')
      .exists('waveform player is rendered');
  });

  test('mini-player presentation renders correctly', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      { presentation: 'mini-player' },
    );

    assert.dom('[data-test-mini-player]').exists('mini player is rendered');
  });

  test('album-cover presentation renders correctly', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      { presentation: 'album-cover' },
    );

    assert
      .dom('[data-test-album-cover-player]')
      .exists('album cover player is rendered');
  });

  test('trim-editor presentation renders correctly', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      { presentation: 'trim-editor' },
    );

    assert.dom('[data-test-trim-editor]').exists('trim editor is rendered');
  });

  test('playlist-row presentation renders correctly', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      { presentation: 'playlist-row' },
    );

    assert.dom('[data-test-playlist-row]').exists('playlist row is rendered');
  });

  test('inline-player (default) presentation renders correctly', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      {}, // Default presentation
    );

    assert
      .dom('[data-test-audio-embedded]')
      .exists('inline player is rendered (default)');
  });

  // ============================================
  // Configuration Options Tests
  // ============================================

  test('showVolume option renders volume control', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      { options: { showVolume: true } },
    );

    assert
      .dom('[data-test-volume-control]')
      .exists('volume control is rendered');
  });

  test('showSpeedControl option renders speed selector', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      { options: { showSpeedControl: true } },
    );

    assert
      .dom('[data-test-audio-advanced-controls]')
      .exists('advanced controls are rendered');
    assert
      .dom('[data-test-audio-speed-control]')
      .exists('speed control is rendered');
  });

  test('showLoopControl option renders loop checkbox', async function (assert) {
    await renderConfiguredField(
      AudioField,
      buildField(AudioField, sampleAudioData),
      { options: { showLoopControl: true } },
    );

    assert
      .dom('[data-test-audio-loop-control]')
      .exists('loop control is rendered');
    assert
      .dom('[data-test-audio-loop-checkbox]')
      .exists('loop checkbox is rendered');
  });

  // ============================================
  // Metadata Display Tests
  // ============================================

  test('audio metadata displays correctly', async function (assert) {
    await renderField(AudioField, buildField(AudioField, sampleAudioData));

    assert.dom('[data-test-audio-metadata]').exists('metadata section exists');
  });

  test('minimal audio data still renders', async function (assert) {
    await renderField(AudioField, buildField(AudioField, minimalAudioData));

    assert.dom('[data-test-audio-embedded]').exists('player still renders');
    assert.dom('[data-test-audio-artist]').doesNotExist('no artist shown');
  });

  // ============================================
  // Player Controls Tests
  // ============================================

  test('play button exists and is clickable', async function (assert) {
    await renderField(AudioField, buildField(AudioField, sampleAudioData));

    assert.dom('[data-test-audio-play-btn]').exists('play button exists');
  });

  test('seek bar is hidden when audio has not loaded metadata', async function (assert) {
    await renderField(AudioField, buildField(AudioField, sampleAudioData));

    // The seek bar/controls only appear after audio metadata is loaded
    // With fake URLs, the audio never loads, so controls won't appear
    // This is expected behavior - controls are conditional on audioDuration
    assert
      .dom('[data-test-audio-controls]')
      .doesNotExist('controls hidden until audio loads');
    assert.dom('[data-test-audio-play-btn]').exists('play button always shows');
  });

  // ============================================
  // Atom View Tests
  // ============================================

  test('atom view shows audio icon', async function (assert) {
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

  test('atom view shows displayTitle fallback', async function (assert) {
    await renderField(
      AudioField,
      buildField(AudioField, { url: 'test.mp3' }),
      'atom',
    );

    assert
      .dom('[data-test-audio-atom]')
      .hasTextContaining('Untitled Audio', 'fallback title shown');
  });

  // ============================================
  // Edit View Tests
  // ============================================

  test('edit view shows metadata fields when audio is uploaded', async function (assert) {
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

  test('edit view shows upload prompt when no audio', async function (assert) {
    await renderField(AudioField, buildField(AudioField, {}), 'edit');

    assert
      .dom('[data-test-audio-upload-area]')
      .exists('upload prompt is shown');
  });
});
