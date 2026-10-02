import { module, test } from 'qunit';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { renderCard } from '@cardstack/host/tests/helpers/render-component';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { DurationField } from './duration-field';
import { Meeting } from './meeting';

import { getLoader } from '../../tests/helpers/field-test-helpers';

export function runTests() {
  module('Rendering | hr meeting card', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('fitted meeting speaks its full date right after the title', async function (assert) {
      let meeting = new Meeting({
        name: 'Design review',
        meetingType: 'interview',
        date: new Date(2026, 2, 3, 9, 30),
      });
      await renderCard(getLoader(), meeting, 'fitted');

      assert
        .dom('.datebox time')
        .exists({ count: 3 }, 'the tile shows month, day and weekday');
      assert
        .dom('.datebox time:not([aria-hidden="true"])')
        .doesNotExist('every tile part is hidden from assistive tech');
      assert
        .dom('.fit-time')
        .hasAttribute('aria-hidden', 'true', 'the time line is hidden too');
      assert
        .dom('.datebox [data-test-pretui-visually-hidden]')
        .doesNotExist('nothing in the tile is spoken before the title');
      assert
        .dom('.fit-head > .fit-name + [data-test-pretui-visually-hidden]')
        .containsText(
          'Tuesday, March 3, 2026',
          'the full date is spoken right after the title',
        )
        .containsText('9:30 AM', 'with the start time');
    });

    test('fitted meeting with only a duration shows it on the tier-2 line', async function (assert) {
      let meeting = new Meeting({
        name: 'Catch-up',
        duration: new DurationField({ value: 30, unit: 'minutes' }),
      });
      await renderCard(getLoader(), meeting, 'fitted');

      assert
        .dom('.fit-eb')
        .hasText('30 min', 'the duration shows without a meeting type');
      assert
        .dom('.datebox [data-test-unset-marker]')
        .containsText('No date', 'the tile speaks the missing date');
      assert
        .dom('.fit-head [data-test-pretui-visually-hidden]')
        .doesNotExist('no spoken date without a date');
    });
  });
}
