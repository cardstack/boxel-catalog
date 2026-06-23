import { CardDef, field, contains } from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';
import { Command } from '@cardstack/runtime-common';

// Minimal system steer; the substance (role, rules, JSON schema) comes from
// the skill instructions, which OneShotLlmRequestCommand folds into the
// request.
const SYSTEM_PROMPT = `You are a travel-itinerary planner. Follow the attached skill's instructions and JSON schema exactly. OUTPUT: ONE JSON object only — no prose, no markdown fences, no commentary.`;

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

class TravelPlannerInput extends CardDef {
  @field userPrompt = contains(StringField, {
    description:
      'The trip facts (destination, days, dates, vibe, category list) and any revision request, as plain text.',
  });
  @field llmModel = contains(StringField, {
    description:
      'Optional OpenRouter model id. Defaults to anthropic/claude-sonnet-4.6.',
  });
}

class TravelPlannerResult extends CardDef {
  @field output = contains(StringField, {
    description: 'Raw JSON itinerary string returned by the model.',
  });
}

export class TravelPlannerCommand extends Command<
  typeof TravelPlannerInput,
  typeof TravelPlannerResult
> {
  static actionVerb = 'Plan';
  static displayName = 'Travel Planner';

  async getInputType() {
    return TravelPlannerInput;
  }

  protected async run(input: TravelPlannerInput): Promise<TravelPlannerResult> {
    if (!input.userPrompt) {
      throw new Error('userPrompt is required');
    }

    let skillCardId = new URL('../Skill/travel-planner-skill', here).href;

    let oneShot = new OneShotLlmRequestCommand(this.commandContext);
    let result = await oneShot.execute({
      systemPrompt: SYSTEM_PROMPT,
      userPrompt: input.userPrompt,
      skillCardIds: [skillCardId],
      llmModel: input.llmModel || 'anthropic/claude-sonnet-4.6',
    });

    return new TravelPlannerResult({
      output: (result as any)?.output ?? '',
    });
  }
}
