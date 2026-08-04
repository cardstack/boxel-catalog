import {
  click,
  waitFor,
  waitUntil,
  fillIn,
  settled,
  triggerEvent,
} from '@ember/test-helpers';

import { module, skip, test } from 'qunit';

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
//tags
const calculatorTagId = `${nonCatalogRealmURL}Tag/calculator`;
const gameTagId = `${nonCatalogRealmURL}Tag/game`;

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

    async function hoverToHydrateCard(buttonSelector: string) {
      await waitFor(buttonSelector);
      await triggerEvent(buttonSelector, 'mouseenter');
      await waitFor('[data-test-hydrated-card]');
    }

    async function openMenu(buttonSelector: string, checkHydration = true) {
      await waitFor(buttonSelector);
      await triggerEvent(buttonSelector, 'mouseenter');
      if (checkHydration) {
        await waitFor('[data-test-hydrated-card]');
      }
      await click(buttonSelector);
    }

    async function executeListingAction(
      buttonSelector: string,
      menuItemText: string,
      checkHydration = true,
    ) {
      await openMenu(buttonSelector, checkHydration);
      await clickDropdownItem(menuItemText);
    }

    async function verifyListingAction(
      assert: Assert,
      listingSelector: string,
      actionSelector: string,
      expectedText: string,
      expectedMessage: string,
      menuItemName = 'Test Workspace B',
      checkHydration = true,
    ) {
      let buttonSelector = `${listingSelector} ${actionSelector}`;
      await waitFor(buttonSelector);
      assert.dom(buttonSelector).containsText(expectedText);
      await executeListingAction(buttonSelector, menuItemName, checkHydration);
      await waitUntil(() => getRoomIds().length > 0);

      const roomId = getRoomIds().pop()!;
      await waitFor(`[data-test-room="${roomId}"][data-test-room-settled]`);
      await waitFor(
        `[data-test-room="${roomId}"] [data-test-ai-assistant-message]`,
      );

      await waitFor(
        `[data-test-room="${roomId}"] [data-test-ai-message-content]`,
      );
      await settled();

      assert
        .dom(`[data-test-room="${roomId}"] [data-test-ai-message-content]`)
        .containsText(expectedMessage);
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
          await click(
            `[data-test-cards-grid-item="${authorListingId}"] [data-test-listing-fitted-remix]`,
          );
          await waitForCardOnStack(authorListingId);
          assert
            .dom(
              `[data-test-stack-card="${authorListingId}"] [data-remix-panel]`,
            )
            .exists('the detail view opens showing the remix panel');
        });

        skip('after clicking "Remix" button on catalog realm listing, the ai room is initiated and prompt is given correctly', async function (assert) {
          await visitOperatorMode({
            stacks: [
              [
                {
                  id: `${catalogRealmMockURL}index`,
                  format: 'isolated',
                },
              ],
            ],
          });
          await waitForShowcase();
          await selectTab('card');
          await waitForGrid();
          await waitForCardOnGrid(catalogRealmAuthorListingId, 'Author');
          await verifyListingAction(
            assert,
            `[data-test-cards-grid-item="${catalogRealmAuthorListingId}"]`,
            '[data-test-catalog-listing-action="Remix"]',
            'Remix',
            'Remix done! Please suggest two example prompts on how to edit this card.',
            'Test Workspace B',
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
          await triggerEvent(
            `[data-test-cards-grid-item="${emptyListingId}"]`,
            'mouseenter',
          );
          await waitFor(
            `[data-test-cards-grid-item="${emptyListingId}"][data-test-hydrated-card]`,
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

        module.skip('filters', function () {
          test('list view is shown if filters are applied', async function (assert) {
            await waitFor('[data-test-filter-search-input]');
            await click('[data-test-filter-search-input]');
            await fillIn('[data-test-filter-search-input]', 'Mortgage');
            // filter by category
            await click('[data-test-filter-list-item="All"]');
            // filter by tag
            let tagPill = document.querySelector('[data-test-tag-list-pill]');
            if (tagPill) {
              await click(tagPill);
            }

            await waitUntil(() => {
              const cards = document.querySelectorAll(
                '[data-test-catalog-list-view]',
              );
              return cards.length === 1;
            });

            assert
              .dom('[data-test-catalog-list-view]')
              .exists(
                'Catalog list view should be visible when filters are applied',
              );
          });

          // TODO: restore in CS-9083
          skip('should be reset when clicking "Catalog Home" button', async function (assert) {
            await waitFor('[data-test-filter-search-input]');
            await click('[data-test-filter-search-input]');
            await fillIn('[data-test-filter-search-input]', 'Mortgage');
            // filter by category
            await click('[data-test-filter-list-item="All"]');
            // filter by tag
            let tagPill = document.querySelector('[data-test-tag-list-pill]');
            if (tagPill) {
              await click(tagPill);
            }

            assert
              .dom('[data-test-showcase-view]')
              .doesNotExist('Should be in list view after applying filter');

            await click('[data-test-navigation-reset-button="showcase"]');

            assert
              .dom('[data-test-showcase-view]')
              .exists(
                'Should return to showcase view after clicking Catalog Home',
              );

            assert
              .dom('[data-test-filter-search-input]')
              .hasValue('', 'Search input should be cleared');
            assert
              .dom('[data-test-filter-list-item].is-selected')
              .doesNotExist('No category should be selected after reset');
            assert
              .dom('[data-test-tag-list-pill].selected')
              .doesNotExist('No tag should be selected after reset');
          });

          skip('updates the card count correctly when filtering by a sphere group', async function (assert) {
            await click('[data-test-boxel-filter-list-button="LIFE"]');
            assert
              .dom('[data-test-cards-grid-cards] [data-test-cards-grid-item]')
              .exists({ count: 2 });
          });

          skip('updates the card count correctly when filtering by a category', async function (assert) {
            await click('[data-test-filter-list-item="LIFE"] .dropdown-toggle');
            await click(
              '[data-test-boxel-filter-list-button="Health & Wellness"]',
            );
            assert
              .dom('[data-test-cards-grid-cards] [data-test-cards-grid-item]')
              .exists({ count: 1 });
          });

          skip('updates the card count correctly when filtering by a search input', async function (assert) {
            await click('[data-test-filter-search-input]');
            await fillIn('[data-test-filter-search-input]', 'Mortgage');
            await waitUntil(() => {
              const cards = document.querySelectorAll(
                '[data-test-cards-grid-cards] [data-test-cards-grid-item]',
              );
              return cards.length === 1;
            });
            assert
              .dom('[data-test-cards-grid-cards] [data-test-cards-grid-item]')
              .exists({ count: 1 });
          });

          test('updates the card count correctly when filtering by a single tag', async function (assert) {
            await click(`[data-test-tag-list-pill="${gameTagId}"]`);
            assert
              .dom(`[data-test-tag-list-pill="${gameTagId}"]`)
              .hasClass('selected');
            assert
              .dom('[data-test-cards-grid-cards] [data-test-cards-grid-item]')
              .exists({ count: 1 });
          });

          test('updates the card count correctly when filtering by multiple tags', async function (assert) {
            await click(`[data-test-tag-list-pill="${calculatorTagId}"]`);
            await click(`[data-test-tag-list-pill="${gameTagId}"]`);
            assert
              .dom('[data-test-cards-grid-cards] [data-test-cards-grid-item]')
              .exists({ count: 2 });
          });

          test('updates the card count correctly when multiple filters are applied together', async function (assert) {
            await click('[data-test-boxel-filter-list-button="All"]');
            await click(`[data-test-tag-list-pill="${gameTagId}"]`);
            await click('[data-test-filter-search-input]');
            await fillIn('[data-test-filter-search-input]', 'Blackjack');

            await waitUntil(() => {
              const cards = document.querySelectorAll(
                '[data-test-cards-grid-cards] [data-test-cards-grid-item]',
              );
              return cards.length === 1;
            });

            assert
              .dom('[data-test-cards-grid-cards] [data-test-cards-grid-item]')
              .exists({ count: 1 });
          });

          test('shows zero results when filtering with a non-matching or invalid search input', async function (assert) {
            await click('[data-test-filter-search-input]');
            await fillIn('[data-test-filter-search-input]', 'asdfasdf');
            await waitUntil(() => {
              const cards = document.querySelectorAll('[data-test-no-results]');
              return cards.length === 1;
            });

            assert.dom('[data-test-no-results]').exists();
          });

          test('categories with null sphere fields are excluded from filter list', async function (assert) {
            // Setup: Create a category with null sphere field
            await setupAcceptanceTestRealm({
              realmURL: nonCatalogRealmURL,
              mockMatrixUtils,
              contents: {
                ...SYSTEM_CARD_FIXTURE_CONTENTS,
                'Category/category-with-null-sphere.json': {
                  data: {
                    type: 'card',
                    attributes: {
                      name: 'CategoryWithNullSphere',
                    },
                    relationships: {
                      sphere: {
                        links: {
                          self: null,
                        },
                      },
                    },
                    meta: {
                      adoptsFrom: {
                        module: `${nonCatalogRealmURL}catalog-app/listing/category`,
                        name: 'Category',
                      },
                    },
                  },
                },
              },
            });

            await visitOperatorMode({
              stacks: [
                [
                  {
                    id: `${nonCatalogRealmURL}`,
                    format: 'isolated',
                  },
                ],
              ],
            });

            assert
              .dom(
                '[data-test-boxel-filter-list-button="CategoryWithNullSphere"]',
              )
              .doesNotExist(
                'Category with null sphere should not appear in filter list',
              );
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

      skip('after clicking "Remix" button on catalog realm listing, the ai room is initiated and prompt is given correctly', async function (assert) {
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
        await verifyListingAction(
          assert,
          `[data-test-card="${catalogRealmAuthorListingId}"]`,
          '[data-test-catalog-listing-action="Remix"]',
          'Remix',
          'Remix done! Please suggest two example prompts on how to edit this card.',
          'Test Workspace B',
          false,
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
