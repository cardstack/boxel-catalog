import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  realmURL,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import DateTimeField from 'https://cardstack.com/base/datetime';
import AmountWithCurrency from 'https://cardstack.com/base/amount-with-currency';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import TicketIcon from '@cardstack/boxel-icons/ticket';
import { Alert } from '@cardstack/pretui/components/alert';
import { FitTile } from '../shared/fit-tile';

import { Contact } from '../crm/contact';
import { Event } from './event';
import RsvpStatusField from './rsvp-status-field';
import { statusField } from '@cardstack/catalog/fields/status/status';
import { IsoFrame } from '../shared/compact-sheet';

/**
 * Money state, separate from attendance intent: a booking can be Going and
 * unpaid, or Refunded and still attended (a goodwill refund). Waived covers
 * comps and zero-price bookings so "everything not Paid owes money" stays a
 * safe query.
 */
export const BookingPaymentStatusField = markDefinition(
  statusField({
    displayName: 'Payment Status',
    options: [
      { value: 'Unpaid', hue: 'amber', meaning: 'Owed — not yet settled' },
      { value: 'Paid', hue: 'green', meaning: 'Settled in full', holds: true },
      {
        value: 'Waived',
        hue: 'slate',
        meaning: 'Nothing owed — comp or zero price',
        holds: true,
      },
      {
        value: 'Refunded',
        hue: 'red',
        meaning: 'Returned to the payer',
        terminal: true,
        holds: true,
      },
    ],
    transitions: {
      Unpaid: ['Paid', 'Waived'],
      Paid: ['Refunded'],
      Waived: ['Unpaid'],
      Refunded: [],
    },
  }),
);

function ticketsOf(quantity?: number | null): string {
  let q = quantity ?? 1;
  return q === 1 ? '1 ticket' : `${q} tickets`;
}

function priceOf(b?: Booking | null): string {
  let amount = b?.totalPrice?.amount;
  if (typeof amount !== 'number') return '';
  let code = b?.totalPrice?.currency?.code;
  try {
    return new Intl.NumberFormat('en-GB', {
      style: code ? 'currency' : 'decimal',
      currency: code ?? undefined,
      minimumFractionDigits: 2,
    }).format(amount);
  } catch {
    return String(amount);
  }
}

/** "Sat 12 Sep, 15:00" */
function whenOf(d?: Date | string | null): string {
  let date = d ? new Date(d) : undefined;
  if (!date || isNaN(+date)) return '';
  return date.toLocaleString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
}

// Dot tone per state: settled is ok, owed is a warning, a refund is a stop.
const TONE: Record<string, string> = {
  Paid: 'ok',
  Unpaid: 'warn',
  Refunded: 'bad',
  Going: 'info',
  Declined: 'bad',
};

function toneOf(value?: string | null): string {
  return TONE[value ?? ''] ?? '';
}

function lower(value?: string | null): string {
  return (value ?? '').toLowerCase();
}

function subtitleOf(b?: Booking | null): string {
  return [b?.holder?.name, b?.event?.cardTitle].filter(Boolean).join(' · ');
}

class BookingIsolated extends Component<typeof Booking> {
  @tracked runningAction: 'confirm' | 'check-in' | undefined;
  @tracked actionProblem: string | undefined;

  get tickets() {
    return ticketsOf(this.args.model.quantity);
  }
  get price() {
    return priceOf(this.args.model as Booking);
  }
  get subtitle() {
    return subtitleOf(this.args.model as Booking);
  }
  get kickOff() {
    return whenOf(this.args.model.event?.startsAt);
  }
  get checkedIn() {
    return whenOf(this.args.model.checkedInAt);
  }

  get realm(): string | undefined {
    return this.args.model?.[realmURL]?.href;
  }

  /** Commands need a live command context and a saved card. */
  get canAct(): boolean {
    return Boolean(
      this.args.context?.commandContext && this.args.model?.id && this.realm,
    );
  }

  get canConfirm(): boolean {
    let m = this.args.model;
    return this.canAct && !m.checkedInAt && m.rsvp !== 'Going';
  }

  get canCheckIn(): boolean {
    let m = this.args.model;
    return this.canAct && !m.checkedInAt && m.rsvp !== 'Declined';
  }

  private runCommand = async (kind: 'confirm' | 'check-in') => {
    let context = this.args.context?.commandContext;
    if (!context || !this.realm) {
      return;
    }
    this.runningAction = kind;
    this.actionProblem = undefined;
    try {
      // Literal lazy imports: both commands import Booking back, so a
      // static import here would be a module cycle.
      if (kind === 'confirm') {
        let { default: ConfirmBookingCommand } =
          // @ts-expect-error TS2834: the realm resolves extensionless module ids
          await import('./confirm-booking');
        await new ConfirmBookingCommand(context).execute({
          booking: this.args.model,
          realm: this.realm,
        } as any);
      } else {
        let { default: CheckInBookingCommand } =
          // @ts-expect-error TS2834: the realm resolves extensionless module ids
          await import('./check-in-booking');
        await new CheckInBookingCommand(context).execute({
          booking: this.args.model,
          realm: this.realm,
        } as any);
      }
    } catch (error: any) {
      this.actionProblem = error?.message ?? String(error);
    } finally {
      this.runningAction = undefined;
    }
  };

  confirm = () => {
    void this.runCommand('confirm');
  };
  checkIn = () => {
    void this.runCommand('check-in');
  };

  <template>
    <IsoFrame>
      <article class='rec'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>Bk</span>
          <div class='id'>
            <h1 class='name'>{{@model.cardTitle}}</h1>
            {{#if this.subtitle}}<p class='meta'>{{this.subtitle}}</p>{{/if}}
          </div>
          <span class='sts'>
            {{#if @model.paymentStatus}}
              <span class='dot-text'><span
                  class='dot {{toneOf @model.paymentStatus}}'
                ></span>{{lower @model.paymentStatus}}</span>
            {{/if}}
            {{#if @model.rsvp}}
              <span class='dot-text'><span
                  class='dot {{toneOf @model.rsvp}}'
                ></span>{{lower @model.rsvp}}</span>
            {{/if}}
          </span>
          {{#if this.canConfirm}}
            <Button
              @tone='neutral'
              @appearance='outlined'
              @size='s'
              @busy={{eq this.runningAction 'confirm'}}
              {{on 'click' this.confirm}}
            >Confirm</Button>
          {{/if}}
          {{#if this.canCheckIn}}
            <Button
              @tone='primary'
              @appearance='accent'
              @size='s'
              @busy={{eq this.runningAction 'check-in'}}
              {{on 'click' this.checkIn}}
            >Check in</Button>
          {{/if}}
        </header>
        {{#if this.actionProblem}}
          <Alert class='problem' @tone='danger'>{{this.actionProblem}}</Alert>
        {{/if}}
        <dl class='stats' aria-label='Key numbers'>
          <div class='stat'>
            <dt>Tickets</dt>
            <dd class='num'>{{if @model.quantity @model.quantity 1}}</dd>
            <dd class='sub'>{{if @model.rsvp @model.rsvp 'No RSVP'}}</dd>
          </div>
          <div class='stat'>
            <dt>Total</dt>
            <dd class='num'>{{if this.price this.price '—'}}</dd>
            <dd class='sub'>{{if
                @model.paymentStatus
                (lower @model.paymentStatus)
                '—'
              }}</dd>
          </div>
          <div class='stat'>
            <dt>Check-in</dt>
            <dd class='num'>{{if this.checkedIn this.checkedIn '—'}}</dd>
            <dd class='sub'>{{if
                @model.checkedInAt
                'arrived'
                'not yet arrived'
              }}</dd>
          </div>
        </dl>
        <div class='cols'>
          <div class='main'>
            <section class='sec'>
              <h2>Fixture</h2>
              <dl class='kv'>
                <dt>Event</dt><dd>{{if
                    @model.eventTitle
                    @model.eventTitle
                    '—'
                  }}</dd>
                <dt>Kick-off</dt><dd>{{if this.kickOff this.kickOff '—'}}</dd>
                <dt>Venue</dt><dd>{{if
                    @model.event.venue.name
                    @model.event.venue.name
                    '—'
                  }}</dd>
              </dl>
            </section>
            <section class='sec'>
              <h2>Payment</h2>
              <dl class='kv'>
                <dt>Total price</dt><dd>{{if this.price this.price '—'}}</dd>
                <dt>Payment status</dt><dd>{{if
                    @model.paymentStatus
                    @model.paymentStatus
                    '—'
                  }}</dd>
                <dt>RSVP</dt><dd>{{if @model.rsvp @model.rsvp '—'}}</dd>
              </dl>
            </section>
          </div>
          <aside class='side'>
            <section class='sec'>
              <h2>Linked</h2>
              <dl class='kv'>
                <dt>Holder</dt><dd>{{#if @model.holder}}<@fields.holder
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
                <dt>Fixture</dt><dd>{{#if @model.event}}<@fields.event
                      @format='atom'
                      @displayContainer={{false}}
                    />{{else}}—{{/if}}</dd>
              </dl>
            </section>
            <section class='sec'>
              <h2>Details</h2>
              <dl class='kv'>
                <dt>Quantity</dt><dd>{{this.tickets}}</dd>
                <dt>Total</dt><dd>{{if this.price this.price '—'}}</dd>
                <dt>Payment</dt><dd>{{if
                    @model.paymentStatus
                    @model.paymentStatus
                    '—'
                  }}</dd>
                <dt>RSVP</dt><dd>{{if @model.rsvp @model.rsvp '—'}}</dd>
                <dt>Kick-off</dt><dd>{{if this.kickOff this.kickOff '—'}}</dd>
                <dt>Checked in</dt><dd>{{if
                    this.checkedIn
                    this.checkedIn
                    'Not yet'
                  }}</dd>
                <dt>Holder</dt><dd>{{if
                    @model.holderName
                    @model.holderName
                    '—'
                  }}</dd>
                <dt>Fixture</dt><dd>{{if
                    @model.eventTitle
                    @model.eventTitle
                    '—'
                  }}</dd>
              </dl>
            </section>
          </aside>
        </div>
      </article>
    </IsoFrame>
    <style scoped>
      .rec {
        container-type: inline-size;
        margin: var(--boxel-sp-sm);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background-color: var(--card);
        color: var(--card-foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
        overflow: hidden;
      }
      .head {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
      }
      .mark {
        display: inline-grid;
        place-items: center;
        flex-shrink: 0;
        width: 2rem;
        height: 2rem;
        border-radius: 0.375rem;
        background-color: var(--muted);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 700;
      }
      .id {
        flex: 1;
        min-width: 0;
      }
      .name {
        margin: 0;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .meta {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .sts {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
      .dot-text {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        font-weight: 600;
      }
      .dot {
        width: 0.4375rem;
        height: 0.4375rem;
        border-radius: 50%;
        background-color: var(--muted-foreground);
      }
      .dot.ok {
        background-color: var(--success);
      }
      .dot.warn {
        background-color: var(--warning);
      }
      .dot.bad {
        background-color: var(--destructive);
      }
      .dot.info {
        background-color: var(--primary);
      }
      .problem {
        margin: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .stats {
        margin: 0;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
        border-bottom: 1px solid var(--border);
      }
      .stat {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-6xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-right: 1px solid var(--border);
        min-width: 0;
      }
      .stat dt,
      .stat dd {
        margin: 0;
      }
      .stat dt,
      .kv dt {
        font-family: var(--font-mono);
        font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .num {
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        line-height: 1.2;
        font-variant-numeric: tabular-nums;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sub {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
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
      .kv {
        display: grid;
        grid-template-columns: 8rem minmax(0, 1fr);
        margin: 0;
        padding: 0 var(--boxel-sp-sm) var(--boxel-sp-4xs);
      }
      .kv dt,
      .kv dd {
        margin: 0;
        padding: var(--boxel-sp-4xs) 0;
        border-top: 1px solid var(--border);
        min-width: 0;
        display: flex;
        align-items: center;
        flex-wrap: wrap;
      }
    </style>
  </template>
}

/**
 * A claim on places at an Event — who is coming, how many places, where the
 * money stands, and whether they actually showed up. Four facts, four
 * fields, deliberately not collapsed: `rsvp` is intent, `paymentStatus` is
 * money, `checkedInAt` is what happened, `quantity` is how much of the
 * capacity this claim consumes.
 *
 * `checkedInAt` is an event fact written once by the Check In Booking
 * command (which is also what makes a ticket one-time-use); anything
 * derived — attendance rates, no-show lists — is computed from it, never
 * stored. Seat-level assignment (section, row, seat) is a seating-plan
 * concern for the consumer's extending card.
 */
export class Booking extends CardDef {
  static displayName = 'Booking';
  static icon = TicketIcon;

  @field reference = contains(StringField);
  @field event = linksTo(Event);
  @field holder = linksTo(Contact);
  @field quantity = contains(NumberField);
  @field rsvp = contains(RsvpStatusField);
  @field paymentStatus = contains(BookingPaymentStatusField);
  @field totalPrice = contains(AmountWithCurrency);
  @field checkedInAt = contains(DateTimeField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Booking) {
      return (
        this.reference ??
        (this.holder?.name
          ? `Booking for ${this.holder.name}`
          : `Untitled ${this.constructor.displayName}`)
      );
    },
  });

  // Queryable read surface: lists and searches see who and what without
  // resolving the links themselves.
  @field eventTitle = contains(StringField, {
    computeVia: function (this: Booking) {
      return this.event?.cardTitle;
    },
  });

  @field holderName = contains(StringField, {
    computeVia: function (this: Booking) {
      return this.holder?.name;
    },
  });

  static atom = class Atom extends Component<typeof Booking> {
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Bk</span>
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          max-width: 100%;
          min-width: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground);
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex-shrink: 0;
          width: 1.125rem;
          height: 1.125rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          font-family: var(--font-mono);
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Booking> {
    get subtitle() {
      return subtitleOf(this.args.model as Booking);
    }
    get price() {
      return priceOf(this.args.model as Booking);
    }
    get kickOff() {
      return whenOf(this.args.model.event?.startsAt);
    }
    get checkedIn() {
      return whenOf(this.args.model.checkedInAt);
    }
    get tickets() {
      return ticketsOf(this.args.model.quantity);
    }
    <template>
      <article class='emb'>
        <header class='head'>
          <span class='mark' aria-hidden='true'>Bk</span>
          <div class='id'>
            <h3 class='name'>{{@model.cardTitle}}</h3>
            {{#if this.subtitle}}<p class='meta'>{{this.subtitle}}</p>{{/if}}
          </div>
          <span class='sts'>
            {{#if @model.paymentStatus}}
              <span class='dot-text'><span
                  class='dot {{toneOf @model.paymentStatus}}'
                ></span>{{lower @model.paymentStatus}}</span>
            {{/if}}
            {{#if @model.rsvp}}
              <span class='dot-text'><span
                  class='dot {{toneOf @model.rsvp}}'
                ></span>{{lower @model.rsvp}}</span>
            {{/if}}
          </span>
        </header>
        <dl class='kv'>
          <dt>Quantity</dt><dd>{{this.tickets}}</dd>
          <dt>Total</dt><dd>{{if this.price this.price '—'}}</dd>
          <dt>Kick-off</dt><dd>{{if this.kickOff this.kickOff '—'}}</dd>
          <dt>Checked in</dt><dd>{{if
              this.checkedIn
              this.checkedIn
              'Not yet'
            }}</dd>
          {{#if @model.holder}}
            <dt>Holder</dt><dd><@fields.holder
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          {{/if}}
          {{#if @model.event}}
            <dt>Fixture</dt><dd><@fields.event
                @format='atom'
                @displayContainer={{false}}
              /></dd>
          {{/if}}
        </dl>
      </article>
      <style scoped>
        .emb {
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground);
        }
        .head {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .mark {
          display: inline-grid;
          place-items: center;
          flex-shrink: 0;
          width: 1.5rem;
          height: 1.5rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
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
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .sts {
          display: flex;
          gap: var(--boxel-sp-xs);
          flex-shrink: 0;
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          font-weight: 600;
        }
        .dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .dot.ok {
          background-color: var(--success);
        }
        .dot.warn {
          background-color: var(--warning);
        }
        .dot.bad {
          background-color: var(--destructive);
        }
        .dot.info {
          background-color: var(--primary);
        }
        .kv {
          display: grid;
          grid-template-columns: 6rem minmax(0, 1fr);
          margin: 0;
          padding: 0 var(--boxel-sp-sm) var(--boxel-sp-4xs);
          border-top: 1px solid var(--border);
        }
        .kv dt,
        .kv dd {
          margin: 0;
          padding: var(--boxel-sp-4xs) 0;
          min-width: 0;
          display: flex;
          align-items: center;
          flex-wrap: wrap;
        }
        .kv > :nth-child(n + 3) {
          border-top: 1px solid var(--border);
        }
        .kv dt {
          font-family: var(--font-mono);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Booking> {
    get fact() {
      let price = priceOf(this.args.model as Booking);
      let tickets = ticketsOf(this.args.model.quantity);
      return price ? `${tickets} · ${price}` : tickets;
    }
    <template>
      <FitTile>
        <:avatar><span class='mark' aria-hidden='true'>Bk</span></:avatar>
        <:title><span class='ref'>{{@model.cardTitle}}</span></:title>
        <:subtitle>{{if
            @model.holderName
            @model.holderName
            'Unassigned'
          }}</:subtitle>
        <:status>
          {{#if @model.paymentStatus}}
            <span class='dot-text'><span
                class='dot {{toneOf @model.paymentStatus}}'
              ></span>{{lower @model.paymentStatus}}</span>
          {{/if}}
          {{#if @model.rsvp}}
            <span class='dot-text'><span
                class='dot {{toneOf @model.rsvp}}'
              ></span>{{lower @model.rsvp}}</span>
          {{/if}}
        </:status>
        <:fact>{{this.fact}}</:fact>
        <:relations>{{#if @model.event}}<@fields.event
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
      <style scoped>
        .mark {
          display: inline-grid;
          place-items: center;
          width: 1.5rem;
          height: 1.5rem;
          border-radius: 0.25rem;
          background-color: var(--muted);
          font-size: 0.5625rem; /* ladder 9px label: no Boxel token below 11px */
          font-weight: 700;
        }
        .ref {
          font-family: var(--font-mono);
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          white-space: nowrap;
        }
        .dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .dot.ok {
          background-color: var(--success);
        }
        .dot.warn {
          background-color: var(--warning);
        }
        .dot.bad {
          background-color: var(--destructive);
        }
        .dot.info {
          background-color: var(--primary);
        }
      </style>
    </template>
  };

  static isolated = BookingIsolated;
}
