import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import {
  settleRealmRenders,
  setupCardLogs,
  setupIntegrationTestRealm,
  setupLocalIndexing,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/reconcile-operations/';
const accounting = `${catalogRealmURL}cards/accounting/`;
const USER = '@testuser:localhost';

// The books hold a $1,000 deposit and a $50 check; the statement shows only the deposit.
function reconciliation() {
  return {
    data: {
      type: 'card',
      attributes: {
        account: '1000',
        side: 'debit',
        statementDate: '2027-01-31',
        endingBalanceMinor: 100000,
        outstanding: [],
        cleared: [],
        status: 'draft',
      },
      meta: {
        adoptsFrom: {
          module: `${accounting}ledger-close`,
          name: 'BankReconciliation',
        },
      },
    },
  };
}
const ticked = {
  cleared: [{ key: 'jan-deposit', date: '2027-01-10', amountMinor: 100000 }],
  outstanding: [{ ref: 'jan-check', amountMinor: -5000 }],
};

export function runTests() {
  module('Catalog | accounting - reconciliation operations', function (hooks) {
    setupRenderingTest(hooks);
    setupLocalIndexing(hooks);

    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: USER,
      activeRealms: [realmURL],
      autostart: true,
    });

    let operations: any;
    let adapter: any;
    let hostTransport: unknown;

    setupCardLogs(hooks, async () =>
      getService('loader-service').loader.import('@cardstack/base/card-api'),
    );

    hooks.beforeEach(async function () {
      hostTransport = (globalThis as any)._CARDSTACK_OPERATIONS_TRANSPORT;
      ({ adapter } = await setupIntegrationTestRealm({
        mockMatrixUtils,
        realmURL,
        enforcePermissions: true,
        permissions: { [USER]: ['read', 'write', 'realm-owner'] },
        contents: {
          'BankReconciliation/finish.json': reconciliation(),
          'BankReconciliation/off.json': reconciliation(),
          'BankReconciliation/draft.json': reconciliation(),
        },
      }));
      let loader: any = getService('loader-service').loader;
      ({ operations } = await loader.import('@cardstack/base/operations'));
      await getService('realm').login(realmURL);
      getService('operations');
    });

    hooks.afterEach(function () {
      (globalThis as any)._CARDSTACK_OPERATIONS_TRANSPORT = hostTransport;
    });

    async function cardAt(path: string) {
      let card = await getService('store').get(`${realmURL}${path}`);
      if (!card || (card as any).errors) {
        throw new Error(
          `expected ${path} to load, got ${JSON.stringify(card)}`,
        );
      }
      return card as any;
    }

    async function stored(path: string) {
      let file = await adapter.openFile(`${path}.json`);
      return JSON.parse(file.content as string).data.attributes;
    }

    test('recording the ticks and finishing in one batch passes the cent check', async function (assert) {
      let rec = await cardAt('BankReconciliation/finish');
      await operations(rec).atomic((b: any) => [
        b.record(ticked),
        b.finish({ bookBalanceMinor: 95000 }),
      ]);
      await settleRealmRenders();
      let saved = await stored('BankReconciliation/finish');
      assert.strictEqual(saved.status, 'reconciled');
      assert.strictEqual(saved.finishedBookMinor, 95000);
      assert.strictEqual(saved.reconciledBy, USER);
      assert.deepEqual(
        saved.cleared.map((c: any) => c.key),
        ['jan-deposit'],
      );
    });

    test('a batch whose statement and books disagree is refused whole', async function (assert) {
      let rec = await cardAt('BankReconciliation/off');
      await assert.rejects(
        operations(rec).atomic((b: any) => [
          b.record(ticked),
          b.finish({ bookBalanceMinor: 95100 }),
        ]),
        /difference must be \$0\.00/,
      );
      await settleRealmRenders();
      let saved = await stored('BankReconciliation/off');
      assert.strictEqual(saved.status, 'draft');
      assert.strictEqual(saved.cleared.length, 0, 'nothing was recorded');
    });

    test('a draft cannot be reopened', async function (assert) {
      let rec = await cardAt('BankReconciliation/draft');
      await assert.rejects(
        operations(rec).undo(),
        /Only a finished reconciliation can be reopened/,
      );
    });
  });
}
