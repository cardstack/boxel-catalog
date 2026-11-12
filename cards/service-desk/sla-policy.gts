import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  StringField,
} from 'https://cardstack.com/base/card-api';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import enumField from 'https://cardstack.com/base/enum';
import ShieldCheckIcon from '@cardstack/boxel-icons/shield-check';
import { DataTable } from '@cardstack/pretui/components/data-table';

import { Schedule } from './schedule';
import { TicketPriorityField, ticketPriorityFactor } from './ticket-taxonomy';
import { formatMinutes, ALWAYS_ON, type BusinessSchedule } from './utils/sla';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import { Avatar as PretAvatar } from '@cardstack/pretui/components/avatar';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import {
  RecCard,
  RecHead,
  RecStats,
  RecBody,
  RecBlock,
  RecRow,
  RecLine,
  RecText,
} from './components/record';
import { IsoFrame } from '../shared/compact-sheet';

export const CONDITION_OPERATORS = ['is', 'is not', 'contains'] as const;

// `customerTier` reads as a field name; "Customer tier" reads as a sentence.
// The condition title is the only place an administrator gets to check that a
// policy still matches what they meant, so it is written in their words.
function humanize(attribute: string): string {
  let spaced = attribute.replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase();
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

const OperatorField = enumField(StringField, {
  displayName: 'Operator',
  options: CONDITION_OPERATORS as unknown as string[],
});

/**
 * One clause of "when does this policy apply".
 *
 * Stored as three readable parts rather than an expression string, so the
 * isolated view can render "Customer tier is VIP" as a chip an administrator
 * can check at a glance. A policy nobody can verify by looking at it is a
 * policy that quietly stops matching.
 */
export class PolicyConditionField extends FieldDef {
  static displayName = 'Condition';

  @field attribute = contains(StringField, {
    description: 'e.g. customerTier, priority, categoryName, channel',
  });
  @field operator = contains(OperatorField);
  @field value = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: PolicyConditionField) {
      if (!this.attribute) {
        return 'Any ticket';
      }
      return `${humanize(this.attribute)} ${this.operator ?? 'is'} ${this.value ?? '—'}`;
    },
  });

  matches(subject: Record<string, unknown>): boolean {
    if (!this.attribute) {
      return true;
    }
    let actual = String(subject[this.attribute] ?? '').toLowerCase();
    let expected = String(this.value ?? '').toLowerCase();
    switch (this.operator) {
      case 'is not':
        return actual !== expected;
      case 'contains':
        return actual.includes(expected);
      default:
        return actual === expected;
    }
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='cond'>{{@model.title}}</span>
      <style scoped>
        .cond {
          display: inline-flex;
          padding: 0.1em 0.5em;
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-pill);
          background-color: var(--muted);
          color: var(--foreground);
          font-size: var(--boxel-font-size-xs);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

/**
 * The committed time for one metric, before priority scaling.
 *
 * A policy states ONE target per metric and lets each priority's factor scale
 * it — a P1 gets a quarter, a P4 gets double. Stating all four explicitly is
 * how a policy ends up with a P3 that resolves faster than a P2 after somebody
 * edits one row.
 */
export class SlaTargetField extends FieldDef {
  static displayName = 'SLA Target';

  @field metric = contains(
    enumField(StringField, {
      displayName: 'Metric',
      options: ['First response', 'Next response', 'Resolution'],
    }),
  );
  @field baseMinutes = contains(NumberField, {
    description: 'Target for a P3 ticket, in minutes. Other priorities scale.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: SlaTargetField) {
      return `${this.metric ?? 'Target'} — ${
        typeof this.baseMinutes === 'number'
          ? formatMinutes(this.baseMinutes)
          : '—'
      }`;
    },
  });

  minutesFor(priority?: string | null): number | undefined {
    if (typeof this.baseMinutes !== 'number') {
      return undefined;
    }
    return Math.round(this.baseMinutes * ticketPriorityFactor(priority));
  }

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='tgt'>
        <span class='tgt-metric'>{{@model.metric}}</span>
        <span class='tgt-value'>{{@model.title}}</span>
      </span>
      <style scoped>
        .tgt {
          display: inline-flex;
          gap: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
        .tgt-metric {
          color: var(--muted-foreground);
        }
        .tgt-value {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}

/**
 * A set of commitments and the conditions under which they apply.
 *
 * The Domain Layers row for SLA Policy has nothing behind it, and neither do
 * SLA Window or Compute SLA Deadline — this card plus `SlaTimerField` plus
 * `utils/sla` are the first implementation of all three.
 */
export class SlaPolicy extends CardDef {
  static displayName = 'SLA Policy';
  static icon = ShieldCheckIcon;

  @field name = contains(StringField);
  @field conditions = containsMany(PolicyConditionField);
  @field targets = containsMany(SlaTargetField);
  @field businessHours = linksTo(() => Schedule);
  @field breachActions = containsMany(StringField, {
    description: 'Fired in order when a target is missed.',
  });
  @field isDefault = contains(BooleanField);
  @field samplePriority = contains(TicketPriorityField, {
    description: 'Only drives the preview in the editor.',
  });

  @field title = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      return this.name?.trim() || 'Untitled policy';
    },
  });

  @field conditionSummary = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      let parts = (this.conditions ?? []).map((c) => c.title).filter(Boolean);
      return parts.length ? parts.join(' and ') : 'Any ticket';
    },
  });

  // Denormalized for tiles: 'P1 15m / 2h'. A prerendered view can walk
  // containsMany, but it cannot do the priority arithmetic and stay readable.
  @field targetSummary = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      let first = (this.targets ?? []).find(
        (t) => t.metric === 'First response',
      );
      let resolve = (this.targets ?? []).find((t) => t.metric === 'Resolution');
      let f = first?.minutesFor('P1');
      let r = resolve?.minutesFor('P1');
      if (f == null && r == null) {
        return 'No targets set';
      }
      return `P1 ${f == null ? '—' : formatMinutes(f)} / ${
        r == null ? '—' : formatMinutes(r)
      }`;
    },
  });

  // Flattened, because a prerendered fitted view resolves no links and
  // READING through one there throws rather than returning undefined — which
  // is how a tile becomes a red error card instead of a slightly emptier tile.
  @field businessHoursSummary = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      return this.businessHours?.summary ?? 'Always on';
    },
  });

  @field breachActionSummary = contains(StringField, {
    computeVia: function (this: SlaPolicy) {
      let n = (this.breachActions ?? []).filter(Boolean).length;
      return n === 0 ? 'none' : n === 1 ? '1 action' : `${n} actions`;
    },
  });

  /** Does this policy apply to a ticket with these attributes? */
  applies(subject: Record<string, unknown>): boolean {
    let conditions = (this.conditions ?? []).filter((c) => c?.attribute);
    if (!conditions.length) {
      return true;
    }
    return conditions.every((c) => c.matches(subject));
  }

  targetFor(metric: string, priority?: string | null): number | undefined {
    return (this.targets ?? [])
      .find((t) => t.metric === metric)
      ?.minutesFor(priority);
  }

  get schedule(): BusinessSchedule {
    return this.businessHours?.businessSchedule ?? ALWAYS_ON;
  }

  static isolated = class Isolated extends Component<typeof this> {
    private base(metric: string): number | undefined {
      return (
        (this.args.model?.targets ?? []).find((x) => x?.metric === metric)
          ?.baseMinutes ?? undefined
      );
    }
    get matrixColumns() {
      return [
        { key: 'priority', label: 'Priority' },
        { key: 'first', label: 'First response', mono: true },
        { key: 'resolution', label: 'Resolution', mono: true },
        { key: 'next', label: 'Next response', mono: true },
      ];
    }
    get matrix() {
      let at = (metric: string, factor: number) => {
        let b = this.base(metric);
        return b == null ? undefined : formatMinutes(Math.round(b * factor));
      };
      return (TicketPriorityField as any).priorityOptions.map((o: any) => {
        let f = ticketPriorityFactor(o.value);
        return {
          id: o.value,
          priority: o.label,
          first: at('First response', f),
          resolution: at('Resolution', f),
          next: at('Next response', f),
        };
      });
    }
    p1 = (metric: string) => {
      let b = this.base(metric);
      return b == null
        ? 'base'
        : `base · P1 ${formatMinutes(Math.round(b * ticketPriorityFactor('P1')))}`;
    };
    rowKey = (r: { id: string }) => r.id;
    get actions() {
      return (this.args.model?.breachActions ?? [])
        .filter(Boolean)
        .map((a, i) => ({ text: a, n: i + 1 }));
    }
    target = (metric: string) => {
      let t = (this.args.model?.targets ?? []).find(
        (x) => x?.metric === metric,
      );
      let m = t?.baseMinutes;
      if (m == null) return '—';
      return m % 60 === 0
        ? `${m / 60}h`
        : m > 60
          ? `${Math.floor(m / 60)}h ${m % 60}m`
          : `${m}m`;
    };
    <template>
      <IsoFrame>
        <RecCard @inset={{true}}>
          <RecHead
            @mark='SL'
            @title={{@model.title}}
            @sub={{@model.conditionSummary}}
          >
            <:status>{{#if @model.isDefault}}<Chip
                  @appearance='plain'
                  @tone='info'
                >default</Chip>{{/if}}{{#if @model.businessHoursSummary}}<Chip
                  @appearance='plain'
                  @tone='info'
                >{{@model.businessHoursSummary}}</Chip>{{/if}}<Chip
                @appearance='plain'
              >{{this.actions.length}} breach actions</Chip></:status>
          </RecHead>
          <RecStats>
            <Stat
              @label='First response'
              @tone='neutral'
              @value={{this.target 'First response'}}
              @hint={{this.p1 'First response'}}
              @roll={{false}}
            />
            <Stat
              @label='Resolution'
              @tone='neutral'
              @value={{this.target 'Resolution'}}
              @hint={{this.p1 'Resolution'}}
              @roll={{false}}
            />
            <Stat
              @label='Next response'
              @tone='neutral'
              @value={{this.target 'Next response'}}
              @hint={{this.p1 'Next response'}}
              @roll={{false}}
            />
          </RecStats>
          <RecBody>
            <:main>
              <RecBlock @title='Applies when'>
                <RecText>{{if
                    @model.conditionSummary
                    @model.conditionSummary
                    'Every ticket'
                  }}</RecText>
              </RecBlock>
              <RecBlock @title='Targets by priority'>
                <div class='dt'>
                  <DataTable
                    @columns={{this.matrixColumns}}
                    @rows={{this.matrix}}
                    @key={{this.rowKey}}
                    @label='Targets by priority'
                    @flush={{true}}
                    @striped={{false}}
                    @size='s'
                    @sortable={{false}}
                    @columnMenu={{false}}
                  />
                </div>
              </RecBlock>
              <RecBlock @title='On breach'>
                {{#each this.actions as |a|}}
                  <RecLine><:default>{{a.text}}</:default><:end><span
                        class='mono'
                      >{{a.n}}</span></:end></RecLine>
                {{else}}
                  <RecLine>—</RecLine>
                {{/each}}
              </RecBlock>
            </:main>
            <:side>
              <RecBlock @title='Linked'>
                <RecRow @label='Hours'>{{#if
                    @model.businessHours
                  }}<@fields.businessHours
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</RecRow>
              </RecBlock>
              <RecBlock @title='Details'>
                <RecRow @label='Targets'>{{if
                    @model.targetSummary
                    @model.targetSummary
                    '—'
                  }}</RecRow>
                <RecRow @label='Hours'>{{if
                    @model.businessHoursSummary
                    @model.businessHoursSummary
                    '—'
                  }}</RecRow>
                <RecRow @label='Default'>{{if
                    @model.isDefault
                    'Yes'
                    'No'
                  }}</RecRow>
              </RecBlock>
            </:side>
          </RecBody>
        </RecCard>
      </IsoFrame>
      <style scoped>
        .dt {
          padding-inline: var(--boxel-sp-2xs);
        }
        .mono {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <RecCard>
        <RecHead
          @mark='SL'
          @title={{@model.title}}
          @sub={{@model.conditionSummary}}
        >
          <:status>{{#if @model.isDefault}}<Chip
                @appearance='plain'
                @tone='info'
              >default</Chip>{{/if}}</:status>
        </RecHead>
        <RecRow @label='Targets'>{{if
            @model.targetSummary
            @model.targetSummary
            '—'
          }}</RecRow>
        <RecRow @label='Hours'>{{if
            @model.businessHoursSummary
            @model.businessHoursSummary
            '—'
          }}</RecRow>
        <RecRow @label='On breach'>{{if
            @model.breachActionSummary
            @model.breachActionSummary
            '—'
          }}</RecRow>
      </RecCard>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>SL</span>
        <span class='nm'>{{@model.title}}</span>
        {{#if @model.isDefault}}<Chip
            @appearance='plain'
            @tone='info'
          >default</Chip>{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-3xs);
          min-inline-size: 0;
          max-inline-size: 100%;
          font-size: var(--boxel-font-size-xs);
        }
        .mark {
          flex: none;
          display: grid;
          place-items: center;
          inline-size: 1rem;
          block-size: 1rem;
          border: 1px solid var(--border);
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          line-height: 1;
          color: var(--muted-foreground);
        }
        .nm {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    // the details tier's key-value rows
    get facts() {
      let m = this.args.model;
      return [
        {
          key: 'Applies when',
          value: String(m?.conditionSummary ?? '') || '—',
        },
        {
          key: 'Targets',
          value: String(m?.targetSummary ?? '') || '—',
        },
        {
          key: 'Hours',
          value: String(m?.businessHoursSummary ?? '') || '—',
        },
        {
          key: 'On breach',
          value: String(m?.breachActionSummary ?? '') || '—',
        },
      ];
    }
    <template>
      <RichFittedCard>
        <:avatar><PretAvatar @name='SL' @shape='square' /></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{@model.conditionSummary}}</:subtitle>
        <:status>{{#if @model.isDefault}}<Chip
              @appearance='plain'
              @tone='info'
            >default</Chip>{{/if}}</:status>
        <:fact>{{@model.targetSummary}}</:fact>
        <:details>{{#each this.facts as |item|}}<Detail
              @label={{item.key}}
              @value={{item.value}}
            />{{/each}}</:details>
      </RichFittedCard>
    </template>
  };
}
