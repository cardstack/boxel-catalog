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
    <template>
      <div class='policy'>
        <span class='policy-name'>
          {{if @model.name @model.name 'Unnamed policy'}}
          {{#unless @model.enabled}}<span
              class='policy-off'
            >off</span>{{/unless}}
        </span>
        <span class='policy-rule'>
          when
          <code>{{@model.whenField}}
            {{@model.whenOp}}
            {{@model.whenValue}}</code>
          →
          <code>{{@model.action}}{{#if
              @model.actionParam
            }}({{@model.actionParam}}){{/if}}</code>
        </span>
        {{#if @model.applyCount}}
          <span class='policy-meta'>applied {{@model.applyCount}}×</span>
        {{/if}}
      </div>
      <style scoped>
        .policy {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-5xs);
          font-size: var(--boxel-font-size-sm);
        }
        .policy-name {
          font-weight: 500;
          display: flex;
          gap: var(--boxel-sp-4xs);
          align-items: baseline;
        }
        .policy-off {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          border: 1px solid var(--border, var(--boxel-border-color));
          border-radius: 999px;
          padding: 0 0.5rem;
        }
        .policy-rule {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .policy-rule code {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          color: var(--foreground, var(--boxel-dark));
        }
        .policy-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
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
