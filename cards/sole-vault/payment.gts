import {
  CardDef,
  field,
  contains,
  linksTo,
  StringField,
  Component,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import {
  statusField,
  canTransition,
  nextStatuses,
} from '../../fields/status/status';
import { Order } from './order';
import CreditCardIcon from '@cardstack/boxel-icons/credit-card';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import ClockIcon from '@cardstack/boxel-icons/clock';
import { tracked } from '@glimmer/tracking';
import { FittedCard } from '@cardstack/boxel-ui/components';
import { Field } from '@cardstack/pretui/components/field';
import { Accordion } from '@cardstack/pretui/components/accordion';
import { eq } from '@cardstack/boxel-ui/helpers';
import { formatMoney } from '../collectibles/money-format';

// Payment — the RECORD of one money movement against one Order.
//
// READ THIS BEFORE EXTENDING IT: this card does not move money and cannot. A
// realm has no processor, no card vault and no balance. Everything here is a
// record of what an external processor reported, and the commands that write it
// are SIMULATIONS. That is a deliberate boundary, not an unfinished feature —
// escrow belongs to a payment provider, which is
// server-side infrastructure this layer has no business impersonating.
//
// WHY IT IS SEPARATE FROM Order. An order has one lifecycle; its money can have
// several movements — an authorization, a capture, a partial refund, a chargeback
// reversal. Folding them into Order would force one status to describe two
// different things, and the moment a refund is partial the model breaks. One
// Order links to many Payment records; each is immutable history.
//
// THE AMOUNT IS SIGNED BY DIRECTION, NOT BY A NEGATIVE NUMBER. `direction`
// says charge or refund and `amount` is always positive. A negative money amount
// renders as "-$175.00" in some formatters and "($175.00)" in others, and every
// aggregate then has to remember which convention it is summing.

export type PaymentState =
  | 'pending'
  | 'authorized'
  | 'captured'
  | 'failed'
  | 'refunded';

export type PaymentDirection = 'charge' | 'refund';

export const PaymentStateField = statusField({
  displayName: 'Payment State',
  icon: CreditCardIcon,
  options: [
    {
      value: 'pending',
      label: 'Pending',
      hue: 'slate',
      meaning: 'Submitted to the processor, no answer yet.',
    },
    {
      value: 'authorized',
      label: 'Authorized',
      hue: 'blue',
      holds: true,
      meaning:
        'The processor is holding the funds. This is the escrow state — money reserved, not yet taken.',
    },
    {
      value: 'captured',
      label: 'Captured',
      hue: 'green',
      terminal: true,
      holds: true,
      meaning: 'Funds actually taken and settled to the platform.',
    },
    {
      value: 'failed',
      label: 'Failed',
      hue: 'red',
      terminal: true,
      meaning: 'Declined or errored. No money moved.',
    },
    {
      value: 'refunded',
      label: 'Refunded',
      hue: 'orange',
      terminal: true,
      holds: true,
      meaning: 'Returned to the payer. Recorded, never edited away.',
    },
  ],
  // A processor's own state machine, mirrored rather than invented:
  //   * `pending` can only resolve — it never goes back to itself.
  //   * An authorization can be captured, can expire into failure, or can be
  //     released as a refund before capture.
  //   * `captured → refunded` is the only edge out of a settled payment, and it
  //     is one-way. A refund is never "un-refunded"; that is a new charge.
  //   * `failed` is terminal because a retry is a NEW payment record. Reusing
  //     this one would erase the evidence that the first attempt was declined.
  transitions: {
    pending: ['authorized', 'captured', 'failed'],
    authorized: ['captured', 'failed', 'refunded'],
    captured: ['refunded'],
    failed: [],
    refunded: [],
  },
});

export function canPaymentTransition(from?: string | null, to?: string | null) {
  return canTransition(PaymentStateField, from, to);
}

export function nextPaymentStates(from?: string | null) {
  return nextStatuses(PaymentStateField, from);
}

class PaymentEdit extends Component<typeof Payment> {
  @tracked refsOpen = true;
  @tracked datesOpen = false;

  toggleRefs = () => (this.refsOpen = !this.refsOpen);
  toggleDates = () => (this.datesOpen = !this.datesOpen);

  <template>
    <div class='pay-edit'>
      <header class='pe-head'>
        <Field @label='Order'>
          <@fields.order />
        </Field>

        <div class='pe-identity'>
          <Field @label='Amount'>
            <@fields.amount />
            <p class='pe-help'>Always positive. Direction decides the sign — a
              negative amount here renders inconsistently across formatters.</p>
          </Field>
          <Field @label='Direction'>
            <@fields.direction @format='atom' />
            <p class='pe-help'>Set by the command that records the payment:
              Process Payment writes a charge, Refund Order a refund.</p>
          </Field>
          <Field @label='State'>
            <@fields.paymentState @format='atom' />
            <p class='pe-help'>Set by the payment commands, from what the
              processor reported.</p>
          </Field>
        </div>
      </header>

      <Accordion class='pe-sections' @displayContainer={{false}} as |A|>
        <A.Item
          @id='refs'
          @isOpen={{this.refsOpen}}
          @onClick={{this.toggleRefs}}
        >
          <:title>Processor &amp; reason</:title>
          <:content>
            <div class='pe-body pe-grid-2'>
              <Field @label='Processor'>
                <@fields.processor />
                <p class='pe-help'>Write
                  <code>simulated</code>
                  unless a real processor produced this record. Naming the
                  simulator in the data is what stops a demo being read as a
                  settlement.</p>
              </Field>
              <Field @label='Processor reference'>
                <@fields.processorReference />
                <p class='pe-help'>The only handle support has when reconciling
                  against the processor’s dashboard.</p>
              </Field>
              <Field @label='Reason'>
                <@fields.reason />
                <p class='pe-help'>Why a refund happened. Leave empty on a
                  charge.</p>
              </Field>
            </div>
          </:content>
        </A.Item>

        <A.Item
          @id='dates'
          @isOpen={{this.datesOpen}}
          @onClick={{this.toggleDates}}
        >
          <:title>Dates</:title>
          <:content>
            <div class='pe-body pe-grid-2'>
              <Field @label='Initiated'>
                <@fields.initiatedAt />
              </Field>
              <Field @label='Settled'>
                <@fields.settledAt />
                <p class='pe-help'>Empty while the payment is only authorized —
                  settlement is when money actually moved.</p>
              </Field>
            </div>
          </:content>
        </A.Item>
      </Accordion>
    </div>

    <style scoped>
      /* Rule 1: edit has no host container — declare our own, named. Same
         literal committed palette as isolated, not theme fallbacks. */
      .pay-edit {
        container-type: inline-size;
        container-name: pay-edit;

        --_raised: color-mix(in oklch, var(--card) 80%, var(--foreground) 20%);
        --_hairline: color-mix(in oklch, var(--border) 55%, transparent);

        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        height: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        box-sizing: border-box;

        scrollbar-color: var(--primary) var(--card);
      }
      .pay-edit ::selection {
        background: var(--primary);
        color: var(--background);
      }
      .pay-edit *:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
      }
      .pe-head {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
        border-bottom: 1px solid var(--_hairline);
        padding-bottom: var(--boxel-sp);
      }
      .pe-identity {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: var(--boxel-sp-sm);
      }
      .pe-body {
        padding: var(--boxel-sp-sm) var(--boxel-sp-xs);
      }
      .pe-grid-2 {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--boxel-sp-sm);
      }
      .pe-help {
        margin: var(--boxel-sp-4xs) 0 0;
        font-size: var(--boxel-font-size-xs);
        line-height: 1.45;
        color: var(--muted-foreground);
      }
      /* An accepted literal shown inline reads as a value to type, not prose. */
      .pe-help code {
        font-family: var(--font-mono);
        background: var(--_raised);
        padding: 0.05em 0.3em;
        border-radius: 3px;
        color: var(--foreground);
      }

      @container pay-edit (width < 40rem) {
        .pe-identity,
        .pe-grid-2 {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

export class Payment extends CardDef {
  static displayName = 'Payment';
  static icon = CreditCardIcon;

  @field order = linksTo(() => Order, { searchable: true });

  @field amount = contains(AmountWithCurrency);
  @field paymentState = contains(PaymentStateField);

  // 'charge' | 'refund'. Plain string with a documented pair rather than an
  // enum field, because the two values never grow — a chargeback is a refund
  // with a different reason, not a third direction.
  @field direction = contains(StringField);

  // The processor's reference. The only
  // handle support has when reconciling against the processor's dashboard, so
  // it is treated as an identifier: never truncated in any format.
  @field processorReference = contains(StringField);

  // 'Stripe', 'simulated'. Naming the simulator explicitly in the data is what
  // stops a demo record being mistaken for a real settlement later.
  @field processor = contains(StringField);

  @field initiatedAt = contains(DateField);
  @field settledAt = contains(DateField);

  // Why a refund happened — 'authentication failed', 'buyer dispute'. Empty on
  // a charge.
  @field reason = contains(StringField);

  // --- denormalized for prerendered fitted (cannot resolve linksTo) ---
  @field orderReference = contains(StringField, {
    computeVia: function (this: Payment) {
      return this.order?.reference ?? '';
    },
  });

  @field productTitle = contains(StringField, {
    computeVia: function (this: Payment) {
      return this.order?.productTitle ?? this.cardInfo?.name ?? '';
    },
  });

  // Signed display string, derived once here so the atom, the row and any future
  // ledger view cannot disagree about how a refund is written.
  @field signedAmount = contains(StringField, {
    computeVia: function (this: Payment) {
      let money = formatMoney(this.amount);
      if (!money) {
        return '';
      }
      return this.direction === 'refund' ? `−${money}` : money;
    },
  });

  // ISOLATED — the payment's landing page. Instrument direction: this is a
  // ledger entry someone opens while reconciling, so the layout is the plaque
  // figure plus reference data, with no queries — a payment points AT its
  // order; nothing points at a payment.
  //
  // Domain question: "did money move, how much, which way, and can I find it
  // on the processor's dashboard?" The first three are the hero; the fourth is
  // the reconciliation section, where the processor reference renders mono and
  // whole — it is the only handle support has.
  static isolated = class Isolated extends Component<typeof Payment> {
    <template>
      <article class='card'>
        <header class='hero'>
          <div class='hero-copy'>
            <h1 class='hero-title'>{{if
                @model.productTitle
                @model.productTitle
                'Unlinked order'
              }}</h1>
            <p class='hero-meta'>
              {{#if @model.orderReference}}
                <span class='meta-item'>order
                  <strong class='mono'>{{@model.orderReference}}</strong></span>
              {{/if}}
              {{#if @model.reason}}
                <span class='meta-item'>{{@model.reason}}</span>
              {{/if}}
            </p>
          </div>

          {{! THE PLAQUE — the signed amount is the dominant element; the
              direction/processor caption sits BELOW the figure, never above it
              as a kicker. A refund's minus sign is carried by `signedAmount`
              itself, derived once for every format. }}
          <div
            class='plaque {{if (eq @model.direction "refund") "plaque--out"}}'
          >
            <p
              class='plaque-amt
                {{if (eq @model.direction "refund") "plaque-amt--out"}}'
            >{{if @model.signedAmount @model.signedAmount '—'}}</p>
            <p class='plaque-caption'>
              {{if (eq @model.direction 'refund') 'Refund' 'Charge'}}
              {{#if @model.processor}}
                <span class='plaque-sep'>·</span>
                {{@model.processor}}
              {{/if}}
            </p>
            {{#if @model.paymentState}}
              <div class='plaque-state'>
                <@fields.paymentState @format='embedded' />
              </div>
            {{/if}}
          </div>
        </header>

        <div class='cols'>
          {{! Shape 1: a printed ledger strip — leader-dot rows, no icon
              header. }}
          <section class='ledger'>
            <h2 class='sec-label'>Ledger</h2>
            <div class='ledger-row'>
              <span class='ledger-key'>Processor</span>
              <span class='ledger-leader'></span>
              <span class='ledger-val'>{{if
                  @model.processor
                  @model.processor
                  '—'
                }}</span>
            </div>
            <div class='ledger-row'>
              <span class='ledger-key'>Reference</span>
              <span class='ledger-leader'></span>
              {{! The only handle support has against the processor's
                  dashboard: mono, tabular, never truncated. }}
              <span class='ledger-val mono'>{{if
                  @model.processorReference
                  @model.processorReference
                  '—'
                }}</span>
            </div>
            <div class='ledger-row'>
              <span class='ledger-key'>Direction</span>
              <span class='ledger-leader'></span>
              <span class='ledger-val'>{{if
                  (eq @model.direction 'refund')
                  'Refund'
                  'Charge'
                }}</span>
            </div>
            <p class='ledger-note'>A record, not a movement — this realm has no
              processor. “simulated” here is what separates a demo from a
              settlement.</p>
          </section>

          {{! Shape 2: a vertical rail — the two moments, connected. }}
          <section class='timing'>
            <h2 class='sec-label'><ClockIcon
                class='sec-icon'
                width='16'
                height='16'
                aria-hidden='true'
              />Timing</h2>
            <ol class='rail'>
              <li class='rail-node'>
                <span class='rail-dot'></span>
                <span class='rail-label'>Initiated</span>
                <span class='rail-val'>{{#if
                    @model.initiatedAt
                  }}<@fields.initiatedAt
                      @format='atom'
                    />{{else}}—{{/if}}</span>
              </li>
              <li class='rail-node'>
                <span class='rail-dot'></span>
                <span class='rail-label'>Settled</span>
                <span class='rail-val'>{{#if
                    @model.settledAt
                  }}<@fields.settledAt @format='atom' />{{else}}—{{/if}}</span>
              </li>
            </ol>
            <p class='rail-note'>Empty settled while only authorized —
              settlement is when money actually moved.</p>
          </section>
        </div>

        {{! Shape 3: the receipt stub — a linked card, torn from the top. }}
        <section class='stub'>
          <h2 class='sec-label'><ReceiptIcon
              class='sec-icon'
              width='16'
              height='16'
              aria-hidden='true'
            />Order</h2>
          {{#if @model.order}}
            <div class='stub-body'>
              <@fields.order @format='embedded' />
            </div>
          {{else}}
            <p class='empty'>
              <ReceiptIcon width='18' height='18' aria-hidden='true' />No order
              linked — a payment with nothing to settle.
            </p>
          {{/if}}
        </section>
      </article>

      <style scoped>
        /* Rule 1: isolated gets NO host container — declare our own, named.
           Literal committed palette, matching the app shell — nothing here
           is meant to be swappable by a theme. */
        .card {
          container-type: inline-size;
          container-name: card;
          width: 100%;
          height: 100%;
          overflow-y: auto;

          --_raised: color-mix(
            in oklch,
            var(--card) 80%,
            var(--foreground) 20%
          );
          --_hairline: color-mix(in oklch, var(--border) 55%, transparent);

          background: var(--background);
          background-image: radial-gradient(
            ellipse 68.75rem 37.5rem at 85% -10%,
            var(--card) 0%,
            transparent 60%
          );
          color: var(--foreground);
          font-family: var(--font-sans);
          padding: var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-lg);
          box-sizing: border-box;

          scrollbar-color: var(--primary) var(--card);
        }
        .card::-webkit-scrollbar {
          width: 0.625rem;
          height: 0.625rem;
        }
        .card::-webkit-scrollbar-track {
          background: var(--card);
        }
        .card::-webkit-scrollbar-thumb {
          background: var(--primary);
          border-radius: 999px;
          border: 2px solid var(--card);
        }
        .card ::selection {
          background: var(--primary);
          color: var(--primary-foreground);
        }
        .card *:focus-visible {
          outline: 2px solid var(--primary);
          outline-offset: 2px;
        }

        /* ---------- hero ---------- */
        .hero {
          display: flex;
          flex-wrap: wrap;
          align-items: flex-end;
          justify-content: space-between;
          gap: var(--boxel-sp-lg);
        }
        .hero-copy {
          min-width: 0;
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
        }
        .hero-title {
          margin: 0;
          font-family: var(--font-serif);
          font-size: 1.75rem;
          line-height: 1.15;
          font-weight: 700;
          letter-spacing: -0.01em;
        }
        .hero-meta {
          margin: 0;
          display: flex;
          flex-wrap: wrap;
          gap: var(--boxel-sp-xs) var(--boxel-sp);
          font-size: 0.8125rem;
          color: var(--muted-foreground);
        }
        .meta-item strong {
          color: var(--foreground);
          font-weight: 600;
        }
        .mono {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }

        /* THE PLAQUE — same filled-panel device as the rest of the family
           (radius/shadow match CollectionItem's --panel-radius convention):
           gold for an inflow, rose for an outflow — the fill is data-driven,
           never a bare-text figure like the family's other cards. Caption
           sits BELOW the figure, never above it as a kicker. */
        /* Light translation of the plaque signature: white ground, the
           top-rule carrying the money's DIRECTION — gold for a charge, the
           destructive rose for money leaving (a refund). The old filled
           gradient slabs were dark-era surfaces. */
        .plaque {
          display: flex;
          flex-direction: column;
          align-items: flex-end;
          gap: var(--boxel-sp-4xs);
          text-align: right;
          margin-top: auto;
          background: var(--card);
          border: 1px solid var(--_hairline);
          border-top: 3px solid var(--primary);
          border-radius: 6px;
          padding: 1.1rem 1.4rem;
          box-shadow: var(--shadow-xs);
        }
        .plaque--out {
          border-top-color: var(--destructive);
        }
        .plaque-amt {
          margin: 0;
          font-family: var(--font-mono);
          color: var(--foreground);
          font-size: 2.75rem;
          line-height: 1.05;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          letter-spacing: -0.01em;
          white-space: nowrap;
        }
        .plaque-amt--out {
          color: var(--destructive-ink);
        }
        .plaque-caption {
          margin: 0;
          font-size: 0.75rem;
          text-transform: uppercase;
          letter-spacing: 0.08em;
          color: var(--primary-ink);
        }
        .plaque-sep {
          opacity: 0.6;
          margin: 0 0.3em;
        }
        .plaque-state {
          margin-top: var(--boxel-sp-2xs);
        }

        /* ---------- section label, shared but not a repeated panel ---------- */
        .sec-label {
          margin: 0 0 var(--boxel-sp-sm);
          display: flex;
          align-items: center;
          gap: 0.5em;
          font-size: 0.6875rem;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.09em;
          color: var(--muted-foreground);
        }
        .sec-icon {
          flex: none;
          color: var(--primary-ink);
        }

        .cols {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(17.5rem, 1fr));
          gap: var(--boxel-sp-lg);
        }

        /* Shape 1: LEDGER — a printed strip, leader-dot rows. */
        .ledger {
          background: var(--card);
          padding: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          border-radius: 8px;
          border: 1px solid var(--_hairline);
          box-shadow: var(--shadow-md);
          min-width: 0;
        }
        .ledger-row {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          font-size: 0.875rem;
          padding: 0.3em 0;
        }
        .ledger-key {
          font-size: 0.6875rem;
          text-transform: uppercase;
          letter-spacing: 0.07em;
          color: var(--muted-foreground);
          flex: none;
        }
        .ledger-leader {
          flex: 1 1 auto;
          border-bottom: 1px dotted var(--_hairline);
          min-width: 1rem;
          transform: translateY(-0.3em);
        }
        .ledger-val {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          text-align: right;
        }
        .ledger-note {
          margin: var(--boxel-sp-sm) 0 0;
          font-size: 0.75rem;
          line-height: 1.45;
          color: var(--muted-foreground);
        }

        /* Shape 2: TIMING — a vertical rail with two connected nodes. */
        .timing {
          background: var(--card);
          padding: var(--boxel-sp) var(--boxel-sp-lg) var(--boxel-sp-lg);
          border-radius: 8px;
          border: 1px solid var(--_hairline);
          box-shadow: var(--shadow-md);
          min-width: 0;
        }
        .rail {
          list-style: none;
          margin: 0;
          padding: 0 0 0 0.4rem;
          position: relative;
        }
        .rail::before {
          content: '';
          position: absolute;
          left: 0.4rem;
          top: 0.5rem;
          bottom: 0.5rem;
          width: 0.0625rem;
          background: var(--_hairline);
        }
        .rail-node {
          position: relative;
          display: grid;
          grid-template-columns: auto 1fr auto;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          padding: 0.4em 0 0.4em 1.1rem;
          font-size: 0.875rem;
        }
        .rail-dot {
          position: absolute;
          left: -0.05rem;
          top: 0.75em;
          width: 0.55rem;
          height: 0.55rem;
          border-radius: 999px;
          background: var(--primary);
          box-shadow: 0 0 0 0.1875rem var(--card);
        }
        .rail-label {
          font-size: 0.6875rem;
          text-transform: uppercase;
          letter-spacing: 0.07em;
          color: var(--muted-foreground);
        }
        .rail-val {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          text-align: right;
        }
        .rail-note {
          margin: var(--boxel-sp-sm) 0 0;
          font-size: 0.75rem;
          line-height: 1.45;
          color: var(--muted-foreground);
        }

        /* Shape 3: STUB — a receipt torn from the page, holding the linked
           Order. The dashed top edge with circular "punches" is the family's
           one signature flourish on this card. */
        .stub {
          position: relative;
          background: var(--card);
          padding: var(--boxel-sp-lg);
          padding-top: calc(var(--boxel-sp-lg) + 0.5rem);
          border-radius: 8px;
          border: 1px solid var(--_hairline);
          box-shadow: var(--shadow-md);
        }
        .stub::before {
          content: '';
          position: absolute;
          top: 0;
          left: var(--boxel-sp-lg);
          right: var(--boxel-sp-lg);
          height: 0;
          border-top: 2px dashed var(--_hairline);
        }
        .stub-body {
          border-radius: 6px;
          transition:
            transform 180ms cubic-bezier(0.16, 1, 0.3, 1),
            box-shadow 180ms cubic-bezier(0.16, 1, 0.3, 1);
        }
        .stub-body:hover,
        .stub-body:focus-within {
          transform: translateY(-0.1875rem);
          box-shadow: var(--shadow-lg);
        }

        .empty {
          margin: 0;
          display: flex;
          align-items: center;
          gap: 0.5em;
          font-size: 0.8125rem;
          line-height: 1.45;
          color: var(--muted-foreground);
        }

        @media (prefers-reduced-motion: reduce) {
          .stub-body {
            transition: none;
          }
          .stub-body:hover,
          .stub-body:focus-within {
            transform: none;
          }
        }

        @container card (width < 43.75rem) {
          .hero {
            flex-direction: column;
            align-items: flex-start;
          }
          .plaque {
            align-items: flex-start;
            text-align: left;
          }
          .cols {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };

  // EDIT — nine editable fields, so grouped rather than a flat list.
  //
  // The identity row carries the two facts that decide what this record MEANS
  // (direction and state); everything else is reference data and dates.
  //
  // `direction` and `processor` both get helper text because both are free
  // strings whose accepted values are not discoverable from the input, and
  // getting either wrong is the difference between a demo record and something
  // a reader believes settled real money.
  static edit = PaymentEdit;

  // FITTED — FittedCard, unlike Order's hand-rolled tile. A payment IS a
  // standard composition (glyph + eyebrow + title + badge + footer), and the
  // family already runs seven of these, so forking an eighth idiom would cost
  // consistency for nothing.
  //
  // SLOT DISCIPLINE — four distinct facts, four slots:
  //   direction (eyebrow) · signedAmount (title, the anchor) · state (badge) ·
  //   processorReference (footer)
  // `<:subtitle>` and `<:meta>` are NOT rendered: the values left over are the
  // order reference and the product title, both of which belong to the Order
  // tile, not here — a payment row that repeats them reads as a duplicate order.
  static fitted = class Fitted extends Component<typeof Payment> {
    <template>
      <FittedCard class='pay-fit' @titleTag='h3'>
        {{! Rule 2 anchor: no image field on a payment, so this is the tier-2
            icon — the card's OWN static icon, the same one its atom uses. }}
        <:placeholder>
          <CreditCardIcon width='18' height='18' aria-hidden='true' />
        </:placeholder>

        {{! The eyebrow carries the PROCESSOR, not the direction.
            Direction was the obvious choice and it is wrong twice over: the
            minus sign in `signedAmount` already states it, and on a settled
            refund an eyebrow reading "REFUND" sits directly above a badge
            reading "Refunded" — two slots saying one thing, which reads as a
            single field wrapped onto two lines.
            The processor is the fact nothing else on the tile carries, and it
            is the one worth surfacing: 'simulated' is how a reader tells a demo
            record from a real settlement. }}
        <:eyebrow>{{@model.processor}}</:eyebrow>

        {{! The amount is the title BECAUSE it is the main field of a payment —
            which keeps FittedCard's own "title is loudest" behaviour pointing at
            the right value instead of fighting it. }}
        <:title>{{if @model.signedAmount @model.signedAmount '—'}}</:title>

        <:badgeRight>
          {{#if @model.paymentState}}
            <@fields.paymentState @format='atom' />
          {{/if}}
        </:badgeRight>

        <:footer>
          {{! A processor reference is reconciled by hand against a dashboard:
              mono, nowrap, and hidden WHOLE at the narrow quanta rather than
              truncated to an unusable stub. }}
          {{#if @model.processorReference}}
            <span class='pay-ref'>{{@model.processorReference}}</span>
          {{/if}}
        </:footer>
      </FittedCard>

      <style scoped>
        /* No container-type / container-name — FittedCard queries the HOST's
           `fitted-card` container. Literal committed palette, same as
           isolated/edit. */
        .pay-fit {
          --_raised: color-mix(
            in oklch,
            var(--card) 80%,
            var(--foreground) 20%
          );

          background: var(--card);
          color: var(--foreground);
          font-family: var(--font-sans);
          /* Family plaque — inset gold edge, never a border. */
          box-shadow: inset 0.125rem 0 0 0 var(--primary);

          --fc-image-width: 34cqh;
          --fc-image-min-width: 2.5rem;
          --fc-image-max-width: 5rem;
          --fc-image-background: var(--_raised);
          --fc-image-fade-color: var(--card);

          --fc-content-padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          --fc-header-gap: 0.15em;
          --fc-content-gap: var(--boxel-sp-2xs);

          /* line-height >= 1.15 on every role so a descender is never sheared
             even when the clamp math "fits". */
          --fc-eyebrow-font-size: max(0.5625rem, 0.62em);
          --fc-eyebrow-line-height: 1.25;
          --fc-title-font-size: max(0.9375rem, 1.3em);
          --fc-title-line-height: 1.2;
          --fc-title-line-clamp: 1;
          --fc-footer-font-size: max(0.6875rem, 0.72em);
          --fc-footer-gap: var(--boxel-sp-xs);
          --fc-footer-justify: flex-start;
          --fc-footer-flex-wrap: nowrap;
          --fc-badge-offset: var(--boxel-sp-2xs);
        }

        .pay-ref {
          font-family: var(--font-mono);
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
          white-space: nowrap;
        }

        /* ---- quanta: visibility only, never a shrink-into-a-clip ---- */
        @container fitted-card (height <= 3.125rem) {
          .pay-fit {
            --fc-footer-display: none;
            --fc-badge-right-display: none;
            --fc-content-padding: var(--boxel-sp-4xs) var(--boxel-sp-2xs);
          }
        }

        /* The reference goes whole rather than becoming a stub. */
        @container fitted-card (width <= 13.75rem) and (height <= 5rem) {
          .pay-fit .pay-ref {
            display: none;
          }
        }

        @container fitted-card (width <= 9.375rem) {
          .pay-fit {
            --fc-image-max-width: 100%;
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Payment> {
    <template>
      <span class='pay-atom'>
        <span
          class='pay-amt {{if (eq @model.direction "refund") "pay-amt--out"}}'
        >{{if @model.signedAmount @model.signedAmount '—'}}</span>
        {{#if @model.paymentState}}
          <@fields.paymentState @format='atom' />
        {{/if}}
      </span>
      <style scoped>
        .pay-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-family: var(--font-sans);
        }
        .pay-amt {
          font-family:
            ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
          color: var(--primary-ink);
        }
        /* A refund reads as an outflow — a distinct rose hue from the family's
           gold inflow tone. */
        .pay-amt--out {
          color: var(--destructive-ink);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Payment> {
    <template>
      <div class='pay-row'>
        <span class='pay-ref'>{{if
            @model.processorReference
            @model.processorReference
            '—'
          }}</span>
        <span class='pay-main'>
          <span class='pay-dir'>{{if
              (eq @model.direction 'refund')
              'Refund'
              'Charge'
            }}</span>
          {{#if @model.reason}}
            <span class='pay-reason'>· {{@model.reason}}</span>
          {{/if}}
        </span>
        {{#if @model.paymentState}}
          <@fields.paymentState @format='atom' />
        {{/if}}
        <span
          class='pay-amt {{if (eq @model.direction "refund") "pay-amt--out"}}'
        >{{if @model.signedAmount @model.signedAmount '—'}}</span>
      </div>
      <style scoped>
        /* Own inset — the host adds none. Literal committed palette,
           self-contained since this template has no root to inherit tokens
           from. */
        .pay-row {
          display: grid;
          grid-template-columns: 9rem minmax(0, 1fr) auto auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          background: var(--card);
          color: var(--foreground);
          font-family: var(--font-sans);
          font-size: var(--boxel-font-size-sm);
        }
        /* A processor reference is reconciled against a dashboard by hand. */
        .pay-ref {
          font-family:
            ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
          font-size: var(--boxel-font-size-xs);
          white-space: nowrap;
        }
        .pay-dir {
          font-weight: 600;
        }
        .pay-reason {
          color: var(--muted-foreground);
        }
        .pay-amt {
          font-family:
            ui-monospace, 'SFMono-Regular', Menlo, Consolas, monospace;
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
          color: var(--primary-ink);
        }
        .pay-amt--out {
          color: var(--destructive-ink);
        }
        @container (width < 32.5rem) {
          .pay-row {
            grid-template-columns: minmax(0, 1fr) auto;
          }
          .pay-ref {
            display: none;
          }
        }
      </style>
    </template>
  };
}

export default Payment;
