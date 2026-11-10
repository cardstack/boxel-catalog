import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import { type getCards } from '@cardstack/runtime-common';
import InboxIcon from '@cardstack/boxel-icons/inbox';

// The Ticket CodeRef, built from the REALM URL at read time.
//
// Two things it is deliberately not. Not an `import { Ticket }`: `ticket.gts`
// imports this module, so importing back closes a cycle, and a cycle in a card
// module fails as `Class extends value undefined` at index time across every
// instance in the realm. Not a `_cardType: 'Ticket'` string either: that is an
// EXACT display-name match and silently drops Incident and ServiceRequest, the
// two subclasses this mostly holds.
//
// The ref comes from the model, not `import.meta.url`, which the checker
// rejects under CommonJS inference (TS1470). The realm URL is already on
// the model, it is what `service-desk.gts` uses to create a ticket, and it
// makes the ref a per-instance value instead of a module-level constant — so
// the same module is correct in whichever realm it is copied into.
import { ticketRefIn } from './utils/ticket-ref';

import {
  SupportAgent,
  AgentTierField,
  AGENT_TIER_LABELS,
} from './support-agent';
import { SlaPolicy } from './sla-policy';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { FitTile } from '../shared/fit-tile';
import { FittedExtras } from '../procurement/vendor';
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

// "L2 Technical" → "L2": the tier code is the queue's mark.
function queueMark(title?: string) {
  let first = (title ?? '').trim().split(/\s+/)[0] ?? '';
  return /^L\d$/i.test(first)
    ? first.toUpperCase()
    : first.slice(0, 2).toUpperCase() || 'Q';
}

function queueCounts(list: unknown[] | undefined) {
  let tickets = (list ?? []).filter(Boolean) as any[];
  let live = tickets.filter((t) => !['Resolved', 'Closed'].includes(t.status));
  return {
    open: live.length,
    atRisk: live.filter((t) => ['warning', 'urgent'].includes(t.slaState))
      .length,
    paused: live.filter((t) => t.slaState === 'paused').length,
  };
}

function liveCount(links: unknown[] | null | undefined): number {
  return (links ?? []).filter(Boolean).length;
}

/**
 * A basket of work with a team attached.
 *
 * The tickets in a queue are found by a live query, never held as a list of
 * links. A maintained list drifts the moment a ticket is escalated, merged or
 * closed, and it drifts silently — the queue keeps showing work that is not
 * there and hiding work that is.
 */
export class Queue extends CardDef {
  static displayName = 'Queue';
  static icon = InboxIcon;

  @field name = contains(StringField);
  @field description = contains(StringField);
  @field tier = contains(AgentTierField);
  @field agents = linksToMany(() => SupportAgent);
  @field defaultPolicy = linksTo(() => SlaPolicy);

  @field title = contains(StringField, {
    computeVia: function (this: Queue) {
      return this.name?.trim() || 'Untitled queue';
    },
  });

  @field tierLabel = contains(StringField, {
    computeVia: function (this: Queue) {
      return AGENT_TIER_LABELS[this.tier ?? ''] ?? this.tier ?? '';
    },
  });

  // The fitted badge already shows the bare tier ("L2"), so the footer must
  // not print the full shared label ("L2 · Specialist") underneath it — two
  // overlapping strings in the same muted style read as one field wrapped onto
  // two lines. This is the descriptor half only, still derived from the one
  // shared map so the wording cannot drift from the badge's.
  @field tierDescriptor = contains(StringField, {
    computeVia: function (this: Queue) {
      let label = AGENT_TIER_LABELS[this.tier ?? ''] ?? '';
      return label.split(' · ')[1] ?? label;
    },
  });

  // liveCount, not `agents.length`: deleting an agent leaves the link slot in
  // place reading as undefined, so a raw length reports people who are gone.
  @field agentCount = contains(StringField, {
    computeVia: function (this: Queue) {
      let n = liveCount(this.agents);
      return n === 1 ? '1 agent' : `${n} agents`;
    },
  });

  // Same reason as SlaPolicy: fitted cannot walk this link, and touching it
  // there throws.
  @field policyName = contains(StringField, {
    computeVia: function (this: Queue) {
      return this.defaultPolicy?.title ?? '';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    tickets: ReturnType<getCards> | undefined;
    constructor(owner: unknown, args: any) {
      super(owner as never, args as never);
      let realm = this.args.model?.[realmURL]?.href;
      this.tickets = (this.args.context as any)?.getCards?.(
        this,
        () => {
          let ref = ticketRefIn(realm);
          return ref
            ? {
                filter: {
                  on: ref,
                  eq: { queueName: this.args.model?.title ?? '—' },
                },
              }
            : undefined;
        },
        () => (realm ? [realm] : []),
        { isLive: true },
      );
    }
    get counts() {
      return queueCounts(this.tickets?.instances);
    }
    <template>
      <RecCard @inset={{true}}>
        <RecHead
          @mark={{queueMark @model.title}}
          @title={{@model.title}}
          @sub={{@model.description}}
        >
          <:status>
            {{#if @model.tierLabel}}<Chip
                @appearance='plain'
              >{{@model.tierLabel}}</Chip>{{/if}}
            <Chip @appearance='plain'>{{@model.agentCount}}</Chip>
          </:status>
        </RecHead>
        <RecStats>
          <Stat
            @label='Open'
            @tone='neutral'
            @value={{this.counts.open}}
            @hint='tickets in this queue'
            @roll={{false}}
          />
          <Stat
            @label='Agents'
            @tone='neutral'
            @value={{this.agentTotal}}
            @hint={{@model.tierDescriptor}}
            @roll={{false}}
          />
          <Stat
            @label='At risk'
            @tone='warning'
            @value={{this.counts.atRisk}}
            @hint='clock close to breach'
            @roll={{false}}
          />
        </RecStats>
        <RecBody>
          <:main>
            <RecBlock @title='About this queue'>
              <RecText>{{if
                  @model.description
                  @model.description
                  '—'
                }}</RecText>
            </RecBlock>
            <RecBlock @title='Agents'>
              {{#each @fields.agents as |Agent|}}
                <RecLine><Agent
                    @format='atom'
                    @displayContainer={{false}}
                  /></RecLine>
              {{else}}
                <RecLine><span class='dim'>Nobody works this queue yet.</span></RecLine>
              {{/each}}
            </RecBlock>
            <RecBlock @title='Routing'>
              <RecRow @label='Default commitment'>{{if
                  @model.policyName
                  @model.policyName
                  '—'
                }}</RecRow>
            </RecBlock>
          </:main>
          <:side>
            <RecBlock @title='Linked'>
              <RecRow @label='Policy'>{{#if
                  @model.defaultPolicy
                }}<@fields.defaultPolicy
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</RecRow>
              {{#each @fields.agents as |Agent|}}
                <RecRow @label='Agent'><Agent
                    @format='atom'
                    @displayContainer={{false}}
                  /></RecRow>
              {{/each}}
            </RecBlock>
            <RecBlock @title='Details'>
              <RecRow @label='Tier'>{{if
                  @model.tierLabel
                  @model.tierLabel
                  '—'
                }}</RecRow>
              <RecRow @label='Agents'>{{@model.agentCount}}</RecRow>
              <RecRow @label='Default policy'>{{if
                  @model.policyName
                  @model.policyName
                  '—'
                }}</RecRow>
              <RecRow
                @label='Open tickets'
                @mono={{true}}
              >{{this.counts.open}}</RecRow>
              <RecRow
                @label='At risk'
                @mono={{true}}
              >{{this.counts.atRisk}}</RecRow>
              <RecRow
                @label='Paused'
                @mono={{true}}
              >{{this.counts.paused}}</RecRow>
            </RecBlock>
          </:side>
        </RecBody>
      </RecCard>
      <style scoped>
        .dim {
          color: var(--muted-foreground);
        }
      </style>
    </template>
    get agentTotal() {
      return liveCount(this.args.model?.agents);
    }
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <RecCard>
        <RecHead
          @mark={{queueMark @model.title}}
          @title={{@model.title}}
          @sub={{@model.description}}
        />
        <div class='chips'>
          {{#if @model.tierLabel}}<Chip
              @appearance='plain'
            >{{@model.tierLabel}}</Chip>{{/if}}
          <Chip @appearance='plain'>{{@model.agentCount}}</Chip>
        </div>
        <p class='fact'>Default commitment
          <b>{{if @model.policyName @model.policyName '—'}}</b>
          · arrives by escalation</p>
        <RecRow @label='Tier'>{{if
            @model.tierLabel
            @model.tierLabel
            '—'
          }}</RecRow>
        <RecRow @label='Agents'>{{@model.agentCount}}</RecRow>
        <RecRow @label='Default policy'>{{if
            @model.policyName
            @model.policyName
            '—'
          }}</RecRow>
        {{#each @fields.agents as |Agent|}}
          <RecRow @label='Agent'><Agent
              @format='atom'
              @displayContainer={{false}}
            /></RecRow>
        {{/each}}
        <RecRow @label='Policy'>{{#if
            @model.defaultPolicy
          }}<@fields.defaultPolicy
              @format='atom'
              @displayContainer={{false}}
            />{{else}}—{{/if}}</RecRow>
      </RecCard>
      <style scoped>
        .chips {
          display: flex;
          gap: var(--boxel-sp-sm);
          padding: 0 var(--boxel-sp-xs) var(--boxel-sp-2xs);
        }
        .fact {
          padding: 0 var(--boxel-sp-xs) var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .fact b {
          color: var(--foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>{{queueMark @model.title}}</span>
        <span class='nm'>{{@model.title}}</span>
        <Chip @appearance='plain'>{{@model.agentCount}}</Chip>
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
          font-size: var(--boxel-font-size-2xs);
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
    // Whole ruled rows the tall fitted sizes add under the FitTile.
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Tier', value: String(m?.tierLabel ?? '') || '—' },
        { key: 'Agents', value: String(m?.agentCount ?? '') || '—' },
        {
          key: 'Default policy',
          value: String(m?.policyName ?? '') || '—',
        },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <FitTile>
            <:avatar><Avatar
                @name={{queueMark @model.title}}
                @shape='square'
                @size={{32}}
              /></:avatar>
            <:title>{{@model.title}}</:title>
            <:subtitle>{{@model.description}}</:subtitle>
            <:status>
              {{#if @model.tierLabel}}<Chip
                  @appearance='plain'
                >{{@model.tierLabel}}</Chip>{{/if}}
              <Chip @appearance='plain'>{{@model.agentCount}}</Chip>
            </:status>
            <:fact>Default commitment
              {{if @model.policyName @model.policyName '—'}}</:fact>
          </FitTile>
        </:default>
      </FittedExtras>
    </template>
  };
}
