import {
  FieldDef,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import { Component } from '@cardstack/base/card-api';

import { formatBytes } from '../../utils/file-metadata';

/**
 * The facts about a directory — not its contents.
 *
 * ### Why this is not the file tree
 *
 * The host already has `DirectoryResource` (`host/app/resources/directory.ts`),
 * which yields live `Entry { name, kind: 'directory' | 'file', path }` rows for
 * code mode's file tree, and `DirectoryViewRefresher` keeps it current. That is
 * **UI plumbing**: an Ember Resource that subscribes and re-renders.
 *
 * This is a **data model** — the aggregate facts a card can store, sort by and
 * show without subscribing to anything: how much is in there, how big, when it
 * last changed, what kinds of thing it holds.
 *
 * The two are complementary, and the vocabulary is deliberately shared: `path`,
 * `name`, and the `'directory' | 'file'` split all mirror `Entry`, so a realm
 * card and code mode never describe the same directory in two dialects.
 *
 * ### Counts are stored, not computed
 *
 * A directory's contents are not reachable from a field — there is no
 * `DirectoryDef` to walk, and a field must not go fetching. So the counts are
 * written by whatever produced them (a scan, an import, a sync) and this field
 * only derives presentation from them. `scannedAt` is therefore load-bearing:
 * it is the only thing telling a reader how stale these numbers are.
 */
export class DirectoryMetadataField extends FieldDef {
  static displayName = 'Directory Metadata';

  @field path = contains(StringField, {
    description: 'Realm-relative path, matching the host Entry vocabulary.',
  });
  @field name = contains(StringField, {
    description: 'The last path segment, when a display name is wanted.',
  });

  @field fileCount = contains(NumberField);
  @field subdirectoryCount = contains(NumberField);
  @field totalBytes = contains(NumberField, {
    description: 'Sum over the files counted. Blank means not measured.',
  });
  @field deepestNesting = contains(NumberField, {
    description: 'Levels below this directory; 0 means flat.',
  });

  // Extensions present, most common first. A list rather than a map because
  // the order is the information — "mostly .gts, some .json" is what a reader
  // wants, and a map would make them sort it themselves.
  @field kinds = containsMany(StringField, {
    description: 'File extensions present, most common first.',
  });

  @field lastModified = contains(DateTimeField);
  @field scannedAt = contains(DateTimeField, {
    description:
      'When these counts were taken. Without it the numbers have no shelf life.',
  });

  @field entryCount = contains(NumberField, {
    computeVia: function (this: DirectoryMetadataField) {
      return (this.fileCount ?? 0) + (this.subdirectoryCount ?? 0);
    },
  });

  @field sizeLabel = contains(StringField, {
    computeVia: function (this: DirectoryMetadataField) {
      return formatBytes(this.totalBytes);
    },
  });

  // "12 files · 3 folders · 4.2 MB", with empty parts dropped rather than
  // rendered as zeros — a directory whose size was never measured should not
  // claim to be 0 B.
  @field summary = contains(StringField, {
    computeVia: function (this: DirectoryMetadataField) {
      let parts: string[] = [];
      if (this.fileCount) {
        parts.push(`${this.fileCount} file${this.fileCount === 1 ? '' : 's'}`);
      }
      if (this.subdirectoryCount) {
        parts.push(
          `${this.subdirectoryCount} folder${this.subdirectoryCount === 1 ? '' : 's'}`,
        );
      }
      let size = formatBytes(this.totalBytes);
      if (size) {
        parts.push(size);
      }
      return parts.join(' · ') || 'Empty';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='dir'>
        <span class='name'>{{if @model.name @model.name @model.path}}</span>
        <span class='sum'>{{@model.summary}}</span>
        {{! scannedAt is the only thing giving these counts a shelf life —
          a directory card asserting freshness it cannot back up is worse
          than one that admits it does not know. }}
        {{#if @model.scannedAt}}
          <span class='when'>scanned <@fields.scannedAt /></span>
        {{else}}
          <span class='stale'>never scanned</span>
        {{/if}}
      </div>
      <style scoped>
        .dir {
          display: flex;
          flex-direction: column;
          gap: 1px;
          color: var(--foreground);
        }
        .name {
          font: 600 var(--boxel-font-sm);
          font-family: var(--font-mono);
        }
        .sum {
          font: var(--boxel-font-xs);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
        .when {
          font: var(--boxel-font-xs);
          color: var(--muted-foreground);
        }
        .stale {
          font: var(--boxel-font-xs);
          color: var(--attention-ink);
        }
      </style>
    </template>
  };
}

export default DirectoryMetadataField;
