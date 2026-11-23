import { Command } from '@cardstack/runtime-common';
import { UTMBuilderInput } from './utm-builder-input';
import { UTMBuilderResult } from './utm-builder-result';
export class UTMBuilderCommand extends Command<
  typeof UTMBuilderInput,
  typeof UTMBuilderResult
> {
  static actionVerb = 'Build';
  static displayName = 'Build a UTM campaign URL';
  async getInputType() {
    return UTMBuilderInput;
  }
  protected async run(input: UTMBuilderInput): Promise<UTMBuilderResult> {
    const raw = (input.url ?? '').trim();
    if (!raw) throw new Error('Enter the destination URL.');
    let destination: URL;
    try {
      destination = new URL(raw);
    } catch {
      throw new Error('Enter a complete URL, including https://.');
    }
    if (destination.protocol !== 'https:' && destination.protocol !== 'http:')
      throw new Error('Use an http or https destination URL.');
    const required: Array<[string, string]> = [
      ['utm_source', input.source ?? ''],
      ['utm_medium', input.medium ?? ''],
      ['utm_campaign', input.campaign ?? ''],
    ];
    if (required.some((entry) => !entry[1].trim()))
      throw new Error('Source, medium, and campaign are required.');
    const optional: Array<[string, string]> = [
      ['utm_term', input.term ?? ''],
      ['utm_content', input.content ?? ''],
    ];
    for (const [key, value] of [...required, ...optional])
      if (value.trim()) destination.searchParams.set(key, value.trim());
    return new UTMBuilderResult({ output: destination.toString() });
  }
}
