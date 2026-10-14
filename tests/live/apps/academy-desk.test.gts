import { click, waitUntil } from '@ember/test-helpers';
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
const realmURL = 'http://test-realm/academy-desk/';
const appModule = `${catalogRealmURL}cards/academy-desk/academy-desk`;
const courseModule = `${catalogRealmURL}cards/academy/course`;

function desk() {
  return {
    data: {
      type: 'card',
      attributes: {
        title: 'Test Academy Desk',
        tagline: 'Course & cohort learning',
      },
      meta: { adoptsFrom: { module: appModule, name: 'AcademyDesk' } },
    },
  };
}

function course(code: string, title: string) {
  return {
    data: {
      type: 'card',
      attributes: { code, title, status: 'published', creditHours: 3 },
      meta: { adoptsFrom: { module: courseModule, name: 'Course' } },
    },
  };
}

function deskText(): string {
  return document.querySelector('.desk')?.textContent ?? '';
}

function tab(label: string): Element | undefined {
  return [...document.querySelectorAll('.desk [role="tab"]')].find(
    (el) => el.textContent?.trim() === label,
  );
}

export function runTests() {
  module('Acceptance | Catalog | apps - academy desk', function (hooks) {
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

    async function openCourses() {
      await visitOperatorMode({
        stacks: [[{ id: `${realmURL}AcademyDesk/main`, format: 'isolated' }]],
      });
      await waitUntil(() => Boolean(tab('Courses')), { timeout: 30000 });
      await click(tab('Courses')!);
    }

    test('it lists the sample course on the Courses tab', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'AcademyDesk/main.json': desk(),
          'Course/paf-101.json': course(
            'PAF-101',
            'Product Analytics Foundations',
          ),
        },
      });
      await openCourses();
      await waitUntil(
        () => deskText().includes('Product Analytics Foundations'),
        { timeout: 30000 },
      );

      assert.ok(
        deskText().includes('Test Academy Desk'),
        'the desk shows its title',
      );
      assert.ok(
        deskText().includes('PAF-101'),
        'the course row shows its code',
      );
    });

    test('it shows an empty Courses tab on an empty realm', async function (assert) {
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'AcademyDesk/main.json': desk(),
        },
      });
      await openCourses();
      await waitUntil(() => deskText().includes('No courses yet.'), {
        timeout: 30000,
      });

      assert.ok(true, 'the Courses tab says there are no courses');
    });
  });
}
