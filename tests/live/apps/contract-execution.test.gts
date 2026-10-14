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
const realmURL = 'http://test-realm/contract-execution/';
const appModule = `${catalogRealmURL}cards/contract-execution/contract-execution-app`;
const contractModule = `${catalogRealmURL}cards/legal/contract`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: { practiceName: 'Example Legal' },
      meta: { adoptsFrom: { module: appModule, name: 'ContractExecutionApp' } },
    },
  };
}

function contract(title: string, status: string) {
  return {
    data: {
      type: 'card',
      attributes: {
        title,
        status,
        contractNumber: 'TEST-0001',
        startDate: '2026-01-01',
        endDate: '2027-01-01',
      },
      meta: { adoptsFrom: { module: contractModule, name: 'Contract' } },
    },
  };
}

function appText(): string {
  return document.querySelector('.cx')?.textContent ?? '';
}

async function openWorkspaceTab() {
  let tab = [...document.querySelectorAll('.cx [role="tab"]')].find((el) =>
    el.textContent?.trim().startsWith('Workspace'),
  );
  if (!tab) {
    throw new Error('no Workspace tab');
  }
  await click(tab);
}

export function runTests() {
  module('Acceptance | Catalog | apps - contract execution', function (hooks) {
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
          [{ id: `${realmURL}ContractExecutionApp/main`, format: 'isolated' }],
        ],
      });
      await waitUntil(
        () => Boolean(document.querySelector('.cx [role="tab"]')),
        {
          timeout: 30000,
        },
      );
    }

    test('it lists the sample contracts in the workspace picker', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ContractExecutionApp/main.json': app(),
          'Contract/example-msa.json': contract(
            'Example Co — Master Services Agreement',
            'draft',
          ),
        },
      });
      await open();

      assert.ok(
        appText().includes('Example Legal'),
        'the masthead names the practice',
      );
      await openWorkspaceTab();
      await waitUntil(
        () => appText().includes('Example Co — Master Services Agreement'),
        { timeout: 30000 },
      );
      assert.ok(true, 'the sample contract is in the picker');
    });

    test('it renders an empty realm without contracts', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ContractExecutionApp/main.json': app(),
        },
      });
      await open();
      await openWorkspaceTab();
      await waitUntil(
        () => appText().includes('No contracts in this realm yet.'),
        { timeout: 30000 },
      );

      assert.ok(
        appText().includes('Example Legal'),
        'the app renders around the empty workspace',
      );
    });
  });
}
