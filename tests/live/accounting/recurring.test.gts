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
  dueDateOf,
  dueRuns,
  draftDateFor,
  nextRunAfter,
} from '../../../cards/accounting/ledger-recurring';
import { padDate } from '../../../cards/accounting/ledger-journal';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/recurring/';
const recurringModule = `${catalogRealmURL}cards/accounting/ledger-recurring`;

const monthly = (startDate: string, more: Record<string, unknown> = {}) =>
  ({
    pattern: 'monthly',
    interval: 1,
    dayOfMonth: 1,
    startDate,
    ...more,
  }) as never;

function template(attributes: Record<string, unknown>) {
  return {
    data: {
      type: 'card',
      attributes: {
        templateId: 'RT-RENT',
        name: 'Rent',
        docKind: 'bill',
        party: 'landlord',
        type: 'scheduled',
        schedule: {
          pattern: 'monthly',
          interval: 1,
          dayOfMonth: 1,
          startDate: '2027-01-01',
        },
        daysInAdvance: 0,
        paused: false,
        billLines: [],
        ...attributes,
      },
      meta: {
        adoptsFrom: { module: recurringModule, name: 'RecurringTemplate' },
      },
    },
  };
}

const reason = (e: any) => String(e?.detail ?? e?.message ?? e);

export function runTests() {
  module('Catalog | accounting - recurring templates', function () {
    test('a template is due on its next date, or its schedule start before its first scheduled run', function (assert) {
      let schedule = { startDate: '2027-01-01' };
      assert.strictEqual(
        dueDateOf({ nextDate: '2027-03-01', scheduledRuns: 2, schedule }),
        '2027-03-01',
      );
      assert.strictEqual(
        dueDateOf({ scheduledRuns: 0, schedule }),
        '2027-01-01',
        'before its first run it starts on the schedule start',
      );
      assert.strictEqual(
        dueDateOf({ schedule: { startDate: new Date(2027, 0, 15) } }),
        '2027-01-15',
        'a start held as a date reads as its calendar day',
      );
      assert.strictEqual(
        dueDateOf({ scheduledRuns: 3, schedule }),
        '',
        'a schedule that has run out has no due date',
      );
    });

    test('the run after a date stops once the schedule reaches its occurrence limit', function (assert) {
      let schedule = monthly('2027-01-01', { occurrences: 3 });
      assert.strictEqual(nextRunAfter(schedule, '2027-01-01', 1), '2027-02-01');
      assert.strictEqual(nextRunAfter(schedule, '2027-02-01', 2), '2027-03-01');
      assert.strictEqual(
        nextRunAfter(schedule, '2027-03-01', 3),
        '',
        'the third run is the last',
      );
      assert.strictEqual(
        nextRunAfter(
          monthly('2027-01-01', { endDate: '2027-02-15' }),
          '2027-02-01',
          2,
        ),
        '',
        'nor does it run past its end date',
      );
    });

    test('runs missed while the desk was closed are all due, oldest first', function (assert) {
      let t = {
        nextDate: '2027-01-01',
        scheduledRuns: 0,
        daysInAdvance: 0,
        schedule: monthly('2027-01-01'),
      };
      assert.deepEqual(dueRuns(t, '2027-03-15'), [
        { runDate: '2027-01-01', scheduledRuns: 0 },
        { runDate: '2027-02-01', scheduledRuns: 1 },
        { runDate: '2027-03-01', scheduledRuns: 2 },
      ]);
      assert.deepEqual(
        dueRuns({ ...t, daysInAdvance: 5 }, '2027-03-27').map((r) => r.runDate),
        ['2027-01-01', '2027-02-01', '2027-03-01', '2027-04-01'],
        'days in advance bring a run forward',
      );
      assert.deepEqual(
        dueRuns(
          { ...t, schedule: monthly('2027-01-01', { occurrences: 2 }) },
          '2027-06-01',
        ).map((r) => r.runDate),
        ['2027-01-01', '2027-02-01'],
        'catching up stops at the occurrence limit',
      );
      assert.deepEqual(
        dueRuns(
          {
            nextDate: '2027-02-01',
            scheduledRuns: 1,
            schedule: monthly('2027-01-01', { occurrences: 2 }),
          },
          '2027-06-01',
        ),
        [{ runDate: '2027-02-01', scheduledRuns: 1 }],
        'a template part way through counts on from its scheduled runs',
      );
      assert.deepEqual(
        dueRuns(t, '2026-12-31'),
        [],
        'nothing before it is due',
      );
      assert.strictEqual(
        dueRuns(t, '2030-01-01', 4).length,
        4,
        'and at most the cap',
      );
    });

    test("a run's draft is dated inside the open books", function (assert) {
      assert.strictEqual(
        draftDateFor('2027-02-01', '2027-04-01'),
        '2027-04-01',
      );
      assert.strictEqual(
        draftDateFor('2027-05-01', '2027-04-01'),
        '2027-05-01',
      );
      assert.strictEqual(draftDateFor('2027-02-01', ''), '2027-02-01');
      let open = [
        { firstDay: '2027-03-01', lastDay: '2027-03-31' },
        { firstDay: '2027-04-01', lastDay: '2027-04-30' },
      ];
      assert.strictEqual(padDate('2027-03-10', open), '2027-03-10');
      assert.strictEqual(padDate('2027-02-01', open), '2027-04-01');
      assert.strictEqual(padDate('2027-06-01', open), '2027-04-30');
      assert.strictEqual(padDate('2027-03-10', []), '', 'no open month');
    });
  });

  module(
    'Acceptance | Catalog | accounting - recurring template operations',
    function (hooks) {
      setupApplicationTest(hooks);
      setupLocalIndexing(hooks);
      setupOnSave(hooks);

      let mockMatrixUtils = setupMockMatrix(hooks, {
        loggedInAs: '@testuser:localhost',
        activeRealms: [realmURL],
      });
      let adapter: any;
      let operations: (card: unknown) => any;

      hooks.beforeEach(async function () {
        mockMatrixUtils.createAndJoinRoom({
          sender: '@testuser:localhost',
          name: 'room-test',
        });
        setupUserSubscription();
        setupAuthEndpoints();
        ({ adapter } = await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'RecurringTemplate/fresh.json': template({
              nextDate: null,
              runCount: 0,
              scheduledRuns: 0,
            }),
            'RecurringTemplate/midway.json': template({
              nextDate: '2027-02-01',
              lastRunDate: '2027-01-01',
              runCount: 1,
              scheduledRuns: 1,
            }),
            'RecurringTemplate/ended.json': template({
              nextDate: null,
              lastRunDate: '2027-03-01',
              runCount: 3,
              scheduledRuns: 3,
            }),
          },
        }));
        await visitOperatorMode({ stacks: [[]] });
        ({ operations } = (await getService('loader-service').loader.import(
          '@cardstack/base/operations',
        )) as any);
      });

      const get = (id: string) =>
        getService('store').get(`${realmURL}RecurringTemplate/${id}`);
      const stored = async (id: string) =>
        JSON.parse(
          (await adapter.openFile(`RecurringTemplate/${id}.json`)).content,
        ).data.attributes;

      test('advance records the run due and moves the template to the next', async function (assert) {
        await operations(await get('midway')).advance({
          runDate: '2027-02-01',
          nextDate: '2027-03-01',
        });
        let t = await stored('midway');
        assert.strictEqual(t.lastRunDate, '2027-02-01');
        assert.strictEqual(t.nextDate, '2027-03-01');
        assert.strictEqual(t.runCount, 2);
        assert.strictEqual(t.scheduledRuns, 2);
      });

      test("advance refuses a run that isn't the one due", async function (assert) {
        await assert.rejects(
          operations(await get('midway')).advance({
            runDate: '2027-01-01',
            nextDate: '2027-02-01',
          }),
          (e: any) => /isn't the one due/.test(reason(e)),
        );
      });

      test('advance takes any first run before the schedule has started', async function (assert) {
        await operations(await get('fresh')).advance({
          runDate: '2027-01-01',
          nextDate: '2027-02-01',
        });
        let t = await stored('fresh');
        assert.strictEqual(t.nextDate, '2027-02-01');
        assert.strictEqual(t.scheduledRuns, 1);
      });

      test('advance refuses a run once the schedule has run out', async function (assert) {
        await assert.rejects(
          operations(await get('ended')).advance({
            runDate: '2027-04-01',
            nextDate: null,
          }),
          (e: any) => /run out/.test(reason(e)),
        );
        assert.strictEqual((await stored('ended')).runCount, 3);
      });

      test('ran records a run by hand once a day, without moving the schedule', async function (assert) {
        await operations(await get('ended')).ran({ runDate: '2027-04-10' });
        let t = await stored('ended');
        assert.strictEqual(t.runCount, 4);
        assert.strictEqual(t.scheduledRuns, 3);
        await assert.rejects(
          operations(await get('ended')).ran({ runDate: '2027-04-10' }),
          (e: any) => /already ran on that day/.test(reason(e)),
        );
      });
    },
  );
}
