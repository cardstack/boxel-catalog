import {
  Component,
  FieldDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import SigmaIcon from '@cardstack/boxel-icons/sigma';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { ExpressionField } from '../expression/expression-field';

// Compiles is not yet proven against a subject, so it reads as information,
// not success.
const STATUS_HUE: Record<string, Hue> = {
  Empty: 'slate',
  Compiles: 'blue',
  Error: 'red',
};

function statusHue(status: string): Hue {
  return STATUS_HUE[status] ?? 'slate';
}

/**
 * A named, author-editable derivation.
 *
 * A FieldDef cannot reach the card that holds it, so the owning card supplies
 * itself at the one call site:
 *
 *   @field projectedTotal = contains(NumberField, {
 *     computeVia: function (this: Invoice) {
 *       return this.annualised?.valueFor(this);
 *     },
 *   });
 */
export class FormulaField extends FieldDef {
  static displayName = 'Formula';
  static icon = SigmaIcon;

  @field label = contains(StringField, {
    description: 'What the formula produces, in the reader’s words.',
  });

  @field expression = contains(ExpressionField);

  @field status = contains(StringField, {
    computeVia: function (this: FormulaField) {
      if (!this.expression?.source?.trim()) {
        return 'Empty';
      }
      return this.expression.error ? 'Error' : 'Compiles';
    },
  });

  valueFor(subject: object): unknown {
    return this.expression?.evaluateAgainst(subject);
  }

  errorFor(subject: object): string {
    return this.expression?.evaluate(subject).error ?? 'No expression.';
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='formula'>
        <div class='head'>
          <span class='label'>{{if
              @model.label
              @model.label
              'Untitled formula'
            }}</span>
          {{#if @model.status}}
            <StatePill
              @label={{@model.status}}
              @hue={{statusHue @model.status}}
              @dot={{true}}
            />
          {{/if}}
        </div>
        <@fields.expression />
      </div>
      <style scoped>
        .formula {
          display: grid;
          gap: var(--boxel-sp-xxs);
        }
        .head {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        .label {
          font-weight: 600;
        }
      </style>
    </template>
  };
}
