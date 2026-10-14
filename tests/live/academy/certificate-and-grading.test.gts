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

import {
  allSatisfied,
  evaluateCompletion,
} from '../../../cards/academy/completion-evaluation-field';
import { nextCertificateNumber } from '../../../cards/academy/certificate-number-field';
import { calendarDay } from '../../../cards/academy/commands/mark-attendance-command';

import { linkedId } from '../../../utils/linked-id';

import type { Certificate } from '../../../cards/academy/certificate';
import type { Enrollment } from '../../../cards/academy/enrollment';
import type { Grade } from '../../../cards/academy/grade';
import type { Submission } from '../../../cards/academy/submission';
import type { CertificationAuthority } from '../../../cards/audit/certification-authority';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/academy-certify/';
const academy = `${catalogRealmURL}cards/academy/`;
const year = new Date().getFullYear();

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
      meta: { adoptsFrom: { module: `${catalogRealmURL}${module}`, name } },
    },
  };
}

function link(id: string) {
  return { links: { self: `${realmURL}${id}` } };
}

function seat(learner: string, cohortId: string) {
  return instance(
    'cards/academy/enrollment',
    'Enrollment',
    { enrollmentStatus: 'active' },
    { learner: link(learner), cohort: link(cohortId) },
  );
}

function submission(enrollment: string, submittedAt: string) {
  return instance(
    'cards/academy/submission',
    'Submission',
    { version: 1, submissionStatus: 'submitted', submittedAt },
    { enrollment: link(enrollment), assignment: link('essay') },
  );
}

// Commands link their input cards by class, so they come from the loader the
// store builds those cards with.
async function command(path: string) {
  let { default: Command } = await commandModule(path);
  return new Command(getService('tool-service').commandContext);
}

// A containsMany input takes field instances, built from the same module.
async function commandModule(path: string) {
  return (await getService('loader-service').loader.import(
    `${academy}commands/${path}`,
  )) as {
    default: new (ctx: unknown) => { execute(input: any): any };
    [field: string]: any;
  };
}

async function card<T = any>(id: string): Promise<T> {
  return (await getService('store').get(`${realmURL}${id}`)) as T;
}

// A link on a stored card may not have loaded; read its id, then fetch it.
async function follow<T = any>(from: any, field: string): Promise<T> {
  let id = linkedId(from, field);
  return (id ? await getService('store').get(id) : undefined) as T;
}

export function runTests() {
  module('Unit | Catalog | academy - completion and numbering', function () {
    test('evaluateCompletion judges each clause and allSatisfied needs at least one', function (assert) {
      let facts = {
        attendanceRecords: [
          { attendanceStatus: 'present' },
          { attendanceStatus: 'absent' },
        ],
        liveLessonsHeld: 2,
        requiredAssignments: [
          { id: 'a1', title: 'Essay' },
          { id: 'a2', title: 'Project' },
        ],
        gradedRequiredAssignmentIds: ['a1'],
        quizzesPassed: 1,
      };
      let clauses = evaluateCompletion(
        {
          minAttendancePct: 50,
          requireAllRequiredAssignments: true,
          minQuizPassCount: 1,
        } as Parameters<typeof evaluateCompletion>[0],
        facts,
      );
      assert.deepEqual(
        clauses.map((c) => [c.rule, c.satisfied]),
        [
          ['Attendance', true],
          ['Required assignments graded', false],
          ['Quizzes passed', true],
        ],
      );
      assert.strictEqual(clauses[1].evidence, 'Missing: Project');
      assert.false(allSatisfied(clauses));
      assert.true(allSatisfied(clauses.filter((c) => c.satisfied)));
      assert.deepEqual(evaluateCompletion(null, facts), []);
      assert.false(allSatisfied([]), 'no rule is not complete');
    });

    test('nextCertificateNumber takes the next sequence under a cleaned prefix', function (assert) {
      assert.deepEqual(nextCertificateNumber('acad-x', 2026, 41), {
        number: 'ACADX-2026-000042',
        sequence: 42,
      });
      assert.strictEqual(
        nextCertificateNumber(undefined, 2026, null).number,
        'CERT-2026-000001',
      );
    });

    test('calendarDay is the local day, not the UTC one', function (assert) {
      assert.strictEqual(
        calendarDay(new Date(2026, 0, 5, 23, 30)),
        '2026-01-05',
      );
      assert.strictEqual(
        calendarDay(new Date(2026, 11, 31, 0, 5)),
        '2026-12-31',
      );
    });
  });

  module(
    'Acceptance | Catalog | academy - certificates and grading',
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
            'authority.json': instance(
              'cards/audit/certification-authority',
              'CertificationAuthority',
              { name: 'Academy', numberPrefix: 'ACAD', lastSequence: 41 },
            ),
            'rubric.json': instance('cards/academy/rubric', 'Rubric', {
              title: 'Essay rubric',
              criteria: [
                {
                  name: 'Analysis',
                  weight: 1,
                  maxPoints: 10,
                  levels: [
                    { label: 'Strong', points: 10 },
                    { label: 'Weak', points: 4 },
                  ],
                },
              ],
            }),
            'essay.json': instance(
              'cards/academy/assignment',
              'Assignment',
              {
                title: 'Essay',
                maxPoints: 10,
                dueWindow: { dueAt: '2026-09-10T09:00:00.000Z' },
              },
              { rubric: link('rubric') },
            ),
            'ruled.json': instance('cards/academy/course', 'Course', {
              title: 'Analytics',
              status: 'published',
              completionRule: { minQuizPassCount: 1 },
              latePolicy: {
                penaltyPctPerDay: 10,
                capPct: 50,
                graceHours: 0,
                hardCloseDays: 0,
              },
            }),
            'open.json': instance('cards/academy/course', 'Course', {
              title: 'Open course',
              status: 'published',
            }),
            'ruled-cohort.json': instance(
              'cards/academy/cohort',
              'Cohort',
              { name: 'Ruled', status: 'running', capacity: 10 },
              { course: link('ruled') },
            ),
            'open-cohort.json': instance(
              'cards/academy/cohort',
              'Cohort',
              { name: 'Open', status: 'running', capacity: 10 },
              { course: link('open') },
            ),
            'ada.json': instance('cards/academy/learner', 'Learner', {
              name: 'Ada',
            }),
            'ben.json': instance('cards/academy/learner', 'Learner', {
              name: 'Ben',
            }),
            'cara.json': instance('cards/academy/learner', 'Learner', {
              name: 'Cara',
            }),
            'ada-ruled.json': seat('ada', 'ruled-cohort'),
            'ben-open.json': seat('ben', 'open-cohort'),
            'cara-ruled.json': seat('cara', 'ruled-cohort'),
            'dan.json': instance('cards/academy/learner', 'Learner', {
              name: 'Dan',
            }),
            'eve.json': instance('cards/academy/learner', 'Learner', {
              name: 'Eve',
            }),
            'dan-ruled.json': seat('dan', 'ruled-cohort'),
            'eve-ruled.json': seat('eve', 'ruled-cohort'),
            // An earlier run saved this certificate, then stopped before
            // linking it from the enrolment.
            'cara-cert.json': instance(
              'cards/academy/certificate',
              'Certificate',
              { number: `ACAD-${year}-000050`, certStatus: 'issued' },
              { enrollment: link('cara-ruled'), authority: link('authority') },
            ),
            'check.json': instance('cards/academy/quiz', 'Quiz', {
              title: 'Check',
              attemptsAllowed: 1,
              questions: [
                {
                  prompt: 'Two plus two?',
                  kind: 'single',
                  points: 1,
                  options: [
                    { label: 'Four', key: 'four', isCorrect: true },
                    { label: 'Five', key: 'five', isCorrect: false },
                  ],
                },
              ],
            }),
            'ada-essay.json': submission(
              'ada-ruled',
              '2026-09-12T10:00:00.000Z',
            ),
            'cara-essay.json': submission(
              'cara-ruled',
              '2026-09-09T10:00:00.000Z',
            ),
            // An earlier grading run saved this grade, then stopped.
            'cara-grade.json': instance(
              'cards/academy/grade',
              'Grade',
              {},
              { submission: link('cara-essay') },
            ),
          },
        });
        await visitOperatorMode({ stacks: [[]] });
      });

      test('issue-certificate refuses unmet clauses, and a forced issue takes the next number', async function (assert) {
        let issue = await command('issue-certificate-command');
        let run = async (force = false) =>
          issue.execute({
            enrollment: await card('ada-ruled'),
            authority: await card('authority'),
            force,
          });
        await assert.rejects(run(), /Not eligible — Quizzes passed: 0 of 1/);

        let result = await run(true);
        assert.ok(
          /forced: Quizzes passed unmet/.test(result.message),
          result.message,
        );
        let enrollment = await card<Enrollment>('ada-ruled');
        assert.strictEqual(enrollment.enrollmentStatus, 'completed');
        let certificate = await follow<Certificate>(enrollment, 'certificate');
        assert.strictEqual(certificate?.number, `ACAD-${year}-000042`);
        let authority = await card<CertificationAuthority>('authority');
        assert.strictEqual(authority.lastSequence, 42);
      });

      test('two concurrent issues against one authority take distinct numbers', async function (assert) {
        let issue = async (enrollmentId: string) =>
          (await command('issue-certificate-command')).execute({
            enrollment: await card(enrollmentId),
            authority: await card('authority'),
            force: true,
          });
        await Promise.all([issue('dan-ruled'), issue('eve-ruled')]);

        let numbers = await Promise.all(
          ['dan-ruled', 'eve-ruled'].map(async (id) => {
            let certificate = await follow<Certificate>(
              await card(id),
              'certificate',
            );
            return certificate?.number;
          }),
        );
        assert.deepEqual([...numbers].sort(), [
          `ACAD-${year}-000042`,
          `ACAD-${year}-000043`,
        ]);
        let authority = await card<CertificationAuthority>('authority');
        assert.strictEqual(authority.lastSequence, 43);
      });

      test('issue-certificate refuses a course with no completion rule unless forced', async function (assert) {
        let issue = await command('issue-certificate-command');
        let run = async (force = false) =>
          issue.execute({
            enrollment: await card('ben-open'),
            authority: await card('authority'),
            force,
          });
        await assert.rejects(run(), /Open course has no completion rule/);
        let result = await run(true);
        assert.ok(
          /forced: no completion rule/.test(result.message),
          result.message,
        );
      });

      test('issue-certificate finishes an interrupted run instead of minting a second number', async function (assert) {
        let issue = await command('issue-certificate-command');
        await issue.execute({
          enrollment: await card('cara-ruled'),
          authority: await card('authority'),
        });
        let enrollment = await card<Enrollment>('cara-ruled');
        assert.strictEqual(
          linkedId(enrollment as any, 'certificate'),
          `${realmURL}cara-cert`,
        );
        assert.strictEqual(enrollment.enrollmentStatus, 'completed');
        let authority = await card<CertificationAuthority>('authority');
        assert.strictEqual(
          authority.lastSequence,
          50,
          'the sequence catches up with the saved number',
        );
      });

      test('take-quiz saves the answers with the attempt and refuses past the attempt limit', async function (assert) {
        let { TakeQuizAnswerField } = await commandModule('take-quiz-command');
        let takeQuiz = await command('take-quiz-command');
        let run = async () =>
          takeQuiz.execute({
            enrollment: await card('ada-ruled'),
            quiz: await card('check'),
            answers: [
              new TakeQuizAnswerField({
                questionIndex: 0,
                selectedKeys: ['FOUR'],
              }),
            ],
          });
        let result = await run();
        assert.ok(/100%/.test(result.message), result.message);
        let attemptId = linkedId(result, 'attempt');
        let attempt = (await getService('store').get(attemptId!)) as any;
        assert.deepEqual(
          [...(attempt.answers?.[0]?.selectedKeys ?? [])],
          ['four'],
          'answers are on the saved attempt',
        );
        await assert.rejects(run(), /No attempts left: 1 of 1 used/);
      });

      test('grade-submission refuses a missing or unknown pick and applies the late penalty', async function (assert) {
        let { GradePickField } = await commandModule(
          'grade-submission-command',
        );
        let grade = await command('grade-submission-command');
        let pick = (criterionName: string, levelLabel: string) =>
          new GradePickField({ criterionName, levelLabel });
        let run = async (
          picks: { criterionName: string; levelLabel: string }[],
        ) =>
          grade.execute({
            submission: await card('ada-essay'),
            picks: picks.map((p) => pick(p.criterionName, p.levelLabel)),
          });
        await assert.rejects(
          run([]),
          /No level picked for criterion "Analysis"/,
        );
        await assert.rejects(
          run([{ criterionName: 'Analysis', levelLabel: 'Great' }]),
          /"Great" is not a level of "Analysis"/,
        );

        let result = await run([
          { criterionName: 'Analysis', levelLabel: 'Strong' },
        ]);
        assert.ok(/late/.test(result.message), result.message);
        let submissionCard = await card<Submission>('ada-essay');
        assert.strictEqual(submissionCard.submissionStatus, 'graded');
        let saved = await follow<Grade>(submissionCard, 'grade');
        assert.strictEqual(
          saved.penaltyPct,
          30,
          'three days late at 10% a day',
        );
        assert.strictEqual(saved.maxPoints, 10);
      });

      test('grade-submission finishes an interrupted run on the grade it left behind', async function (assert) {
        let { GradePickField } = await commandModule(
          'grade-submission-command',
        );
        let grade = await command('grade-submission-command');
        await grade.execute({
          submission: await card('cara-essay'),
          picks: [
            new GradePickField({
              criterionName: 'Analysis',
              levelLabel: 'Weak',
            }),
          ],
        });
        let submissionCard = await card<Submission>('cara-essay');
        assert.strictEqual(submissionCard.submissionStatus, 'graded');
        assert.strictEqual(
          linkedId(submissionCard as any, 'grade'),
          `${realmURL}cara-grade`,
        );
        let saved = await card<Grade>('cara-grade');
        assert.strictEqual(saved.penaltyPct, 0, 'on time');
      });
    },
  );
}
