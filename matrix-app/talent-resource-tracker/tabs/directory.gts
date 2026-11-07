import type { ComponentLike } from '@glint/template';
import GlimmerComponent from '@glimmer/component';
import { EmployeeStatusField } from '../../hr/employee';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import {
  searchEntryWireQueryFromQuery,
  type RenderableSearchEntryLike,
  type SearchEntryWireQuery,
} from '@cardstack/runtime-common';
import { Employee } from '../../hr/employee';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import type { TrackerView } from '../talent-resource-tracker';
import {
  getComponent,
  ListToolbar,
  TrackerEmpty,
  TrackerPage,
  TrackerSection,
  type TrackerStat,
} from '../shared';
import { tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { Button } from '@cardstack/pretui/components/button';
import { toLocalDate } from '../dates';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class DirectoryTab extends GlimmerComponent<Signature> {
  // the status column renders the field's own format: dot + label
  StatusAtom = EmployeeStatusField.atom as unknown as ComponentLike<{
    Args: { model: string | undefined };
  }>;
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
    let t = this.args.tracker;
    if (t.isLoading) {
      return '—';
    }
    return `${this.headcount} people · ${this.onboarding} onboarding · ${this.onLeave} on leave this week.`;
  }

  // ── the mock's four stat cards ────────────────────────────────────────
  get headcount(): number {
    return this.args.tracker.employees.filter((e) => e.status !== 'offboarded')
      .length;
  }
  get onboarding(): number {
    return this.args.tracker.employees.filter((e) => e.status === 'onboarding')
      .length;
  }
  get onLeave(): number {
    let today = new Date();
    let weekEnd = new Date(today);
    weekEnd.setDate(today.getDate() + 7);
    return this.args.tracker.ptoRequests.filter(
      (r) =>
        r.status === 'approved' &&
        r.startDate &&
        r.endDate &&
        toLocalDate(r.startDate) <= weekEnd &&
        toLocalDate(r.endDate) >= today,
    ).length;
  }
  get stats(): TrackerStat[] {
    let t = this.args.tracker;
    let loading = t.isLoading;
    let ending = t.contractors.filter(
      (c) =>
        c.status === 'active' &&
        c.daysRemaining != null &&
        c.daysRemaining <= 30,
    ).length;
    return [
      {
        label: 'Headcount',
        dot: 'success',
        value: loading ? '—' : this.headcount,
        hint: 'excluding offboarded',
      },
      {
        label: 'Onboarding',
        dot: 'info',
        value: loading ? '—' : this.onboarding,
        hint: 'not yet active',
      },
      {
        label: 'On leave',
        dot: 'warning',
        value: loading ? '—' : this.onLeave,
        hint: 'this week',
      },
      {
        label: 'Contractors',
        value: loading ? '—' : t.contractors.length,
        hint: `${ending} end within 30 days`,
      },
    ];
  }

  // ── list view: DataTable, columns drop by the section's width ─────────
  @tracked tableWidth = 0;
  measureTable = modifier((el: HTMLElement) => {
    let ro = new ResizeObserver(([e]) => {
      this.tableWidth = e?.contentRect.width ?? 0;
    });
    ro.observe(el);
    return () => ro.disconnect();
  });
  columns: DataColumn<Employee>[] = [
    { key: 'name', label: 'Name' },
    { key: 'role', label: 'Role' },
    { key: 'dept', label: 'Dept', value: (e) => e.department ?? '' },
    { key: 'manager', label: 'Manager' },
    { key: 'start', label: 'Start', mono: true },
    { key: 'status', label: 'Status' },
  ];
  get visibleColumns(): string[] {
    let w = this.tableWidth;
    let keys = ['name'];
    if (w >= 520) keys.push('role');
    if (w >= 640) keys.push('dept');
    if (w >= 760) keys.push('manager');
    if (w >= 860) keys.push('start');
    keys.push('status');
    return keys;
  }
  get rows(): Employee[] {
    let t = this.args.tracker;
    let q = (t.directorySearch ?? '').trim().toLowerCase();
    let dept = t.directoryDept;
    return t.employees.filter(
      (e) =>
        (!dept || dept === 'all' || e.department === dept) &&
        (!q ||
          [e.name, e.role, e.department].some((v) =>
            v?.toLowerCase().includes(q),
          )),
    );
  }
  rowKey = (e: Employee) => e.id ?? e.name ?? '';
  startLabel = (e: Employee) =>
    e.startDate
      ? toLocalDate(e.startDate).toLocaleDateString('en-US', {
          month: 'short',
          day: 'numeric',
          year: 'numeric',
        })
      : '—';

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
    <TrackerPage
      @stats={{this.stats}}
      @group='People'
      @title='Directory'
      @subtitle={{this.subtitle}}
    >
      <:default>
        <ListToolbar
          @label='Employees'
          @searchValue={{@tracker.directorySearch}}
          @searchPlaceholder='Search employees…'
          @onSearch={{this.setDirectorySearch}}
          @filterLabel='Filter by department'
          @filterOptions={{this.deptOptions}}
          @filterValue={{@tracker.directoryDept}}
          @onFilter={{this.setDirectoryDept}}
          @viewOptions={{this.viewOptions}}
          @view={{@tracker.directoryView}}
          @onView={{this.setDirectoryView}}
          as |bar|
        >
          {{#if @tracker.canCreate}}
            <bar.Action
              @id='add-employee'
              @label='Add employee'
              @primary={{true}}
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew Employee}}
            />
          {{/if}}
        </ListToolbar>
        {{#if (eq @tracker.directoryView 'strip')}}
          <div {{this.measureTable}}>
            <TrackerSection @title='By name' @meta='{{this.rows.length}} shown'>
              <DataTable
                @loading={{@tracker.isLoading}}
                @columns={{this.columns}}
                @visibleColumns={{this.visibleColumns}}
                @rows={{this.rows}}
                @key={{this.rowKey}}
                @label='People'
                @columnMenu={{false}}
                @sortable={{false}}
                @striped={{false}}
                @flush={{true}}
                @size='xs'
              >
                <:empty>{{#if @tracker.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<TrackerEmpty>No employees match. Try another
                      department or clear the search.</TrackerEmpty>{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'name')}}
                    <Button
                      type='button'
                      @tone='neutral'
                      @appearance='plain'
                      @size='xs'
                      class='dir-person'
                      {{on 'click' (fn @tracker.openCard row)}}
                    >{{#let (getComponent row) as |Atom|}}{{#if Atom}}<Atom
                            @format='atom'
                            @displayContainer={{false}}
                          />{{/if}}{{/let}}</Button>
                  {{else if (eq col.key 'role')}}
                    <span class='dir-muted'>{{row.role}}</span>
                  {{else if (eq col.key 'manager')}}
                    {{#if row.manager}}
                      {{#let (getComponent row.manager) as |Atom|}}{{#if
                          Atom
                        }}<span class='dir-mgr'><Atom
                              @format='atom'
                              @displayContainer={{false}}
                            /></span>{{/if}}{{/let}}
                    {{else}}
                      <span class='dir-muted'>—</span>
                    {{/if}}
                  {{else if (eq col.key 'start')}}
                    <span class='dir-mono'>{{this.startLabel row}}</span>
                  {{else if (eq col.key 'status')}}
                    <this.StatusAtom @model={{row.status}} />
                  {{else}}
                    {{text}}
                  {{/if}}
                </:cell>
              </DataTable>
            </TrackerSection>
          </div>
        {{else}}
          {{#let (component @context.searchResultsComponent) as |Search|}}
            <Search
              @query={{this.searchQuery}}
              @mode='none'
              @displayContainer={{false}}
              as |results|
            >
              {{#if results.entries.length}}
                <ul class='directory'>
                  {{#each (this.asEntries results.entries) as |entry|}}
                    <li
                      class='tile'
                      role={{if @tracker.cardCrudFunctions.viewCard 'button'}}
                      tabindex={{if @tracker.cardCrudFunctions.viewCard '0'}}
                      {{on 'click' (fn @tracker.viewEntry entry.id)}}
                      {{on 'keydown' (fn @tracker.viewEntryOnKeydown entry.id)}}
                    ><entry.component /></li>
                  {{/each}}
                </ul>
              {{else}}
                {{#if results.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<TrackerEmpty>No employees match. Try another
                    department or clear the search.</TrackerEmpty>{{/if}}
              {{/if}}
            </Search>
          {{/let}}
        {{/if}}
      </:default>
    </TrackerPage>
    <style scoped>
      /* Grid: the Employee card's fitted tile, 210px columns, 8px gap */
      .directory {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(13.125rem, 1fr));
        grid-auto-rows: 4.0625rem;
        gap: var(--trt-gap);
        margin: 0;
        padding: 0;
        list-style: none;
      }
      .tile {
        overflow: hidden;
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: var(--radius);
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 0.125rem;
      }
      @media (hover: hover) {
        .tile:hover {
          border-color: var(--border-strong);
        }
      }
      .dir-person {
        --pretui-button-h: 0;
        --pretui-button-px: 0;
      }
      .dir-muted {
        color: var(--muted-foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .dir-mgr {
        font-weight: 500;
      }
      .dir-mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
    </style>
  </template>
}
