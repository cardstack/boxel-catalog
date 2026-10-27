import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  OnboardingChecklist,
  ONBOARDING_CHECKLIST_STATUSES,
} from '../../hr/onboarding-checklist';
import { OnboardingTemplate } from '../../hr/onboarding-template';
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
import { PanelHead } from '../shared';

const HYPHEN_RE = /-/g;

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class OnboardingTab extends GlimmerComponent<Signature> {
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
        this.args.tracker.onboardingStatusFilter === 'all'
          ? c.status !== 'complete'
          : c.status === this.args.tracker.onboardingStatusFilter;
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
    { value: 'all', label: 'Active' },
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
      sortable: false,
      value: (c) =>
        `${this.completedTaskCount(c)}/${c.tasks?.length ?? 0} tasks`,
    },
    {
      key: 'started',
      label: 'Started',
      value: (c) => this.args.tracker.formatDate(c.createdDate),
    },
  ];

  rowKey = (c: OnboardingChecklist) => c.id ?? c.title ?? '';

  get subtitle(): string {
    return 'Active onboarding checklists';
  }

  get panelMeta(): string {
    let n = this.filteredChecklists.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'active' : 'active'}`;
  }

  <template>
    <PageScaffold @title='Onboarding' @subtitle={{this.subtitle}}>
      <:actions>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='neutral'
            @appearance='outlined'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew OnboardingTemplate)}}
          >New template</Button>
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew OnboardingChecklist)}}
          >+ Add checklist</Button>
        {{/if}}
      </:actions>
      <:default>
        <div class='list-toolbar'>
          <SearchInput
            class='list-search'
            @value={{@tracker.onboardingSearch}}
            @placeholder='Search checklists…'
            @label='Search onboarding checklists'
            @onInput={{this.setOnboardingSearch}}
          />
          <FilterChips
            @options={{this.statusOptions}}
            @value={{@tracker.onboardingStatusFilter}}
            @onValueChange={{this.setOnboardingStatusFilter}}
            @label='Filter by status'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.onboardingView}}
            @onValueChange={{this.setOnboardingView}}
            @label='View'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='Checklists'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            {{#if (eq @tracker.onboardingView 'table')}}
              <DataTable
                @loading={{@tracker.onboardingChecklistsQuery.isLoading}}
                @columns={{this.columns}}
                @rows={{this.filteredChecklists}}
                @key={{this.rowKey}}
                @label='Onboarding checklists'
                @columnMenu={{false}}
              >
                <:empty>{{#if
                    @tracker.onboardingChecklistsQuery.isLoading
                  }}<LoadingState @label='Loading' />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No active onboarding checklists'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'status')}}
                    <StatusChip @value={{row.status}} />
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
                        @title='No active onboarding checklists'
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
