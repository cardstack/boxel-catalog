import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import TextAreaField from '@cardstack/base/text-area';
import enumField from '@cardstack/base/enum';
import Link2Icon from '@cardstack/boxel-icons/link-2';

export const RELATION_KINDS = [
  'duplicate-of',
  'caused-by',
  'blocks',
  'blocked-by',
  'related-to',
  'follows-up',
] as const;

export const RelationKindField = enumField(StringField, {
  displayName: 'Relation Kind',
  options: RELATION_KINDS as unknown as string[],
});

/**
 * One typed link between this record and another card. The type is data —
 * "related" alone is useless at scale; "duplicate-of" is a query.
 *
 * A FieldDef cannot `linksTo`, so the target is stored as card id + display
 * title, written by the UI action that created the relation. Nothing here
 * names a domain type: the target may be a Case, an Incident, or a Spec.
 */
export class RelationEntryField extends FieldDef {
  static displayName = 'Relation';
  static icon = Link2Icon;

  @field kind = contains(RelationKindField);
  @field targetId = contains(StringField, {
    description: 'Card id of the related record.',
  });
  @field targetTitle = contains(StringField);
  @field note = contains(TextAreaField);
  @field createdByName = contains(StringField);
  @field createdAt = contains(DateTimeField);

  @field title = contains(StringField, {
    computeVia: function (this: RelationEntryField) {
      if (!this.kind && !this.targetTitle) return 'Relation';
      return `${this.kind ?? 'related-to'} ${this.targetTitle ?? ''}`.trim();
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='rel'>
        <span class='rel-kind'>{{if
            @model.kind
            @model.kind
            'related-to'
          }}</span>
        <span class='rel-target'>{{if
            @model.targetTitle
            @model.targetTitle
            '—'
          }}</span>
      </span>
      <style scoped>
        .rel {
          display: inline-flex;
          align-items: baseline;
          gap: var(--boxel-sp-4xs);
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: var(--boxel-border-radius-sm);
          padding: 0.125rem 0.5rem;
          font-size: var(--boxel-font-size-xs);
          max-width: 100%;
        }
        .rel-kind {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
        }
        .rel-target {
          font-weight: 500;
          color: var(--foreground, var(--boxel-dark));
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='rel-atom'>{{if @model.kind @model.kind 'related-to'}}
        {{if @model.targetTitle @model.targetTitle '—'}}</span>
      <style scoped>
        .rel-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

/**
 * The typed relations a record carries. Kept as one compound field so a host
 * card adds a single `@field relationships = contains(RelationshipSetField)`
 * and every consumer renders the same chips.
 */
export class RelationshipSetField extends FieldDef {
  static displayName = 'Relationship Set';
  static icon = Link2Icon;

  @field relations = containsMany(RelationEntryField);

  @field title = contains(StringField, {
    computeVia: function (this: RelationshipSetField) {
      let n = this.relations?.length ?? 0;
      return n === 0 ? 'No relations' : `${n} relation${n === 1 ? '' : 's'}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      {{#if @model.relations.length}}
        <div class='relset'><@fields.relations /></div>
      {{else}}
        <span class='relset-none'>No linked records</span>
      {{/if}}
      <style scoped>
        .relset {
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .relset :deep(.containsMany-field) {
          display: contents;
        }
        .relset-none {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='relset-atom'>{{@model.title}}</span>
      <style scoped>
        .relset-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };
}

export default RelationshipSetField;
