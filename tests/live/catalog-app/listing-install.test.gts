import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import {
  identifyCard,
  isResolvedCodeRef,
  rri,
} from '@cardstack/runtime-common';

import ListingInstallCommand from '../../../commands/listing-install';

import {
  getRelationshipMembershipState,
  type CardDef,
} from '@cardstack/base/card-api';

import {
  setupLocalIndexing,
  setupOnSave,
  testRealmURL as mockCatalogURL,
  setupAuthEndpoints,
  setupUserSubscription,
  setupAcceptanceTestRealm,
  SYSTEM_CARD_FIXTURE_CONTENTS,
  visitOperatorMode,
  openDir,
  verifyFolderWithUUIDInFileTree,
  verifyFileInFileTree,
  setCatalogRealmURL,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

import {
  makeMockCatalogContents,
  makeLinkEdgeCaseListingContents,
  makeDestinationRealmContents,
} from '../../helpers/test-fixtures';

// The test file is served from the catalog realm, so its own URL tells us
// where the realm is without needing an env var.
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const testDestinationRealmURL = `http://test-realm/test2/`;

//listing
const authorListingId = `${mockCatalogURL}Listing/author`;
const blogPostListingId = `${mockCatalogURL}Listing/blog-post`;
const photoPostListingId = `${mockCatalogURL}Listing/photo-post`;
const brokenSpecListingId = `${mockCatalogURL}Listing/broken-spec`;
const baseSpecOnlyListingId = `${mockCatalogURL}Listing/base-spec-only`;

export function runTests() {
  module(
    'Acceptance | Catalog | catalog app - listing install',
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
            ...makeLinkEdgeCaseListingContents(mockCatalogURL, catalogRealmURL),
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

      async function executeCommand(
        commandClass: typeof ListingInstallCommand,
        listingUrl: string,
        realm: string,
      ) {
        const commandService = getService('tool-service');
        const store = getService('store');

        const command = new commandClass(commandService.commandContext);
        const listing = (await store.get(listingUrl)) as CardDef;

        return command.execute({
          realm,
          listing,
        });
      }

      // Build the input the way an AI tool call does: the listing arrives as a
      // bare link on a freshly added input card, so the command has to load it.
      async function executeCommandFromToolCall(
        listingUrl: string,
        realm: string,
      ) {
        const commandService = getService('tool-service');
        const store = getService('store');

        const command = new ListingInstallCommand(
          commandService.commandContext,
        );
        const InputType = await command.getInputType();
        const input = await store.addWithoutPersisting({
          data: {
            type: 'card',
            meta: { adoptsFrom: identifyCard(InputType)! },
            attributes: { realm },
            relationships: { listing: { links: { self: listingUrl } } },
          },
        });

        return command.execute(input as any);
      }

      module('listing commands', function (hooks) {
        hooks.beforeEach(async function () {
          // we always run a command inside interact mode
          await visitOperatorMode({
            stacks: [[]],
          });
        });
        module('"install"', function () {
          test('card listing', async function (assert) {
            const listingName = 'author';

            let result = await executeCommand(
              ListingInstallCommand,
              authorListingId,
              testDestinationRealmURL,
            );
            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${testDestinationRealmURL}index`,
            });

            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let gtsFilePath = `${outerFolder}${listingName}/author.gts`;
            await openDir(assert, gtsFilePath);
            await verifyFileInFileTree(assert, gtsFilePath);
            let examplePath = `${outerFolder}${listingName}/Author/example.json`;
            await openDir(assert, examplePath);
            await verifyFileInFileTree(assert, examplePath);

            // Author/example.json's own adoptsFrom is an absolute URL into the
            // catalog realm (see makeMockCatalogContents), so this catches the
            // install pipeline leaving the copied instance pointed at the
            // source realm instead of rewriting it into the newly installed
            // module.
            let store = getService('store');
            let installedCard = (await store.get(
              result.exampleCardId as string,
            )) as CardDef;
            let installedRef = identifyCard(installedCard.constructor);
            if (!installedRef || !isResolvedCodeRef(installedRef)) {
              throw new Error('expected a resolved code ref');
            }
            assert.ok(
              installedRef.module.startsWith(testDestinationRealmURL),
              `installed card module "${installedRef.module}" resolves into the destination realm`,
            );
            assert.false(
              installedRef.module.startsWith(mockCatalogURL),
              `installed card module "${installedRef.module}" should not still point at the catalog realm`,
            );
          });

          test('listing installs relationships of examples and its modules', async function (assert) {
            const listingName = 'blog-post';

            await executeCommand(
              ListingInstallCommand,
              blogPostListingId,
              testDestinationRealmURL,
            );
            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${testDestinationRealmURL}index`,
            });

            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let blogPostModulePath = `${outerFolder}blog-post/blog-post.gts`;
            let authorModulePath = `${outerFolder}author/author.gts`;
            await openDir(assert, blogPostModulePath);
            await verifyFileInFileTree(assert, blogPostModulePath);
            await openDir(assert, authorModulePath);
            await verifyFileInFileTree(assert, authorModulePath);

            let blogPostExamplePath = `${outerFolder}blog-post/BlogPost/example.json`;
            let authorExamplePath = `${outerFolder}author/Author/example.json`;
            let authorCompanyExamplePath = `${outerFolder}author/AuthorCompany/example.json`;
            await openDir(assert, blogPostExamplePath);
            await verifyFileInFileTree(assert, blogPostExamplePath);
            await openDir(assert, authorExamplePath);
            await verifyFileInFileTree(assert, authorExamplePath);
            await openDir(assert, authorCompanyExamplePath);
            await verifyFileInFileTree(assert, authorCompanyExamplePath);
          });

          test('listing installs binary files linked from examples', async function (assert) {
            const listingName = 'photo-post';

            await executeCommand(
              ListingInstallCommand,
              photoPostListingId,
              testDestinationRealmURL,
            );
            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${testDestinationRealmURL}index`,
            });

            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let examplePath = `${outerFolder}photo-post/PhotoPost/example.json`;
            await openDir(assert, examplePath);
            await verifyFileInFileTree(assert, examplePath);
            let photoPath = `${outerFolder}photo-post/photo.png`;
            await openDir(assert, photoPath);
            await verifyFileInFileTree(assert, photoPath);
          });

          test('field listing', async function (assert) {
            const listingName = 'contact-link';
            const contactLinkFieldListingCardId = `${mockCatalogURL}FieldListing/contact-link`;

            await executeCommand(
              ListingInstallCommand,
              contactLinkFieldListingCardId,
              testDestinationRealmURL,
            );

            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${testDestinationRealmURL}index`,
            });

            // contact-link-[uuid]/
            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            await openDir(
              assert,
              `${outerFolder}fields/contact-link/contact-link.gts`,
            );
            let gtsFilePath = `${outerFolder}fields/contact-link/contact-link.gts`;
            await verifyFileInFileTree(assert, gtsFilePath);
          });

          test('skill listing', async function (assert) {
            const listingName = 'pirate-skill';
            const listingId = `${mockCatalogURL}SkillListing/${listingName}`;
            await executeCommand(
              ListingInstallCommand,
              listingId,
              testDestinationRealmURL,
            );
            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${testDestinationRealmURL}index`,
            });

            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let instancePath = `${outerFolder}Skill/pirate-speak.json`;
            await openDir(assert, instancePath);
            await verifyFileInFileTree(assert, instancePath);
          });
        });

        module('linked cards', function () {
          test('a listing from a tool call installs once it loads', async function (assert) {
            const listingName = 'author';

            let result = await executeCommandFromToolCall(
              authorListingId,
              testDestinationRealmURL,
            );
            assert.ok(result.exampleCardId, 'the example card is installed');

            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${testDestinationRealmURL}index`,
            });
            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let gtsFilePath = `${outerFolder}${listingName}/author.gts`;
            await openDir(assert, gtsFilePath);
            await verifyFileInFileTree(assert, gtsFilePath);
          });

          test('a listing whose spec and example links have not loaded installs once they load', async function (assert) {
            const listingName = 'author';
            const commandService = getService('tool-service');
            const store = getService('store');

            // A document without `included` leaves every link unloaded, which
            // is the state that crashed the planner on `undefined` entries.
            let listing = (await store.addWithoutPersisting({
              data: {
                type: 'card',
                attributes: { name: 'Author', cardTitle: 'Author' },
                relationships: {
                  'specs.0': {
                    links: { self: `${mockCatalogURL}Spec/author` },
                  },
                  'examples.0': {
                    links: { self: `${mockCatalogURL}author/Author/example` },
                  },
                },
                meta: {
                  adoptsFrom: {
                    module: rri(
                      `${catalogRealmURL}catalog-app/listing/listing`,
                    ),
                    name: 'CardListing',
                  },
                  // A listing served by a realm carries its realm, which the
                  // install planner needs to place the copied files.
                  realmURL: mockCatalogURL,
                },
              },
            })) as CardDef;
            for (let fieldName of ['specs', 'examples']) {
              assert.deepEqual(
                getRelationshipMembershipState(
                  listing,
                  fieldName,
                ).membership?.map((slot) => slot.kind),
                ['not-loaded'],
                `${fieldName} starts out not loaded`,
              );
            }

            let result = await new ListingInstallCommand(
              commandService.commandContext,
            ).execute({ realm: testDestinationRealmURL, listing });
            assert.ok(result.exampleCardId, 'the example card is installed');
            assert.ok(result.selectedCodeRef, 'a code ref is selected');

            await visitOperatorMode({
              submode: 'code',
              fileView: 'browser',
              codePath: `${testDestinationRealmURL}index`,
            });
            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let gtsFilePath = `${outerFolder}${listingName}/author.gts`;
            await openDir(assert, gtsFilePath);
            await verifyFileInFileTree(assert, gtsFilePath);
            let examplePath = `${outerFolder}${listingName}/Author/example.json`;
            await openDir(assert, examplePath);
            await verifyFileInFileTree(assert, examplePath);
          });

          test('a tool call naming a missing listing fails with an error naming it', async function (assert) {
            const missingListingId = `${mockCatalogURL}Listing/does-not-exist`;
            await assert.rejects(
              executeCommandFromToolCall(
                missingListingId,
                testDestinationRealmURL,
              ),
              (e: Error) =>
                !(e instanceof TypeError) &&
                e.message.includes(`Listing "${missingListingId}"`),
              'the error names the listing, not a TypeError',
            );
          });

          test('a broken spec link fails with an error naming the spec', async function (assert) {
            await assert.rejects(
              executeCommandFromToolCall(
                brokenSpecListingId,
                testDestinationRealmURL,
              ),
              (e: Error) =>
                !(e instanceof TypeError) &&
                e.message.includes(
                  `Listing spec "${mockCatalogURL}Spec/does-not-exist"`,
                ) &&
                e.message.includes('Update Specs'),
              'the error names the broken spec and how to fix it, not a TypeError',
            );
          });

          test('a listing whose only spec is a base-realm def installs without a code ref', async function (assert) {
            let result = await executeCommand(
              ListingInstallCommand,
              baseSpecOnlyListingId,
              testDestinationRealmURL,
            );
            assert.strictEqual(
              result.selectedCodeRef,
              undefined,
              'no module was copied, so there is no code ref to select',
            );
          });
        });

        test('"install" is successful even if target realm does not have a trailing slash', async function (assert) {
          const listingName = 'author';
          await executeCommand(
            ListingInstallCommand,
            authorListingId,
            removeTrailingSlash(testDestinationRealmURL),
          );
          await visitOperatorMode({
            submode: 'code',
            fileView: 'browser',
            codePath: `${testDestinationRealmURL}index`,
          });

          let outerFolder = await verifyFolderWithUUIDInFileTree(
            assert,
            listingName,
          );

          let gtsFilePath = `${outerFolder}${listingName}/author.gts`;
          await openDir(assert, gtsFilePath);
          await verifyFileInFileTree(assert, gtsFilePath);
          let instancePath = `${outerFolder}${listingName}/Author/example.json`;

          await openDir(assert, instancePath);
          await verifyFileInFileTree(assert, instancePath);
        });
      });
    },
  );
}

function removeTrailingSlash(url: string): string {
  if (url === undefined || url === null) {
    throw new Error(`removeTrailingSlash called with invalid url: ${url}`);
  }
  return url.endsWith('/') && url.length > 1 ? url.slice(0, -1) : url;
}
