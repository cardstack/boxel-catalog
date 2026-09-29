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
import {
  type Query,
  rri,
  searchEntryWireQueryFromQuery,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import InboxIcon from '@cardstack/boxel-icons/inbox';
import UsersIcon from '@cardstack/boxel-icons/users';

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

import {
  SupportAgent,
  AgentTierField,
  AGENT_TIER_LABELS,
} from './support-agent';
import { SlaPolicy } from './sla-policy';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { LoadingState } from '@cardstack/pretui/components/loading-state';

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
    get realms(): string[] {
      let url = this.args.model?.[realmURL];
      return url ? [url.href] : [];
    }

    // One query feeds every view of this queue. Two queries is how a board and
    // a table start disagreeing about how many tickets are open.
    get openQuery(): Query | undefined {
      let ticketRef = ticketRefIn(this.realms[0]);
      if (!ticketRef) {
        return undefined;
      }
      return {
        // ONE anchored node, not a bare type node beside an unanchored `eq`.
        //
        // `{ every: [{ type: ref }, { eq: {...} }] }` translates to a wire
        // node carrying only `item.on` next to an `eq` that names no type at
        // all, and the result is empty — which is how this list read "nothing
        // waiting" while the queue counted tickets three feet to the left.
        // `on` both anchors the field paths and constrains the type, and it
        // is adoption-aware, so Incident and ServiceRequest are included
        // where a `_cardType` display-name match dropped them.
        filter: {
          on: ticketRef,
          eq: { queueName: this.args.model?.title ?? '\u2014' },
        },
        // Nearest breach first. Created-date order only equals urgency order
        // when every ticket carries the same promise, which is never.
        //
        // `on` is not optional here either: a sort without it returns an
        // empty result rather than an unsorted one.
        sort: [{ by: 'slaDeadline', on: ticketRef, direction: 'asc' }],
      };
    }

    get wireQuery(): SearchEntryWireQuery | undefined {
      let query = this.openQuery;
      if (!this.realms.length || !query) {
        return undefined;
      }
      return {
        ...searchEntryWireQueryFromQuery(query),
        realms: this.realms,
      };
    }

    open = (id: string, _event?: Event) => {
      if (id) {
        (this.args as any).viewCard?.(new URL(id));
      }
    };

    <template>
      <article class='iso'>
        <header class='iso-head'>
          <div class='iso-id'>
            <h1>{{@model.title}}</h1>
            {{#if @model.description}}
              <p class='iso-sub'>{{@model.description}}</p>
            {{/if}}
          </div>
          {{#if @model.tier}}
            <StatePill @label={{@model.tierLabel}} @hue='teal' />
          {{/if}}
          <span class='iso-agents'>{{@model.agentCount}}</span>
        </header>

        <div class='queue-bar'>
          <span class='queue-sort'>Sorted by nearest breach</span>
        </div>

        {{#if @context.searchResultsComponent}}
          {{#let (component @context.searchResultsComponent) as |Search|}}
            <Search @query={{this.wireQuery}} @mode='none' as |results|>
              <ul class='q-grid'>
                {{#each results.entries key='id' as |entry|}}
                  <li class='q-tile'>
                    <entry.component />
                  </li>
                {{else}}
                  {{#if results.isLoading}}
                    <li class='q-note'>
                      <LoadingState
                        class='q-loading'
                        @label='Loading this queue'
                      />
                    </li>
                  {{else}}
                    {{! An empty queue is GOOD NEWS and has to look like it.
                        This said "No results were found" — the base CardList's
                        generic string, which reads as a failed search on a
                        surface where nothing was searched for. }}
                    <li class='q-clear'>
                      <EmptyState
                        class='q-empty'
                        @title='Nothing waiting in this queue'
                        @message='Everything routed here has been answered. New work lands at the top of this list.'
                        @texture={{false}}
                      />
                    </li>
                  {{/if}}
                {{/each}}
              </ul>
            </Search>
          {{/let}}
        {{else}}
          <EmptyState
            class='empty'
            @title='No live list here'
            @message='Open this queue in the console to see its live list.'
            @texture={{false}}
          />
        {{/if}}

        <section class='team'>
          <h2><UsersIcon class='sec-icon' role='presentation' />Who works this
            queue</h2>
          {{#if @model.agents.length}}
            <ul class='team-list'>
              {{#each @fields.agents as |Agent|}}
                <li><Agent @format='atom' /></li>
              {{/each}}
            </ul>
          {{else}}
            <EmptyState
              class='empty'
              @title='Nobody is assigned to this queue yet'
              @message='Tickets routed here will sit unclaimed — and their clocks keep running.'
              @texture={{false}}
            />
          {{/if}}
        </section>
      </article>

      <style scoped>
        .iso {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          min-height: 100%;
        }
        .iso-head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp);
          flex-wrap: wrap;
          padding-bottom: var(--boxel-sp);
          border-bottom: 1px solid var(--border);
        }
        .iso-id {
          flex: 1;
          min-width: 0;
        }
        .iso-head h1 {
          margin: 0;
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          letter-spacing: -0.01em;
        }
        .iso-sub {
          margin: 0;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-sm);
        }
        .iso-agents {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .queue-bar {
          display: flex;
          align-items: center;
          justify-content: flex-end;
        }
        .queue-sort {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }

        /* The tile grid. This markup shipped with no CSS at all, which is why
           the empty state rendered as a bare bullet in the document flow —
           a state message indistinguishable from a line of data. */
        .q-grid {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
          gap: var(--boxel-sp-xs);
        }
        .q-tile {
          min-width: 0;
          height: 6.5rem;
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-sm);
          overflow: hidden;
          background-color: var(--card);
        }
        /* A state message spans the whole grid, so it reads as "the list is
           telling you something" rather than as a row. */
        .q-note,
        .q-clear {
          grid-column: 1 / -1;
        }
        .q-note {
          padding: var(--boxel-sp) var(--boxel-sp-sm);
          border: 1px dashed var(--border);
          border-radius: var(--boxel-border-radius-sm);
        }
        /* Pret UI LoadingState: its dim shimmer stop (--ink-3) falls back to
           a 2.2:1 grey, so it is pointed at the muted foreground. */
        .q-loading {
          --ink-3: var(--muted-foreground);
          --text-ui-md: var(--boxel-font-size-sm);
        }
        /* An empty queue is good news, so the well carries the success hue as
           a stripe, never as the text. */
        .q-clear {
          border-inline-start: 0.1875rem solid var(--success);
          border-radius: var(--boxel-border-radius-sm);
          overflow: hidden;
        }
        /* Pret UI EmptyState, tuned through its spacing and title knobs to a
           compact well. */
        .q-empty,
        .empty {
          --space-9: 1rem;
          --space-6: 1rem;
          --text-heading: var(--boxel-font-size);
        }
        .team h2 {
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
        .team-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='emb'>
        <span class='emb-name'>{{@model.title}}</span>
        <span class='emb-meta'>{{@model.tierLabel}}
          ·
          {{@model.agentCount}}</span>
      </div>
      <style scoped>
        .emb {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .emb-name {
          font-weight: 700;
          font-size: var(--boxel-font-size-sm);
        }
        .emb-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.title}}
        {{#if @model.tier}}<span class='atom-t'>{{@model.tier}}</span>{{/if}}
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          gap: 0.3rem;
          align-items: baseline;
          font-size: 0.8125rem;
          font-weight: 500;
        }
        .atom-t {
          font-size: 0.625rem;
          font-weight: 700;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <header class='r-head'>
          <InboxIcon class='fit-glyph' role='presentation' />
          <h3 class='title'>{{@model.title}}</h3>
          <span class='badge'>{{@model.tier}}</span>
        </header>
        {{! .line-2 and .blurb both printed `description`, so every size that
            showed both said the same sentence twice. One prose slot only. }}
        <div class='r-body'>
          <span class='line'>{{@model.agentCount}}</span>
          <p class='blurb'>{{@model.description}}</p>
          <span class='tail'>{{@model.policyName}}</span>
        </div>
        <footer class='r-meta'>{{@model.tierDescriptor}}</footer>
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
          align-items: baseline;
          gap: 0.3125rem;
          min-width: 0;
        }
        /* fitted-card Rule 2: the anchor. Without it these cells were a title at
           weight 600 plus a badge — no image, no glyph, and 600 is not the
           "decisively loud" type the rule accepts as a substitute, so all 16
           sizes read as bare text. This is the card's OWN icon, the same one its
           isolated section headers use, which is what makes it identity rather
           than decoration.

           Sized in em with a px floor so it never shrinks to a dot; `align-self`
           because the head is a baseline row and an SVG has no baseline; muted so
           the title stays the loudest thing in the cell. */
        .fit-glyph {
          flex: none;
          align-self: center;
          width: max(0.6875rem, 1.1em);
          height: max(0.6875rem, 1.1em);
          color: var(--muted-foreground);
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
            gap: 1px;
          }
        }
        @container fitted-card (width <= 170px) {
          .fit-glyph {
            display: none;
          }
          /* The glyph is dropped just above, so from here down the anchor is
             type alone — and fitted-card Rule 2's typographic path wants real
             weight. Weight only, never size: at 150px the title is one word from
             wrapping and Rule 1 (nothing clipped) outranks Rule 2. */
          .title {
            font-weight: 700;
          }
        }
      </style>
    </template>
  };
}
