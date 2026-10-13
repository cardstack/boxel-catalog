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

import type AuthenticateItemCommand from '../../../cards/collectibles/commands/authenticate-item-command';
import type { CollectionItem } from '../../../cards/collectibles/collection-item';

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

export function runTests() {
  module(
    'Acceptance | Catalog | collectibles - authenticate item',
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
            'owner.json': instance('marketplace-member', 'MarketplaceMember', {
              name: 'Mo',
            }),
            'product.json': instance(
              'collectible-product',
              'CollectibleProduct',
              { sku: 'DZ5485-612' },
            ),
            'pair.json': instance(
              'collection-item',
              'CollectionItem',
              { variant: '10' },
              { owner: link('owner'), item: link('product') },
            ),
          },
        });
        await visitOperatorMode({ stacks: [[]] });
      });

      // Loaded through the host's loader, as the host runs a command.
      async function run(itemId: string, outcome: 'passed' | 'failed') {
        let { default: Command } = (await getService(
          'loader-service',
        ).loader.import(
          `${collectibles}commands/authenticate-item-command`,
        )) as {
          default: typeof AuthenticateItemCommand;
        };
        let command = new Command(getService('tool-service').commandContext);
        return command.execute({
          itemId: `${realmURL}${itemId}`,
          outcome,
          authenticator: 'Checker',
          certificateId: 'CERT-1',
        });
      }

      test('authenticate-item clears an earlier pass when a re-check fails', async function (assert) {
        let store = getService('store');

        await run('pair', 'passed');
        let item = (await store.get(`${realmURL}pair`)) as CollectionItem;
        assert.ok(item.verified, 'a pass marks the item verified');
        assert.strictEqual(item.verifiedBy, 'Checker');

        await run('pair', 'failed');
        item = (await store.get(`${realmURL}pair`)) as CollectionItem;
        assert.notOk(
          item.verified,
          'a failed re-check removes the verification',
        );
        assert.notOk(item.verifiedBy, 'and the verifier with it');
      });

      test('authenticate-item rejects a card that is not a collection item', async function (assert) {
        await assert.rejects(
          run('product', 'passed'),
          /is not a Collection Item/,
        );
      });
    },
  );
}
