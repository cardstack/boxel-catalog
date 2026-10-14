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

import type { Listing } from '../../../cards/collectibles/listing';
import type { Order } from '../../../cards/sole-vault/order';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/sole-vault-commands/';
const collectibles = `${catalogRealmURL}cards/collectibles/`;
const soleVault = `${catalogRealmURL}cards/sole-vault/`;

function instance(
  module: string,
  name: string,
  attributes: Record<string, unknown> = {},
  relationships: Record<string, unknown> = {},
) {
  return {
    data: {
      type: 'card',
      attributes,
      relationships,
      meta: { adoptsFrom: { module, name } },
    },
  };
}

function link(id: string) {
  return { links: { self: `${realmURL}${id}` } };
}

function usd(amount: number) {
  return { amount, currency: { code: 'USD' } };
}

export function runTests() {
  module('Acceptance | Catalog | apps - sole vault commands', function (hooks) {
    setupApplicationTest(hooks);
    setupLocalIndexing(hooks);
    setupOnSave(hooks);

    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: '@testuser:localhost',
      activeRealms: [realmURL],
    });

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
          'seller.json': instance(
            `${collectibles}seller-profile`,
            'SellerProfile',
            { name: 'Test Seller' },
          ),
          'buyer.json': instance(
            `${collectibles}marketplace-member`,
            'MarketplaceMember',
            { name: 'Test Buyer' },
          ),
          'product.json': instance(
            `${collectibles}collectible-product`,
            'CollectibleProduct',
            { sku: 'TEST-0001' },
          ),
          'item.json': instance(
            `${collectibles}collection-item`,
            'CollectionItem',
            { variant: '10', listedAt: '2026-08-01' },
            { owner: link('seller'), item: link('product') },
          ),
          'listing.json': instance(
            `${collectibles}listing`,
            'Listing',
            {
              price: usd(200),
              shippingPrice: usd(15),
              listingStatus: 'active',
            },
            {
              seller: link('seller'),
              product: link('product'),
              collectionItem: link('item'),
            },
          ),
        },
      });
      await visitOperatorMode({ stacks: [[]] });
    });

    // Loaded through the host's loader, as the host runs a command.
    async function run(name: string, input: Record<string, unknown>) {
      let { default: Command } = (await getService(
        'loader-service',
      ).loader.import(`${soleVault}commands/${name}`)) as {
        default: new (context: unknown) => {
          execute(input: unknown): Promise<any>;
        };
      };
      return new Command(getService('tool-service').commandContext).execute(
        input,
      );
    }

    async function orderStatus(orderId: string) {
      let order = (await getService('store').get(orderId)) as Order;
      return order.orderStatus;
    }

    async function place() {
      let placed = await run('place-order-command', {
        listingId: `${realmURL}listing`,
        buyerId: `${realmURL}buyer`,
      });
      return placed.orderId as string;
    }

    test('an order moves from placed to delivered across both shipping legs', async function (assert) {
      let orderId = await place();
      assert.strictEqual(await orderStatus(orderId), 'pending-payment');
      let listing = (await getService('store').get(
        `${realmURL}listing`,
      )) as Listing;
      assert.strictEqual(
        listing.listingStatus,
        'sold',
        'placing the order closes the listing as sold',
      );

      let paid = await run('process-payment-command', { orderId });
      assert.strictEqual(paid.orderStatus, 'paid');

      let first = await run('dispatch-shipment-command', {
        orderId,
        trackingNumber: 'TEST-TRACK-1',
      });
      assert.strictEqual(first.orderStatus, 'shipped');

      let atAuth = await run('mark-delivered-command', {
        shipmentId: first.shipmentId,
      });
      assert.strictEqual(
        atAuth.orderStatus,
        'authenticating',
        'the first leg arriving puts the order into authentication',
      );

      let second = await run('dispatch-shipment-command', {
        orderId,
        trackingNumber: 'TEST-TRACK-2',
        leg: 'to-buyer',
      });
      assert.strictEqual(
        second.orderStatus,
        'authenticating',
        'dispatching the buyer leg does not move the order',
      );

      let delivered = await run('mark-delivered-command', {
        shipmentId: second.shipmentId,
      });
      assert.strictEqual(delivered.orderStatus, 'delivered');
      assert.strictEqual(await orderStatus(orderId), 'delivered');
    });

    test('a paid order can be refunded, and a refunded order cannot be dispatched', async function (assert) {
      let orderId = await place();
      await run('process-payment-command', { orderId });

      let refunded = await run('refund-order-command', {
        orderId,
        reason: 'Failed authentication',
      });
      assert.strictEqual(refunded.orderStatus, 'refunded');
      assert.ok(refunded.paymentId, 'the refund is recorded as a payment');

      await assert.rejects(
        run('dispatch-shipment-command', {
          orderId,
          trackingNumber: 'TEST-TRACK-3',
        }),
        /cannot move from refunded to shipped/,
      );
    });

    test('dispatch refuses the buyer leg before authentication', async function (assert) {
      let orderId = await place();
      await run('process-payment-command', { orderId });

      await assert.rejects(
        run('dispatch-shipment-command', {
          orderId,
          trackingNumber: 'TEST-TRACK-4',
          leg: 'to-buyer',
        }),
        /ships to the buyer only while authenticating/,
      );
    });
  });
}
