import { Command } from '@cardstack/runtime-common';
import { CleanTextInput } from './clean-text-input';
import { CleanTextResult } from './clean-text-result';
export class CleanTextCommand extends Command<
  typeof CleanTextInput,
  typeof CleanTextResult
> {
  static actionVerb = 'Clean';
  static displayName = 'Clean Text';
  async getInputType() {
    return CleanTextInput;
  }
  protected async run(input: CleanTextInput): Promise<CleanTextResult> {
    const nl = String.fromCharCode(10);
    const lines = (input.source ?? '')
      .split(String.fromCharCode(13))
      .join('')
      .split(nl)
      .map((line) => line.replace(/[ \t]+$/g, ''));
    const cleaned: string[] = [];
    let blankRun = 0;
    for (const line of lines) {
      if (!line.trim()) {
        blankRun++;
        if (blankRun <= 2) cleaned.push('');
      } else {
        blankRun = 0;
        cleaned.push(line);
      }
    }
    const result = cleaned.join(nl).trim();
    return new CleanTextResult({ output: result || 'No text to clean.' });
  }
}
