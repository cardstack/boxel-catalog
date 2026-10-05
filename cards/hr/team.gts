import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import UsersIcon from '@cardstack/boxel-icons/users';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import type { KeyValueItem } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';

import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { FactList } from '@cardstack/catalog/cards/hr/hr-ui';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import { liveCount } from '@cardstack/catalog/cards/hr/utils';

export class Team extends CardDef {
  static displayName = 'Team';
  static icon = UsersIcon;

  @field name = contains(StringField);
  @field mission = contains(StringField);
  @field lead = linksTo(() => Employee);
  @field members = linksToMany(() => Employee);

  @field title = contains(StringField, {
    computeVia: function (this: Team) {
      return this.name?.trim() || 'Unnamed Team';
    },
  });

  // Denormalized for fitted: prerendered fitted does not resolve linksTo,
  // so the lead's name and the member tally must exist as own attributes.
  @field leadName = contains(StringField, {
    computeVia: function (this: Team) {
      return this.lead?.name ?? '';
    },
  });

  @field memberTally = contains(StringField, {
    computeVia: function (this: Team) {
      return String(liveCount(this.members));
    },
  });

  @field headcount = contains(StringField, {
    computeVia: function (this: Team) {
      let count = liveCount(this.members);
      return `${count} ${count === 1 ? 'member' : 'members'}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get markName() {
      return this.args.model?.name?.trim() || '?';
    }

    get memberCount(): number {
      return liveCount(this.args.model?.members);
    }

    get members() {
      return (this.args.model?.members ?? []).filter(Boolean);
    }

    // Members carry their own status; surfacing the split here means a
    // manager sees "3 active, 1 onboarding" without opening anyone.
    get statusSplit() {
      let counts: Record<string, number> = {};
      for (let m of this.members) {
        let k = (m as any)?.status ?? 'unknown';
        counts[k] = (counts[k] ?? 0) + 1;
      }
      return Object.entries(counts).map(
        ([status, count]): KeyValueItem => ({
          key: status,
          value: String(count),
        }),
      );
    }

    get leadName(): string | undefined {
      return (this.args.model?.lead as any)?.name ?? undefined;
    }

    <template>
      <article class='team-isolated'>
        <header class='hero'>
          <Avatar
            class='team-mark'
            @name={{this.markName}}
            @hue={{AVATAR_HUE}}
            @size={{52}}
            aria-hidden='true'
          />
          <div class='hero-text'>
            <h1>{{@model.title}}</h1>
            <p class='byline'>
              {{if @model.headcount @model.headcount '0 members'}}
              {{#if this.leadName}}
                <span class='sep-dot'>&middot;</span>
                led by
                {{this.leadName}}
              {{/if}}
            </p>
            {{#if @model.mission}}
              <p class='mission'>{{@model.mission}}</p>
            {{/if}}
          </div>
          <div class='hero-num'>
            <Stat
              class='num'
              @label='On the team'
              @value={{this.memberCount}}
              @roll={{false}}
            />
          </div>
        </header>

        <div class='body'>
          <div class='main'>
            <h2 class='panel-title'>Members</h2>
            {{#if @model.members.length}}
              <ul class='member-list'>
                {{#each @fields.members as |Member|}}
                  <li><Member
                      @format='embedded'
                      @displayContainer={{false}}
                    /></li>
                {{/each}}
              </ul>
            {{else}}
              <EmptyState
                class='empty'
                @texture={{false}}
                @title='No members yet'
                @message='Link an employee to build the team.'
              />
            {{/if}}
          </div>

          <aside class='side'>
            <h2 class='panel-title'>Composition</h2>
            <dl class='stacked'>
              <dt>Headcount</dt>
              <dd>{{if @model.headcount @model.headcount '0 members'}}</dd>
              <dt>Lead</dt>
              <dd>{{#if @model.lead}}<@fields.lead
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}&mdash;{{/if}}</dd>
            </dl>

            {{#if this.statusSplit.length}}
              <h2 class='panel-title spaced'>By status</h2>
              <FactList @items={{this.statusSplit}} />
            {{/if}}
          </aside>
        </div>
      </article>
      <style scoped>
        .team-isolated {
          container-type: inline-size;
          container-name: iso;
          height: 100%;
          overflow-y: auto;
          display: flex;
          flex-direction: column;
        }
        .hero {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border);
        }
        /* A team's mark is square, so it never reads as a person's avatar. */
        .hero .team-mark {
          border-radius: var(--boxel-border-radius);
        }
        .hero-text {
          flex: 1;
          min-width: 0;
        }
        h1 {
          margin: 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 750;
          letter-spacing: -0.02em;
          line-height: 1.2;
          overflow-wrap: anywhere;
        }
        .byline {
          margin: var(--boxel-sp-5xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .sep-dot {
          margin: 0 0.25rem;
        }
        .mission {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          line-height: 1.6;
          max-width: 52ch;
        }
        .hero-num {
          flex: none;
          text-align: right;
        }
        .num {
          --text-stat: 1.9rem;
          justify-items: end;
        }
        .body {
          display: grid;
          grid-template-columns: 1fr 17rem;
          /* Fill whatever height is left so the aside's surface reaches the
             bottom edge. Without this the grid is only as tall as its content
             and the panel stops mid-card, reading as a cut-off seam. */
          flex: 1;
          min-height: 0;
          align-content: start;
        }
        .main {
          padding: var(--boxel-sp-lg);
          min-width: 0;
        }
        .side {
          padding: var(--boxel-sp-lg);
          border-left: 1px solid var(--border);
          background-color: var(--muted);
          color: var(--foreground);
        }
        .panel-title {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
        }
        .panel-title.spaced {
          margin-top: var(--boxel-sp-lg);
        }
        .member-list {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .member-list > li {
          border: 1px solid var(--border);
          border-radius: var(--boxel-border-radius-sm);
          overflow: hidden;
        }
        .empty {
          --space-9: var(--boxel-sp);
          --space-6: var(--boxel-sp);
          --text-heading: var(--boxel-font-size);
        }
        .stacked {
          margin: 0;
          display: grid;
        }
        .stacked dt {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          padding-top: 0.4rem;
        }
        .stacked dd {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          overflow-wrap: anywhere;
          font-variant-numeric: tabular-nums;
        }
        @container iso (max-width: 40rem) {
          .body {
            grid-template-columns: 1fr;
          }
          .side {
            border-left: 0;
            border-top: 1px solid var(--border);
          }
          .hero {
            flex-wrap: wrap;
          }
          .hero-num {
            text-align: left;
          }
          .num {
            justify-items: start;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='team-embedded'>
        <header>
          <h3>{{@model.title}}</h3>
          <span class='headcount'>{{@model.headcount}}</span>
        </header>
        {{#if @model.mission}}
          <p class='mission'>{{@model.mission}}</p>
        {{/if}}
        {{#if @model.lead}}
          <div class='lead'>
            <span class='label'>Lead</span>
            <@fields.lead @format='atom' @displayContainer={{false}} />
          </div>
        {{/if}}
      </div>
      <style scoped>
        .team-embedded {
          padding: var(--boxel-sp);
          background-color: var(--card);
          color: var(--card-foreground);
          transition: box-shadow 0.15s ease-out;
        }
        header {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
        }
        h3 {
          margin: 0;
          font-size: var(--boxel-font-size);
        }
        .headcount {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .mission {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .lead {
          margin-top: var(--boxel-sp-xs);
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .label {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='team-atom'>
        <UsersIcon class='team-atom-icon' />
        <span class='team-atom-name'>{{@model.title}}</span>
      </span>
      <style scoped>
        .team-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .team-atom-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .team-atom-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get markName() {
      return this.args.model?.name?.trim() || '?';
    }

    <template>
      <article class='fit'>
        <div class='fit-top'>
          {{! Avatar sizes itself from @size, so the smallest tier mounts its
              own 20px mark and the container queries show one of the two. }}
          <Avatar
            class='team-mark mark-lg'
            @name={{this.markName}}
            @hue={{AVATAR_HUE}}
            @size={{26}}
            aria-hidden='true'
          />
          <Avatar
            class='team-mark mark-sm'
            @name={{this.markName}}
            @hue={{AVATAR_HUE}}
            @size={{20}}
            aria-hidden='true'
          />
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.title}}</h3>
            {{#if @model.leadName}}
              <span class='fit-eb'>led by {{@model.leadName}}</span>
            {{/if}}
          </div>
          {{! Headcount rides in the pill slot — it is this card's status. }}
          <StatePill
            class='fit-pill'
            @label={{if @model.headcount @model.headcount '0 members'}}
            @dot={{true}}
          />
        </div>

        {{#if @model.mission}}
          <p class='fit-mission'>{{@model.mission}}</p>
        {{/if}}

        <dl class='fit-add'>
          <div><dt>Members</dt><dd>{{if
                @model.memberTally
                @model.memberTally
                '0'
              }}</dd></div>
          {{#if @model.leadName}}
            <div><dt>Lead</dt><dd>{{@model.leadName}}</dd></div>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        /* Four tiers, each ADDING a field. Nothing shrinks below 11px. */
        .fit {
          height: 100%;
          /* Flex, not a three-row grid: with `minmax(0, 1fr)` in the middle
             a taller bottom block squeezed the middle row and clipped its
             text. Here the middle keeps its natural height and the extras
             block is pushed to the bottom by `margin-top: auto`. */
          display: flex;
          flex-direction: column;
          gap: 0.3rem;
          padding: 0.55rem 0.6rem;
          overflow: hidden;
          background-color: var(--card);
          color: var(--card-foreground);
          --fit-name: clamp(0.6875rem, 3.2cqi, 0.9375rem);
          --fit-small: clamp(0.6875rem, 2.6cqi, 0.75rem);
        }
        .fit > * {
          min-height: 0;
          overflow: hidden;
        }
        .fit-top {
          flex: none;
          display: flex;
          align-items: flex-start;
          gap: 0.4rem;
          flex-wrap: wrap;
        }
        .fit-top .team-mark {
          border-radius: 0.25rem;
        }
        .fit-top .mark-sm {
          display: none;
        }
        .fit-head {
          flex: 1;
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--fit-name);
          font-weight: 700;
          line-height: 1.25;
          letter-spacing: -0.01em;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          display: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .fit-pill {
          flex: none;
          align-self: flex-start;
        }
        .fit-mission {
          display: none;
          margin: 0;
          font-size: var(--fit-small);
          line-height: 1.5;
          color: var(--muted-foreground);
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-add {
          display: none;
          margin: 0;
          margin-top: auto;
          padding-top: 0.3rem;
          border-top: 1px dashed var(--border);
          grid-template-columns: 1fr 1fr;
          gap: 0.05rem 0.5rem;
        }
        .fit-add > div {
          display: flex;
          gap: 0.25rem;
          min-width: 0;
        }
        .fit-add dt {
          flex: none;
          font-size: var(--fit-small);
          color: var(--muted-foreground);
        }
        .fit-add dd {
          margin: 0;
          font-size: var(--fit-small);
          font-weight: 600;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        /* TIER 2 — add the lead. Two rules: container queries have no `or`. */
        @container fitted-card (height > 80px) {
          .fit-eb {
            display: block;
          }
        }
        @container fitted-card (width > 240px) {
          .fit-eb {
            display: block;
          }
        }
        /* TIER 3 — add the mission. */
        @container fitted-card (height > 130px) and (width > 180px) {
          .fit-mission {
            display: -webkit-box;
          }
        }
        /* TIER 4 — width-driven extra facts (previously missing entirely). */
        @container fitted-card (height > 150px) and (width > 180px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr;
          }
        }
        @container fitted-card (width > 340px) and (height > 130px) {
          .fit-add {
            display: grid;
            grid-template-columns: 1fr 1fr;
          }
        }
        /* Short strip: horizontal, one-line name. */
        @container fitted-card (height <= 90px) {
          .fit {
            grid-template-rows: 1fr;
            align-content: center;
          }
          .fit-top {
            align-items: center;
            flex-wrap: nowrap;
          }
          .fit-pill {
            align-self: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        /* Smallest: drop the lead, keep the headcount pill. */
        @container fitted-card (height <= 50px) {
          .fit-top .mark-lg {
            display: none;
          }
          .fit-top .mark-sm {
            display: inline-flex;
          }
          .fit-eb {
            display: none;
          }
        }
      </style>
    </template>
  };
}
