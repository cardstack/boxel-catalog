import type { ComponentLike } from '@glint/template';
import GlimmerComponent from '@glimmer/component';
import { PositionStatusField } from '../../hr/position';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Grid } from '@cardstack/pretui/components/grid';
import { Position } from '../../hr/position';
import { daysBetween, toLocalDate } from '../dates';
import type { TrackerView } from '../talent-resource-tracker';
import {
  ColumnFit,
  getComponent,
  TrackerSection,
  RowOpen,
  ListToolbar,
  TrackerEmpty,
  TrackerPage,
  StatusDot,
} from '../shared';

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
  // the status column renders the field's own format: dot + label
  StatusAtom = PositionStatusField.atom as unknown as ComponentLike<{
    Args: { model: string | undefined };
  }>;
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

  // Only the queries this tab counts from; one slow unrelated query must
  // not blank the whole table.
  get isLoading(): boolean {
    let t = this.args.tracker;
    return [t.positionsQuery, t.applicationsQuery, t.candidatesQuery].some(
      (q) => q?.isLoading,
    );
  }

  get panelMeta(): string {
    let n = this.args.tracker.positions.length;
    return this.isLoading ? '—' : `${n} ${n === 1 ? 'position' : 'positions'}`;
  }

  // rows wrap the card; the table hands back the wrapper

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

  fit = new ColumnFit();
  get visibleColumns(): string[] {
    return this.fit.pick(this.columns.map((c) => c.key));
  }
  get notTable(): boolean {
    return this.args.tracker.positionsView !== 'table';
  }

  <template>
    <TrackerPage
      @group='Hiring'
      @title='Open Positions'
      @subtitle={{this.subtitle}}
    >
      <:default>
        <ListToolbar
          @label='Positions'
          @searchValue={{@tracker.positionsSearch}}
          @searchPlaceholder='Search positions…'
          @onSearch={{this.setPositionsSearch}}
          @viewOptions={{this.viewOptions}}
          @view={{@tracker.positionsView}}
          @onView={{this.setPositionsView}}
          as |bar|
        >
          {{#if @tracker.canCreate}}
            <bar.Action
              @id='add-position'
              @label='Add position'
              @primary={{true}}
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew Position}}
            />
          {{/if}}
        </ListToolbar>
        <TrackerSection
          {{this.fit.measure}}
          @title='Positions'
          @meta={{this.panelMeta}}
          @padded={{this.notTable}}
        >
          {{#if (eq @tracker.positionsView 'table')}}
            <DataTable
              @visibleColumns={{this.visibleColumns}}
              @loading={{@tracker.positionsQuery.isLoading}}
              @columns={{this.columns}}
              @rows={{this.positionsTableRows}}
              @key={{this.rowKey}}
              @label='Open positions'
              @columnMenu={{false}}
              @sortable={{false}}
              @striped={{false}}
              @flush={{true}}
            >
              <:empty>{{#if @tracker.positionsQuery.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<TrackerEmpty>No open positions yet</TrackerEmpty>{{/if}}</:empty>
              <:cell as |text row col|>
                {{#if (eq col.key 'position')}}
                  <RowOpen
                    @onOpen={{fn @tracker.openRowCard row.position}}
                  >{{#let (getComponent row.position) as |Atom|}}{{#if
                        Atom
                      }}<Atom
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}{{if text text '—'}}{{/if}}{{/let}}</RowOpen>
                {{else if (eq col.key 'applicantCount')}}
                  {{if this.isLoading '—' row.applicantCount}}
                {{else if (eq col.key 'interviewingCount')}}
                  {{if this.isLoading '—' row.interviewingCount}}
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
                      stroke-linecap='round'
                      stroke-linejoin='round'
                      stroke-width='1.6'
                    />
                  </svg>
                {{else if (eq col.key 'status')}}
                  <this.StatusAtom @model={{row.position.status}} />
                {{else if (eq col.key 'signal')}}
                  {{#if row.stalled}}
                    <StatusDot @tone='danger' @label='Stalled' />
                  {{else if (eq row.position.status 'open')}}
                    <StatusDot @tone='success' @label='Healthy' />
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
                    />{{else}}<TrackerEmpty>No open positions yet</TrackerEmpty>{{/if}}
                {{/if}}
              </Search>
            {{/let}}
          {{/if}}
        </TrackerSection>
      </:default>
    </TrackerPage>
    <style scoped>
      /* the host's card container draws the frame and the hover ring;
         the tile adds only sizing, so there is one hover affordance */
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
      .trend {
        stroke: var(--primary);
      }
      .trend-red {
        stroke: var(--destructive);
      }
    </style>
  </template>
}
