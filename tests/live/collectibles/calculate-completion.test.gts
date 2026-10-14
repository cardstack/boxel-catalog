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

import type CalculateCompletionCommand from '../../../cards/collectibles/commands/calculate-completion-command';

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

function product(sku: string, availableVariants: string[] = []) {
  return instance('collectible-product', 'CollectibleProduct', {
    sku,
    availableVariants,
  });
}

function item(owner: string, productId: string, variant?: string) {
  return instance(
    'collection-item',
    'CollectionItem',
    variant ? { variant } : {},
    { owner: link(owner), item: link(productId) },
  );
}

function set(name: string, completionRule: string, products: string[]) {
  return instance(
    'completion-set',
    'CompletionSet',
    { cardInfo: { name }, completionRule },
    Object.fromEntries(products.map((id, i) => [`products.${i}`, link(id)])),
  );
}

export function runTests() {
  module(
    'Acceptance | Catalog | collectibles - calculate completion',
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
            'ana.json': instance('marketplace-member', 'MarketplaceMember', {
              name: 'Ana',
            }),
            'ben.json': instance('marketplace-member', 'MarketplaceMember', {
              name: 'Ben',
            }),
            'p1.json': product('P1'),
            'p2.json': product('P2'),
            'p3.json': product('P3'),
            'p4.json': product('P4'),
            'set.json': instance(
              'completion-set',
              'CompletionSet',
              { cardInfo: { name: 'Four pairs' } },
              {
                'products.0': link('p1'),
                'products.1': link('p2'),
                'products.2': link('p3'),
                'products.3': link('p4'),
              },
            ),
            'ana-p1.json': item('ana', 'p1'),
            'ben-p2.json': item('ben', 'p2'),
            'ben-p3.json': item('ben', 'p3'),
            // p5 comes in two sizes and Cleo owns one; p6 lists no sizes.
            'p5.json': product('P5', ['9', '10']),
            'p6.json': product('P6'),
            'own-any.json': set('Any size', 'own-any', ['p5', 'p6']),
            'own-all.json': set('Every size', 'own-all', ['p5', 'p6']),
            'cleo.json': instance('marketplace-member', 'MarketplaceMember', {
              name: 'Cleo',
            }),
            'cleo-p5-9.json': item('cleo', 'p5', '9'),
            'cleo-p6.json': item('cleo', 'p6'),
          },
        });
        await visitOperatorMode({ stacks: [[]] });
      });

      async function run(ownerId?: string, setId = 'set') {
        let { default: Command } = (await getService(
          'loader-service',
        ).loader.import(
          `${collectibles}commands/calculate-completion-command`,
        )) as { default: typeof CalculateCompletionCommand };
        let command = new Command(getService('tool-service').commandContext);
        return command.execute({
          completionSetId: `${realmURL}${setId}`,
          ...(ownerId ? { ownerId: `${realmURL}${ownerId}` } : {}),
        });
      }

      test('calculate-completion counts only the given owner', async function (assert) {
        let ana = await run('ana');
        assert.strictEqual(ana?.ownedCount, 1, 'Ana owns one of the set');
        assert.strictEqual(ana?.targetCount, 4);
        assert.strictEqual(ana?.percent, 25);

        let ben = await run('ben');
        assert.strictEqual(ben?.ownedCount, 2, 'Ben owns two of the set');
        assert.strictEqual(ben?.percent, 50);
      });

      test('calculate-completion applies the set completion rule', async function (assert) {
        let any = await run('cleo', 'own-any');
        assert.strictEqual(any?.ownedCount, 2, 'any copy completes a product');
        assert.strictEqual(any?.percent, 100);

        let all = await run('cleo', 'own-all');
        assert.strictEqual(
          all?.ownedCount,
          1,
          'p5 needs both sizes; p6 lists none, so one copy completes it',
        );
        assert.strictEqual(all?.percent, 50);
      });

      test('calculate-completion without an owner counts every item', async function (assert) {
        let all = await run();
        assert.strictEqual(all?.ownedCount, 3, 'the union of both owners');
        assert.strictEqual(all?.percent, 75);
      });
    },
  );
}
