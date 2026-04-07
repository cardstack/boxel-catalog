import { on } from '@ember/modifier';

import CreateAiAssistantRoomCommand from '@cardstack/boxel-host/commands/create-ai-assistant-room';
import SendAiAssistantMessageCommand from '@cardstack/boxel-host/commands/send-ai-assistant-message';

import { Button } from '@cardstack/boxel-ui/components';
import { CardContainer } from '@cardstack/boxel-ui/components';

import { Command } from '@cardstack/runtime-common';

import {
  CardDef,
  Component,
  StringField,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import { Skill } from 'https://cardstack.com/base/skill';

export class SampleInput extends CardDef {
  @field prompt = contains(StringField);
}

export class SampleOutput extends CardDef {
  @field result = contains(StringField);
}

export class SampleCommand extends Command<
  typeof SampleInput,
  typeof SampleOutput
> {
  static actionVerb = 'Run';
  inputType = SampleInput;

  async getInputType() {
    return SampleInput;
  }

  protected async run(input: SampleInput): Promise<SampleOutput> {
    return new SampleOutput({ result: `Processed: ${input.prompt}` });
  }
}

export class SampleCommandCard extends CardDef {
  static displayName = 'Sample Command Card';
  @field title = contains(StringField);

  static isolated = class Isolated extends Component<typeof SampleCommandCard> {
    runSample = async () => {
      let commandContext = this.args.context?.commandContext;
      if (!commandContext) {
        throw new Error('No command context found');
      }

      let createAIAssistantRoomCommand = new CreateAiAssistantRoomCommand(
        commandContext,
      );
      let sampleSkill = new Skill({
        name: 'Sample Skill',
        cardDescription: 'A sample skill',
        instructions: 'Use the command to process a sample input',
        commands: [
          {
            codeRef: {
              module: import.meta.url,
              name: 'SampleCommand',
            },
            requiresApproval: false,
          },
        ],
      });
      let { roomId } = await createAIAssistantRoomCommand.execute({
        name: 'Sample Assistant',
        enabledSkills: [sampleSkill],
      });

      let sendMessageCommand = new SendAiAssistantMessageCommand(
        commandContext,
      );
      await sendMessageCommand.execute({
        roomId,
        prompt: `Run the sample command with: ${this.args.model.title}`,
      });
    };

    <template>
      <CardContainer>
        <h1><@fields.title /></h1>
        <Button data-test-run-sample {{on 'click' this.runSample}}>
          Run Sample
        </Button>
      </CardContainer>
    </template>
  };
}
