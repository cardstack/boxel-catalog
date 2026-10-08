import GlimmerComponent from '@glimmer/component';
import { cached } from '@glimmer/tracking';
import type Owner from '@ember/owner';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import type { Account } from '@cardstack/catalog/cards/crm/account';
import {
  Invoice,
  invoiceAmounts,
} from '@cardstack/catalog/cards/commerce/invoice';
import { Subscription } from '@cardstack/catalog/cards/commerce/subscription';
import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';

const OPEN_STATUSES = ['sent', 'viewed', 'partial'];

interface AccountMetricsSignature {
  Args: {
    account: Account | undefined;
    context?: any;
  };
  Element: HTMLElement;
}

export class AccountMetrics extends GlimmerComponent<AccountMetricsSignature> {
  private invoiceList: ReturnType<getCards> | undefined;
  private subscriptionList: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: AccountMetricsSignature['Args']) {
    super(owner, args);
    // The account is matched in the query: a search result's links load only
    // after it renders.
    let byAccount = (type: typeof Invoice | typeof Subscription) => () => {
      let ref = identifyCard(type);
      let id = this.args.account?.id;
      return ref && id
        ? { filter: { on: ref, eq: { 'account.id': id } } }
        : undefined;
    };
    this.invoiceList = this.args.context?.getCards(
      this,
      byAccount(Invoice),
      () => this.realms,
      { isLive: true },
    );
    this.subscriptionList = this.args.context?.getCards(
      this,
      byAccount(Subscription),
      () => this.realms,
      { isLive: true },
    );
  }

  private get realms(): string[] | undefined {
    let url = (this.args.account as any)?.[realmURL];
    return url ? [url.href] : undefined;
  }

  private get invoices(): Invoice[] {
    return ((this.invoiceList?.instances ?? []) as Invoice[]).filter(Boolean);
  }

  private get subscriptions(): Subscription[] {
    return ((this.subscriptionList?.instances ?? []) as Subscription[]).filter(
      Boolean,
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
    return [
      { label: 'MRR', value: formatMoney(mrr, code) },
      { label: 'ARR', value: formatMoney(mrr * 12, code) },
      {
        label: 'Outstanding',
        value: formatMoney(this.sum(open, 'balance'), code),
      },
      { label: 'Collected', value: formatMoney(this.sum(paid, 'total'), code) },
      { label: 'Overdue invoices', value: String(overdueCount) },
    ];
  }

  <template>
    <div class='metrics' ...attributes>
      {{#each this.metrics as |metric|}}
        <div class='metric'>
          <span class='label'>{{metric.label}}</span>
          <span class='value'>{{metric.value}}</span>
        </div>
      {{/each}}
    </div>
    <style scoped>
      .metrics {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(9rem, 1fr));
        gap: 0.75rem;
        width: 100%;
      }
      .metric {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        border: 1px solid var(--border, #e5e7eb);
        border-radius: 0.75rem;
        padding: 0.875rem 1rem;
        background: var(--card, #ffffff);
      }
      .label {
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--muted-foreground, #6b7280);
      }
      .value {
        font-size: 1.375rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1.1;
      }
    </style>
  </template>
}
