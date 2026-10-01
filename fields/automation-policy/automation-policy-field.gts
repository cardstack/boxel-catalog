import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import enumField from '@cardstack/base/enum';
import ZapIcon from '@cardstack/boxel-icons/zap';
import { htmlSafe } from '@ember/template';
import { Token } from '@cardstack/pretui/components/token';
import { tokenStyle } from '../shared/pretui-token';

// The rule's two halves are machine values, so they read as Pret UI Tokens in
// the muted hue at the rule line's own size. Token sets `nowrap`, but a rule
// half carries free text (a `contains` phrase), so these Tokens wrap and break
// long words instead of running past a narrow card's edge.
const RULE_TOKEN_STYLE = htmlSafe(
  `${tokenStyle('--boxel-font-size-xs', 'var(--muted-foreground)')}; white-space: normal; overflow-wrap: anywhere`,
);

export const POLICY_OPS = ['is', 'is not', 'gte', 'lte', 'contains'] as const;

export const PolicyOpField = enumField(StringField, {
  displayName: 'Policy Operator',
  options: POLICY_OPS as unknown as string[],
});

export const POLICY_ACTIONS = [
  'assign-round-robin',
  'escalate-to-level',
  'apply-sla-policy',
  'move-workflow-state',
  'add-tag',
] as const;

export const PolicyActionField = enumField(StringField, {
  displayName: 'Policy Action',
  options: POLICY_ACTIONS as unknown as string[],
});

/**
 * "Round-robin new P1s; escalate to L2 at 75% SLA" — a when-predicate plus
 * one action, stored as data.
 *
 * THE HONEST LIMIT, stated here because every consumer must repeat it: the
 * platform has no scheduler, so a policy is APPLIED WHEN A COMMAND RUNS
 * (case created, reply recorded, the board's "Apply policies" action) — never
 * on a timer. `lastAppliedAt`/`applyCount` are stamped by the applying
 * command, and every application is attributed on the record's timeline as
 * "by policy <name>", so automation never reads as a ghost.
 */
export class AutomationPolicyField extends FieldDef {
  static displayName = 'Automation Policy';
  static icon = ZapIcon;

  @field name = contains(StringField);
  @field whenField = contains(StringField, {
    description:
      'Field path on the subject, e.g. "priority" or "slaConsumedPercent".',
  });
  @field whenOp = contains(PolicyOpField);
  @field whenValue = contains(StringField);
  @field action = contains(PolicyActionField);
  @field actionParam = contains(StringField, {
    description: 'Level key, policy id, state key or tag — per action.',
  });
  @field enabled = contains(BooleanField);
  @field lastAppliedAt = contains(DateTimeField);
  @field applyCount = contains(NumberField);

  @field title = contains(StringField, {
    computeVia: function (this: AutomationPolicyField) {
      return this.name ?? 'Policy';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get hasCondition() {
      let m = this.args.model;
      return Boolean(m.whenField || m.whenOp || m.whenValue);
    }
    get hasAction() {
      let m = this.args.model;
      return Boolean(m.action || m.actionParam);
    }
    get hasConditionAndAction() {
      return this.hasCondition && this.hasAction;
    }
    get hasRule() {
      return this.hasCondition || this.hasAction;
    }
    <template>
      <div class='policy'>
        <span class='policy-name'>
          {{if @model.name @model.name 'Unnamed policy'}}
          {{#unless @model.enabled}}<span
              class='policy-off'
            >off</span>{{/unless}}
        </span>
        {{#if this.hasRule}}
          <span class='policy-rule'>
            {{#if this.hasCondition}}
              when
              <Token style={{RULE_TOKEN_STYLE}}>{{@model.whenField}}
                {{@model.whenOp}}
                {{@model.whenValue}}</Token>
            {{/if}}
            {{#if this.hasConditionAndAction}}
              →
            {{/if}}
            {{#if this.hasAction}}
              <Token style={{RULE_TOKEN_STYLE}}>{{@model.action}}{{#if
                  @model.actionParam
                }}({{@model.actionParam}}){{/if}}</Token>
            {{/if}}
          </span>
        {{/if}}
        {{#if @model.applyCount}}
          <span class='policy-meta'>applied {{@model.applyCount}}×</span>
        {{/if}}
      </div>
      <style scoped>
        .policy {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-sm);
        }
        .policy-name {
          font-weight: 500;
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-2xs) var(--boxel-sp-xs);
          align-items: baseline;
        }
        .policy-off {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-pill);
          padding: 0 0.5rem;
        }
        .policy-rule {
          min-width: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .policy-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='policy-atom'>{{if @model.name @model.name 'Policy'}}</span>
      <style scoped>
        .policy-atom {
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

export default AutomationPolicyField;
