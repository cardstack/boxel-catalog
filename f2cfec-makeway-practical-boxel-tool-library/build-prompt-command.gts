import { Command } from '@cardstack/runtime-common';
import { BuildPromptInput } from './build-prompt-input';
import { BuildPromptResult } from './build-prompt-result';
export class BuildPromptCommand extends Command<
  typeof BuildPromptInput,
  typeof BuildPromptResult
> {
  static actionVerb = 'Build';
  static displayName = 'Build a coding prompt';
  async getInputType() {
    return BuildPromptInput;
  }
  protected async run(input: BuildPromptInput): Promise<BuildPromptResult> {
    const goal = (input.goal ?? '').trim();
    if (!goal)
      throw new Error('Add a short description of what you want to build.');
    const nl = String.fromCharCode(10);
    const parts = ['Help me build this project.', '', 'GOAL', goal];
    if (input.audience?.trim())
      parts.push('', 'WHO IT IS FOR', input.audience.trim());
    if (input.mustHave?.trim())
      parts.push('', 'MUST-HAVE FEATURES', input.mustHave.trim());
    if (input.feel?.trim())
      parts.push('', 'DESIGN DIRECTION', input.feel.trim());
    parts.push(
      '',
      'HOW TO WORK WITH ME',
      '- Restate the goal and list important assumptions.',
      '- Ask one question at a time when a missing detail changes the solution.',
      '- Suggest a small first version before expanding scope.',
      '- Explain unfamiliar technical terms in plain language.',
      '- Verify changes before saying they work; explain errors and the next action.',
    );
    return new BuildPromptResult({ output: parts.join(nl) });
  }
}
