import { getService } from '@universal-ember/test-support';
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

import type PublishCourseCommand from '../../../cards/academy/commands/publish-course-command';
import type { Course } from '../../../cards/academy/course';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/academy/';
const academy = `${catalogRealmURL}cards/academy/`;

const RULE = { minAttendancePct: 70 };

function instance(
  module: string,
  name: string,
  attributes: Record<string, unknown> = {},
  relationships: Record<string, unknown> = {},
) {
  return {
    data: {
      type: 'card',
      attributes,
      relationships,
      meta: { adoptsFrom: { module: `${academy}${module}`, name } },
    },
  };
}

function links(field: string, ids: string[]) {
  return Object.fromEntries(
    ids.map((id, i) => [
      `${field}.${i}`,
      { links: { self: `${realmURL}${id}` } },
    ]),
  );
}

function course(
  title: string,
  moduleIds: string[],
  completionRule: Record<string, unknown> | null = RULE,
) {
  return instance(
    'course',
    'Course',
    { title, status: 'draft', completionRule },
    links('modules', moduleIds),
  );
}

export function runTests() {
  module('Acceptance | Catalog | academy - publish course', function (hooks) {
    setupApplicationTest(hooks);
    setupLocalIndexing(hooks);
    setupOnSave(hooks);

    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: '@testuser:localhost',
      activeRealms: [realmURL],
    });

    hooks.beforeEach(async function () {
      mockMatrixUtils.createAndJoinRoom({
        sender: '@testuser:localhost',
        name: 'room-test',
      });
      setupUserSubscription();
      setupAuthEndpoints();
      await setupAcceptanceTestRealm({
        realmURL,
        mockMatrixUtils,
        contents: {
          ...SYSTEM_CARD_FIXTURE_CONTENTS,
          'lesson.json': instance('lesson', 'Lesson', { title: 'Welcome' }),
          'full-module.json': instance(
            'course-module',
            'Module',
            { title: 'Foundations' },
            links('lessons', ['lesson']),
          ),
          'empty-module.json': instance('course-module', 'Module', {
            title: 'Hollow',
          }),
          'no-modules.json': course('No modules', []),
          'no-lessons.json': course('No lessons', ['empty-module']),
          'no-rule.json': course('No rule', ['full-module'], null),
          'ready.json': course('Ready', ['full-module']),
        },
      });
      await visitOperatorMode({ stacks: [[]] });
    });

    // The command's input links a Course, so it has to come from the loader
    // the store builds that course with.
    async function run(courseId: string) {
      let { default: Command } = (await getService(
        'loader-service',
      ).loader.import(`${academy}commands/publish-course-command`)) as {
        default: typeof PublishCourseCommand;
      };
      let card = (await getService('store').get(
        `${realmURL}${courseId}`,
      )) as Course;
      return new Command(getService('tool-service').commandContext).execute({
        course: card,
      });
    }

    test('publish-course refuses a course with no modules', async function (assert) {
      await assert.rejects(run('no-modules'), /the course has no modules/);
    });

    test('publish-course refuses a course whose module has no lessons', async function (assert) {
      await assert.rejects(run('no-lessons'), /Hollow has no lessons/);
    });

    test('publish-course refuses a course with no completion rule', async function (assert) {
      await assert.rejects(run('no-rule'), /completion requirement/);
    });

    test('publish-course publishes a ready course, and a second run changes nothing', async function (assert) {
      let first = await run('ready');
      assert.ok(/published/.test(first?.message ?? ''), first?.message);
      let published = (await getService('store').get(
        `${realmURL}ready`,
      )) as Course;
      assert.strictEqual(published.status, 'published');

      let second = await run('ready');
      assert.ok(
        /already published/.test(second?.message ?? ''),
        second?.message,
      );
    });
  });
}
