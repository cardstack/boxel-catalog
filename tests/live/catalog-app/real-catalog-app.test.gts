import { visit, waitFor, waitUntil } from '@ember/test-helpers';

import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import {
  setupLocalIndexing,
  setupAuthEndpoints,
  setupUserSubscription,
  setCatalogRealmURL,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

// The test file is served from the catalog realm, so its own URL tells us
// where the realm is without needing an env var. This file lives in the
// catalog-app/ subdirectory, so we go up one level to reach the realm root.
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const CATALOG_READINESS_URL = `${catalogRealmURL}_readiness-check?acceptHeader=application%2Fvnd.api%2Bjson`;

// Force host mode on the real service instance rather than registering a
// stub class: the index route leans on the rest of its interface (routing
// map, head template, …), which must keep working.
function forceHostMode() {
  let hostModeService = getService('host-mode-service');
  Object.defineProperty(hostModeService, 'isActive', {
    get: () => true,
    configurable: true,
  });
  Object.defineProperty(hostModeService, 'hostModeOrigin', {
    get: () => new URL(catalogRealmURL).origin,
    configurable: true,
  });
}

export function runTests() {
  module('Acceptance | Catalog | real catalog app', function (hooks) {
    setupApplicationTest(hooks);
    setupLocalIndexing(hooks);

    // Unlike the other suites this one renders the REAL catalog realm the
    // live-test run serves, not a mock — the login is mocked, the content
    // is not. That makes it the smoke test for the shipped catalog: a
    // broken index card or module in real content fails here and nowhere
    // else.
    setupMockMatrix(hooks, {
      loggedInAs: '@testuser:localhost',
      activeRealms: [],
    });

    hooks.beforeEach(function () {
      setupUserSubscription();
      setupAuthEndpoints();
      setCatalogRealmURL(catalogRealmURL);
      forceHostMode();
    });

    test('visiting /catalog/ renders the catalog index card', async function (assert) {
      let realmServer = getService('realm-server');
      await realmServer.ready;
      await ensureCatalogRealmReady();

      await visit('/catalog/');

      await waitFor('[data-test-catalog-app]', { timeout: 30_000 });
      assert.dom('[data-test-card-error]').doesNotExist();
      assert.dom('[data-test-catalog-app]').exists();
    });
  });
}

async function ensureCatalogRealmReady() {
  let network = getService('network');
  await waitUntil(
    async () => {
      try {
        let response = await network.fetch(CATALOG_READINESS_URL);
        return response.ok;
      } catch (e) {
        return false;
      }
    },
    {
      timeout: 30_000,
      timeoutMessage: `Timed out waiting for catalog realm readiness at ${CATALOG_READINESS_URL}`,
    },
  );
}
