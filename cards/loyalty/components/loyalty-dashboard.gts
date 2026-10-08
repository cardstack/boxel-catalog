import GlimmerComponent from '@glimmer/component';

import type {
  LoyaltyAccount,
  PointsTransaction,
} from '@cardstack/catalog/cards/loyalty/loyalty-account';
import {
  TierBadge,
  type TierOption,
} from '@cardstack/catalog/cards/loyalty/loyalty-tier-field';
import { Alert } from '@cardstack/pretui/components/alert';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { FormatDate } from '@cardstack/pretui/components/format-date';
import { Stat } from '@cardstack/pretui/components/stat';

import {
  ALERT_STYLE,
  COMPACT_EMPTY_STYLE,
} from '@cardstack/catalog/components/pretui-helpers';

interface Signature {
  Args: {
    account: LoyaltyAccount;
    /**
     * The account's resolved rung — the consumer owns its ladder, so it
     * resolves once: `tierOption(MyTierField, account.tier)`.
     */
    tier?: TierOption;
    /**
     * Recent ledger rows, newest first, already queried and sliced by the
     * consumer — the dashboard renders what it is handed and never counts
     * or sums the ledger itself.
     */
    transactions?: PointsTransaction[];
    /**
     * Expiry callout, precomputed by the consumer: FIFO expiry math is the
     * program's business (see the Credit Points spec), so the dashboard
     * only displays the result.
     */
    expiringPoints?: number;
    expiringOn?: Date;
    /**
     * The rung above, resolved by the consumer from ITS ladder
     * (`nextTier(MyTierField, account.tier)`) — the dashboard displays the
     * aspiration, it never walks a ladder itself.
     */
    nextTier?: TierOption;
  };
  Blocks: {
    /** The consumer's calls to action: view rewards, upgrade, renew. */
    actions?: [];
  };
  Element: HTMLElement;
}

function formatPoints(n?: number | null): string {
  if (n == null || Number.isNaN(n)) {
    return '—';
  }
  return new Intl.NumberFormat().format(n);
}

/**
 * The member's home view of their standing: who they are to the program,
 * the numbers that matter (balance, lifetime), what just happened, and
 * what is about to expire. One component so every loyalty app's home
 * screen carries the same reading order — identity, standing, movement,
 * urgency, actions.
 */
export class LoyaltyDashboard extends GlimmerComponent<Signature> {
  get hasActivity() {
    return (this.args.transactions ?? []).length > 0;
  }

  signedAmount = (transaction: PointsTransaction): string => {
    let amount = transaction.amount ?? 0;
    return `${amount > 0 ? '+' : ''}${formatPoints(amount)}`;
  };

  isEarn = (transaction: PointsTransaction): boolean =>
    (transaction.amount ?? 0) > 0;

  <template>
    <section class='loyalty-dashboard' ...attributes>
      <header class='ld-head'>
        <div class='ld-who'>
          <span class='ld-name'>{{if
              @account.holder.name
              @account.holder.name
              'Member'
            }}</span>
          <span class='ld-number'>{{@account.memberNumber}}</span>
        </div>
        <div class='ld-standing'>
          {{#if @tier}}
            <TierBadge
              @label={{if @tier.label @tier.label @tier.value}}
              @hue={{@tier.hue}}
              @value={{@tier.value}}
            />
          {{/if}}
          {{#if @nextTier}}
            <span class='ld-next-tier'>next:
              {{if @nextTier.label @nextTier.label @nextTier.value}}</span>
          {{/if}}
        </div>
      </header>

      <div class='ld-stats'>
        <Stat
          class='ld-stat'
          @label='Points balance'
          @value={{@account.pointsBalance}}
          @roll={{false}}
        />
        <Stat
          class='ld-stat'
          @label='Lifetime earned'
          @value={{@account.lifetimePoints}}
          @roll={{false}}
        />
      </div>

      {{#if @expiringPoints}}
        <Alert
          @tone='attention'
          @title='{{formatPoints @expiringPoints}} points expire'
          style={{ALERT_STYLE.attention}}
        >{{#if @expiringOn}}On
            <FormatDate
              @date={{@expiringOn}}
              @dateStyle='medium'
            />.{{else}}Soon.{{/if}}
          Use them before then or lose them.</Alert>
      {{/if}}

      <div class='ld-activity'>
        <h3 class='ld-activity-title'>Recent activity</h3>
        {{#if this.hasActivity}}
          <ol class='ld-rows'>
            {{#each @transactions key='id' as |transaction|}}
              <li class='ld-row'>
                <span
                  class='ld-amount
                    {{if (this.isEarn transaction) "earn" "spend"}}'
                >{{this.signedAmount transaction}}</span>
                <span class='ld-reason'>{{if
                    transaction.reason
                    transaction.reason
                    'Points adjustment'
                  }}</span>
                <FormatDate
                  class='ld-when'
                  @date={{transaction.occurredAt}}
                  @dateStyle='medium'
                />
              </li>
            {{/each}}
          </ol>
        {{else}}
          <EmptyState
            @title='No points activity yet'
            @message='It starts with the first earn.'
            @texture={{false}}
            style={{COMPACT_EMPTY_STYLE}}
          />
        {{/if}}
      </div>

      {{#if (has-block 'actions')}}
        <footer class='ld-actions'>{{yield to='actions'}}</footer>
      {{/if}}
    </section>
    <style scoped>
      .loyalty-dashboard {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
        font-family: var(--font-sans);
        color: var(--foreground);
      }
      .ld-head {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .ld-who {
        min-width: 0;
        flex: 1;
        display: flex;
        flex-direction: column;
        gap: 0.125rem;
      }
      .ld-name {
        font-weight: 700;
        font-size: var(--boxel-font-size);
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .ld-number {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.04em;
        color: var(--muted-foreground);
      }
      .ld-standing {
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        gap: var(--boxel-sp-5xs);
        flex-shrink: 0;
      }
      .ld-next-tier {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .ld-stats {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .ld-stat {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        background: var(--card);
        color: var(--card-foreground);
      }
      .ld-activity-title {
        margin: 0 0 var(--boxel-sp-4xs);
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .ld-rows {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
      }
      .ld-row {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-4xs) 0;
        border-bottom: 1px solid var(--border);
        font-size: var(--boxel-font-size-sm);
      }
      .ld-row:last-child {
        border-bottom: none;
      }
      /* Constant-width signed column so the ledger reads as a column of
         numbers, not a ragged list. */
      .ld-amount {
        width: 3.75rem;
        text-align: right;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        flex-shrink: 0;
      }
      .ld-amount.earn {
        color: var(--success-ink);
      }
      .ld-amount.spend {
        color: var(--destructive-ink);
      }
      .ld-reason {
        min-width: 0;
        flex: 1;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .ld-when {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
        flex-shrink: 0;
      }
      .ld-actions {
        display: flex;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
    </style>
  </template>
}

export default LoyaltyDashboard;
