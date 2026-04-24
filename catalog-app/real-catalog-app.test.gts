import { getOwner } from '@ember/owner';
import Service from '@ember/service';
import { visit, waitFor, waitUntil } from '@ember/test-helpers';

import { getService } from '@universal-ember/test-support';
import { module, skip } from 'qunit';

import { setupLocalIndexing } from '@cardstack/host/tests/helpers';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

// The test file is served from the catalog realm, so its own URL tells us
// where the realm is without needing an env var. This file lives in the
// catalog-app/ subdirectory, so we go up one level to reach the realm root.
// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../', import.meta.url).href;
const CATALOG_READINESS_URL = `${catalogRealmURL}_readiness-check?acceptHeader=application%2Fvnd.api%2Bjson`;

class StubHostModeService extends Service {
  get isActive() {
    return true;
  }

  get hostModeOrigin() {
    return 'http://localhost:4201';
  }
}

export function runTests() {
  module('Acceptance | Catalog | real catalog app', function (hooks) {
    setupApplicationTest(hooks);
    setupLocalIndexing(hooks);

    hooks.beforeEach(function () {
      getOwner(this)!.register('service:host-mode-service', StubHostModeService);
    });

    // CS-9919 - Skipping this test for now as the catalog realm is now setup only in
    // part for speed in host tests.
    skip('visiting /catalog/ renders the catalog index card', async function (assert) {
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
