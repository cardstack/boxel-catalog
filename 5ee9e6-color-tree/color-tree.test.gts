import { click } from '@ember/test-helpers';
import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { renderCard } from '@cardstack/host/tests/helpers/render-component';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { ColorTree } from './color-tree';
import {
  buildArrays,
  chipHex,
  hueLabel,
  lerpWrapDeg,
  maxChroma,
  munsellNotation,
} from './utils/munsell';

import { getLoader } from '../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | color-tree card', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('color-tree card renders isolated view with a picked color', async function (assert) {
      let card = new ColorTree({
        selectedColor: '#c93a52',
        selectedMunsell: '5R 5/10',
      });
      await renderCard(getLoader(), card, 'isolated');

      assert.dom('.room canvas.stage').exists('the WebGL stage renders');
      assert.dom('.masthead .name').hasText('THE COLOR TREE');
      assert.dom('.panel').exists('the control panel is open');
    });

    test('color-tree card renders isolated view on a fresh instance', async function (assert) {
      await renderCard(getLoader(), new ColorTree({}), 'isolated');

      assert
        .dom('.room canvas.stage')
        .exists('the stage renders with no pick saved');
    });

    test('color-tree card renders embedded view with a picked color', async function (assert) {
      let card = new ColorTree({
        selectedColor: '#c93a52',
        selectedMunsell: '5R 5/10',
      });
      await renderCard(getLoader(), card, 'embedded');

      assert.dom('.ct-embedded .detail').containsText('#c93a52');
      assert.dom('.ct-embedded .detail').containsText('5R 5/10');
    });

    test('color-tree card renders embedded empty state', async function (assert) {
      await renderCard(getLoader(), new ColorTree({}), 'embedded');

      assert.dom('.ct-embedded .detail').hasText('no chip picked yet');
    });

    test('color-tree card renders fitted view with a picked color', async function (assert) {
      let card = new ColorTree({
        selectedColor: '#c93a52',
        selectedMunsell: '5R 5/10',
      });
      await renderCard(getLoader(), card, 'fitted');

      assert.dom('.ct-fit').containsText('5R 5/10');
      assert.dom('.ct-fit').containsText('#c93a52');
    });

    test('color-tree card renders fitted empty state', async function (assert) {
      await renderCard(getLoader(), new ColorTree({}), 'fitted');

      assert.dom('.ct-fit').containsText('Munsell solid');
      assert.dom('.ct-fit').containsText('no chip picked yet');
    });

    test('color-tree card hint speaks to the view on stage', async function (assert) {
      await renderCard(getLoader(), new ColorTree({}), 'isolated');

      assert.dom('.hint').containsText('drag to tumble');
      assert
        .dom('.hint')
        .doesNotContainText(
          'copy its hex',
          'no pick hint while the atlas is closed',
        );

      let [, scanButton] = [
        ...document.querySelectorAll('.stage-actions button'),
      ];
      await click(scanButton as Element);

      assert.dom('.hint').containsText('copy its hex');
      assert
        .dom('.hint')
        .doesNotContainText(
          'drag to tumble',
          'no tumble hint on the open atlas',
        );
    });

    test('color-tree card hamburger docks at the panel edge while it is open', async function (assert) {
      await renderCard(getLoader(), new ColorTree({}), 'isolated');

      assert.dom('.hamburger').hasClass('panel-open');
      assert.dom('.hamburger').hasText('✕');

      await click('.hamburger');

      assert.dom('.panel').doesNotExist('the panel closes');
      assert.dom('.hamburger').doesNotHaveClass('panel-open');
      assert.dom('.hamburger').hasText('☰');
    });

    test('color-tree card munsellNotation formats chromatic and neutral chips', function (assert) {
      assert.strictEqual(munsellNotation(0, 5, 12), '5R 5/12');
      assert.strictEqual(munsellNotation(0.5, 4, 8), '5BG 4/8');
      assert.strictEqual(munsellNotation(0.3, 4, 0), 'N 4/');
    });

    test('color-tree card maxChroma peaks at each hue peak and never goes negative', function (assert) {
      assert.strictEqual(maxChroma(0, 5), 14, '5R peaks at chroma 14, value 5');
      assert.true(
        maxChroma(0, 9) < maxChroma(0, 5),
        'chroma falls off away from the peak',
      );
      for (let v = 0; v <= 10; v++) {
        assert.true(maxChroma(0.7, v) >= 0, `chroma at value ${v} is >= 0`);
      }
    });

    test('color-tree card chipHex returns a css hex color', function (assert) {
      assert.true(/^#[0-9a-f]{6}$/.test(chipHex(0, 5, 12)));
      assert.true(
        /^#[0-9a-f]{6}$/.test(chipHex(0, 5, 0)),
        'neutral chips also format as hex',
      );
    });

    test('color-tree card hue helpers wrap around the hue circle', function (assert) {
      assert.strictEqual(hueLabel(0), '5R');
      assert.strictEqual(hueLabel(0.5), '5BG');
      // between 5R (357°) and 5YR (32°) the blend crosses 0°, not 180°
      let deg = lerpWrapDeg(0.05);
      assert.true(deg >= 0 && deg < 32, `deg ${deg} takes the short way`);
    });

    test('color-tree card buildArrays produces a consistent lattice', function (assert) {
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
