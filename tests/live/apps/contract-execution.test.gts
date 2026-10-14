import { click, fillIn, waitUntil } from '@ember/test-helpers';
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

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/contract-execution/';
const appModule = `${catalogRealmURL}cards/contract-execution/contract-execution-app`;
const contractModule = `${catalogRealmURL}cards/legal/contract`;
const employeeModule = `${catalogRealmURL}cards/hr/employee`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: { practiceName: 'Example Legal' },
      meta: { adoptsFrom: { module: appModule, name: 'ContractExecutionApp' } },
    },
  };
}

function employee(name: string) {
  return {
    data: {
      type: 'card',
      attributes: { name },
      meta: { adoptsFrom: { module: employeeModule, name: 'Employee' } },
    },
  };
}

function contract(
  title: string,
  status: string,
  steps: { decision: string; approver?: string }[] = [],
) {
  let relationships: Record<string, unknown> = {};
  steps.forEach((step, i) => {
    if (step.approver) {
      relationships[`approvalChain.steps.${i}.approver`] = {
        links: { self: `${realmURL}${step.approver}` },
      };
    }
  });
  return {
    data: {
      type: 'card',
      attributes: {
        title,
        status,
        contractNumber: 'TEST-0001',
        startDate: '2026-01-01',
        endDate: '2027-01-01',
        approvalChain: steps.length
          ? {
              startedAt: '2026-01-02T09:00:00.000Z',
              steps: steps.map((step) => ({
                decision: step.decision,
                openedAt: '2026-01-02T09:00:00.000Z',
              })),
            }
          : null,
      },
      relationships,
      meta: { adoptsFrom: { module: contractModule, name: 'Contract' } },
    },
  };
}

function appText(): string {
  return document.querySelector('.cx')?.textContent ?? '';
}

async function openTab(label: string) {
  let tab = [...document.querySelectorAll('.cx [role="tab"]')].find((el) =>
    el.textContent?.trim().startsWith(label),
  );
  if (!tab) {
    throw new Error(`no ${label} tab`);
  }
  await click(tab);
}

function buttonNamed(text: string): HTMLButtonElement | undefined {
  return [...document.querySelectorAll<HTMLButtonElement>('.cx button')].find(
    (b) => b.textContent?.trim() === text,
  );
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
        { timeout: 30000 },
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
      await openTab('Workspace');
      await waitUntil(() => document.querySelector('.cx .cx-pick-row'), {
        timeout: 30000,
      });
      let rows = [...document.querySelectorAll('.cx .cx-pick-row')];
      assert.strictEqual(rows.length, 1, 'the picker lists the one contract');
      assert.ok(
        rows[0]?.textContent?.includes(
          'Example Co — Master Services Agreement',
        ),
        'the row names the sample contract',
      );
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
      await openTab('Workspace');
      await waitUntil(
        () => appText().includes('No contracts in this realm yet.'),
        { timeout: 30000 },
      );

      assert.strictEqual(
        document.querySelectorAll('.cx .cx-pick-row').length,
        0,
        'the picker shows its empty state once the query has answered',
      );
    });

    test('approving the open step moves the chain and approves the contract', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ContractExecutionApp/main.json': app(),
          'Employee/approver.json': employee('Example Approver'),
          'Contract/needs-approval.json': contract(
            'Example Co — Order Form',
            'in review',
            [{ decision: 'pending', approver: 'Employee/approver' }],
          ),
        },
      });
      await open();
      await openTab('Approvals');
      await waitUntil(() => document.querySelector('.cx #cx-acting'), {
        timeout: 30000,
      });
      await fillIn('.cx #cx-acting', `${realmURL}Employee/approver`);
      let approve = buttonNamed('Approve');
      assert.ok(approve, 'the decision tray offers Approve');
      await click(approve!);

      let store = getService('store') as any;
      let id = `${realmURL}Contract/needs-approval`;
      await waitUntil(
        async () => (await store.get(id))?.status === 'approved',
        { timeout: 30000 },
      );
      let saved = await store.get(id);
      assert.strictEqual(
        saved.approvalChain.steps[0].decision,
        'approved',
        'the open step is decided',
      );
      assert.strictEqual(
        saved.approvalChain.steps[0].approver?.id,
        `${realmURL}Employee/approver`,
        'the step keeps its approver',
      );
    });

    test('a fully approved contract is signed in the workspace', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ContractExecutionApp/main.json': app(),
          'Employee/approver.json': employee('Example Approver'),
          'Contract/approved.json': contract(
            'Example Co — Renewal',
            'approved',
            [{ decision: 'approved', approver: 'Employee/approver' }],
          ),
        },
      });
      await open();
      await openTab('Repository');
      await waitUntil(() => buttonNamed('Sign in workspace'), {
        timeout: 30000,
      });
      assert.notOk(
        buttonNamed('Mark as signed'),
        'the repository has no direct way to mark a contract signed',
      );
      await click(buttonNamed('Sign in workspace')!);
      await waitUntil(() => buttonNamed('Execute contract'), {
        timeout: 30000,
      });
      assert.ok(
        appText().includes('Example Co — Renewal'),
        'the workspace opens on the contract, where Execute Contract signs it',
      );
    });
  });
}
