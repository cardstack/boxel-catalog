import { markDefinition } from '@cardstack/base/mark-definition';
import {
  Component,
  field,
  contains,
  containsMany,
  StringField,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import { Button } from '@cardstack/pretui/components/button';
import enumField from 'https://cardstack.com/base/enum';
import HeadsetIcon from '@cardstack/boxel-icons/headset';

import { PersonBase } from '../people/person-base';

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
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import { RichFittedCard } from '../shared/rich-fitted-card';
import { FittedExtras } from '../procurement/vendor';
import { initials } from './utils/initials';
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

import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { IsoFrame } from '../shared/compact-sheet';

export const AGENT_TIERS = ['L1', 'L2', 'L3'] as const;

export const AGENT_TIER_LABELS: Record<string, string> = {
  L1: 'L1 · Front line',
  L2: 'L2 · Specialist',
  L3: 'L3 · Engineering',
};

export const AgentTierField = markDefinition(
  enumField(StringField, {
    displayName: 'Support Tier',
    options: AGENT_TIERS as unknown as string[],
  }),
);

/** The next tier up, or undefined at the top. Escalation reads this. */
export function nextTier(tier?: string | null): string | undefined {
  let idx = AGENT_TIERS.indexOf(tier as never);
  return idx >= 0 && idx < AGENT_TIERS.length - 1
    ? AGENT_TIERS[idx + 1]
    : undefined;
}

/**
 * Someone who answers.
 *
 * Extends `PersonBase` for the same reason `SupportContact` does. `skills` is
 * the field auto-assignment reads: routing on tier alone sends every SSO
 * question to whoever is least busy, which is how a ticket takes three days
 * and two escalations to reach the person who could have answered it in five
 * minutes.
 */
export class SupportAgent extends PersonBase {
  static displayName = 'Agent';
  static icon = HeadsetIcon;

  @field tier = contains(AgentTierField);
  @field skills = containsMany(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: SupportAgent) {
      return this.name?.trim() || 'Unnamed agent';
    },
  });

  @field tierLabel = contains(StringField, {
    computeVia: function (this: SupportAgent) {
      return AGENT_TIER_LABELS[this.tier ?? ''] ?? this.tier ?? '';
    },
  });

  // The fitted badge shows the bare tier ("L2"); printing the full shared
  // label ("L2 · Specialist") in the body underneath it repeated the badge.
  // Descriptor half only, still from the one shared map.
  @field tierDescriptor = contains(StringField, {
    computeVia: function (this: SupportAgent) {
      let label = AGENT_TIER_LABELS[this.tier ?? ''] ?? '';
      return label.split(' · ')[1] ?? label;
    },
  });

  @field skillSummary = contains(StringField, {
    computeVia: function (this: SupportAgent) {
      let skills = (this.skills ?? []).filter(Boolean);
      if (!skills.length) {
        return 'No skills listed';
      }
      return skills.length <= 3
        ? skills.join(', ')
        : `${skills.slice(0, 3).join(', ')} +${skills.length - 3}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    tickets: any;
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
                  eq: { assigneeName: this.args.model?.title ?? '—' },
                },
              }
            : undefined;
        },
        () => (realm ? [realm] : []),
        { isLive: true },
      );
    }
    get assigned(): any[] {
      return ((this.tickets?.instances ?? []) as any[]).filter(
        (t) => t && !['Resolved', 'Closed'].includes(t.status),
      );
    }
    get paused() {
      return this.assigned.filter((t) => t.slaState === 'paused').length;
    }
    get skills(): string[] {
      return (this.args.model?.skills ?? []).filter(Boolean) as string[];
    }
    openTicket = (t: any) => (this.args as any).viewCard?.(t);
    <template>
      <IsoFrame>
        <RecCard @inset={{true}}>
          <RecHead
            @mark={{initials @model.title}}
            @title={{@model.title}}
            @sub={{@model.tierLabel}}
          >
            <:status>
              {{#if @model.tier}}<Chip
                  @appearance='plain'
                >{{@model.tier}}</Chip>{{/if}}
              <Chip @appearance='plain'>{{this.assigned.length}} assigned</Chip>
            </:status>
          </RecHead>
          <RecStats>
            <Stat
              @label='Tier'
              @tone='neutral'
              @value={{if @model.tier @model.tier '—'}}
              @hint={{@model.tierDescriptor}}
              @roll={{false}}
            />
            <Stat
              @label='Assigned'
              @tone='neutral'
              @value={{this.assigned.length}}
              @hint='{{this.paused}} paused on customer'
              @roll={{false}}
            />
            <Stat
              @label='Skills'
              @tone='neutral'
              @value={{this.skills.length}}
              @hint={{@model.skillSummary}}
              @roll={{false}}
            />
          </RecStats>
          <RecBody>
            <:main>
              <RecBlock @title='Skills'>
                <RecText><span class='mono'>{{if
                      @model.skillSummary
                      @model.skillSummary
                      '—'
                    }}</span></RecText>
              </RecBlock>
              <RecBlock @title='Assigned tickets'>
                {{#each this.assigned as |t|}}
                  <RecLine>
                    <:default><Button
                        @appearance='link'
                        {{on 'click' (fn this.openTicket t)}}
                      ><b>{{t.subject}}</b></Button>
                      <span class='dim'>{{t.reference}}
                        ·
                        {{t.customerName}}
                        ·
                        {{t.priority}}</span></:default>
                    <:end><Chip
                        @appearance='plain'
                        @tone={{if (eq t.status 'Open') 'info' 'warning'}}
                      >{{t.status}}</Chip></:end>
                  </RecLine>
                {{else}}
                  <RecLine><span class='dim'>Nothing assigned.</span></RecLine>
                {{/each}}
              </RecBlock>
              <RecBlock @title='Contact'>
                <RecRow @label='Email'>{{if
                    @model.email
                    @model.email
                    '—'
                  }}</RecRow>
                <RecRow @label='Phone' @mono={{true}}>{{if
                    @model.phone
                    @model.phone
                    '—'
                  }}</RecRow>
              </RecBlock>
            </:main>
            <:side>
              <RecBlock @title='Details'>
                <RecRow @label='Tier'>{{if
                    @model.tierLabel
                    @model.tierLabel
                    '—'
                  }}</RecRow>
                <RecRow @label='Skills'>{{if
                    @model.skillSummary
                    @model.skillSummary
                    '—'
                  }}</RecRow>
                <RecRow @label='Email'>{{if
                    @model.email
                    @model.email
                    '—'
                  }}</RecRow>
                <RecRow @label='Phone' @mono={{true}}>{{if
                    @model.phone
                    @model.phone
                    '—'
                  }}</RecRow>
                <RecRow
                  @label='Assigned'
                  @mono={{true}}
                >{{this.assigned.length}}</RecRow>
                <RecRow @label='Paused' @mono={{true}}>{{this.paused}}</RecRow>
              </RecBlock>
            </:side>
          </RecBody>
        </RecCard>
      </IsoFrame>
      <style scoped>
        .dim {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
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
          @mark={{initials @model.title}}
          @title={{@model.title}}
          @sub={{@model.tierLabel}}
        >
          <:status>{{#if @model.tier}}<Chip
                @appearance='plain'
              >{{@model.tier}}</Chip>{{/if}}</:status>
        </RecHead>
        <p class='fact'>Skills
          <b>{{if @model.skillSummary @model.skillSummary '—'}}</b></p>
        <RecRow @label='Tier'>{{if
            @model.tierLabel
            @model.tierLabel
            '—'
          }}</RecRow>
        <RecRow @label='Skills'>{{if
            @model.skillSummary
            @model.skillSummary
            '—'
          }}</RecRow>
        <RecRow @label='Email'>{{if @model.email @model.email '—'}}</RecRow>
        <RecRow @label='Phone' @mono={{true}}>{{if
            @model.phone
            @model.phone
            '—'
          }}</RecRow>
      </RecCard>
      <style scoped>
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
        <span class='mark' aria-hidden='true'>{{initials @model.title}}</span>
        <span class='nm'>{{@model.title}}</span>
        {{#if @model.tier}}<Chip
            @appearance='plain'
          >{{@model.tier}}</Chip>{{/if}}
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
    // Whole ruled rows the tall fitted sizes add under the RichFittedCard.
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Tier', value: String(m?.tierLabel ?? '') || '—' },
        { key: 'Skills', value: String(m?.skillSummary ?? '') || '—' },
        { key: 'Email', value: String((m as any)?.email ?? '') || '—' },
        { key: 'Phone', value: String((m as any)?.phone ?? '') || '—' },
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}}>
        <:default>
          <RichFittedCard>
            <:avatar><Avatar
                @name={{if @model.title @model.title ''}}
                @shape='square'
                @size={{32}}
              /></:avatar>
            <:title>{{@model.title}}</:title>
            <:subtitle>{{@model.tierLabel}}</:subtitle>
            <:status>{{#if @model.tier}}<Chip
                  @appearance='plain'
                >{{@model.tier}}</Chip>{{/if}}</:status>
            <:fact>Skills
              {{if @model.skillSummary @model.skillSummary '—'}}</:fact>
          </RichFittedCard>
        </:default>
      </FittedExtras>
    </template>
  };
}
