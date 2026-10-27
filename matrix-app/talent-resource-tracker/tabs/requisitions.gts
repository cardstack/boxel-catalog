import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { JobRequisition } from '../../hr/job-requisition';
import {
  REQUISITION_STATUSES,
  REQUISITION_STATUS_LABELS,
} from '../../hr/requisition-field';
import { Button } from '../../../ui-component/components/button';
import {
  DataTable,
  type DataColumn,
} from '../../../ui-component/components/data-table';
import { EmptyState } from '../../../ui-component/components/empty-state';
import { LoadingState } from '../../../ui-component/components/loading-state';
import { FilterChips } from '../../../ui-component/components/filter-chips';
import { Grid } from '../../../ui-component/components/grid';
import { PageScaffold } from '../../../ui-component/components/page-scaffold';
import { Panel } from '../../../ui-component/components/panel';
import { SearchInput } from '../../../ui-component/components/search-input';
import { SegmentedControl } from '../../../ui-component/components/segmented-control';
import { StatusChip } from '../../../ui-component/components/status-chip';
import type { TrackerView } from '../talent-resource-tracker';
import { PanelHead } from '../shared';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class RequisitionsTab extends GlimmerComponent<Signature> {
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  setRequisitionsView = (view: string) => {
    this.args.tracker.requisitionsView = view as 'grid' | 'strip' | 'table';
  };

  setRequisitionsSearch = (value: string) => {
    this.args.tracker.debouncedSetRequisitionsSearch(value);
  };

  // Status chip rows for the three v2 tabs — the same idiom as the
  // Directory's department chips, but over each type's fixed enum.
  requisitionsStatuses = REQUISITION_STATUSES;

  setRequisitionsStatusFilter = (status: string) => {
    this.args.tracker.requisitionsStatusFilter = status;
  };

  get requisitions(): JobRequisition[] {
    return (this.args.tracker.requisitionsQuery?.instances ??
      []) as JobRequisition[];
  }

  // Client-side mirrors of the three v2 tabs' wire-query filters, for their
  // TABLE views — toggling grid ↔ table keeps the same rows. The text match
  // approximates the wire query's full-doc `matches` with the fields a table
  // reader would scan for.
  get filteredRequisitions(): JobRequisition[] {
    let q = this.args.tracker.requisitionsSearch.trim().toLowerCase();
    return this.requisitions.filter((req) => {
      let statusOk =
        this.args.tracker.requisitionsStatusFilter === 'all' ||
        (req.status ?? 'draft') === this.args.tracker.requisitionsStatusFilter;
      let textOk =
        !q ||
        req.displayTitle?.toLowerCase().includes(q) ||
        req.department?.toLowerCase().includes(q);
      return statusOk && Boolean(textOk);
    });
  }

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  statusOptions = [
    { value: 'all', label: 'All' },
    ...REQUISITION_STATUSES.map((value) => ({
      value,
      label: REQUISITION_STATUS_LABELS[value] ?? value,
    })),
  ];

  columns: DataColumn<JobRequisition>[] = [
    { key: 'title', label: 'Title', value: (r) => r.displayTitle },
    { key: 'department', label: 'Department' },
    { key: 'headcount', label: 'Headcount', align: 'end' },
    { key: 'status', label: 'Status' },
    {
      key: 'targetFillDate',
      label: 'Target fill date',
      value: (r) => this.args.tracker.formatDate(r.targetFillDate),
    },
  ];

  rowKey = (r: JobRequisition) => r.id ?? r.displayTitle ?? '';

  get subtitle(): string {
    return 'Job openings by approval status';
  }

  get panelMeta(): string {
    let n = this.filteredRequisitions.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'requisition' : 'requisitions'}`;
  }

  <template>
    <PageScaffold @title='Requisitions' @subtitle={{this.subtitle}}>
      <:actions>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew JobRequisition)}}
          >+ Add requisition</Button>
        {{/if}}
      </:actions>
      <:default>
        <div class='list-toolbar'>
          <SearchInput
            class='list-search'
            @value={{@tracker.requisitionsSearch}}
            @placeholder='Search requisitions…'
            @label='Search requisitions'
            @onInput={{this.setRequisitionsSearch}}
          />
          <FilterChips
            @options={{this.statusOptions}}
            @value={{@tracker.requisitionsStatusFilter}}
            @onValueChange={{this.setRequisitionsStatusFilter}}
            @label='Filter by status'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.requisitionsView}}
            @onValueChange={{this.setRequisitionsView}}
            @label='View'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='All requisitions'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            {{#if (eq @tracker.requisitionsView 'table')}}
              <DataTable
                @loading={{@tracker.requisitionsQuery.isLoading}}
                @columns={{this.columns}}
                @rows={{this.filteredRequisitions}}
                @key={{this.rowKey}}
                @label='Requisitions'
                @columnMenu={{false}}
                @sortable={{false}}
              >
                <:empty>{{#if
                    @tracker.requisitionsQuery.isLoading
                  }}<LoadingState @label='Loading' />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No requisitions yet'
                      @message='Draft a requisition to start the approval chain.'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'status')}}
                    <StatusChip @value={{if row.status row.status 'draft'}} />
                  {{else}}
                    {{if text text '—'}}
                  {{/if}}
                </:cell>
              </DataTable>
            {{else}}
              {{#let (component @context.searchResultsComponent) as |Search|}}
                <Search
                  @query={{@tracker.requisitionsSearchQuery}}
                  @mode='none'
                  as |results|
                >
                  {{#if results.entries.length}}
                    <Grid
                      @items={{this.asEntries results.entries}}
                      @size={{if
                        (eq @tracker.requisitionsView 'strip')
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
                        @title='No requisitions yet'
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
