import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import CalculatorIcon from '@cardstack/boxel-icons/calculator';
import { FormulaField } from '../formula-field';

/**
 * Exercises a stored formula against the card holding it. The `computeVia`
 * below is the whole integration contract: a FieldDef cannot reach its owner,
 * so the card passes itself.
 */
export class FormulaSandbox extends CardDef {
  static displayName = 'Formula Sandbox';
  static icon = CalculatorIcon;

  @field amount = contains(NumberField);
  @field rate = contains(NumberField);
  @field recurring = contains(BooleanField);

  @field formula = contains(FormulaField);

  @field result = contains(StringField, {
    computeVia: function (this: FormulaSandbox) {
      let value = this.formula?.valueFor(this);
      return value === undefined || value === null ? '' : String(value);
    },
  });

  @field resultError = contains(StringField, {
    computeVia: function (this: FormulaSandbox) {
      if (!this.formula?.expression?.source?.trim()) {
        return '';
      }
      return this.formula.errorFor(this);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: FormulaSandbox) {
      return this.cardInfo?.name ?? this.formula?.label ?? 'Formula Sandbox';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    <template>
      <section class='sandbox'>
        <h2><@fields.cardTitle /></h2>
        <dl class='inputs'>
          <div><dt>Amount</dt><dd><@fields.amount /></dd></div>
          <div><dt>Rate</dt><dd><@fields.rate /></dd></div>
          <div><dt>Recurring</dt><dd><@fields.recurring /></dd></div>
        </dl>
        <@fields.formula />
        <p class='result'>
          <span class='rl'>Result</span>
          <span class='rv'>{{if @model.result @model.result '—'}}</span>
        </p>
        {{#if @model.resultError}}
          <p class='rerr'>{{@model.resultError}}</p>
        {{/if}}
      </section>
      <style scoped>
        .sandbox {
          display: grid;
          gap: var(--boxel-sp, 1rem);
          padding: var(--boxel-sp, 1rem);
        }
        h2 {
          margin: 0;
          font-size: 1.125rem;
        }
        .inputs {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(110px, 1fr));
          gap: var(--boxel-sp-xs, 0.5rem);
          margin: 0;
        }
        dt {
          font-size: 0.6875rem;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--boxel-450, #6b7683);
        }
        dd {
          margin: 0;
          font-weight: 600;
        }
        .result {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs, 0.5rem);
          margin: 0;
          padding-top: var(--boxel-sp-xs, 0.5rem);
          border-top: 1px solid var(--boxel-border-color, #d8dee5);
        }
        .rl {
          font-size: 0.6875rem;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--boxel-450, #6b7683);
        }
        .rv {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          font-size: 1.25rem;
          font-weight: 600;
        }
        .rerr {
          margin: 0;
          font-size: 0.75rem;
          color: var(--boxel-danger, #a83f3f);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='t'><@fields.cardTitle /></span>
        <span class='v'>{{if @model.result @model.result '—'}}</span>
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs, 0.5rem);
        }
        .t {
          font-weight: 600;
        }
        .v {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fit'>
        <span class='t'><@fields.cardTitle /></span>
        <span class='v'>{{if @model.result @model.result '—'}}</span>
      </div>
      <style scoped>
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          align-content: center;
          gap: 0.125rem;
          padding: var(--boxel-sp-xs, 0.5rem);
          overflow: hidden;
        }
        .t {
          font-size: 0.8125rem;
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .v {
          font-family: var(
            --boxel-monospace-font-family,
            ui-monospace,
            monospace
          );
          font-size: 1rem;
          color: var(--boxel-450, #6b7683);
        }
      </style>
    </template>
  };
}
