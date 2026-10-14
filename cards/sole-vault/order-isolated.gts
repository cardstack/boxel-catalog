import { Component, realmURL, getComponent } from '@cardstack/base/card-api';
import { identifyCard } from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/pretui/components/button';
import { Spinner } from '@cardstack/pretui/components/spinner';
import { eq } from '@cardstack/boxel-ui/helpers';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import CalendarIcon from '@cardstack/boxel-icons/calendar';
import CoinsIcon from '@cardstack/boxel-icons/coins';
import CreditCardIcon from '@cardstack/boxel-icons/credit-card';
import PackageIcon from '@cardstack/boxel-icons/package';
import LockIcon from '@cardstack/boxel-icons/lock';
import AlertTriangleIcon from '@cardstack/boxel-icons/alert-triangle';
import { formatMoney } from '../collectibles/money-format';
import { Shipment } from './shipment';
import { Payment } from './payment';
import { canOrderTransition, nextOrderStatuses } from './order-status';
import type { Order } from './order';

export class OrderIsolated extends Component<typeof Order> {
  get realms() {
    let realmUrl = this.args.model?.[realmURL];
    return realmUrl ? [realmUrl.href] : [];
  }

  // REVERSE QUERIES. `{ eq: { 'order.id': <this card's id> } }` is the shape,
  // and `on: ref` is not optional — without the anchor the field path resolves
  // against CardDef and the request fails with HTTP 500.
  //
  // IMPORT CYCLE, ON PURPOSE: shipment.gts and payment.gts both import THIS
  // module, so importing them back here is a cycle. ES modules tolerate it
  // because `identifyCard(Shipment)` is only ever read inside this getter —
  // never at module-evaluation time. Do not hoist these to a top-level const
  // "for clarity"; that is what breaks it.
  private shipmentsQuery = this.args.context?.getCards(
    this,
    () => {
      let ref = identifyCard(Shipment);
      let id = this.args.model?.id;
      return ref && id
        ? { filter: { on: ref, every: [{ eq: { 'order.id': id } }] } }
        : undefined;
    },
    () => this.realms,
    { isLive: true },
  );

  private paymentsQuery = this.args.context?.getCards(
    this,
    () => {
      let ref = identifyCard(Payment);
      let id = this.args.model?.id;
      return ref && id
        ? { filter: { on: ref, every: [{ eq: { 'order.id': id } }] } }
        : undefined;
    },
    () => this.realms,
    { isLive: true },
  );

  // `.instances` read at the point of use, dead slots filtered: a deleted
  // target leaves its slot in place, so a raw iteration renders an empty row.
  get shipments() {
    return (this.shipmentsQuery?.instances ?? []).filter(Boolean);
  }

  get payments() {
    return (this.paymentsQuery?.instances ?? []).filter(Boolean);
  }

  // Absent query (no `context` in some render modes) and unresolved query are
  // different states, and only one of them may paint "none".
  get shipmentsLoading() {
    return Boolean(this.shipmentsQuery) && !this.shipmentsQuery?.instances;
  }

  get paymentsLoading() {
    return Boolean(this.paymentsQuery) && !this.paymentsQuery?.instances;
  }

  // A failed query must render its message where the section would be, not
  // silently as empty — otherwise an HTTP 500 reads as "no results".
  get shipmentsError() {
    return (this.shipmentsQuery as any)?.error;
  }

  get paymentsError() {
    return (this.paymentsQuery as any)?.error;
  }

  get total() {
    return formatMoney(this.args.model?.total);
  }

  get itemPrice() {
    return formatMoney(this.args.model?.price);
  }

  get shipping() {
    return formatMoney(this.args.model?.shippingPrice);
  }

  get authFee() {
    return formatMoney(this.args.model?.authFee);
  }

  get platformFee() {
    return formatMoney(this.args.model?.platformFee);
  }

  // The escrow rail. Each step is `done` from its own event DATE rather than
  // from the status string, so the rail cannot disagree with the timeline —
  // and a refunded order correctly shows the steps it did reach.
  get steps() {
    let m = this.args.model;
    return [
      { key: 'placed', label: 'Placed', done: Boolean(m?.placedAt) },
      { key: 'paid', label: 'Paid into escrow', done: Boolean(m?.paidAt) },
      { key: 'shipped', label: 'Shipped', done: Boolean(m?.shippedAt) },
      {
        key: 'authenticated',
        label: 'Authenticated',
        done: Boolean(m?.authenticatedAt),
      },
      {
        key: 'delivered',
        label: 'Delivered',
        done: Boolean(m?.deliveredAt),
      },
      {
        key: 'completed',
        label: 'Funds released',
        done: Boolean(m?.completedAt),
      },
    ];
  }

  // What the graph itself permits from here. Rendered as TEXT for the moves
  // that still have no command (a shipment's own delivery events drive
  // `authenticating`/`delivered`; `completed` and `disputed` have no tool at
  // all) — a control that looks live and no-ops teaches the user to
  // distrust every other control on the page. The three moves that DO have
  // commands render as real buttons below instead of appearing here.
  get allowedNext() {
    // GUARD THE UNSET CASE. `nextStatuses` with no `from` falls back to
    // "everything except the current value" — which, when the status is
    // blank, is all eight states. Listing all eight as "permitted next" is
    // worse than saying nothing, so an order with no status offers none.
    let from = this.args.model?.orderStatus;
    if (!from) {
      return [];
    }
    return nextOrderStatuses(from).filter(
      // These three are the buttons now — repeating them as text would be
      // the fitted-card "one value in two slots" defect wearing a new hat.
      (n) => !['paid', 'shipped', 'refunded'].includes(n.value),
    );
  }

  // ---- command wiring ----
  // Buttons render ONLY when a command context exists (interactive render)
  // AND the state machine permits the move — otherwise nothing, per the
  // no-lying-affordances rule. The command modules import this one for the
  // transition guards, so importing them back statically is a cycle that
  // evaluates `extends`-time code — the exact bug seller-profile hit. They
  // are loaded dynamically inside the click instead, where the cycle cannot
  // exist because the click happens after every module has evaluated.
  @tracked private acting: string | undefined;
  @tracked private actionError: string | undefined;

  get isBusy() {
    return Boolean(this.acting);
  }

  get commandContext() {
    return this.args.context?.commandContext;
  }

  get canProcessPayment() {
    return canOrderTransition(this.args.model?.orderStatus, 'paid');
  }

  get canRefund() {
    return canOrderTransition(this.args.model?.orderStatus, 'refunded');
  }

  private runAction = async (name: string, make: () => Promise<unknown>) => {
    if (this.acting || !this.commandContext) {
      return;
    }
    this.acting = name;
    this.actionError = undefined;
    try {
      await make();
    } catch (e: any) {
      // Render at the action, not in a toast — the reader must see which
      // move failed and why, next to the button that made it.
      this.actionError = e?.message ?? String(e);
    } finally {
      this.acting = undefined;
    }
  };

  processPayment = () =>
    this.runAction('pay', async () => {
      let { default: ProcessPaymentCommand } =
        await import('./commands/process-payment-command.gts');
      await new ProcessPaymentCommand(this.commandContext!).execute({
        orderId: this.args.model?.id,
      } as any);
    });

  refundOrder = () =>
    this.runAction('refund', async () => {
      let { default: RefundOrderCommand } =
        await import('./commands/refund-order-command.gts');
      await new RefundOrderCommand(this.commandContext!).execute({
        orderId: this.args.model?.id,
      } as any);
    });

  <template>
    <article class='card'>
      <header class='hero'>
        <div class='hero-head'>
          <h1 class='hero-title'>{{if
              @model.productTitle
              @model.productTitle
              'Unlinked listing'
            }}</h1>

          <p class='hero-sub'>
            <ReceiptIcon width='12' height='12' aria-hidden='true' />
            {{#if @model.reference}}
              <span class='ref'>{{@model.reference}}</span>
            {{/if}}
            {{#if @model.sellerName}}
              <span class='sep'>·</span>
              <span class='party'>from
                <strong>{{@model.sellerName}}</strong></span>
            {{/if}}
            {{#if @model.buyerName}}
              <span class='sep'>·</span>
              <span class='party'>to
                <strong>{{@model.buyerName}}</strong></span>
            {{/if}}
          </p>
        </div>

        {{! THE PLAQUE — the total is the dominant element, with the escrow
            state beside it as the thing that qualifies it. Two facts, and the
            money is the loud one. }}
        <div class='answer'>
          <p class='total'>{{if this.total this.total '—'}}</p>
          <div class='answer-meta'>
            {{#if @model.orderStatus}}
              <@fields.orderStatus @format='embedded' />
            {{/if}}
            {{#if @model.fundsHeld}}
              <p class='held'>
                <LockIcon width='12' height='12' aria-hidden='true' />
                Funds held in escrow
              </p>
            {{/if}}
          </div>
        </div>
      </header>

      {{! AT A GLANCE — shape: ol. The escrow rail, the family signature. }}
      <section class='sec'>
        <h2><CalendarIcon
            class='sec-icon'
            width='16'
            height='16'
            aria-hidden='true'
          />Escrow progress</h2>
        <ol class='steps'>
          {{#each this.steps as |s|}}
            <li class='step {{if s.done "step--done"}}'>
              <span class='step-label'>{{s.label}}</span>
            </li>
          {{/each}}
        </ol>
        {{! Dispatch needs a tracking number, so it runs as a command with
            its own input rather than as a button here. }}
        {{#if this.commandContext}}
          <div class='actions'>
            {{#if this.canProcessPayment}}
              <Button
                @tone='primary'
                @appearance='accent'
                @busy={{eq this.acting 'pay'}}
                @disabled={{this.isBusy}}
                {{on 'click' this.processPayment}}
              >Process payment</Button>
            {{/if}}
            {{#if this.canRefund}}
              <Button
                @tone='neutral'
                @busy={{eq this.acting 'refund'}}
                @disabled={{this.isBusy}}
                {{on 'click' this.refundOrder}}
              >Refund order</Button>
            {{/if}}
          </div>
          {{#if this.actionError}}
            <p class='action-err' role='alert'>
              <AlertTriangleIcon width='14' height='14' aria-hidden='true' />
              {{this.actionError}}
            </p>
          {{/if}}
        {{/if}}
        {{#if this.allowedNext.length}}
          {{! Text, not buttons — these moves have no command of their own;
              see `allowedNext`. }}
          <p class='next'>
            <span class='next-k'>Permitted next</span>
            {{! `label` is optional on StatusOption, so fall back to the raw
                value rather than rendering nothing. }}
            {{#each this.allowedNext as |n|}}
              <span class='next-v'>{{if n.label n.label n.value}}</span>
            {{/each}}
          </p>
        {{/if}}
      </section>

      <div class='cols'>
        {{! DETAIL — shape: dl. The receipt. Every amount through the one
            formatter so minor units survive, and the total is visually a step
            above its components rather than a fifth row. }}
        <section class='sec'>
          <h2><CoinsIcon
              class='sec-icon'
              width='16'
              height='16'
              aria-hidden='true'
            />Receipt</h2>
          <dl class='receipt'>
            <div class='r-row'>
              <dt>Item</dt>
              <dd>{{if this.itemPrice this.itemPrice '—'}}</dd>
            </div>
            <div class='r-row'>
              <dt>Shipping</dt>
              <dd>{{if this.shipping this.shipping '—'}}</dd>
            </div>
            <div class='r-row'>
              <dt>Authentication</dt>
              <dd>{{if this.authFee this.authFee '—'}}</dd>
            </div>
            <div class='r-row'>
              <dt>Platform fee</dt>
              <dd>{{if this.platformFee this.platformFee '—'}}</dd>
            </div>
            <div class='r-row r-row--total'>
              <dt>Total</dt>
              <dd>{{if this.total this.total '—'}}</dd>
            </div>
          </dl>
          <p class='receipt-note'>Fees are the amounts charged, not rates —
            re-deriving them would rewrite this receipt if the rate ever
            changed.</p>
        </section>

        {{! DETAIL — shape: linked cards. A different shape from the dl beside
            it, and the answer to "what happens next". }}
        <section class='sec'>
          <h2><PackageIcon
              class='sec-icon'
              width='16'
              height='16'
              aria-hidden='true'
            />Shipments<span class='count'>{{this.shipments.length}}</span></h2>

          {{#if this.shipmentsError}}
            <p class='err'>
              <AlertTriangleIcon
                width='18'
                height='18'
                aria-hidden='true'
              />Could not load shipments.
            </p>
          {{else if this.shipmentsLoading}}
            <p class='wait'><Spinner />Looking for shipments…</p>
          {{else if this.shipments.length}}
            <ul class='links'>
              {{! getCards instances are bare card instances with NO
                  `.component` property — rendering `s.component` silently
                  yields an empty row. getComponent(card) is the API. }}
              {{#each this.shipments as |s|}}
                <li>{{#let (getComponent s) as |ShipmentCard|}}
                    <ShipmentCard @format='embedded' />
                  {{/let}}</li>
              {{/each}}
            </ul>
          {{else}}
            <p class='empty'>
              <PackageIcon width='18' height='18' aria-hidden='true' />Nothing
              shipped yet. The seller ships to the authenticator first, not to
              the buyer.
            </p>
          {{/if}}
        </section>
      </div>

      {{! DETAIL — shape: linked cards again, but this is the money ledger and
          it earns its own full-width row: a partial refund is the case where
          several rows matter at once. }}
      <section class='sec'>
        <h2><CreditCardIcon
            class='sec-icon'
            width='16'
            height='16'
            aria-hidden='true'
          />Payments<span class='count'>{{this.payments.length}}</span></h2>

        {{#if this.paymentsError}}
          <p class='err'>
            <AlertTriangleIcon width='18' height='18' aria-hidden='true' />Could
            not load payments.
          </p>
        {{else if this.paymentsLoading}}
          <p class='wait'><Spinner />Looking for payments…</p>
        {{else if this.payments.length}}
          <ul class='links'>
            {{#each this.payments as |p|}}
              <li>{{#let (getComponent p) as |PaymentCard|}}
                  <PaymentCard @format='embedded' />
                {{/let}}</li>
            {{/each}}
          </ul>
        {{else}}
          <p class='empty'>
            <CreditCardIcon width='18' height='18' aria-hidden='true' />No
            payment recorded. Nothing is held.
          </p>
        {{/if}}
      </section>
    </article>

    <style scoped>
      /* Rule 1: an isolated card gets NO host container — every ancestor
         reports `container-type: normal` — so this template declares its own,
         NAMED, or every @container rule below is inert CSS. `inline-size`, not
         `size`: this column scrolls and `size` needs a definite block size. */
      .card {
        container-type: inline-size;
        container-name: card;
        width: 100%;
        height: 100%;
        overflow-y: auto;
        --_raised: color-mix(in oklch, var(--card) 80%, var(--foreground) 20%);
        --_hairline: color-mix(in oklch, var(--border) 55%, transparent);

        background: var(--background);
        background-image: radial-gradient(
          ellipse 75rem 40rem at 15% -10%,
          var(--card) 0%,
          transparent 60%
        );
        color: var(--foreground);
        font-family: var(--font-sans);
        padding: 1.75rem;
        /* ONE rhythm mechanism — the parent's gap. No child margin-top, so
           there is no override to undo it. */
        display: flex;
        flex-direction: column;
        gap: 1.5rem;
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
        gap: 1.25rem;
      }
      .hero-head {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 0.4rem;
      }
      .hero-title {
        margin: 0;
        font-family: var(--font-serif);
        font-size: clamp(1.5rem, 1.1rem + 1.6cqi, 2rem);
        line-height: 1.15;
        font-weight: 700;
        letter-spacing: -0.01em;
      }
      .hero-sub {
        margin: 0;
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.45em;
        font-size: 0.8125rem;
        color: var(--muted-foreground);
      }
      .sep {
        opacity: 0.6;
      }
      /* An order reference is quoted into support threads and emails: mono,
         tabular, and never truncated. */
      .ref {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        letter-spacing: 0.04em;
        white-space: nowrap;
        color: var(--foreground);
      }
      .party strong {
        color: var(--foreground);
        font-weight: 600;
      }

      /* THE VAULT PLAQUE — gold hairline over the headline figure, the same
         mark as CollectionItem's worth and AuthenticationRecord's verdict. */
      .answer {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: 0.3rem;
        border-top: 1px solid
          color-mix(in oklch, var(--primary) 45%, transparent);
        padding-top: 0.6rem;
      }
      /* The dominant element: hero figure against an 0.875rem body. */
      .total {
        margin: 0;
        font-family: var(--font-serif);
        color: var(--primary-ink);
        font-size: clamp(2.25rem, 1.4rem + 3.5cqi, 2.75rem);
        line-height: 1.05;
        font-weight: 900;
        font-variant-numeric: tabular-nums;
        letter-spacing: -0.02em;
      }
      .answer-meta {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 0.6rem;
      }
      .held {
        margin: 0;
        display: inline-flex;
        align-items: center;
        gap: 0.35em;
        font-size: 0.6875rem;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }

      /* ---------- the one panel primitive ---------- */
      .sec {
        background: var(--card);
        padding: 1rem 1.25rem 1.35rem;
        border-radius: 14px;
        border: 1px solid var(--_hairline);
        box-shadow: var(--shadow-xs);
        min-width: 0;
      }
      .sec h2 {
        margin: 0 0 0.75rem;
        display: flex;
        align-items: center;
        gap: 0.5em;
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.09em;
        color: var(--muted-foreground);
      }
      /* Rule 5: section icons are muted and identical in size across every
         header — one loud thing per card, and it is the total. */
      .sec-icon {
        flex: none;
        color: var(--primary-ink);
      }
      .count {
        margin-left: auto;
        font-variant-numeric: tabular-nums;
        color: var(--foreground);
      }

      .cols {
        display: grid;
        /* Content-sized, not 1fr 1fr: a dl of short rows and a list of linked
           cards should not be forced to equal widths. */
        grid-template-columns: repeat(auto-fit, minmax(17.5rem, 1fr));
        gap: 1.5rem;
      }

      /* ---------- escrow rail (signature) ---------- */
      .steps {
        list-style: none;
        margin: 0;
        padding: 0 0 0 1.25rem;
        border-left: 2px solid var(--_hairline);
        display: grid;
        gap: 0.6rem;
      }
      .step {
        position: relative;
        font-size: 0.875rem;
        color: var(--muted-foreground);
        transition: color 180ms cubic-bezier(0.16, 1, 0.3, 1);
      }
      .step::before {
        content: '';
        position: absolute;
        left: calc(-1.25rem - 0.375rem);
        top: 0.4em;
        width: 0.5625rem;
        height: 0.5625rem;
        border-radius: 50%;
        background: var(--_raised);
        border: 2px solid var(--card);
        transition: background 180ms cubic-bezier(0.16, 1, 0.3, 1);
      }
      /* A reached milestone is a vault mark — gold, matching the provenance
         rail on CollectionItem. */
      .step--done::before {
        background: var(--primary);
      }
      .step--done {
        color: var(--foreground);
        font-weight: 600;
      }
      .actions {
        margin-top: 1rem;
        display: flex;
        flex-wrap: wrap;
        gap: 0.6rem;
      }
      .action-err {
        margin: 0.6rem 0 0;
        display: flex;
        align-items: center;
        gap: 0.45em;
        font-size: 0.8125rem;
        color: var(--destructive-ink);
      }
      .next {
        margin: 1rem 0 0;
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: 0.6rem;
        font-size: 0.8125rem;
      }
      .next-k {
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.07em;
        color: var(--muted-foreground);
      }
      .next-v {
        font-weight: 600;
        color: var(--foreground);
      }

      /* ---------- receipt ---------- */
      .receipt {
        display: grid;
        gap: 0.55rem;
        margin: 0;
      }
      .r-row {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        justify-content: space-between;
        gap: 0.6rem;
        font-size: 0.875rem;
      }
      .r-row dt {
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.07em;
        color: var(--muted-foreground);
      }
      .r-row dd {
        margin: 0;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        color: var(--foreground);
      }
      /* The total steps ABOVE its components rather than reading as a fifth
         row of the same weight. */
      .r-row--total {
        border-top: 1px solid var(--_hairline);
        padding-top: 0.6rem;
      }
      .r-row--total dd {
        font-family: var(--font-serif);
        font-size: 1.25rem;
        font-weight: 700;
        color: var(--primary-ink);
      }
      .receipt-note {
        margin: 0.75rem 0 0;
        font-size: 0.75rem;
        line-height: 1.45;
        color: var(--muted-foreground);
      }

      /* ---------- linked-card lists ---------- */
      .links {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: 0.6rem;
      }

      .empty,
      .wait,
      .err {
        margin: 0;
        display: flex;
        align-items: center;
        gap: 0.5em;
        font-size: 0.8125rem;
        line-height: 1.45;
        color: var(--muted-foreground);
      }
      .err {
        color: var(--destructive-ink);
      }

      @media (prefers-reduced-motion: reduce) {
        .step,
        .step::before {
          transition: none;
        }
      }

      /* Rule 1: these fire because .card declares the container above. */
      @container card (width < 43.75rem) {
        .cols {
          grid-template-columns: 1fr;
        }
        .hero {
          flex-direction: column;
          align-items: flex-start;
        }
      }
    </style>
  </template>
}
