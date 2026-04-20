import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import { ensureTrailingSlash } from '@cardstack/runtime-common';

import ListingInstallCommand from '@cardstack/boxel-host/commands/listing-install';

import ENV from '@cardstack/host/config/environment';

import type { CardDef } from 'https://cardstack.com/base/card-api';

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
  makeDestinationRealmContents,
} from './catalog-app-test-fixtures';

const catalogRealmURL = ensureTrailingSlash(ENV.resolvedCatalogRealmURL!);
const testDestinationRealmURL = `http://test-realm/test2/`;

//listing
const authorListingId = `${mockCatalogURL}Listing/author`;
const blogPostListingId = `${mockCatalogURL}Listing/blog-post`;

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
        const commandService = getService('command-service');
        const store = getService('store');

        const command = new commandClass(commandService.commandContext);
        const listing = (await store.get(listingUrl)) as CardDef;

        return command.execute({
          realm,
          listing,
        });
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

            await executeCommand(
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
            await openDir(assert, `${outerFolder}fields/contact-link.gts`);
            let gtsFilePath = `${outerFolder}fields/contact-link.gts`;
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
