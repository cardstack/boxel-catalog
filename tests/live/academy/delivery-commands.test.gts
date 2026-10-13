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

import type { Certificate } from '../../../cards/academy/certificate';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/academy-delivery/';
const academy = `${catalogRealmURL}cards/academy/`;

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

function link(id: string) {
  return { links: { self: `${realmURL}${id}` } };
}

function cohort(
  name: string,
  status: string,
  capacity: number,
  releasedModuleIds: string[] = [],
) {
  return instance(
    'cohort',
    'Cohort',
    {
      name,
      status,
      capacity,
      releases: releasedModuleIds.map(() => ({
        releasedAt: '2026-09-01T09:00:00.000Z',
      })),
    },
    {
      course: link('course'),
      ...Object.fromEntries(
        releasedModuleIds.map((id, i) => [`releases.${i}.module`, link(id)]),
      ),
    },
  );
}

function seat(learner: string, cohortId: string) {
  return instance(
    'enrollment',
    'Enrollment',
    { enrollmentStatus: 'active' },
    { learner: link(learner), cohort: link(cohortId) },
  );
}

// Each command links its input cards by class, so it has to come from the
// loader the store builds those cards with.
async function command(path: string) {
  let { default: Command } = (await getService('loader-service').loader.import(
    `${academy}commands/${path}`,
  )) as { default: new (ctx: unknown) => { execute(input: any): any } };
  return new Command(getService('tool-service').commandContext);
}

async function card(id: string) {
  return getService('store').get(`${realmURL}${id}`);
}

export function runTests() {
  module(
    'Acceptance | Catalog | academy - delivery commands',
    function (hooks) {
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
            'm1.json': instance('course-module', 'Module', { title: 'One' }),
            'm2.json': instance('course-module', 'Module', { title: 'Two' }),
            'outsider.json': instance('course-module', 'Module', {
              title: 'Elsewhere',
            }),
            'course.json': instance(
              'course',
              'Course',
              { title: 'Analytics', status: 'published' },
              { 'modules.0': link('m1'), 'modules.1': link('m2') },
            ),
            'ada.json': instance('learner', 'Learner', { name: 'Ada' }),
            'ben.json': instance('learner', 'Learner', { name: 'Ben' }),
            'running.json': cohort('Running', 'running', 1, ['m1']),
            'planned.json': cohort('Planned', 'planned', 10),
            'closed.json': cohort('Closed', 'closed', 10),
            'ada-running.json': seat('ada', 'running'),
            'cert.json': instance('certificate', 'Certificate', {
              number: 'ACAD-2026-000042',
              certStatus: 'issued',
            }),
          },
        });
        await visitOperatorMode({ stacks: [[]] });
      });

      test('enroll-learner refuses a closed cohort, a second seat and a full cohort', async function (assert) {
        let enroll = await command('enroll-learner-command');
        let run = async (cohortId: string, learnerId: string) =>
          enroll.execute({
            cohort: await card(cohortId),
            learner: await card(learnerId),
          });
        await assert.rejects(run('closed', 'ben'), /is closed/);
        await assert.rejects(run('running', 'ada'), /Ada already has a seat/);
        await assert.rejects(run('running', 'ben'), /is full \(1\/1\)/);
      });

      test('release-module refuses a cohort that is not running, a module outside the course, and a second release', async function (assert) {
        let release = await command('release-module-command');
        let run = async (cohortId: string, moduleId: string) =>
          release.execute({
            cohort: await card(cohortId),
            module: await card(moduleId),
          });
        await assert.rejects(run('planned', 'm2'), /not running/);
        await assert.rejects(run('running', 'outsider'), /not part of/);
        await assert.rejects(run('running', 'm1'), /already released/);

        let result = await run('running', 'm2');
        assert.ok(/Two released/.test(result?.message ?? ''), result?.message);
        await assert.rejects(run('running', 'm2'), /already released/);
      });

      test('revoke-certificate needs a reason and refuses a second revoke', async function (assert) {
        let revoke = await command('revoke-certificate-command');
        let run = async (reason: string) =>
          revoke.execute({ certificate: await card('cert'), reason });
        await assert.rejects(run('  '), /A reason is required/);

        await run('Issued against the wrong cohort');
        let revoked = (await card('cert')) as Certificate;
        assert.strictEqual(revoked.certStatus, 'revoked');
        assert.strictEqual(
          revoked.revokedReason,
          'Issued against the wrong cohort',
        );
        await assert.rejects(run('Again'), /already revoked/);
      });
    },
  );
}
