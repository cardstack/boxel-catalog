import { Command } from '@cardstack/runtime-common';
import { RegexTesterInput } from './regex-tester-input';
import { RegexTesterResult } from './regex-tester-result';
export class RegexTesterCommand extends Command<
  typeof RegexTesterInput,
  typeof RegexTesterResult
> {
  static actionVerb = 'Test';
  static displayName = 'Test regular expression';
  async getInputType() {
    return RegexTesterInput;
  }
  protected async run(input: RegexTesterInput): Promise<RegexTesterResult> {
    const pattern = input.pattern ?? '';
    if (!pattern) throw new Error('Enter a regular expression.');
    if (pattern.length > 256)
      throw new Error('Keep the pattern under 256 characters.');
    const sample = input.sample ?? '';
    if (sample.length > 20000)
      throw new Error('Keep sample text under 20,000 characters.');
    if (/([^)]*[+*][^)]*)[+*{]/.test(pattern))
      throw new Error(
        'Nested quantifiers can be unpredictable. Simplify the expression before testing.',
      );
    let flags = Array.from(
      new Set((input.flags ?? '').replace(/[^dgimsuvy]/g, '').split('')),
    ).join('');
    if (!flags.includes('g')) flags += 'g';
    let expression: RegExp;
    try {
      expression = new RegExp(pattern, flags);
    } catch (error) {
      throw new Error(
        error instanceof Error
          ? 'Invalid regular expression: ' + error.message
          : 'Invalid regular expression.',
      );
    }
    const matches: string[] = [];
    let count = 0;
    for (const match of sample.matchAll(expression)) {
      count++;
      if (count <= 50)
        matches.push(
          count + '. index ' + match.index + ': ' + JSON.stringify(match[0]),
        );
    }
    return new RegexTesterResult({
      output: count
        ? 'Found ' +
          count +
          ' match' +
          (count === 1 ? '' : 'es') +
          (count > 50 ? ' (first 50 shown)' : '') +
          String.fromCharCode(10) +
          matches.join(String.fromCharCode(10))
        : 'No matches found.',
    });
  }
}
