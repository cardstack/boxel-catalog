import {
  Component,
  FieldDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import SigmaIcon from '@cardstack/boxel-icons/sigma';
import { ExpressionField } from '../expression/expression-field';

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
          <span
            class='status'
            data-status={{@model.status}}
          >{{@model.status}}</span>
        </div>
        <@fields.expression />
      </div>
      <style scoped>
        .formula {
          display: grid;
          gap: var(--boxel-sp-xxs, 0.25rem);
        }
        .head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs, 0.5rem);
        }
        .label {
          font-weight: 600;
        }
        .status {
          font-size: 0.6875rem;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--boxel-450, #6b7683);
        }
        .status[data-status='Error'] {
          color: var(--boxel-danger, #a83f3f);
        }
        .status[data-status='Ready'] {
          color: var(--boxel-success, #3f7a5e);
        }
      </style>
    </template>
  };
}
