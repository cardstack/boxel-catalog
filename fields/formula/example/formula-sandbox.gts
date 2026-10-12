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
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';
import { FormulaField } from '../formula-field';

// Labels only: each row's value is the field component itself.
const INPUT_ROWS = [
  { key: 'Amount', value: '' },
  { key: 'Tax rate', value: '' },
  { key: 'Recurring', value: '' },
];

/**
 * Exercises a stored formula against the card holding it. The `computeVia`
 * below is the whole integration contract: a FieldDef cannot reach its owner,
 * so the card passes itself.
 */
export class FormulaSandbox extends CardDef {
  static displayName = 'Formula Sandbox';
  static icon = CalculatorIcon;

  @field amount = contains(NumberField);
  // NumberField's standard display rounds to whole numbers unless decimals
  // are configured, which would show a 0.15 rate as 0.
  @field rate = contains(NumberField, {
    description: 'Tax rate as a fraction, e.g. 0.15 for 15%.',
    configuration: { presentation: 'standard', options: { decimals: 2 } },
  });
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
        <KeyValue
          class='inputs'
          @items={{INPUT_ROWS}}
          @layout='inline'
          @labelStyle='eyebrow'
        >
          <:value as |row|>
            {{#if (eq row.key 'Amount')}}
              <@fields.amount />
            {{else if (eq row.key 'Tax rate')}}
              <@fields.rate />
            {{else}}
              <@fields.recurring />
            {{/if}}
          </:value>
        </KeyValue>
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
          gap: var(--boxel-sp);
          padding: var(--boxel-sp);
        }
        .inputs {
          gap: var(--boxel-sp-xs) var(--boxel-sp-lg);
        }
        .result {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          padding-top: var(--boxel-sp-xs);
          border-top: 1px solid var(--border);
        }
        .rl {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .rv {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-md);
          font-weight: 600;
        }
        .rerr {
          font-size: var(--boxel-font-size-xs);
          color: var(--destructive-ink);
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
          gap: var(--boxel-sp-xs);
        }
        .t {
          font-weight: 600;
        }
        .v {
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FittedCard class='fit' @titleTag='h3'>
        <:title><@fields.cardTitle /></:title>
        <:subtitle><span class='v'>{{if
              @model.result
              @model.result
              '—'
            }}</span></:subtitle>
      </FittedCard>
      <style scoped>
        .fit {
          --fc-subtitle-font-size: var(--boxel-font-size);
        }
        .v {
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };
}
