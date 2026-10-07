import {
  FieldDef,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { Component } from '@cardstack/base/card-api';

/**
 * One heading in a document.
 *
 * ### The gap
 *
 * `MarkdownFileDef` carries `title`, `excerpt`, `content`, `frontmatter`,
 * `cardReferenceUrls`, `linkedCards`, `fileReferenceUrls` and `linkedFiles` —
 * and no headings. So a long document can be linked, embedded and searched,
 * but never outlined: nothing knows it has sections.
 *
 * ### `slug` is the anchor contract
 *
 * Produced by `slugify` in `utils/file-metadata`, which mirrors the GitHub
 * algorithm closely enough that a `#some-heading` link written against
 * markdown rendered anywhere else resolves here. That compatibility is the
 * whole reason to match an existing algorithm rather than invent a cleaner
 * one — an anchor that only works inside one renderer is not an anchor.
 *
 * Duplicates are disambiguated through `uniqueSlug`: the second "Overview"
 * becomes `overview-1`, the way anchor generators do.
 *
 * ### `charOffset` rather than a line number
 *
 * Markdown is edited as a character stream, and a line number is invalidated
 * by any reflow above it. An offset survives wrapping and is what a "jump to
 * section" action can actually seek to.
 */
export class HeadingField extends FieldDef {
  static displayName = 'Heading';

  @field level = contains(NumberField, {
    description: '1–6, as written. Not normalised — the document’s own shape.',
  });
  @field text = contains(StringField);
  @field slug = contains(StringField, {
    description:
      'URL anchor, GitHub-compatible, de-duplicated across the document.',
  });
  @field charOffset = contains(NumberField, {
    description:
      'Character index of the heading in the source. Survives reflow; a line number does not.',
  });

  // Depth relative to the document's own top level, filled by the extractor.
  // A document whose highest heading is h2 should still read as starting at
  // depth 0 — otherwise every outline of it renders indented for no reason.
  @field depth = contains(NumberField);

  @field label = contains(StringField, {
    computeVia: function (this: HeadingField) {
      return this.text?.trim() || `Untitled h${this.level ?? 1}`;
    },
  });

  @field anchor = contains(StringField, {
    computeVia: function (this: HeadingField) {
      return this.slug ? `#${this.slug}` : '';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='h'>
        <span class='lvl'>h{{@model.level}}</span>
        <span class='txt'>{{@model.label}}</span>
        {{#if @model.slug}}<span class='slug'>{{@model.anchor}}</span>{{/if}}
      </div>
      <style scoped>
        .h {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xxs);
          color: var(--foreground, var(--boxel-dark));
        }
        .lvl {
          flex: none;
          font: 600 var(--boxel-font-xs);
          font-family: var(--font-mono, monospace);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .txt {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font: var(--boxel-font-sm);
        }
        .slug {
          flex: none;
          font: var(--boxel-font-xs);
          font-family: var(--font-mono, monospace);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

export default HeadingField;
