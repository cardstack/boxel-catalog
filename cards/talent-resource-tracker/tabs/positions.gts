import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import TableIcon from '@cardstack/boxel-icons/table';
import { htmlSafe } from '@ember/template';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Input } from '@cardstack/pretui/components/input';
import { Position, POSITION_STATUS_HUES } from '../../hr/position';
import { stateColorsOf } from '../../hr/hr-ui';

const POSITION_STATUS_COLORS = stateColorsOf(POSITION_STATUS_HUES);
import { daysBetween, toLocalDate } from '../dates';
import { stateColorOf } from '../../../components/state-pill';
import type { TrackerView } from '../talent-resource-tracker';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class PositionsTab extends GlimmerComponent<Signature> {
  setPositionsView = (view: 'grid' | 'strip' | 'table') => {
    this.args.tracker.positionsView = view;
  };

  setPositionsSearch = (value: string) => {
    this.args.tracker.debouncedSetPositionsSearch(value);
  };

  get filteredPositions(): { item: Position; index: number }[] {
    let q = this.args.tracker.positionsSearch.trim().toLowerCase();
    return this.args.tracker.positions
      .map((item, index) => ({ item, index }))
      .filter(
        ({ item }) =>
          !q ||
          item.title?.toLowerCase().includes(q) ||
          item.department?.toLowerCase().includes(q),
      );
  }

  // Positions need horizontal comparison, not a card grid — which is open
  // longest, which has gone quiet. "Stalled" is computed, not a status
  // anyone sets by hand: open 30+ days with zero new applicants this week.
  get positionsTableRows(): Array<{
    position: Position;
    openDays: number | null;
    applicantCount: number;
    weeklyNew: number;
    interviewingCount: number;
    trendPoints: string;
    stalled: boolean;
    tone: 'red' | 'green' | 'mute';
  }> {
    let now = new Date();
    return this.args.tracker.positions.map((position) => {
      let apps = this.args.tracker.applications.filter(
        (a) => a.position?.id === position.id,
      );
      let openDays = position.postedDate
        ? daysBetween(toLocalDate(position.postedDate), now)
        : null;
      let weeklyNew = apps.filter(
        (a) =>
          a.appliedDate &&
          (daysBetween(toLocalDate(a.appliedDate), now) ?? 99) <= 7,
      ).length;
      let interviewingCount = this.args.tracker.candidates.filter(
        (c) => c.position?.id === position.id && c.status === 'interviewing',
      ).length;
      let buckets = [0, 0, 0, 0];
      for (let a of apps) {
        if (!a.appliedDate) continue;
        let age = daysBetween(toLocalDate(a.appliedDate), now);
        if (age == null || age < 0 || age > 28) continue;
        buckets[3 - Math.min(3, Math.floor(age / 7))] += 1;
      }
      let maxBucket = Math.max(1, ...buckets);
      let trendPoints = buckets
        .map((v, i) => {
          let x = Math.round((i / (buckets.length - 1)) * 76) + 2;
          let y = 18 - Math.round((v / maxBucket) * 14);
          return `${x},${y}`;
        })
        .join(' ');
      let stalled =
        position.status === 'open' && (openDays ?? 0) >= 30 && weeklyNew === 0;
      let tone: 'red' | 'green' | 'mute' =
        position.status !== 'open' ? 'mute' : stalled ? 'red' : 'green';
      return {
        position,
        openDays: openDays ?? null,
        applicantCount: apps.length,
        weeklyNew,
        interviewingCount,
        trendPoints,
        stalled,
        tone,
      };
    });
  }

  positionStatusStyle = (status: string | undefined) => {
    let color = stateColorOf(POSITION_STATUS_COLORS, status);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  <template>
    <div class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Open Positions</h2>
          <p class='byline'>Requisitions open across the org</p>
        </div>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            class='btn-review'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Position)}}
          >+ Add position</Button>
        {{/if}}
      </div>
      <div class='list-toolbar'>
        <div class='list-search'>
          <Input
            @type='search'
            @value={{@tracker.positionsSearch}}
            @placeholder='Search positions…'
            @onInput={{this.setPositionsSearch}}
            aria-label='Search positions'
          />
        </div>
        <div class='view-toggle' role='group' aria-label='View'>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.positionsView "grid") "active"}}'
            @label='Grid view'
            {{on 'click' (fn this.setPositionsView 'grid')}}
          ><LayoutGridIcon
              class='view-icon'
              width='16'
              height='16'
            /></IconButton>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.positionsView "strip") "active"}}'
            @label='List view'
            {{on 'click' (fn this.setPositionsView 'strip')}}
          ><ListIcon class='view-icon' width='16' height='16' /></IconButton>
          <IconButton
            type='button'
            class='view-btn {{if (eq @tracker.positionsView "table") "active"}}'
            @label='Table view'
            {{on 'click' (fn this.setPositionsView 'table')}}
          ><TableIcon class='view-icon' width='16' height='16' /></IconButton>
        </div>
      </div>
      {{#if (eq @tracker.positionsView 'table')}}
        {{#if this.filteredPositions.length}}
          <div class='data-table-wrap'>
            <table class='data-table'>
              <thead>
                <tr>
                  <th>Position</th>
                  <th>Department</th>
                  <th>Days Open</th>
                  <th>Applicants</th>
                  <th>This Week</th>
                  <th>28-Day Trend</th>
                  <th>Interviewing</th>
                  <th>Status</th>
                  <th>Signal</th>
                </tr>
              </thead>
              <tbody>
                {{#each this.positionsTableRows as |row|}}
                  <tr>
                    <td>{{row.position.jobTitle}}</td>
                    <td>{{row.position.department}}</td>
                    <td>{{if row.openDays row.openDays '—'}}</td>
                    <td>{{row.applicantCount}}</td>
                    <td>{{row.weeklyNew}}</td>
                    <td>
                      <svg
                        viewBox='0 0 80 20'
                        width='80'
                        height='20'
                        role='img'
                        aria-label='28-day applicant trend'
                      >
                        <polyline
                          points={{row.trendPoints}}
                          fill='none'
                          class='trend trend-{{row.tone}}'
                          stroke-width='1.6'
                        />
                      </svg>
                    </td>
                    <td>{{row.interviewingCount}}</td>
                    <td>
                      <span
                        class='status-pill'
                        style={{this.positionStatusStyle row.position.status}}
                      >{{row.position.status}}</span>
                    </td>
                    <td>
                      {{#if row.stalled}}
                        <span class='status-pill pill-red'>Stalled</span>
                      {{else if (eq row.position.status 'open')}}
                        <span class='status-pill pill-green'>Healthy</span>
                      {{/if}}
                    </td>
                  </tr>
                {{/each}}
              </tbody>
            </table>
          </div>
        {{else if @tracker.positionsQuery.isLoading}}
          <p class='empty-note'>Loading…</p>
        {{else}}
          <p class='empty-note'>No open positions yet</p>
        {{/if}}
      {{else}}
        {{#let (component @context.searchResultsComponent) as |Search|}}
          <Search
            @query={{@tracker.positionsSearchQuery}}
            @mode='none'
            as |results|
          >
            <div
              class='tile-grid
                {{if (eq @tracker.positionsView "strip") "strip-view"}}'
            >
              {{#each results.entries key='id' as |entry|}}
                <div
                  class='tile
                    {{if (eq @tracker.positionsView "strip") "strip-tile"}}'
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
                  <p class='empty-note'>No open positions yet</p>
                {{/if}}
              {{/each}}
            </div>
          </Search>
        {{/let}}
      {{/if}}
    </div>
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
      .pill-red {
        background: color-mix(in oklch, var(--destructive) 14%, var(--card));
        color: color-mix(
          in oklch,
          var(--destructive) 38%,
          var(--card-foreground)
        );
      }
      .pill-green {
        background: color-mix(in oklch, var(--success) 14%, var(--card));
        color: color-mix(in oklch, var(--success) 38%, var(--card-foreground));
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
      .trend {
        stroke: var(--border);
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
