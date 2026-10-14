import {
  Component,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import BallFootballIcon from '@cardstack/boxel-icons/ball-football';

import { Event } from '../events/event';
import CountField from '../../fields/count/count-field';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';

const MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/** The day and short month of a kickoff, for the date anchors. */
export function datePart(
  value?: Date | null,
): { day: string; month: string } | null {
  if (!value) {
    return null;
  }
  let d = new Date(value);
  if (Number.isNaN(d.getTime())) {
    return null;
  }
  return { day: String(d.getDate()), month: MONTHS[d.getMonth()] };
}

export const HomeAwayField = enumField(StringField, {
  displayName: 'Home / Away',
  options: [
    { value: 'Home', label: 'Home' },
    { value: 'Away', label: 'Away' },
  ],
});

export const CompetitionField = enumField(StringField, {
  displayName: 'Competition',
  options: ['League', 'Cup', 'Friendly'],
});

function concatPercent(n: number): string {
  return `${n}% sold`;
}

function formatCount(n: number): string {
  return new Intl.NumberFormat().format(n);
}

function eqAway(value?: string): boolean {
  return value === 'Away';
}

function soldStats(
  model: Match,
):
  | { sold: number; total: number; percent: number; soldOut: boolean }
  | undefined {
  let total = model.capacity?.total;
  if (!total || total <= 0) {
    return undefined;
  }
  let sold = model.ticketsSold ?? 0;
  let percent = Math.min(100, Math.round((sold / total) * 100));
  return { sold, total, percent, soldOut: sold >= total };
}

/**
 * A fixture IS an Event — the club adds who we play, where we stand in the
 * tie, and the ops-maintained sales tally. `capacity` (the ceiling and its
 * allocations), venue, kickoff and status are consumed unchanged from the
 * block.
 *
 * `ticketsSold` is the box office's own running total (it includes season
 * tickets and sales outside this system), which is why it is a stored
 * baseline the ops team maintains rather than a count of Booking cards.
 */
export class Match extends Event {
  static displayName = 'Match';
  static icon = BallFootballIcon;

  @field opponent = contains(StringField);
  @field homeAway = contains(HomeAwayField);
  @field competition = contains(CompetitionField);
  @field ticketsSold = contains(CountField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Match) {
      if (this.opponent?.trim()?.length) {
        return `${this.homeAway === 'Away' ? 'at' : 'v'} ${this.opponent}`;
      }
      return this.title?.trim()?.length ? this.title : 'Untitled Match';
    },
  });

  static atom = class Atom extends Component<typeof Event> {
    get match(): Match {
      return this.args.model as unknown as Match;
    }
    <template>
      <span class='ma-atom'>
        <BallFootballIcon class='ma-icon' />
        <span class='ma-name'>{{this.match.cardTitle}}</span>
      </span>
      <style scoped>
        .ma-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          font-size: 0.8125rem;
          font-weight: 500;
        }
        .ma-icon {
          width: 14px;
          height: 14px;
          flex-shrink: 0;
          color: var(--muted-foreground);
        }
        .ma-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Event> {
    get match(): Match {
      return this.args.model as unknown as Match;
    }
    get date() {
      return datePart(this.args.model.startsAt);
    }
    get sold() {
      return soldStats(this.match);
    }
    <template>
      <div class='ma'>
        <div class='ma-date'>
          {{#if this.date}}
            <span class='ma-day'>{{this.date.day}}</span>
            <span class='ma-month'>{{this.date.month}}</span>
          {{else}}
            <span class='ma-day ma-tbd'>?</span>
            <span class='ma-month'>TBD</span>
          {{/if}}
        </div>
        <div class='ma-info'>
          <span class='ma-title'>{{this.match.cardTitle}}</span>
          <span class='ma-meta'>
            {{#if this.match.homeAway}}<span
                class='ha ha-{{this.match.homeAway}}'
              >{{this.match.homeAway}}</span>{{/if}}
            {{#if this.match.competition}}{{this.match.competition}}{{/if}}
            {{#if this.match.venue.name}}· {{this.match.venue.name}}{{/if}}
          </span>
        </div>
        {{#if this.sold}}
          <span class='ma-sold {{if this.sold.soldOut "out"}}'>{{if
              this.sold.soldOut
              'SOLD OUT'
              (concatPercent this.sold.percent)
            }}</span>
        {{/if}}
      </div>
      <style scoped>
        .ma {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
        }
        .ma-date {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          width: 2.75rem;
          height: 2.75rem;
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          background: var(--muted);
          flex-shrink: 0;
        }
        .ma-day {
          font-size: 1rem;
          font-weight: 700;
          line-height: 1.1;
          font-variant-numeric: tabular-nums;
        }
        .ma-tbd {
          color: var(--muted-foreground);
        }
        .ma-month {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground);
        }
        .ma-info {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }
        .ma-title {
          font-weight: 600;
          font-size: 0.875rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .ma-meta {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.75rem;
          color: var(--muted-foreground);
          overflow: hidden;
          white-space: nowrap;
        }
        .ha {
          font-size: 0.5625rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.06em;
          padding: 0.0625rem 0.375rem;
          border-radius: 999px;
        }
        .ha-Home {
          background: color-mix(
            in oklch,
            var(--tier-gold-hue, var(--accent)) 18%,
            var(--card)
          );
          color: var(--card-foreground);
        }
        .ha-Away {
          background: var(--muted);
          color: var(--foreground);
        }
        .ma-sold {
          font-size: 0.6875rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .ma-sold.out {
          color: var(--destructive-ink);
          letter-spacing: 0.04em;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Event> {
    get match(): Match {
      return this.args.model as unknown as Match;
    }
    get date() {
      return datePart(this.args.model.startsAt);
    }
    get sold() {
      return soldStats(this.match);
    }
    <template>
      <div class='fitted'>
        <div class='ma-date'>
          {{#if this.date}}
            <span class='ma-day'>{{this.date.day}}</span>
            <span class='ma-month'>{{this.date.month}}</span>
          {{else}}
            <span class='ma-day ma-tbd'>?</span>
            <span class='ma-month'>TBD</span>
          {{/if}}
        </div>
        <div class='info'>
          <span class='title'>{{this.match.cardTitle}}</span>
          <span class='meta line-comp'>
            {{#if this.match.homeAway}}{{this.match.homeAway}}{{/if}}
            {{#if this.match.competition}}· {{this.match.competition}}{{/if}}
          </span>
          <span class='meta line-when'>
            {{#if this.match.startsAt}}<@fields.startsAt />{{/if}}
          </span>
          {{#if this.sold}}
            <span class='line-sold'>
              <ProgressBar
                class='sold-bar'
                @value={{this.sold.percent}}
                @max={{100}}
                @hue={{if this.sold.soldOut 'var(--destructive)'}}
                @valueText='{{this.sold.percent}}% sold'
              />
              <span class='sold-label'>
                {{if
                  this.sold.soldOut
                  'SOLD OUT'
                  (concatPercent this.sold.percent)
                }}
              </span>
            </span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .fitted {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          width: 100%;
          height: 100%;
          padding: 0.625rem 0.75rem;
          box-sizing: border-box;
          overflow: hidden;
        }
        .ma-date {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          width: 2.5rem;
          height: 2.5rem;
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          background: var(--muted);
          flex-shrink: 0;
        }
        .ma-day {
          font-size: 0.9375rem;
          font-weight: 700;
          line-height: 1.1;
          font-variant-numeric: tabular-nums;
        }
        .ma-tbd {
          color: var(--muted-foreground);
        }
        .ma-month {
          font-size: 0.5rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--muted-foreground);
        }
        .info {
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .line-comp,
        .line-when,
        .line-sold {
          display: none;
        }
        /* Badge degradation: at strip height there is only room for the
           date anchor and the opponent. */
        @container fitted-card (max-height: 50px) {
          .fitted {
            padding: 0.25rem 0.5rem;
            gap: 0.5rem;
          }
          .ma-date {
            width: 2rem;
            height: 2rem;
          }
        }
        @container fitted-card (min-height: 65px) {
          .line-when {
            display: block;
          }
        }
        @container fitted-card (min-height: 170px) {
          .fitted {
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            padding: 0.875rem;
          }
          .line-comp {
            display: block;
          }
          .line-sold {
            display: flex;
            align-items: center;
            gap: 0.375rem;
            width: 100%;
          }
        }
        .sold-bar {
          flex: 1;
          min-width: 0;
        }
        .sold-label {
          font-size: 0.625rem;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Event> {
    get match(): Match {
      return this.args.model as unknown as Match;
    }
    get sold() {
      return soldStats(this.match);
    }
    <template>
      <article class='ma-page'>
        <header class='mh'>
          <div class='mh-id'>
            <p class='doc-kind'>
              {{if this.match.competition this.match.competition 'Fixture'}}
              {{#if this.match.homeAway}}·
                <span
                  class='ha ha-{{this.match.homeAway}}'
                >{{this.match.homeAway}}</span>{{/if}}
            </p>
            <h1 class='duel'>
              {{#if this.match.opponent}}
                <span class='duel-vs'>{{if
                    (eqAway this.match.homeAway)
                    'at'
                    'v'
                  }}</span>
                {{this.match.opponent}}
              {{else}}
                {{this.match.cardTitle}}
              {{/if}}
            </h1>
            <p class='mh-when'>
              {{#if this.match.startsAt}}
                <@fields.startsAt />
                {{#if this.match.endsAt}}&nbsp;–&nbsp;<@fields.endsAt />{{/if}}
              {{else}}
                Kickoff to be announced
              {{/if}}
            </p>
          </div>
          {{#if this.match.status}}
            <span class='mh-status'><@fields.status @format='embedded' /></span>
          {{/if}}
        </header>

        {{#if this.sold}}
          <section class='panel sales'>
            <h2>Box office</h2>
            <div class='sold-row'>
              <span class='sold-big {{if this.sold.soldOut "out"}}'>
                {{if
                  this.sold.soldOut
                  'SOLD OUT'
                  (concatPercent this.sold.percent)
                }}
              </span>
              <span class='sold-detail'>{{formatCount this.sold.sold}}
                of
                {{formatCount this.sold.total}}
                {{if this.match.capacity.unit this.match.capacity.unit 'seats'}}
                sold</span>
            </div>
            <ProgressBar
              class='sold-bar'
              @value={{this.sold.percent}}
              @max={{100}}
              @hue={{if this.sold.soldOut 'var(--destructive)'}}
              @valueText='{{this.sold.percent}}% sold'
            />
            {{#if this.match.capacity.total}}
              <div class='alloc'>
                <@fields.capacity @format='embedded' />
              </div>
            {{/if}}
          </section>
        {{else if this.match.capacity.total}}
          <section class='panel'>
            <h2>Capacity</h2>
            <@fields.capacity @format='embedded' />
          </section>
        {{/if}}

        {{#if this.match.venue}}
          <section class='panel'>
            <h2>Venue</h2>
            <div class='venue'><@fields.venue @format='embedded' /></div>
          </section>
        {{/if}}
        {{#if this.match.description}}
          <section class='panel'>
            <h2>About</h2>
            <div class='about'><@fields.description /></div>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .ma-page {
          max-width: 44rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
        }
        .mh {
          display: flex;
          align-items: center;
          gap: 1rem;
          border-bottom: 2px solid var(--foreground);
          padding-bottom: 1.25rem;
        }
        .mh-id {
          flex: 1;
          min-width: 0;
        }
        .doc-kind {
          display: flex;
          align-items: center;
          gap: 0.375rem;
          margin: 0 0 0.125rem;
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.14em;
          color: var(--muted-foreground);
        }
        .ha {
          font-size: 0.5625rem;
          font-weight: 700;
          padding: 0.0625rem 0.4375rem;
          border-radius: 999px;
          letter-spacing: 0.06em;
        }
        .ha-Home {
          background: color-mix(
            in oklch,
            var(--tier-gold-hue, var(--accent)) 18%,
            var(--card)
          );
          color: var(--card-foreground);
        }
        .ha-Away {
          background: var(--muted);
          color: var(--foreground);
        }
        .duel {
          margin: 0;
          font-size: 2rem;
          line-height: 1.05;
          font-family: var(--font-heading, inherit);
        }
        .duel-vs {
          font-size: 1.125rem;
          font-weight: 500;
          color: var(--muted-foreground);
          margin-right: 0.25rem;
        }
        .mh-when {
          margin: 0.375rem 0 0;
          font-size: 0.875rem;
          color: var(--muted-foreground);
        }
        .mh-status {
          flex-shrink: 0;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: 1rem 1.25rem;
          background: var(--card);
        }
        h2 {
          margin: 0 0 0.75rem;
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.1em;
          color: var(--muted-foreground);
        }
        .sold-row {
          display: flex;
          align-items: baseline;
          gap: 0.75rem;
          margin-bottom: 0.5rem;
        }
        .sold-big {
          font-size: 1.75rem;
          font-weight: 800;
          font-variant-numeric: tabular-nums;
          line-height: 1;
        }
        .sold-big.out {
          color: var(--destructive-ink);
          letter-spacing: 0.03em;
        }
        .sold-detail {
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
        .sold-bar {
          flex: 1;
          min-width: 0;
        }
        .venue {
          border: 1px solid var(--border);
          border-radius: 0.5rem;
        }
        .about {
          font-size: 0.875rem;
          line-height: 1.6;
        }
      </style>
    </template>
  };
}
