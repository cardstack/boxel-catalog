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
import {
  AllCards,
  searchAll,
  MAX_SEARCH_PAGES,
  SEARCH_PAGE,
} from '../../../cards/accounting/all-cards';

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
        (sku) => (sku === 'SVC-ROAST-CONSULT' ? '4100' : '4200'),
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
          [ta2, 'SVC-OTHER', 333, 10000, 3330, '4200'],
        ],
        'amounts are rate times hours in whole cents, credited to each service its own account',
      );
      assert.strictEqual(lines[0].description, 'u-rivera: time (2027-01-12)');
      assert.throws(
        () =>
          timeInvoiceLines(
            [{ id: ta1, serviceSku: 'SVC-GONE', hours: 1000, rateMinor: 100 }],
            () => undefined,
          ),
        /Give the service SVC-GONE an income account/,
        'a service without an income account is refused, not guessed',
      );
    });

    test('reading unbilled time walks every page up to the cap, and refuses past it', async function (assert) {
      let storeOf = (count: number) => ({
        async search(query: { page: { size: number; number: number } }) {
          let { size, number } = query.page;
          return Array.from(
            { length: Math.max(0, Math.min(size, count - size * number)) },
            (_, i) => ({ id: `t-${size * number + i}` }),
          );
        },
      });
      let read = (count: number) =>
        searchAll(storeOf(count), {}, undefined, 500, 'too many');
      assert.strictEqual((await read(450)).length, 450, '450 of 500 are read');
      assert.strictEqual((await read(500)).length, 500, 'exactly 500 are read');
      await assert.rejects(read(501), /too many/, '501 is refused');
    });
  });

  module('Catalog | accounting - reading every page', function () {
    // Stand-ins for getCards' page resources: each answers, fails or is still loading, as told.
    const fakeContext = (rows: { id: string }[]) => {
      let pages: {
        state: 'loading' | 'answered' | 'failed';
        getQuery: () => any;
      }[] = [];
      let context = {
        getCards(_parent: object, getQuery: () => any) {
          let page = { state: 'loading' as const, getQuery } as any;
          pages.push(page);
          return {
            get isLoading() {
              return !!page.getQuery() && page.state === 'loading';
            },
            get instances() {
              let q = page.getQuery();
              if (!q || page.state !== 'answered') return [];
              let { size, number } = q.page;
              return rows.slice(size * number, size * (number + 1));
            },
            get meta() {
              return page.state === 'failed'
                ? { page: { total: 0 }, incomplete: true }
                : page.state === 'answered'
                  ? { page: { total: rows.length } }
                  : { page: { total: 0 } };
            },
          };
        },
      };
      let answer = (n: number) => (pages[n].state = 'answered');
      let fail = (n: number) => (pages[n].state = 'failed');
      return { context, pages, answer, fail };
    };
    const ids = (n: number) =>
      Array.from({ length: n }, (_, i) => ({ id: `c-${i}` }));
    const query = () => ({ filter: {} });

    test('a read is complete only once every page it needs has answered', function (assert) {
      let f = fakeContext(ids(250));
      let all = new AllCards(f.context, {}, query);
      assert.true(all.isLoading, 'loading before the first page answers');
      f.answer(0);
      assert.strictEqual(all.total, 250);
      assert.false(all.isComplete, 'pages 1 and 2 have not answered');
      f.answer(1);
      assert.false(all.isComplete, 'page 2 has not answered');
      f.answer(2);
      assert.true(all.isComplete);
      assert.strictEqual(all.instances.length, 250);
    });

    test('a failed first page is a failed read with no total', function (assert) {
      let f = fakeContext(ids(250));
      let all = new AllCards(f.context, {}, query);
      f.fail(0);
      assert.true(all.failed);
      assert.strictEqual(all.total, undefined);
      assert.false(all.isComplete);
      assert.false(all.isLoading);
    });

    test('a later page failing fails the read', function (assert) {
      let f = fakeContext(ids(250));
      let all = new AllCards(f.context, {}, query);
      f.answer(0);
      f.fail(1);
      f.answer(2);
      assert.true(all.failed);
      assert.false(all.isComplete, 'its rows are not the whole set');
    });

    test('more than the cap matched is too many', function (assert) {
      let f = fakeContext(ids(MAX_SEARCH_PAGES * SEARCH_PAGE + 1));
      let all = new AllCards(f.context, {}, query);
      f.answer(0);
      assert.true(all.tooMany);
      assert.false(all.isComplete);
    });

    test('a limited read reads whole pages up to its limit, and says more matched', function (assert) {
      let f = fakeContext(ids(500));
      let all = new AllCards(f.context, {}, query, undefined, { limit: 240 });
      for (let n = 0; n < f.pages.length; n++) f.answer(n);
      assert.true(all.truncated);
      assert.false(all.isComplete, 'a truncated read is not every record');
      assert.strictEqual(all.instances.length, 300);
    });

    test('a card on two pages is counted once', function (assert) {
      let rows = ids(150);
      rows[120] = rows[50];
      let f = fakeContext(rows);
      let all = new AllCards(f.context, {}, query);
      f.answer(0);
      f.answer(1);
      assert.strictEqual(all.instances.length, 149);
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
        batch.on(a).markBilled({ docNo: DOC, customerId: 'atlas' }),
        batch.on(b).markBilled({ docNo: DOC, customerId: 'atlas' }),
      ]);
    }

    test('billing marks each activity with its invoice, and time already billed is refused', async function (assert) {
      await billBoth();
      assert.strictEqual((await stored(ta1)).billedInvoice, DOC);
      assert.strictEqual((await stored(ta2)).billedInvoice, DOC);

      await assert.rejects(
        operations(await card(ta1)).markBilled({
          docNo: 'INV-OTHER',
          customerId: 'atlas',
        }),
        /already billed/,
      );
      assert.strictEqual(
        (await stored(ta1)).billedInvoice,
        DOC,
        'the refused bill leaves the first invoice on it',
      );
    });

    test("time is billed only to its own customer's invoice", async function (assert) {
      await assert.rejects(
        operations(await card(ta1)).markBilled({
          docNo: DOC,
          customerId: 'harbor',
        }),
        /only to its own customer's invoice/,
      );
      assert.notOk(
        (await stored(ta1)).billedInvoice,
        'the time stays unbilled',
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

      await assert.rejects(
        operations(inv).atomic((b: any) => [
          b.on(inv).removeTimeLine({ timeId: ta1 }),
        ]),
        /no line for that time/,
        'a draft without the line refuses to take it off',
      );
    });
  });
}
