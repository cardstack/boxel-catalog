import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import TableIcon from '@cardstack/boxel-icons/table';
import { htmlSafe } from '@ember/template';
import {
  Contractor,
  CONTRACTOR_STATUSES,
  CONTRACTOR_STATUS_COLORS,
  EXPIRY_TONE_COLORS,
  expiryTone,
} from '../../hr/contractor';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Input } from '@cardstack/pretui/components/input';
import { stateColorOf } from '../../../components/state-pill';
import type { TrackerView } from '../talent-resource-tracker';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class ContractorsTab extends GlimmerComponent<Signature> {
  setContractorsView = (view: 'grid' | 'strip' | 'table') => {
    this.args.tracker.contractorsView = view;
  };

  setContractorSearch = (value: string) => {
    this.args.tracker.debouncedSetContractorSearch(value);
  };

  contractorStatuses = CONTRACTOR_STATUSES;

  setContractorStatusFilter = (status: string) => {
    this.args.tracker.contractorStatusFilter = status;
  };

  get filteredContractors(): Contractor[] {
    let q = this.args.tracker.contractorSearch.trim().toLowerCase();
    return this.args.tracker.contractors.filter((contractor) => {
      let statusOk =
        this.args.tracker.contractorStatusFilter === 'all' ||
        contractor.status === this.args.tracker.contractorStatusFilter;
      let textOk = !q || contractor.name?.toLowerCase().includes(q);
      return statusOk && Boolean(textOk);
    });
  }

  contractorStatusStyle = (status: string | undefined) => {
    let color = stateColorOf(CONTRACTOR_STATUS_COLORS, status);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  // Amber/red tint on the Contractors table's end-date cell — the same tone
  // map (expiryTone + EXPIRY_TONE_COLORS) contractor.gts's own formats use,
  // so table and tile can never disagree about what "expiring" means.
  contractorEndDateStyle = (contractor: Contractor) => {
    let tone = expiryTone(contractor.daysRemaining ?? undefined);
    if (!tone) {
      return undefined;
    }
    let color = stateColorOf(EXPIRY_TONE_COLORS, tone);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  rateLabel = (rate: number | undefined): string => {
    return rate ? `$${rate}/hr` : '—';
  };

  <template>
    <section class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Contractors</h2>
          <p class='byline'>Current contractor roster</p>
        </div>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            class='btn-review'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Contractor)}}
          >+ Add contractor</Button>
        {{/if}}
      </div>
      <div class='list-toolbar'>
        <div class='list-search'>
          <Input
            @type='search'
            @value={{@tracker.contractorSearch}}
            @placeholder='Search contractors…'
            @onInput={{this.setContractorSearch}}
            aria-label='Search contractors'
          />
        </div>
        <div class='directory-chips'>
          <Button
            type='button'
            @tone='neutral'
            @appearance='outlined'
            class='chip
              {{if (eq @tracker.contractorStatusFilter "all") "active"}}'
            {{on 'click' (fn this.setContractorStatusFilter 'all')}}
          >All</Button>
          {{#each this.contractorStatuses as |status|}}
            <Button
              type='button'
              @tone='neutral'
              @appearance='outlined'
              class='chip
                {{if (eq @tracker.contractorStatusFilter status) "active"}}'
              {{on 'click' (fn this.setContractorStatusFilter status)}}
            >{{status}}</Button>
          {{/each}}
        </div>
        <div class='view-toggle' role='group' aria-label='View'>
          <IconButton
            type='button'
            class='view-btn'
            @variant={{if
              (eq @tracker.contractorsView 'grid')
              'primary'
              'ghost'
            }}
            aria-pressed={{if
              (eq @tracker.contractorsView 'grid')
              'true'
              'false'
            }}
            @label='Grid view'
            {{on 'click' (fn this.setContractorsView 'grid')}}
          ><LayoutGridIcon
              class='view-icon'
              width='16'
              height='16'
            /></IconButton>
          <IconButton
            type='button'
            class='view-btn'
            @variant={{if
              (eq @tracker.contractorsView 'strip')
              'primary'
              'ghost'
            }}
            aria-pressed={{if
              (eq @tracker.contractorsView 'strip')
              'true'
              'false'
            }}
            @label='List view'
            {{on 'click' (fn this.setContractorsView 'strip')}}
          ><ListIcon class='view-icon' width='16' height='16' /></IconButton>
          <IconButton
            type='button'
            class='view-btn'
            @variant={{if
              (eq @tracker.contractorsView 'table')
              'primary'
              'ghost'
            }}
            aria-pressed={{if
              (eq @tracker.contractorsView 'table')
              'true'
              'false'
            }}
            @label='Table view'
            {{on 'click' (fn this.setContractorsView 'table')}}
          ><TableIcon class='view-icon' width='16' height='16' /></IconButton>
        </div>
      </div>
      {{#if (eq @tracker.contractorsView 'table')}}
        {{#if this.filteredContractors.length}}
          <div class='data-table-wrap'>
            <table class='data-table'>
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Status</th>
                  <th>Rate</th>
                  <th>Invoice frequency</th>
                  <th>Contract end</th>
                </tr>
              </thead>
              <tbody>
                {{#each this.filteredContractors as |contractor|}}
                  <tr>
                    <td>{{contractor.name}}</td>
                    <td>
                      <span
                        class='status-pill'
                        style={{this.contractorStatusStyle contractor.status}}
                      >{{contractor.status}}</span>
                    </td>
                    <td>{{this.rateLabel contractor.billableRate}}</td>
                    <td>{{if
                        contractor.invoiceFrequency
                        contractor.invoiceFrequency
                        '—'
                      }}</td>
                    <td>
                      {{#if contractor.contractEndDate}}
                        {{#let
                          (this.contractorEndDateStyle contractor)
                          as |endTone|
                        }}
                          {{#if endTone}}
                            <span class='status-pill' style={{endTone}}>
                              {{@tracker.formatDate contractor.contractEndDate}}
                              ·
                              {{contractor.expiryLabel}}
                            </span>
                          {{else}}
                            {{@tracker.formatDate contractor.contractEndDate}}
                          {{/if}}
                        {{/let}}
                      {{else}}
                        —
                      {{/if}}
                    </td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          </div>
        {{else if @tracker.contractorsQuery.isLoading}}
          <p class='empty-note' role='status'>Loading…</p>
        {{else}}
          <p class='empty-note' role='status'>No contractors</p>
        {{/if}}
      {{else}}
        {{#let (component @context.searchResultsComponent) as |Search|}}
          <Search
            @query={{@tracker.contractorsSearchQuery}}
            @mode='none'
            as |results|
          >
            <div
              class='tile-grid
                {{if (eq @tracker.contractorsView "strip") "strip-view"}}'
            >
              {{#each results.entries key='id' as |entry|}}
                <div
                  class='tile
                    {{if (eq @tracker.contractorsView "strip") "strip-tile"}}'
                  role={{if @tracker.cardCrudFunctions.viewCard 'button'}}
                  tabindex={{if @tracker.cardCrudFunctions.viewCard '0'}}
                  {{on 'click' (fn @tracker.viewEntry entry.id)}}
                  {{on 'keydown' (fn @tracker.viewEntryOnKeydown entry.id)}}
                >
                  <entry.component />
                </div>
              {{else}}
                {{#if results.isLoading}}
                  <p class='empty-note' role='status'>Loading…</p>
                {{else}}
                  <p class='empty-note' role='status'>No contractors</p>
                {{/if}}
              {{/each}}
            </div>
          </Search>
        {{/let}}
      {{/if}}
    </section>
    <style scoped>
      .sec-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp);
        padding-bottom: var(--boxel-sp);
        border-bottom: 0.125rem solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 1.25rem;
        margin: 0 0 0.1875rem;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 0.7188rem;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .chip:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      .tab-section {
        animation: tracker-tab-fade-in 0.2s ease-out;
      }
      @keyframes tracker-tab-fade-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tab-section {
          animation: none;
        }
      }
      .data-table {
        margin-top: 0;
      }
      .btn-review {
        margin-bottom: var(--boxel-sp-5xs);
      }
      .empty-note {
        margin: var(--boxel-sp-xs) 0 0;
        font-family: var(--font-mono);
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .tile-grid {
        margin-top: var(--boxel-sp);
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
        gap: var(--boxel-sp);
      }
      .data-table-wrap {
        margin-top: var(--boxel-sp);
        overflow-x: auto;
        border: 1px solid var(--border);
        border-radius: 1rem;
        background: var(--card);
        box-shadow: var(--shadow-xs);
      }
      .data-table {
        width: 100%;
        border-collapse: collapse;
        font-size: var(--boxel-font-size-sm);
      }
      .data-table th {
        text-align: left;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: var(--muted-foreground);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      .data-table td {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      .data-table tbody tr:last-child td {
        border-bottom: none;
      }
      .data-table tbody tr:hover {
        background: var(--muted);
      }
      .status-pill {
        display: inline-block;
        padding: 0.125rem 0.5rem;
        border-radius: 62.4375rem;
        font-size: 0.6875rem;
        text-transform: capitalize;
        white-space: nowrap;
      }
      .tile {
        border: 1px solid var(--border);
        border-radius: 1.25rem;
        overflow: hidden;

        height: 13.5rem;
        background: var(--card);
        box-shadow: var(--shadow-xs);
        transition:
          border-color 0.15s ease-out,
          box-shadow 0.15s ease-out;
      }
      .tile:hover {
        border-color: var(--primary-ink);
        box-shadow: var(--shadow-sm);
      }
      .tile:focus-within {
        border-color: var(--primary-ink);
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
      .tile-grid.strip-view {
        grid-template-columns: repeat(auto-fill, minmax(20rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .tile.strip-tile {
        height: 4rem;
      }
      .directory-chips {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
      }
      .chip {
        text-transform: capitalize;
        transition:
          background-color 0.15s ease-out,
          color 0.15s ease-out,
          border-color 0.15s ease-out;
      }
      .list-toolbar {
        margin-top: var(--boxel-sp-lg);
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp);
        margin-bottom: var(--boxel-sp);
      }
      .list-search {
        flex: 1;
        min-width: 12rem;
        max-width: 20rem;
      }
      .view-toggle {
        display: flex;
        margin-left: auto;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
        flex: none;
      }
      .sec-head {
        flex: none;
      }
      @keyframes action-busy-pulse {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.55;
        }
      }
    </style>
  </template>
}
