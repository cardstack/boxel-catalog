import { waitUntil } from '@ember/test-helpers';
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
const realmURL = 'http://test-realm/sole-vault/';
const appModule = `${catalogRealmURL}cards/sole-vault/sole-vault-app`;
const itemModule = `${catalogRealmURL}cards/collectibles/collection-item`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: { cardInfo: { name: 'Sole Vault' } },
      meta: { adoptsFrom: { module: appModule, name: 'SoleVaultApp' } },
    },
  };
}

function item(name: string) {
  return {
    data: {
      type: 'card',
      attributes: { variant: '10', cardInfo: { name } },
      meta: { adoptsFrom: { module: itemModule, name: 'CollectionItem' } },
    },
  };
}

function appText(): string {
  return document.querySelector('article.vault')?.textContent ?? '';
}

function pairs(): string | undefined {
  let fact = [...document.querySelectorAll('article.vault .fact')].find(
    (el) => el.querySelector('dt')?.textContent?.trim() === 'Pairs',
  );
  return fact?.querySelector('dd')?.textContent?.trim();
}

export function runTests() {
  module('Acceptance | Catalog | apps - sole vault', function (hooks) {
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
        stacks: [[{ id: `${realmURL}SoleVaultApp/main`, format: 'isolated' }]],
      });
      await waitUntil(() => Boolean(document.querySelector('article.vault')), {
        timeout: 30000,
      });
    }

    test('it counts the collection items in the realm', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'SoleVaultApp/main.json': app(),
          'CollectionItem/one.json': item('Test Pair One'),
          'CollectionItem/two.json': item('Test Pair Two'),
        },
      });
      await open();
      await waitUntil(() => pairs() === '2', { timeout: 30000 });

      assert.strictEqual(pairs(), '2', 'the ledger counts both pairs');
      assert.ok(
        document.querySelector('article.vault [role="tablist"]'),
        'the sections render as tabs',
      );
    });

    test('it renders an empty realm with a prompt to add a pair', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'SoleVaultApp/main.json': app(),
        },
      });
      await open();
      await waitUntil(() => appText().includes('Nothing catalogued yet'), {
        timeout: 30000,
      });

      assert.strictEqual(pairs(), '0', 'the ledger counts no pairs');
    });
  });
}
