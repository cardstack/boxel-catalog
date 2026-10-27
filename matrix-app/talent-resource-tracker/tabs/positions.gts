import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Button } from '../../../ui-component/components/button';
import {
  DataTable,
  type DataColumn,
} from '../../../ui-component/components/data-table';
import { EmptyState } from '../../../ui-component/components/empty-state';
import { LoadingState } from '../../../ui-component/components/loading-state';
import { Grid } from '../../../ui-component/components/grid';
import { PageScaffold } from '../../../ui-component/components/page-scaffold';
import { Panel } from '../../../ui-component/components/panel';
import { SearchInput } from '../../../ui-component/components/search-input';
import { SegmentedControl } from '../../../ui-component/components/segmented-control';
import { StatusChip } from '../../../ui-component/components/status-chip';
import { Position } from '../../hr/position';
import { daysBetween, toLocalDate } from '../dates';
import type { TrackerView } from '../talent-resource-tracker';
import { PanelHead } from '../shared';

interface PositionRow {
  position: Position;
  openDays: number | null;
  applicantCount: number;
  weeklyNew: number;
  interviewingCount: number;
  trendPoints: string;
  stalled: boolean;
  tone: 'red' | 'green' | 'mute';
}

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class PositionsTab extends GlimmerComponent<Signature> {
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  setPositionsView = (view: string) => {
    this.args.tracker.positionsView = view as 'grid' | 'strip' | 'table';
  };

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  get subtitle(): string {
    return 'Requisitions open across the org';
  }

  get panelMeta(): string {
    let n = this.args.tracker.positions.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'position' : 'positions'}`;
  }

  columns: DataColumn<PositionRow>[] = [
    { key: 'position', label: 'Position', value: (r) => r.position.jobTitle },
    {
      key: 'department',
      label: 'Department',
      value: (r) => r.position.department,
    },
    { key: 'openDays', label: 'Days open', align: 'end' },
    { key: 'applicantCount', label: 'Applicants', align: 'end' },
    { key: 'weeklyNew', label: 'This week', align: 'end' },
    { key: 'trend', label: '28-day trend', sortable: false },
    { key: 'interviewingCount', label: 'Interviewing', align: 'end' },
    { key: 'status', label: 'Status', value: (r) => r.position.status },
    { key: 'signal', label: 'Signal', sortable: false },
  ];

  rowKey = (r: PositionRow) => r.position.id ?? r.position.jobTitle ?? '';

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
  get positionsTableRows(): PositionRow[] {
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

  <template>
    <PageScaffold @title='Open Positions' @subtitle={{this.subtitle}}>
      <:actions>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew Position)}}
          >+ Add position</Button>
        {{/if}}
      </:actions>
      <:default>
        <div class='list-toolbar'>
          <SearchInput
            class='list-search'
            @value={{@tracker.positionsSearch}}
            @placeholder='Search positions…'
            @label='Search positions'
            @onInput={{this.setPositionsSearch}}
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.positionsView}}
            @onValueChange={{this.setPositionsView}}
            @label='View'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='Positions'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            {{#if (eq @tracker.positionsView 'table')}}
              <DataTable
                @loading={{@tracker.positionsQuery.isLoading}}
                @columns={{this.columns}}
                @rows={{this.positionsTableRows}}
                @key={{this.rowKey}}
                @label='Open positions'
                @columnMenu={{false}}
              >
                <:empty>{{#if @tracker.positionsQuery.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No open positions yet'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'applicantCount')}}
                    {{if @tracker.isLoading '—' row.applicantCount}}
                  {{else if (eq col.key 'interviewingCount')}}
                    {{if @tracker.isLoading '—' row.interviewingCount}}
                  {{else if (eq col.key 'openDays')}}
                    {{if row.openDays row.openDays '—'}}
                  {{else if (eq col.key 'trend')}}
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
                  {{else if (eq col.key 'status')}}
                    <StatusChip @value={{row.position.status}} />
                  {{else if (eq col.key 'signal')}}
                    {{#if row.stalled}}
                      <StatusChip @value='Stalled' @tone='danger' />
                    {{else if (eq row.position.status 'open')}}
                      <StatusChip @value='Healthy' @tone='success' />
                    {{/if}}
                  {{else}}
                    {{text}}
                  {{/if}}
                </:cell>
              </DataTable>
            {{else}}
              {{#let (component @context.searchResultsComponent) as |Search|}}
                <Search
                  @query={{@tracker.positionsSearchQuery}}
                  @mode='none'
                  as |results|
                >
                  {{#if results.entries.length}}
                    <Grid
                      @items={{this.asEntries results.entries}}
                      @size={{if
                        (eq @tracker.positionsView 'strip')
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
                        @title='No open positions yet'
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
      .trend {
        stroke: var(--muted-foreground);
      }
      .trend-red {
        stroke: var(--destructive);
      }
      .trend-green {
        stroke: var(--success);
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
    </style>
  </template>
}
