import { markDefinition } from '@cardstack/base/mark-definition';
import {
  Component,
  field,
  contains,
  StringField,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import { Button } from '@cardstack/pretui/components/button';
import enumField from 'https://cardstack.com/base/enum';
import CircleUserIcon from '@cardstack/boxel-icons/circle-user';

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
} from './components/record';

import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { IsoFrame } from '../shared/compact-sheet';

export const CUSTOMER_TIERS = ['VIP', 'Standard', 'Trial'] as const;

export const CustomerTierField = markDefinition(
  enumField(StringField, {
    displayName: 'Customer Tier',
    options: CUSTOMER_TIERS as unknown as string[],
  }),
);

/**
 * Someone who asks for help.
 *
 * Extends `PersonBase` rather than restating name/email/photo — that block was
 * built for the talent tracker, and consuming it here is what turns it from
 * "works" into "reusable". The only things added are the two facts support
 * actually reasons about: who they work for, and what we promised them.
 */
export class SupportContact extends PersonBase {
  static displayName = 'Contact';
  static icon = CircleUserIcon;

  @field company = contains(StringField);
  @field tier = contains(CustomerTierField);

  @field title = contains(StringField, {
    computeVia: function (this: SupportContact) {
      return this.name?.trim() || 'Unnamed contact';
    },
  });

  @field isVip = contains(StringField, {
    computeVia: function (this: SupportContact) {
      return this.tier === 'VIP' ? 'VIP' : '';
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
                  eq: { customerName: this.args.model?.title ?? '—' },
                },
              }
            : undefined;
        },
        () => (realm ? [realm] : []),
        { isLive: true },
      );
    }
    get open(): any[] {
      return ((this.tickets?.instances ?? []) as any[]).filter(
        (t) => t && !['Resolved', 'Closed'].includes(t.status),
      );
    }
    get openHint() {
      let t = this.open[0];
      return t
        ? `${t.reference} ${String(t.status ?? '').toLowerCase()}`
        : 'none open';
    }
    get lastContact() {
      let times = ((this.tickets?.instances ?? []) as any[])
        .flatMap((t) => (t?.messages ?? []).map((m: any) => m?.sentAt))
        .filter(Boolean)
        .map((d: any) => new Date(d).getTime());
      return times.length
        ? new Date(Math.max(...times)).toLocaleDateString('en-GB', {
            month: 'short',
            day: 'numeric',
          })
        : '—';
    }
    openTicket = (t: any) => (this.args as any).viewCard?.(t);
    <template>
      <IsoFrame>
        <RecCard @inset={{true}}>
          <RecHead
            @mark={{initials @model.title}}
            @title={{@model.title}}
            @sub={{@model.company}}
          >
            <:status>
              {{#if @model.tier}}<Chip
                  @appearance='plain'
                >{{@model.tier}}</Chip>{{/if}}
              <Chip @appearance='plain'>{{this.open.length}} open</Chip>
            </:status>
          </RecHead>
          <RecStats>
            <Stat
              @label='Tier'
              @tone='neutral'
              @value={{if @model.tier @model.tier '—'}}
              @roll={{false}}
            />
            <Stat
              @label='Open tickets'
              @tone='neutral'
              @value={{this.open.length}}
              @hint={{this.openHint}}
              @roll={{false}}
            />
            <Stat
              @label='Last contact'
              @tone='neutral'
              @value={{this.lastContact}}
              @roll={{false}}
            />
          </RecStats>
          <RecBody>
            <:main>
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
                <RecRow @label='Company'>{{if
                    @model.company
                    @model.company
                    '—'
                  }}</RecRow>
              </RecBlock>
              <RecBlock @title='Tickets'>
                {{#each this.open as |t|}}
                  <RecLine>
                    <:default><Button
                        @appearance='link'
                        {{on 'click' (fn this.openTicket t)}}
                      ><b>{{t.subject}}</b></Button>
                      <span class='dim'>{{t.reference}}
                        ·
                        {{t.priority}}
                        ·
                        {{t.assigneeName}}</span></:default>
                    <:end><Chip
                        @appearance='plain'
                        @tone={{if (eq t.status 'Open') 'info' 'warning'}}
                      >{{t.status}}</Chip></:end>
                  </RecLine>
                {{else}}
                  <RecLine><span class='dim'>No open tickets.</span></RecLine>
                {{/each}}
              </RecBlock>
            </:main>
            <:side>
              <RecBlock @title='Details'>
                <RecRow @label='Company'>{{if
                    @model.company
                    @model.company
                    '—'
                  }}</RecRow>
                <RecRow @label='Tier'>{{if
                    @model.tier
                    @model.tier
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
                  @label='Open tickets'
                  @mono={{true}}
                >{{this.open.length}}</RecRow>
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
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <RecCard>
        <RecHead
          @mark={{initials @model.title}}
          @title={{@model.title}}
          @sub={{@model.company}}
        >
          <:status>{{#if @model.tier}}<Chip
                @appearance='plain'
              >{{@model.tier}}</Chip>{{/if}}</:status>
        </RecHead>
        <RecRow @label='Company'>{{if
            @model.company
            @model.company
            '—'
          }}</RecRow>
        <RecRow @label='Tier'>{{if @model.tier @model.tier '—'}}</RecRow>
        <RecRow @label='Email'>{{if @model.email @model.email '—'}}</RecRow>
        <RecRow @label='Phone' @mono={{true}}>{{if
            @model.phone
            @model.phone
            '—'
          }}</RecRow>
      </RecCard>
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
        { key: 'Company', value: String((m as any)?.company ?? '') || '—' },
        { key: 'Tier', value: String((m as any)?.tier ?? '') || '—' },
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
            <:subtitle>{{@model.company}}</:subtitle>
            <:status>{{#if @model.tier}}<Chip
                  @appearance='plain'
                >{{@model.tier}}</Chip>{{/if}}</:status>
            <:fact>{{@model.email}}</:fact>
          </RichFittedCard>
        </:default>
      </FittedExtras>
    </template>
  };
}
