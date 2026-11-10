import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { array, fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import { AccountMetrics } from '../../crm/components/account-metrics';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { CardList } from './card-list';
import { RelatedList, shortDate, usd as money } from '../../crm/record-views';
import { sumLineItems } from '../../commerce/line-item-totals';
import { PageHead } from './page-head';
import { StatStrip } from './stat-strip';
import type { Opportunity } from '../../crm/opportunity';
import type { Invoice } from '../../commerce/invoice';
import type { Subscription } from '../../commerce/subscription';
import type { Contact } from '../../crm/contact';
import type { Activity } from '../../crm/activity';
import type { RevenueOsConsole } from '../revenue-os';

interface Signature {
  Args: {
    console: RevenueOsConsole;
    context: RevenueOsConsole['args']['context'];
  };
}

// The Accounts tab: a searchable account list beside the selected account's
// deals, invoices, contacts, subscriptions and activity.
export class AccountsPane extends Component<Signature> {
  get accountContacts(): Contact[] {
    let id = this.args.console.selectedAccount?.id;
    return this.args.console.contacts.filter((c) => c.account?.id === id);
  }
  get accountSubscriptions(): Subscription[] {
    let id = this.args.console.selectedAccount?.id;
    return this.args.console.subscriptions.filter((s) => s.account?.id === id);
  }
  get accountDeals(): Opportunity[] {
    let id = this.args.console.selectedAccount?.id;
    return this.args.console.opportunities.filter((o) => o.account?.id === id);
  }
  get accountInvoices(): Invoice[] {
    let id = this.args.console.selectedAccount?.id;
    return this.args.console.invoices.filter((i) => i.account?.id === id);
  }
  get accountActivities(): Activity[] {
    let ids = new Set<string>();
    let id = this.args.console.selectedAccount?.id;
    if (id) ids.add(id);
    for (let inv of this.args.console.invoices) {
      if (inv.account?.id === id && inv.id) ids.add(inv.id);
    }
    for (let opp of this.args.console.opportunities) {
      if (opp.account?.id === id && opp.id) ids.add(opp.id);
    }
    return this.args.console.activities
      .filter((a) => a.about?.id && ids.has(a.about.id))
      .sort(
        (a, b) =>
          new Date(b.occurredAt ?? 0).getTime() -
          new Date(a.occurredAt ?? 0).getTime(),
      );
  }

  dealMeta = (d: any) =>
    [d.stage, d.closeDate ? `closes ${shortDate(d.closeDate)}` : '']
      .filter(Boolean)
      .join(' · ');
  dealStage = (_d: any) => undefined;
  dealAmount = (d: any) => money(d.value?.amount);
  invoiceMeta = (i: any) =>
    i.dueDate ? `Due ${shortDate(i.dueDate)}` : undefined;
  invoiceStatus = (i: any) => i.displayStatus ?? i.status;
  invoiceAmount = (i: any) => money(sumLineItems(i.lineItems).total);
  contactMeta = (c: any) => [c.jobTitle, c.email].filter(Boolean).join(' · ');
  subMeta = (x: any) =>
    [x.billingCycle, x.startDate ? `since ${shortDate(x.startDate, true)}` : '']
      .filter(Boolean)
      .join(' · ');
  subStatus = (x: any) => x.status;
  subAmount = (x: any) =>
    `${money(x.price?.amount)}${x.billingCycle === 'yearly' ? '/yr' : '/mo'}`;
  activityMeta = (a: any) =>
    [a.occurredAt ? shortDate(a.occurredAt) : '', a.author?.name]
      .filter(Boolean)
      .join(' · ');

  FORMS = [
    { name: 'full', minWidth: 14 },
    { name: 'icon', minWidth: 2.5 },
  ];
  PRIMARY_FORMS = [{ name: 'full', minWidth: 8 }];

  get activeSubscriptions() {
    return this.stats[1]?.value;
  }
  get stats() {
    let c = this.args.console;
    let active = c.subscriptions.filter((s) =>
      ['active', 'trial'].includes(s.status ?? ''),
    ).length;
    return [
      {
        label: 'Accounts',
        value: c.accounts.length,
        hint: 'customers on file',
        tone: 'neutral',
      },
      {
        label: 'Active subscriptions',
        value: active,
        hint: 'active or in trial',
        tone: 'success',
      },
      {
        label: 'MRR',
        value: c.dash.mrr,
        hint: `${c.dash.arr} annualized`,
        tone: 'info',
      },
    ];
  }

  <template>
    <section class='pane'>
      <PageHead
        @title='Accounts'
        @subtitle='{{@console.accounts.length}} accounts · {{this.activeSubscriptions}} active subscriptions'
      />
      <StatStrip @stats={{this.stats}} @label='Account totals' />
      <LayoutControl @label='Account search and actions' as |lc|>
        <lc.Slot
          @id='search'
          @priority={{1}}
          @forms={{this.FORMS}}
          @label='Search'
        >
          <label>
            <VisuallyHidden>Search accounts</VisuallyHidden>
            <SearchInput
              @placeholder='Search name, domain, contact email…'
              @value={{@console.accountQuery}}
              @onInput={{@console.setAccountQuery}}
            />
          </label>
        </lc.Slot>
        <span class='spacer'></span>
        <lc.Slot
          @id='new'
          @priority={{0}}
          @pinned={{true}}
          @forms={{this.PRIMARY_FORMS}}
          @label='New account'
        >
          <Button
            @icon={{PlusIcon}}
            @appearance='accent'
            {{on 'click' @console.newAccount}}
          >New account</Button>
        </lc.Slot>
      </LayoutControl>
      {{#if @console.queriesSettled}}
        <div class='split'>
          <aside class='side-list'>
            <h3>Accounts</h3>
            <CardList
              @items={{@console.filteredAccounts}}
              @label='Accounts'
              @format='atom'
              @cardComponent={{@console.cardComponent}}
              @loading={{@console.isLoading}}
              @onOpen={{@console.openCard}}
              @selected={{@console.selectedAccount.id}}
              @onSelect={{@console.selectAccount}}
              @emptyMessage='No accounts match'
            />
          </aside>
          <div class='detail'>
            {{#if @console.selectedAccount}}
              <div class='detail-head'>
                <h2>{{@console.selectedAccount.name}}</h2>
                <div class='head-actions'>
                  <Button
                    @appearance='outlined'
                    {{on 'click' @console.logActivity}}
                  >Log activity</Button>
                  <Button
                    @appearance='outlined'
                    {{on
                      'click'
                      (fn @console.openCard @console.selectedAccount)
                    }}
                  >Open account</Button>
                </div>
              </div>
              {{! keyed: a new account gets a new component, so its queries are rebuilt, not re-aimed }}
              {{#each (array @console.selectedAccount) key='id' as |account|}}
                <AccountMetrics
                  @account={{account}}
                  @invoices={{@console.invoices}}
                  @subscriptions={{@console.subscriptions}}
                />
              {{/each}}
              <div class='detail-cols'>
                <div class='panel'>
                  <div class='panel-head'>
                    <h3>Deals</h3>
                    <Button
                      @icon={{PlusIcon}}
                      @appearance='plain'
                      {{on 'click' @console.newDeal}}
                    >Add</Button>
                  </div>
                  <RelatedList
                    @cards={{this.accountDeals}}
                    @empty='No deals yet'
                    @meta={{this.dealMeta}}
                    @status={{this.dealStage}}
                    @amount={{this.dealAmount}}
                  />
                </div>
                <div class='panel'>
                  <h3>Invoices</h3>
                  <RelatedList
                    @cards={{this.accountInvoices}}
                    @empty='No invoices yet'
                    @meta={{this.invoiceMeta}}
                    @status={{this.invoiceStatus}}
                    @amount={{this.invoiceAmount}}
                  />
                </div>
                <div class='panel'>
                  <div class='panel-head'>
                    <h3>Contacts</h3>
                    <Button
                      @icon={{PlusIcon}}
                      @appearance='plain'
                      {{on 'click' @console.newContact}}
                    >Add</Button>
                  </div>
                  <RelatedList
                    @cards={{this.accountContacts}}
                    @empty='No contacts yet'
                    @meta={{this.contactMeta}}
                  />
                </div>
                <div class='panel'>
                  <h3>Subscriptions</h3>
                  <RelatedList
                    @cards={{this.accountSubscriptions}}
                    @empty='No subscriptions'
                    @meta={{this.subMeta}}
                    @status={{this.subStatus}}
                    @amount={{this.subAmount}}
                  />
                </div>
                <div class='panel wide'>
                  <h3>Activity</h3>
                  <RelatedList
                    @cards={{this.accountActivities}}
                    @empty='No activity recorded'
                    @meta={{this.activityMeta}}
                  />
                </div>
              </div>
            {{/if}}
          </div>
        </div>
      {{else}}
        <p class='loading' role='status'>Loading accounts…</p>
      {{/if}}
    </section>
    <style scoped>
      .pane {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }
      .loading {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .spacer {
        flex: 1;
      }
      .panel-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
      }
      h3 {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
        color: var(--foreground);
      }
      .panel-head h3 {
        padding-inline-end: 0;
      }
      .panel {
        min-width: 0;
        overflow: hidden;
      }
      .split {
        display: grid;
        grid-template-columns: minmax(15rem, 20rem) 1fr;
        align-items: start;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .side-list {
        display: flex;
        flex-direction: column;
        min-width: 0;
      }
      .detail {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        min-width: 0;
        box-shadow: -1px 0 0 var(--border);
      }
      .detail-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .detail-head h2 {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      /* One grid, every cell full height: the dividers sit on the cells, so a
         short column never leaves its border hanging. */
      .detail-cols {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        align-items: stretch;
        border-block-start: 1px solid var(--border);
      }
      .detail-cols > .panel:nth-child(odd):not(.wide) {
        border-inline-end: 1px solid var(--border);
      }
      .detail-cols > .panel:nth-child(n + 3) {
        border-block-start: 1px solid var(--border);
      }
      .wide {
        grid-column: 1 / -1;
      }
      @container (max-width: 36rem) {
        .detail-cols {
          grid-template-columns: minmax(0, 1fr);
        }
        .detail-cols > .panel:nth-child(odd):not(.wide) {
          border-inline-end: 0;
        }
        .detail-cols > .panel + .panel {
          border-block-start: 1px solid var(--border);
        }
      }

      .head-actions {
        display: flex;
        gap: var(--boxel-sp-xxs);
      }
    </style>
  </template>
}
