import {
  Component,
  FieldDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import CircleCheckIcon from '@cardstack/boxel-icons/circle-check';

/**
 * One selectable answer in a closed question — the Standards-layer
 * **Choice Option** block. Generic on purpose: a quiz reads `isCorrect`, a
 * survey ignores it, a poll counts `value`s. `value` is the stable key stored
 * in an answer; `label` is what the respondent sees and may be reworded
 * without invalidating recorded answers.
 */
export class ChoiceOptionField extends FieldDef {
  static displayName = 'Choice Option';
  static icon = CircleCheckIcon;

  @field label = contains(StringField);
  @field value = contains(StringField, {
    description: 'Stable key recorded in answers. Defaults to the label.',
  });
  @field isCorrect = contains(BooleanField, {
    description: 'Only meaningful for scored questions.',
  });
  @field feedback = contains(StringField, {
    description:
      'Shown to the respondent after answering, if the consumer chooses.',
  });

  @field key = contains(StringField, {
    computeVia: function (this: ChoiceOptionField): string {
      return optionKey(this);
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='opt {{if @model.isCorrect "correct"}}'>
        <span class='opt-mark' aria-hidden='true'></span>
        <span class='opt-label'>{{@model.label}}</span>
        {{#if @model.isCorrect}}
          <span class='opt-tag'>correct</span>
        {{/if}}
      </span>
      <style scoped>
        .opt {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground, var(--boxel-dark));
        }
        .opt-mark {
          width: 0.75rem;
          height: 0.75rem;
          border-radius: 50%;
          border: 1.5px solid var(--border, var(--boxel-300));
          flex: none;
        }
        .correct .opt-mark {
          background: var(--boxel-success);
          border-color: var(--boxel-success);
        }
        .opt-tag {
          font-size: var(--boxel-font-size-xs);
          color: color-mix(
            in oklab,
            var(--boxel-success) 45%,
            var(--card-foreground, var(--boxel-dark))
          );
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='opt-atom'>{{@model.label}}{{#if @model.isCorrect}}
          ✓{{/if}}</span>
      <style scoped>
        .opt-atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export function optionKey(
  o: { value?: string | null; label?: string | null } | null | undefined,
): string {
  return (o?.value?.trim() || o?.label?.trim() || '').toLowerCase();
}

export default ChoiceOptionField;
