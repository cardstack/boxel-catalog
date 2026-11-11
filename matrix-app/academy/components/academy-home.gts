import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { identifyCard, type getCards } from '@cardstack/runtime-common';
import CheckIcon from '@cardstack/boxel-icons/check';
import PlusIcon from '@cardstack/boxel-icons/plus';

import { Cohort, CohortStatusField } from '../cohort';
import { Course, CourseStatusField } from '../course';
import { Enrollment } from '../enrollment';
import { Submission } from '../submission';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Table } from '@cardstack/pretui/components/table';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { StatStrip, dotHue, type DeskStat } from './desk-parts';

interface Signature {
  Args: {
    context?: any;
    realms?: string[];
    onOpenCohort?: (cohort: any) => void;
    onOpenCourse?: (course: any) => void;
    onOpenSubmission?: (submission: any) => void;
    onNewCohort?: () => void;
  };
  Element: HTMLElement;
}

/**
 * The instructor's Monday morning: what is running, where the grading pile
 * is, what starts next and which courses exist. Everything is a live realm
 * query; nothing is stored.
 */
export class AcademyHome extends GlimmerComponent<Signature> {
  private cohorts: ReturnType<getCards> | undefined;
  private courses: ReturnType<getCards> | undefined;
  private enrollments: ReturnType<getCards> | undefined;
  private submissions: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    let ctx = this.args.context;
    if (!ctx?.getCards) return;
    // Captured once: thunks must not read tracked state.
    let realmList = this.args.realms;
    let realms = () => realmList;
    let q = (cls: any) => () => {
      let ref = identifyCard(cls);
      return ref ? { filter: { type: ref } } : undefined;
    };
    this.cohorts = ctx.getCards(this, q(Cohort), realms, { isLive: true });
    this.courses = ctx.getCards(this, q(Course), realms, { isLive: true });
    this.enrollments = ctx.getCards(this, q(Enrollment), realms, {
      isLive: true,
    });
    this.submissions = ctx.getCards(this, q(Submission), realms, {
      isLive: true,
    });
  }

  get isLoading() {
    return !!(
      this.cohorts?.isLoading ||
      this.courses?.isLoading ||
      this.enrollments?.isLoading ||
      this.submissions?.isLoading
    );
  }
  get allCohorts(): any[] {
    return ((this.cohorts?.instances ?? []) as any[]).filter(Boolean);
  }
  private byStart(status: string): any[] {
    return this.allCohorts
      .filter((c) => c.status === status)
      .sort(
        (a, b) =>
          (toDate(a.term?.start)?.getTime() ?? 0) -
          (toDate(b.term?.start)?.getTime() ?? 0),
      );
  }
  get running(): any[] {
    return this.byStart('running');
  }
  get planned(): any[] {
    return this.byStart('planned');
  }
  get closedCount(): number {
    return this.allCohorts.filter((c) => c.status === 'closed').length;
  }
  get allCourses(): any[] {
    return ((this.courses?.instances ?? []) as any[]).filter(Boolean);
  }
  get activeSeats(): number {
    return ((this.enrollments?.instances ?? []) as any[]).filter(
      (e) => e?.enrollmentStatus === 'active',
    ).length;
  }
  get awaiting(): any[] {
    return ((this.submissions?.instances ?? []) as any[])
      .filter((s) => s?.submissionStatus === 'submitted')
      .sort(
        (a, b) =>
          new Date(a.submittedAt ?? 0).getTime() -
          new Date(b.submittedAt ?? 0).getTime(),
      );
  }

  get stats(): DeskStat[] {
    let oldest = this.awaiting[0]?.submittedAt;
    let next = toDate(this.planned[0]?.term?.start);
    return [
      {
        label: 'Cohorts running',
        value: this.running.length,
        hint: `of ${this.allCohorts.length} cohorts`,
        hue: 'green',
      },
      {
        label: 'Active learners',
        value: this.activeSeats,
        hint: 'active enrollments',
      },
      {
        label: 'Awaiting grade',
        value: this.awaiting.length,
        hint: oldest ? `oldest ${ago(oldest)}` : 'nothing waiting',
        hue: 'amber',
      },
      {
        label: 'Planned',
        value: this.planned.length,
        hint: next ? `next starts ${shortDate(next)}` : 'none planned',
      },
      {
        label: 'Closed',
        value: this.closedCount,
        hint: 'closed cohorts',
        hue: 'blue',
      },
    ];
  }

  cohortHue = (c: any) => dotHue(statusHue(CohortStatusField, c.status));
  courseHue = (c: any) => dotHue(statusHue(CourseStatusField, c.status));
  moduleCount = (c: any) => (c.course?.modules ?? []).length;
  cohortOf = (s: any) => s.enrollment?.cohortName ?? '';
  open = (c: any) => this.args.onOpenCohort?.(c);
  openCourse = (c: any) => this.args.onOpenCourse?.(c);
  openSub = (s: any) => this.args.onOpenSubmission?.(s);
  gradeOldest = () => {
    let s = this.awaiting[0];
    if (s) this.openSub(s);
  };

  <template>
    <div class='home' ...attributes>
      <div class='actions'>
        {{#if @onNewCohort}}
          <Button
            @icon={{PlusIcon}}
            @appearance='outlined'
            @tone='neutral'
            @size='s'
            {{on 'click' @onNewCohort}}
          >New cohort</Button>
        {{/if}}
        <Button
          @icon={{CheckIcon}}
          @tone='primary'
          @size='s'
          @disabled={{if this.awaiting.length false true}}
          {{on 'click' this.gradeOldest}}
        >Grade the oldest</Button>
      </div>

      {{#if this.isLoading}}
        <p class='muted'>Loading the academy…</p>
      {{else}}
        <StatStrip @stats={{this.stats}} @label='Academy this week' />

        <div class='pair'>
          <section class='blk'>
            <div class='bh'><h2>Running cohorts</h2><span
                class='n'
              >{{this.running.length}}</span></div>
            {{#if this.running.length}}
              <Table @label='Running cohorts' @framed={{false}}>
                <:head><tr><th scope='col'>Cohort</th><th
                      scope='col'
                    >Status</th><th scope='col'>Course</th><th
                      scope='col'
                    >Week</th><th
                      scope='col'
                      class='end'
                    >Released</th></tr></:head>
                <:body>
                  {{#each this.running as |c|}}
                    <tr>
                      <td><button
                          type='button'
                          class='name'
                          {{on 'click' (fn this.open c)}}
                        ><span class='mark' aria-hidden='true'>Ch</span><b
                          >{{c.cardTitle}}</b></button></td>
                      <td><span class='st'><span
                            class='dot'
                            data-hue={{this.cohortHue c}}
                          ></span>Running</span></td>
                      <td class='mono'>{{c.courseCode}}</td>
                      <td><span class='wk'><ProgressBar
                            class='bar'
                            @value={{c.currentWeek}}
                            @max={{c.weekCount}}
                            aria-label='Week'
                          /><span
                            class='mono'
                          >{{c.currentWeek}}/{{c.weekCount}}</span></span></td>
                      <td
                        class='mono end'
                      >{{c.releasedCount}}/{{this.moduleCount c}}</td>
                    </tr>
                  {{/each}}
                </:body>
              </Table>
            {{else}}
              <EmptyState
                @size='s'
                @title='Nothing running'
                @message='No cohort is running this week.'
              />
            {{/if}}
          </section>

          <section class='blk'>
            <div class='bh'><h2>Grading pile</h2><span
                class='n'
              >{{this.awaiting.length}} waiting</span></div>
            {{#if this.awaiting.length}}
              <ol class='rows'>
                {{#each this.awaiting as |s|}}
                  <li class='row'>
                    <button
                      type='button'
                      class='two'
                      {{on 'click' (fn this.openSub s)}}
                    ><b>{{s.learnerName}} · {{s.assignmentTitle}}</b><span
                        class='sub'
                      >v{{if s.version s.version 1}}
                        ·
                        {{this.cohortOf s}}</span></button>
                    <span class='meta'><span class='mono'>{{ago
                          s.submittedAt
                        }}</span>{{#if s.isLate}}<span class='st'><span
                            class='dot'
                            data-hue='destructive'
                          ></span>{{s.daysLate}}d late</span>{{/if}}</span>
                  </li>
                {{/each}}
              </ol>
            {{else}}
              <EmptyState
                @size='s'
                @title='Nothing waiting'
                @message='Every submission is graded.'
              />
            {{/if}}
          </section>
        </div>

        <div class='pair'>
          <section class='blk'>
            <div class='bh'><h2>Planned</h2><span
                class='n'
              >{{this.planned.length}}</span></div>
            {{#if this.planned.length}}
              <ul class='rows'>
                {{#each this.planned as |c|}}
                  <li class='row'>
                    <button
                      type='button'
                      class='name'
                      {{on 'click' (fn this.open c)}}
                    ><span class='mark' aria-hidden='true'>Ch</span><b
                      >{{c.cardTitle}}</b><span
                        class='mono muted'
                      >{{c.courseCode}}</span></button>
                    <span class='mono'>{{c.termLabel}}</span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class='muted pad'>No planned cohorts.</p>
            {{/if}}
          </section>

          <section class='blk'>
            <div class='bh'><h2>Courses</h2><span
                class='n'
              >{{this.allCourses.length}}</span></div>
            {{#if this.allCourses.length}}
              <ul class='rows'>
                {{#each this.allCourses as |c|}}
                  <li class='row'>
                    <button
                      type='button'
                      class='name'
                      {{on 'click' (fn this.openCourse c)}}
                    ><span class='mark' aria-hidden='true'>Co</span><b
                      >{{c.cardTitle}}</b><span
                        class='mono muted'
                      >{{c.code}}</span></button>
                    <span class='st'><span
                        class='dot'
                        data-hue={{this.courseHue c}}
                      ></span>{{c.status}}</span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class='muted pad'>No courses yet.</p>
            {{/if}}
          </section>
        </div>
      {{/if}}
    </div>
    <style scoped>
      .home {
        container-type: inline-size;
        display: grid;
        gap: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-xs);
      }
      .actions {
        display: flex;
        justify-content: flex-end;
        gap: var(--boxel-sp-xs);
        --control-height: 1.625rem;
      }
      /* Two blocks joined into one card: equal height, one divider. */
      .pair {
        display: grid;
        grid-template-columns: minmax(0, 2fr) minmax(0, 1fr);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        color: var(--card-foreground);
        overflow: hidden;
      }
      .blk {
        min-width: 0;
      }
      .blk + .blk {
        border-inline-start: 1px solid var(--border);
      }
      .bh {
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
      }
      h2 {
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .n,
      .mono {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        font-variant-numeric: tabular-nums;
      }
      .n,
      .muted,
      .sub {
        color: var(--muted-foreground);
      }
      th {
        text-align: start;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs);
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        border-bottom: 1px solid var(--border);
      }
      td {
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
        white-space: nowrap;
      }
      .end {
        text-align: end;
      }
      .wk {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .bar {
        inline-size: 4rem;
      }
      .rows {
        list-style: none;
        margin: 0;
        padding: 0;
      }
      .row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-4xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border);
      }
      .row:last-child {
        border-bottom: none;
      }
      .name,
      .two {
        all: unset;
        cursor: pointer;
        min-width: 0;
      }
      .name {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .two {
        display: grid;
      }
      .name:focus-visible,
      .two:focus-visible {
        outline: 2px solid var(--ring);
      }
      .two b,
      .name b {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .name .mono {
        white-space: nowrap;
      }
      .mark {
        display: grid;
        place-items: center;
        inline-size: 1.125rem;
        block-size: 1.125rem;
        border-radius: var(--radius);
        background: var(--muted);
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
        flex: none;
      }
      .meta {
        display: inline-flex;
        gap: var(--boxel-sp-xs);
        flex: none;
      }
      .st {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-5xs);
        text-transform: capitalize;
      }
      .dot {
        inline-size: 0.375rem;
        block-size: 0.375rem;
        border-radius: 50%;
        background: var(--muted-foreground);
      }
      .dot[data-hue='success'] {
        background: var(--success);
      }
      .dot[data-hue='warning'] {
        background: var(--warning);
      }
      .dot[data-hue='destructive'] {
        background: var(--destructive);
      }
      .dot[data-hue='primary'] {
        background: var(--primary);
      }
      .pad {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
      }
      @container (width <= 48rem) {
        .pair {
          grid-template-columns: minmax(0, 1fr);
        }
        .blk + .blk {
          border-inline-start: none;
          border-block-start: 1px solid var(--border);
        }
      }
    </style>
  </template>
}

function shortDate(d: Date) {
  return d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
}

function ago(d?: Date | string | null) {
  if (!d) return '';
  let diff = Date.now() - new Date(d).getTime();
  if (diff < 3600_000) return `${Math.max(1, Math.round(diff / 60_000))}m ago`;
  if (diff < 86_400_000) return `${Math.round(diff / 3600_000)}h ago`;
  return `${Math.round(diff / 86_400_000)}d ago`;
}

export default AcademyHome;
