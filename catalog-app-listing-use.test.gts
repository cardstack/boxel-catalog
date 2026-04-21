import { getService } from '@universal-ember/test-support';
import { module, skip } from 'qunit';

import { ensureTrailingSlash } from '@cardstack/runtime-common';

import ListingUseCommand from '@cardstack/boxel-host/commands/listing-use';

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
  verifyJSONWithUUIDInFolder,
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

export function runTests() {
  module(
    'Acceptance | Catalog | catalog app - listing use',
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
        commandClass: typeof ListingUseCommand,
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
        skip('"use"', async function () {
          skip('card listing', async function (assert) {
            const listingName = 'author';
            const listingId = mockCatalogURL + 'Listing/author.json';
            await executeCommand(
              ListingUseCommand,
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

            let instanceFolder = `${outerFolder}Author/`;
            await openDir(assert, instanceFolder);
            await verifyJSONWithUUIDInFolder(assert, instanceFolder);
          });
        });

        skip('"use" is successful even if target realm does not have a trailing slash', async function (assert) {
          const listingName = 'author';
          const listingId = mockCatalogURL + 'Listing/author.json';
          await executeCommand(
            ListingUseCommand,
            listingId,
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

          let instanceFolder = `${outerFolder}Author`;
          await openDir(assert, instanceFolder);
          await verifyJSONWithUUIDInFolder(assert, instanceFolder);
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
