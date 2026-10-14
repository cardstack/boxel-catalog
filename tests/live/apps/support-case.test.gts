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
const realmURL = 'http://test-realm/support-case/';
const appModule = `${catalogRealmURL}cards/support-case/support-case-app`;
const caseModule = `${catalogRealmURL}cards/service-desk/case`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: {
        appName: 'Support Ops',
        cardInfo: { name: 'Support Ops Desk' },
      },
      meta: { adoptsFrom: { module: appModule, name: 'SupportCaseApp' } },
    },
  };
}

function supportCase(subject: string, status: string) {
  return {
    data: {
      type: 'card',
      attributes: { subject, status, severity: 'high' },
      meta: { adoptsFrom: { module: caseModule, name: 'Case' } },
    },
  };
}

function deskText(): string {
  return document.querySelector('article.desk')?.textContent ?? '';
}

function openCasesTile(count: number) {
  return document.querySelector(`article.desk [aria-label^="open cases: ${count}"]`);
}

export function runTests() {
  module('Acceptance | Catalog | apps - support case', function (hooks) {
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
        stacks: [[{ id: `${realmURL}SupportCaseApp/main`, format: 'isolated' }]],
      });
      await waitUntil(() => Boolean(document.querySelector('article.desk')), {
        timeout: 30000,
      });
    }

    test('it counts the sample cases on the command center wall', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'SupportCaseApp/main.json': app(),
          'Case/login.json': supportCase('Login page times out', 'open'),
          'Case/export.json': supportCase('Export drops the last row', 'resolved'),
        },
      });
      await open();
      await waitUntil(() => Boolean(openCasesTile(1)), { timeout: 30000 });

      assert.ok(openCasesTile(1), 'only the unresolved case counts as open');
      assert.ok(
        deskText().includes('Setup is not finished'),
        'a desk with no completed setup says so',
      );
    });

    test('it renders an empty realm with a zero wall', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'SupportCaseApp/main.json': app(),
        },
      });
      await open();
      await waitUntil(() => Boolean(openCasesTile(0)), { timeout: 30000 });

      assert.ok(openCasesTile(0), 'the wall counts no open cases');
    });
  });
}
