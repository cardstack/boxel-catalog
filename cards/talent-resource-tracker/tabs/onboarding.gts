import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import TableIcon from '@cardstack/boxel-icons/table';
import { htmlSafe } from '@ember/template';
import {
  OnboardingChecklist,
  ONBOARDING_CHECKLIST_STATUSES,
  ONBOARDING_CHECKLIST_STATUS_COLORS,
} from '../../hr/onboarding-checklist';
import { OnboardingTemplate } from '../../hr/onboarding-template';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Input } from '@cardstack/pretui/components/input';
import { stateColorOf } from '../../../components/state-pill';
import type { TrackerView } from '../talent-resource-tracker';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class OnboardingTab extends GlimmerComponent<Signature> {
  setOnboardingView = (view: 'grid' | 'strip' | 'table') => {
    this.args.tracker.onboardingView = view;
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

  checklistStatusStyle = (status: string | undefined) => {
    let color = stateColorOf(ONBOARDING_CHECKLIST_STATUS_COLORS, status);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  completedTaskCount = (checklist: OnboardingChecklist): number => {
    let tasks = checklist.tasks ?? [];
    return tasks.filter((t) => t && t.status === 'complete').length;
  };

  <template>
    <section class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Onboarding</h2>
          <p class='byline'>Active onboarding checklists</p>
        </div>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            class='btn-review'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew OnboardingChecklist)}}
          >+ Add checklist</Button>
          <Button
            type='button'
            @tone='neutral'
            @appearance='filled'
            class='btn-review-exit'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew OnboardingTemplate)}}
          >New template</Button>
        {{/if}}
      </div>
      <div class='list-toolbar'>
        <div class='list-search'>
          <Input
            @type='search'
            @value={{@tracker.onboardingSearch}}
            @placeholder='Search checklists…'
            @onInput={{this.setOnboardingSearch}}
            aria-label='Search onboarding checklists'
          />
        </div>
        <div class='directory-chips'>
          <Button
            type='button'
            @tone='neutral'
            @appearance='outlined'
            class='chip
              {{if (eq @tracker.onboardingStatusFilter "all") "active"}}'
            {{on 'click' (fn this.setOnboardingStatusFilter 'all')}}
          >Active</Button>
          {{#each this.onboardingStatuses as |status|}}
            <Button
              type='button'
              @tone='neutral'
              @appearance='outlined'
              class='chip
                {{if (eq @tracker.onboardingStatusFilter status) "active"}}'
              {{on 'click' (fn this.setOnboardingStatusFilter status)}}
            >{{status}}</Button>
          {{/each}}
        </div>
        <div class='view-toggle' role='group' aria-label='View'>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.onboardingView "grid") "active"}}'
            @label='Grid view'
            {{on 'click' (fn this.setOnboardingView 'grid')}}
          ><LayoutGridIcon
              class='view-icon'
              width='16'
              height='16'
            /></IconButton>
          <IconButton
            type='button'
            class='view-btn
              {{if (eq @tracker.onboardingView "strip") "active"}}'
            @label='List view'
            {{on 'click' (fn this.setOnboardingView 'strip')}}
          ><ListIcon class='view-icon' width='16' height='16' /></IconButton>
          <IconButton
            type='button'
            class='view-btn
              {{if (eq @tracker.onboardingView "table") "active"}}'
            @label='Table view'
            {{on 'click' (fn this.setOnboardingView 'table')}}
          ><TableIcon class='view-icon' width='16' height='16' /></IconButton>
        </div>
      </div>
      {{#if (eq @tracker.onboardingView 'table')}}
        {{#if this.filteredChecklists.length}}
          <div class='data-table-wrap'>
            <table class='data-table'>
              <thead>
                <tr>
                  <th>Person</th>
                  <th>Status</th>
                  <th>Progress</th>
                  <th>Started</th>
                </tr>
              </thead>
              <tbody>
                {{#each this.filteredChecklists as |checklist|}}
                  <tr>
                    <td>{{if
                        checklist.personName
                        checklist.personName
                        checklist.title
                      }}</td>
                    <td>
                      <span
                        class='status-pill'
                        style={{this.checklistStatusStyle checklist.status}}
                      >{{checklist.status}}</span>
                    </td>
                    <td>{{this.completedTaskCount
                        checklist
                      }}/{{checklist.tasks.length}}
                      tasks</td>
                    <td>{{@tracker.formatDate checklist.createdDate}}</td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          </div>
        {{else if @tracker.onboardingChecklistsQuery.isLoading}}
          <p class='empty-note'>Loading…</p>
        {{else}}
          <p class='empty-note'>No active onboarding checklists</p>
        {{/if}}
      {{else}}
        {{#let (component @context.searchResultsComponent) as |Search|}}
          <Search
            @query={{@tracker.onboardingSearchQuery}}
            @mode='none'
            as |results|
          >
            <div
              class='tile-grid
                {{if (eq @tracker.onboardingView "strip") "strip-view"}}'
            >
              {{#each results.entries key='id' as |entry|}}
                <div
                  class='tile
                    {{if (eq @tracker.onboardingView "strip") "strip-tile"}}'
                  role={{if @tracker.cardCrudFunctions.viewCard 'button'}}
                  tabindex={{if @tracker.cardCrudFunctions.viewCard '0'}}
                  {{on 'click' (fn @tracker.viewEntry entry.id)}}
                  {{on 'keydown' (fn @tracker.viewEntryOnKeydown entry.id)}}
                >
                  <entry.component />
                </div>
              {{else}}
                {{#if results.isLoading}}
                  <p class='empty-note'>Loading…</p>
                {{else}}
                  <p class='empty-note'>No active onboarding checklists</p>
                {{/if}}
              {{/each}}
            </div>
          </Search>
        {{/let}}
      {{/if}}
    </section>
    <style scoped>
      .sec-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp);
        padding-bottom: var(--boxel-sp);
        border-bottom: 0.125rem solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 1.25rem;
        margin: 0 0 0.1875rem;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 0.7188rem;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .chip:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      .tab-section {
        animation: tracker-tab-fade-in 0.2s ease-out;
      }
      @keyframes tracker-tab-fade-in {
        from {
          opacity: 0;
        }
        to {
          opacity: 1;
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .tab-section {
          animation: none;
        }
      }
      .data-table {
        margin-top: 0;
      }
      .btn-review {
        margin-bottom: var(--boxel-sp-5xs);
      }
      .empty-note {
        margin: var(--boxel-sp-xs) 0 0;
        font-family: var(--font-mono);
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .tile-grid {
        margin-top: var(--boxel-sp);
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr));
        gap: var(--boxel-sp);
      }
      .data-table-wrap {
        margin-top: var(--boxel-sp);
        overflow-x: auto;
        border: 1px solid var(--border);
        border-radius: 1rem;
        background: var(--card);
        box-shadow: 0 0.0625rem 0.125rem rgba(15, 23, 42, 0.04);
      }
      .data-table {
        width: 100%;
        border-collapse: collapse;
        font-size: var(--boxel-font-size-sm);
      }
      .data-table th {
        text-align: left;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: var(--muted-foreground);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      .data-table td {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      .data-table tbody tr:last-child td {
        border-bottom: none;
      }
      .data-table tbody tr:hover {
        background: var(--muted);
      }
      .status-pill {
        display: inline-block;
        padding: 0.125rem 0.5rem;
        border-radius: 62.4375rem;
        font-size: 0.6875rem;
        text-transform: capitalize;
        white-space: nowrap;
      }
      .tile {
        border: 1px solid var(--border);
        border-radius: 1.25rem;
        overflow: hidden;

        height: 13.5rem;
        background: var(--card);
        box-shadow: 0 0.0625rem 0.125rem rgba(15, 23, 42, 0.04);
        transition:
          border-color 0.15s ease-out,
          box-shadow 0.15s ease-out;
      }
      .tile:hover {
        border-color: var(--primary-ink);
        box-shadow: 0 0.125rem 0.5rem rgba(19, 19, 16, 0.08);
      }
      .tile:focus-within {
        border-color: var(--primary-ink);
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
      .tile-grid.strip-view {
        grid-template-columns: repeat(auto-fill, minmax(20rem, 1fr));
        gap: var(--boxel-sp-xs);
      }
      .tile.strip-tile {
        height: 4rem;
      }
      .directory-chips {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
      }
      .chip {
        text-transform: capitalize;
        transition:
          background-color 0.15s ease-out,
          color 0.15s ease-out,
          border-color 0.15s ease-out;
      }
      .list-toolbar {
        margin-top: var(--boxel-sp-lg);
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp);
        margin-bottom: var(--boxel-sp);
      }
      .list-search {
        flex: 1;
        min-width: 12rem;
        max-width: 20rem;
      }
      .view-toggle {
        display: flex;
        margin-left: auto;
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
        overflow: hidden;
        flex: none;
      }
      .view-btn {
        --boxel-icon-button-width: 2rem;
        --boxel-icon-button-height: 2rem;
        --boxel-icon-button-background: var(--card);
        --boxel-icon-button-color: var(--muted-foreground);
        transition:
          background-color 0.15s ease-out,
          color 0.15s ease-out;
      }
      .view-btn:hover {
        --boxel-icon-button-color: var(--card-foreground);
      }
      .view-btn.active {
        --boxel-icon-button-background: var(--card-foreground);
        --boxel-icon-button-color: var(--card);
      }
      .sec-head {
        flex: none;
      }
      @keyframes action-busy-pulse {
        0%,
        100% {
          opacity: 1;
        }
        50% {
          opacity: 0.55;
        }
      }
    </style>
  </template>
}
