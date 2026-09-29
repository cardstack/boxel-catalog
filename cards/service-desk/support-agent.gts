import {
  Component,
  field,
  contains,
  containsMany,
  StringField,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import { type Query, rri } from '@cardstack/runtime-common';
import CardList from 'https://cardstack.com/base/components/card-list';
import enumField from 'https://cardstack.com/base/enum';
import HeadsetIcon from '@cardstack/boxel-icons/headset';
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
import { eq } from '@cardstack/boxel-ui/helpers';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { AVATAR_HUE } from './components/service-desk-ui';

export const AGENT_TIERS = ['L1', 'L2', 'L3'] as const;

export const AGENT_TIER_LABELS: Record<string, string> = {
  L1: 'L1 · Front line',
  L2: 'L2 · Specialist',
  L3: 'L3 · Engineering',
};

export const AgentTierField = enumField(StringField, {
  displayName: 'Support Tier',
  options: AGENT_TIERS as unknown as string[],
});

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
    get assignedQuery(): Query | undefined {
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
          eq: { assigneeName: this.args.model?.title ?? '\u2014' },
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
        { key: 'Skills', value: model?.skillSummary ?? '' },
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
            <p class='org'>{{@model.tierLabel}}</p>
          </div>
        </header>

        <KeyValue class='facts' @items={{this.facts}}>
          <:value as |row|>
            {{#if (eq row.key 'Email')}}
              <@fields.email />
            {{else}}
              {{row.value}}
            {{/if}}
          </:value>
        </KeyValue>

        {{#if @model.skills.length}}
          <ul class='skills'>
            {{#each @model.skills as |skill|}}
              <li><StatePill @label={{skill}} @hue='teal' /></li>
            {{/each}}
          </ul>
        {{/if}}

        <section class='work'>
          <h2><TicketIcon class='sec-icon' role='presentation' />Assigned to
            them</h2>
          {{#if this.realms.length}}
            <CardList
              @context={{@context}}
              @query={{this.assignedQuery}}
              @realms={{this.realms}}
              @isLive={{true}}
              @format='fitted'
            />
          {{else}}
            <EmptyState
              class='empty'
              @title='Nothing assigned right now'
              @texture={{false}}
            />
          {{/if}}
        </section>
      </article>

      <style scoped>
        .iso {
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
        /* Pret UI KeyValue at the card's 14px text, values in bold. A long
           corporate email wraps inside its column instead of widening it. */
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
        .skills {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-4xs);
        }
        .work h2 {
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
   * The row a ticket shows when it embeds its owner.
   *
   * For an agent looking at somebody else's ticket the question is not "who
   * is this person" but "can they take it" — so the tier and the skills are
   * the content, and the name is the label on them.
   */
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <article class='sa-row'>
        <Avatar
          @name={{if @model.name @model.name '?'}}
          @src={{@model.photo.resolvedUrl}}
          @hue='var(--muted-foreground)'
          @size={{30}}
          aria-hidden='true'
        />
        <span class='sa-main'>
          <span class='sa-line'>
            <span class='sa-name'>{{if
                @model.name
                @model.name
                'Unnamed agent'
              }}</span>
            {{#if @model.tierLabel}}
              <StatePill @label={{@model.tierLabel}} @chrome={{true}} />
            {{/if}}
          </span>
          <span class='sa-dim'>{{if
              @model.skillSummary
              @model.skillSummary
              'No skills recorded'
            }}</span>
        </span>
      </article>

      <style scoped>
        .sa-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          padding: var(--boxel-sp-4xs) 0;
          color: var(--foreground);
        }
        .sa-main {
          flex: 1;
          min-width: 0;
          display: flex;
          flex-direction: column;
        }
        .sa-line {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          min-width: 0;
        }
        .sa-name {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sa-dim {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
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
        {{#if @model.tier}}<span class='atom-tier'>{{@model.tier}}</span>{{/if}}
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
        .atom-tier {
          font-size: 0.5625rem;
          font-weight: 700;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
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
        {{! Was: tierLabel in .line AND .r-meta, skillSummary in .line-2 AND
            .blurb — so most sizes printed two of their four values twice, and
            .line restated the badge. One fact per slot. }}
        <div class='r-body'>
          <span class='line'>{{@model.tierDescriptor}}</span>
          <p class='blurb'>{{@model.skillSummary}}</p>
          <span class='tail'>{{@model.email}}</span>
        </div>
        <footer class='r-meta'>{{@model.phone}}</footer>
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
        .blurb {
          display: none;
          margin: 0;
          font-size: var(--type-base);
          color: var(--muted-foreground);
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
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
        @container fitted-card (height > 160px) {
          .blurb {
            display: -webkit-box;
          }
        }
        @container fitted-card (height > 240px) {
          .blurb {
            -webkit-line-clamp: 4;
          }
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
            gap: 0.0625rem;
          }
        }
        @container fitted-card (width <= 170px) {
        }
      </style>
    </template>
  };
}
