import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Campaign } from '../campaign';
import { inputCard } from '@cardstack/catalog/utils/find-card';
import { isCardOfType } from '@cardstack/catalog/utils/card-type';

export class LaunchCampaignInput extends CardDef {
  @field campaign = linksTo(Campaign, { searchable: true });
  @field realm = contains(StringField);
}

export class LaunchCampaignResult extends CardDef {
  @field campaign = linksTo(Campaign);
  @field message = contains(StringField);
}

/**
 * Starts a planned Campaign: its status moves to `running`, and a campaign
 * with no start date starts today. A running campaign is left as it is, so
 * running the command again changes nothing.
 */
export default class LaunchCampaignCommand extends Command<
  typeof LaunchCampaignInput,
  typeof LaunchCampaignResult
> {
  static actionVerb = 'Launch Campaign';

  async getInputType() {
    return LaunchCampaignInput;
  }

  protected async run(
    input: LaunchCampaignInput,
  ): Promise<LaunchCampaignResult> {
    let campaign = await inputCard<Campaign>(
      this.commandContext,
      input,
      'campaign',
    );
    if (!campaign) throw new Error('A campaign is required');
    if (!isCardOfType(campaign, Campaign)) {
      throw new Error(
        `${(campaign as CardDef).id ?? 'The card'} is not a campaign`,
      );
    }

    if (campaign.status === 'running') {
      return new LaunchCampaignResult({
        campaign,
        message: `${campaign.cardTitle} is already running.`,
      });
    }
    if (campaign.status !== 'planned') {
      throw new Error(
        `Only a planned campaign can be launched (this one is "${campaign.status ?? 'unset'}")`,
      );
    }

    let realm = input.realm?.trim() || (campaign as any)[realmURL]?.href;
    if (!realm) throw new Error('A realm is required');

    let { status, startDate } = campaign;
    campaign.status = 'running';
    if (!startDate) {
      campaign.startDate = new Date();
    }
    try {
      await new SaveCardCommand(this.commandContext).execute({
        card: campaign,
        realm,
      } as any);
    } catch (e) {
      campaign.status = status;
      campaign.startDate = startDate;
      throw e;
    }

    return new LaunchCampaignResult({
      campaign,
      message: `${campaign.cardTitle} is now running.`,
    });
  }
}
