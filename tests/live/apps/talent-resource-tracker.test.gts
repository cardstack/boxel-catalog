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
const realmURL = 'http://test-realm/talent-resource-tracker/';
const appModule = `${catalogRealmURL}cards/talent-resource-tracker/talent-resource-tracker`;
const hr = `${catalogRealmURL}cards/hr/`;

function card(module: string, name: string, attributes: object) {
  return {
    data: {
      type: 'card',
      attributes,
      meta: { adoptsFrom: { module, name } },
    },
  };
}

function app() {
  return card(appModule, 'TalentResourceTracker', {
    name: 'Talent & Resource Tracker',
    cardInfo: { name: 'Talent & Resource Tracker' },
  });
}

function trackerText(): string {
  return document.querySelector('section.tracker')?.textContent ?? '';
}

export function runTests() {
  module(
    'Acceptance | Catalog | apps - talent resource tracker',
    function (hooks) {
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
            [
              {
                id: `${realmURL}TalentResourceTracker/main`,
                format: 'isolated',
              },
            ],
          ],
        });
        await waitUntil(
          () => Boolean(document.querySelector('section.tracker')),
          { timeout: 30000 },
        );
      }

      test('it lists the sample positions and people', async function (assert) {
        await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'TalentResourceTracker/main.json': app(),
            'Position/example-engineer.json': card(
              `${hr}position`,
              'Position',
              {
                jobTitle: 'Example Engineer',
                department: 'Engineering',
                status: 'open',
                headcount: 1,
              },
            ),
            'Employee/example-person.json': card(`${hr}employee`, 'Employee', {
              name: 'Example Person',
              department: 'Engineering',
              status: 'active',
            }),
          },
        });
        await open();
        await waitUntil(() => trackerText().includes('Example Engineer'), {
          timeout: 30000,
        });

        assert.ok(
          trackerText().includes('Example Engineer'),
          'the open position is listed in the rail',
        );
        assert.ok(
          trackerText().includes('Personnel Registry'),
          'the rail renders',
        );
      });

      test('it renders an empty realm once its queries load', async function (assert) {
        await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'TalentResourceTracker/main.json': app(),
          },
        });
        await open();
        await waitUntil(
          () =>
            [...document.querySelectorAll('section.tracker .empty-note')].some(
              (el) => el.textContent?.trim() === 'No teams yet',
            ),
          { timeout: 30000 },
        );

        let notes = [
          ...document.querySelectorAll('section.tracker .empty-note'),
        ].map((el) => el.textContent?.trim());
        assert.ok(
          notes.includes('No teams yet'),
          'teams show their empty state',
        );
        assert.ok(
          notes.includes('No projects yet'),
          'projects show their empty state',
        );
        assert.notOk(notes.includes('Loading…'), 'no query is still loading');
        let byline = (
          document.querySelector('section.tracker .byline')?.textContent ?? ''
        ).replace(/\s+/g, ' ');
        assert.ok(
          /\b0 people\b/.test(byline),
          'the headcount reads 0 once loaded, not a dash',
        );
      });
    },
  );
}
