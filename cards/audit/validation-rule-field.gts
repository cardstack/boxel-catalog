import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import RulerIcon from '@cardstack/boxel-icons/ruler';

import { RegimeMetadataField } from './regime-metadata-field';
import { SeverityField } from '@cardstack/catalog/cards/audit/severity-field';
import { SeverityBadge } from '@cardstack/catalog/cards/audit/components/severity-badge';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import {
  RULE_KINDS,
  RULE_KIND_LABELS,
  RULE_KIND_HINTS,
  parametersAreValid,
} from './utils/rule-evaluation';

export const RuleKindField = enumField(StringField, {
  displayName: 'Rule Kind',
  options: RULE_KINDS.map((value) => ({
    value,
    label: RULE_KIND_LABELS[value],
  })),
});

/**
 * The testable statement of a control: which field, tested how, against what.
 *
 * A control written as prose ("suppliers must be reviewed regularly") cannot
 * be evaluated, only argued about. This field is the version a machine can
 * settle — and the version an auditor can read back, which is why `statement`
 * stays alongside the machinery rather than being generated from it.
 *
 * Domain-neutral: `fieldPath` points at any card's field, so one rule shape
 * judges a vendor, a contract, a site or a Spec. Nothing here names a
 * compliance concept, which is what lets the standards evaluator reuse it.
 *
 * `fieldPath` is a deliberate addition to the spec's field list — the four
 * kinds all need to know WHAT they are testing, and burying it in the
 * parameters JSON would hide the one thing every rule must state.
 */
export class ValidationRuleField extends FieldDef {
  static displayName = 'Validation Rule';
  static icon = RulerIcon;

  /** Stable within the regime — "SUP-03". Findings cite it. */
  @field ruleId = contains(StringField);
  /** The control in a sentence, as the auditor would say it. */
  @field statement = contains(StringField);
  @field regime = contains(RegimeMetadataField);
  @field kind = contains(RuleKindField);
  /** Dotted path on the subject: `riskRating.score`, `lifecycle.reviewedAt`. */
  @field fieldPath = contains(StringField);
  /** JSON object: {"min":70} · {"maxAgeDays":365} · {"oneOf":["a","b"]}. */
  @field parameters = contains(StringField);
  /** The severity a Finding raised by this rule starts at. */
  @field severityIfFailed = contains(SeverityField);
  /** When true, a pass with no proof attached is `unproven`, not `pass`. */
  @field evidenceRequired = contains(BooleanField);

  @field kindLabel = contains(StringField, {
    computeVia: function (this: ValidationRuleField) {
      return RULE_KIND_LABELS[this.kind ?? ''] ?? '';
    },
  });

  /** A malformed parameters blob is a rule that can never fire — say so. */
  @field isWellFormed = contains(BooleanField, {
    computeVia: function (this: ValidationRuleField) {
      return Boolean(this.fieldPath) && parametersAreValid(this.parameters);
    },
  });

  @field summary = contains(StringField, {
    computeVia: function (this: ValidationRuleField) {
      let id = this.ruleId ? `${this.ruleId} ` : '';
      return `${id}${this.statement ?? ''}`.trim();
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hint() {
      return RULE_KIND_HINTS[this.args.model?.kind ?? ''] ?? '';
    }
    <template>
      <div class='rule'>
        <div class='head'>
          {{#if @model.ruleId}}
            <span class='rid mono'>{{@model.ruleId}}</span>
          {{/if}}
          <StatePill @label={{@model.kindLabel}} @hue='blue' />
          {{#if @model.severityIfFailed.level}}
            <SeverityBadge
              @level={{@model.severityIfFailed.level}}
              @compact={{true}}
            />
          {{/if}}
          {{#if @model.evidenceRequired}}
            <StatePill @label='evidence required' @hue='teal' />
          {{/if}}
          {{#unless @model.isWellFormed}}
            <StatePill @label='cannot fire' @hue='red' @dot={{true}} />
          {{/unless}}
        </div>

        {{#if @model.statement}}
          <p class='statement'>{{@model.statement}}</p>
        {{/if}}

        <div class='mechanics'>
          {{#if @model.fieldPath}}
            <span class='mono'>{{@model.fieldPath}}</span>
          {{/if}}
          {{#if @model.parameters}}
            <span class='mono params'>{{@model.parameters}}</span>
          {{/if}}
          <span class='hint'>{{this.hint}}</span>
        </div>

        {{#if @model.regime.reference}}
          <div class='regime'><@fields.regime @format='atom' /></div>
        {{/if}}
      </div>
      <style scoped>
        .rule {
          display: grid;
          gap: var(--boxel-sp-5xs);
          padding: var(--boxel-sp-xs) 0;
          min-width: 0;
        }
        .head {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .rid {
          font-size: 0.8125rem;
          font-weight: 700;
        }
        .statement {
          margin: 0;
          font-size: 0.875rem;
          line-height: 1.5;
          color: var(--foreground, var(--boxel-dark));
        }
        .mechanics {
          display: flex;
          flex-wrap: wrap;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .params {
          overflow-wrap: anywhere;
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        .hint {
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        {{#if @model.ruleId}}<span class='mono'>{{@model.ruleId}}</span>{{/if}}
        <span class='st'>{{@model.statement}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: baseline;
          gap: var(--boxel-sp-5xs);
          font-size: 0.8125rem;
          min-width: 0;
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
          font-weight: 700;
        }
        .st {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export default ValidationRuleField;
