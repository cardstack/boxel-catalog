import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Spinner } from '@cardstack/pretui/components/spinner';
import { StatePill } from '../../../components/state-pill';
import ChevronRightIcon from '@cardstack/boxel-icons/chevron-right';
import ReceiptIcon from '@cardstack/boxel-icons/receipt';
import LockIcon from '@cardstack/boxel-icons/lock';
import type { SoleVaultView } from '../sole-vault-app';

interface Signature {
  Args: {
    tracker: SoleVaultView;
  };
}

export class OrdersTab extends GlimmerComponent<Signature> {
  <template>
    <section class='pane pane--orders'>
      <div class='toolbar'>
        <div class='toolbar-left'>
          <h2 class='pane-h'>Orders</h2>
          {{#if @tracker.escrowHeldLabel}}
            <span class='escrow'>
              <LockIcon width='13' height='13' aria-hidden='true' />
              {{@tracker.escrowHeldLabel}}
              <span class='escrow-k'>in escrow</span>
            </span>
          {{/if}}
        </div>
      </div>

      {{#if @tracker.vaultError}}
        <p class='empty' role='alert'>
          <ReceiptIcon width='22' height='22' aria-hidden='true' />
          Orders could not load:
          {{@tracker.vaultError}}
        </p>
      {{else if @tracker.vaultLoading}}
        <p class='empty' role='status'><Spinner />Fetching orders…</p>
      {{else if @tracker.orderRows.length}}
        <ul class='ledger-rows'>
          {{#each @tracker.orderRows as |r|}}
            <li>
              {{! Native button: the row holds an order's item, parties, status and totals. }}
              <button
                type='button'
                class='o-row'
                {{on 'click' (fn @tracker.open r.card)}}
              >
                <span class='cell-ref'>{{r.reference}}</span>
                <span class='tile-title'>{{r.productTitle}}</span>
                {{#if r.statusLabel}}
                  <StatePill @label={{r.statusLabel}} @hue={{r.statusHue}} />
                {{/if}}
                <span class='cell-total'>{{r.total}}</span>
                <ChevronRightIcon
                  class='tile-open'
                  width='16'
                  height='16'
                  role='presentation'
                />
              </button>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class='empty'>
          <ReceiptIcon width='22' height='22' aria-hidden='true' />
          No orders yet. An order is created when a buyer purchases an active
          listing.
        </p>
      {{/if}}
    </section>
    <style scoped>
      .toolbar {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex-wrap: wrap;
        margin-bottom: 1rem;
      }
      .toolbar-left {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        flex: 1 1 auto;
        min-width: 0;
        flex-wrap: nowrap;
      }
      .escrow {
        display: inline-flex;
        align-items: center;
        gap: 0.35em;
        font-size: 0.875rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        color: var(--gold-ink, var(--primary));
        white-space: nowrap;
      }
      .escrow-k {
        font-size: 0.6875rem;
        font-weight: 500;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .cell-ref {
        font-family: var(--font-mono);
        font-size: 0.75rem;
        font-variant-numeric: tabular-nums;
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .cell-total {
        font-family: var(--font-serif);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        color: var(--gold-ink, var(--primary));
        white-space: nowrap;
      }
      .pane {
        animation: stage-enter 240ms cubic-bezier(0.16, 1, 0.3, 1) both;
      }
      @media (prefers-reduced-motion: reduce) {
        .pane {
          animation: none;
        }
      }
      .pane-h {
        margin: 0;
        font-family: var(--font-serif);
        font-size: 1.625rem;
        font-weight: 700;
        letter-spacing: -0.01em;
      }
      .wall,
      .ledger-list,
      .ledger-rows {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .ledger-rows {
        display: grid;
        gap: 0.5rem;
      }
      .tile,
      .o-row {
        position: relative;
        display: block;
        width: 100%;
        text-align: left;
        padding: 0;
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-radius: 6px;
        color: inherit;
        font: inherit;
        cursor: pointer;
        overflow: hidden;
        box-shadow: var(--shadow-xs);
        transition:
          transform 180ms cubic-bezier(0.16, 1, 0.3, 1),
          box-shadow 180ms cubic-bezier(0.16, 1, 0.3, 1),
          border-color 180ms cubic-bezier(0.16, 1, 0.3, 1);
      }
      .tile:hover,
      .tile:focus-visible,
      .o-row:hover,
      .o-row:focus-visible {
        transform: translateY(-3px);
        box-shadow: var(--shadow-lg);
        border-color: color-mix(in oklch, var(--primary) 55%, var(--_hairline));
      }
      .tile:focus-visible,
      .o-row:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
      }
      .tile-open {
        position: absolute;
        top: 0.75rem;
        right: 0.75rem;
        color: var(--muted-foreground);
        transition: transform 180ms cubic-bezier(0.16, 1, 0.3, 1);
      }
      @media (prefers-reduced-motion: reduce) {
        .tile,
        .o-row,
        .cert,
        .tile-open {
          transition: none;
        }
        .tile:hover,
        .tile:focus-visible,
        .o-row:hover,
        .o-row:focus-visible,
        .cert:hover,
        .cert:focus-visible {
          transform: none;
        }
      }
      .tile-title {
        font-weight: 700;
        font-size: 0.9375rem;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .o-row {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto auto auto;
        align-items: center;
        gap: 0.9rem;
        padding: 0.75rem 1rem;
      }
      .empty {
        margin: 0;
        display: flex;
        align-items: center;
        gap: 0.6rem;
        padding: 2rem;
        background: var(--card);
        border: 1px solid var(--_hairline);
        border-radius: 6px;
        color: var(--muted-foreground);
        font-size: 0.9375rem;
        box-shadow: var(--shadow-xs);
      }
      @container vault (width < 860px) {
        .toolbar-left {
          flex-wrap: wrap;
        }
      }
      @container vault (width < 460px) {
        .o-row {
          grid-template-columns: auto minmax(0, 1fr) auto;
        }
      }
    </style>
  </template>
}
