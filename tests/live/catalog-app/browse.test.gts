import {
  click,
  waitFor,
  waitUntil,
  fillIn,
  settled,
  triggerEvent,
} from '@ember/test-helpers';

import { module, test } from 'qunit';

import {
  setupLocalIndexing,
  setupOnSave,
  testRealmURL as nonCatalogRealmURL,
  setupAuthEndpoints,
  setupUserSubscription,
  setupAcceptanceTestRealm,
  SYSTEM_CARD_FIXTURE_CONTENTS,
  visitOperatorMode,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

import {
  makeMockCatalogContents,
  makeDestinationRealmContents,
} from '../../helpers/test-fixtures';

// The test file is served from the catalog realm, so its own URL tells us
// where the realm is without needing an env var. This file lives in the
// catalog-app/ subdirectory, so we go up one level to reach the realm root.
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const testDestinationRealmURL = `http://test-realm/test2/`;
// A realm URL ending with /catalog/ so isRemixableRealm returns true
const catalogRealmMockURL = `http://test-realm/catalog/`;

//listing
const authorListingId = `${nonCatalogRealmURL}Listing/author`;
const catalogRealmAuthorListingId = `${catalogRealmMockURL}Listing/author`;
const personListingId = `${nonCatalogRealmURL}Listing/person`;
const emptyListingId = `${nonCatalogRealmURL}Listing/empty`;
const pirateSkillListingId = `${nonCatalogRealmURL}SkillListing/pirate-skill`;
const incompleteSkillListingId = `${nonCatalogRealmURL}Listing/incomplete-skill`;

export function runTests() {
  module('Acceptance | Catalog | catalog app - browse tests', function (hooks) {
    setupApplicationTest(hooks);
    setupLocalIndexing(hooks);
    setupOnSave(hooks);

    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: '@testuser:localhost',
      activeRealms: [
        nonCatalogRealmURL,
        testDestinationRealmURL,
        catalogRealmMockURL,
      ],
    });

    let { getRoomIds, createAndJoinRoom } = mockMatrixUtils;

    hooks.beforeEach(async function () {
      createAndJoinRoom({
        sender: '@testuser:localhost',
        name: 'room-test',
      });
      setupUserSubscription();
      setupAuthEndpoints();
      // this setup test realm is pretending to be a mock catalog
      await setupAcceptanceTestRealm({
        realmURL: nonCatalogRealmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          ...makeMockCatalogContents(nonCatalogRealmURL, catalogRealmURL),
        },
      });
      await setupAcceptanceTestRealm({
        mockMatrixUtils,
        realmURL: testDestinationRealmURL,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          ...makeDestinationRealmContents(),
        },
      });
      // Catalog realm whose URL ends with /catalog/ so isRemixableRealm returns true
      await setupAcceptanceTestRealm({
        realmURL: catalogRealmMockURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          ...makeMockCatalogContents(catalogRealmMockURL, catalogRealmURL),
        },
      });
    });

    /**
     * Selects a storefront nav tab by its tabId (card, field, skill, …)
     */
    async function selectTab(tabId: string) {
      await waitFor(
        `[data-test-catalog-app] [data-test-storefront-tab="${tabId}"]`,
      );
      await click(
        `[data-test-catalog-app] [data-test-storefront-tab="${tabId}"]`,
      );
    }

    /**
     * Waits for grid to load in the catalog app
     */
    async function waitForGrid() {
      await waitFor('[data-test-cards-grid-cards]');
      await settled();
    }

    /**
     * Waits for the storefront hero (the showcase landing view) to load
     */
    async function waitForShowcase() {
      await waitFor('[data-test-storefront-hero]');
      await settled();
    }

    /**
     * Waits for a card to appear on the grid with optional title verification
     */
    async function waitForCardOnGrid(cardId: string, title?: string) {
      await waitFor(`[data-test-cards-grid-item="${cardId}"]`);
      if (title) {
        await waitFor(
          `[data-test-cards-grid-item="${cardId}"] [data-test-card-title="${title}"]`,
          //its problematic when we are waiting for computed title
          //my recommendation for the purposes of test is to populate the card title in the realm
        );
      }
    }

    /**
     * Waits for a card to appear on the stack with optional title verification
     */
    async function waitForCardOnStack(cardId: string, expectedTitle?: string) {
      await waitFor(
        `[data-test-stack-card="${cardId}"] [data-test-boxel-card-header-title]`,
      );
      if (expectedTitle) {
        await waitFor(
          `[data-test-stack-card="${cardId}"] [data-test-boxel-card-header-title]`,
        );
      }
    }

    async function clickDropdownItem(menuItemText: string) {
      let selector = `[data-test-boxel-dropdown-content] [data-test-boxel-menu-item-text="${menuItemText}"]`;
      await waitFor(selector);
      await click(selector);
    }

    // The hydrated live component replaces the prerendered tile on the same
    // element, so the hydration marker can be awaited on the card itself.
    async function hoverToHydrateCard(cardSelector: string) {
      await waitFor(cardSelector);
      await triggerEvent(cardSelector, 'mouseenter');
      await waitFor(`${cardSelector}[data-test-hydrated-card]`);
    }

    module('catalog index', function (hooks) {
      hooks.beforeEach(async function () {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: `${nonCatalogRealmURL}index`,
                format: 'isolated',
              },
            ],
          ],
        });
        await waitForShowcase();
      });

      module('listing fitted', function () {
        test('after clicking "Remix", the listing details open with the remix panel', async function (assert) {
          await selectTab('card');
          await waitForGrid();
          await waitForCardOnGrid(authorListingId, 'Author');
          await hoverToHydrateCard(
            `[data-test-cards-grid-item="${authorListingId}"]`,
          );
          // The Remix click bails out until the tile's listing actions are
          // ready; the Preview button only renders once they are, so its
          // presence is the readiness signal.
          await waitFor(
            `[data-test-cards-grid-item="${authorListingId}"] [data-test-listing-fitted-preview]`,
          );
          await click(
            `[data-test-cards-grid-item="${authorListingId}"] [data-test-listing-fitted-remix]`,
          );
          await waitForCardOnStack(authorListingId);
          assert
            .dom(
              `[data-test-stack-card="${authorListingId}"] [data-remix-panel].is-focused`,
            )
            .exists(
              'the detail view opens with its remix panel focused by the remix intent',
            );
        });

        test('after clicking "Preview" button, the first example card opens up onto the stack', async function (assert) {
          await selectTab('card');
          await waitForGrid();
          await waitForCardOnGrid(authorListingId, 'Author');
          await hoverToHydrateCard(
            `[data-test-cards-grid-item="${authorListingId}"]`,
          );
          await click(
            `[data-test-cards-grid-item="${authorListingId}"] [data-test-listing-fitted-preview]`,
          );
          await waitForCardOnStack(
            `${nonCatalogRealmURL}author/Author/example`,
          );
          assert
            .dom(
              `[data-test-stack-card="${nonCatalogRealmURL}author/Author/example"] [data-test-boxel-card-header-title]`,
            )
            .hasText('Author - Mike Dane');
        });

        test('after clicking "View details", the listing details card opens up onto the stack', async function (assert) {
          await selectTab('card');
          await waitForGrid();
          await waitForCardOnGrid(authorListingId, 'Author');
          await hoverToHydrateCard(
            `[data-test-cards-grid-item="${authorListingId}"]`,
          );
          await click(
            `[data-test-cards-grid-item="${authorListingId}"] [data-test-listing-fitted-details]`,
          );
          await waitForCardOnStack(authorListingId);
          assert
            .dom(
              `[data-test-stack-card="${authorListingId}"] [data-test-boxel-card-header-title]`,
            )
            .hasText('CardListing - Author');
        });

        test('fitted card shows a screenshot when present and a monogram cover when not', async function (assert) {
          await selectTab('card');
          await waitForGrid();
          await waitForCardOnGrid(personListingId, 'Person');
          assert
            .dom(
              `[data-test-cards-grid-item="${personListingId}"] [data-test-listing-fitted][data-no-image="false"] .media-img`,
            )
            .exists('a listing with screenshots renders the first one');

          await waitForCardOnGrid(emptyListingId, 'Empty');
          assert
            .dom(
              `[data-test-cards-grid-item="${emptyListingId}"] [data-test-listing-fitted][data-no-image="true"] .monogram`,
            )
            .hasText(
              'E',
              'a listing with no screenshot falls back to its monogram',
            );
        });

        test('preview button appears only when examples exist', async function (assert) {
          await selectTab('card');
          await waitForGrid();
          await waitForCardOnGrid(authorListingId);
          await hoverToHydrateCard(
            `[data-test-cards-grid-item="${authorListingId}"]`,
          );
          assert
            .dom(
              `[data-test-cards-grid-item="${authorListingId}"] [data-test-listing-fitted-preview]`,
            )
            .exists('preview button renders when the listing has examples');

          await waitForCardOnGrid(emptyListingId);
          await hoverToHydrateCard(
            `[data-test-cards-grid-item="${emptyListingId}"]`,
          );
          assert
            .dom(
              `[data-test-cards-grid-item="${emptyListingId}"] [data-test-listing-fitted-preview]`,
            )
            .doesNotExist(
              'preview button is omitted when the listing has no examples',
            );
        });
      });

      module('navigation', function () {
        module('show results as per catalog tab selected', function () {
          test('switch to cards tab', async function (assert) {
            await selectTab('card');
            await waitForGrid();
            assert
              .dom('[data-test-storefront-tab="card"]')
              .hasClass('is-active', 'the Cards tab is selected');
            assert
              .dom('[data-test-storefront-hero]')
              .doesNotExist('the hero is hidden outside the showcase view');
            assert
              .dom('[data-test-catalog-gallery] .gallery-title')
              .hasText('Cards');
          });
        });

        module('filters', function () {
          test('search filters the gallery and hides the hero', async function (assert) {
            await fillIn('[data-test-storefront-search]', 'Person');
            await waitUntil(
              () =>
                document.querySelectorAll(
                  '[data-test-cards-grid-cards] [data-test-cards-grid-item]',
                ).length === 1,
              { timeout: 10_000 },
            );
            assert
              .dom(`[data-test-cards-grid-item="${personListingId}"]`)
              .exists('only the matching listing remains');
            assert
              .dom('[data-test-storefront-hero]')
              .doesNotExist('the hero is hidden while a search is active');
          });

          test('type pill filters the gallery to that listing type', async function (assert) {
            await click('[data-test-type-pill="skill"]');
            await waitUntil(
              () =>
                document.querySelectorAll(
                  '[data-test-cards-grid-cards] [data-test-cards-grid-item]',
                ).length === 2,
              { timeout: 10_000 },
            );
            assert
              .dom(`[data-test-cards-grid-item="${pirateSkillListingId}"]`)
              .exists();
            assert
              .dom(`[data-test-cards-grid-item="${incompleteSkillListingId}"]`)
              .exists();
            assert
              .dom('[data-test-storefront-tab="skill"]')
              .hasClass('is-active', 'the type pills mirror the nav tabs');
          });

          test('a type pill and a search combine', async function (assert) {
            await click('[data-test-type-pill="skill"]');
            await fillIn('[data-test-storefront-search]', 'Pirate');
            await waitUntil(
              () =>
                document.querySelectorAll(
                  '[data-test-cards-grid-cards] [data-test-cards-grid-item]',
                ).length === 1,
              { timeout: 10_000 },
            );
            assert
              .dom(`[data-test-cards-grid-item="${pirateSkillListingId}"]`)
              .exists('only the skill matching the search remains');
          });

          test('a non-matching search shows no results and "Show everything" resets', async function (assert) {
            await fillIn('[data-test-storefront-search]', 'asdfasdf');
            await waitFor('[data-test-no-results]', { timeout: 10_000 });
            assert.dom('[data-test-no-results]').exists();

            await click('[data-test-no-results] .clear-link');
            await waitForShowcase();
            assert
              .dom('[data-test-storefront-search]')
              .hasValue('', 'the search input is cleared');
            await waitUntil(
              () =>
                document.querySelectorAll(
                  '[data-test-cards-grid-cards] [data-test-cards-grid-item]',
                ).length === 11,
              { timeout: 10_000 },
            );
            assert
              .dom('[data-test-cards-grid-cards] [data-test-cards-grid-item]')
              .exists({ count: 11 }, 'the full gallery returns');
          });
        });
      });
    });

    module('listing isolated', function (hooks) {
      hooks.beforeEach(async function () {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: authorListingId,
                format: 'isolated',
              },
            ],
          ],
        });
      });

      test('listing card shows more options dropdown in stack item', async function (assert) {
        let triggerSelector = `[data-test-stack-card="${authorListingId}"] [data-test-more-options-button]`;
        await waitFor(triggerSelector);
        await click(triggerSelector);
        await waitFor('[data-test-boxel-dropdown-content]');
        assert
          .dom('[data-test-boxel-dropdown-content] [data-test-boxel-menu-item]')
          .exists('Listing card dropdown renders menu items');
        assert
          .dom(
            `[data-test-boxel-dropdown-content] [data-test-boxel-menu-item-text="Generate Example with AI"]`,
          )
          .exists('Generate Example with AI action is present');
      });

      test('remix button is hidden in isolated view when listing is not under catalog realm', async function (assert) {
        assert
          .dom(
            `[data-test-card="${authorListingId}"] [data-test-catalog-listing-action]`,
          )
          .doesNotExist(
            'Remix button should be hidden when listing is not under catalog realm',
          );
      });

      test('remixing a catalog realm listing initiates an ai room with the remix prompt', async function (assert) {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: catalogRealmAuthorListingId,
                format: 'isolated',
              },
            ],
          ],
        });
        let roomsBefore = getRoomIds().length;
        let remixButton = `[data-test-card="${catalogRealmAuthorListingId}"] [data-test-catalog-listing-action="Remix into my realm"]`;
        await waitFor(remixButton);
        await click(remixButton);
        await clickDropdownItem('Test Workspace B');

        await waitUntil(() => getRoomIds().length > roomsBefore, {
          timeout: 30_000,
        });
        const roomId = getRoomIds().pop()!;
        await waitFor(`[data-test-room="${roomId}"][data-test-room-settled]`, {
          timeout: 30_000,
        });
        await waitFor(
          `[data-test-room="${roomId}"] [data-test-ai-message-content]`,
        );
        await settled();
        assert
          .dom(`[data-test-room="${roomId}"] [data-test-ai-message-content]`)
          .containsText(
            'Remix done! Please suggest two example prompts on how to edit this card.',
          );
      });

      test('after clicking "Use Skills" button, the skills is attached to the skill menu', async function (assert) {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: pirateSkillListingId,
                format: 'isolated',
              },
            ],
          ],
        });
        await click('[data-test-listing-use-skills-button]');

        await waitFor('[data-room-settled]');
        await click('[data-test-skill-menu][data-test-pill-menu-button]');
        await waitFor('[data-test-skill-menu]');
        assert.dom('[data-test-skill-menu]').exists('Skill menu is visible');
        assert
          .dom('[data-test-pill-menu-item]')
          .containsText('Talk Like a Pirate')
          .exists('Skill is attached to the skill menu');
      });

      test('after clicking "Preview" button, the first example card opens up onto the stack', async function (assert) {
        await click(
          `[data-test-card="${authorListingId}"] [data-test-listing-preview-button]`,
        );
        await waitForCardOnStack(`${nonCatalogRealmURL}author/Author/example`);
        assert
          .dom(
            `[data-test-stack-card="${nonCatalogRealmURL}author/Author/example"] [data-test-boxel-card-header-title]`,
          )
          .hasText('Author - Mike Dane');
      });

      test('display of sections when viewing listing details', async function (assert) {
        assert
          .dom('[data-test-listing-summary]')
          .containsText('A card for representing an author');
        assert
          .dom('[data-test-listing-publisher]')
          .containsText('@Boxel Publishing');
        assert.dom('[data-test-listing-tags]').containsText('Calculator');

        await click('[data-test-listing-tab="Includes"]');
        assert
          .dom('[data-test-listing-includes] [data-test-spec-card]')
          .exists({ count: 1 });

        await click('[data-test-listing-tab="Examples"]');
        assert
          .dom('[data-test-listing-examples] .example-card')
          .exists({ count: 1 });

        await click('[data-test-listing-tab="License"]');
        assert.dom('[data-test-listing-license]').containsText('MIT License');
      });

      test('listing with spec that has a missing specType groups it under unknown', async function (assert) {
        const unknownListingId = `${nonCatalogRealmURL}Listing/unknown-only`;
        await visitOperatorMode({
          stacks: [
            [
              {
                id: unknownListingId,
                format: 'isolated',
              },
            ],
          ],
        });

        await click('[data-test-listing-tab="Includes"]');
        assert
          .dom('[data-test-listing-includes] [data-test-listing-spec-group]')
          .exists({ count: 1 });
        assert
          .dom('[data-test-listing-spec-group="unknown"]')
          .containsText('Other', 'unknown specs group under the Other label');
        assert
          .dom('[data-test-listing-spec-group="unknown"] [data-test-spec-card]')
          .exists({ count: 1 });
      });

      test('unknown-only listing shows all default fallback texts', async function (assert) {
        const unknownListingId = `${nonCatalogRealmURL}Listing/unknown-only`;
        await visitOperatorMode({
          stacks: [
            [
              {
                id: unknownListingId,
                format: 'isolated',
              },
            ],
          ],
        });

        assert
          .dom('[data-test-listing-summary]')
          .containsText('No summary provided.');
        assert
          .dom('[data-test-listing-tags]')
          .doesNotExist('tags card is omitted when there are no tags');

        await click('[data-test-listing-tab="Examples"]');
        assert
          .dom('[data-test-listing-examples]')
          .containsText('No examples provided.');

        await click('[data-test-listing-tab="License"]');
        assert
          .dom('[data-test-listing-license]')
          .containsText('Open Remix', 'license falls back to Open Remix');
      });

      test('remix button does not exist when a listing has no specs', async function (assert) {
        await visitOperatorMode({
          stacks: [
            [
              {
                id: emptyListingId,
                format: 'isolated',
              },
            ],
          ],
        });
        await click('[data-test-listing-tab="Includes"]');
        assert
          .dom('[data-test-listing-includes]')
          .containsText('No specs included.');
        assert.dom('[data-test-catalog-listing-action]').doesNotExist();
      });

      test('remix button does not exist when a skill listing has no skills', async function (assert) {
        const emptySkillListingId = incompleteSkillListingId;
        await visitOperatorMode({
          stacks: [
            [
              {
                id: emptySkillListingId,
                format: 'isolated',
              },
            ],
          ],
        });
        assert
          .dom('[data-test-listing-use-skills-button]')
          .doesNotExist(
            'Use Skills button is omitted when the listing has no skills',
          );
        assert.dom('[data-test-catalog-listing-action]').doesNotExist();
      });
    });
  });
}
