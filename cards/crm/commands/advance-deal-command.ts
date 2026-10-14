import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Opportunity } from '../opportunity';
import {
  PIPELINE_STAGES,
  PipelineStageField,
  canTransition,
} from '../pipeline-stage-field';
import { inputCard } from '@cardstack/catalog/utils/find-card';
import { isCardOfType } from '@cardstack/catalog/utils/card-type';

export class AdvanceDealInput extends CardDef {
  @field deal = linksTo(Opportunity, { searchable: true });
  @field toStage = contains(StringField);
  @field realm = contains(StringField);
}

export class AdvanceDealResult extends CardDef {
  @field deal = linksTo(Opportunity);
  @field message = contains(StringField);
}

/**
 * Moves an Opportunity (or a Deal) to a new Pipeline Stage, following the
 * stage graph. A deal already at the target stage is left as it is, so
 * running the command again changes nothing.
 */
export default class AdvanceDealCommand extends Command<
  typeof AdvanceDealInput,
  typeof AdvanceDealResult
> {
  static actionVerb = 'Advance Deal';

  async getInputType() {
    return AdvanceDealInput;
  }

  protected async run(input: AdvanceDealInput): Promise<AdvanceDealResult> {
    let ctx = this.commandContext;
    let toStage = input.toStage?.trim();
    if (!toStage) throw new Error('A target stage is required');
    if (!(PIPELINE_STAGES as readonly string[]).includes(toStage)) {
      throw new Error(`"${toStage}" is not a pipeline stage`);
    }

    let deal = await inputCard<Opportunity>(ctx, input, 'deal');
    if (!deal) throw new Error('A deal or opportunity is required');
    if (!isCardOfType(deal, Opportunity)) {
      throw new Error(
        `${(deal as CardDef).id ?? 'The card'} is not a deal or opportunity`,
      );
    }

    if (deal.stage === toStage) {
      return new AdvanceDealResult({
        deal,
        message: `${deal.cardTitle} is already at "${toStage}".`,
      });
    }
    if (!canTransition(PipelineStageField, deal.stage, toStage)) {
      throw new Error(
        `Cannot move a deal from "${deal.stage ?? 'unset'}" to "${toStage}"`,
      );
    }

    let realm = input.realm?.trim() || (deal as any)[realmURL]?.href;
    if (!realm) throw new Error('A realm is required');

    deal.stage = toStage;
    deal.lastStageChangedAt = new Date();
    await new SaveCardCommand(ctx).execute({ card: deal, realm } as any);

    return new AdvanceDealResult({
      deal,
      message: `${deal.cardTitle} moved to "${toStage}".`,
    });
  }
}
