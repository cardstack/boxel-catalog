import { Command } from '@cardstack/runtime-common';
import { MarkdownOutlineInput } from './markdown-outline-input';
import { MarkdownOutlineResult } from './markdown-outline-result';
export class MarkdownOutlineCommand extends Command<
  typeof MarkdownOutlineInput,
  typeof MarkdownOutlineResult
> {
  static actionVerb = 'Outline';
  static displayName = 'Outline Markdown';
  async getInputType() {
    return MarkdownOutlineInput;
  }
  protected async run(
    input: MarkdownOutlineInput,
  ): Promise<MarkdownOutlineResult> {
    const nl = String.fromCharCode(10);
    const source = (input.source ?? '').split(String.fromCharCode(13)).join('');
    const lines = source.split(nl);
    const headings: string[] = [];
    let inFence = false;
    for (const line of lines) {
      const trimmed = line.trimStart();
      if (
        trimmed.startsWith('~~~') ||
        trimmed.startsWith(String.fromCharCode(96).repeat(3))
      ) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      let start = 0;
      while (start < line.length && line[start] === ' ' && start < 4) start++;
      if (start > 3) continue;
      let level = 0;
      while (line[start + level] === '#') level++;
      if (
        level < 1 ||
        level > 6 ||
        (line[start + level] !== ' ' &&
          line[start + level] !== String.fromCharCode(9))
      )
        continue;
      let title = line.slice(start + level).trim();
      while (title.endsWith('#')) title = title.slice(0, -1).trimEnd();
      if (title) headings.push('  '.repeat(level - 1) + '- ' + title);
    }
    return new MarkdownOutlineResult({
      output: headings.length
        ? headings.join(nl)
        : 'No Markdown headings found outside code fences.',
    });
  }
}
