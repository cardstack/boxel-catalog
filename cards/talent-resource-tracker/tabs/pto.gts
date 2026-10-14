import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import TableIcon from '@cardstack/boxel-icons/table';
import { htmlSafe } from '@ember/template';
import { Employee } from '../../hr/employee';
import {
  PtoRequest,
  PTO_STATUSES,
  PTO_STATUS_COLORS,
  PTO_TYPE_COLORS,
} from '../../hr/pto-request';
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

export class PtoTab extends GlimmerComponent<Signature> {
  setPtoView = (view: 'grid' | 'strip' | 'table') => {
    this.args.tracker.ptoView = view;
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
        let aT = a.requestedDate ? new Date(a.requestedDate).getTime() : 0;
        let bT = b.requestedDate ? new Date(b.requestedDate).getTime() : 0;
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
              new Date(r.startDate).getFullYear() === year,
          )
          .reduce((sum, r) => sum + (r.days ?? 0), 0);
        let allowance = employee.ptoAllowanceDays as number;
        return { employee, allowance, used, balance: allowance - used };
      })
      .sort((a, b) => a.balance - b.balance);
  }

  ptoTypeStyle = (ptoType: string | undefined) => {
    let color = stateColorOf(PTO_TYPE_COLORS, ptoType);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  ptoStatusStyle = (status: string | undefined) => {
    let color = stateColorOf(PTO_STATUS_COLORS, status);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  <template>
    <section class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>PTO Requests</h2>
          <p class='byline'>Time-off requests, newest first</p>
        </div>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            class='btn-review'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew PtoRequest)}}
          >+ Add request</Button>
        {{/if}}
      </div>
      {{#if this.ptoBalances.length}}
        <div class='capacity-row'>
          <span class='capacity-label'>Balance this year</span>
          {{#each this.ptoBalances key='employee.id' as |row|}}
            <span
              class='turn-chip
                {{if (eq row.balance 0) "turn-amber" "turn-green"}}'
            >
              {{row.employee.name}}
              {{row.balance}}d /
              {{row.allowance}}d
            </span>
          {{/each}}
        </div>
      {{/if}}
      <div class='list-toolbar'>
        <div class='list-search'>
          <Input
            @type='search'
            @value={{@tracker.ptoSearch}}
            @placeholder='Search PTO requests…'
            @onInput={{this.setPtoSearch}}
            aria-label='Search PTO requests'
          />
        </div>
        <div class='directory-chips'>
          <Button
            type='button'
            @tone='neutral'
            @appearance={{if
              (eq @tracker.ptoStatusFilter 'all')
              'filled'
              'outlined'
            }}
            class='chip {{if (eq @tracker.ptoStatusFilter "all") "active"}}'
            {{on 'click' (fn this.setPtoStatusFilter 'all')}}
          >All</Button>
          {{#each this.ptoStatuses as |status|}}
            <Button
              type='button'
              @tone='neutral'
              @appearance='outlined'
              class='chip {{if (eq @tracker.ptoStatusFilter status) "active"}}'
              {{on 'click' (fn this.setPtoStatusFilter status)}}
            >{{status}}</Button>
          {{/each}}
        </div>
        <div class='view-toggle' role='group' aria-label='View'>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.ptoView "grid") "active"}}'
            @label='Grid view'
            {{on 'click' (fn this.setPtoView 'grid')}}
          ><LayoutGridIcon class='view-icon' /></IconButton>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.ptoView "strip") "active"}}'
            @label='List view'
            {{on 'click' (fn this.setPtoView 'strip')}}
          ><ListIcon class='view-icon' /></IconButton>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.ptoView "table") "active"}}'
            @label='Table view'
            {{on 'click' (fn this.setPtoView 'table')}}
          ><TableIcon class='view-icon' /></IconButton>
        </div>
      </div>
      {{#if (eq @tracker.ptoView 'table')}}
        {{#if this.filteredPtoRequests.length}}
          <div class='data-table-wrap'>
            <table class='data-table'>
              <thead>
                <tr>
                  <th>Person</th>
                  <th>Type</th>
                  <th>Dates</th>
                  <th>Days</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {{#each this.filteredPtoRequests key='id' as |req|}}
                  <tr>
                    <td>{{if req.employeeName req.employeeName '—'}}</td>
                    <td>
                      {{#if req.ptoType}}
                        <span
                          class='status-pill'
                          style={{this.ptoTypeStyle req.ptoType}}
                        >{{req.ptoType}}</span>
                      {{else}}
                        —
                      {{/if}}
                    </td>
                    <td>{{@tracker.formatDate req.startDate}}
                      –
                      {{@tracker.formatDate req.endDate}}</td>
                    <td>{{if req.days req.days '—'}}</td>
                    <td>
                      <span
                        class='status-pill'
                        style={{this.ptoStatusStyle req.status}}
                      >{{req.status}}</span>
                    </td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          </div>
        {{else if @tracker.ptoRequestsQuery.isLoading}}
          <p class='empty-note'>Loading…</p>
        {{else}}
          <p class='empty-note'>No PTO requests yet</p>
        {{/if}}
      {{else}}
        {{#let (component @context.searchResultsComponent) as |Search|}}
          <Search @query={{@tracker.ptoSearchQuery}} @mode='none' as |results|>
            <div
              class='tile-grid
                {{if (eq @tracker.ptoView "strip") "strip-view"}}'
            >
              {{#each results.entries key='id' as |entry|}}
                <div
                  class='tile {{if (eq @tracker.ptoView "strip") "strip-tile"}}'
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
                  <p class='empty-note'>No PTO requests yet</p>
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
        border-bottom: 2px solid var(--card-foreground);
        margin: 0 0 var(--boxel-sp-lg);
      }
      .sec-head .htext {
        margin-right: auto;
      }
      .sec-head .htext h2 {
        font-family: var(--font-sans);
        font-weight: 700;
        font-size: 20px;
        margin: 0 0 3px;
      }
      .sec-head .htext .byline {
        font-family: var(--font-mono);
        font-size: 11.5px;
        letter-spacing: 0.02em;
        color: var(--muted-foreground);
        margin: 0;
      }
      .turn-chip {
        font-family: var(--font-mono);
        font-size: 0.625rem;
        font-weight: 700;
        letter-spacing: 0.02em;
        padding: 0.125rem 0.4375rem;
        border-radius: 999px;
      }
      .turn-amber {
        background: color-mix(in oklch, var(--warning) 14%, var(--card));
        color: color-mix(in oklch, var(--warning) 38%, var(--card-foreground));
      }
      .turn-green {
        background: color-mix(in oklch, var(--success) 14%, var(--card));
        color: color-mix(in oklch, var(--success) 38%, var(--card-foreground));
      }
      .capacity-row {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
        margin-bottom: var(--boxel-sp);
      }
      .capacity-label {
        font-family: var(--font-mono);
        font-size: 11px;
        color: var(--muted-foreground);
      }
      .btn-review {
        font-family: var(--font-mono);
        font-size: 11.5px;
        font-weight: 700;
      }
      .review-queue-item.on {
        background: var(--muted);
      }
      .stage-act:focus-visible,
      .screen-btn:focus-visible,
      .chip:focus-visible,
      .account-row:focus-visible,
      .rail-link:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
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
        font-size: 10px;
        margin-bottom: var(--boxel-sp-5xs);
      }
      .empty-note {
        margin: var(--boxel-sp-xs) 0 0;
        font-family: var(--font-mono);
        font-size: 12px;
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
        box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
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
        font-size: 11px;
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
        border-radius: 999px;
        font-size: 11px;
        text-transform: capitalize;
        white-space: nowrap;
      }
      .tile {
        border: 1px solid var(--border);
        border-radius: 1.25rem;
        overflow: hidden;

        height: 13.5rem;
        background: var(--card);
        box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
        transition:
          border-color 0.15s ease-out,
          box-shadow 0.15s ease-out;
      }
      .tile:hover {
        border-color: var(--primary);
        box-shadow: 0 2px 8px rgba(19, 19, 16, 0.08);
      }
      .tile:focus-within {
        border-color: var(--primary);
      }
      .tile[role='button'] {
        cursor: pointer;
      }
      .tile[role='button']:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
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
        font-family: var(--font-sans);
        font-size: 11.5px;
        font-weight: 600;
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
        border: none;
        border-radius: 0;
        transition:
          background-color 0.15s ease-out,
          color 0.15s ease-out;
      }
      .view-btn + .view-btn {
        border-left: 1px solid var(--border);
      }
      .view-btn:hover {
        --boxel-icon-button-color: var(--card-foreground);
      }
      .view-btn.active {
        --boxel-icon-button-background: var(--card-foreground);
        --boxel-icon-button-color: var(--card);
      }
      .view-icon {
        width: 1rem;
        height: 1rem;
      }
      .tab-section > .directory.grid-view {
        --item-width: auto;
        --item-height: 14rem;
        grid-template-columns: repeat(auto-fill, minmax(13rem, 1fr));
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
