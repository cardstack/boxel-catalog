import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import {
  setupIntegrationTestRealm,
  setupLocalIndexing,
  testRealmURL,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import {
  CountAdjustment,
  Draw,
  Fulfillment,
  RoastBatch,
  drawCost,
  fifoDraws,
  repricedDraws,
  sameDraws,
  type LotLike,
} from '../../../cards/accounting/ledger-stock';
import { journalPostingFor } from '../../../cards/accounting/ledger-journal';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const stockModule = `${catalogRealmURL}cards/accounting/ledger-stock`;

const LOTS: LotLike[] = [
  {
    sku: 'GRN-ETH',
    lot: 'L2',
    asset: '1200',
    received: '2026-02-10',
    qty: 50000,
    consumedQty: 0,
    part5000Minor: 40000,
    part5100Minor: 0,
  },
  {
    sku: 'GRN-ETH',
    lot: 'L1',
    asset: '1200',
    received: '2026-01-05',
    qty: 30000,
    consumedQty: 10000,
    part5000Minor: 15001,
    part5100Minor: 2999,
  },
  {
    sku: 'GRN-ETH',
    lot: 'L0',
    asset: '1200',
    received: '2026-01-01',
    qty: 9000,
    consumedQty: 0,
    part5000Minor: 9000,
    part5100Minor: 0,
    retiredBy: 'reverse:RB-1',
  },
  {
    sku: 'GRN-COL',
    lot: 'C1',
    asset: '1200',
    received: '2026-01-01',
    qty: 9000,
    consumedQty: 0,
    part5000Minor: 9000,
    part5100Minor: 0,
  },
];

// StockLot.draw's checks, in plain arithmetic: within the lot, the cost its pro-rata share of what's
// left (to half a cent), the split adding up, and neither part more than the lot has left of it.
function drawAccepted(
  lot: LotLike,
  d: ReturnType<typeof drawCost> & { qty: number },
) {
  let qty = lot.qty ?? 0,
    used = lot.consumedQty ?? 0,
    p5000 = lot.part5000Minor ?? 0,
    p5100 = lot.part5100Minor ?? 0;
  let off = 2 * d.costMinor * (qty - used) - 2 * (p5000 + p5100) * d.qty;
  return (
    d.qty > 0 &&
    qty - used - d.qty >= 0 &&
    Math.abs(off) <= qty - used &&
    d.part5000Minor >= 0 &&
    d.part5100Minor >= 0 &&
    d.part5000Minor + d.part5100Minor === d.costMinor &&
    p5000 - d.part5000Minor >= 0 &&
    p5100 - d.part5100Minor >= 0
  );
}

export function runTests() {
  module('Catalog | accounting - stock draws', function () {
    test('draws come from the oldest lots received by the date, skipping retired and other products', function (assert) {
      let draws = fifoDraws(LOTS, 'GRN-ETH', 25000, '2026-03-01');
      assert.deepEqual(
        draws.map((d) => [
          d.lot,
          d.qty,
          d.costMinor,
          d.part5000Minor,
          d.part5100Minor,
        ]),
        [
          ['L1', 20000, 18000, 15001, 2999],
          ['L2', 5000, 4000, 4000, 0],
        ],
        'L1 is used up at its whole remaining cost, then L2 at its rate',
      );
      assert.throws(
        () => fifoDraws(LOTS, 'GRN-ETH', 25000, '2026-02-01'),
        /There isn't enough GRN-ETH in stock on 2026-02-01: 5\.000 more/,
        'a lot received after the date is not drawn',
      );
    });

    test('a part draw costs its share of what is left, split so neither part overdraws', function (assert) {
      let lot = LOTS[1];
      assert.deepEqual(drawCost(lot, 7000), {
        costMinor: 6300,
        part5000Minor: 5250,
        part5100Minor: 1050,
      });
      assert.deepEqual(drawCost(lot, 1), {
        costMinor: 1,
        part5000Minor: 1,
        part5100Minor: 0,
      });
    });

    test("every draw fifoDraws prices passes the lot's own draw checks", function (assert) {
      let failures: string[] = [];
      for (let p5000 of [0, 1, 7, 999, 15001, 123457])
        for (let p5100 of [0, 1, 3, 2999, 40001])
          for (let left of [1, 3, 7, 1000, 12345])
            for (
              let take = 1;
              take <= left;
              take += Math.max(1, Math.floor(left / 7))
            ) {
              let lot: LotLike = {
                qty: left + 500,
                consumedQty: 500,
                part5000Minor: p5000,
                part5100Minor: p5100,
              };
              let d = { qty: take, ...drawCost(lot, take) };
              if (!drawAccepted(lot, d))
                failures.push(JSON.stringify({ p5000, p5100, left, take, d }));
            }
      assert.deepEqual(failures, [], 'no priced draw is one the lot refuses');
    });

    test('a draft is repriced by product, and compared lot by lot', function (assert) {
      let drafted = fifoDraws(LOTS, 'GRN-ETH', 25000, '2026-03-01');
      assert.true(
        sameDraws(drafted, repricedDraws(LOTS, drafted, '2026-03-01')),
        'unchanged lots reprice to the same draws',
      );
      let landed = LOTS.map((l) =>
        l.lot === 'L1'
          ? { ...l, part5000Minor: (l.part5000Minor ?? 0) + 500 }
          : l,
      );
      assert.false(
        sameDraws(drafted, repricedDraws(landed, drafted, '2026-03-01')),
        'landed cost on a drawn lot changes the draws',
      );
    });
  });

  module('Catalog | accounting - stock journal postings', function () {
    let draw = (o: Record<string, unknown>) => new Draw(o);

    function balanced(assert: Assert, entry: any) {
      let debit = entry.lines.reduce(
          (n: number, l: any) => n + l.debitMinor,
          0,
        ),
        credit = entry.lines.reduce(
          (n: number, l: any) => n + l.creditMinor,
          0,
        );
      assert.strictEqual(debit, credit, 'the entry balances');
      assert.true(debit > 0, 'the entry moves money');
    }

    test('a fulfillment posts its cost of goods sold by part, and items carry the split', function (assert) {
      let card = new Fulfillment({
        docNo: 'FUL-1',
        date: '2026-03-01',
        saleNo: 'INV-1',
        draws: [
          draw({
            sku: 'RST-ETH',
            lot: 'R1',
            asset: '1210',
            qty: 2000,
            costMinor: 3000,
            part5000Minor: 2500,
            part5100Minor: 500,
          }),
          draw({
            sku: 'RST-ETH',
            lot: 'R2',
            asset: '1210',
            qty: 1000,
            costMinor: 1600,
            part5000Minor: 1300,
            part5100Minor: 300,
          }),
        ],
      });
      let entry = journalPostingFor(card, 'Fulfillment', 'x');
      assert.strictEqual(entry.kind, 'fulfillment');
      balanced(assert, entry);
      let at = (account: string) =>
        entry.lines.filter((l: any) => l.account === account);
      assert.deepEqual(
        [at('5000')[0]?.debitMinor, at('5100')[0]?.debitMinor],
        [3800, 800],
      );
      assert.deepEqual(
        at('1210').map((l: any) => [l.doc, l.creditMinor]),
        [
          ['R1', 3000],
          ['R2', 1600],
        ],
      );
      assert.deepEqual(
        entry.items.map((i: any) => [
          i.lot,
          i.qty,
          i.amountMinor,
          i.part5000Minor,
          i.part5100Minor,
        ]),
        [
          ['R1', 2000, 3000, 2500, 500],
          ['R2', 1000, 1600, 1300, 300],
        ],
      );
    });

    test('a count and a roast post balanced entries whose items name each draw', function (assert) {
      let count = journalPostingFor(
        new CountAdjustment({
          docNo: 'CNT-1',
          date: '2026-03-01',
          reason: 'Water damage',
          account: '5200',
          draws: [
            draw({
              sku: 'PKG-BAG',
              lot: 'P1',
              asset: '1220',
              qty: 500,
              costMinor: 250,
              part5000Minor: 0,
              part5100Minor: 250,
            }),
          ],
        }),
        'CountAdjustment',
        'x',
      );
      assert.strictEqual(count.kind, 'count');
      balanced(assert, count);
      assert.deepEqual(
        count.lines.map((l: any) => [l.account, l.debitMinor, l.creditMinor]),
        [
          ['5200', 250, 0],
          ['1220', 0, 250],
        ],
      );

      let roast = journalPostingFor(
        new RoastBatch({
          docNo: 'RB-1',
          date: '2026-03-01',
          outputSku: 'RST-ETH',
          outputLot: 'R9',
          outputAsset: '1210',
          outputQty: 8000,
          outputPart5000Minor: 8000,
          outputPart5100Minor: 0,
          inputs: [
            draw({
              sku: 'GRN-ETH',
              lot: 'L2',
              asset: '1200',
              qty: 10000,
              costMinor: 8000,
              part5000Minor: 8000,
              part5100Minor: 0,
            }),
          ],
        }),
        'RoastBatch',
        'x',
      );
      assert.strictEqual(roast.kind, 'roast');
      balanced(assert, roast);
      assert.deepEqual(
        roast.items.map((i: any) => [
          i.lot,
          i.qty,
          i.part5000Minor,
          i.part5100Minor,
        ]),
        [['L2', 10000, 8000, 0]],
      );
      let facts = Object.fromEntries(
        roast.facts.map((f: any) => [f.key, f.value]),
      );
      assert.deepEqual(
        [facts.outputSku, facts.outputLot],
        ['RST-ETH', 'R9'],
        'the reversal finds the roasted lot from the facts',
      );
    });
  });

  module('Catalog | accounting - stock lot draws in a realm', function (hooks) {
    setupRenderingTest(hooks);
    setupLocalIndexing(hooks);

    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: '@testuser:localhost',
      activeRealms: [testRealmURL],
      autostart: true,
    });

    let adapter: any;
    let operations: any;

    const lotFile = (l: LotLike) => ({
      data: {
        type: 'card',
        attributes: { landedMinor: 0, costMinor: 0, ...l },
        meta: { adoptsFrom: { module: stockModule, name: 'StockLot' } },
      },
    });

    hooks.beforeEach(async function () {
      ({ adapter } = await setupIntegrationTestRealm({
        mockMatrixUtils,
        contents: {
          'StockLot/l1.json': lotFile(LOTS[1]),
          'StockLot/l2.json': lotFile(LOTS[0]),
        },
      }));
      ({ operations } = await getService('loader-service').loader.import<any>(
        '@cardstack/base/operations',
      ));
      await getService('realm').login(testRealmURL);
      getService('operations');
    });

    async function stored(path: string) {
      let file = await adapter.openFile(path);
      return JSON.parse(file.content as string).data.attributes;
    }

    test('the lots accept the draws fifoDraws prices, and refuse a cent off', async function (assert) {
      let draws = fifoDraws(LOTS, 'GRN-ETH', 25000, '2026-03-01');
      let l1 = await getService('store').get(`${testRealmURL}StockLot/l1`);
      let l2 = await getService('store').get(`${testRealmURL}StockLot/l2`);

      let off = draws[1];
      await assert.rejects(
        operations(l2).draw({
          qty: off.qty,
          costMinor: off.costMinor + 1,
          part5000Minor: off.part5000Minor + 1,
          part5100Minor: off.part5100Minor,
          docNo: 'FUL-1',
        }),
        (e: any) =>
          /A draw costs its share of what's left/.test(
            `${e?.message} ${e?.detail}`,
          ),
      );

      for (let [card, d] of [
        [l1, draws[0]],
        [l2, draws[1]],
      ] as const)
        await operations(card).draw({
          qty: d.qty,
          costMinor: d.costMinor,
          part5000Minor: d.part5000Minor,
          part5100Minor: d.part5100Minor,
          docNo: 'FUL-1',
        });

      let [a, b] = [
        await stored('StockLot/l1.json'),
        await stored('StockLot/l2.json'),
      ];
      assert.deepEqual(
        [a.consumedQty, a.part5000Minor, a.part5100Minor],
        [30000, 0, 0],
        'L1 is used up',
      );
      assert.deepEqual(
        [b.consumedQty, b.part5000Minor, b.part5100Minor],
        [5000, 36000, 0],
        'L2 keeps the rest of its cost',
      );
    });
  });
}
