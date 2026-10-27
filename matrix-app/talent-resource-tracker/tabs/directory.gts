import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Employee } from '../../hr/employee';
import CardList from '@cardstack/base/components/card-list';
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
            @onInput={{this.setDirectorySearch}}
          />
          <FilterChips
            @options={{this.deptOptions}}
            @value={{@tracker.directoryDept}}
            @onValueChange={{this.setDirectoryDept}}
            @label='Filter by department'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.directoryView}}
            @onValueChange={{this.setDirectoryView}}
            @label='View'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='People'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            <CardList
              class='directory'
              @query={{@tracker.employeeQuery}}
              @realms={{@tracker.realms}}
              @context={{@context}}
              @format='fitted'
              @viewOption={{@tracker.directoryView}}
            />
          </:default>
        </Panel>
      </:default>
    </PageScaffold>
    <style scoped>
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
      .directory {
        --embedded-card-min-height: 4.0625rem;
      }
    </style>
  </template>
}
