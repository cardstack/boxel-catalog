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
const realmURL = 'http://test-realm/audit-compliance-desk/';
const appModule = `${catalogRealmURL}cards/audit-compliance-desk/audit-compliance-desk`;
const documentModule = `${catalogRealmURL}cards/audit/document`;

function desk() {
  return {
    data: {
      type: 'card',
      attributes: { organisation: 'Northbridge Industries' },
      meta: { adoptsFrom: { module: appModule, name: 'AuditComplianceDesk' } },
    },
  };
}

function documentCard(title: string, contentHash: string | null) {
  return {
    data: {
      type: 'card',
      attributes: { title, kind: 'evidence', contentHash },
      meta: { adoptsFrom: { module: documentModule, name: 'Document' } },
    },
  };
}

function deskText(): string {
  return document.querySelector('.desk')?.textContent ?? '';
}

function stat(label: string): string | undefined {
  let stats = [...document.querySelectorAll('.desk .stat')];
  let match = stats.find((s) => s.querySelector('.sl')?.textContent === label);
  return match?.querySelector('.sv')?.textContent?.trim();
}

export function runTests() {
  module(
    'Acceptance | Catalog | apps - audit compliance desk',
    function (hooks) {
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
            [{ id: `${realmURL}AuditComplianceDesk/main`, format: 'isolated' }],
          ],
        });
        await waitUntil(() => Boolean(document.querySelector('.desk')), {
          timeout: 30000,
        });
      }

      test('it lists the sample documents in the evidence register', async function (assert) {
        await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'AuditComplianceDesk/main.json': desk(),
            'Document/hashed.json': documentCard(
              'Access review Q3',
              'sha256:test0001',
            ),
            'Document/unhashed.json': documentCard(
              'Supplier attestation',
              null,
            ),
          },
        });
        await open();
        await waitUntil(() => deskText().includes('Supplier attestation'), {
          timeout: 30000,
        });

        assert.ok(
          deskText().includes('Access review Q3'),
          'both documents are in the register',
        );
        assert.strictEqual(stat('documents'), '2', 'the masthead counts them');
        assert.strictEqual(stat('hashed'), '1', 'one is hashed');
        assert.strictEqual(stat('not yet hashed'), '1', 'one is not');
      });

      test('it renders an empty realm with an empty register', async function (assert) {
        await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'AuditComplianceDesk/main.json': desk(),
          },
        });
        await open();
        await waitUntil(
          () => deskText().includes('No documents in the register yet'),
          { timeout: 30000 },
        );

        assert.strictEqual(stat('documents'), '0', 'the masthead counts none');
      });
    },
  );
}
