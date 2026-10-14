import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import LayoutGridIcon from '@cardstack/boxel-icons/layout-grid';
import ListIcon from '@cardstack/boxel-icons/list';
import TableIcon from '@cardstack/boxel-icons/table';
import { htmlSafe } from '@ember/template';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Input } from '@cardstack/pretui/components/input';
import { Application, APPLICATION_STATUS_COLORS } from '../../hr/application';
import { ScreenApplicationCommand } from '../../hr/commands/screen-application-command';
import { stateColorOf } from '../../../components/state-pill';
import type { TrackerView } from '../talent-resource-tracker';

interface Signature {
  Args: {
    tracker: TrackerView;
    context: TrackerView['args']['context'];
  };
}

export class ApplicationsTab extends GlimmerComponent<Signature> {
  setApplicationsView = (view: 'grid' | 'strip' | 'table') => {
    this.args.tracker.applicationsView = view;
  };

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

  applicationStatusStyle = (status: string | undefined) => {
    let color = stateColorOf(APPLICATION_STATUS_COLORS, status);
    return htmlSafe(`background: ${color.bg}; color: ${color.fg};`);
  };

  // Review mode — a full-screen triage queue instead of clicking Screen on
  // one tile at a time. Oldest-waiting-first, because that's the real
  // signal this app has (no AI match score exists to sort by instead).
  get reviewQueue(): Application[] {
    return this.args.tracker.applications
      .filter((a) => a.status === 'new' || a.status === 'reviewing')
      .sort((a, b) => {
        let aTime = a.appliedDate ? new Date(a.appliedDate).getTime() : 0;
        let bTime = b.appliedDate ? new Date(b.appliedDate).getTime() : 0;
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

  reviewKeydown = (e: Event) => {
    let event = e as KeyboardEvent;
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
    <div class='tab-section'>
      <div class='sec-head'>
        <div class='htext'>
          <h2>Applications</h2>
          <p class='byline'>Inbound, not yet promoted to the pipeline</p>
        </div>
        {{#unless @tracker.reviewMode}}
          {{#if @tracker.canCreate}}
            <Button
              type='button'
              @tone='primary'
              @appearance='accent'
              class='btn-review'
              @loading={{@tracker.addCard.isRunning}}
              {{on 'click' (fn @tracker.addNew Application)}}
            >+ Add application</Button>
          {{/if}}
          {{#if this.reviewQueue.length}}
            <Button
              type='button'
              @tone='primary'
              @appearance='accent'
              class='btn-review'
              {{on 'click' this.startReview}}
            >Review mode ({{this.reviewQueue.length}})</Button>
          {{/if}}
        {{/unless}}
      </div>
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
                    <p class='empty-note'>No résumé text on file</p>
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
          <p class='empty-note'>Queue is empty — every inbound application has
            been reviewed.</p>
        {{/if}}
      {{else}}
        <div class='list-toolbar'>
          <div class='list-search'>
            <Input
              @type='search'
              @value={{@tracker.applicationsSearch}}
              @placeholder='Search applications…'
              @onInput={{this.setApplicationsSearch}}
              aria-label='Search applications'
            />
          </div>
          <div class='view-toggle' role='group' aria-label='View'>
            <IconButton
              type='button'
              class='view-btn
                {{if (eq @tracker.applicationsView "grid") "active"}}'
              @label='Grid view'
              {{on 'click' (fn this.setApplicationsView 'grid')}}
            ><LayoutGridIcon class='view-icon' /></IconButton>
            <IconButton
              type='button'
              class='view-btn
                {{if (eq @tracker.applicationsView "strip") "active"}}'
              @label='List view'
              {{on 'click' (fn this.setApplicationsView 'strip')}}
            ><ListIcon class='view-icon' /></IconButton>
            <IconButton
              type='button'
              class='view-btn
                {{if (eq @tracker.applicationsView "table") "active"}}'
              @label='Table view'
              {{on 'click' (fn this.setApplicationsView 'table')}}
            ><TableIcon class='view-icon' /></IconButton>
          </div>
        </div>
        {{#if (eq @tracker.applicationsView 'table')}}
          {{#if this.filteredApplications.length}}
            <div class='data-table-wrap'>
              <table class='data-table'>
                <thead>
                  <tr>
                    <th>Applicant</th>
                    <th>Role</th>
                    <th>Source</th>
                    <th>Applied</th>
                    <th>Status</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {{#each this.filteredApplications as |entry|}}
                    <tr>
                      <td>{{entry.item.name}}</td>
                      <td>{{entry.item.position.jobTitle}}</td>
                      <td>{{entry.item.source}}</td>
                      <td>{{@tracker.formatDate entry.item.appliedDate}}</td>
                      <td>
                        <span
                          class='status-pill'
                          style={{this.applicationStatusStyle
                            entry.item.status
                          }}
                        >{{entry.item.status}}</span>
                      </td>
                      <td>
                        {{#if
                          (or
                            (eq entry.item.status 'new')
                            (eq entry.item.status 'reviewing')
                          )
                        }}
                          <Button
                            type='button'
                            @tone='neutral'
                            @appearance='filled'
                            class='screen-btn'
                            @disabled={{this.isBusyApplication entry.item}}
                            {{on
                              'click'
                              (fn this.screenApplication entry.item)
                            }}
                          >{{if
                              (this.isBusyApplication entry.item)
                              'Screening…'
                              'Screen → Candidate'
                            }}</Button>
                        {{/if}}
                      </td>
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{else if @tracker.applicationsQuery.isLoading}}
            <p class='empty-note'>Loading…</p>
          {{else}}
            <p class='empty-note'>No applications yet</p>
          {{/if}}
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
              <div
                class='tile-grid
                  {{if (eq @tracker.applicationsView "strip") "strip-view"}}'
              >
                {{#each results.entries key='id' as |entry|}}
                  <div
                    class='tile
                      {{if
                        (eq @tracker.applicationsView "strip")
                        "strip-tile"
                      }}'
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
                    <p class='empty-note'>No applications yet</p>
                  {{/if}}
                {{/each}}
              </div>
            </Search>
          {{/let}}
        {{/if}}
      {{/if}}
    </div>
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
      .dim {
        color: var(--muted-foreground);
      }
      .btn-review {
        font-family: var(--font-mono);
        font-size: 11.5px;
        font-weight: 700;
      }
      .review {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow: hidden;
      }
      .review:focus-visible {
        outline: 2px solid var(--primary);
        outline-offset: 2px;
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
        font-weight: 700;
      }
      .review-keys {
        margin-left: auto;
        color: var(--muted-foreground);
      }
      .review-keys kbd {
        font-family: var(--font-mono);
        font-size: 10.5px;
        border: 1px solid var(--border);
        border-radius: 3px;
        padding: 1px 4px;
        background: var(--card);
      }
      .btn-review-exit {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .review-panes {
        display: grid;
        grid-template-columns: 200px minmax(0, 1fr) 220px;
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
        gap: 0.125rem;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: none;
        border-bottom: 1px solid var(--border);
        background: none;
        cursor: pointer;
      }
      .review-queue-item.on {
        background: var(--muted);
      }
      .review-queue-name {
        font-weight: 700;
        font-size: var(--boxel-font-size-sm);
      }
      .review-queue-meta {
        font-family: var(--font-mono);
        font-size: 10.5px;
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
      .btn-review-primary,
      .btn-review-danger {
        font-family: var(--font-mono);
        font-size: 0.75rem;
        font-weight: 700;
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
      .screen-btn {
        margin: 0 var(--boxel-sp-xs) var(--boxel-sp-xs);
        font-family: var(--font-mono);
        font-size: 0.8125rem;
        font-weight: 600;
        transition:
          background-color 0.15s ease-out,
          color 0.15s ease-out;
      }
      .screen-btn:disabled {
        cursor: not-allowed;
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
