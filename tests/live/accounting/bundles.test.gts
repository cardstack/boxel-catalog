import { module, test } from 'qunit';
import { getService } from '@universal-ember/test-support';

import {
  setupIntegrationTestRealm,
  setupLocalIndexing,
} from '@cardstack/host/tests/helpers';
import { setupBaseRealm } from '@cardstack/host/tests/helpers/base-realm';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import type * as OperationsModule from '@cardstack/base/operations';

import {
  BundleComponent,
  Item,
  bundleSaleLines,
  lowStockStatus,
} from '../../../cards/accounting/ledger-cards';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/accounting-bundles/';
const salesModule = `${catalogRealmURL}cards/accounting/ledger-sales`;
const TEST_USER = '@testuser:localhost';

const BAG = 'RST-ETH-LGHT-12OZ';

function product(attrs: Record<string, unknown>) {
  return {
    sku: BAG,
    productName: 'Bag',
    salesPriceMinor: 1900,
    incomeAccount: '4200',
    ...attrs,
  };
}

function draft(name: 'Invoice' | 'SalesReceipt', docNo: string, extra = {}) {
  return {
    data: {
      type: 'card',
      attributes: {
        docNo,
        date: '2026-04-10',
        customerId: 'walkin',
        status: 'draft',
        lines: [],
        taxRatePpm: 0,
        taxMinor: 0,
        ...extra,
      },
      meta: { adoptsFrom: { module: salesModule, name } },
    },
  };
}

export function runTests() {
  module('Integration | Catalog | accounting - bundle lines', function (hooks) {
    setupRenderingTest(hooks);
    setupBaseRealm(hooks);

    test('a bundle puts one line per component at its own price and account', function (assert) {
      let bag = product({}),
        mug = product({
          sku: 'MUG',
          productName: 'Mug',
          salesPriceMinor: 1250,
          incomeAccount: null,
        }),
        bundle = {
          productName: 'Gift box',
          incomeAccount: '4300',
          components: [{ sku: BAG, qty: 333 }, null, { sku: 'MUG', qty: 1000 }],
        };
      let lines = bundleSaleLines(
        bundle,
        new Map([
          [BAG, bag],
          ['MUG', mug],
        ]),
        1.5,
      );
      assert.deepEqual(
        lines.map((l) => [
          l.sku,
          l.description,
          l.qty,
          l.priceMinor,
          l.amountMinor,
          l.account,
        ]),
        [
          [BAG, 'Gift box: Bag', 500, 1900, 950, '4200'],
          ['MUG', 'Gift box: Mug', 1500, 1250, 1875, '4300'],
        ],
        'qty is the component qty times the count, rounded; a component with no income account takes the bundle’s',
      );
    });

    test('a bundle line is refused rather than guessed', function (assert) {
      let bundle = {
        productName: 'Gift box',
        components: [{ sku: BAG, qty: 2000 }],
      };
      assert.throws(
        () => bundleSaleLines(bundle, new Map([[BAG, product({})]]), 0),
        /Enter how many bundles/,
      );
      assert.throws(
        () =>
          bundleSaleLines(
            bundle,
            new Map([[BAG, product({ salesPriceMinor: null })]]),
            1,
          ),
        /Give Bag a sales price first/,
      );
      assert.throws(
        () =>
          bundleSaleLines(
            bundle,
            new Map([[BAG, product({ incomeAccount: null })]]),
            1,
          ),
        /Give Bag an income account first/,
      );
      assert.throws(
        () => bundleSaleLines(bundle, new Map(), 1),
        /holds RST-ETH-LGHT-12OZ, which isn't a product/,
      );
      assert.throws(
        () => bundleSaleLines({ productName: 'Empty' }, new Map(), 1),
        /Empty holds no products/,
      );
    });

    test('a product with components is a bundle, and a bundle is never low', function (assert) {
      let bundle = new Item({
        sku: 'BND',
        components: [new BundleComponent({ sku: BAG, qty: 2000 })],
        reorderPoint: 1000,
      });
      let bag = new Item({ sku: BAG, reorderPoint: 200000 });
      assert.true(bundle.isBundle, 'components make a bundle');
      assert.false(bag.isBundle, 'no components, no bundle');
      assert.strictEqual(lowStockStatus(bundle, 0, false), '');
      assert.strictEqual(lowStockStatus(bag, 200000, false), 'Low');
      assert.strictEqual(lowStockStatus(bag, 200000, true), 'Check');
      assert.strictEqual(lowStockStatus(bag, 200001, false), 'OK');
      assert.strictEqual(
        lowStockStatus(new Item({ sku: BAG }), 0, false),
        '',
        'no reorder point, not listed',
      );
    });
  });

  module(
    'Integration | Catalog | accounting - bundles on a sale',
    function (hooks) {
      setupRenderingTest(hooks);
      setupLocalIndexing(hooks);

      let mockMatrixUtils = setupMockMatrix(hooks, {
        loggedInAs: TEST_USER,
        activeRealms: [realmURL],
        autostart: true,
      });

      let hostTransport: unknown;
      hooks.beforeEach(function () {
        hostTransport = (globalThis as any)._CARDSTACK_OPERATIONS_TRANSPORT;
      });
      hooks.afterEach(function () {
        (globalThis as any)._CARDSTACK_OPERATIONS_TRANSPORT = hostTransport;
      });

      async function setup() {
        // Permissions are enforced so a request carries the signed-in user, which `post` stamps.
        let { adapter } = await setupIntegrationTestRealm({
          mockMatrixUtils,
          realmURL,
          enforcePermissions: true,
          permissions: { [TEST_USER]: ['read', 'write', 'realm-owner'] },
          contents: {
            'Invoice/draft.json': draft('Invoice', 'INV-TEST-1', {
              due: '2026-05-10',
              kind: 'sale',
            }),
            'SalesReceipt/draft.json': draft('SalesReceipt', 'SR-TEST-1', {
              depositTo: '1010',
            }),
          },
        });
        let loader = getService('loader-service').loader;
        let { operations } = await loader.import<typeof OperationsModule>(
          '@cardstack/base/operations',
        );
        await getService('realm').login(realmURL);
        getService('operations');
        return { adapter, operations };
      }

      async function cardAt(id: string): Promise<any> {
        let card: any = await getService('store').get(id);
        if (!card || card.errors || !card.id) {
          throw new Error(
            `expected ${id} to load, got ${JSON.stringify(card)}`,
          );
        }
        return card;
      }

      async function stored(adapter: any, path: string) {
        let file = await adapter.openFile(path);
        return JSON.parse(file.content as string).data.attributes;
      }

      async function holidayBoxLines(count: number) {
        let bundle = await cardAt(
          `${catalogRealmURL}cards/accounting/Item/BND-HOLIDAY-BOX`,
        );
        let bag = await cardAt(
          `${catalogRealmURL}cards/accounting/Item/${BAG}`,
        );
        return bundleSaleLines(bundle, new Map([[BAG, bag]]), count);
      }

      for (let [name, path, refusal] of [
        [
          'invoice',
          'Invoice/draft',
          "Only a draft invoice's lines can change.",
        ],
        [
          'sales receipt',
          'SalesReceipt/draft',
          "Only a draft sales receipt's lines can change.",
        ],
      ]) {
        test(`the holiday box goes on a draft ${name}, which then posts and takes no more lines`, async function (assert) {
          let { adapter, operations } = await setup();
          let lines = await holidayBoxLines(2);
          let doc = await cardAt(`${realmURL}${path}`);

          await (operations(doc) as any).addLines({ lines });
          let added = await stored(adapter, `${path}.json`);
          assert.deepEqual(
            added.lines.map((l: any) => [
              l.sku,
              l.description,
              l.qty,
              l.priceMinor,
              l.amountMinor,
              l.account,
            ]),
            [
              [
                BAG,
                'Holiday gift box: Roasted · Ethiopia light 12oz retail bag',
                4000,
                1900,
                7600,
                '4200',
              ],
            ],
            'one line per component, at its price times two bundles',
          );

          await (operations(doc) as any).post();
          let posted = await stored(adapter, `${path}.json`);
          assert.strictEqual(posted.status, 'posted', 'the draft posts');
          assert.strictEqual(posted.postedBy, TEST_USER);

          let error: any;
          try {
            await (operations(doc) as any).addLines({ lines });
          } catch (e) {
            error = e;
          }
          assert.ok(error, 'adding lines to a posted document is refused');
          assert.true(
            String(error?.detail ?? error?.message).includes(refusal),
            `with the draft-only message: ${error?.detail ?? error?.message}`,
          );
          assert.strictEqual(
            (await stored(adapter, `${path}.json`)).lines.length,
            1,
            'and its lines are unchanged',
          );
        });
      }
    },
  );
}
