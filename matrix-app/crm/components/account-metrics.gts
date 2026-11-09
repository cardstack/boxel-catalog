import GlimmerComponent from '@glimmer/component';
import { cached } from '@glimmer/tracking';
import { Stat } from '@cardstack/pretui/components/stat';
import type { Account } from '../account';
import { Invoice, invoiceAmounts } from '../../commerce/invoice';
import { Subscription } from '../../commerce/subscription';

const OPEN_STATUSES = ['sent', 'viewed', 'partial'];

interface AccountMetricsSignature {
  Args: {
    account: Account | undefined;
    invoices?: readonly Invoice[];
    subscriptions?: readonly Subscription[];
  };
  Element: HTMLElement;
}

export class AccountMetrics extends GlimmerComponent<AccountMetricsSignature> {
  // The caller already holds every invoice and subscription: filter them here
  // instead of opening two live searches per selected account (a search created
  // during render re-set its realms after they were read and crashed the tab).
  private get invoices(): Invoice[] {
    let id = this.args.account?.id;
    return (this.args.invoices ?? []).filter((i) => id && i.account?.id === id);
  }

  private get subscriptions(): Subscription[] {
    let id = this.args.account?.id;
    return (this.args.subscriptions ?? []).filter(
      (s) => id && s.account?.id === id,
    );
  }

  /**
   * The account's currency: its subscriptions' first, else its invoices'.
   * Amounts in any other currency are left out of the sums rather than
   * added as if they were the same money.
   */
  @cached
  get currency(): string {
    for (let sub of this.subscriptions) {
      let c = sub.price?.currency?.code;
      if (c) return c;
    }
    for (let inv of this.invoices) {
      let c = invoiceAmounts(inv).code;
      if (c) return c;
    }
    return 'USD';
  }

  private sum(list: Invoice[], pick: 'total' | 'balance'): number {
    let code = this.currency;
    let sum = 0;
    for (let inv of list) {
      let amounts = invoiceAmounts(inv);
      if ((amounts.code ?? code) !== code) continue;
      sum += amounts[pick];
    }
    return sum;
  }

  @cached
  get mrr(): number {
    let code = this.currency;
    let amount = 0;
    for (let sub of this.subscriptions) {
      if (!['active', 'trial'].includes(sub.status ?? '')) continue;
      if ((sub.price?.currency?.code ?? code) !== code) continue;
      let price = sub.price?.amount ?? 0;
      amount += sub.billingCycle === 'yearly' ? price / 12 : price;
    }
    return amount;
  }

  @cached
  get metrics() {
    let mrr = this.mrr;
    let code = this.currency;
    let open = this.invoices.filter((i) =>
      OPEN_STATUSES.includes(i.status ?? ''),
    );
    let paid = this.invoices.filter((i) => i.status === 'paid');
    let overdueCount = this.invoices.filter(
      (i) => (i.daysOverdue ?? 0) > 0,
    ).length;
    let money = (label: string, value: number) => ({
      label,
      value,
      style: 'currency' as const,
      currency: code,
    });
    return [
      money('MRR', mrr),
      money('ARR', mrr * 12),
      money('Outstanding', this.sum(open, 'balance')),
      money('Collected', this.sum(paid, 'total')),
      {
        label: 'Overdue invoices',
        value: overdueCount,
        style: 'decimal' as const,
        currency: undefined,
      },
    ];
  }

  <template>
    <div class='metrics' ...attributes>
      {{#each this.metrics as |metric|}}
        {{! Fed from a live query, so the digits do not roll. }}
        <Stat
          class='metric'
          @label={{metric.label}}
          @value={{metric.value}}
          @style={{metric.style}}
          @currency={{metric.currency}}
          @locale='en-US'
          @maximumFractionDigits={{0}}
          @roll={{false}}
        />
      {{/each}}
    </div>
    <style scoped>
      .metrics {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(7rem, 1fr));
        width: 100%;
        border-block: 1px solid var(--border);
      }
      .metric {
        padding: 0.5rem 0.625rem;
        background: var(--card);
        color: var(--card-foreground);
        box-shadow: -1px 0 0 var(--border);
      }
    </style>
  </template>
}
