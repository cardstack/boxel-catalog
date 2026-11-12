import type { ComponentLike } from '@glint/template';
import GlimmerComponent from '@glimmer/component';
import { ContractorStatusField } from '../../hr/contractor';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import {
  Contractor,
  CONTRACTOR_STATUSES,
  expiryTone,
  statusLabel,
  statusTone,
} from '../../hr/contractor';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Grid } from '@cardstack/pretui/components/grid';
import type { TrackerView } from '../talent-resource-tracker';
import {
  AlertPill,
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

export class ContractorsTab extends GlimmerComponent<Signature> {
  // the status column renders the field's own format: dot + label
  StatusAtom = ContractorStatusField.atom as unknown as ComponentLike<{
    Args: { model: string | undefined };
  }>;
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

  fit = new ColumnFit();
  get visibleColumns(): string[] {
    return this.fit.pick(this.columns.map((c) => c.key));
  }
  get notTable(): boolean {
    return this.args.tracker.contractorsView !== 'table';
  }

  <template>
    <TrackerPage
      @group='Resources'
      @title='Contractors'
      @subtitle={{this.subtitle}}
    >
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
        <ListToolbar
          @label='Contractors'
          @searchValue={{@tracker.contractorSearch}}
          @searchPlaceholder='Search contractors…'
          @onSearch={{this.setContractorSearch}}
          @filterLabel='Filter by status'
          @filterOptions={{this.statusOptions}}
          @filterValue={{@tracker.contractorStatusFilter}}
          @onFilter={{this.setContractorStatusFilter}}
          @viewOptions={{this.viewOptions}}
          @view={{@tracker.contractorsView}}
          @onView={{this.setContractorsView}}
          as |bar|
        >
          {{#if @tracker.canCreate}}
            <bar.Action
              @id='add-contractor'
              @label='Add contractor'
              @primary={{true}}
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew Contractor}}
            />
          {{/if}}
        </ListToolbar>
        <TrackerSection
          {{this.fit.measure}}
          @title='Roster'
          @meta={{this.panelMeta}}
          @padded={{this.notTable}}
        >
          {{#if (eq @tracker.contractorsView 'table')}}
            <DataTable
              @visibleColumns={{this.visibleColumns}}
              @loading={{@tracker.contractorsQuery.isLoading}}
              @columns={{this.columns}}
              @rows={{this.filteredContractors}}
              @key={{this.rowKey}}
              @label='Contractor roster'
              @columnMenu={{false}}
              @sortable={{false}}
              @flush={{true}}
              @striped={{false}}
            >
              <:empty>{{#if @tracker.contractorsQuery.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<TrackerEmpty>No contractors</TrackerEmpty>{{/if}}</:empty>
              <:cell as |text row col|>
                {{#if (eq col.key 'name')}}
                  <RowOpen @onOpen={{fn @tracker.openRowCard row}}>{{#let
                      (getComponent row)
                      as |Atom|
                    }}{{#if Atom}}<Atom
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}{{if text text '—'}}{{/if}}{{/let}}</RowOpen>
                {{else if (eq col.key 'status')}}
                  <this.StatusAtom @model={{row.status}} />
                {{else if (eq col.key 'contractEnd')}}
                  {{#if row.contractEndDate}}
                    <span class='end'>
                      {{#if (this.endTone row)}}
                        <StatusDot
                          @tone={{if
                            (eq (this.endTone row) 'expired')
                            'danger'
                            'warning'
                          }}
                          @label={{this.endLabel row}}
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
                    />{{else}}<TrackerEmpty>No contractors</TrackerEmpty>{{/if}}
                {{/if}}
              </Search>
            {{/let}}
          {{/if}}
        </TrackerSection>
      </:default>
    </TrackerPage>
    <style scoped>
      .alert-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-lg);
        padding: var(--boxel-sp-xs) 0;
        border-block: 1px solid var(--border);
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
