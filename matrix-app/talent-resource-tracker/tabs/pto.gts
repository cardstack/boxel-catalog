import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Employee } from '../../hr/employee';
import {
  PtoRequest,
  PTO_STATUSES,
  PTO_STATUS_TONES,
  PTO_TYPE_LABELS,
} from '../../hr/pto-request';
import { Avatar } from '../../../ui-component/components/avatar';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
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
import { toLocalDate } from '../dates';
import { PanelHead, RowOpen } from '../shared';

const HYPHEN_RE = /-/g;

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class PtoTab extends GlimmerComponent<Signature> {
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  setPtoView = (view: string) => {
    this.args.tracker.ptoView = view as 'grid' | 'strip' | 'table';
  };

  setPtoSearch = (value: string) => {
    this.args.tracker.debouncedSetPtoSearch(value);
  };

  ptoStatuses = PTO_STATUSES;

  setPtoStatusFilter = (status: string) => {
    this.args.tracker.ptoStatusFilter = status;
  };

  // Client-side mirrors of the PTO/Reviews wire queries for their TABLE
  // views — same mirroring contract as filteredContractors above. Sorted to
  // match the wire query so grid ↔ table shows the same rows in the same
  // order.
  get filteredPtoRequests(): PtoRequest[] {
    let q = this.args.tracker.ptoSearch.trim().toLowerCase();
    return this.args.tracker.ptoRequests
      .filter((req) => {
        let statusOk =
          this.args.tracker.ptoStatusFilter === 'all' ||
          (req.status ?? 'draft') === this.args.tracker.ptoStatusFilter;
        let textOk =
          !q ||
          req.employeeName?.toLowerCase().includes(q) ||
          req.ptoType?.toLowerCase().includes(q);
        return statusOk && Boolean(textOk);
      })
      .sort((a, b) => {
        let aT = a.requestedDate ? toLocalDate(a.requestedDate).getTime() : 0;
        let bT = b.requestedDate ? toLocalDate(b.requestedDate).getTime() : 0;
        return bT - aT;
      });
  }

  // Per-employee PTO balance for the current year: allowance minus days on
  // APPROVED requests starting this year. Matches on the denormalized
  // employeeId scalar, never the `employee` linksTo — this runs once per
  // employee per render (see whoseTurn's comment for the race).
  get ptoBalances(): Array<{
    employee: Employee;
    allowance: number;
    used: number;
    balance: number;
  }> {
    let year = new Date().getFullYear();
    return this.args.tracker.employees
      .filter((e) => e.status !== 'offboarded' && e.ptoAllowanceDays != null)
      .map((employee) => {
        let used = this.args.tracker.ptoRequests
          .filter(
            (r) =>
              r.status === 'approved' &&
              r.employeeId === employee.id &&
              r.startDate &&
              toLocalDate(r.startDate).getFullYear() === year,
          )
          .reduce((sum, r) => sum + (r.days ?? 0), 0);
        let allowance = employee.ptoAllowanceDays as number;
        return { employee, allowance, used, balance: allowance - used };
      })
      .sort((a, b) => a.balance - b.balance);
  }

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  statusOptions = [
    { value: 'all', label: 'All' },
    ...PTO_STATUSES.map((value) => ({
      value,
      label: (value.charAt(0).toUpperCase() + value.slice(1)).replace(
        HYPHEN_RE,
        ' ',
      ),
    })),
  ];

  columns: DataColumn<PtoRequest>[] = [
    { key: 'person', label: 'Person', value: (r) => r.employeeName },
    { key: 'type', label: 'Type', value: (r) => r.ptoType },
    {
      key: 'dates',
      label: 'Dates',
      sortable: false,
      value: (r) => this.dateRange(r),
    },
    { key: 'days', label: 'Days', align: 'end' },
    { key: 'status', label: 'Status' },
  ];

  // Mockup reads day-first: "2 Nov – 6 Nov 2026", a single day as "30 Oct 2026".
  dateRange = (r: PtoRequest): string => {
    // en-US month names: en-GB abbreviates September as "Sept".
    let fmt = (d: Date, year: boolean) =>
      `${d.getDate()} ${d.toLocaleDateString('en-US', { month: 'short' })}${year ? ` ${d.getFullYear()}` : ''}`;
    let s = r.startDate ? toLocalDate(r.startDate) : undefined;
    let e = r.endDate ? toLocalDate(r.endDate) : undefined;
    if (!s || !e) {
      return '—';
    }
    return s.getTime() === e.getTime()
      ? fmt(s, true)
      : `${fmt(s, false)} – ${fmt(e, true)}`;
  };

  statusWord = (status?: string) =>
    (status ?? 'draft')
      .split('-')
      .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
      .join(' ');

  statusTone = (status?: string) => PTO_STATUS_TONES[status ?? 'draft'];

  typeLabel = (type?: string) => (type ? PTO_TYPE_LABELS[type] : undefined);

  rowKey = (r: PtoRequest) => r.id ?? '';

  get subtitle(): string {
    return 'Time-off requests, newest first';
  }

  get panelMeta(): string {
    let n = this.filteredPtoRequests.filter(
      (r) => r.status === 'in-progress',
    ).length;
    return this.args.tracker.isLoading ? '—' : `${n} awaiting approval`;
  }

  <template>
    <PageScaffold @title='PTO Requests' @subtitle={{this.subtitle}}>
      <:actions>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew PtoRequest)}}
          >+ Add request</Button>
        {{/if}}
      </:actions>
      <:default>
        <div class='capacity-row'>
          <span class='capacity-label'>Balance this year</span>
          {{#if this.ptoBalances.length}}
            <ul class='balance-row'>
              {{#each this.ptoBalances key='employee.id' as |row|}}
                <li>
                  <StatusChip
                    @value='{{row.employee.name}} {{row.balance}}d / {{row.allowance}}d'
                    @tone={{if (eq row.balance 0) 'warning' 'success'}}
                    @appearance='soft'
                    @shape='pill'
                    @dot={{false}}
                  />
                </li>
              {{/each}}
            </ul>
          {{else if @tracker.isLoading}}
            <span class='capacity-empty'>—</span>
          {{else}}
            <span class='capacity-empty'>No balances yet</span>
          {{/if}}
        </div>
        <div class='list-toolbar'>
          <SearchInput
            class='list-search'
            @value={{@tracker.ptoSearch}}
            @placeholder='Search PTO requests…'
            @label='Search PTO requests'
            @size='s'
            @onInput={{this.setPtoSearch}}
          />
          <FilterChips
            @options={{this.statusOptions}}
            @value={{@tracker.ptoStatusFilter}}
            @onValueChange={{this.setPtoStatusFilter}}
            @label='Filter by status'
            @size='s'
            @appearance='solid'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.ptoView}}
            @onValueChange={{this.setPtoView}}
            @label='View'
            @size='s'
            @appearance='tinted'
            class='list-view'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='Requests'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            {{#if (eq @tracker.ptoView 'table')}}
              <DataTable
                @loading={{@tracker.ptoRequestsQuery.isLoading}}
                @columns={{this.columns}}
                @rows={{this.filteredPtoRequests}}
                @key={{this.rowKey}}
                @onRowActivate={{@tracker.openRowCard}}
                @label='PTO requests'
                @columnMenu={{false}}
                @sortable={{false}}
                @flush={{true}}
                @striped={{false}}
              >
                <:empty>{{#if @tracker.ptoRequestsQuery.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No PTO requests yet'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'status')}}
                    <StatusChip
                      @value={{this.statusWord row.status}}
                      @tone={{this.statusTone row.status}}
                      @appearance='soft'
                      @shape='pill'
                      @dot={{false}}
                    />
                  {{else if (eq col.key 'type')}}
                    {{#if row.ptoType}}<StatusChip
                        @value={{this.typeLabel row.ptoType}}
                        @tone='neutral'
                        @appearance='soft'
                        @shape='pill'
                        @dot={{false}}
                      />{{else}}—{{/if}}
                  {{else if (eq col.key 'person')}}
                    <RowOpen @onOpen={{fn @tracker.openRowCard row}}><span
                        class='person'
                      >
                        <Avatar
                          @name={{if row.employeeName row.employeeName '?'}}
                          @src={{row.employee.photo.resolvedUrl}}
                          @hue={{AVATAR_HUE}}
                          @size={{40}}
                          aria-hidden='true'
                        />
                        {{if text text '—'}}
                      </span></RowOpen>
                  {{else}}
                    {{if text text '—'}}
                  {{/if}}
                </:cell>
              </DataTable>
            {{else}}
              {{#let (component @context.searchResultsComponent) as |Search|}}
                <Search
                  @query={{@tracker.ptoSearchQuery}}
                  @mode='none'
                  as |results|
                >
                  {{#if results.entries.length}}
                    <Grid
                      @items={{this.asEntries results.entries}}
                      @size={{if
                        (eq @tracker.ptoView 'strip')
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
                        @title='No PTO requests yet'
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
      /* one radius family across the row: the search is a pill */
      .list-view {
        --pretui-seg-radius: var(--boxel-border-radius-pill);
      }
      .list-toolbar > :last-child {
        margin-left: auto;
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
      .person {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-sm);
      }
      .capacity-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .capacity-label {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .capacity-empty {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .balance-row {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        margin: 0;
        padding: 0;
        list-style: none;
      }
    </style>
  </template>
}
