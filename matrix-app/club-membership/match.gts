import type { TemplateOnlyComponent } from '@ember/component/template-only';
import {
  type CardDef,
  Component,
  contains,
  field,
  getComponent,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import { codeRef, type getCards } from '@cardstack/runtime-common';
import BallFootballIcon from '@cardstack/boxel-icons/ball-football';

import { Event } from '../events/event';
import { FitTile } from '../shared/fit-tile';
import CountField from '@cardstack/catalog/fields/count/count-field';

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const moduleURL: string = import.meta.url;
const bookingRef = codeRef(moduleURL, '../events/booking', 'Booking');

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

const NUM = new Intl.NumberFormat();
const KICKOFF = new Intl.DateTimeFormat(undefined, {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  hour: '2-digit',
  minute: '2-digit',
});
const DATE = new Intl.DateTimeFormat(undefined, {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  year: 'numeric',
});
const TIME = new Intl.DateTimeFormat(undefined, {
  hour: '2-digit',
  minute: '2-digit',
});

function fmt(f: Intl.DateTimeFormat, value?: Date | null): string {
  let d = value ? new Date(value) : undefined;
  return d && !Number.isNaN(d.getTime()) ? f.format(d) : '—';
}
function kickoff(value?: Date | null): string {
  return fmt(KICKOFF, value);
}
function dateOf(value?: Date | null): string {
  return fmt(DATE, value);
}
function timeOf(value?: Date | null): string {
  return fmt(TIME, value);
}
function num(n?: number | null): string {
  return n == null ? '—' : NUM.format(n);
}

function statusTone(status?: string | null): string {
  switch (status) {
    case 'Scheduled':
      return 'primary';
    case 'Live':
      return 'success';
    case 'Cancelled':
      return 'destructive';
    default:
      return 'muted';
  }
}

function payTone(status?: string | null): string {
  return status === 'Paid' ? 'success' : status === 'Unpaid' ? 'warning' : '';
}

function nameOf(m?: Match): string {
  return m?.opponent?.trim() || m?.cardTitle || 'Untitled Match';
}

/** "League · Home" */
function kindLine(m?: Match): string {
  return [m?.competition, m?.homeAway].filter(Boolean).join(' · ');
}

/** "League · Home · Sat 12 Sep, 15:00" */
function metaLine(m?: Match): string {
  return [kindLine(m), m?.startsAt ? kickoff(m.startsAt) : '']
    .filter(Boolean)
    .join(' · ');
}

function soldLine(m?: Match): string {
  let total = m?.capacity?.total;
  let sold = num(m?.ticketsSold ?? 0);
  return total ? `${sold} of ${num(total)} seats sold` : `${sold} sold`;
}

function soldPercent(m?: Match): string {
  let total = m?.capacity?.total;
  if (!total) return 'no capacity set';
  let pct = Math.round(((m?.ticketsSold ?? 0) / total) * 100);
  return `${pct}% of ${num(total)}`;
}

/** A status as dot + text. */
const DotText: TemplateOnlyComponent<{
  Args: { label?: string | null; tone?: string };
}> = <template>
  {{#if @label}}
    <span class='dot-text'><span
        class='dot'
        data-tone={{@tone}}
      ></span>{{@label}}</span>
  {{/if}}
  <style scoped>
    .dot-text {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-4xs);
      font-weight: 600;
      white-space: nowrap;
    }
    .dot {
      flex-shrink: 0;
      width: 0.4375rem;
      height: 0.4375rem;
      border-radius: 50%;
      background-color: var(--muted-foreground);
    }
    .dot[data-tone='primary'] {
      background-color: var(--primary);
    }
    .dot[data-tone='success'] {
      background-color: var(--success);
    }
    .dot[data-tone='warning'] {
      background-color: var(--warning);
    }
    .dot[data-tone='destructive'] {
      background-color: var(--destructive);
    }
  </style>
</template>;

const MatchMark: TemplateOnlyComponent<{ Args: { size?: 'sm' | 'lg' } }> =
  <template>
    <span class='mark' data-size={{@size}} aria-hidden='true'>
      <BallFootballIcon width='0.75rem' height='0.75rem' />
    </span>
    <style scoped>
      .mark {
        display: inline-grid;
        place-items: center;
        flex-shrink: 0;
        width: 1.125rem;
        height: 1.125rem;
        border-radius: 0.25rem;
        background-color: var(--muted);
        color: var(--muted-foreground);
      }
      .mark[data-size='lg'] {
        width: 1.75rem;
        height: 1.75rem;
        border-radius: 0.375rem;
      }
    </style>
  </template>;

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
    get name() {
      return nameOf(this.match);
    }
    <template>
      <span class='atom'>
        <MatchMark />
        <span class='name'>{{this.name}}</span>
        <DotText
          @label={{this.match.status}}
          @tone={{statusTone this.match.status}}
        />
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-3xs);
          max-width: 100%;
          min-width: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground);
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Event> {
    get match(): Match {
      return this.args.model as unknown as Match;
    }
    get name() {
      return nameOf(this.match);
    }
    get meta() {
      return metaLine(this.match);
    }
    <template>
      <article class='emb'>
        <header class='head'>
          <MatchMark @size='lg' />
          <div class='id'>
            <p class='name'>{{this.name}}</p>
            {{#if this.meta}}<p class='meta'>{{this.meta}}</p>{{/if}}
          </div>
          <div class='tags'>
            <DotText
              @label={{this.match.status}}
              @tone={{statusTone this.match.status}}
            />
            <DotText @label={{this.match.homeAway}} />
          </div>
        </header>
        <dl class='kv'>
          <dt>Kick-off</dt><dd>{{kickoff this.match.startsAt}}</dd>
          <dt>Ends</dt><dd>{{timeOf this.match.endsAt}}</dd>
          <dt>Sold</dt><dd class='num'>{{num this.match.ticketsSold}}
            seats</dd>
          <dt>Capacity</dt><dd class='num'>{{num this.match.capacity.total}}
            seats</dd>
          <dt>Competition</dt><dd>{{if
              this.match.competition
              this.match.competition
              '—'
            }}</dd>
          {{#if this.match.venue}}
            <dt>Venue</dt><dd><@fields.venue
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        .emb {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-3xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          background-color: var(--card);
          color: var(--card-foreground);
        }
        .head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        .name,
        .meta {
          margin: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .name {
          font-weight: 700;
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .tags {
          display: flex;
          flex-shrink: 0;
          gap: var(--boxel-sp-xs);
        }
        .kv {
          display: grid;
          grid-template-columns: 7rem minmax(0, 1fr);
          margin: 0;
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-3xs) 0;
          border-top: 1px solid var(--border);
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .kv dt {
          font-family: var(--font-mono);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
          align-self: center;
        }
        .num {
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Event> {
    get match(): Match {
      return this.args.model as unknown as Match;
    }
    get name() {
      return nameOf(this.match);
    }
    get sub() {
      return kindLine(this.match);
    }
    get sold() {
      return soldLine(this.match);
    }
    <template>
      <FitTile>
        <:avatar><MatchMark @size='lg' /></:avatar>
        <:title>{{this.name}}</:title>
        <:subtitle>{{this.sub}}</:subtitle>
        <:status>
          <DotText
            @label={{this.match.status}}
            @tone={{statusTone this.match.status}}
          />
          <DotText @label={{this.match.homeAway}} />
        </:status>
        <:fact>{{this.sold}}</:fact>
        <:relations>{{#if this.match.venue}}<@fields.venue
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Event> {
    private bookingQuery: ReturnType<getCards> | undefined;

    constructor(owner: unknown, args: any) {
      super(owner as never, args as never);
      this.bookingQuery = this.args.context?.getCards(
        this,
        () => {
          let id = this.args.model?.id;
          return id
            ? { filter: { on: bookingRef, eq: { 'event.id': id } } }
            : undefined;
        },
        () => {
          let url = this.args.model?.[realmURL]?.href;
          return url ? [url] : [];
        },
        { isLive: true },
      );
    }

    get match(): Match {
      return this.args.model as unknown as Match;
    }
    get name() {
      return nameOf(this.match);
    }
    get meta() {
      return metaLine(this.match);
    }
    get soldPercent() {
      return soldPercent(this.match);
    }

    // Booking is read by query and string ref, so this module never imports
    // the booking module (which imports Event back).
    get bookings(): any[] {
      return (this.bookingQuery?.instances ?? []) as any[];
    }
    get bookingCards(): CardDef[] {
      return this.bookings as CardDef[];
    }
    get bookingHint(): string {
      let tickets = this.bookings.reduce((a, b) => a + (b.quantity ?? 0), 0);
      let unpaid = this.bookings.filter(
        (b) => b.paymentStatus === 'Unpaid',
      ).length;
      return `${tickets} tickets · ${unpaid} unpaid`;
    }

    <template>
      <article class='page'>
        <header class='head'>
          <MatchMark @size='lg' />
          <div class='id'>
            <h1 class='name'>{{this.name}}</h1>
            {{#if this.meta}}<p class='meta'>{{this.meta}}</p>{{/if}}
          </div>
          <div class='tags'>
            <DotText
              @label={{this.match.status}}
              @tone={{statusTone this.match.status}}
            />
            <DotText @label={{this.match.homeAway}} />
          </div>
        </header>

        <dl class='stats' aria-label='Key numbers'>
          <div class='stat'>
            <dt class='label'>Sold</dt>
            <dd class='value'>{{num this.match.ticketsSold}}</dd>
            <dd class='sub'>{{this.soldPercent}}</dd>
          </div>
          <div class='stat'>
            <dt class='label'>Club bookings</dt>
            <dd class='value'>{{this.bookings.length}}</dd>
            <dd class='sub'>{{this.bookingHint}}</dd>
          </div>
          <div class='stat'>
            <dt class='label'>Kick-off</dt>
            <dd class='value'>{{timeOf this.match.startsAt}}</dd>
            <dd class='sub'>{{dateOf this.match.startsAt}}</dd>
          </div>
          <div class='stat'>
            <dt class='label'>Capacity</dt>
            <dd class='value'>{{num this.match.capacity.total}}</dd>
            <dd class='sub'>{{if
                this.match.capacity.unit
                this.match.capacity.unit
                'seats'
              }}</dd>
          </div>
        </dl>

        <div class='cols'>
          <div class='main'>
            {{#if this.match.description}}
              <section class='sec'>
                <h2>About</h2>
                <div class='body'><@fields.description /></div>
              </section>
            {{/if}}
            {{#if this.match.capacity.allocations.length}}
              <section class='sec'>
                <h2>Capacity</h2>
                <dl class='kv'>
                  {{#each this.match.capacity.allocations as |a|}}
                    <dt>{{a.name}}</dt><dd class='num'>{{num a.quantity}}</dd>
                  {{/each}}
                </dl>
              </section>
            {{/if}}
            <section class='sec'>
              <h2>Club bookings</h2>
              {{#if this.bookings.length}}
                <ul class='rows'>
                  {{#each this.bookings key='id' as |b|}}
                    <li class='row'>
                      <span class='ref'>{{b.reference}}</span>
                      <span class='what'><strong>{{b.holderName}}</strong>
                        <span class='muted'>·
                          {{b.quantity}}
                          tickets{{#if b.rsvp}}
                            ·
                            {{b.rsvp}}{{/if}}</span></span>
                      <DotText
                        @label={{b.paymentStatus}}
                        @tone={{payTone b.paymentStatus}}
                      />
                    </li>
                  {{/each}}
                </ul>
              {{else}}
                <p class='empty'>No club bookings yet</p>
              {{/if}}
            </section>
          </div>

          <aside class='side'>
            <section class='sec'>
              <h2>Linked</h2>
              <dl class='kv'>
                <dt>Venue</dt>
                <dd>{{#if this.match.venue}}<@fields.venue
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
                {{#each this.bookingCards as |b|}}
                  <dt>Booking</dt>
                  <dd>{{#let (getComponent b) as |B|}}<B
                        @format='atom'
                        @displayContainer={{false}}
                      />{{/let}}</dd>
                {{/each}}
              </dl>
            </section>
            <section class='sec'>
              <h2>Details</h2>
              <dl class='kv'>
                <dt>Kick-off</dt><dd>{{kickoff this.match.startsAt}}</dd>
                <dt>Ends</dt><dd>{{timeOf this.match.endsAt}}</dd>
                <dt>Sold</dt><dd class='num'>{{num this.match.ticketsSold}}
                  seats</dd>
                <dt>Capacity</dt><dd class='num'>{{num
                    this.match.capacity.total
                  }}
                  seats</dd>
                <dt>Competition</dt><dd>{{if
                    this.match.competition
                    this.match.competition
                    '—'
                  }}</dd>
                <dt>Home / Away</dt><dd>{{if
                    this.match.homeAway
                    this.match.homeAway
                    '—'
                  }}</dd>
                <dt>Club bookings</dt><dd>{{this.bookings.length}}
                  ·
                  {{this.bookingHint}}</dd>
                <dt>Status</dt><dd>{{if
                    this.match.status
                    this.match.status
                    '—'
                  }}</dd>
              </dl>
            </section>
          </aside>
        </div>
      </article>
      <style scoped>
        .page {
          container-type: inline-size;
          margin: var(--boxel-sp-sm);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background-color: var(--card);
          color: var(--card-foreground);
          font-size: var(--boxel-font-size-xs);
          overflow: hidden;
        }
        .head {
          display: flex;
          align-items: center;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-sm);
          border-bottom: 1px solid var(--border);
        }
        .id {
          flex: 1 1 10rem;
          min-width: 0;
        }
        .name {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .tags {
          display: flex;
          gap: var(--boxel-sp-sm);
          margin-left: auto;
        }
        .stats {
          margin: 0;
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
          border-bottom: 1px solid var(--border);
          overflow: hidden;
        }
        .stat {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-6xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          margin: 0 -1px -1px 0;
          border-right: 1px solid var(--border);
          border-bottom: 1px solid var(--border);
          min-width: 0;
        }
        .stat dt,
        .stat dd {
          margin: 0;
        }
        .label,
        .kv dt {
          font-family: var(--font-mono);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .value {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          line-height: 1.2;
          font-variant-numeric: tabular-nums;
        }
        .sub,
        .muted,
        .empty {
          color: var(--muted-foreground);
        }
        .sub {
          font-size: var(--boxel-font-size-2xs);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        }
        .main {
          border-right: 1px solid var(--border);
        }
        @container (max-width: 44rem) {
          .cols {
            grid-template-columns: minmax(0, 1fr);
          }
          .main {
            border-right: 0;
            border-bottom: 1px solid var(--border);
          }
        }
        .sec + .sec {
          border-top: 1px solid var(--border);
        }
        h2 {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .body {
          padding: var(--boxel-sp-3xs) var(--boxel-sp-sm) var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
          line-height: 1.5;
        }
        .rows {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-3xs) var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
        }
        .ref {
          flex-shrink: 0;
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .what {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .empty {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-top: 1px solid var(--border);
        }
        .kv {
          display: grid;
          grid-template-columns: 8rem minmax(0, 1fr);
          margin: 0;
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-3xs);
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-3xs) 0;
          border-top: 1px solid var(--border);
          min-width: 0;
          display: flex;
          align-items: center;
          flex-wrap: wrap;
        }
        .num {
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}
