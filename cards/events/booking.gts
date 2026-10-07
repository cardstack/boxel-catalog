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
import { Button } from '@cardstack/boxel-ui/components';
import TicketIcon from '@cardstack/boxel-icons/ticket';
import { Alert } from '@cardstack/pretui/components/alert';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Token } from '@cardstack/pretui/components/token';
import { ALERT_STYLE } from '@cardstack/catalog/components/pretui-helpers';

import { Contact } from '@cardstack/catalog/cards/crm/contact';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { Event } from './event';
import RsvpStatusField from './rsvp-status-field';
import { statusField } from '@cardstack/catalog/fields/status/status';

/**
 * Money state, separate from attendance intent: a booking can be Going and
 * unpaid, or Refunded and still attended (a goodwill refund). Waived covers
 * comps and zero-price bookings so "everything not Paid owes money" stays a
 * safe query.
 */
export const BookingPaymentStatusField = statusField({
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
});

function placesOf(quantity?: number | null): string {
  let q = quantity ?? 1;
  return q === 1 ? '1 place' : `${q} places`;
}

class BookingIsolated extends Component<typeof Booking> {
  @tracked runningAction: 'confirm' | 'check-in' | undefined;
  @tracked actionProblem: string | undefined;

  get places() {
    return placesOf(this.args.model.quantity);
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

  get hasActions(): boolean {
    return this.canConfirm || this.canCheckIn;
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
    <article class='bk-page'>
      <header class='bh'>
        <div class='bh-id'>
          <p class='doc-kind'>Booking</p>
          <h1>{{if @model.reference @model.reference 'No reference'}}</h1>
          <p class='bh-places'>{{this.places}}</p>
        </div>
        <div class='bh-standing'>
          {{#if @model.rsvp}}<@fields.rsvp @format='embedded' />{{/if}}
          {{#if @model.paymentStatus}}
            <@fields.paymentStatus @format='embedded' />
          {{/if}}
        </div>
      </header>
      {{#if @model.event}}
        <section class='panel'>
          <h2>Event</h2>
          <div class='linked'><@fields.event @format='embedded' /></div>
        </section>
      {{/if}}
      {{#if @model.holder}}
        <section class='panel'>
          <h2>Holder</h2>
          <div class='linked'><@fields.holder @format='embedded' /></div>
        </section>
      {{/if}}
      <section class='panel'>
        <h2>Attendance</h2>
        {{#if @model.checkedInAt}}
          <p class='fact'>Checked in <@fields.checkedInAt /></p>
        {{else if this.hasActions}}
          <EmptyState class='not-in' @title='Not checked in' @texture={{false}}>
            <:action>
              <div class='actions'>
                {{#if this.canConfirm}}
                  <Button
                    @kind='secondary-light'
                    @size='small'
                    @loading={{eq this.runningAction 'confirm'}}
                    {{on 'click' this.confirm}}
                  >Confirm</Button>
                {{/if}}
                {{#if this.canCheckIn}}
                  <Button
                    @kind='primary'
                    @size='small'
                    @loading={{eq this.runningAction 'check-in'}}
                    {{on 'click' this.checkIn}}
                  >Check in</Button>
                {{/if}}
              </div>
            </:action>
          </EmptyState>
        {{else}}
          <EmptyState
            class='not-in'
            @title='Not checked in'
            @texture={{false}}
          />
        {{/if}}
        {{#if this.actionProblem}}
          <Alert class='problem' @tone='danger' style={{ALERT_STYLE.danger}}>
            {{this.actionProblem}}
          </Alert>
        {{/if}}
      </section>
      {{#if @model.totalPrice.amount}}
        <section class='panel'>
          <h2>Price</h2>
          <Money
            class='price'
            @amount={{@model.totalPrice.amount}}
            @code={{@model.totalPrice.currency.code}}
          />
        </section>
      {{/if}}
    </article>
    <style scoped>
      .bk-page {
        max-width: 40rem;
        margin: 0 auto;
        padding: 2rem 1.5rem;
        display: flex;
        flex-direction: column;
        gap: 1.25rem;
      }
      .bh {
        display: flex;
        align-items: center;
        gap: 1rem;
        border-bottom: 0.125rem solid var(--foreground);
        padding-bottom: 1.25rem;
      }
      .bh-id {
        flex: 1;
        min-width: 0;
      }
      .doc-kind {
        margin: 0 0 0.125rem;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      h1 {
        font-size: 1.5rem;
        line-height: 1.1;
        font-family: var(--font-mono);
        letter-spacing: 0.04em;
      }
      .bh-places {
        margin: 0.25rem 0 0;
        font-size: 0.875rem;
        color: var(--muted-foreground);
      }
      .bh-standing {
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        gap: 0.375rem;
        flex-shrink: 0;
      }
      .panel {
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        padding: 1rem 1.25rem;
        background-color: var(--card);
        color: var(--card-foreground);
      }
      h2 {
        margin: 0 0 0.75rem;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .linked {
        border: 1px solid var(--border);
        border-radius: 0.5rem;
      }
      .fact {
        margin: 0;
        font-size: 0.875rem;
      }
      /* Pret UI EmptyState, tuned through its own spacing and title knobs
         to a compact well that fits inside the panel. */
      .not-in {
        --space-9: 1rem;
        --space-6: 1rem;
        --text-heading: var(--boxel-font-size);
      }
      .actions {
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: 0.5rem;
      }
      .problem {
        margin-top: 0.75rem;
        --text-ui-md: 0.8125rem;
      }
      .price {
        display: block;
        font-size: 0.9375rem;
        font-weight: 600;
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
      <span class='bk-atom'>
        <TicketIcon class='bk-icon' />
        <span class='bk-ref'>{{if
            @model.reference
            @model.reference
            'No reference'
          }}</span>
      </span>
      <style scoped>
        .bk-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
          font-size: 0.8125rem;
        }
        .bk-icon {
          width: 0.875rem;
          height: 0.875rem;
          flex-shrink: 0;
          color: var(--muted-foreground);
        }
        .bk-ref {
          font-family: var(--font-mono);
          letter-spacing: 0.04em;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Booking> {
    get places() {
      return placesOf(this.args.model.quantity);
    }
    <template>
      <div class='bk'>
        <div class='bk-id'>
          <Token
            class='bk-ref'
            @value={{if @model.reference @model.reference 'No reference'}}
          />
          <span class='bk-meta'>
            {{if @model.holder.name @model.holder.name 'Unassigned'}}
            ·
            {{this.places}}
            {{#if @model.checkedInAt}}· checked in{{/if}}
          </span>
        </div>
        <span class='bk-payment'>
          {{#if @model.paymentStatus}}
            <@fields.paymentStatus @format='atom' />
          {{/if}}
        </span>
        <span class='bk-rsvp'>
          {{#if @model.rsvp}}<@fields.rsvp @format='atom' />{{/if}}
        </span>
      </div>
      <style scoped>
        .bk {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.625rem 0.875rem;
        }
        .bk-id {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }
        /* Pret UI Token, sized through its body-text knob to the row's
           title size (Token draws at the knob minus 3.5px, so the calc
           cancels it), inked from --primary-ink (8.24:1 light / 8.14:1 dark
           on its own tint) and clipped with an ellipsis like a title. */
        .bk-ref {
          --text-body: calc(0.8125rem + 3.5px);
          --pretui-primary-ink: var(--primary-ink);
          align-self: flex-start;
          max-width: 100%;
          margin-inline: 0;
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .bk-meta {
          font-size: 0.75rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        /* Constant-width trailing slots so booking rows column-align. */
        .bk-payment {
          width: 4.5rem;
          display: inline-flex;
          justify-content: flex-end;
          flex-shrink: 0;
        }
        .bk-rsvp {
          width: 5.25rem;
          display: inline-flex;
          justify-content: flex-end;
          flex-shrink: 0;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Booking> {
    get places() {
      return placesOf(this.args.model.quantity);
    }
    <template>
      <div class='fitted'>
        <Token
          class='ref'
          @value={{if @model.reference @model.reference 'No reference'}}
        />
        <span class='meta line-places'>{{this.places}}</span>
        <span class='line-rsvp'>
          {{#if @model.rsvp}}<@fields.rsvp @format='atom' />{{/if}}
        </span>
        {{#if @model.checkedInAt}}
          <span class='meta line-checkin'>Checked in
            <@fields.checkedInAt /></span>
        {{/if}}
      </div>
      <style scoped>
        .fitted {
          display: flex;
          flex-direction: column;
          justify-content: center;
          gap: 0.25rem;
          width: 100%;
          height: 100%;
          padding: 0.625rem 0.75rem;
          box-sizing: border-box;
          overflow: hidden;
        }
        /* Pret UI Token at the fitted title size; see Embedded. */
        .ref {
          --text-body: calc(0.75rem + 3.5px);
          --pretui-primary-ink: var(--primary-ink);
          align-self: flex-start;
          max-width: 100%;
          margin-inline: 0;
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .line-places,
        .line-rsvp,
        .line-checkin {
          display: none;
        }
        /* Badge degradation: strip height keeps only the first line. */
        @container fitted-card (max-height: 50px) {
          .fitted {
            padding: 0.25rem 0.5rem;
            gap: 0.125rem;
          }
        }
        @container fitted-card (min-height: 65px) {
          .line-rsvp {
            display: inline-flex;
          }
        }
        @container fitted-card (min-height: 170px) {
          .line-places {
            display: block;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .line-checkin {
            display: block;
          }
        }
      </style>
    </template>
  };

  static isolated = BookingIsolated;
}
