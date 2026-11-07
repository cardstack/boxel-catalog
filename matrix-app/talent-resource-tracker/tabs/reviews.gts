import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import {
  PerformanceReview,
  ReviewCycle,
  REVIEW_STATUSES,
  cycleShort,
  statusLabel,
  statusTone,
} from '../../hr/performance-review';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Grid } from '@cardstack/pretui/components/grid';
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

  fit = new ColumnFit();
  get visibleColumns(): string[] {
    return this.fit.pick(this.columns.map((c) => c.key));
  }
  get notTable(): boolean {
    return this.args.tracker.reviewsView !== 'table';
  }

  <template>
    <TrackerPage
      @group='People'
      @title='Performance Reviews'
      @subtitle={{this.subtitle}}
    >
      <:default>
        <ListToolbar
          @label='Performance reviews'
          @searchValue={{@tracker.reviewsSearch}}
          @searchPlaceholder='Search reviews by person…'
          @onSearch={{this.setReviewsSearch}}
          @filterLabel='Filter by status'
          @filterOptions={{this.statusOptions}}
          @filterValue={{@tracker.reviewStatusFilter}}
          @onFilter={{this.setReviewStatusFilter}}
          @viewOptions={{this.viewOptions}}
          @view={{@tracker.reviewsView}}
          @onView={{this.setReviewsView}}
          as |bar|
        >
          {{#if @tracker.canCreate}}
            <bar.Action
              @id='new-cycle'
              @label='New cycle'
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew ReviewCycle}}
            />
            <bar.Action
              @id='add-review'
              @label='Add review'
              @primary={{true}}
              @loading={{@tracker.addCard.isRunning}}
              @onClick={{fn @tracker.addNew PerformanceReview}}
            />
          {{/if}}
        </ListToolbar>
        <TrackerSection
          {{this.fit.measure}}
          @title='Reviews'
          @meta={{this.panelMeta}}
          @padded={{this.notTable}}
        >
          {{#if (eq @tracker.reviewsView 'table')}}
            <DataTable
              @visibleColumns={{this.visibleColumns}}
              @loading={{@tracker.reviewsQuery.isLoading}}
              @columns={{this.columns}}
              @rows={{this.filteredReviews}}
              @key={{this.rowKey}}
              @label='Performance reviews'
              @columnMenu={{false}}
              @sortable={{false}}
              @striped={{false}}
              @flush={{true}}
            >
              <:empty>{{#if @tracker.reviewsQuery.isLoading}}<LoadingState
                    @label='Loading'
                  />{{else}}<TrackerEmpty>No performance reviews yet</TrackerEmpty>{{/if}}</:empty>
              <:cell as |text row col|>
                {{#if (eq col.key 'person')}}
                  <RowOpen @onOpen={{fn @tracker.openRowCard row}}>{{#let
                      (getComponent row.employee)
                      as |Atom|
                    }}{{#if Atom}}<Atom
                          @format='atom'
                          @displayContainer={{false}}
                        />{{else}}{{if text text '—'}}{{/if}}{{/let}}</RowOpen>
                {{else if (eq col.key 'status')}}
                  <StatusDot
                    @tone={{statusTone row.status}}
                    @label={{this.statusText row.status}}
                  />
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
                    />{{else}}<TrackerEmpty>No performance reviews yet</TrackerEmpty>{{/if}}
                {{/if}}
              </Search>
            {{/let}}
          {{/if}}
        </TrackerSection>
      </:default>
    </TrackerPage>
    <style scoped>
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
