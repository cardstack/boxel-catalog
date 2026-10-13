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

import type CreateListingCommand from '../../../cards/collectibles/commands/create-listing-command';
import type CloseListingCommand from '../../../cards/collectibles/commands/close-listing-command';
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

      // The command checks the cards it fetches with `instanceof`, so it has
      // to come from the loader the store builds those cards with.
      async function run(collectionItemId: string) {
        let { default: Command } = (await getService(
          'loader-service',
        ).loader.import(`${collectibles}commands/create-listing-command`)) as {
          default: typeof CreateListingCommand;
        };
        let command = new Command(getService('tool-service').commandContext);
        return command.execute({
          collectionItemId: `${realmURL}${collectionItemId}`,
          price: 250,
          currency: 'USD',
        });
      }

      async function close(listingId: string, outcome: string) {
        let { default: Command } = (await getService(
          'loader-service',
        ).loader.import(`${collectibles}commands/close-listing-command`)) as {
          default: typeof CloseListingCommand;
        };
        let command = new Command(getService('tool-service').commandContext);
        return command.execute({ listingId, outcome });
      }

      test('create-listing refuses a second listing while one is active, and relists once it closes', async function (assert) {
        let first = await run('sellers-item');
        await assert.rejects(run('sellers-item'), /already for sale/);

        await close(first!.listingId!, 'cancelled');
        let store = getService('store');
        let item = (await store.get(
          `${realmURL}sellers-item`,
        )) as CollectionItem;
        assert.notOk(item.listedAt, 'closing the listing clears listedAt');
        assert.notOk(item.forSale, 'the item is no longer for sale');

        let second = await run('sellers-item');
        assert.ok(second?.listingId, 'the item can be listed again');
        assert.notStrictEqual(second?.listingId, first?.listingId);
        item = (await store.get(`${realmURL}sellers-item`)) as CollectionItem;
        assert.ok(item.forSale, 'the relisted item is for sale');
      });

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
