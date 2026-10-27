import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  PerformanceReview,
  ReviewCycle,
  REVIEW_STATUSES,
} from '../../hr/performance-review';
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
import { StatusChip } from '../../../ui-component/components/status-chip';
import type { TrackerView } from '../talent-resource-tracker';
import { PanelHead } from '../shared';

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
    { key: 'cycle', label: 'Cycle', value: (r) => r.cycleName },
    { key: 'score', label: 'Score', value: (r) => r.scoreLabel },
    { key: 'status', label: 'Status' },
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
            @loading={{@tracker.addCard.isRunning}}
            {{on 'click' (fn @tracker.addNew ReviewCycle)}}
          >New cycle</Button>
          <Button
            type='button'
            @tone='primary'
            @appearance='accent'
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
            @onInput={{this.setReviewsSearch}}
          />
          <FilterChips
            @options={{this.statusOptions}}
            @value={{@tracker.reviewStatusFilter}}
            @onValueChange={{this.setReviewStatusFilter}}
            @label='Filter by status'
          />
          <SegmentedControl
            @options={{this.viewOptions}}
            @value={{@tracker.reviewsView}}
            @onValueChange={{this.setReviewsView}}
            @label='View'
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
                @label='Performance reviews'
                @columnMenu={{false}}
              >
                <:empty>{{#if @tracker.reviewsQuery.isLoading}}<LoadingState
                      @label='Loading'
                    />{{else}}<EmptyState
                      @size='s'
                      @texture={{false}}
                      @title='No performance reviews yet'
                    />{{/if}}</:empty>
                <:cell as |text row col|>
                  {{#if (eq col.key 'status')}}
                    <StatusChip @value={{row.status}} />
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
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
    </style>
  </template>
}
