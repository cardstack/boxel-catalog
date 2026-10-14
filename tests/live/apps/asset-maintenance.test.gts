import { click, waitUntil } from '@ember/test-helpers';
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

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/asset-maintenance/';
const appModule = `${catalogRealmURL}cards/asset-maintenance/asset-maintenance-app`;
const planModule = `${catalogRealmURL}cards/maintenance/maintenance-plan`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: {
        name: 'Test Plant Desk',
        config: { idPattern: 'AST-{seq4}', setupStep: 2 },
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
