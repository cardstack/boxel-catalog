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
const realmURL = 'http://test-realm/vendor-onboarding/';
const appModule = `${catalogRealmURL}cards/vendor-onboarding/vendor-onboarding-app`;
const profileModule = `${catalogRealmURL}cards/procurement/vendor-profile`;

function app() {
  return {
    data: {
      type: 'card',
      attributes: { cardInfo: { name: 'Vendor Onboarding' } },
      meta: { adoptsFrom: { module: appModule, name: 'VendorOnboardingApp' } },
    },
  };
}

function profile(companyName: string, status: string) {
  return {
    data: {
      type: 'card',
      attributes: {
        companyName,
        status,
        insuranceExpiry: '2099-01-01',
        certifications: [],
      },
      meta: { adoptsFrom: { module: profileModule, name: 'VendorProfile' } },
    },
  };
}

function appText(): string {
  return document.querySelector('article.app')?.textContent ?? '';
}

export function runTests() {
  module('Acceptance | Catalog | apps - vendor onboarding', function (hooks) {
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
          [{ id: `${realmURL}VendorOnboardingApp/main`, format: 'isolated' }],
        ],
      });
      await waitUntil(() => Boolean(document.querySelector('article.app')), {
        timeout: 30000,
      });
    }

    test('it lays the sample profiles out on the vetting pipeline', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'VendorOnboardingApp/main.json': app(),
          'VendorProfile/helio.json': profile('Helio Freight', 'intake'),
          'VendorProfile/acme.json': profile('Acme Supply', 'onboarded'),
        },
      });
      await open();
      await waitUntil(() => appText().includes('Helio Freight'), {
        timeout: 30000,
      });

      assert.ok(
        appText().includes('Acme Supply'),
        'both profiles are on the board',
      );
      assert.strictEqual(
        document.querySelector('article.app .count-big')?.textContent?.trim(),
        '2',
        'the masthead counts the profiles',
      );
      assert.ok(
        appText().includes('1 profile waiting on your review'),
        'the masthead names what is waiting on the buyer',
      );
    });

    test('it renders an empty realm with a prompt to add a profile', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'VendorOnboardingApp/main.json': app(),
        },
      });
      await open();
      await waitUntil(() => appText().includes('No vendor profiles yet'), {
        timeout: 30000,
      });

      assert.strictEqual(
        document.querySelector('article.app .count-big')?.textContent?.trim(),
        '0',
        'the masthead counts no profiles',
      );
    });
  });
}
