import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/pretui/components/button';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import { AccountMetrics } from '../../crm/components/account-metrics';
import { CardList } from './card-list';
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

  <template>
    <section class='pane'>
      <div class='pane-head'>
        <h2>Accounts</h2>
        <Button
          @appearance='outlined'
          @size='sm'
          {{on 'click' @console.newAccount}}
        >New account</Button>
      </div>
      <div class='split'>
        <aside class='side-list'>
          <label class='search-label'>
            <VisuallyHidden>Search accounts</VisuallyHidden>
            <SearchInput
              @placeholder='Search name, domain, contact email…'
              @value={{@console.accountQuery}}
              @onInput={{@console.setAccountQuery}}
            />
          </label>
          <CardList
            @items={{@console.filteredAccounts}}
            @label='Accounts'
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
                  @size='sm'
                  {{on 'click' @console.logActivity}}
                >Log activity</Button>
                <Button
                  @appearance='outlined'
                  @size='sm'
                  {{on 'click' (fn @console.openCard @console.selectedAccount)}}
                >Open account</Button>
              </div>
            </div>
            <AccountMetrics
              @account={{@console.selectedAccount}}
              @context={{@context}}
            />
            <div class='detail-cols'>
              <div class='panel'>
                <div class='panel-head'>
                  <h3>Deals</h3>
                  <Button
                    @appearance='plain'
                    @size='sm'
                    {{on 'click' @console.newDeal}}
                  >+ Add</Button>
                </div>
                <CardList
                  @items={{this.accountDeals}}
                  @label='Deals'
                  @cardComponent={{@console.cardComponent}}
                  @loading={{@console.isLoading}}
                  @onOpen={{@console.openCard}}
                  @emptyMessage='No deals yet'
                />
              </div>
              <div class='panel'>
                <h3>Invoices</h3>
                <CardList
                  @items={{this.accountInvoices}}
                  @label='Invoices'
                  @cardComponent={{@console.cardComponent}}
                  @loading={{@console.isLoading}}
                  @onOpen={{@console.openCard}}
                  @emptyMessage='No invoices yet'
                />
              </div>
              <div class='panel'>
                <div class='panel-head'>
                  <h3>Contacts</h3>
                  <Button
                    @appearance='plain'
                    @size='sm'
                    {{on 'click' @console.newContact}}
                  >+ Add</Button>
                </div>
                <CardList
                  @items={{this.accountContacts}}
                  @label='Contacts'
                  @cardComponent={{@console.cardComponent}}
                  @loading={{@console.isLoading}}
                  @onOpen={{@console.openCard}}
                  @emptyMessage='No contacts yet'
                />
              </div>
              <div class='panel'>
                <h3>Subscriptions</h3>
                <CardList
                  @items={{this.accountSubscriptions}}
                  @label='Subscriptions'
                  @cardComponent={{@console.cardComponent}}
                  @loading={{@console.isLoading}}
                  @onOpen={{@console.openCard}}
                  @emptyMessage='No subscriptions'
                />
              </div>
              <div class='panel timeline'>
                <h3>Activity</h3>
                <CardList
                  @items={{this.accountActivities}}
                  @label='Activity'
                  @cardComponent={{@console.cardComponent}}
                  @loading={{@console.isLoading}}
                  @onOpen={{@console.openCard}}
                  @emptyMessage='No activity recorded'
                />
              </div>
            </div>
          {{/if}}
        </div>
      </div>
    </section>
    <style scoped>
      .pane {
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      .pane-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 1rem;
        flex-wrap: wrap;
      }
      h2 {
        margin: 0;
        font-size: 1.0625rem;
        font-family: var(--font-sans);
      }
      .panel-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 0.5rem;
      }
      .panel {
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        padding: 1rem 1.25rem;
        background: var(--card);
      }
      h3 {
        margin: 0 0 0.75rem;
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--muted-foreground);
      }
      .split {
        display: grid;
        grid-template-columns: minmax(15rem, 20rem) 1fr;
        gap: 1rem;
        align-items: start;
      }
      .side-list {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }
      .detail {
        display: flex;
        flex-direction: column;
        gap: 1rem;
        min-width: 0;
      }
      .detail-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
      }
      .detail-cols {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
        gap: 1rem;
        align-items: start;
      }
      .timeline {
        max-height: 24rem;
        overflow-y: auto;
      }
      .head-actions {
        display: flex;
        gap: 0.375rem;
      }
    </style>
  </template>
}
