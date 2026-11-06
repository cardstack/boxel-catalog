import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import { Employee } from '../../hr/employee';
import {
  PtoRequest,
  PTO_STATUSES,
  PTO_STATUS_TONES,
  PTO_TYPE_LABELS,
} from '../../hr/pto-request';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Grid } from '@cardstack/pretui/components/grid';
import type { TrackerView } from '../talent-resource-tracker';
import { toLocalDate } from '../dates';
import {
  ColumnFit,
  getComponent,
  TrackerSection,
  RowOpen,
  ListToolbar,
  TrackerEmpty,
  TrackerPage,
  StatusDot,
} from '../shared';

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

  fit = new ColumnFit();
  get visibleColumns(): string[] {
    return this.fit.pick(this.columns.map((c) => c.key));
  }
  get notTable(): boolean {
    return this.args.tracker.ptoView !== 'table';
  }

  <template>
    <TrackerPage
      @group='People'
      @title='PTO Requests'
      @subtitle={{this.subtitle}}
    >
      <:default>
        <div class='capacity-row'>
          <span class='capacity-label'>Balance this year</span>
          {{#if this.ptoBalances.length}}
            <ul class='balance-row'>
              {{#each this.ptoBalances key='employee.id' as |row|}}
                <li>
                  <StatusDot
                    @tone={{if (eq row.balance 0) 'warning' 'success'}}
                    @label='{{row.employee.name}} {{row.balance}}d / {{row.allowance}}d'
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
        <ListToolbar
          @label='PTO requests'
          @searchValue={{@tracker.ptoSearch}}
          @searchPlaceholder='Search PTO requests…'
          @onSearch={{this.setPtoSearch}}
          @filterLabel='Filter by status'
          @filterOptions={{this.statusOptions}}
          @filterValue={{@tracker.ptoStatusFilter}}
          @onFilter={{this.setPtoStatusFilter}}
          @viewOptions={{this.viewOptions}}
          @view={{@tracker.ptoView}}
          @onView={{this.setPtoView}}
          as |bar|
        >
          {{#if @tracker.canCreate}}
            <bar.Action
              @id='add-request'
              @label='Add request'
              @primary={{true}}
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew PtoRequest}}
            />
          {{/if}}
        </ListToolbar>
        <TrackerSection
          {{this.fit.measure}}
          @title='Requests'
          @meta={{this.panelMeta}}
          @padded={{this.notTable}}
        >
          {{#if (eq @tracker.ptoView 'table')}}
            <DataTable
              @visibleColumns={{this.visibleColumns}}
              @loading={{@tracker.ptoRequestsQuery.isLoading}}
              @columns={{this.columns}}
              @rows={{this.filteredPtoRequests}}
              @key={{this.rowKey}}
              @label='PTO requests'
              @columnMenu={{false}}
              @sortable={{false}}
              @flush={{true}}
              @striped={{false}}
            >
              <:empty>{{#if @tracker.ptoRequestsQuery.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<TrackerEmpty>No PTO requests yet</TrackerEmpty>{{/if}}</:empty>
              <:cell as |text row col|>
                {{#if (eq col.key 'status')}}
                  <StatusDot
                    @tone={{this.statusTone row.status}}
                    @label={{this.statusWord row.status}}
                  />
                {{else if (eq col.key 'type')}}
                  {{#if row.ptoType}}<StatusDot
                      @tone='neutral'
                      @label={{this.typeLabel row.ptoType}}
                    />{{else}}—{{/if}}
                {{else if (eq col.key 'person')}}
                  <RowOpen @onOpen={{fn @tracker.openRowCard row}}>{{#let
                      (getComponent row.employee)
                      as |Atom|
                    }}{{#if Atom}}<Atom
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}{{if text text '—'}}{{/if}}{{/let}}</RowOpen>
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
                        role={{if @tracker.cardCrudFunctions.viewCard 'button'}}
                        tabindex={{if @tracker.cardCrudFunctions.viewCard '0'}}
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
                    />{{else}}<TrackerEmpty>No PTO requests yet</TrackerEmpty>{{/if}}
                {{/if}}
              </Search>
            {{/let}}
          {{/if}}
        </TrackerSection>
      </:default>
    </TrackerPage>
    <style scoped>
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
