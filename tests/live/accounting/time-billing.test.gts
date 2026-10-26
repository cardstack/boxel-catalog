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

import { timeInvoiceLines } from '../../../cards/accounting/ledger-time';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/time-billing/';
const accounting = `${catalogRealmURL}cards/accounting/`;
const ta1 = `${realmURL}ta-1`;
const ta2 = `${realmURL}ta-2`;
const DOC = 'INV-TIME';

function time(date: string, hours: number) {
  return {
    data: {
      type: 'card',
      attributes: {
        date,
        workerKind: 'employee',
        worker: 'u-rivera',
        customerId: 'atlas',
        serviceSku: 'SVC-ROAST-CONSULT',
        hours,
        rateMinor: 12500,
        billable: true,
        description: 'Roasting consultation',
        billedInvoice: null,
      },
      meta: {
        adoptsFrom: {
          module: `${accounting}ledger-time`,
          name: 'TimeActivity',
        },
      },
    },
  };
}

function draftInvoice() {
  return {
    data: {
      type: 'card',
      attributes: {
        docNo: DOC,
        date: '2027-01-20',
        status: 'draft',
        kind: 'sale',
        customerId: 'atlas',
        lines: timeInvoiceLines(
          [
            { id: ta1, ...time('2027-01-12', 2500).data.attributes },
            { id: ta2, ...time('2027-01-13', 1000).data.attributes },
          ],
          () => '4100',
        ),
      },
      meta: {
        adoptsFrom: { module: `${accounting}ledger-sales`, name: 'Invoice' },
      },
    },
  };
}

export function runTests() {
  module('Catalog | accounting - time billing lines', function () {
    test('an invoice from time has a line per activity naming it, at its rate and hours', function (assert) {
      let lines = timeInvoiceLines(
        [
          {
            id: ta1,
            worker: 'u-rivera',
            description: '',
            date: '2027-01-12',
            serviceSku: 'SVC-ROAST-CONSULT',
            hours: 2500,
            rateMinor: 12500,
          },
          {
            id: ta2,
            worker: 'u-rivera',
            date: '2027-01-13',
            serviceSku: 'SVC-OTHER',
            hours: 333,
            rateMinor: 10000,
          },
        ],
        (sku) => (sku === 'SVC-ROAST-CONSULT' ? '4100' : undefined),
      );
      assert.deepEqual(
        lines.map((l) => [
          l.timeId,
          l.sku,
          l.qty,
          l.priceMinor,
          l.amountMinor,
          l.account,
        ]),
        [
          [ta1, 'SVC-ROAST-CONSULT', 2500, 12500, 31250, '4100'],
          [ta2, 'SVC-OTHER', 333, 10000, 3330, '4000'],
        ],
        'amounts are rate times hours in whole cents; a service with no income account takes 4000',
      );
      assert.strictEqual(lines[0].description, 'u-rivera: time (2027-01-12)');
    });
  });

  module('Acceptance | Catalog | accounting - time billing', function (hooks) {
    setupApplicationTest(hooks);
    setupLocalIndexing(hooks);
    setupOnSave(hooks);

    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: '@testuser:localhost',
      activeRealms: [realmURL],
    });

    let operations: (card: unknown) => any;
    let TimeActivity: unknown;

    hooks.beforeEach(async function () {
      mockMatrixUtils.createAndJoinRoom({
        sender: '@testuser:localhost',
        name: 'room-test',
      });
      setupUserSubscription();
      setupAuthEndpoints();
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ta-1.json': time('2027-01-12', 2500),
          'ta-2.json': time('2027-01-13', 1000),
          'inv-time.json': draftInvoice(),
        },
      });
      await visitOperatorMode({ stacks: [[]] });
      // Through the host's loader, so `operations()` recognizes the store's instances.
      let loader = getService('loader-service').loader;
      ({ operations } = (await loader.import(
        '@cardstack/base/operations',
      )) as any);
      ({ TimeActivity } = (await loader.import(
        `${accounting}ledger-time`,
      )) as any);
      getService('operations');
    });

    async function card(id: string) {
      return getService('store').get(id);
    }

    async function stored(id: string) {
      let doc = await operations(await card(id)).read();
      return doc.data.attributes;
    }

    async function billBoth() {
      let [a, b, inv] = await Promise.all([
        card(ta1),
        card(ta2),
        card(`${realmURL}inv-time`),
      ]);
      await operations(inv).atomic((batch: any) => [
        batch.on(a).markBilled({ docNo: DOC }),
        batch.on(b).markBilled({ docNo: DOC }),
      ]);
    }

    test('billing marks each activity with its invoice, and time already billed is refused', async function (assert) {
      await billBoth();
      assert.strictEqual((await stored(ta1)).billedInvoice, DOC);
      assert.strictEqual((await stored(ta2)).billedInvoice, DOC);

      await assert.rejects(
        operations(await card(ta1)).markBilled({ docNo: 'INV-OTHER' }),
        /already billed/,
      );
      assert.strictEqual(
        (await stored(ta1)).billedInvoice,
        DOC,
        'the refused bill leaves the first invoice on it',
      );
    });

    test('voiding the invoice puts every activity it billed back to unbilled', async function (assert) {
      await billBoth();
      await assert.rejects(
        operations(await card(ta1)).unmarkBilled({ docNo: 'INV-OTHER' }),
        /isn't billed by that invoice/,
      );

      // The time half of the desk's void batch.
      let inv = await card(`${realmURL}inv-time`);
      await operations(inv).atomic((b: any) => [
        b
          .on(
            b.find(
              {
                every: [
                  { type: TimeActivity },
                  { on: TimeActivity, eq: { billedInvoice: DOC } },
                ],
              },
              { expect: 'many' },
            ),
          )
          .unmarkBilled({ docNo: DOC }),
      ]);
      assert.notOk((await stored(ta1)).billedInvoice, 'the first is unbilled');
      assert.notOk((await stored(ta2)).billedInvoice, 'the second is unbilled');
    });

    test('unbilling time takes its line off the draft in the same batch', async function (assert) {
      await billBoth();
      let [a, inv] = await Promise.all([
        card(ta1),
        card(`${realmURL}inv-time`),
      ]);
      await operations(inv).atomic((b: any) => [
        b.on(inv).removeTimeLine({ timeId: ta1 }),
        b.on(a).unmarkBilled({ docNo: DOC }),
      ]);

      let lines = (await stored(`${realmURL}inv-time`)).lines as {
        timeId: string;
      }[];
      assert.deepEqual(
        lines.map((l) => l.timeId),
        [ta2],
        "only the other activity's line is left",
      );
      assert.notOk(
        (await stored(ta1)).billedInvoice,
        'the unbilled time is free to bill again',
      );
      assert.strictEqual(
        (await stored(ta2)).billedInvoice,
        DOC,
        'the other stays billed',
      );
    });
  });
}
