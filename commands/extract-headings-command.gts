import {
  CardDef,
  contains,
  containsMany,
  field,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';

import { HeadingField } from '../fields/heading/heading-field';

function slugify(text?: string | null): string {
  if (!text) {
    return '';
  }
  return text
    .toLowerCase()
    .trim()
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .replace(/\s+/g, '-')
    .replace(/-{2,}/g, '-')
    .replace(/^-|-$/g, '');
}

function uniqueSlug(base: string, seen: Set<string>): string {
  if (!base) {
    return '';
  }
  if (!seen.has(base)) {
    seen.add(base);
    return base;
  }
  let n = 1;
  while (seen.has(`${base}-${n}`)) {
    n++;
  }
  let slug = `${base}-${n}`;
  seen.add(slug);
  return slug;
}

export class ExtractHeadingsInput extends CardDef {
  @field markdown = contains(StringField, {
    description: 'The document source. The command never fetches anything.',
  });
  @field maxLevel = contains(NumberField, {
    description: 'Deepest level to include, 1–6. Defaults to 6 (all).',
  });
  @field includeSetext = contains(BooleanField, {
    description:
      'Also read underlined (setext) h1/h2. Off by default — rare, and the underline is easy to confuse with a table rule.',
  });
}

export class ExtractHeadingsResult extends CardDef {
  @field headings = containsMany(HeadingField);
  @field count = contains(NumberField);
  @field topLevel = contains(NumberField, {
    description: 'The document’s own highest heading level.',
  });
  @field message = contains(StringField);
}

// Fenced blocks, so a `# comment` inside a code sample is never read as a
// heading. Both backtick and tilde fences, any length ≥ 3, with the closing
// fence required to be at least as long as the opening one — that is what
// lets a ```` ``` ```` appear inside a ~~~~ block.
const FENCE_RE = /^(\s*)(`{3,}|~{3,})/;

// ATX heading: 1–6 hashes, a space, then the text. Trailing hashes are
// decoration and are stripped. A hash with no space after it is not a
// heading — `#hashtag` stays text, per CommonMark.
const ATX_RE = /^(#{1,6})\s+(.*?)\s*#*\s*$/;

/**
 * Read a markdown document's headings into an outline.
 *
 * ### Why a command and not an extractor on the FileDef
 *
 * The tracker files this row under Tools & Commands. The natural home for
 * extraction in this platform is `extractAttributes` on the FileDef — but
 * that lives in `packages/base`, and `MarkdownFileDef` would have to gain a
 * `headings` field there.
 *
 * This command is the part that does not require touching base: it takes
 * markdown as a string, so it works on a file's `content`, on a text field,
 * on a pasted draft, or on anything else that is markdown. When the base
 * field eventually lands, the same `slugify`/`uniqueSlug` helpers should
 * produce it, so the anchors stay identical on both paths.
 *
 * ### Fenced code is stripped first
 *
 * Without this, every `# comment` line in a shell example becomes an h1 and
 * a document's outline is dominated by its code samples. This is the single
 * most common bug in naive heading extractors.
 */
export class ExtractHeadingsCommand extends Command<
  typeof ExtractHeadingsInput,
  typeof ExtractHeadingsResult
> {
  static actionVerb = 'Extract';
  static displayName = 'Extract Headings';

  async getInputType() {
    return ExtractHeadingsInput;
  }

  protected async run(
    input: ExtractHeadingsInput,
  ): Promise<ExtractHeadingsResult> {
    let src = input.markdown ?? '';
    if (!src.trim()) {
      return new ExtractHeadingsResult({
        headings: [],
        count: 0,
        message: 'No markdown supplied — nothing to outline.',
      });
    }

    let maxLevel = Math.min(Math.max(input.maxLevel ?? 6, 1), 6);
    let lines = src.split('\n');
    let seen = new Set<string>();
    let found: { level: number; text: string; slug: string; offset: number }[] =
      [];

    let offset = 0;
    let fence: string | undefined;

    for (let i = 0; i < lines.length; i++) {
      let line = lines[i];
      let lineStart = offset;
      offset += line.length + 1;

      // Fence tracking. A closing fence must be at least as long as the one
      // that opened the block, so a shorter fence inside stays content.
      let fenceMatch = line.match(FENCE_RE);
      if (fenceMatch) {
        let marker = fenceMatch[2];
        if (!fence) {
          fence = marker;
          continue;
        }
        if (marker[0] === fence[0] && marker.length >= fence.length) {
          fence = undefined;
        }
        continue;
      }
      if (fence) {
        continue;
      }

      let atx = line.match(ATX_RE);
      if (atx) {
        let level = atx[1].length;
        let text = atx[2].trim();
        if (!text || level > maxLevel) {
          continue;
        }
        found.push({
          level,
          text,
          slug: uniqueSlug(slugify(text), seen),
          offset: lineStart,
        });
        continue;
      }

      // Setext: the text is the PREVIOUS line, so this branch looks back.
      // Off by default because `---` under a line is also how a table rule
      // and a frontmatter close are written.
      if (input.includeSetext && i > 0) {
        let underline = line.trim();
        let isSetext =
          (/^=+$/.test(underline) || /^-+$/.test(underline)) &&
          underline.length >= 2;
        let prev = lines[i - 1]?.trim();
        if (isSetext && prev && !prev.startsWith('#')) {
          let level = underline[0] === '=' ? 1 : 2;
          if (level <= maxLevel) {
            found.push({
              level,
              text: prev,
              slug: uniqueSlug(slugify(prev), seen),
              offset: lineStart - (lines[i - 1].length + 1),
            });
          }
        }
      }
    }

    // Depth is relative to the document's own top level. A document whose
    // highest heading is h2 starts at depth 0, so an outline of it is not
    // indented for no reason.
    let topLevel = found.length
      ? Math.min(...found.map((h) => h.level))
      : undefined;

    let headings = found.map(
      (h) =>
        new HeadingField({
          level: h.level,
          text: h.text,
          slug: h.slug,
          charOffset: h.offset,
          depth: topLevel == null ? 0 : h.level - topLevel,
        }),
    );

    return new ExtractHeadingsResult({
      headings,
      count: headings.length,
      topLevel,
      message: headings.length
        ? `Found ${headings.length} heading${headings.length === 1 ? '' : 's'}, starting at h${topLevel}.`
        : 'No headings found. Fenced code blocks are skipped, so a document whose only hashes are inside code samples correctly outlines as empty.',
    });
  }
}

export default ExtractHeadingsCommand;
