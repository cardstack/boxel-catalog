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
const realmURL = 'http://test-realm/club-membership/';
const clubModule = `${catalogRealmURL}cards/club-membership/club-membership`;
const memberModule = `${catalogRealmURL}cards/club-membership/member`;
const matchModule = `${catalogRealmURL}cards/club-membership/match`;

function club() {
  return {
    data: {
      type: 'card',
      attributes: { clubName: 'Example FC' },
      meta: { adoptsFrom: { module: clubModule, name: 'ClubMembership' } },
    },
  };
}

function member(memberNumber: string, tier: string, pointsBalance: number) {
  return {
    data: {
      type: 'card',
      attributes: { memberNumber, tier, status: 'Active', pointsBalance },
      meta: { adoptsFrom: { module: memberModule, name: 'Member' } },
    },
  };
}

function match(opponent: string) {
  return {
    data: {
      type: 'card',
      attributes: {
        opponent,
        homeAway: 'Home',
        competition: 'League',
        kind: 'Match',
        status: 'Scheduled',
        startsAt: '2099-09-12T14:00:00.000Z',
        ticketsSold: 100,
        capacity: { total: 1000, unit: 'seats', allocations: [] },
      },
      meta: { adoptsFrom: { module: matchModule, name: 'Match' } },
    },
  };
}

function clubText(): string {
  return document.querySelector('.club')?.textContent ?? '';
}

export function runTests() {
  module('Acceptance | Catalog | apps - club membership', function (hooks) {
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
          [{ id: `${realmURL}ClubMembership/main`, format: 'isolated' }],
        ],
      });
      await waitUntil(() => Boolean(document.querySelector('.club')), {
        timeout: 30000,
      });
    }

    test('it opens the dashboard on the sample season', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ClubMembership/main.json': club(),
          'Member/gold.json': member('TEST-0001', 'Gold', 1200),
          'Member/silver.json': member('TEST-0002', 'Silver', 300),
          'Match/riverton.json': match('Riverton Rovers'),
        },
      });
      await open();
      await waitUntil(() => clubText().includes('v Riverton Rovers'), {
        timeout: 30000,
      });

      assert.ok(
        clubText().includes('Example FC'),
        'the masthead names the club',
      );
      assert.ok(
        clubText().includes('Membership by tier'),
        'the dashboard shows the tier breakdown',
      );
      assert.ok(
        clubText().includes('Next fixture'),
        'the dashboard leads with the next fixture',
      );
    });

    test('it renders an empty realm without a next fixture', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'ClubMembership/main.json': club(),
        },
      });
      await open();
      await waitUntil(() => clubText().includes('No upcoming fixture'), {
        timeout: 30000,
      });

      assert.ok(
        clubText().includes('Schedule the next match to open bookings.'),
        'the empty dashboard says what to do next',
      );
    });
  });
}
