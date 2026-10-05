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
import { Token } from '@cardstack/pretui/components/token';
import { ID_TOKEN_STYLE } from '@cardstack/catalog/components/pretui-helpers';

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
            <Token style={{ID_TOKEN_STYLE.xs}}>{{@model.anchor}}</Token>
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
        .who {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .text {
          margin: 0;
          font-size: 0.8125rem;
          line-height: 1.5;
          color: var(--foreground);
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
        {{#if @model.anchor}}<Token
            style={{ID_TOKEN_STYLE.xs}}
          >{{@model.anchor}}</Token>{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
        }
      </style>
    </template>
  };
}

export default AnnotationField;
