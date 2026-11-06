import GlimmerComponent from '@glimmer/component';
import { OnboardingChecklistStatusField } from '../../hr/onboarding-checklist';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  OnboardingChecklist,
  ONBOARDING_CHECKLIST_STATUSES,
} from '../../hr/onboarding-checklist';
import { OnboardingTemplate } from '../../hr/onboarding-template';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
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

const HYPHEN_RE = /-/g;

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class OnboardingTab extends GlimmerComponent<Signature> {
  // the status column renders the field's own format: dot + label
  StatusAtom = OnboardingChecklistStatusField.atom;
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  setOnboardingView = (view: string) => {
    this.args.tracker.onboardingView = view as 'grid' | 'strip' | 'table';
  };

  setOnboardingSearch = (value: string) => {
    this.args.tracker.debouncedSetOnboardingSearch(value);
  };

  onboardingStatuses = ONBOARDING_CHECKLIST_STATUSES;

  setOnboardingStatusFilter = (status: string) => {
    this.args.tracker.onboardingStatusFilter = status;
  };

  get filteredChecklists(): OnboardingChecklist[] {
    let all = (this.args.tracker.onboardingChecklistsQuery?.instances ??
      []) as OnboardingChecklist[];
    let q = this.args.tracker.onboardingSearch.trim().toLowerCase();
    return all.filter((c) => {
      let statusOk =
        this.args.tracker.onboardingStatusFilter === 'all' ||
        c.status === this.args.tracker.onboardingStatusFilter;
      let textOk =
        !q ||
        c.personName?.toLowerCase().includes(q) ||
        c.title?.toLowerCase().includes(q);
      return statusOk && Boolean(textOk);
    });
  }

  completedTaskCount = (checklist: OnboardingChecklist): number => {
    let tasks = checklist.tasks ?? [];
    return tasks.filter((t) => t && t.status === 'complete').length;
  };

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  statusOptions = [
    { value: 'all', label: 'All' },
    ...ONBOARDING_CHECKLIST_STATUSES.map((value) => ({
      value,
      label: (value.charAt(0).toUpperCase() + value.slice(1)).replace(
        HYPHEN_RE,
        ' ',
      ),
    })),
  ];

  columns: DataColumn<OnboardingChecklist>[] = [
    {
      key: 'person',
      label: 'Person',
      value: (c) => c.personName || c.title,
    },
    { key: 'status', label: 'Status' },
    {
      key: 'progress',
      label: 'Progress',
      value: (c) => `${this.completedTaskCount(c)}/${c.tasks?.length ?? 0}`,
    },
    {
      key: 'started',
      label: 'Started',
      value: (c) => this.args.tracker.formatDate(c.createdDate),
    },
  ];

  progressPct = (c: OnboardingChecklist): number => {
    let total = c.tasks?.length ?? 0;
    return total ? (this.completedTaskCount(c) / total) * 100 : 0;
  };

  rowKey = (c: OnboardingChecklist) => c.id ?? c.title ?? '';

  get subtitle(): string {
    return 'Active onboarding checklists';
  }

  get panelMeta(): string {
    let n = this.filteredChecklists.filter(
      (c) => c.status !== 'complete',
    ).length;
    return this.args.tracker.onboardingChecklistsQuery?.isLoading && !n
      ? '—'
      : `${n} active`;
  }

  fit = new ColumnFit();
  get visibleColumns(): string[] {
    return this.fit.pick(this.columns.map((c) => c.key));
  }
  get notTable(): boolean {
    return this.args.tracker.onboardingView !== 'table';
  }

  <template>
    <TrackerPage
      @group='Hiring'
      @title='Onboarding'
      @subtitle={{this.subtitle}}
    >
      <:default>
        <ListToolbar
          @label='Onboarding checklists'
          @searchValue={{@tracker.onboardingSearch}}
          @searchPlaceholder='Search onboarding checklists…'
          @onSearch={{this.setOnboardingSearch}}
          @filterLabel='Filter by status'
          @filterOptions={{this.statusOptions}}
          @filterValue={{@tracker.onboardingStatusFilter}}
          @onFilter={{this.setOnboardingStatusFilter}}
          @viewOptions={{this.viewOptions}}
          @view={{@tracker.onboardingView}}
          @onView={{this.setOnboardingView}}
          as |bar|
        >
          {{#if @tracker.canCreate}}
            <bar.Action
              @id='new-template'
              @label='New template'
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew OnboardingTemplate}}
            />
            <bar.Action
              @id='add-checklist'
              @label='Add checklist'
              @primary={{true}}
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew OnboardingChecklist}}
            />
          {{/if}}
        </ListToolbar>
        <TrackerSection
          {{this.fit.measure}}
          @title='Checklists'
          @meta={{this.panelMeta}}
          @padded={{this.notTable}}
        >
          {{#if (eq @tracker.onboardingView 'table')}}
            <DataTable
              @visibleColumns={{this.visibleColumns}}
              @loading={{@tracker.onboardingChecklistsQuery.isLoading}}
              @columns={{this.columns}}
              @rows={{this.filteredChecklists}}
              @key={{this.rowKey}}
              @onRowActivate={{@tracker.openRowCard}}
              @label='Onboarding checklists'
              @columnMenu={{false}}
              @sortable={{false}}
              @striped={{false}}
              @flush={{true}}
            >
              <:empty>{{#if
                  @tracker.onboardingChecklistsQuery.isLoading
                }}<LoadingState @label='Loading' />{{else}}<TrackerEmpty>No
                    active onboarding checklists</TrackerEmpty>{{/if}}</:empty>
              <:cell as |text row col|>
                {{#if (eq col.key 'person')}}
                  <RowOpen @onOpen={{fn @tracker.openRowCard row}}>{{#let
                      (getComponent row.employee)
                      as |Atom|
                    }}{{#if Atom}}<Atom
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}{{if text text '—'}}{{/if}}{{/let}}</RowOpen>
                {{else if (eq col.key 'status')}}
                  <this.StatusAtom @model={{row.status}} />
                {{else if (eq col.key 'progress')}}
                  <span class='progress'>
                    {{text}}
                    <ProgressBar
                      class='mini-bar'
                      @value={{this.progressPct row}}
                      aria-hidden='true'
                    />
                  </span>
                {{else}}
                  {{if text text '—'}}
                {{/if}}
              </:cell>
            </DataTable>
          {{else}}
            {{#let (component @context.searchResultsComponent) as |Search|}}
              <Search
                @query={{@tracker.onboardingSearchQuery}}
                @mode='none'
                as |results|
              >
                {{#if results.entries.length}}
                  <Grid
                    @items={{this.asEntries results.entries}}
                    @size={{if
                      (eq @tracker.onboardingView 'strip')
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
                    />{{else}}<TrackerEmpty>No active onboarding checklists</TrackerEmpty>{{/if}}
                {{/if}}
              </Search>
            {{/let}}
          {{/if}}
        </TrackerSection>
      </:default>
    </TrackerPage>
    <style scoped>
      .progress {
        display: inline-flex;
        vertical-align: middle;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .mini-bar {
        width: 4rem;
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
