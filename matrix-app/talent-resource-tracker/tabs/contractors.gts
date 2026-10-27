import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  Contractor,
  CONTRACTOR_STATUSES,
  expiryTone,
  statusLabel,
  statusTone,
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
import { AlertPill, PanelHead, RowOpen } from '../shared';

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
    {
      key: 'invoiceFrequency',
      label: 'Invoice frequency',
      value: (c) => statusLabel(c.invoiceFrequency),
    },
    {
      key: 'contractEnd',
      label: 'Contract end',
      value: (c) => c.contractEndDate,
    },
  ];

  statusLabel = statusLabel;
  statusTone = statusTone;

  endLabel = (contractor: Contractor): string => {
    let days = contractor.daysRemaining ?? 0;
    return days < 0
      ? 'Expired'
      : days === 0
        ? 'Ends today'
        : `Ends in ${days} d`;
  };

  // "5 Nov 2026": day first, short English month, as the mockup writes it.
  endDate = (value: Date | string | undefined): string => {
    if (!value) {
      return '—';
    }
    let d = new Date(value);
    let month = d.toLocaleString('en-US', { month: 'short' });
    return `${d.getDate()} ${month} ${d.getFullYear()}`;
  };

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
            @size='s'
            @onInput={{this.setContractorSearch}}
          />
          <FilterChips
            @options={{this.statusOptions}}
            @value={{@tracker.contractorStatusFilter}}
            @onValueChange={{this.setContractorStatusFilter}}
            @label='Filter by status'
            @size='s'
            @appearance='solid'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.contractorsView}}
            @onValueChange={{this.setContractorsView}}
            @label='View'
            @size='s'
            @appearance='tinted'
            class='list-view'
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
                @onRowActivate={{@tracker.openRowCard}}
                @label='Contractor roster'
                @columnMenu={{false}}
                @sortable={{false}}
                @flush={{true}}
                @striped={{false}}
              >
                <:empty>{{#if @tracker.contractorsQuery.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No contractors'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'name')}}
                    <RowOpen @onOpen={{fn @tracker.openRowCard row}}>{{if
                        text
                        text
                        '—'
                      }}</RowOpen>
                  {{else if (eq col.key 'status')}}
                    <StatusChip
                      @value={{this.statusLabel row.status}}
                      @tone={{this.statusTone row.status}}
                      @appearance='soft'
                      @shape='pill'
                      @dot={{false}}
                    />
                  {{else if (eq col.key 'contractEnd')}}
                    {{#if row.contractEndDate}}
                      <span class='end'>
                        {{#if (this.endTone row)}}
                          <StatusChip
                            @value={{this.endLabel row}}
                            @tone={{if
                              (eq (this.endTone row) 'expired')
                              'danger'
                              'warning'
                            }}
                            @appearance='soft'
                            @shape='pill'
                            @dot={{false}}
                          />
                        {{/if}}
                        {{this.endDate row.contractEndDate}}
                      </span>
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
      .list-view {
        --pretui-seg-radius: var(--boxel-border-radius-pill);
      }
      .list-toolbar > :last-child {
        margin-left: auto;
      }
      .end {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .tile {
        height: 100%;
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.125rem;
      }
    </style>
  </template>
}
