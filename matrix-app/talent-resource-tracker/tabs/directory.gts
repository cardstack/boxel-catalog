import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import {
  searchEntryWireQueryFromQuery,
  type RenderableSearchEntryLike,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { Employee } from '../../hr/employee';
import { EmptyState } from '../../../ui-component/components/empty-state';
import { LoadingState } from '../../../ui-component/components/loading-state';
import { Button } from '../../../ui-component/components/button';
import { FilterChips } from '../../../ui-component/components/filter-chips';
import { PageScaffold } from '../../../ui-component/components/page-scaffold';
import { Panel } from '../../../ui-component/components/panel';
import { SearchInput } from '../../../ui-component/components/search-input';
import { SegmentedControl } from '../../../ui-component/components/segmented-control';
import type { TrackerView } from '../talent-resource-tracker';
import { PanelHead } from '../shared';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class DirectoryTab extends GlimmerComponent<Signature> {
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  get searchQuery(): SearchEntryWireQuery | undefined {
    let { realms, employeeQuery } = this.args.tracker;
    return realms.length
      ? { ...searchEntryWireQueryFromQuery(employeeQuery), realms }
      : undefined;
  }

  setDirectoryView = (view: string) => {
    this.args.tracker.directoryView = view as 'grid' | 'strip';
  };

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
  ];

  get deptOptions() {
    return [
      { value: 'all', label: 'All' },
      ...this.departments.map((d) => ({ value: d, label: d })),
    ];
  }

  get subtitle(): string {
    return 'Every standing entry, searchable';
  }

  get panelMeta(): string {
    let n = this.args.tracker.employees.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'person' : 'people'}`;
  }

  get departments(): string[] {
    let seen = new Set<string>();
    for (let employee of this.args.tracker.employees) {
      if (employee.department) {
        seen.add(employee.department);
      }
    }
    return [...seen].sort();
  }

  setDirectoryDept = (dept: string) => {
    this.args.tracker.directoryDept = dept;
  };

  setDirectorySearch = (value: string) => {
    this.args.tracker.debouncedSetDirectorySearch(value);
  };

  <template>
    <PageScaffold @title='Directory' @subtitle={{this.subtitle}}>
      <:actions>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Employee)}}
          >+ Add employee</Button>
        {{/if}}
      </:actions>
      <:default>
        <div class='directory-filters'>
          <SearchInput
            class='directory-search'
            @value={{@tracker.directorySearch}}
            @placeholder='Search employees…'
            @label='Search employees'
            @size='s'
            @onInput={{this.setDirectorySearch}}
          />
          <FilterChips
            @options={{this.deptOptions}}
            @value={{@tracker.directoryDept}}
            @onValueChange={{this.setDirectoryDept}}
            @label='Filter by department'
            @size='s'
            @appearance='solid'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.directoryView}}
            @onValueChange={{this.setDirectoryView}}
            @label='View'
            @size='s'
            @appearance='tinted'
            class='directory-view'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='People'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            {{#let (component @context.searchResultsComponent) as |Search|}}
              <Search
                @query={{this.searchQuery}}
                @mode='none'
                @displayContainer={{false}}
                as |results|
              >
                {{#if results.entries.length}}
                  <ul class='directory' data-view={{@tracker.directoryView}}>
                    {{#each (this.asEntries results.entries) as |entry|}}
                      <li
                        class='tile'
                        role={{if @tracker.cardCrudFunctions.viewCard 'button'}}
                        tabindex={{if @tracker.cardCrudFunctions.viewCard '0'}}
                        {{on 'click' (fn @tracker.viewEntry entry.id)}}
                        {{on
                          'keydown'
                          (fn @tracker.viewEntryOnKeydown entry.id)
                        }}
                      ><entry.component /></li>
                    {{/each}}
                  </ul>
                {{else}}
                  {{#if results.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No employees match'
                      @message='Try another department or clear the search.'
                    />{{/if}}
                {{/if}}
              </Search>
            {{/let}}
          </:default>
        </Panel>
      </:default>
    </PageScaffold>
    <style scoped>
      /* one radius family across the row: the search is a pill */
      .directory-view {
        --pretui-seg-radius: var(--boxel-border-radius-pill);
      }
      .directory-filters > :last-child {
        margin-left: auto;
      }
      .directory-filters {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .directory-search {
        flex: 1;
        min-width: 12rem;
        max-width: 20rem;
      }
      /* The mockup's tile grid: columns from 12.5rem, one fixed row
         height so every tile is the same fitted size (the Employee card's
         directory tile; a role on two lines still fits). */
      .directory {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(12.5rem, 1fr));
        grid-auto-rows: 8.75rem;
        gap: var(--boxel-sp);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .directory[data-view='strip'] {
        grid-template-columns: minmax(0, 1fr);
        grid-auto-rows: 4.0625rem;
        gap: var(--boxel-sp-xs);
      }
      /* The list frames each result itself (the search renders them without
         their container): the panel's white tile, its shadow, no border. */
      .tile {
        overflow: hidden;
        border-radius: var(--radius);
        background-color: var(--card);
        color: var(--card-foreground);
        box-shadow: var(--shadow-md);
        transition: box-shadow 0.15s ease-out;
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      @media (hover: hover) {
        /* a ring, not a border: a border would take 2px from the fitted
           card and drop it into the next smaller size tier */
        .tile:hover {
          box-shadow:
            0 0 0 1px var(--border),
            var(--shadow-sm);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
    </style>
  </template>
}
