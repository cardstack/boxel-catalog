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
const realmURL = 'http://test-realm/order-fulfilment/';
const appModule = `${catalogRealmURL}cards/order-fulfilment/order-fulfilment-app`;
const orderModule = `${catalogRealmURL}cards/fulfilment/fulfilment-order`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: { operationName: 'Example Goods' },
      meta: { adoptsFrom: { module: appModule, name: 'OrderFulfilmentApp' } },
    },
  };
}

function order(orderNumber: string, customerName: string, status: string) {
  return {
    data: {
      type: 'card',
      attributes: { orderNumber, customerName, status, priority: 'normal' },
      meta: { adoptsFrom: { module: orderModule, name: 'FulfilmentOrder' } },
    },
  };
}

function appText(): string {
  return document.querySelector('.app')?.textContent ?? '';
}

export function runTests() {
  module('Acceptance | Catalog | apps - order fulfilment', function (hooks) {
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
          [{ id: `${realmURL}OrderFulfilmentApp/main`, format: 'isolated' }],
        ],
      });
      await waitUntil(() => Boolean(document.querySelector('.app')), {
        timeout: 30000,
      });
    }

    test('it puts the sample orders on the fulfilment board', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'OrderFulfilmentApp/main.json': app(),
          'FulfilmentOrder/one.json': order(
            'ORD-TEST-0001',
            'Example Customer',
            'pending',
          ),
          'FulfilmentOrder/two.json': order(
            'ORD-TEST-0002',
            'Sample Buyer',
            'packing',
          ),
        },
      });
      await open();
      await waitUntil(() => appText().includes('ORD-TEST-0001'), {
        timeout: 30000,
      });

      assert.ok(
        appText().includes('ORD-TEST-0002'),
        'both open orders are on the board',
      );
      assert.ok(
        appText().includes('Example Goods'),
        'the masthead names the operation',
      );
    });

    test('it renders an empty realm with an empty board', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'OrderFulfilmentApp/main.json': app(),
        },
      });
      await open();
      await waitUntil(() => appText().includes('No orders in the pipeline'), {
        timeout: 30000,
      });

      assert.ok(
        appText().includes('Example Goods'),
        'the app renders with no fulfilment data',
      );
    });
  });
}
