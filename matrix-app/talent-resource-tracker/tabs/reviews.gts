import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  PerformanceReview,
  ReviewCycle,
  REVIEW_STATUSES,
  cycleShort,
  statusLabel,
  statusTone,
} from '../../hr/performance-review';
import { Avatar } from '../../../ui-component/components/avatar';
import { AVATAR_HUE } from '@cardstack/catalog/components/pretui-helpers';
import { Chip } from '../../../ui-component/components/chip';
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
import type { TrackerView } from '../talent-resource-tracker';
import { PanelHead, RowOpen } from '../shared';

const HYPHEN_RE = /-/g;

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class ReviewsTab extends GlimmerComponent<Signature> {
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  setReviewsView = (view: string) => {
    this.args.tracker.reviewsView = view as 'grid' | 'strip' | 'table';
  };

  setReviewsSearch = (value: string) => {
    this.args.tracker.debouncedSetReviewsSearch(value);
  };

  reviewStatuses = REVIEW_STATUSES;

  setReviewStatusFilter = (status: string) => {
    this.args.tracker.reviewStatusFilter = status;
  };

  get filteredReviews(): PerformanceReview[] {
    let q = this.args.tracker.reviewsSearch.trim().toLowerCase();
    return this.args.tracker.performanceReviews
      .filter((review) => {
        let statusOk =
          this.args.tracker.reviewStatusFilter === 'all' ||
          (review.status ?? 'draft') === this.args.tracker.reviewStatusFilter;
        let textOk =
          !q ||
          review.employeeName?.toLowerCase().includes(q) ||
          review.cycleName?.toLowerCase().includes(q);
        return statusOk && Boolean(textOk);
      })
      .sort((a, b) =>
        (a.employeeName ?? '').localeCompare(b.employeeName ?? ''),
      );
  }

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  // The table spells the hyphen as a space ("Signed Off"); cards keep it.
  statusText = (status?: string | null) =>
    statusLabel(status).replace(HYPHEN_RE, ' ');

  statusOptions = [
    { value: 'all', label: 'All' },
    ...REVIEW_STATUSES.map((value) => ({
      value,
      label: (value.charAt(0).toUpperCase() + value.slice(1)).replace(
        HYPHEN_RE,
        ' ',
      ),
    })),
  ];

  columns: DataColumn<PerformanceReview>[] = [
    { key: 'person', label: 'Person', value: (r) => r.employeeName },
    { key: 'cycle', label: 'Cycle', value: (r) => cycleShort(r.cycleName) },
    {
      key: 'score',
      label: 'Score',
      align: 'end',
      value: (r) => r.scorecard?.averageScore,
    },
    { key: 'status', label: 'Status', value: (r) => r.status },
  ];

  rowKey = (r: PerformanceReview) => r.id ?? '';

  get subtitle(): string {
    return 'Review records by sign-off status';
  }

  get panelMeta(): string {
    let n = this.filteredReviews.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'review' : 'reviews'}`;
  }

  <template>
    <PageScaffold @title='Performance Reviews' @subtitle={{this.subtitle}}>
      <:actions>
        {{#if @tracker.canCreate}}
          <Button
            type='button'
            @tone='neutral'
            @appearance='outlined'
            @shape='pill'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew ReviewCycle)}}
          >New cycle</Button>
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
            @shape='pill'
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew PerformanceReview)}}
          >+ Add review</Button>
        {{/if}}
      </:actions>
      <:default>
        <div class='list-toolbar'>
          <SearchInput
            class='list-search'
            @value={{@tracker.reviewsSearch}}
            @placeholder='Search reviews by person…'
            @label='Search performance reviews'
            @size='s'
            @onInput={{this.setReviewsSearch}}
          />
          <FilterChips
            @options={{this.statusOptions}}
            @value={{@tracker.reviewStatusFilter}}
            @onValueChange={{this.setReviewStatusFilter}}
            @label='Filter by status'
            @size='s'
            @appearance='solid'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.reviewsView}}
            @onValueChange={{this.setReviewsView}}
            @label='View'
            @size='s'
            @appearance='tinted'
            class='list-view'
          />
        </div>
        <Panel>
          <:header><PanelHead
              @title='Reviews'
              @meta={{this.panelMeta}}
            /></:header>
          <:default>
            {{#if (eq @tracker.reviewsView 'table')}}
              <DataTable
                @loading={{@tracker.reviewsQuery.isLoading}}
                @columns={{this.columns}}
                @rows={{this.filteredReviews}}
                @key={{this.rowKey}}
                @onRowActivate={{@tracker.openRowCard}}
                @label='Performance reviews'
                @columnMenu={{false}}
                @sortable={{false}}
                @striped={{false}}
                @flush={{true}}
              >
                <:empty>{{#if @tracker.reviewsQuery.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No performance reviews yet'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'person')}}
                    <RowOpen @onOpen={{fn @tracker.openRowCard row}}><span
                        class='person'
                      >
                        <Avatar
                          @name={{if text text '?'}}
                          @src={{row.employee.photo.resolvedUrl}}
                          @hue={{AVATAR_HUE}}
                          @size={{40}}
                          aria-hidden='true'
                        />
                        {{if text text '—'}}
                      </span></RowOpen>
                  {{else if (eq col.key 'status')}}
                    <Chip
                      @tone={{statusTone row.status}}
                      @appearance='soft'
                      @shape='pill'
                      @dot={{false}}
                    >{{this.statusText row.status}}</Chip>
                  {{else}}
                    {{if text text '—'}}
                  {{/if}}
                </:cell>
              </DataTable>
            {{else}}
              {{#let (component @context.searchResultsComponent) as |Search|}}
                <Search
                  @query={{@tracker.reviewsSearchQuery}}
                  @mode='none'
                  as |results|
                >
                  {{#if results.entries.length}}
                    <Grid
                      @items={{this.asEntries results.entries}}
                      @size={{if
                        (eq @tracker.reviewsView 'strip')
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
                        @title='No performance reviews yet'
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
        flex: 1 1 auto;
        min-width: 12rem;
        max-width: 22.5rem;
      }
      /* one radius family across the row: search, chips and toggle are pills */
      .list-view {
        --pretui-seg-radius: var(--boxel-border-radius-pill);
      }
      .person {
        --pretui-avatar-font-size: var(--boxel-font-size-xs);
        display: inline-flex;
        vertical-align: middle;
        align-items: center;
        gap: var(--boxel-sp-sm);
      }
      .list-toolbar > :last-child {
        margin-left: auto;
      }
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
    </style>
  </template>
}
