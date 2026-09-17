import { click } from '@ember/test-helpers';
import { module, skip, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { renderCard } from '@cardstack/host/tests/helpers/render-component';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { ColorTreeField } from './color-tree-field';
import { ColorTreeFieldExample } from './example/color-tree-field-playground-example';
import {
  buildArrays,
  chipColor,
  chipHex,
  hslToRgb,
  hueLabel,
  lerpWrap,
  lerpWrapDeg,
  maxChroma,
  munsellNotation,
  rgbHex,
  toHex2,
} from './utils/munsell';

import { getLoader } from '../tests/helpers/field-test-helpers';

// The studio draws through a WebGL canvas. A browser with no GPU and no
// software rasteriser returns no context, and the renderer throws while it is
// being constructed, which fails the test before any assertion runs. These
// render where a context is available and report as skipped where it is not,
// so the failure mode is visible rather than silent.
function hasWebGLContext(): boolean {
  try {
    let canvas = document.createElement('canvas');
    return Boolean(canvas.getContext('webgl2') ?? canvas.getContext('webgl'));
  } catch {
    return false;
  }
}

const studioTest = hasWebGLContext() ? test : skip;

export function runTests() {
  module('Rendering | color-tree field', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    studioTest(
      'color-tree field example renders the studio as the edit format',
      async function (assert) {
        let card = new ColorTreeFieldExample({
          pick: new ColorTreeField({ hex: '#2e8b6a', munsell: '5G 5/8' }),
          title: 'Color Tree Field',
        });
        await renderCard(getLoader(), card, 'isolated');

        assert
          .dom('[data-test-color-tree-field-edit] canvas.stage')
          .exists('the edit format hosts the 3D studio');
        assert
          .dom('[data-test-color-tree-field-edit] .room')
          .hasClass('compact', 'the studio runs bounded in a form');
        assert
          .dom('[data-test-color-tree-field-embedded]')
          .containsText('#2e8b6a');
        assert.dom('[data-test-color-tree-field-atom]').containsText('5G 5/8');
      },
    );

    studioTest(
      'color-tree field renders the designed empty state',
      async function (assert) {
        await renderCard(
          getLoader(),
          new ColorTreeFieldExample({}),
          'isolated',
        );

        assert
          .dom('[data-test-color-tree-field-edit] canvas.stage')
          .exists('the studio renders with no pick saved');
        assert
          .dom('[data-test-color-tree-field-embedded]')
          .containsText('no chip picked yet');
      },
    );

    studioTest(
      'color-tree field hint speaks to the view on stage',
      async function (assert) {
        await renderCard(
          getLoader(),
          new ColorTreeFieldExample({}),
          'isolated',
        );

        assert.dom('.hint').containsText('drag to tumble');
        assert
          .dom('.hint')
          .doesNotContainText(
            'copy its hex',
            'no pick hint while the atlas is closed',
          );

        await click('[data-test-scan]');

        assert.dom('.hint').containsText('copy its hex');
        assert
          .dom('.hint')
          .doesNotContainText(
            'drag to tumble',
            'no tumble hint on the open atlas',
          );
      },
    );

    studioTest(
      'color-tree field hamburger docks at the panel edge while it is open',
      async function (assert) {
        await renderCard(
          getLoader(),
          new ColorTreeFieldExample({}),
          'isolated',
        );

        assert
          .dom('.panel')
          .doesNotExist('the compact studio starts with the panel closed');
        assert.dom('.hamburger').hasText('☰');

        await click('[data-test-toggle-panel]');

        assert.dom('.panel').exists('the panel opens');
        assert.dom('.hamburger').hasClass('panel-open');
        assert.dom('.hamburger').hasText('✕');
      },
    );

    studioTest(
      'color-tree field scan dial only engages while a cut is open',
      async function (assert) {
        await renderCard(
          getLoader(),
          new ColorTreeFieldExample({}),
          'isolated',
        );
        await click('[data-test-toggle-panel]');

        assert
          .dom('input[aria-label="scan"]')
          .isDisabled('the scan dial is greyed out on the closed solid');

        await click('[data-test-scan]');

        assert
          .dom('input[aria-label="scan"]')
          .isEnabled('opening the atlas engages the scan dial');
      },
    );

    studioTest(
      'color-tree field scout miniature toggles away over the open atlas',
      async function (assert) {
        await renderCard(
          getLoader(),
          new ColorTreeFieldExample({}),
          'isolated',
        );

        assert
          .dom('[data-test-toggle-mini]')
          .doesNotExist('no scout toggle while the atlas is closed');

        await click('[data-test-scan]');

        assert.dom('.mini-frame').exists('the scout shows on the open atlas');
        assert
          .dom('[data-test-toggle-mini]')
          .hasAttribute('aria-pressed', 'true');

        await click('[data-test-toggle-mini]');

        assert
          .dom('.mini-frame')
          .doesNotExist('the toggle waves the scout away');
        assert
          .dom('[data-test-toggle-mini]')
          .hasAttribute('aria-pressed', 'false');

        await click('[data-test-toggle-mini]');

        assert.dom('.mini-frame').exists('the toggle brings the scout back');
      },
    );

    test('color-tree field munsellNotation formats chromatic and neutral chips', function (assert) {
      assert.strictEqual(munsellNotation(0, 5, 12), '5R 5/12');
      assert.strictEqual(munsellNotation(0.5, 4, 8), '5BG 4/8');
      assert.strictEqual(munsellNotation(0.3, 4, 0), 'N 4/');
    });

    test('color-tree field maxChroma peaks at each hue peak and never goes negative', function (assert) {
      assert.strictEqual(maxChroma(0, 5), 14, '5R peaks at chroma 14, value 5');
      assert.true(
        maxChroma(0, 9) < maxChroma(0, 5),
        'chroma falls off away from the peak',
      );
      for (let v = 0; v <= 10; v++) {
        assert.true(maxChroma(0.7, v) >= 0, `chroma at value ${v} is >= 0`);
      }
    });

    test('color-tree field chipHex returns a css hex color', function (assert) {
      assert.true(/^#[0-9a-f]{6}$/.test(chipHex(0, 5, 12)));
      assert.true(
        /^#[0-9a-f]{6}$/.test(chipHex(0, 5, 0)),
        'neutral chips also format as hex',
      );
    });

    test('color-tree field hue helpers wrap around the hue circle', function (assert) {
      assert.strictEqual(hueLabel(0), '5R');
      assert.strictEqual(hueLabel(0.5), '5BG');
      // between 5R (357°) and 5YR (32°) the blend crosses 0°, not 180°
      let deg = lerpWrapDeg(0.05);
      assert.true(deg >= 0 && deg < 32, `deg ${deg} takes the short way`);
    });

    test('color-tree field toHex2 clamps and pads to two hex digits', function (assert) {
      assert.strictEqual(toHex2(0), '00');
      assert.strictEqual(toHex2(1), 'ff', 'above 1 clamps to ff');
      assert.strictEqual(toHex2(-1), '00', 'below 0 clamps to 00');
      assert.strictEqual(toHex2(0.5), '80', '0.5 rounds to 128 → 80');
    });

    test('color-tree field rgbHex assembles a css hex color from 0-1 channels', function (assert) {
      assert.strictEqual(rgbHex(1, 0, 0), '#ff0000');
      assert.strictEqual(rgbHex(0, 0, 0), '#000000');
    });

    test('color-tree field hslToRgb reproduces primary hues at full saturation', function (assert) {
      let [r, g, b] = hslToRgb(0, 1, 0.5);
      assert.true(r > 0.95 && g < 0.05 && b < 0.05, 'hue 0 is red');
      let [r2, g2, b2] = hslToRgb(120, 1, 0.5);
      assert.true(r2 < 0.05 && g2 > 0.95 && b2 < 0.05, 'hue 120 is green');
    });

    test('color-tree field chipColor renders neutrals as gray and chromatic chips as tinted', function (assert) {
      let [r, g, b] = chipColor(0, 5, 0);
      assert.true(
        Math.abs(r - g) < 0.05 && Math.abs(g - b) < 0.05,
        'a zero-chroma chip is neutral (r ≈ g ≈ b)',
      );
      let [rc, gc, bc] = chipColor(0, 5, 12);
      assert.false(
        Math.abs(rc - gc) < 0.02 && Math.abs(gc - bc) < 0.02,
        'a saturated chip is not neutral',
      );
    });

    test('color-tree field lerpWrap eases smoothly between adjacent array entries', function (assert) {
      let arr = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90];
      assert.strictEqual(lerpWrap(arr, 0), 0, 'exact index returns the value');
      let mid = lerpWrap(arr, 0.05);
      assert.true(
        mid > 0 && mid < 10,
        'halfway between two ticks interpolates between them',
      );
    });

    test('color-tree field buildArrays produces a consistent lattice', function (assert) {
      let arrays = buildArrays(10, 0);
      let n = arrays.val.length;
      assert.true(n > 0, 'the lattice has chips');
      assert.strictEqual(arrays.tree.length, n * 3, 'a tree address per chip');
      assert.strictEqual(
        arrays.sphere.length,
        n * 3,
        'a sphere address per chip',
      );
      assert.strictEqual(arrays.cols.length, n * 3, 'a color per chip');
      assert.strictEqual(arrays.edg.length, n, 'an edge size per chip');
      assert.true(
        arrays.edg.every((e) => e > 0),
        'every cube has positive size',
      );
      assert.strictEqual(
        arrays.chr.filter((c) => c === 0).length,
        11,
        'the gray trunk runs value 0 through 10',
      );
    });
  });
}
