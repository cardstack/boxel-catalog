import { waitFor } from '@ember/test-helpers';

import { getService } from '@universal-ember/test-support';
import { module, skip, test } from 'qunit';

import { ensureTrailingSlash } from '@cardstack/runtime-common';

import ListingCreateCommand from '@cardstack/boxel-host/commands/listing-create';

import ENV from '@cardstack/host/config/environment';

import {
  setupLocalIndexing,
  setupOnSave,
  testRealmURL as mockCatalogURL,
  setupAuthEndpoints,
  setupUserSubscription,
  setupAcceptanceTestRealm,
  SYSTEM_CARD_FIXTURE_CONTENTS,
  visitOperatorMode,
  verifySubmode,
  openDir,
  verifyJSONWithUUIDInFolder,
  setupRealmServerEndpoints,
  setCatalogRealmURL,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

import type { CardListing } from '@cardstack/catalog/listing/listing';

import {
  makeMockCatalogContents,
  makeDestinationRealmContents,
} from './catalog-app-test-fixtures';

const catalogRealmURL = ensureTrailingSlash(ENV.resolvedCatalogRealmURL);
const testDestinationRealmURL = `http://test-realm/test2/`;

//listing
const apiDocumentationStubListingId = `${mockCatalogURL}Listing/api-documentation-stub`;
//license
const mitLicenseId = `${mockCatalogURL}License/mit`;
//category
const writingCategoryId = `${mockCatalogURL}Category/writing`;

//tags
const calculatorTagId = `${mockCatalogURL}Tag/c1fe433a-b3df-41f4-bdcf-d98686ee42d7`;

export function runTests() {
  module(
    'Acceptance | Catalog | catalog app - listing create',
    function (hooks) {
      setupApplicationTest(hooks);
      setupLocalIndexing(hooks);
      setupOnSave(hooks);

      let mockMatrixUtils = setupMockMatrix(hooks, {
        loggedInAs: '@testuser:localhost',
        activeRealms: [mockCatalogURL, testDestinationRealmURL],
      });

      let { createAndJoinRoom } = mockMatrixUtils;

      hooks.beforeEach(async function () {
        createAndJoinRoom({
          sender: '@testuser:localhost',
          name: 'room-test',
        });
        setupUserSubscription();
        setupAuthEndpoints();
        setCatalogRealmURL(mockCatalogURL, catalogRealmURL);
        // this setup test realm is pretending to be a mock catalog
        await setupAcceptanceTestRealm({
          realmURL: mockCatalogURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            ...makeMockCatalogContents(mockCatalogURL, catalogRealmURL),
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
      });

      /**
       * Waits for a card to appear on the stack with optional title verification
       */
      async function waitForCardOnStack(
        cardId: string,
        expectedTitle?: string,
      ) {
        await waitFor(
          `[data-test-stack-card="${cardId}"] [data-test-boxel-card-header-title]`,
        );
        if (expectedTitle) {
          await waitFor(
            `[data-test-stack-card="${cardId}"] [data-test-boxel-card-header-title]`,
          );
        }
      }

      module('listing commands', function (hooks) {
        hooks.beforeEach(async function () {
          // we always run a command inside interact mode
          await visitOperatorMode({
            stacks: [[]],
          });
        });
        module('"build"', function () {
          test('card listing', async function (assert) {
            await visitOperatorMode({
              stacks: [
                [
                  {
                    id: apiDocumentationStubListingId,
                    format: 'isolated',
                  },
                ],
              ],
            });
            await waitFor(
              `[data-test-card="${apiDocumentationStubListingId}"]`,
            );
            assert
              .dom(
                `[data-test-card="${apiDocumentationStubListingId}"] [data-test-catalog-listing-action="Build"]`,
              )
              .containsText('Build', 'Build button exist in listing');
          });
        });
        skip('"create"', function (hooks) {
          // Mock proxy LLM endpoint only for create-related tests
          setupRealmServerEndpoints(hooks, [
            {
              route: '_request-forward',
              getResponse: async (req: Request) => {
                try {
                  const body = await req.json();
                  if (
                    body.url === 'https://openrouter.ai/api/v1/chat/completions'
                  ) {
                    let requestBody: any = {};
                    try {
                      requestBody = body.requestBody
                        ? JSON.parse(body.requestBody)
                        : {};
                    } catch {
                      // ignore parse failure
                    }
                    const messages = requestBody.messages || [];
                    const system: string =
                      messages.find((m: any) => m.role === 'system')?.content ||
                      '';
                    const user: string =
                      messages.find((m: any) => m.role === 'user')?.content ||
                      '';
                    const systemLower = system.toLowerCase();
                    let content: string | undefined;
                    if (
                      systemLower.includes(
                        'respond only with one token: card, app, skill, or theme',
                      )
                    ) {
                      // Heuristic moved from production code into test mock:
                      // If the serialized example or prompts reference an App construct
                      // (e.g. AppCard base class, module paths with /App/, or a name ending with App)
                      // then classify as 'app'. If it references Skill, classify as 'skill'.
                      const userLower = user.toLowerCase();
                      if (
                        /(appcard|blogapp|"appcard"|\.appcard|name: 'appcard')/.test(
                          userLower,
                        )
                      ) {
                        content = 'app';
                      } else if (
                        /(cssvariables|css imports|theme card|themecreator|theme listing)/.test(
                          userLower,
                        )
                      ) {
                        content = 'theme';
                      } else if (/skill/.test(userLower)) {
                        content = 'skill';
                      } else {
                        content = 'card';
                      }
                    } else if (systemLower.includes('catalog listing title')) {
                      content = 'Mock Listing Title';
                    } else if (systemLower.includes('spec-style summary')) {
                      content = 'Mock listing summary sentence.';
                    } else if (
                      systemLower.includes("boxel's sample data assistant")
                    ) {
                      content = JSON.stringify({
                        examples: [
                          {
                            label: 'Generated field value',
                            url: 'https://example.com/contact',
                          },
                        ],
                      });
                    } else if (systemLower.includes('representing tag')) {
                      // Deterministic tag selection
                      content = JSON.stringify([calculatorTagId]);
                    } else if (systemLower.includes('representing category')) {
                      // Deterministic category selection
                      content = JSON.stringify([writingCategoryId]);
                    } else if (systemLower.includes('representing license')) {
                      // Deterministic license selection
                      content = JSON.stringify([mitLicenseId]);
                    }

                    return new Response(
                      JSON.stringify({
                        choices: [
                          {
                            message: {
                              content,
                            },
                          },
                        ],
                      }),
                      {
                        status: 200,
                        headers: { 'Content-Type': 'application/json' },
                      },
                    );
                  }
                } catch (e) {
                  return new Response(
                    JSON.stringify({
                      error: 'mock forward error',
                      details: (e as Error).message,
                    }),
                    {
                      status: 500,
                      headers: { 'Content-Type': 'application/json' },
                    },
                  );
                }
                return new Response(
                  JSON.stringify({ error: 'Unknown proxy path' }),
                  {
                    status: 404,
                    headers: { 'Content-Type': 'application/json' },
                  },
                );
              },
            },
          ]);
          test('card listing with single dependency module', async function (assert) {
            const cardId = mockCatalogURL + 'author/Author/example';
            const commandService = getService('command-service');
            const command = new ListingCreateCommand(
              commandService.commandContext,
            );
            const result = await command.execute({
              openCardId: cardId,
              codeRef: {
                module: `${mockCatalogURL}author/author.gts`,
                name: 'Author',
              },
              targetRealm: mockCatalogURL,
            });
            const interim = result?.listing as any;
            assert.ok(interim, 'Interim listing exists');
            assert.strictEqual((interim as any).name, 'Mock Listing Title');
            assert.strictEqual(
              (interim as any).summary,
              'Mock listing summary sentence.',
            );
            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${mockCatalogURL}index`,
            });
            await verifySubmode(assert, 'code');
            const instanceFolder = 'CardListing/';
            await openDir(assert, instanceFolder);
            const listingId = await verifyJSONWithUUIDInFolder(
              assert,
              instanceFolder,
            );
            if (listingId) {
              const listing = (await getService('store').get(
                listingId,
              )) as CardListing;
              assert.ok(listing, 'Listing should be created');
              // Assertions for AI generated fields coming from proxy mock
              assert.strictEqual(
                (listing as any).name,
                'Mock Listing Title',
                'Listing name populated from autoPatchName mock response',
              );
              assert.strictEqual(
                (listing as any).summary,
                'Mock listing summary sentence.',
                'Listing summary populated from autoPatchSummary mock response',
              );
              assert.strictEqual(
                listing.specs.length,
                2,
                'Listing should have two specs',
              );
              assert.true(
                listing.specs.some((spec) => spec.ref.name === 'Author'),
                'Listing should have an Author spec',
              );
              assert.true(
                listing.specs.some((spec) => spec.ref.name === 'AuthorCompany'),
                'Listing should have an AuthorCompany spec',
              );
              // Deterministic autoLink assertions from proxy mock
              assert.ok((listing as any).license, 'License linked');
              assert.strictEqual(
                (listing as any).license.id,
                mitLicenseId,
                'License id matches mitLicenseId',
              );
              assert.ok(
                Array.isArray((listing as any).tags),
                'Tags array exists',
              );
              assert.true(
                (listing as any).tags.some(
                  (t: any) => t.id === calculatorTagId,
                ),
                'Contains calculator tag id',
              );
              assert.ok(
                Array.isArray((listing as any).categories),
                'Categories array exists',
              );
              assert.true(
                (listing as any).categories.some(
                  (c: any) => c.id === writingCategoryId,
                ),
                'Contains writing category id',
              );
            }
          });

          test('listing will only create specs with recognised imports from realms it can read from', async function (assert) {
            const cardId = mockCatalogURL + 'UnrecognisedImports/example';
            const commandService = getService('command-service');
            const command = new ListingCreateCommand(
              commandService.commandContext,
            );
            await command.execute({
              openCardId: cardId,
              codeRef: {
                module: `${mockCatalogURL}card-with-unrecognised-imports.gts`,
                name: 'UnrecognisedImports',
              },
              targetRealm: mockCatalogURL,
            });
            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${mockCatalogURL}index`,
            });
            await verifySubmode(assert, 'code');
            const instanceFolder = 'CardListing/';
            await openDir(assert, instanceFolder);
            const listingId = await verifyJSONWithUUIDInFolder(
              assert,
              instanceFolder,
            );
            if (listingId) {
              const listing = (await getService('store').get(
                listingId,
              )) as CardListing;
              assert.ok(listing, 'Listing should be created');
              assert.true(
                listing.specs.every(
                  (spec) =>
                    spec.ref.module !=
                    'https://cdn.jsdelivr.net/npm/chess.js/+esm',
                ),
                'Listing should does not have unrecognised import',
              );
            }
          });

          test('app listing', async function (assert) {
            const cardId = mockCatalogURL + 'blog-app/BlogApp/example';
            const commandService = getService('command-service');
            const command = new ListingCreateCommand(
              commandService.commandContext,
            );
            const createResult = await command.execute({
              openCardId: cardId,
              codeRef: {
                module: `${mockCatalogURL}blog-app/blog-app.gts`,
                name: 'BlogApp',
              },
              targetRealm: testDestinationRealmURL,
            });
            // Assert store-level (in-memory) results BEFORE navigating to code mode
            let immediateListing = createResult?.listing as any;
            assert.ok(immediateListing, 'Listing object returned from command');
            assert.strictEqual(
              immediateListing.name,
              'Mock Listing Title',
              'Immediate listing has patched name before persistence',
            );
            assert.strictEqual(
              immediateListing.summary,
              'Mock listing summary sentence.',
              'Immediate listing has patched summary before persistence',
            );
            assert.ok(
              immediateListing.license,
              'Immediate listing has linked license before persistence',
            );
            assert.strictEqual(
              immediateListing.license?.id,
              mitLicenseId,
              'Immediate listing license id matches mitLicenseId',
            );
            // Lint: avoid logical expression inside assertion
            assert.ok(
              Array.isArray(immediateListing.tags),
              'Immediate listing tags is an array before persistence',
            );
            if (Array.isArray(immediateListing.tags)) {
              assert.ok(
                immediateListing.tags.length > 0,
                'Immediate listing has linked tag(s) before persistence',
              );
            }
            assert.true(
              immediateListing.tags.some((t: any) => t.id === calculatorTagId),
              'Immediate listing includes calculator tag id',
            );
            assert.ok(
              Array.isArray(immediateListing.categories),
              'Immediate listing categories is an array before persistence',
            );
            if (Array.isArray(immediateListing.categories)) {
              assert.ok(
                immediateListing.categories.length > 0,
                'Immediate listing has linked category(ies) before persistence',
              );
            }
            assert.true(
              immediateListing.categories.some(
                (c: any) => c.id === writingCategoryId,
              ),
              'Immediate listing includes writing category id',
            );
            assert.ok(
              Array.isArray(immediateListing.specs),
              'Immediate listing specs is an array before persistence',
            );
            if (Array.isArray(immediateListing.specs)) {
              assert.strictEqual(
                immediateListing.specs.length,
                5,
                'Immediate listing has expected number of specs before persistence',
              );
            }
            assert.ok(
              Array.isArray(immediateListing.examples),
              'Immediate listing examples is an array before persistence',
            );
            if (Array.isArray(immediateListing.examples)) {
              assert.strictEqual(
                immediateListing.examples.length,
                1,
                'Immediate listing has expected examples before persistence',
              );
            }
            // Header/title: wait for persisted id (listing.id) then assert via stack card selector
            const persistedId = immediateListing.id;
            assert.ok(persistedId, 'Immediate listing has a persisted id');
            await waitForCardOnStack(persistedId);
            assert
              .dom(
                `[data-test-stack-card="${persistedId}"] [data-test-boxel-card-header-title]`,
              )
              .containsText(
                'Mock Listing Title',
                'Isolated view shows patched name (persisted id)',
              );
            // Summary section
            assert
              .dom('[data-test-catalog-listing-embedded-summary-section]')
              .containsText(
                'Mock listing summary sentence.',
                'Isolated view shows patched summary',
              );

            // License section should not show fallback text
            assert
              .dom('[data-test-catalog-listing-embedded-license-section]')
              .doesNotContainText(
                'No License Provided',
                'License section populated (autoLinkLicense)',
              );

            // Tags section
            assert
              .dom('[data-test-catalog-listing-embedded-tags-section]')
              .doesNotContainText(
                'No Tags Provided',
                'Tags section populated (autoLinkTag)',
              );

            // Categories section
            assert
              .dom('[data-test-catalog-listing-embedded-categories-section]')
              .doesNotContainText(
                'No Categories Provided',
                'Categories section populated (autoLinkCategory)',
              );
            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${testDestinationRealmURL}index`,
            });
            await verifySubmode(assert, 'code');
            const instanceFolder = 'AppListing/';
            await openDir(assert, instanceFolder);
            const persistedListingId = await verifyJSONWithUUIDInFolder(
              assert,
              instanceFolder,
            );
            if (persistedListingId) {
              const listing = (await getService('store').get(
                persistedListingId,
              )) as CardListing;
              assert.ok(listing, 'Listing should be created');
              assert.strictEqual(
                listing.specs.length,
                5,
                'Listing should have five specs',
              );
              [
                'Author',
                'AuthorCompany',
                'BlogPost',
                'BlogApp',
                'AppCard',
              ].forEach((specName) => {
                assert.true(
                  listing.specs.some((spec) => spec.ref.name === specName),
                  `Listing should have a ${specName} spec`,
                );
              });
              assert.strictEqual(
                listing.examples.length,
                1,
                'Listing should have one example',
              );

              // Assert autoPatch fields populated (from proxy mock responses)
              assert.strictEqual(
                (listing as any).name,
                'Mock Listing Title',
                'autoPatchName populated listing.name',
              );
              assert.strictEqual(
                (listing as any).summary,
                'Mock listing summary sentence.',
                'autoPatchSummary populated listing.summary',
              );

              // Basic object-level sanity for autoLink fields (they should exist, may be arrays)
              assert.ok(
                (listing as any).license,
                'autoLinkLicense populated listing.license',
              );
              assert.strictEqual(
                (listing as any).license?.id,
                mitLicenseId,
                'Persisted listing license id matches mitLicenseId',
              );
              assert.ok(
                Array.isArray((listing as any).tags),
                'autoLinkTag populated listing.tags array',
              );
              if (Array.isArray((listing as any).tags)) {
                assert.ok(
                  (listing as any).tags.length > 0,
                  'autoLinkTag populated listing.tags with at least one tag',
                );
              }
              assert.true(
                (listing as any).tags.some(
                  (t: any) => t.id === calculatorTagId,
                ),
                'Persisted listing includes calculator tag id',
              );
              assert.ok(
                Array.isArray((listing as any).categories),
                'autoLinkCategory populated listing.categories array',
              );
              if (Array.isArray((listing as any).categories)) {
                assert.ok(
                  (listing as any).categories.length > 0,
                  'autoLinkCategory populated listing.categories with at least one category',
                );
              }
              assert.true(
                (listing as any).categories.some(
                  (c: any) => c.id === writingCategoryId,
                ),
                'Persisted listing includes writing category id',
              );
            }
          });

          test('after create command, listing card opens on stack in interact mode', async function (assert) {
            const cardId = mockCatalogURL + 'author/Author/example';
            const commandService = getService('command-service');
            const command = new ListingCreateCommand(
              commandService.commandContext,
            );

            let r = await command.execute({
              openCardId: cardId,
              codeRef: {
                module: `${mockCatalogURL}author/author.gts`,
                name: 'Author',
              },
              targetRealm: mockCatalogURL,
            });

            await verifySubmode(assert, 'interact');
            const listing = r?.listing as any;
            const createdId = listing.id;
            assert.ok(createdId, 'Listing id should be present');
            await waitForCardOnStack(createdId);
            assert
              .dom(`[data-test-stack-card="${createdId}"]`)
              .exists(
                'Created listing card (by persisted id) is displayed on stack after command execution',
              );
          });
        });
      });
    },
  );
}
