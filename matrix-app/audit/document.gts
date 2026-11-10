import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import { FileDef } from '@cardstack/base/file-api';
import { DocumentInfoField } from '@cardstack/base/file-formats/metadata-fields';
import Tag from '@cardstack/base/tag';
import FileTextIcon from '@cardstack/boxel-icons/file-text';
import { Stat } from '@cardstack/pretui/components/stat';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import type { TemplateOnlyComponent } from '@ember/component/template-only';

import { Employee } from '../hr/employee';
import { FitTile } from '../shared/fit-tile';
import { DocumentPreview } from './components/document-preview';
import { shortHash } from './utils/evidence-hash';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const DOCUMENT_KINDS = [
  'policy',
  'procedure',
  'record',
  'evidence',
  'report',
  'other',
] as const;

export const DOCUMENT_KIND_LABELS: Record<string, string> = {
  policy: 'Policy',
  procedure: 'Procedure',
  record: 'Record',
  evidence: 'Evidence',
  report: 'Report',
  other: 'Other',
};

export const DOCUMENT_KIND_HUE: Record<string, Hue> = {
  policy: 'purple',
  procedure: 'blue',
  record: 'teal',
  evidence: 'gold',
  report: 'pink',
  other: 'slate',
};

/** A Hue from the shared vocabularies, folded onto the theme's four status tones. */
export type Tone = 'success' | 'danger' | 'warning' | 'info' | undefined;

export function hueTone(hue?: string | null): Tone {
  switch (hue) {
    case 'green':
      return 'success';
    case 'red':
      return 'danger';
    case 'amber':
    case 'orange':
    case 'gold':
      return 'warning';
    case 'blue':
    case 'teal':
    case 'purple':
      return 'info';
    default:
      return undefined;
  }
}

const KIND_TONE: Record<string, Tone> = {
  policy: 'info',
  procedure: 'info',
  evidence: 'warning',
};

export function kindTone(kind?: string | null): Tone {
  return KIND_TONE[kind ?? ''];
}

// A neutral StatusChip hashes its dot colour; status here is grey when it has no tone.
export const Status: TemplateOnlyComponent<{
  Args: { value: string; tone?: Tone };
}> = <template>
  <StatusChip
    @value={{@value}}
    @tone={{@tone}}
    @appearance='plain'
    @hue={{unless @tone 'var(--muted-foreground)'}}
  />
</template>;

export const DocumentKindField = markDefinition(
  enumField(StringField, {
    displayName: 'Document Kind',
    options: DOCUMENT_KINDS.map((value) => ({
      value,
      label: DOCUMENT_KIND_LABELS[value],
    })),
  }),
);

const DAY = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
});
const STAMP = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
  timeZone: 'UTC',
});

function day(d?: Date | null) {
  return d ? DAY.format(new Date(d)) : '';
}
function stamp(d?: Date | null) {
  return d ? `${STAMP.format(new Date(d))} UTC` : '—';
}
function kindLabel(kind?: string | null) {
  return DOCUMENT_KIND_LABELS[kind ?? ''] ?? '—';
}
function metaLine(doc: Document) {
  return [kindLabel(doc.kind), doc.info?.subject].filter(Boolean).join(' · ');
}
function hashed(doc: Document) {
  return Boolean((doc.contentHash ?? '').trim());
}
/** "Hashed Aug 20, 2026 · 02987499…", or "Not hashed". */
function hashLine(doc: Document) {
  if (!hashed(doc)) {
    return 'Not hashed';
  }
  let when = day(doc.hashedAt);
  return `Hashed${when ? ` ${when}` : ''} · ${shortHash(doc.contentHash)}`;
}
function dash(v?: string | null) {
  return v && v.trim() ? v : '—';
}

/**
 * A document as a record: the artefact plus who owns it, which version it is,
 * and what it replaced.
 *
 * The file itself is a `linksTo(FileDef)` rather than bytes on the card, so
 * the platform's file shells do the previewing and any file family the base
 * supports works here on arrival.
 *
 * `supersedes` is why this is a card and not a field. Evidence is replaced,
 * never deleted: a superseded document stays readable from every finding that
 * cited it, which is only possible if it keeps its own identity and URL.
 *
 * `contentHash` is stamped over the file's bytes when the document is hashed.
 * Held here it is a fact about the artefact; the tamper comparison lives on
 * Proof Field, which records the hash it saw when the evidence was attached.
 */
export class Document extends CardDef {
  static displayName = 'Document';
  static icon = FileTextIcon;

  @field title = contains(StringField);
  @field kind = contains(DocumentKindField);
  @field file = linksTo(FileDef, { searchable: true });
  /** Reuse: the base file-format metadata block (page count, author, dates). */
  @field info = contains(DocumentInfoField);
  @field version = contains(StringField);
  @field owner = linksTo(() => Employee);
  @field supersedes = linksTo(() => Document);
  @field tags = linksToMany(Tag);

  /** SHA-256 of the file's bytes, lower-case hex, stamped when hashed. */
  @field contentHash = contains(StringField);
  @field hashedAt = contains(DateTimeField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Document) {
      let name = this.title ?? this.file?.name ?? 'Document';
      return this.version ? `${name} v${this.version}` : name;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get doc() {
      return this.args.model as Document;
    }
    get stats() {
      let d = this.doc;
      let prev = d.supersedes?.version;
      return [
        {
          label: 'Version',
          value: dash(d.version),
          hint: prev ? `supersedes v${prev}` : 'first version',
        },
        {
          label: 'Hash',
          value: hashed(d) ? shortHash(d.contentHash) : 'None',
          tone: hashed(d) ? 'success' : 'warning',
          hint: hashed(d)
            ? `SHA-256 · ${day(d.hashedAt) || 'date not recorded'}`
            : 'not yet evidence',
        },
        {
          label: 'Artefact',
          value: d.file ? 'Attached' : 'None',
          tone: d.file ? 'success' : undefined,
          hint: d.file
            ? (d.file.name ?? 'file linked')
            : 'no file attached yet',
        },
      ];
    }
    get hasTags() {
      return Boolean(this.doc.tags?.length);
    }
    <template>
      <article class='doc'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>Dc</span>
          <div class='id'>
            <h1>{{@model.cardTitle}}</h1>
            <p class='meta'>{{metaLine this.doc}}</p>
          </div>
          <div class='states'>
            <Status
              @value={{kindLabel @model.kind}}
              @tone={{kindTone @model.kind}}
            /><Status
              @value={{if (hashed this.doc) 'hashed' 'not hashed'}}
              @tone={{if (hashed this.doc) 'success' 'warning'}}
            />
          </div>
        </header>

        <section class='stats' aria-label='Key facts'>
          {{#each this.stats as |st|}}
            <div class='stat'>
              <Stat
                @label={{st.label}}
                @value={{st.value}}
                @tone={{st.tone}}
                @hint={{st.hint}}
                @roll={{false}}
              />
            </div>
          {{/each}}
        </section>

        <div class='cols'>
          <div class='main'>
            <section class='sec'>
              <h2>Preview</h2>
              <DocumentPreview
                @document={{@model}}
                @fileField={{@fields.file}}
                @format='embedded'
                @bare={{true}}
              />
            </section>
            <section class='sec'>
              <h2>Facts</h2>
              <dl class='kv'>
                <dt>Hashed</dt>
                <dd>{{stamp @model.hashedAt}}</dd>
                <dt>Supersedes</dt>
                <dd>{{#if @model.supersedes}}<@fields.supersedes
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
              </dl>
            </section>
            <section class='sec'>
              <h2>File metadata</h2>
              <dl class='kv'>
                <dt>Title</dt>
                <dd>{{dash @model.info.title}}</dd>
                <dt>Author</dt>
                <dd>{{dash @model.info.author}}</dd>
                <dt>Subject</dt>
                <dd>{{dash @model.info.subject}}</dd>
              </dl>
            </section>
            <section class='sec'>
              <h2>Content hash</h2>
              <p class='mono hash'>{{dash @model.contentHash}}</p>
            </section>
          </div>

          <aside class='side'>
            <section class='sec'>
              <h2>Linked</h2>
              <dl class='kv'>
                <dt>Supersedes</dt>
                <dd>{{#if @model.supersedes}}<@fields.supersedes
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
                <dt>Owner</dt>
                <dd>{{#if @model.owner}}<@fields.owner
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}not set{{/if}}</dd>
              </dl>
            </section>
            <section class='sec'>
              <h2>Details</h2>
              <dl class='kv'>
                <dt>Kind</dt>
                <dd>{{kindLabel @model.kind}}</dd>
                <dt>Version</dt>
                <dd>{{dash @model.version}}</dd>
                <dt>Content hash</dt>
                <dd class='mono'>{{if
                    (hashed this.doc)
                    (shortHash @model.contentHash)
                    '—'
                  }}</dd>
                <dt>Hashed at</dt>
                <dd>{{stamp @model.hashedAt}}</dd>
                <dt>Artefact</dt>
                <dd>{{if @model.file 'attached' 'none attached'}}</dd>
                <dt>Author</dt>
                <dd>{{dash @model.info.author}}</dd>
                <dt>Subject</dt>
                <dd>{{dash @model.info.subject}}</dd>
                <dt>Tags</dt>
                <dd>{{#if this.hasTags}}<@fields.tags
                      @format='atom'
                    />{{else}}none{{/if}}</dd>
              </dl>
            </section>
          </aside>
        </div>
      </article>
      <style scoped>
        .doc {
          margin: var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
          container-type: inline-size;
        }
        .head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .mark {
          display: grid;
          place-items: center;
          flex: none;
          inline-size: 1.75rem;
          block-size: 1.75rem;
          border-radius: var(--radius);
          background: var(--muted);
          font: 600 var(--boxel-font-size-2xs)/1 var(--font-mono);
        }
        .id {
          flex: 1;
          min-inline-size: 0;
        }
        h1 {
          margin: 0;
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
        }
        .meta {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .states {
          display: flex;
          gap: var(--boxel-sp-sm);
          font-weight: 600;
        }
        .stats {
          --text-stat: 1.375rem;
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          border-block: 1px solid var(--border);
        }
        .stat {
          min-inline-size: 0;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .stat + .stat {
          border-inline-start: 1px solid var(--border);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
        }
        .side {
          border-inline-start: 1px solid var(--border);
        }
        @container (width < 40rem) {
          .stats,
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .stat + .stat {
            border-inline-start: 0;
            border-block-start: 1px solid var(--border);
          }
          .side {
            border-inline-start: 0;
            border-block-start: 1px solid var(--border);
          }
        }
        .sec {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .sec + .sec {
          border-block-start: 1px solid var(--border);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-4xs);
          font: 600 var(--boxel-font-size-2xs)/1.3 var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .kv {
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr);
          margin: 0;
        }
        dt,
        dd {
          margin: 0;
          padding: var(--boxel-sp-4xs) 0;
          border-block-start: 1px solid var(--border);
        }
        dt {
          font: 600 var(--boxel-font-size-2xs)/1.8 var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        dd {
          display: flex;
          flex-wrap: wrap;
          min-inline-size: 0;
        }
        .mono {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
        }
        .hash {
          margin: 0;
          overflow-wrap: anywhere;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get doc() {
      return this.args.model as Document;
    }
    <template>
      <article class='emb'>
        <header>
          <span class='mark' aria-hidden='true'>Dc</span>
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p class='meta'>{{metaLine this.doc}}</p>
          </div>
        </header>
        <p class='fact'>{{hashLine this.doc}}</p>
        <dl class='kv'>
          <dt>State</dt>
          <dd class='states'>
            <Status
              @value={{kindLabel @model.kind}}
              @tone={{kindTone @model.kind}}
            /><Status
              @value={{if (hashed this.doc) 'hashed' 'not hashed'}}
              @tone={{if (hashed this.doc) 'success' 'warning'}}
            />
          </dd>
          <dt>Version</dt>
          <dd>{{dash @model.version}}</dd>
          <dt>Hashed at</dt>
          <dd>{{stamp @model.hashedAt}}</dd>
          <dt>Artefact</dt>
          <dd>{{if @model.file 'attached' 'none attached'}}</dd>
          <dt>Author</dt>
          <dd>{{dash @model.info.author}}</dd>
          <dt>Owner</dt>
          <dd>{{#if @model.owner}}<@fields.owner
                @format='atom'
                @displayContainer={{false}}
              />{{else}}not set{{/if}}</dd>
          <dt>Supersedes</dt>
          <dd>{{#if @model.supersedes}}<@fields.supersedes
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</dd>
        </dl>
      </article>
      <style scoped>
        .emb {
          display: grid;
          gap: var(--boxel-sp-4xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          background: var(--card);
          color: var(--card-foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-xs);
          line-height: 1.4;
        }
        header {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
        }
        .mark {
          display: grid;
          place-items: center;
          flex: none;
          inline-size: 1.5rem;
          block-size: 1.5rem;
          border-radius: var(--radius);
          background: var(--muted);
          font: 600 var(--boxel-font-size-2xs)/1 var(--font-mono);
        }
        .id {
          min-inline-size: 0;
        }
        h3 {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
        }
        .meta,
        .fact {
          margin: 0;
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .fact {
          font-family: var(--font-mono);
        }
        .kv {
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr);
          margin: 0;
        }
        dt,
        dd {
          margin: 0;
          padding: var(--boxel-sp-4xs) 0;
          border-block-start: 1px solid var(--border);
        }
        dt {
          font: 600 var(--boxel-font-size-2xs)/1.8 var(--font-mono);
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        dd {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          min-inline-size: 0;
        }
        .states {
          font-weight: 600;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'><span class='mark' aria-hidden='true'>Dc</span><span
          class='name'
        >{{@model.cardTitle}}</span></span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          max-inline-size: 100%;
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
        .mark {
          flex: none;
          padding: 0 var(--boxel-sp-5xs);
          border-radius: var(--radius);
          background: var(--muted);
          font: 600 var(--boxel-font-size-2xs)/1.6 var(--font-mono);
        }
        .name {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get doc() {
      return this.args.model as Document;
    }
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>Dc</span></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{metaLine this.doc}}</:subtitle>
        <:status><Status
            @value={{kindLabel @model.kind}}
            @tone={{kindTone @model.kind}}
          /><Status
            @value={{if (hashed this.doc) 'hashed' 'not hashed'}}
            @tone={{if (hashed this.doc) 'success' 'warning'}}
          /></:status>
        <:fact><span class='mono'>{{hashLine this.doc}}</span></:fact>
        <:relations>{{#if @model.supersedes}}<@fields.supersedes
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
      <style scoped>
        .mark {
          display: inline-grid;
          place-items: center;
          inline-size: 2rem;
          block-size: 2rem;
          border-radius: var(--radius);
          background: var(--muted);
          font: 600 var(--boxel-font-size-2xs)/1 var(--font-mono);
        }
        .mono {
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };
}

export default Document;
