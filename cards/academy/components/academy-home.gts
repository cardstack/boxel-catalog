import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { identifyCard, type getCards } from '@cardstack/runtime-common';

import {
  Cohort,
  CohortStatusField,
  buildCohortWeeks,
  todayPosition,
} from '../cohort';
import { Course, CourseStatusField } from '../course';
import { Enrollment } from '../enrollment';
import { Submission } from '../submission';
import { CohortTimeline } from './cohort-timeline';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';

interface Signature {
  Args: {
    context?: any;
    realms?: string[];
    onOpenCohort?: (cohort: any) => void;
    onOpenCourse?: (course: any) => void;
    onOpenSubmission?: (submission: any) => void;
  };
  Element: HTMLElement;
}

/**
 * The instructor's Monday morning: what is running this week, where the
 * grading pile is, and which live sessions are next — then one timeline row
 * per running cohort, so the whole academy reads as a set of rails rather
 * than a grid of tiles. Everything is a live realm query; nothing is stored.
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
    // Captured once: thunks must not read tracked state (see cohort-workspace).
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
  get running(): any[] {
    return this.allCohorts
      .filter((c) => c.status === 'running')
      .sort(
        (a, b) =>
          (toDate(a.term?.start)?.getTime() ?? 0) -
          (toDate(b.term?.start)?.getTime() ?? 0),
      );
  }
  get planned(): any[] {
    return this.allCohorts
      .filter((c) => c.status === 'planned')
      .sort(
        (a, b) =>
          (toDate(a.term?.start)?.getTime() ?? 0) -
          (toDate(b.term?.start)?.getTime() ?? 0),
      );
  }
  get closed(): any[] {
    return this.allCohorts.filter((c) => c.status === 'closed');
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
  get oldestAwaitingAt(): Date | string | undefined {
    return this.awaiting[0]?.submittedAt;
  }
  get upcomingLive(): { lesson: any; cohort: any; at: Date }[] {
    let now = Date.now();
    let horizon = now + 7 * 86_400_000;
    let out: { lesson: any; cohort: any; at: Date }[] = [];
    for (let c of this.running) {
      let released = new Set(
        ((c.releases ?? []) as any[]).map((r) => r?.module?.id).filter(Boolean),
      );
      for (let m of (c.course?.modules ?? []) as any[]) {
        if (!m || !released.has(m.id)) continue;
        for (let l of (m.lessons ?? []) as any[]) {
          if (l?.kind === 'live' && l.liveSessionAt) {
            let at = new Date(l.liveSessionAt).getTime();
            if (at >= now && at <= horizon)
              out.push({ lesson: l, cohort: c, at: new Date(at) });
          }
        }
      }
    }
    return out.sort((a, b) => a.at.getTime() - b.at.getTime()).slice(0, 6);
  }

  weeks = (c: any) => buildCohortWeeks(c);
  today = (c: any) => todayPosition(c.term?.start, c.term?.end);
  cohortHue = (c: any) => statusHue(CohortStatusField, c.status);
  courseHue = (c: any) => statusHue(CourseStatusField, c.status);
  open = (c: any) => this.args.onOpenCohort?.(c);
  openCourse = (c: any) => this.args.onOpenCourse?.(c);
  openSub = (s: any) => this.args.onOpenSubmission?.(s);

  <template>
    <div class='home' ...attributes>
      {{#if this.isLoading}}
        <p class='muted'>Loading the academy…</p>
      {{else}}
        <section class='hero'>
          <div class='hero-main'>
            <span class='eyebrow'>This week</span>
            <h2 class='hero-n'>{{this.running.length}}
              <span class='hero-l'>{{if
                  (isOne this.running.length)
                  'cohort'
                  'cohorts'
                }}
                running</span></h2>
            <p class='hero-sub'>{{this.activeSeats}}
              active learners ·
              {{this.planned.length}}
              planned ·
              {{this.closed.length}}
              closed</p>
          </div>
          <div class='pile {{if this.awaiting.length "hot"}}'>
            <span class='pile-n'>{{this.awaiting.length}}</span>
            <span class='pile-l'>awaiting grade</span>
            {{#if this.awaiting.length}}
              <span class='pile-hint'>oldest:
                {{ago this.oldestAwaitingAt}}</span>
              <Button
                @tone='primary'
                @appearance='accent'
                @size='xs'
                {{on 'click' (fn this.openSub (first this.awaiting))}}
              >Grade the oldest</Button>
            {{/if}}
          </div>
          <div class='live'>
            <span class='eyebrow'>Live in the next 7 days</span>
            {{#if this.upcomingLive.length}}
              <ul class='live-list'>
                {{#each this.upcomingLive as |u|}}
                  <li>
                    <span class='live-when'>{{fmtShort u.at}}</span>
                    <span class='live-what'>{{u.lesson.cardTitle}}</span>
                    <Button
                      @appearance='link'
                      @size='xs'
                      {{on 'click' (fn this.open u.cohort)}}
                    >{{u.cohort.cardTitle}}</Button>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class='muted small'>No live sessions scheduled.</p>
            {{/if}}
          </div>
        </section>

        <section class='rails'>
          <h3 class='sec'>Running cohorts</h3>
          {{#if this.running.length}}
            <ol class='rail-list'>
              {{#each this.running as |c|}}
                <li class='rail-row'>
                  <div class='rail-head'>
                    <Button
                      @appearance='link'
                      {{on 'click' (fn this.open c)}}
                    ><strong>{{c.cardTitle}}</strong></Button>
                    <span class='rail-sub'>{{c.courseCode}}
                      · week
                      {{if c.currentWeek c.currentWeek '—'}}
                      of
                      {{c.weekCount}}{{#if c.leadInstructorName}}
                        ·
                        {{c.leadInstructorName}}{{/if}}</span>
                  </div>
                  <div class='rail-tl'>
                    {{#let (this.today c) as |t|}}
                      <CohortTimeline
                        @weeks={{this.weeks c}}
                        @todayIndex={{t.index}}
                        @todayFraction={{t.fraction}}
                        @onSelectWeek={{fn this.open c}}
                      />
                    {{/let}}
                  </div>
                  <span
                    class='rail-rel'
                  >{{c.releasedCount}}/{{c.course.moduleCount}} released</span>
                </li>
              {{/each}}
            </ol>
          {{else}}
            <EmptyState
              @size='s'
              @title='Nothing is running'
              @message='Start a planned cohort from its page when the term begins.'
            />
          {{/if}}
        </section>

        <section class='pile-list'>
          <h3 class='sec'>Grading pile</h3>
          {{#if this.awaiting.length}}
            <ol class='plain'>
              {{#each this.awaiting as |s|}}
                <li>
                  <div class='row'>
                    <span class='sub-who'><Button
                        @appearance='link'
                        @size='s'
                        {{on 'click' (fn this.openSub s)}}
                      >{{s.learnerName}}</Button>
                      ·
                      {{s.assignmentTitle}}</span>
                    <span class='muted small'>v{{if s.version s.version 1}}
                      · handed in
                      {{ago s.submittedAt}}{{#if s.isLate}}
                        ·
                        <span class='late'>{{s.daysLate}}d late</span>{{/if}}</span>
                  </div>
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

        <div class='cols'>
          <section>
            <h3 class='sec'>Planned</h3>
            {{#if this.planned.length}}
              <ul class='plain'>
                {{#each this.planned as |c|}}
                  <li class='row'><Button
                      @appearance='link'
                      @size='s'
                      {{on 'click' (fn this.open c)}}
                    >{{c.cardTitle}}</Button><span
                      class='muted small'
                    >{{c.termLabel}}</span></li>
                {{/each}}
              </ul>
            {{else}}
              <p class='muted small'>No planned cohorts.</p>
            {{/if}}
          </section>
          <section>
            <h3 class='sec'>Courses</h3>
            {{#if this.allCourses.length}}
              <ul class='plain'>
                {{#each this.allCourses as |c|}}
                  <li>
                    <div class='row'>
                      <span><span class='code'>{{c.code}}</span>
                        <Button
                          @appearance='link'
                          @size='s'
                          {{on 'click' (fn this.openCourse c)}}
                        >{{c.cardTitle}}</Button></span>
                      <StatePill
                        @label={{c.status}}
                        @hue={{this.courseHue c}}
                      />
                    </div>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class='muted small'>No courses yet.</p>
            {{/if}}
          </section>
        </div>
      {{/if}}
    </div>
    <style scoped>
      .home {
        container-type: inline-size;
        display: grid;
        gap: var(--boxel-sp-lg);
        color: var(--foreground);
      }
      .hero {
        display: grid;
        grid-template-columns: 1.3fr auto 1fr;
        gap: var(--boxel-sp);
        align-items: stretch;
      }
      .hero-main,
      .live {
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .eyebrow {
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .hero-n {
        margin: var(--boxel-sp-4xs) 0 0;
        font-size: var(--boxel-font-size-2xl);
        font-weight: 800;
        line-height: 1;
        letter-spacing: -0.02em;
      }
      .hero-l {
        font-size: var(--boxel-font-size-lg);
        font-weight: 500;
        color: var(--muted-foreground);
      }
      .hero-sub {
        margin: var(--boxel-sp-xs) 0 0;
        color: var(--muted-foreground);
      }
      .pile {
        display: grid;
        align-content: center;
        justify-items: center;
        gap: 0.125rem;
        min-width: 9rem;
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .pile.hot {
        background: color-mix(in oklab, var(--warning) 14%, var(--card));
        border-color: color-mix(in oklab, var(--warning) 40%, var(--border));
      }
      .pile-n {
        font-size: var(--boxel-font-size-xl);
        font-weight: 800;
        line-height: 1;
        font-variant-numeric: tabular-nums;
      }
      .pile-l {
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
      }
      .pile-hint {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .live-list {
        list-style: none;
        margin: var(--boxel-sp-xs) 0 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-sm);
      }
      .live-list li {
        display: grid;
        grid-template-columns: auto 1fr;
        gap: 0 var(--boxel-sp-xs);
      }
      .live-when {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        grid-row: span 2;
        align-self: start;
        padding-top: 0.125rem;
      }
      .live-what {
        font-weight: 600;
      }
      .sec {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .rail-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .rail-row {
        display: grid;
        grid-template-columns: minmax(12rem, 0.8fr) minmax(16rem, 2fr) auto;
        gap: var(--boxel-sp);
        align-items: center;
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .rail-head {
        display: grid;
        justify-items: start;
        min-width: 0;
      }
      @media (prefers-reduced-motion: no-preference) {
        .rail-row,
        .pile {
          transition:
            transform 160ms cubic-bezier(0.2, 0.8, 0.2, 1),
            box-shadow 160ms ease,
            background 140ms ease;
        }
        .rail-row:hover,
        .pile.hot:hover {
          transform: translateY(-0.0625rem);
          box-shadow: 0 0.375rem 1.125rem -0.75rem
            color-mix(in oklab, var(--foreground) 40%, transparent);
        }
      }
      .rail-sub {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .rail-tl {
        min-width: 0;
      }
      .rail-rel {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
        font-variant-numeric: tabular-nums;
      }
      .cols {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--boxel-sp);
      }
      .plain {
        list-style: none;
        margin: 0;
        padding: 0;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .plain li + li {
        border-top: 1px solid var(--border);
      }
      .row {
        min-height: 2.75rem;
        display: flex;
        flex-wrap: wrap;
        justify-content: space-between;
        gap: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        align-items: center;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
      }
      .sub-who {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .late {
        color: var(--warning-ink);
        font-weight: 600;
      }
      .code {
        font-family: var(--font-mono);
        color: var(--primary-ink);
        font-weight: 700;
      }
      .muted {
        color: var(--muted-foreground);
      }
      .small {
        font-size: var(--boxel-font-size-xs);
        margin: 0;
      }
      @container (width <= 47.5rem) {
        .hero {
          grid-template-columns: 1fr 1fr;
        }
        .live {
          grid-column: 1 / -1;
        }
        .rail-row {
          grid-template-columns: 1fr;
        }
        .cols {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}

function isOne(n: number) {
  return n === 1;
}
function first<T>(arr: T[]): T | undefined {
  return arr[0];
}
function fmtShort(d: Date) {
  return d.toLocaleString(undefined, {
    weekday: 'short',
    hour: 'numeric',
    minute: '2-digit',
  });
}
function ago(d?: Date | string | null) {
  if (!d) return '';
  let diff = Date.now() - new Date(d).getTime();
  if (diff < 3600_000) return `${Math.max(1, Math.round(diff / 60_000))}m ago`;
  if (diff < 86_400_000) return `${Math.round(diff / 3600_000)}h ago`;
  return `${Math.round(diff / 86_400_000)}d ago`;
}

export default AcademyHome;
