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
const realmURL = 'http://test-realm/revenue-os/';
const appModule = `${catalogRealmURL}cards/revenue-os/revenue-os`;
const opportunityModule = `${catalogRealmURL}cards/crm/opportunity`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: {
        orgName: 'Example Revenue Co',
        cardInfo: { name: 'Revenue OS' },
      },
      meta: { adoptsFrom: { module: appModule, name: 'RevenueOs' } },
    },
  };
}

function opportunity(name: string, stage: string) {
  return {
    data: {
      type: 'card',
      attributes: { name, stage },
      meta: { adoptsFrom: { module: opportunityModule, name: 'Opportunity' } },
    },
  };
}

function appText(): string {
  return document.querySelector('.app')?.textContent ?? '';
}

export function runTests() {
  module('Acceptance | Catalog | apps - revenue os', function (hooks) {
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
        stacks: [[{ id: `${realmURL}RevenueOs/main`, format: 'isolated' }]],
      });
      await waitUntil(() => appText().includes('Pipeline'), {
        timeout: 30000,
      });
    }

    test('it puts the sample deals on the pipeline board', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'RevenueOs/main.json': app(),
          'Opportunity/northwind.json': opportunity(
            'Northwind renewal',
            'qualified',
          ),
          'Opportunity/acme.json': opportunity('Acme expansion', 'proposal'),
        },
      });
      await open();
      await waitUntil(() => appText().includes('Northwind renewal'), {
        timeout: 30000,
      });

      assert.ok(
        appText().includes('Acme expansion'),
        'both deals are on the board',
      );
    });

    test('it opens on an empty realm without breaking', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'RevenueOs/main.json': app(),
        },
      });
      await open();
      await waitUntil(() => !appText().includes('Loading pipeline'), {
        timeout: 30000,
      });

      assert.ok(
        appText().includes('Revenue OS'),
        'the app renders its title with no records',
      );
    });
  });
}
