import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import {
  realmConfigCardJSON,
  settleRealmRenders,
  setupCardLogs,
  setupIntegrationTestRealm,
  setupLocalIndexing,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { bankPostingKey } from '../../../cards/accounting/ledger-bank-statement';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/bank-feed-operations/';
const accounting = `${catalogRealmURL}cards/accounting/`;
const USER = '@testuser:localhost';
const lineRef = {
  module: `${accounting}ledger-bank`,
  name: 'BankTransaction',
} as never;

function instance(
  module: string,
  name: string,
  attributes: Record<string, unknown>,
) {
  return {
    data: {
      type: 'card',
      attributes,
      meta: { adoptsFrom: { module: `${accounting}${module}`, name } },
    },
  };
}

function bankLine(externalId: string, date: string, amountMinor: number) {
  return instance('ledger-bank', 'BankTransaction', {
    account: '1000',
    externalId,
    date,
    description: `Line ${externalId}`,
    amountMinor,
    importNo: 'IMP-TEST',
    status: 'for-review',
  });
}

const line = (account: string, debitMinor: number, creditMinor: number) => ({
  account,
  debitMinor,
  creditMinor,
  date: null,
  cls: null,
  loc: null,
  party: null,
  doc: null,
});

// Rent paid from the operating account, as the desk posts a line it adds.
function rentEntry(key: string) {
  return {
    key,
    kind: 'expense',
    date: '2027-01-05',
    memo: 'Rent',
    party: null,
    source: 'FCB-270105-01',
    lines: [line('6100', 450000, 0), line('1000', 0, 450000)],
    facts: [],
    items: [],
    preparer: null,
    reviewer: null,
  };
}

export function runTests() {
  module('Catalog | accounting - bank feed operations', function (hooks) {
    setupRenderingTest(hooks);
    setupLocalIndexing(hooks);

    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: USER,
      activeRealms: [realmURL],
      autostart: true,
    });

    let loader: any;
    let operations: any;
    let adapter: any;
    let BankTransaction: any;
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
          'realm.json': realmConfigCardJSON({
            name: 'Bank feed',
            config: { closedThrough: '2026-12-31' },
          }),
          'Journal/2027-01.json': instance('ledger-journal', 'JournalMonth', {
            month: '2027-01',
            firstDay: '2027-01-01',
            lastDay: '2027-01-31',
            status: 'open',
            nextSeq: 1,
            postings: [],
          }),
          'Ledger/books.json': instance('ledger-cards', 'Ledger', {
            company: 'Test Books',
          }),
          'BankTransaction/rent.json': bankLine(
            'FCB-270105-01',
            '2027-01-05',
            -450000,
          ),
          'BankTransaction/payout.json': bankLine(
            'FCB-270106-01',
            '2027-01-06',
            231045,
          ),
          'BankTransaction/fee.json': bankLine(
            'FCB-270108-01',
            '2027-01-08',
            -1500,
          ),
        },
      }));
      loader = getService('loader-service').loader;
      ({ operations } = await loader.import('@cardstack/base/operations'));
      ({ BankTransaction } = await loader.import(`${accounting}ledger-bank`));
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

    // Each write is followed by the realm's render of what it wrote, and a request sent during it
    // would be answered as the realm's own, which carries no actor.
    async function run(write: Promise<unknown>) {
      let result = await write;
      await settleRealmRenders();
      return result;
    }

    async function addRent(key: string) {
      let rent = await cardAt('BankTransaction/rent');
      let month = await cardAt('Journal/2027-01');
      return await run(
        operations(rent).atomic((b: any) => [
          b.add({ key, category: '6100' }),
          b.on(month).post(rentEntry(key)),
        ]),
      );
    }

    test('a line added, reversed and added again posts under the next key', async function (assert) {
      let firstKey = bankPostingKey(
        '1000|FCB-270105-01',
        (await stored('Journal/2027-01')).postings,
      );
      assert.strictEqual(firstKey, 'bank:1000|FCB-270105-01');
      await addRent(firstKey);
      let rent = await stored('BankTransaction/rent');
      assert.strictEqual(rent.status, 'added');
      assert.strictEqual(rent.matchedKey, firstKey);
      assert.strictEqual(rent.reviewedBy, USER);

      let month = await cardAt('Journal/2027-01');
      await run(
        operations(month).atomic((b: any) => [
          b.reverse({
            seq: 1,
            key: 'reverse:2027-01:1',
            date: '2027-01-20',
            memo: 'Reverses 2027-01 #1',
            party: null,
            source: null,
            lines: [line('6100', 0, 450000), line('1000', 450000, 0)],
            unwound: [],
          }),
          b
            .on(
              b.find(
                {
                  every: [
                    { type: BankTransaction },
                    { on: BankTransaction, eq: { matchedKey: firstKey } },
                  ],
                },
                { expect: 'many' },
              ),
            )
            .unmatch(),
        ]),
      );
      rent = await stored('BankTransaction/rent');
      assert.strictEqual(
        rent.status,
        'for-review',
        'the line is back for review',
      );
      assert.strictEqual(rent.matchedKey, null);
      assert.strictEqual(rent.category, null);

      await assert.rejects(
        addRent(firstKey),
        /already posted/,
        'the first key stays taken by the reversed posting',
      );
      let postings = (await stored('Journal/2027-01')).postings;
      assert.strictEqual(
        postings.length,
        2,
        'the refused batch posted nothing',
      );
      assert.strictEqual(
        (await stored('BankTransaction/rent')).status,
        'for-review',
        'and left the line for review',
      );

      let nextKey = bankPostingKey('1000|FCB-270105-01', postings);
      assert.strictEqual(nextKey, 'bank:1000|FCB-270105-01#2');
      await addRent(nextKey);
      rent = await stored('BankTransaction/rent');
      assert.strictEqual(rent.status, 'added');
      assert.strictEqual(rent.matchedKey, nextKey);
      assert.deepEqual(
        (await stored('Journal/2027-01')).postings.map((p: any) => p.key),
        [firstKey, 'reverse:2027-01:1', nextKey],
      );
    });

    test('add refuses the bank account itself and a line no longer waiting for review', async function (assert) {
      let rent = await cardAt('BankTransaction/rent');
      await assert.rejects(
        operations(rent).add({ key: 'bank:x', category: '1000' }),
        /can't be added to its own bank account/,
      );
      await run(operations(rent).exclude({ reason: 'Duplicate' }));
      await assert.rejects(
        operations(rent).add({ key: 'bank:x', category: '6100' }),
        /Only a line waiting for review can be added/,
      );
    });

    test('match marks a line matched once, and unmatch puts it back', async function (assert) {
      let payout = await cardAt('BankTransaction/payout');
      await run(operations(payout).match({ key: 'Deposit:DEP-1' }));
      let stored1 = await stored('BankTransaction/payout');
      assert.strictEqual(stored1.status, 'matched');
      assert.strictEqual(stored1.matchedKey, 'Deposit:DEP-1');
      assert.strictEqual(stored1.reviewedBy, USER);
      await assert.rejects(
        operations(payout).match({ key: 'Deposit:DEP-2' }),
        /Only a line waiting for review can be matched/,
      );

      await run(operations(payout).unmatch());
      let back = await stored('BankTransaction/payout');
      assert.strictEqual(back.status, 'for-review');
      assert.strictEqual(back.matchedKey, null);
      assert.strictEqual(back.reviewedBy, null);
      await assert.rejects(
        operations(payout).unmatch(),
        /Only a matched or added line can go back for review/,
      );
    });

    test('exclude keeps the reason, and restore puts the line back for review', async function (assert) {
      let fee = await cardAt('BankTransaction/fee');
      await assert.rejects(
        operations(fee).restore(),
        /Only an excluded line can be put back for review/,
      );
      await run(operations(fee).exclude({ reason: 'Personal charge' }));
      let excluded = await stored('BankTransaction/fee');
      assert.strictEqual(excluded.status, 'excluded');
      assert.strictEqual(excluded.excludedReason, 'Personal charge');
      await assert.rejects(
        operations(fee).match({ key: 'x' }),
        /Only a line waiting for review can be matched/,
      );

      await run(operations(fee).restore());
      let restored = await stored('BankTransaction/fee');
      assert.strictEqual(restored.status, 'for-review');
      assert.strictEqual(restored.excludedReason, null);
    });

    test('an import that brings a line already in the feed is refused whole', async function (assert) {
      let ledger = await cardAt('Ledger/books');
      let importBatch = (externalIds: string[]) =>
        operations(ledger).atomic((b: any) => [
          b
            .on(
              b.find(
                {
                  every: [
                    { type: BankTransaction },
                    { on: BankTransaction, eq: { account: '1000' } },
                    {
                      any: externalIds.map((externalId) => ({
                        on: BankTransaction,
                        eq: { externalId },
                      })),
                    },
                  ],
                },
                { expect: 'many' },
              ),
            )
            .refuseReimport(),
          ...externalIds.map((externalId) =>
            b.enterBankLine({
              account: '1000',
              externalId,
              date: '2027-01-12',
              description: 'Coffee',
              amountMinor: -2500,
              reference: null,
              payee: null,
              importNo: 'IMP-AGAIN',
            }),
          ),
        ]);
      let lines = async () =>
        (
          await getService('store').search(
            {
              filter: {
                every: [
                  { type: lineRef },
                  { on: lineRef, eq: { importNo: 'IMP-AGAIN' } },
                ],
              },
            },
            [realmURL],
          )
        ).length;

      await assert.rejects(
        importBatch(['FCB-270112-01', 'FCB-270105-01']),
        /already in the feed/,
      );
      assert.strictEqual(
        await lines(),
        0,
        'no line of the refused batch landed',
      );

      await run(importBatch(['FCB-270112-01']));
      assert.strictEqual(await lines(), 1, 'a file of new lines imports');
    });
  });
}
