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

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { StatePill } from '@cardstack/catalog/components/state-pill';
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
  evidence: 'amber',
  report: 'green',
  other: 'slate',
};

export const DocumentKindField = enumField(StringField, {
  displayName: 'Document Kind',
  options: DOCUMENT_KINDS.map((value) => ({
    value,
    label: DOCUMENT_KIND_LABELS[value],
  })),
});

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
    get kindLabel() {
      return DOCUMENT_KIND_LABELS[this.args.model?.kind ?? ''] ?? '';
    }
    get kindHue() {
      return DOCUMENT_KIND_HUE[this.args.model?.kind ?? ''] ?? 'slate';
    }
    get tagList() {
      return (this.args.model?.tags ?? []).filter(Boolean);
    }
    <template>
      <article class='doc'>
        <header>
          <p class='kicker'>{{this.kindLabel}}</p>
          <h1>{{@model.title}}</h1>
          <div class='head-meta'>
            <StatePill @label={{this.kindLabel}} @hue={{this.kindHue}} />
            {{#if @model.version}}
              <span class='meta'>version {{@model.version}}</span>
            {{/if}}
            {{#if @model.owner}}
              <span class='meta'>owner
                <@fields.owner @format='atom' /></span>
            {{/if}}
          </div>
        </header>

        <DocumentPreview
          @document={{@model}}
          @fileField={{@fields.file}}
          @format='embedded'
        />

        {{#if this.tagList.length}}
          <div class='tags'><@fields.tags @format='atom' /></div>
        {{/if}}

        <section class='facts'>
          {{#if @model.hashedAt}}
            <div class='fact'>
              <span class='k'>Hashed</span>
              <span class='v'><@fields.hashedAt /></span>
            </div>
          {{/if}}
          {{#if @model.supersedes}}
            <div class='fact'>
              <span class='k'>Supersedes</span>
              <span class='v'><@fields.supersedes @format='atom' /></span>
            </div>
          {{/if}}
        </section>

        {{#if @model.info}}
          <section>
            <h2>File metadata</h2>
            <@fields.info />
          </section>
        {{/if}}
      </article>
      <style scoped>
        .doc {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          max-width: 52rem;
          color: var(--foreground, var(--boxel-dark));
        }
        header {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .kicker {
          margin: 0;
          font-size: 0.6875rem;
          font-weight: 700;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        h1 {
          margin: 0;
          font-size: 1.5rem;
          font-family: var(--font-heading, inherit);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: 0.75rem;
          font-weight: 700;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .head-meta {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: 0.8125rem;
        }
        .meta {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .tags {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
        .facts {
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .fact {
          display: grid;
          grid-template-columns: 7rem 1fr;
          gap: var(--boxel-sp-sm);
          align-items: baseline;
          font-size: 0.875rem;
        }
        .k {
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get kindLabel() {
      return DOCUMENT_KIND_LABELS[this.args.model?.kind ?? ''] ?? '';
    }
    get kindHue() {
      return DOCUMENT_KIND_HUE[this.args.model?.kind ?? ''] ?? 'slate';
    }
    get hashLabel() {
      return shortHash(this.args.model?.contentHash);
    }
    <template>
      <div class='row'>
        <div class='what'>
          <span class='name'>{{@model.cardTitle}}</span>
          <span class='sub mono'>{{if
              this.hashLabel
              this.hashLabel
              'not hashed'
            }}</span>
        </div>
        <StatePill @label={{this.kindLabel}} @hue={{this.kindHue}} />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .what {
          display: flex;
          flex-direction: column;
          gap: 2px;
          min-width: 0;
        }
        .name {
          font-weight: 600;
          font-size: 0.9375rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: 0.8125rem;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get kindLabel() {
      return DOCUMENT_KIND_LABELS[this.args.model?.kind ?? ''] ?? '';
    }
    get hashLabel() {
      return shortHash(this.args.model?.contentHash);
    }
    get artefactLabel() {
      return this.args.model?.file ? 'artefact attached' : 'no artefact';
    }
    get versionLabel() {
      let v = this.args.model?.version;
      return v ? `Version ${v}` : null;
    }
    get supersedesLabel() {
      let t = this.args.model?.supersedes?.cardTitle;
      return t ? `Supersedes ${t}` : null;
    }

    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.cardTitle}}</span>
        <span class='fit-kind'>{{this.kindLabel}}</span>

        <div class='tier-tile'>
          <span class='row mono'>{{if
              this.hashLabel
              this.hashLabel
              'not hashed'
            }}</span>
          <span class='row'>{{this.artefactLabel}}</span>
        </div>

        <div class='tier-card'>
          {{#if this.versionLabel}}
            <span class='row'>{{this.versionLabel}}</span>
          {{/if}}
          {{#if this.supersedesLabel}}
            <span class='row clamp'>{{this.supersedesLabel}}</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        /* Progressive: a badge shows what it is, a tile adds the evidence
           facts, a card adds the version chain. Every tier ADDS — none of
           them leaves the box mostly empty, which is what a bottom-pinned
           single line was doing at tile size. */
        .fit {
          height: 100%;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-name {
          font-weight: 600;
          font-size: 0.9375rem;
          line-height: 1.2;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .fit-kind,
        .row {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .clamp {
          white-space: normal;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        .tier-tile,
        .tier-card {
          display: none;
          flex-direction: column;
          gap: 2px;
          min-height: 0;
        }
        .tier-tile {
          margin-top: auto;
          padding-top: var(--boxel-sp-5xs);
          border-top: 1px solid var(--border-subtle, var(--border, #f3f4f6));
        }
        @container fitted-card (height <= 65px) {
          .fit {
            flex-direction: row;
            align-items: center;
            gap: var(--boxel-sp-xs);
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (height > 120px) {
          .tier-tile {
            display: flex;
          }
        }
        @container fitted-card (height > 210px) {
          .tier-card {
            display: flex;
          }
        }
        @container fitted-card (width > 400px) and (height > 120px) {
          .tier-card {
            display: flex;
          }
        }
      </style>
    </template>
  };
}

export default Document;
