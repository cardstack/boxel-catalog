import {
  FieldDef,
  Component,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import DateTimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import MessageSquareQuoteIcon from '@cardstack/boxel-icons/message-square-quote';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import type { Hue } from '@cardstack/catalog/components/state-pill';

export const ANNOTATION_KINDS = ['note', 'concern', 'question'] as const;

export const ANNOTATION_LABELS: Record<string, string> = {
  note: 'Note',
  concern: 'Concern',
  question: 'Question',
};

export const ANNOTATION_HUE: Record<string, Hue> = {
  note: 'slate',
  concern: 'amber',
  question: 'blue',
};

export const AnnotationKindField = enumField(StringField, {
  displayName: 'Annotation Kind',
  options: ANNOTATION_KINDS.map((value) => ({
    value,
    label: ANNOTATION_LABELS[value],
  })),
});

/**
 * A remark pinned to a location in something else.
 *
 * `anchor` is a plain string so one field serves every surface a reader can
 * point at: a PDF page ("p.2 ¶3"), a card field path ("severity.level"), a
 * spreadsheet cell, a source line. Typing it per surface would fork the field
 * per consumer, which is the opposite of what this row is for — it comes from
 * the BSL design records, where the annotated thing is a card.
 *
 * The kind is what makes annotations scannable. A concern raised in the margin
 * of evidence is a finding in waiting; a note is context. Same shape, and the
 * reader needs to tell them apart without reading every one.
 */
export class AnnotationField extends FieldDef {
  static displayName = 'Annotation';
  static icon = MessageSquareQuoteIcon;

  @field anchor = contains(StringField);
  @field text = contains(TextAreaField);
  @field kind = contains(AnnotationKindField);
  @field author = linksTo(() => Employee);
  @field createdAt = contains(DateTimeField);

  @field label = contains(StringField, {
    computeVia: function (this: AnnotationField) {
      return ANNOTATION_LABELS[this.kind ?? ''] ?? '';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return ANNOTATION_HUE[this.args.model?.kind ?? ''] ?? 'slate';
    }
    <template>
      <div class='annotation'>
        <div class='head'>
          {{#if @model.anchor}}
            <span class='anchor mono'>{{@model.anchor}}</span>
          {{/if}}
          <StatePill @label={{@model.label}} @hue={{this.hue}} @dot={{true}} />
          {{#if @model.author}}
            <span class='who'><@fields.author @format='atom' /></span>
          {{/if}}
        </div>
        {{#if @model.text}}
          <p class='text'>{{@model.text}}</p>
        {{/if}}
      </div>
      <style scoped>
        .annotation {
          display: grid;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs) 0;
        }
        .head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .anchor {
          font-size: 0.75rem;
          font-weight: 600;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        .who {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .text {
          margin: 0;
          font-size: 0.8125rem;
          line-height: 1.5;
          color: var(--foreground, var(--boxel-dark));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return ANNOTATION_HUE[this.args.model?.kind ?? ''] ?? 'slate';
    }
    <template>
      <span class='atom'>
        <StatePill @label={{@model.label}} @hue={{this.hue}} />
        {{#if @model.anchor}}<span
            class='a mono'
          >{{@model.anchor}}</span>{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
        }
        .a {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
      </style>
    </template>
  };
}

export default AnnotationField;
