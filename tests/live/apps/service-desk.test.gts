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
const realmURL = 'http://test-realm/service-desk/';
const appModule = `${catalogRealmURL}cards/service-desk-app/service-desk`;
const ticketModule = `${catalogRealmURL}cards/service-desk/ticket`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: { name: 'Test Desk' },
      meta: { adoptsFrom: { module: appModule, name: 'ServiceDesk' } },
    },
  };
}

function ticket(reference: string, subject: string) {
  return {
    data: {
      type: 'card',
      attributes: {
        reference,
        subject,
        status: 'Open',
        priority: 'P2',
        openedAt: '2026-08-12T03:00:00.000Z',
      },
      meta: { adoptsFrom: { module: ticketModule, name: 'Ticket' } },
    },
  };
}

function consoleText(): string {
  return document.querySelector('.console')?.textContent ?? '';
}

export function runTests() {
  module('Acceptance | Catalog | apps - service desk', function (hooks) {
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
        stacks: [[{ id: `${realmURL}ServiceDesk/main`, format: 'isolated' }]],
      });
      await waitUntil(() => Boolean(document.querySelector('.console')), {
        timeout: 30000,
      });
    }

    test('it lists the sample tickets in the queue', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ServiceDesk/main.json': app(),
          'Ticket/a.json': ticket('#1', 'Invoice download fails silently'),
          'Ticket/b.json': ticket('#2', 'Report export garbles accents'),
        },
      });
      await open();
      await waitUntil(
        () => consoleText().includes('Invoice download fails silently'),
        { timeout: 30000 },
      );

      assert.ok(
        consoleText().includes('Report export garbles accents'),
        'both tickets are in the queue',
      );
      assert.ok(
        document.querySelector('.console h1')?.textContent?.includes('Test Desk'),
        'the masthead names the desk',
      );
    });

    test('it renders an empty realm with an empty queue', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ServiceDesk/main.json': app(),
        },
      });
      await open();
      await waitUntil(() => consoleText().includes('No tickets yet'), {
        timeout: 30000,
      });

      assert.ok(
        consoleText().includes('Pick a ticket'),
        'the detail pane invites a pick',
      );
    });
  });
}
