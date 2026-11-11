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

import type { CardDef } from '@cardstack/base/card-api';

import { dayKey, addDays } from '../../../cards/maintenance/utils/recurrence';
import type { MaintenancePlan } from '../../../cards/maintenance/maintenance-plan';
import type { Meter } from '../../../cards/maintenance/meter';
import type { WorkOrder } from '../../../cards/maintenance/work-order';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/maintenance/';
const maintenance = `${catalogRealmURL}cards/maintenance/`;

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
      meta: { adoptsFrom: { module: `${maintenance}${module}`, name } },
    },
  };
}

function link(id: string) {
  return { links: { self: `${realmURL}${id}` } };
}

const today = new Date();
const todayKey = dayKey(today);
const yesterdayKey = dayKey(addDays(today, -1));

function dailyPlan(name: string) {
  return instance(
    'maintenance-plan',
    'MaintenancePlan',
    {
      name,
      kind: 'preventive',
      active: true,
      trigger: {
        calendar: { pattern: 'daily', interval: 1, startDate: yesterdayKey },
      },
      lastCompletedAt: yesterdayKey,
    },
    { asset: link('forklift') },
  );
}

export function runTests() {
  module('Acceptance | Catalog | maintenance - commands', function (hooks) {
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
          'forklift.json': instance('asset', 'Asset', {
            name: 'Forklift',
            serialNumber: 'SN-1',
            primaryMeterValue: 4600,
            primaryMeterUnit: 'h',
          }),
          'plan-raised.json': dailyPlan('Daily walkaround'),
          'plan-fresh.json': dailyPlan('Daily battery check'),
          'plan-meter.json': instance(
            'maintenance-plan',
            'MaintenancePlan',
            {
              name: '500-hour service',
              kind: 'preventive',
              active: true,
              trigger: { meterThreshold: 500, meterUnit: 'h' },
              lastCompletedMeter: 4000,
            },
            { asset: link('forklift') },
          ),
          'plan-both.json': instance(
            'maintenance-plan',
            'MaintenancePlan',
            {
              name: 'Quarterly or 500-hour service',
              kind: 'preventive',
              active: true,
              trigger: {
                calendar: { pattern: 'monthly', interval: 3 },
                meterThreshold: 500,
                meterUnit: 'h',
                whicheverFirst: true,
              },
              lastCompletedAt: yesterdayKey,
              lastCompletedMeter: 4000,
            },
            { asset: link('forklift') },
          ),
          'both-open.json': instance(
            'work-order',
            'WorkOrder',
            {
              title: 'Quarterly or 500-hour service',
              status: 'scheduled',
              kind: 'preventive',
              planDueKey: `plan-both@${dayKey(addDays(today, 90))}`,
            },
            { plan: link('plan-both') },
          ),
          'raised.json': instance(
            'work-order',
            'WorkOrder',
            {
              title: 'Daily walkaround',
              status: 'requested',
              kind: 'preventive',
              planDueKey: `plan-raised@${todayKey}`,
            },
            { plan: link('plan-raised') },
          ),
          'done.json': instance(
            'work-order',
            'WorkOrder',
            {
              title: 'Daily battery check',
              status: 'completed',
              kind: 'preventive',
              completedAt: `${todayKey}T12:00:00`,
            },
            { plan: link('plan-fresh'), subjectAsset: link('forklift') },
          ),
          'hours.json': instance(
            'meter',
            'Meter',
            {
              name: 'Running hours',
              kind: 'cumulative',
              unit: 'h',
              readings: [
                {
                  value: 4600,
                  unit: 'h',
                  readAt: '2026-09-01T00:00:00.000Z',
                },
              ],
            },
            { asset: link('forklift') },
          ),
        },
      });
      await visitOperatorMode({ stacks: [[]] });
    });

    // Commands that check fetched cards with `instanceof` must come from the
    // loader the store builds those cards with.
    async function command<T>(path: string): Promise<T> {
      let { default: Command } = (await getService(
        'loader-service',
      ).loader.import(`${maintenance}commands/${path}`)) as {
        default: new (context: unknown) => T;
      };
      return new Command(getService('tool-service').commandContext);
    }

    async function card<T extends CardDef>(id: string): Promise<T> {
      return (await getService('store').get(`${realmURL}${id}`)) as T;
    }

    test('complete-work-order re-run on a completed order advances its plan once', async function (assert) {
      let cmd = await command<any>('complete-work-order-command');
      let workOrder = await card<WorkOrder>('done');
      await cmd.execute({ workOrder, completedByName: 'Priya' });

      let plan = await card<MaintenancePlan>('plan-fresh');
      assert.strictEqual(
        plan.lastCompletedAt ? dayKey(new Date(plan.lastCompletedAt)) : null,
        todayKey,
        'the plan picks up the completion day',
      );
      assert.strictEqual(plan.lastCompletedMeter, 4600);

      await cmd.execute({ workOrder, completedByName: 'Priya' });
      let after = await card<WorkOrder>('done');
      assert.strictEqual(after.status, 'completed', 'still completed');
      plan = await card<MaintenancePlan>('plan-fresh');
      assert.strictEqual(
        plan.lastCompletedAt ? dayKey(new Date(plan.lastCompletedAt)) : null,
        todayKey,
        'the re-run leaves the completion day alone',
      );
      assert.strictEqual(
        plan.lastCompletedMeter,
        4600,
        'the re-run leaves the meter alone',
      );
    });

    test('record-meter-reading refuses a cumulative reading below the last one', async function (assert) {
      let cmd = await command<any>('record-meter-reading-command');
      let meter = await card<Meter>('hours');
      await assert.rejects(cmd.execute({ meter, value: 4500 }), /cumulative/);

      let readAt = new Date('2026-09-02T00:00:00.000Z');
      await cmd.execute({ meter, value: 4700, readAt });
      await cmd.execute({ meter, value: 4700, readAt });
      let after = await card<Meter>('hours');
      assert.strictEqual(
        after.readings.length,
        2,
        'the repeated reading is recorded once',
      );
    });
  });
}
