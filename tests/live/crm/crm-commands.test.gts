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

import type AdvanceDealCommand from '../../../cards/crm/commands/advance-deal-command';
import type LaunchCampaignCommand from '../../../cards/crm/commands/launch-campaign-command';
import type { Campaign } from '../../../cards/crm/campaign';
import type { Opportunity } from '../../../cards/crm/opportunity';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/crm/';
const crm = `${catalogRealmURL}cards/crm/`;

function instance(
  module: string,
  name: string,
  attributes: Record<string, unknown> = {},
) {
  return {
    data: {
      type: 'card',
      attributes,
      meta: { adoptsFrom: { module: `${crm}${module}`, name } },
    },
  };
}

export function runTests() {
  module(
    'Acceptance | Catalog | crm - deal and campaign commands',
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
            'negotiating.json': instance('opportunity', 'Opportunity', {
              name: 'Harbor Renewal',
              stage: 'negotiation',
            }),
            'planned.json': instance('campaign', 'Campaign', {
              name: 'Spring Expo',
              status: 'planned',
            }),
            'completed.json': instance('campaign', 'Campaign', {
              name: 'Winter Webinar',
              status: 'completed',
              startDate: '2026-01-10',
            }),
          },
        });
        await visitOperatorMode({ stacks: [[]] });
      });

      // The inputs link cards, so each command has to come from the loader the
      // store builds those cards with.
      async function load<T>(path: string): Promise<T> {
        let { default: Command } = (await getService(
          'loader-service',
        ).loader.import(`${crm}commands/${path}`)) as { default: T };
        return Command;
      }

      async function advance(dealId: string, toStage: string) {
        let Command = await load<typeof AdvanceDealCommand>(
          'advance-deal-command',
        );
        let deal = (await getService('store').get(
          `${realmURL}${dealId}`,
        )) as Opportunity;
        return new Command(getService('tool-service').commandContext).execute({
          deal,
          toStage,
        });
      }

      async function launch(campaignId: string) {
        let Command = await load<typeof LaunchCampaignCommand>(
          'launch-campaign-command',
        );
        let campaign = (await getService('store').get(
          `${realmURL}${campaignId}`,
        )) as Campaign;
        return new Command(getService('tool-service').commandContext).execute({
          campaign,
        });
      }

      test('advance-deal refuses a move the stage graph does not allow', async function (assert) {
        await assert.rejects(
          advance('negotiating', 'proposal'),
          /Cannot move a deal from "negotiation" to "proposal"/,
        );
      });

      test('advance-deal refuses a stage that is not a pipeline stage', async function (assert) {
        await assert.rejects(
          advance('negotiating', 'signed'),
          /"signed" is not a pipeline stage/,
        );
      });

      test('advance-deal moves a deal one step, and a second run changes nothing', async function (assert) {
        let first = await advance('negotiating', 'closed won');
        assert.ok(
          /moved to "closed won"/.test(first?.message ?? ''),
          first?.message,
        );
        let deal = (await getService('store').get(
          `${realmURL}negotiating`,
        )) as Opportunity;
        assert.strictEqual(deal.stage, 'closed won');
        assert.ok(deal.lastStageChangedAt, 'the stage change is stamped');

        let second = await advance('negotiating', 'closed won');
        assert.ok(
          /already at "closed won"/.test(second?.message ?? ''),
          second?.message,
        );
      });

      test('launch-campaign refuses a campaign that is not planned', async function (assert) {
        await assert.rejects(
          launch('completed'),
          /Only a planned campaign can be launched \(this one is "completed"\)/,
        );
      });

      test('launch-campaign starts a planned campaign today, and a second run changes nothing', async function (assert) {
        let first = await launch('planned');
        assert.ok(/is now running/.test(first?.message ?? ''), first?.message);
        let campaign = (await getService('store').get(
          `${realmURL}planned`,
        )) as Campaign;
        assert.strictEqual(campaign.status, 'running');
        let start = campaign.startDate as Date | undefined;
        let today = new Date();
        assert.ok(start, 'a start date is set');
        assert.strictEqual(
          start?.toDateString(),
          today.toDateString(),
          'the start date is the local day of the launch',
        );

        let second = await launch('planned');
        assert.ok(
          /already running/.test(second?.message ?? ''),
          second?.message,
        );
      });
    },
  );
}
