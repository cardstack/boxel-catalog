import GlimmerComponent from '@glimmer/component';
import type { RenderableSearchEntryLike } from '@cardstack/runtime-common';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
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
import { Application } from '../../hr/application';
import { ScreenApplicationCommand } from '../../hr/commands/screen-application-command';
import type { TrackerView } from '../talent-resource-tracker';
import { toLocalDate } from '../dates';
import { PanelHead } from '../shared';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class ApplicationsTab extends GlimmerComponent<Signature> {
  asEntries = (entries: unknown) => entries as RenderableSearchEntryLike[];

  setApplicationsView = (view: string) => {
    this.args.tracker.applicationsView = view as 'grid' | 'strip' | 'table';
  };

  viewOptions = [
    { value: 'grid', label: 'Grid' },
    { value: 'strip', label: 'List' },
    { value: 'table', label: 'Table' },
  ];

  columns: DataColumn<Application>[] = [
    { key: 'name', label: 'Applicant' },
    { key: 'role', label: 'Role', value: (a) => a.position?.jobTitle },
    { key: 'source', label: 'Source' },
    {
      key: 'applied',
      label: 'Applied',
      value: (a) => this.args.tracker.formatDate(a.appliedDate),
    },
    { key: 'status', label: 'Status' },
    { key: 'action', label: 'Action', sortable: false },
  ];

  rowKey = (a: Application) => a.id ?? a.name ?? '';

  get tableRows(): Application[] {
    return this.filteredApplications.map((e) => e.item);
  }

  get subtitle(): string {
    return 'Inbound, not yet promoted to the pipeline';
  }

  get panelMeta(): string {
    let n = this.tableRows.length;
    return this.args.tracker.isLoading
      ? '—'
      : `${n} ${n === 1 ? 'application' : 'applications'}`;
  }

  setApplicationsSearch = (value: string) => {
    this.args.tracker.debouncedSetApplicationsSearch(value);
  };

  get filteredApplications(): { item: Application; index: number }[] {
    let q = this.args.tracker.applicationsSearch.trim().toLowerCase();
    return this.args.tracker.applications
      .map((item, index) => ({ item, index }))
      .filter(
        ({ item }) =>
          !q ||
          item.name?.toLowerCase().includes(q) ||
          item.position?.title?.toLowerCase().includes(q),
      );
  }

  isBusyApplication = (application: Application | undefined): boolean => {
    return (
      Boolean(application?.id) &&
      this.args.tracker.busyApplicationId === application?.id
    );
  };

  // Review mode — a full-screen triage queue instead of clicking Screen on
  // one tile at a time. Oldest-waiting-first, because that's the real
  // signal this app has (no AI match score exists to sort by instead).
  get reviewQueue(): Application[] {
    return this.args.tracker.applications
      .filter((a) => a.status === 'new' || a.status === 'reviewing')
      .sort((a, b) => {
        let aTime = a.appliedDate ? toLocalDate(a.appliedDate).getTime() : 0;
        let bTime = b.appliedDate ? toLocalDate(b.appliedDate).getTime() : 0;
        return aTime - bTime;
      });
  }

  get currentReviewApplication(): Application | undefined {
    let queue = this.reviewQueue;
    if (!queue.length) {
      return undefined;
    }
    return queue[Math.min(this.args.tracker.reviewIndex, queue.length - 1)];
  }

  get reviewPositionLabel(): string {
    return `${Math.min(this.args.tracker.reviewIndex + 1, this.reviewQueue.length)} / ${this.reviewQueue.length}`;
  }

  startReview = () => {
    this.args.tracker.reviewMode = true;
    this.args.tracker.reviewIndex = 0;
    this.args.tracker.reviewedCount = 0;
  };

  exitReview = () => {
    this.args.tracker.reviewMode = false;
  };

  reviewStep = (delta: number) => {
    let max = this.reviewQueue.length;
    if (!max) {
      return;
    }
    this.args.tracker.reviewIndex = Math.max(
      0,
      Math.min(max - 1, this.args.tracker.reviewIndex + delta),
    );
  };

  reviewGoTo = (index: number) => {
    this.args.tracker.reviewIndex = Math.max(
      0,
      Math.min(this.reviewQueue.length - 1, index),
    );
  };

  // Enter screens the current application only when the panel itself has
  // focus, so Enter on a focused button inside it activates that button.
  reviewKeydown = (e: Event) => {
    let event = e as KeyboardEvent;
    if (event.key === 'Enter' && event.target !== event.currentTarget) {
      return;
    }
    if (event.key === 'ArrowRight') {
      event.preventDefault();
      this.reviewStep(1);
    } else if (event.key === 'ArrowLeft') {
      event.preventDefault();
      this.reviewStep(-1);
    } else if (event.key === 'Escape') {
      event.preventDefault();
      this.exitReview();
    } else if (event.key === 'Enter') {
      event.preventDefault();
      let app = this.currentReviewApplication;
      if (app) {
        void this.reviewScreen(app);
      }
    }
  };

  reviewScreen = async (application: Application) => {
    await this.screenApplication(application);
    this.args.tracker.reviewedCount++;
    if (
      this.args.tracker.reviewIndex >= this.reviewQueue.length &&
      this.args.tracker.reviewIndex > 0
    ) {
      this.args.tracker.reviewIndex = this.reviewQueue.length - 1;
    }
  };

  reviewReject = async (application: Application) => {
    let commandContext = this.args.tracker.args.context?.commandContext;
    if (!commandContext) {
      this.args.tracker.actionError = 'Commands are unavailable in this mode';
      return;
    }
    this.args.tracker.busyApplicationId = application.id;
    try {
      application.status = 'rejected';
      await new SaveCardCommand(commandContext).execute({
        card: application,
      } as any);
      this.args.tracker.reviewedCount++;
      if (
        this.args.tracker.reviewIndex >= this.reviewQueue.length &&
        this.args.tracker.reviewIndex > 0
      ) {
        this.args.tracker.reviewIndex = this.reviewQueue.length - 1;
      }
    } catch (error: any) {
      this.args.tracker.actionError = error?.message ?? String(error);
    } finally {
      this.args.tracker.busyApplicationId = undefined;
    }
  };

  screenApplication = async (application: Application) => {
    this.args.tracker.actionError = undefined;
    let commandContext = this.args.tracker.args.context?.commandContext;
    if (!commandContext) {
      this.args.tracker.actionError = 'Commands are unavailable in this mode';
      return;
    }
    this.args.tracker.busyApplicationId = application.id;
    try {
      // The created Candidate reaches the Pipeline via the live
      // `candidatesQuery` — nothing to link back onto the tracker.
      await new ScreenApplicationCommand(commandContext).execute({
        application,
      } as any);
    } catch (error: any) {
      this.args.tracker.actionError = error?.message ?? String(error);
    } finally {
      this.args.tracker.busyApplicationId = undefined;
    }
  };

  <template>
    <PageScaffold @title='Applications' @subtitle={{this.subtitle}}>
      <:actions>
        {{#unless @tracker.reviewMode}}
          {{#if @tracker.canCreate}}
            <Button
              type='button'
              @tone='neutral'
              @appearance='outlined'
              @loading={{@tracker.addCard.isRunning}}
              {{on 'click' (fn @tracker.addNew Application)}}
            >+ Add application</Button>
          {{/if}}
          {{#if this.reviewQueue.length}}
            <Button
              type='button'
              @tone='primary'
              @appearance='accent'
              {{on 'click' this.startReview}}
            >Review mode ({{if
                @tracker.isLoading
                '—'
                this.reviewQueue.length
              }})</Button>
          {{/if}}
        {{/unless}}
      </:actions>
      <:default>
        {{#if @tracker.reviewMode}}
          {{#if this.currentReviewApplication}}
            {{#let this.currentReviewApplication as |app|}}
              <div
                class='review'
                tabindex='0'
                {{on 'keydown' this.reviewKeydown}}
              >
                <div class='review-bar'>
                  <span class='review-status'>Review mode ·
                    {{this.reviewPositionLabel}}
                    · reviewed
                    {{@tracker.reviewedCount}}</span>
                  <span class='review-keys'>
                    <kbd>←</kbd><kbd>→</kbd>
                    navigate ·
                    <kbd>↵</kbd>
                    screen ·
                    <kbd>Esc</kbd>
                    exit
                  </span>
                  <Button
                    type='button'
                    @tone='neutral'
                    @appearance='outlined'
                    class='btn-review-exit'
                    {{on 'click' this.exitReview}}
                  >Exit</Button>
                </div>
                <div class='review-panes'>
                  <div class='review-queue'>
                    {{#each this.reviewQueue as |queued index|}}
                      <Button
                        @tone='neutral'
                        @appearance='plain'
                        class='review-queue-item
                          {{if (eq index @tracker.reviewIndex) "on"}}'
                        {{on 'click' (fn this.reviewGoTo index)}}
                      >
                        <span class='review-queue-name'>{{queued.name}}</span>
                        <span class='review-queue-meta'>{{@tracker.formatDate
                            queued.appliedDate
                          }}</span>
                      </Button>
                    {{/each}}
                  </div>
                  <div class='review-resume'>
                    <div class='review-resume-head'>
                      <strong>{{app.name}}</strong>
                      <span class='dim'>{{app.position.jobTitle}}</span>
                    </div>
                    {{#if app.resumeText}}
                      <p class='review-resume-text'>{{app.resumeText}}</p>
                    {{else}}
                      <EmptyState
                        @size='s'
                        @texture={{false}}
                        @title='No résumé text on file'
                      />
                    {{/if}}
                  </div>
                  <div class='review-actions'>
                    <Button
                      type='button'
                      @tone='primary'
                      @appearance='accent'
                      class='btn-review-primary'
                      @disabled={{this.isBusyApplication app}}
                      {{on 'click' (fn this.reviewScreen app)}}
                    >{{if
                        (this.isBusyApplication app)
                        'Screening…'
                        'Screen → Candidate'
                      }}</Button>
                    <Button
                      type='button'
                      @tone='danger'
                      @appearance='outlined'
                      class='btn-review-danger'
                      @disabled={{this.isBusyApplication app}}
                      {{on 'click' (fn this.reviewReject app)}}
                    >Reject</Button>
                  </div>
                </div>
              </div>
            {{/let}}
          {{else}}
            <EmptyState
              @size='s'
              @texture={{false}}
              @title='Queue is empty'
              @message='Every inbound application has been reviewed.'
            />
          {{/if}}
        {{else}}
          <div class='list-toolbar'>
            <SearchInput
              class='list-search'
              @value={{@tracker.applicationsSearch}}
              @placeholder='Search applications…'
              @label='Search applications'
              @onInput={{this.setApplicationsSearch}}
            />
            <SegmentedControl
              @options={{this.viewOptions}}
              @value={{@tracker.applicationsView}}
              @onValueChange={{this.setApplicationsView}}
              @label='View'
            />
          </div>
          <Panel>
            <:header><PanelHead
                @title='Inbound'
                @meta={{this.panelMeta}}
              /></:header>
            <:default>
              {{#if (eq @tracker.applicationsView 'table')}}
                <DataTable
                  @loading={{@tracker.applicationsQuery.isLoading}}
                  @columns={{this.columns}}
                  @rows={{this.tableRows}}
                  @key={{this.rowKey}}
                  @label='Applications'
                  @columnMenu={{false}}
                >
                  <:empty>{{#if
                      @tracker.applicationsQuery.isLoading
                    }}<LoadingState @label='Loading' />{{else}}<EmptyState
                        @size='s'
                        @texture={{false}}
                        @title='No applications yet'
                      />{{/if}}</:empty>
                  <:cell as |text row col|>
                    {{#if (eq col.key 'status')}}
                      <StatusChip @value={{row.status}} />
                    {{else if (eq col.key 'action')}}
                      {{#if
                        (or (eq row.status 'new') (eq row.status 'reviewing'))
                      }}
                        <Button
                          type='button'
                          @tone='neutral'
                          @appearance='filled'
                          @size='s'
                          @disabled={{this.isBusyApplication row}}
                          {{on 'click' (fn this.screenApplication row)}}
                        >{{if
                            (this.isBusyApplication row)
                            'Screening…'
                            'Screen → Candidate'
                          }}</Button>
                      {{/if}}
                    {{else}}
                      {{if text text '—'}}
                    {{/if}}
                  </:cell>
                </DataTable>
              {{else}}
                {{! Screening actions live in the table view and Review
              mode; the tiles here are the prerendered entry API's —
              hover to hydrate, click to open. }}
                {{#let (component @context.searchResultsComponent) as |Search|}}
                  <Search
                    @query={{@tracker.applicationsSearchQuery}}
                    @mode='none'
                    as |results|
                  >
                    {{#if results.entries.length}}
                      <Grid
                        @items={{this.asEntries results.entries}}
                        @size={{if
                          (eq @tracker.applicationsView 'strip')
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
                          @title='No applications yet'
                        />{{/if}}
                    {{/if}}
                  </Search>
                {{/let}}
              {{/if}}
            </:default>
          </Panel>
        {{/if}}
      </:default>
    </PageScaffold>
    <style scoped>
      .dim {
        color: var(--muted-foreground);
      }
      .review {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .review:focus-visible {
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      .review-bar {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp);
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        background: var(--muted);
        border-bottom: 1px solid var(--border);
        font-size: var(--boxel-font-size-xs);
      }
      .review-status {
        font-weight: 600;
      }
      .review-keys {
        margin-left: auto;
        color: var(--muted-foreground);
      }
      .review-keys kbd {
        font-size: var(--boxel-font-size-xs);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-xs);
        padding: var(--boxel-sp-6xs) var(--boxel-sp-4xs);
        background: var(--card);
      }
      .review-panes {
        display: grid;
        grid-template-columns: 12.5rem minmax(0, 1fr) 13.75rem;
        min-height: 24rem;
      }
      @container tracker (max-width: 60rem) {
        .review-panes {
          grid-template-columns: minmax(0, 1fr);
        }
      }
      .review-queue {
        border-right: 1px solid var(--border);
        overflow-y: auto;
        max-height: 32rem;
      }
      .review-queue-item {
        display: flex;
        flex-direction: column;
        width: 100%;
        text-align: left;
        gap: var(--boxel-sp-6xs);
        cursor: pointer;
      }
      .review-queue-name {
        font-weight: 600;
        font-size: var(--boxel-font-size-sm);
      }
      .review-queue-meta {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .review-resume {
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        overflow-y: auto;
        max-height: 32rem;
      }
      .review-resume-head {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        margin-bottom: var(--boxel-sp);
      }
      .review-resume-text {
        white-space: pre-wrap;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.6;
      }
      .review-actions {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp);
        border-left: 1px solid var(--border);
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
        outline: 0.125rem solid var(--primary);
        outline-offset: 0.125rem;
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          transition: none;
        }
      }
      .list-toolbar {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      .list-toolbar > :last-child {
        margin-left: auto;
      }
      .list-search {
        flex: 1;
        min-width: 12rem;
        max-width: 20rem;
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
