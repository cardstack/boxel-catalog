import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import SquareFunctionIcon from '@cardstack/boxel-icons/square-function';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { ValidationRuleField } from './validation-rule-field';
import { EvaluationStatusField, EVALUATION_HUE } from '@cardstack/catalog/fields/evaluation-status/evaluation-status-field';
import { FindingField } from './finding-field';
import { ProofField } from './proof-field';
import { AuditMetadataField } from './audit-metadata-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { SeverityBadge } from '@cardstack/catalog/cards/audit/components/severity-badge';

/**
 * One rule, one subject, one verdict — the atom an audit is made of.
 *
 * A card rather than a field because a result is cited: a report links it, a
 * finding is read out of it, and next period's run compares against it. All
 * three need it to have a URL.
 *
 * The rule is stored **by value**. A result says what was judged and by which
 * version of the rule, so editing the rule next quarter cannot retroactively
 * change what this run concluded. That is also why `meta.sourceVersion`
 * exists — a re-read of an old report must reinterpret nothing.
 *
 * Evidence lives here as well as on the finding: a **pass** is worth proving
 * too, and a control that passed with nothing attached is exactly what
 * `unproven` is for.
 */
export class AuditResult extends CardDef {
  static displayName = 'Audit Result';
  static icon = SquareFunctionIcon;

  /** The report this belongs to. Linked by URL to avoid a module cycle. */
  @field audit = linksTo(CardDef);
  @field rule = contains(ValidationRuleField);
  @field subject = linksTo(CardDef, { searchable: true });
  @field status = contains(EvaluationStatusField);
  /** What the engine read, rendered for a human. */
  @field observedValue = contains(StringField);
  @field evidence = containsMany(ProofField);
  /** Present when the verdict was fail or partial. */
  @field finding = contains(FindingField);
  @field evaluatedAt = contains(DateTimeField);
  @field evaluatedBy = linksTo(() => Employee);
  @field meta = contains(AuditMetadataField);

  @field hasFinding = contains(BooleanField, {
    computeVia: function (this: AuditResult) {
      return Boolean(this.finding?.findingId);
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AuditResult) {
      let rule = this.rule?.ruleId ?? 'Rule';
      let subject = this.subject?.cardTitle ?? 'subject';
      return `${rule} · ${subject}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get hue() {
      return EVALUATION_HUE[this.args.model?.status?.status ?? ''] ?? 'slate';
    }
    <template>
      <article class='result'>
        <header>
          <p class='kicker'>Audit result</p>
          <h1>{{@model.cardTitle}}</h1>
          <div class='head-meta'>
            <StatePill
              @label={{@model.status.label}}
              @hue={{this.hue}}
              @dot={{true}}
            />
            {{#if @model.evaluatedAt}}
              <span class='meta'><@fields.evaluatedAt /></span>
            {{/if}}
            {{#if @model.evaluatedBy}}
              <span class='meta'>by <@fields.evaluatedBy @format='atom' /></span>
            {{/if}}
          </div>
        </header>

        <section class='facts'>
          <div class='fact'>
            <span class='k'>Required</span>
            <span class='v'>{{@model.rule.statement}}</span>
          </div>
          <div class='fact'>
            <span class='k'>Observed</span>
            <span class='v mono'>{{@model.observedValue}}</span>
          </div>
          {{#if @model.rule.regime.reference}}
            <div class='fact'>
              <span class='k'>Clause</span>
              <span class='v'><@fields.rule @format='atom' /></span>
            </div>
          {{/if}}
        </section>

        {{#if @model.hasFinding}}
          <section>
            <h2>Finding</h2>
            <@fields.finding />
          </section>
        {{/if}}

        {{#if @model.evidence.length}}
          <section>
            <h2>Evidence</h2>
            <@fields.evidence />
          </section>
        {{else}}
          <p class='empty'>No evidence attached. A rule that requires proof
            reads <strong>unproven</strong> rather than pass.</p>
        {{/if}}

        {{#if @model.meta}}
          <section class='trail'><@fields.meta /></section>
        {{/if}}
      </article>
      <style scoped>
        .result {
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
          font-size: 1.375rem;
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
        .meta,
        .empty {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .empty {
          margin: 0;
          font-size: 0.875rem;
        }
        .facts {
          display: grid;
          gap: var(--boxel-sp-sm);
        }
        .fact {
          display: grid;
          grid-template-columns: 6rem minmax(0, 1fr);
          gap: var(--boxel-sp-sm);
          align-items: baseline;
          font-size: 0.875rem;
        }
        .k {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
          overflow-wrap: anywhere;
        }
        .trail {
          border-top: 1px solid var(--border, var(--boxel-200));
          padding-top: var(--boxel-sp-sm);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return EVALUATION_HUE[this.args.model?.status?.status ?? ''] ?? 'slate';
    }
    <template>
      <div class='row'>
        <div class='what'>
          <span class='name'>{{@model.cardTitle}}</span>
          <span class='sub mono'>{{@model.observedValue}}</span>
        </div>
        {{#if @model.finding.severity.level}}
          <SeverityBadge
            @level={{@model.finding.severity.level}}
            @compact={{true}}
          />
        {{/if}}
        <StatePill @label={{@model.status.label}} @hue={{this.hue}} @dot={{true}} />
      </div>
      <style scoped>
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .what {
          display: flex;
          flex-direction: column;
          gap: 1px;
          min-width: 0;
          flex: 1;
        }
        .name {
          font-weight: 600;
          font-size: 0.875rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
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
    <template>
      <div class='fit'>
        <span class='fit-name'>{{@model.cardTitle}}</span>
        <span class='fit-sub'>{{@model.status.label}}</span>
        <div class='tier-tile'>
          <span class='row mono'>{{@model.observedValue}}</span>
          {{#if @model.hasFinding}}
            <span class='row'>{{@model.finding.findingId}}</span>
          {{/if}}
        </div>
      </div>
      <style scoped>
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
          font-size: 0.875rem;
          line-height: 1.2;
          overflow: hidden;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
        }
        .fit-sub,
        .row {
          font-size: 0.75rem;
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .mono {
          font-family: var(--font-mono, ui-monospace, monospace);
        }
        .tier-tile {
          display: none;
          flex-direction: column;
          gap: 2px;
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
      </style>
    </template>
  };
}

export default AuditResult;
