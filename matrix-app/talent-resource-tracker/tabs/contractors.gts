import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  Contractor,
  CONTRACTOR_STATUSES,
  expiryTone,
} from '../../hr/contractor';
import { Button } from '../../../ui-component/components/button';
import {
  DataTable,
  type DataColumn,
} from '../../../ui-component/components/data-table';
import { EmptyState } from '../../../ui-component/components/empty-state';
import { LoadingState } from '../../../ui-component/components/loading-state';
import { Grid } from '../../../ui-component/components/grid';
import { FilterChips } from '../../../ui-component/components/filter-chips';
import { PageScaffold } from '../../../ui-component/components/page-scaffold';
import { Panel } from '../../../ui-component/components/panel';
import { SearchInput } from '../../../ui-component/components/search-input';
import { SegmentedControl } from '../../../ui-component/components/segmented-control';
import { StatusChip } from '../../../ui-component/components/status-chip';
import type { TrackerView } from '../talent-resource-tracker';
import { AlertPill, PanelHead } from '../shared';

const HYPHEN_RE = /-/g;

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class ContractorsTab extends GlimmerComponent<Signature> {
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  setContractorsView = (view: string) => {
    this.args.tracker.contractorsView = view as 'grid' | 'strip' | 'table';
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

  rateLabel = (rate: number | undefined): string => {
    return rate ? `$${rate}/hr` : '—';
  };

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  statusOptions = [
    { value: 'all', label: 'All' },
    ...CONTRACTOR_STATUSES.map((value) => ({
      value,
      label: (value.charAt(0).toUpperCase() + value.slice(1)).replace(
        HYPHEN_RE,
        ' ',
      ),
    })),
  ];

  columns: DataColumn<Contractor>[] = [
    { key: 'name', label: 'Name' },
    { key: 'status', label: 'Status' },
    {
      key: 'rate',
      label: 'Rate',
      align: 'end',
      value: (c) => this.rateLabel(c.billableRate),
    },
    { key: 'invoiceFrequency', label: 'Invoice frequency' },
    {
      key: 'contractEnd',
      label: 'Contract end',
      value: (c) => c.contractEndDate,
    },
  ];

  rowKey = (c: Contractor) => c.id ?? c.name ?? '';

  endTone = (contractor: Contractor) =>
    expiryTone(contractor.daysRemaining ?? undefined);

  get subtitle(): string {
    return 'Current contractor roster';
  }

  get panelMeta(): string {
    let n = this.filteredContractors.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'contractor' : 'contractors'}`;
  }

  get expiringCount(): number {
    return this.args.tracker.contractors.filter(
      (c) =>
        c.status === 'active' &&
        c.daysRemaining != null &&
        c.daysRemaining <= 30,
    ).length;
  }

  showActive = () => this.setContractorStatusFilter('active');

  <template>
    <PageScaffold @title='Contractors' @subtitle={{this.subtitle}}>
      <:actions>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Contractor)}}
          >+ Add contractor</Button>
        {{/if}}
      </:actions>
      <:default>
        {{#if this.expiringCount}}
          <div class='alert-row' role='group' aria-label='Needs attention'>
            <AlertPill
              @tone='warning'
              @onClick={{this.showActive}}
            >{{this.expiringCount}}
              contractor
              {{if (eq this.expiringCount 1) 'contract' 'contracts'}}
              ending ≤30d</AlertPill>
          </div>
        {{/if}}
        <div class='list-toolbar'>
          <SearchInput
            class='list-search'
            @value={{@tracker.contractorSearch}}
            @placeholder='Search contractors…'
            @label='Search contractors'
            @onInput={{this.setContractorSearch}}
          />
          <FilterChips
            @options={{this.statusOptions}}
            @value={{@tracker.contractorStatusFilter}}
            @onValueChange={{this.setContractorStatusFilter}}
            @label='Filter by status'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.contractorsView}}
            @onValueChange={{this.setContractorsView}}
            @label='View'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='Roster'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            {{#if (eq @tracker.contractorsView 'table')}}
              <DataTable
                @loading={{@tracker.contractorsQuery.isLoading}}
                @columns={{this.columns}}
                @rows={{this.filteredContractors}}
                @key={{this.rowKey}}
                @label='Contractor roster'
                @columnMenu={{false}}
              >
                <:empty>{{#if @tracker.contractorsQuery.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No contractors'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'status')}}
                    <StatusChip @value={{row.status}} />
                  {{else if (eq col.key 'contractEnd')}}
                    {{#if row.contractEndDate}}
                      {{@tracker.formatDate row.contractEndDate}}
                      {{#if (this.endTone row)}}
                        <StatusChip
                          @value={{row.expiryLabel}}
                          @tone={{if
                            (eq (this.endTone row) 'expired')
                            'danger'
                            'warning'
                          }}
                        />
                      {{/if}}
                    {{else}}
                      —
                    {{/if}}
                  {{else}}
                    {{if text text '—'}}
                  {{/if}}
                </:cell>
              </DataTable>
            {{else}}
              {{#let (component @context.searchResultsComponent) as |Search|}}
                <Search
                  @query={{@tracker.contractorsSearchQuery}}
                  @mode='none'
                  as |results|
                >
                  {{#if results.entries.length}}
                    <Grid
                      @items={{this.asEntries results.entries}}
                      @size={{if
                        (eq @tracker.contractorsView 'strip')
                        'double-wide-strip'
                        'regular-tile'
                      }}
                      as |entry Item|
                    >
                      <Item>
                        <div
                          class='tile'
                          role={{if
                            @tracker.cardCrudFunctions.viewCard
                            'button'
                          }}
                          tabindex={{if
                            @tracker.cardCrudFunctions.viewCard
                            '0'
                          }}
                          {{on 'click' (fn @tracker.viewEntry entry.id)}}
                          {{on
                            'keydown'
                            (fn @tracker.viewEntryOnKeydown entry.id)
                          }}
                        >
                          <entry.component />
                        </div>
                      </Item>
                    </Grid>
                  {{else}}
                    {{#if results.isLoading}}<LoadingState
                        @label='Loading'
                      />{{else}}<EmptyState
                        @size='s'
                        @texture={{false}}
                        @title='No contractors'
                      />{{/if}}
                  {{/if}}
                </Search>
              {{/let}}
            {{/if}}
          </:default>
        </Panel>
      </:default>
    </PageScaffold>
    <style scoped>
      .alert-row {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }
      .list-toolbar {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .list-search {
        flex: 1;
        min-width: 12rem;
        max-width: 20rem;
      }
      .list-toolbar > :last-child {
        margin-left: auto;
      }
      .tile {
        box-sizing: border-box;
        height: 100%;
        border-radius: var(--boxel-border-radius-lg);
        overflow: hidden;
        background: var(--card);
        box-shadow: var(--pretui-card-shadow, var(--shadow-xs));
        transition: box-shadow 0.15s ease-out;
      }
      .tile:hover,
      .tile:focus-within {
        /* a ring, not a border: a border would take 2px from the fitted
           card and drop it into the next smaller size tier */
        box-shadow:
          0 0 0 1px var(--primary-ink),
          var(--pretui-card-shadow, var(--shadow-xs));
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.125rem;
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
    </style>
  </template>
}
