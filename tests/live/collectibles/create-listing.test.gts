import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import CreateListingCommand from '../../../cards/collectibles/commands/create-listing-command';

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

import type { CollectionItem } from '../../../cards/collectibles/collection-item';
import type { Listing } from '../../../cards/collectibles/listing';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/collectibles/';
const collectibles = `${catalogRealmURL}cards/collectibles/`;

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
      meta: { adoptsFrom: { module: `${collectibles}${module}`, name } },
    },
  };
}

function link(id: string) {
  return { links: { self: `${realmURL}${id}` } };
}

function item(owner: string, product: string) {
  return instance(
    'collection-item',
    'CollectionItem',
    { variant: '10' },
    { owner: link(owner), item: link(product) },
  );
}

export function runTests() {
  module(
    'Acceptance | Catalog | collectibles - create listing',
    function (hooks) {
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
            'seller.json': instance('seller-profile', 'SellerProfile', {
              name: 'Sam',
            }),
            'member.json': instance('marketplace-member', 'MarketplaceMember', {
              name: 'Mo',
            }),
            'product.json': instance(
              'collectible-product',
              'CollectibleProduct',
              {
                sku: 'DZ5485-612',
              },
            ),
            'sellers-item.json': item('seller', 'product'),
            'members-item.json': item('member', 'product'),
            'not-a-product.json': item('seller', 'member'),
          },
        });
        await visitOperatorMode({ stacks: [[]] });
      });

      function run(collectionItemId: string) {
        let command = new CreateListingCommand(
          getService('tool-service').commandContext,
        );
        return command.execute({
          collectionItemId: `${realmURL}${collectionItemId}`,
          price: 250,
          currency: 'USD',
        });
      }

      test('create-listing rejects an owner that is not a seller profile', async function (assert) {
        await assert.rejects(run('members-item'), /is not a Seller Profile/);
      });

      test('create-listing rejects an item that is not a collectible product', async function (assert) {
        await assert.rejects(
          run('not-a-product'),
          /is not a Collectible Product/,
        );
      });

      test('create-listing writes the listing and the item listedAt', async function (assert) {
        let result = await run('sellers-item');
        let store = getService('store');
        let listing = (await store.get(result!.listingId!)) as Listing;
        assert.strictEqual(listing.listingStatus, 'active');
        assert.strictEqual(listing.seller?.id, `${realmURL}seller`);
        assert.strictEqual(listing.product?.id, `${realmURL}product`);

        let collectionItem = (await store.get(
          `${realmURL}sellers-item`,
        )) as CollectionItem;
        assert.ok(collectionItem.listedAt, 'listedAt is set on the item');
      });
    },
  );
}
