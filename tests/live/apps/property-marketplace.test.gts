import { waitUntil } from '@ember/test-helpers';
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

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/property-marketplace/';
const appModule = `${catalogRealmURL}cards/property-marketplace/property-marketplace-app`;
const listingModule = `${catalogRealmURL}cards/real-estate/property-listing`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: { cardInfo: { name: 'Property Marketplace' } },
      meta: {
        adoptsFrom: { module: appModule, name: 'PropertyMarketplaceApp' },
      },
    },
  };
}

function listing(
  headline: string,
  status: string,
  amount: number | null,
  publishedAt: string | null,
) {
  return {
    data: {
      type: 'card',
      attributes: {
        headline,
        status,
        publishedAt,
        askingPrice:
          amount == null ? null : { amount, currency: { code: 'USD' } },
      },
      meta: { adoptsFrom: { module: listingModule, name: 'PropertyListing' } },
    },
  };
}

function appText(): string {
  return document.querySelector('article.market')?.textContent ?? '';
}

function daysAgo(days: number): string {
  return new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
}

export function runTests() {
  module(
    'Acceptance | Catalog | apps - property marketplace',
    function (hooks) {
      setupApplicationTest(hooks);
      setupLocalIndexing(hooks);
      setupOnSave(hooks);

      let mockMatrixUtils = setupMockMatrix(hooks, {
        loggedInAs: '@testuser:localhost',
        activeRealms: [realmURL],
      });

      hooks.beforeEach(function () {
        mockMatrixUtils.createAndJoinRoom({
          sender: '@testuser:localhost',
          name: 'room-test',
        });
        setupUserSubscription();
        setupAuthEndpoints();
      });

      async function open() {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${realmURL}PropertyMarketplaceApp/main`,
                format: 'isolated',
              },
            ],
          ],
        });
        await waitUntil(
          () => Boolean(document.querySelector('article.market')),
          {
            timeout: 30000,
          },
        );
      }

      test('it reads the book: value on the market and what needs attention', async function (assert) {
        await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'PropertyMarketplaceApp/main.json': app(),
            'PropertyListing/test-stale.json': listing(
              'Test Stale House',
              'published',
              400000,
              daysAgo(45),
            ),
            'PropertyListing/test-offer.json': listing(
              'Test Offer Flat',
              'under-offer',
              100000,
              daysAgo(5),
            ),
            'PropertyListing/test-draft.json': listing(
              'Test Draft Cottage',
              'draft',
              null,
              null,
            ),
          },
        });
        await open();
        await waitUntil(() => appText().includes('Test Draft Cottage'), {
          timeout: 30000,
        });

        assert.ok(
          appText().includes('$500,000.00'),
          'the value on the market sums the two live listings',
        );
        let attention =
          document.querySelector('article.market .attn')?.textContent ?? '';
        assert.ok(
          attention.includes('Test Stale House'),
          'a live listing past 30 days needs attention',
        );
        assert.ok(
          attention.includes('Test Draft Cottage'),
          'a draft with no price needs attention',
        );
        assert.notOk(
          attention.includes('Test Offer Flat'),
          'a fresh listing does not',
        );
      });

      test('it renders an empty realm with a prompt to create a listing', async function (assert) {
        await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'PropertyMarketplaceApp/main.json': app(),
          },
        });
        await open();
        await waitUntil(() => appText().includes('No listings yet'), {
          timeout: 30000,
        });

        assert.ok(
          appText().includes('Create the first listing'),
          'the empty realm offers the first listing',
        );
      });
    },
  );
}
