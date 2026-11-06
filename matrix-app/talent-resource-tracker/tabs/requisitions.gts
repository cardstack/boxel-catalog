import type { ComponentLike } from '@glint/template';
import GlimmerComponent from '@glimmer/component';
import { RequisitionStatusField } from '../../hr/requisition-field';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import { JobRequisition } from '../../hr/job-requisition';
import {
  REQUISITION_STATUSES,
  REQUISITION_STATUS_LABELS,
} from '../../hr/requisition-field';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Grid } from '@cardstack/pretui/components/grid';
import type { TrackerView } from '../talent-resource-tracker';
import {
  ColumnFit,
  getComponent,
  TrackerSection,
  RowOpen,
  ListToolbar,
  TrackerEmpty,
  TrackerPage,
} from '../shared';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class RequisitionsTab extends GlimmerComponent<Signature> {
  // the status column renders the field's own format: dot + label
  StatusAtom = RequisitionStatusField.atom as unknown as ComponentLike<{
    Args: { model: string | undefined };
  }>;
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
    return this.args.tracker.requisitionsQuery?.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'requisition' : 'requisitions'}`;
  }

  fit = new ColumnFit();
  get visibleColumns(): string[] {
    return this.fit.pick(this.columns.map((c) => c.key));
  }
  get notTable(): boolean {
    return this.args.tracker.requisitionsView !== 'table';
  }

  <template>
    <TrackerPage
      @group='Hiring'
      @title='Requisitions'
      @subtitle={{this.subtitle}}
    >
      <:default>
        <ListToolbar
          @label='Requisitions'
          @searchValue={{@tracker.requisitionsSearch}}
          @searchPlaceholder='Search requisitions…'
          @onSearch={{this.setRequisitionsSearch}}
          @filterLabel='Filter by status'
          @filterOptions={{this.statusOptions}}
          @filterValue={{@tracker.requisitionsStatusFilter}}
          @onFilter={{this.setRequisitionsStatusFilter}}
          @viewOptions={{this.viewOptions}}
          @view={{@tracker.requisitionsView}}
          @onView={{this.setRequisitionsView}}
          as |bar|
        >
          {{#if @tracker.canCreate}}
            <bar.Action
              @id='add-requisition'
              @label='Add requisition'
              @primary={{true}}
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew JobRequisition}}
            />
          {{/if}}
        </ListToolbar>
        <TrackerSection
          {{this.fit.measure}}
          @title='All requisitions'
          @meta={{this.panelMeta}}
          @padded={{this.notTable}}
        >
          {{#if (eq @tracker.requisitionsView 'table')}}
            <DataTable
              @visibleColumns={{this.visibleColumns}}
              @loading={{@tracker.requisitionsQuery.isLoading}}
              @columns={{this.columns}}
              @rows={{this.filteredRequisitions}}
              @key={{this.rowKey}}
              @label='Requisitions'
              @columnMenu={{false}}
              @sortable={{false}}
              @striped={{false}}
              @flush={{true}}
            >
              <:empty>{{#if @tracker.requisitionsQuery.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<TrackerEmpty>No requisitions yet. Draft a
                    requisition to start the approval chain.</TrackerEmpty>{{/if}}</:empty>
              <:cell as |text row col|>
                {{#if (eq col.key 'title')}}
                  <RowOpen @onOpen={{fn @tracker.openRowCard row}}>{{#let
                      (getComponent row)
                      as |Atom|
                    }}{{#if Atom}}<Atom
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}{{if text text '—'}}{{/if}}{{/let}}</RowOpen>
                {{else if (eq col.key 'status')}}
                  <this.StatusAtom @model={{row.status}} />
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
                    />{{else}}<TrackerEmpty>No requisitions yet</TrackerEmpty>{{/if}}
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
    </style>
  </template>
}
