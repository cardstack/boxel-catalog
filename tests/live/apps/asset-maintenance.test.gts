import { click, waitUntil } from '@ember/test-helpers';
import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import {
  setupLocalIndexing,
  setupOnSave,
  setupAuthEndpoints,
  setupUserSubscription,
  setupAcceptanceTestRealm,
  SYSTEM_CARD_FIXTURE_CONTENTS,
  visitOperatorMode,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

import {
  nextIdentifier,
  type AssetMaintenanceApp,
} from '../../../cards/asset-maintenance/asset-maintenance-app';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/asset-maintenance/';
const appModule = `${catalogRealmURL}cards/asset-maintenance/asset-maintenance-app`;
const planModule = `${catalogRealmURL}cards/maintenance/maintenance-plan`;
const assetModule = `${catalogRealmURL}cards/maintenance/asset`;
const year = new Date().getFullYear();

function asset(name: string, identifier: string) {
  return {
    data: {
      type: 'card',
      attributes: { name, identifier: { value: identifier } },
      meta: { adoptsFrom: { module: assetModule, name: 'Asset' } },
    },
  };
}

function app() {
  return {
    data: {
      type: 'card',
      attributes: {
        name: 'Test Plant Desk',
        config: {
          idPattern: 'TST-{yyyy}-{seq4}',
          identifierSeq: 0,
          setupStep: 2,
        },
        workOrderPattern: 'WO-{seq4}',
      },
      meta: { adoptsFrom: { module: appModule, name: 'AssetMaintenanceApp' } },
    },
  };
}

function plan(name: string) {
  return {
    data: {
      type: 'card',
      attributes: { name, active: true },
      meta: { adoptsFrom: { module: planModule, name: 'MaintenancePlan' } },
    },
  };
}

function deskText(): string {
  return document.querySelector('article.desk')?.textContent ?? '';
}

async function openTab(label: string) {
  let tab = [...document.querySelectorAll('article.desk [role="tab"]')].find(
    (el) => el.textContent?.trim() === label,
  );
  if (!tab) {
    throw new Error(`no tab labelled ${label}`);
  }
  await click(tab);
}

export function runTests() {
  module('Unit | Catalog | apps - asset maintenance identifiers', function () {
    test('nextIdentifier mints after the counter and skips taken values', function (assert) {
      let now = new Date(2026, 9, 14);
      let first = nextIdentifier('TST-{yyyy}-{seq4}', 0, [], now);
      assert.deepEqual(first, { value: 'TST-2026-0001', seq: 1 });

      let skipped = nextIdentifier(
        'TST-{yyyy}-{seq4}',
        0,
        ['TST-2026-0001', 'TST-2026-0002', undefined],
        now,
      );
      assert.deepEqual(skipped, { value: 'TST-2026-0003', seq: 3 });

      let second = nextIdentifier('WO-{seq4}', first!.seq, [], now);
      assert.deepEqual(second, { value: 'WO-0002', seq: 2 });

      assert.strictEqual(
        nextIdentifier('AST-{yyyy}', 0, ['AST-2026'], now),
        undefined,
        'a pattern with no sequence slot mints nothing',
      );
    });
  });

  module('Acceptance | Catalog | apps - asset maintenance', function (hooks) {
    setupApplicationTest(hooks);
    setupLocalIndexing(hooks);
    setupOnSave(hooks);

    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: '@testuser:localhost',
      activeRealms: [realmURL],
    });

    hooks.beforeEach(function () {
      mockMatrixUtils.createAndJoinRoom({
        sender: '@testuser:localhost',
        name: 'room-test',
      });
      setupUserSubscription();
      setupAuthEndpoints();
    });

    async function open() {
      await visitOperatorMode({
        stacks: [
          [
            {
              id: `${realmURL}AssetMaintenanceApp/main`,
              format: 'isolated',
            },
          ],
        ],
      });
      await waitUntil(() => Boolean(document.querySelector('article.desk')), {
        timeout: 30000,
      });
    }

    test('it lists the sample maintenance plans', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'AssetMaintenanceApp/main.json': app(),
          'MaintenancePlan/quarterly.json': plan('Quarterly compressor check'),
        },
      });
      await open();
      assert.ok(
        deskText().includes('Test Plant Desk'),
        'the desk shows its name',
      );

      await openTab('Plans & Parts');
      await waitUntil(() => deskText().includes('Quarterly compressor check'), {
        timeout: 30000,
      });
      assert.ok(
        deskText().includes('Plans · 1'),
        'the collection switch counts the plan',
      );
    });

    test('adding assets mints distinct identifiers from the desk pattern', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'AssetMaintenanceApp/main.json': app(),
          'Asset/existing.json': asset('Existing pump', `TST-${year}-0001`),
        },
      });
      await open();
      await openTab('Assets');
      await waitUntil(() => deskText().includes('Existing pump'), {
        timeout: 30000,
      });

      let addButton = () =>
        [...document.querySelectorAll('article.desk button')].find(
          (el) => el.textContent?.trim() === 'Add asset',
        ) as HTMLElement;
      await click(addButton());
      await click(addButton());

      let store = getService('store');
      let desk = () =>
        store.peek(`${realmURL}AssetMaintenanceApp/main`) as unknown as
          | AssetMaintenanceApp
          | undefined;
      await waitUntil(() => desk()?.config?.identifierSeq === 3, {
        timeout: 30000,
      });
      assert.strictEqual(
        desk()?.config?.identifierSeq,
        3,
        'two adds skip the taken TST-0001 and advance the counter twice',
      );

      // An Asset's tag reads its identifier, and the register lists tags,
      // so the minted ids show once the new Assets index.
      await openTab('Assets');
      await waitUntil(
        () =>
          deskText().includes(`TST-${year}-0002`) &&
          deskText().includes(`TST-${year}-0003`),
        { timeout: 30000 },
      );
      assert.ok(
        deskText().includes(`TST-${year}-0002`),
        'the first added Asset carries TST-0002',
      );
      assert.ok(
        deskText().includes(`TST-${year}-0003`),
        'the second added Asset carries TST-0003',
      );
    });

    test('it renders an empty realm with a prompt to add a plan', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'AssetMaintenanceApp/main.json': app(),
        },
      });
      await open();
      await openTab('Plans & Parts');
      await waitUntil(() => deskText().includes('No maintenance plans yet'), {
        timeout: 30000,
      });
      assert.ok(deskText().includes('Plans · 0'), 'no plans are counted');
    });
  });
}
