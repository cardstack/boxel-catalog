import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import TableIcon from '@cardstack/boxel-icons/table';
import { htmlSafe } from '@ember/template';
import { JobRequisition } from '../../hr/job-requisition';
import {
  REQUISITION_STATUSES,
  REQUISITION_STATUS_COLORS,
} from '../../hr/requisition-field';
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

export class RequisitionsTab extends GlimmerComponent<Signature> {
  setRequisitionsView = (view: 'grid' | 'strip' | 'table') => {
    this.args.tracker.requisitionsView = view;
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

  requisitionsStatusStyle = (status: string | undefined) => {
    let color = stateColorOf(REQUISITION_STATUS_COLORS, status);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  <template>
    <section class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Requisitions</h2>
          <p class='byline'>Job openings by approval status</p>
        </div>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            class='btn-review'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew JobRequisition)}}
          >+ Add requisition</Button>
        {{/if}}
      </div>
      <div class='list-toolbar'>
        <div class='list-search'>
          <Input
            @type='search'
            @value={{@tracker.requisitionsSearch}}
            @placeholder='Search requisitions…'
            @onInput={{this.setRequisitionsSearch}}
            aria-label='Search requisitions'
          />
        </div>
        <div class='directory-chips'>
          <Button
            type='button'
            @tone='neutral'
            @appearance='outlined'
            class='chip
              {{if (eq @tracker.requisitionsStatusFilter "all") "active"}}'
            {{on 'click' (fn this.setRequisitionsStatusFilter 'all')}}
          >All</Button>
          {{#each this.requisitionsStatuses as |status|}}
            <Button
              type='button'
              @tone='neutral'
              @appearance='outlined'
              class='chip
                {{if (eq @tracker.requisitionsStatusFilter status) "active"}}'
              {{on 'click' (fn this.setRequisitionsStatusFilter status)}}
            >{{status}}</Button>
          {{/each}}
        </div>
        <div class='view-toggle' role='group' aria-label='View'>
          <IconButton
            type='button'
            class='view-btn'
            @variant={{if
              (eq @tracker.requisitionsView 'grid')
              'primary'
              'ghost'
            }}
            aria-pressed={{if
              (eq @tracker.requisitionsView 'grid')
              'true'
              'false'
            }}
            @label='Grid view'
            {{on 'click' (fn this.setRequisitionsView 'grid')}}
          ><LayoutGridIcon
              class='view-icon'
              width='16'
              height='16'
            /></IconButton>
          <IconButton
            type='button'
            class='view-btn'
            @variant={{if
              (eq @tracker.requisitionsView 'strip')
              'primary'
              'ghost'
            }}
            aria-pressed={{if
              (eq @tracker.requisitionsView 'strip')
              'true'
              'false'
            }}
            @label='List view'
            {{on 'click' (fn this.setRequisitionsView 'strip')}}
          ><ListIcon class='view-icon' width='16' height='16' /></IconButton>
          <IconButton
            type='button'
            class='view-btn'
            @variant={{if
              (eq @tracker.requisitionsView 'table')
              'primary'
              'ghost'
            }}
            aria-pressed={{if
              (eq @tracker.requisitionsView 'table')
              'true'
              'false'
            }}
            @label='Table view'
            {{on 'click' (fn this.setRequisitionsView 'table')}}
          ><TableIcon class='view-icon' width='16' height='16' /></IconButton>
        </div>
      </div>
      {{#if (eq @tracker.requisitionsView 'table')}}
        {{#if this.filteredRequisitions.length}}
          <div class='data-table-wrap'>
            <table class='data-table'>
              <thead>
                <tr>
                  <th>Title</th>
                  <th>Department</th>
                  <th>Headcount</th>
                  <th>Status</th>
                  <th>Target fill date</th>
                </tr>
              </thead>
              <tbody>
                {{#each this.filteredRequisitions as |req|}}
                  <tr>
                    <td>{{req.displayTitle}}</td>
                    <td>{{if req.department req.department '—'}}</td>
                    <td>{{if req.headcount req.headcount '—'}}</td>
                    <td>
                      <span
                        class='status-pill'
                        style={{this.requisitionsStatusStyle req.status}}
                      >{{req.status}}</span>
                    </td>
                    <td>{{@tracker.formatDate req.targetFillDate}}</td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          </div>
        {{else if @tracker.requisitionsQuery.isLoading}}
          <p class='empty-note' role='status'>Loading…</p>
        {{else}}
          <p class='empty-note' role='status'>No requisitions yet</p>
        {{/if}}
      {{else}}
        {{#let (component @context.searchResultsComponent) as |Search|}}
          <Search
            @query={{@tracker.requisitionsSearchQuery}}
            @mode='none'
            as |results|
          >
            <div
              class='tile-grid
                {{if (eq @tracker.requisitionsView "strip") "strip-view"}}'
            >
              {{#each results.entries key='id' as |entry|}}
                <div
                  class='tile
                    {{if (eq @tracker.requisitionsView "strip") "strip-tile"}}'
                  role={{if @tracker.cardCrudFunctions.viewCard 'button'}}
                  tabindex={{if @tracker.cardCrudFunctions.viewCard '0'}}
                  {{on 'click' (fn @tracker.viewEntry entry.id)}}
                  {{on 'keydown' (fn @tracker.viewEntryOnKeydown entry.id)}}
                >
                  <entry.component />
                </div>
              {{else}}
                {{#if results.isLoading}}
                  <p class='empty-note' role='status'>Loading…</p>
                {{else}}
                  <p class='empty-note' role='status'>No requisitions yet</p>
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
        box-shadow: var(--shadow-xs);
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
        box-shadow: var(--shadow-xs);
        transition:
          border-color 0.15s ease-out,
          box-shadow 0.15s ease-out;
      }
      .tile:hover {
        border-color: var(--primary-ink);
        box-shadow: var(--shadow-sm);
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
