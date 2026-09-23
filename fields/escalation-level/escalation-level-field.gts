import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import enumField from '@cardstack/base/enum';
import TrendingUpIcon from '@cardstack/boxel-icons/trending-up';

import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';

export const ESCALATION_LEVELS = ['L1', 'L2', 'L3', 'exec'] as const;
export type EscalationLevelKey = (typeof ESCALATION_LEVELS)[number];

export const EscalationLevelKeyField = enumField(StringField, {
  displayName: 'Escalation Level Key',
  options: ESCALATION_LEVELS as unknown as string[],
});

const LEVEL_RANK: Record<string, number> = { L1: 1, L2: 2, L3: 3, exec: 4 };

/** One hue map beside the enum, so every consumer colors the ladder alike. */
export const LEVEL_HUES: Record<string, Hue> = {
  L1: 'slate',
  L2: 'blue',
  L3: 'amber',
  exec: 'red',
};

export function levelColor(key?: string | null): StateColor {
  return stateColor(LEVEL_HUES[key ?? 'L1'] ?? 'slate');
}

export function levelRank(key?: string | null): number {
  return LEVEL_RANK[key ?? 'L1'] ?? 1;
}

/**
 * One rung of the escalation ladder. The ladder is data, not tribal
 * knowledge: each level names who answers (`targetRoleName`) and how fast
 * they must acknowledge (`ackTargetMinutes`) — an unacknowledged escalation
 * is invisible risk, so the ack clock is first-class.
 */
export class EscalationLevelField extends FieldDef {
  static displayName = 'Escalation Level';
  static icon = TrendingUpIcon;

  @field key = contains(EscalationLevelKeyField);
  @field label = contains(StringField, {
    description: 'Display label, e.g. "Senior support" for L2.',
  });
  @field targetRoleName = contains(StringField, {
    description: 'The Role that answers at this level, by name.',
  });
  @field ackTargetMinutes = contains(NumberField, {
    description: 'How fast this level must acknowledge, in minutes.',
  });

  @field rank = contains(NumberField, {
    computeVia: function (this: EscalationLevelField) {
      return levelRank(this.key);
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: EscalationLevelField) {
      if (!this.key) return 'Level';
      return this.label ? `${this.key} · ${this.label}` : this.key;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get chipStyle() {
      let c = levelColor(this.args.model.key);
      return `--level-fg: ${c.fg}; --level-bg: ${c.bg};`;
    }
    <template>
      <span class='level' style={{this.chipStyle}}>
        <span class='level-key'>{{if @model.key @model.key 'L1'}}</span>
        {{#if @model.label}}<span
            class='level-label'
          >{{@model.label}}</span>{{/if}}
      </span>
      <style scoped>
        .level {
          display: inline-flex;
          align-items: baseline;
          gap: var(--boxel-sp-4xs);
          border-radius: var(--boxel-border-radius-sm);
          padding: 0.125rem 0.5rem;
          background: var(--level-bg);
          color: var(--level-fg);
          font-size: var(--boxel-font-size-xs);
        }
        .level-key {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-weight: 600;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='level-atom'>{{if @model.key @model.key 'L1'}}</span>
      <style scoped>
        .level-atom {
          font-family: var(--font-mono, var(--boxel-monospace-font-family));
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
        }
      </style>
    </template>
  };
}

export default EscalationLevelField;
