import { waitFor, settled } from '@ember/test-helpers';

import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import ListingRemixCommand from '@cardstack/boxel-host/commands/listing-remix';

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
  verifySubmode,
  toggleFileTree,
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

// The test file is served from the catalog realm, so its own URL tells us
// where the realm is without needing an env var.
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('./', import.meta.url).href;
const testDestinationRealmURL = `http://test-realm/test2/`;

//listing
const themeListingId = `${mockCatalogURL}ThemeListing/cardstack-theme`;

export function runTests() {
  module(
    'Acceptance | Catalog | catalog app - listing remix',
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
        commandClass: typeof ListingRemixCommand,
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
        module('"remix"', function () {
          test('card listing: installs the card and redirects to code mode with persisted playground selection for first example successfully', async function (assert) {
            const listingName = 'author';
            const listingId = `${mockCatalogURL}Listing/${listingName}`;
            await visitOperatorMode({
              stacks: [[]],
            });
            await executeCommand(
              ListingRemixCommand,
              listingId,
              testDestinationRealmURL,
            );
            await settled();
            await verifySubmode(assert, 'code');
            await toggleFileTree();
            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let instanceFile = `${outerFolder}${listingName}/Author/example.json`;
            await openDir(assert, instanceFile);
            await verifyFileInFileTree(assert, instanceFile);
            let gtsFilePath = `${outerFolder}${listingName}/author.gts`;
            await openDir(assert, gtsFilePath);
            await verifyFileInFileTree(assert, gtsFilePath);
            await settled();
            assert
              .dom(
                '[data-test-playground-panel] [data-test-boxel-card-header-title]',
              )
              .hasText('Author - Mike Dane');
          });
          test('skill listing: installs the card and redirects to code mode with preview on first skill successfully', async function (assert) {
            const listingName = 'pirate-skill';
            const listingId = `${mockCatalogURL}SkillListing/${listingName}`;
            await executeCommand(
              ListingRemixCommand,
              listingId,
              testDestinationRealmURL,
            );
            await settled();
            await verifySubmode(assert, 'code');
            await toggleFileTree();
            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let instancePath = `${outerFolder}Skill/pirate-speak.json`;
            await openDir(assert, instancePath);
            await verifyFileInFileTree(assert, instancePath);
            let cardId =
              testDestinationRealmURL + instancePath.replace('.json', '');
            await waitFor('[data-test-card-resource-loaded]');
            assert
              .dom(`[data-test-code-mode-card-renderer-header="${cardId}"]`)
              .exists();
          });
          test('theme listing: installs the theme example and redirects to code mode successfully', async function (assert) {
            const listingName = 'cardstack-theme';
            await executeCommand(
              ListingRemixCommand,
              themeListingId,
              testDestinationRealmURL,
            );
            await settled();
            await verifySubmode(assert, 'code');
            await toggleFileTree();
            let outerFolder = await verifyFolderWithUUIDInFileTree(
              assert,
              listingName,
            );
            let instancePath = `${outerFolder}theme/theme-example.json`;
            await openDir(assert, instancePath);
            await verifyFileInFileTree(assert, instancePath);
            let cardId =
              testDestinationRealmURL + instancePath.replace('.json', '');
            await waitFor('[data-test-card-resource-loaded]');
            assert
              .dom(`[data-test-code-mode-card-renderer-header="${cardId}"]`)
              .exists();
          });
        });

        test('"remix" is successful even if target realm does not have a trailing slash', async function (assert) {
          const listingName = 'author';
          const listingId = `${mockCatalogURL}Listing/${listingName}`;
          await visitOperatorMode({
            stacks: [[]],
          });
          await executeCommand(
            ListingRemixCommand,
            listingId,
            removeTrailingSlash(testDestinationRealmURL),
          );
          await settled();
          await verifySubmode(assert, 'code');
          await toggleFileTree();
          let outerFolder = await verifyFolderWithUUIDInFileTree(
            assert,
            listingName,
          );
          let instancePath = `${outerFolder}${listingName}/Author/example.json`;
          await openDir(assert, instancePath);
          await verifyFileInFileTree(assert, instancePath);
          let gtsFilePath = `${outerFolder}${listingName}/author.gts`;
          await openDir(assert, gtsFilePath);
          await verifyFileInFileTree(assert, gtsFilePath);
          await settled();
          assert
            .dom(
              '[data-test-playground-panel] [data-test-boxel-card-header-title]',
            )
            .hasText('Author - Mike Dane');
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
