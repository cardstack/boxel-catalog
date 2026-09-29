import {
  Component,
  field,
  contains,
  StringField,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import { type Query, rri } from '@cardstack/runtime-common';
import CardList from 'https://cardstack.com/base/components/card-list';
import enumField from 'https://cardstack.com/base/enum';
import CircleUserIcon from '@cardstack/boxel-icons/circle-user';
import TicketIcon from '@cardstack/boxel-icons/ticket';

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
// It was `import.meta.url` until `import.meta` turned out to be unavailable
// under the checker's CommonJS inference (TS1470). The realm URL is already on
// the model, it is what `service-desk.gts` uses to create a ticket, and it
// makes the ref a per-instance value instead of a module-level constant — so
// the same module is correct in whichever realm it is copied into.
function ticketRefIn(realm: string | undefined) {
  return realm
    ? { module: rri(new URL('./ticket', realm).href), name: 'Ticket' }
    : undefined;
}

import { StatePill } from '@cardstack/catalog/components/state-pill';
import { type Hue } from '@cardstack/catalog/components/state-pill';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { AVATAR_HUE } from './components/service-desk-ui';

export const CUSTOMER_TIERS = ['VIP', 'Standard', 'Trial'] as const;

export const CustomerTierField = enumField(StringField, {
  displayName: 'Customer Tier',
  options: CUSTOMER_TIERS as unknown as string[],
});

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
    // Live, not a maintained list of links: a ticket that moves queue, gets
    // merged or is closed must leave this list without anyone editing the
    // contact. It matches on the ticket's denormalized customer name — the
    // same string the tiles themselves render.
    get historyQuery(): Query | undefined {
      let ticketRef = ticketRefIn(this.realms[0]);
      if (!ticketRef) {
        return undefined;
      }
      return {
        // ONE anchored node. A bare type node beside an unanchored `eq`
        // translates to a wire filter whose predicate names no type, and the
        // result is always empty. `on` anchors the field path AND constrains
        // the type, adoption-aware, so Incident and ServiceRequest count.
        filter: {
          on: ticketRef,
          eq: { customerName: this.args.model?.title ?? '\u2014' },
        },
      };
    }

    get realms(): string[] {
      let url = this.args.model?.[realmURL];
      return url ? [url.href] : [];
    }

    get facts() {
      let model = this.args.model;
      return [
        ...(model?.email ? [{ key: 'Email', value: model.email }] : []),
        ...(model?.phone ? [{ key: 'Phone', value: model.phone }] : []),
      ];
    }

    <template>
      <article class='iso'>
        <header class='iso-head'>
          <Avatar
            @name={{if @model.name @model.name '?'}}
            @src={{@model.photo.resolvedUrl}}
            @hue={{AVATAR_HUE}}
            @size={{48}}
            aria-hidden='true'
          />
          <div class='who'>
            <h1>{{@model.title}}</h1>
            {{#if @model.company}}
              <p class='org'>{{@model.company}}</p>
            {{/if}}
          </div>
          <StatePill
            @label={{@model.tier}}
            @hue={{if @model.isVip 'purple' 'slate'}}
            @emphatic={{if @model.isVip true false}}
          />
        </header>

        {{#if this.facts.length}}
          <KeyValue class='facts' @items={{this.facts}}>
            <:value as |row|>
              {{#if (eq row.key 'Email')}}
                <@fields.email />
              {{else}}
                {{row.value}}
              {{/if}}
            </:value>
          </KeyValue>
        {{/if}}

        <section class='hist'>
          <h2><TicketIcon class='sec-icon' role='presentation' />Their tickets</h2>
          {{#if this.realms.length}}
            <CardList
              @context={{@context}}
              @query={{this.historyQuery}}
              @realms={{this.realms}}
              @isLive={{true}}
              @format='fitted'
            />
          {{else}}
            <EmptyState
              class='empty'
              @title='No tickets yet'
              @message='When they write in, everything they have asked before will be here — which is the difference between support and a stranger asking you to explain it again.'
              @texture={{false}}
            />
          {{/if}}
        </section>
      </article>

      <style scoped>
        .iso {
          container-name: iso;
          container-type: inline-size;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          padding: var(--boxel-sp-lg);
          min-height: 100%;
        }
        .iso-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          padding-bottom: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
        }
        .who {
          flex: 1;
          min-width: 0;
        }
        .who h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
        }
        .org {
          margin: 0;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
        }
        /* Pret UI KeyValue at the card's 14px text, values in bold.
           min-width:0 and anywhere-wrapping on the value: a real corporate
           email is long enough to widen the column otherwise, and short demo
           data hides it. */
        .facts {
          --text-ui: var(--boxel-font-size-xs);
          --text-ui-md: var(--boxel-font-size-sm);
          --space-6: var(--boxel-sp);
        }
        .facts :deep(dd) {
          min-width: 0;
          font-weight: 600;
          overflow-wrap: anywhere;
        }
        .hist h2 {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin: 0 0 var(--boxel-sp-xs);
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        /* Rule 5: one icon per section header, quiet by design — muted colour and
           ~1em with a px floor, so it identifies the section without competing
           with it. Same size in every header, which is what makes the card
           scannable by shape on a second visit. */
        .sec-icon {
          width: max(0.875rem, 1em);
          height: max(0.875rem, 1em);
          flex: 0 0 auto;
          color: var(--muted-foreground);
        }
        /* Pret UI EmptyState, tuned through its spacing and title knobs to a
           compact well. */
        .empty {
          --space-9: 1rem;
          --space-6: 1rem;
          --text-heading: var(--boxel-font-size);
        }
      </style>
    </template>
  };

  /**
   * The row a ticket shows when it embeds its customer.
   *
   * An agent picking up a ticket asks three things about the person on the
   * other end, in this order: who are they, who do they work for, and what
   * did we promise them. VIP is the only one that changes what happens next,
   * so it is the only one that carries colour.
   */
  static embedded = class Embedded extends Component<typeof this> {
    get tierHue(): Hue {
      return this.args.model?.tier === 'VIP' ? 'purple' : 'slate';
    }

    <template>
      <article class='sc-row'>
        <Avatar
          @name={{if @model.name @model.name '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue='var(--muted-foreground)'
          @size={{30}}
          aria-hidden='true'
        />
        <span class='sc-main'>
          <span class='sc-line'>
            <span class='sc-name'>{{if
                @model.name
                @model.name
                'Unnamed contact'
              }}</span>
            {{#if @model.tier}}
              <StatePill
                @label={{@model.tier}}
                @hue={{this.tierHue}}
                @emphatic={{if @model.isVip true false}}
              />
            {{/if}}
          </span>
          <span class='sc-dim'>{{if
              @model.company
              @model.company
              'No company on file'
            }}</span>
        </span>
        {{#if @model.email}}
          <span class='sc-contact'><@fields.email /></span>
        {{/if}}
      </article>

      <style scoped>
        .sc-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          padding: var(--boxel-sp-4xs) 0;
          color: var(--foreground);
        }
        .sc-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
        }
        .sc-line {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
        }
        .sc-name {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sc-dim,
        .sc-contact {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        /* Constant slot so a list of contacts column-aligns whether or not a
           given one has an email on file. */
        .sc-contact {
          flex: none;
          width: 12rem;
          text-align: end;
        }
        /* Narrow wraps the email under the name rather than dropping it —
           "how do I reach them" is not a detail worth deleting on a phone. */
        @container (max-width: 26rem) {
          .sc-row {
            flex-wrap: wrap;
          }
          .sc-contact {
            width: 100%;
            padding-left: calc(1.875rem + var(--boxel-sp-xs));
            text-align: start;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>
        <Avatar
          @name={{if @model.name @model.name '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue={{AVATAR_HUE}}
          @size={{18}}
          aria-hidden='true'
        />
        <span class='atom-name'>{{@model.title}}</span>
        {{#if @model.isVip}}<StatePill @label='VIP' @hue='purple' />{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: 0.3rem;
          font-size: 0.8125rem;
        }
        .atom-name {
          font-weight: 500;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <header class='r-head'>
          {{#if @model.photo.resolvedUrl}}
            <img class='av' src={{@model.photo.resolvedUrl}} alt='' />
          {{else}}
            <span class='av'>{{@model.initials}}</span>
          {{/if}}
          <h3 class='title'>{{@model.title}}</h3>
          <span class='badge'>{{@model.tier}}</span>
        </header>
        {{! A contact is four facts — tier, employer, email, phone — but the
            template had five slots, so `company` and `email` each filled two.
            The prose slot is gone rather than padded: a contact record has no
            prose. }}
        <div class='r-body'>
          <span class='line'>{{@model.company}}</span>
          <span class='tail'>{{@model.phone}}</span>
        </div>
        <footer class='r-meta'>{{@model.email}}</footer>
      </article>
      <style scoped>
        /* Same skeleton as ticket.gts: one `.fit` grid, no container declared
           here (the host provides `fitted-card`), one continuous type scale,
           and tiers that ADD a row rather than un-crop one. */
        .fit {
          width: 100%;
          height: 100%;
          display: grid;
          grid-template-rows: auto minmax(0, 1fr) auto;
          grid-template-areas: 'head' 'body' 'meta';
          gap: 0.125rem;
          padding: 0.4375rem 0.5625rem;
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
          --type-base: clamp(0.5938rem, 2.7cqi, 0.75rem);
          --type-title: max(0.6875rem, calc(var(--type-base) * 1.25));
        }
        .fit > * {
          overflow: hidden;
          min-height: 0;
        }
        .r-head {
          grid-area: head;
          display: flex;
          align-items: center;
          gap: 0.3125rem;
          min-width: 0;
        }
        .av {
          flex: none;
          width: 1.35rem;
          height: 1.35rem;
          border-radius: 50%;
          display: grid;
          place-items: center;
          object-fit: cover;
          font-size: var(--type-base);
          font-weight: 700;
          background-color: var(--primary);
          color: var(--primary-foreground);
        }
        .title {
          flex: 1;
          min-width: 0;
          margin: 0;
          font-size: var(--type-title);
          font-weight: 600;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .badge {
          flex: none;
          margin-left: auto;
          font-family: var(--font-mono);
          font-size: var(--type-base);
          font-weight: 600;
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .r-body {
          grid-area: body;
          display: none;
          flex-direction: column;
          gap: 0.125rem;
          min-width: 0;
        }
        .line {
          font-size: var(--type-base);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .tail {
          display: none;
          margin-top: auto;
          font-size: var(--type-base);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .r-meta {
          grid-area: meta;
          display: none;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          font-size: var(--type-base);
          color: var(--muted-foreground);
        }
        @container fitted-card (height <= 50px) {
          .fit {
            grid-template-rows: 1fr;
            align-content: center;
          }
          .title {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (height > 50px) {
          .r-meta {
            display: flex;
          }
        }
        @container fitted-card (height > 50px) and (height <= 105px) {
          .title {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (height > 80px) {
          .r-body {
            display: flex;
          }
        }
        @container fitted-card (height > 240px) {
          .tail {
            display: block;
          }
        }
        @container fitted-card (width > 300px) and (height <= 130px) {
          .fit {
            grid-template-columns: minmax(12.5rem, 1fr) auto;
            grid-template-areas: 'head meta' 'body meta';
            align-items: center;
          }
          .r-meta {
            flex-direction: column;
            align-items: flex-end;
            gap: 1px;
          }
        }
      </style>
    </template>
  };
}
