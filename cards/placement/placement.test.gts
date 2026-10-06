import { module, test } from 'qunit';
import { click } from '@ember/test-helpers';

import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import {
  renderCard,
  renderComponent,
} from '@cardstack/host/tests/helpers/render-component';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import {
  PlacementField,
  PlacementZoneField,
  isDirty,
} from '../../fields/placement/placement-vocabulary';
import type { PlacementItem } from '../../components/placement-palette';
import { getLoader } from '../../tests/helpers/field-test-helpers';

import { PersonBase } from '../people/person-base';
import { PlacementBoard } from './placement-board';
import { PlacementDropZone } from './components/placement-drop-zone';

const ITEMS: Record<string, PlacementItem> = {
  'Tech/a': { id: 'Tech/a', title: 'A' },
  'Tech/b': { id: 'Tech/b', title: 'B' },
};
const itemFor = (id: string) => ITEMS[id];
const noop = () => {};
const actions = () => [{ label: 'Remove', onSelect: noop }];

function placed(itemId: string, zoneKey: string, seq: number) {
  return new PlacementField({ itemId, zoneKey, seq });
}

async function chooseMenuItem(trigger: string, label: string) {
  await click(`[aria-label="${trigger}"]`);
  let item = [
    ...document.querySelectorAll(
      '[data-test-pretui-menu-panel] [role^="menuitem"]',
    ),
  ].find((el) => el.textContent?.trim().startsWith(label));
  if (!item) {
    throw new Error(`no menu item "${label}"`);
  }
  await click(item);
}

export function runTests() {
  module('Unit | placement vocabulary', function () {
    test('a note-only edit makes the draft dirty', function (assert) {
      let committed = [
        new PlacementField({ itemId: 'Tech/a', zoneKey: 'm', seq: 0 }),
      ];
      let draft = [
        new PlacementField({
          itemId: 'Tech/a',
          zoneKey: 'm',
          seq: 0,
          note: 'lead',
        }),
      ];
      assert.true(isDirty(committed, draft));
    });
  });

  module('Rendering | placement drop zone', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('a locked zone keeps its chips', async function (assert) {
      const zone = new PlacementZoneField({ key: 'm', label: 'Mechanical' });
      const placements = [placed('Tech/a', 'm', 0)];
      await renderComponent(
        <template>
          <PlacementDropZone
            @zone={{zone}}
            @placements={{placements}}
            @itemFor={{itemFor}}
            @onRemove={{noop}}
            @menuFor={{actions}}
            @isLocked={{true}}
          />
        </template>,
      );
      assert.dom('.placed-open').hasAttribute('draggable', 'false');
      assert.dom('.placed-remove').doesNotExist();
      assert.dom('.placed-menu').doesNotExist();
    });

    test('the over-capacity warning follows the zone occupancy', async function (assert) {
      const unlimited = new PlacementZoneField({ key: 'm', capacity: -1 });
      const placements = [placed('Tech/a', 'm', 0), placed('Tech/b', 'm', 1)];
      await renderComponent(
        <template>
          <PlacementDropZone
            @zone={{unlimited}}
            @placements={{placements}}
            @itemFor={{itemFor}}
          />
        </template>,
      );
      assert
        .dom('.zone-warning')
        .doesNotExist('a non-positive capacity is unlimited');

      const single = new PlacementZoneField({ key: 'm', capacity: 1 });
      await renderComponent(
        <template>
          <PlacementDropZone
            @zone={{single}}
            @placements={{placements}}
            @itemFor={{itemFor}}
          />
        </template>,
      );
      assert.dom('.zone-warning').hasText('Over capacity');
    });
  });

  module('Rendering | placement board', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    function board() {
      return new PlacementBoard({
        zones: [
          new PlacementZoneField({ key: 'm', label: 'Mechanical' }),
          new PlacementZoneField({ key: 'b', label: 'Bench' }),
        ],
        pool: [
          new PersonBase({ id: 'https://example.test/Tech/a', name: 'A' }),
          new PersonBase({ id: 'https://example.test/Tech/b', name: 'B' }),
        ],
        draft: [],
        placements: [],
      });
    }

    test('an item can be placed, reordered and removed from the keyboard', async function (assert) {
      let b = board();
      await renderCard(getLoader(), b, 'isolated');

      await chooseMenuItem('Place A', 'Place in Bench');
      assert.deepEqual(
        b.draft.map((p) => [p.itemId, p.zoneKey]),
        [['Tech/a', 'b']],
        'A is placed in Bench',
      );

      await chooseMenuItem('Place B', 'Place in Bench');
      await chooseMenuItem('Move B', 'Move up');
      assert.deepEqual(
        [...b.draft]
          .sort((x, y) => (x.seq ?? 0) - (y.seq ?? 0))
          .map((p) => p.itemId),
        ['Tech/b', 'Tech/a'],
        'B moved above A',
      );

      await chooseMenuItem('Move A', 'Remove');
      assert.deepEqual(
        b.draft.map((p) => p.itemId),
        ['Tech/b'],
        'A is back in the palette',
      );
    });

    test('moving an item keeps its note', async function (assert) {
      let b = board();
      b.draft = [
        new PlacementField({
          itemId: 'Tech/a',
          zoneKey: 'm',
          seq: 0,
          note: 'lead',
        }),
      ];
      await renderCard(getLoader(), b, 'isolated');
      await chooseMenuItem('Move A', 'Move to');
      let bench = [
        ...document.querySelectorAll(
          '[data-test-pretui-menu-panel] [role^="menuitem"]',
        ),
      ].find((el) => el.textContent?.trim() === 'Bench');
      assert.ok(bench, 'the Move to submenu lists Bench');
      await click(bench as Element);
      assert.strictEqual(b.draft[0]?.zoneKey, 'b', 'moved to Bench');
      assert.strictEqual(b.draft[0]?.note, 'lead', 'note kept');
    });
  });
}
