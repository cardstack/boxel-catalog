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
const realmURL = 'http://test-realm/rfq-to-payment/';
const appModule = `${catalogRealmURL}cards/rfq-to-payment/rfq-to-payment-app`;
const budgetModule = `${catalogRealmURL}cards/procurement/procurement-budget`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: { cardInfo: { name: 'RFQ to Payment' } },
      meta: { adoptsFrom: { module: appModule, name: 'RfqToPaymentApp' } },
    },
  };
}

function budget(department: string) {
  return {
    data: {
      type: 'card',
      attributes: { department, period: 'FY2026', budgetAmount: 50000 },
      meta: {
        adoptsFrom: { module: budgetModule, name: 'ProcurementBudget' },
      },
    },
  };
}

function appText(): string {
  return document.querySelector('article.app')?.textContent ?? '';
}

export function runTests() {
  module('Acceptance | Catalog | apps - rfq to payment', function (hooks) {
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
          [{ id: `${realmURL}RfqToPaymentApp/main`, format: 'isolated' }],
        ],
      });
      await waitUntil(() => Boolean(document.querySelector('article.app')), {
        timeout: 30000,
      });
    }

    test('it opens on the dashboard with the sample budget', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'RfqToPaymentApp/main.json': app(),
          'ProcurementBudget/design.json': budget('Design'),
        },
      });
      await open();
      await waitUntil(() => appText().includes('Design'), {
        timeout: 30000,
      });

      assert.ok(
        appText().includes('Budgets · committed vs actual'),
        'the dashboard is the opening view',
      );
      assert.notOk(
        appText().includes('No budgets yet'),
        'the budget list is not empty',
      );
    });

    test('it renders an empty realm with an empty budget list', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'RfqToPaymentApp/main.json': app(),
        },
      });
      await open();
      await waitUntil(() => appText().includes('No budgets yet'), {
        timeout: 30000,
      });

      assert.ok(
        appText().includes('RFQ to Payment'),
        'the console header renders',
      );
    });
  });
}
