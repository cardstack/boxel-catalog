import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked, cached } from '@glimmer/tracking';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';
import { Select } from '@cardstack/pretui/components/select';
import { Tabs } from '@cardstack/pretui/components/tabs';
import { Textarea } from '@cardstack/pretui/components/textarea';

import { buildCohortWeeks, todayPosition, releasedModuleIds } from '../cohort';
import { Enrollment } from '../enrollment';
import { Submission } from '../submission';
import { AttendanceRecord } from '../attendance-record';
import { QuizAttempt } from '../quiz-attempt';
import { Thread } from '@cardstack/catalog/cards/service-desk/thread';
import { Learner } from '../learner';
import { CertificationAuthority } from '@cardstack/catalog/cards/audit/certification-authority';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { EnrollmentStatusField } from '../enrollment-status-field';
import { CohortTimeline, type TimelineWeek } from './cohort-timeline';
import { CourseOutline } from './course-outline';
import { Gradebook } from './gradebook';
import { RubricGrader } from './rubric-grader';
import { AttendanceGrid } from './attendance-grid';
import { LearnerProgress } from './learner-progress';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import ReleaseModuleCommand from '../commands/release-module-command';
import EnrollLearnerCommand from '../commands/enroll-learner-command';
import IssueCertificateCommand from '../commands/issue-certificate-command';
import PostToThreadCommand from '@cardstack/catalog/cards/service-desk/commands/post-to-thread-command';
import { EmptyState } from '@cardstack/pretui/components/empty-state';

interface Signature {
  Args: {
    cohort: any;
    context?: any;
    /** The signed-in instructor, for releasedBy / gradedBy / markedBy / author. */
    actor?: any;
    /** Default authority for Issue Certificate. */
    authority?: any;
    onOpenCard?: (card: any) => void;
  };
  Element: HTMLElement;
}

type Tab = 'week' | 'learners' | 'gradebook' | 'attendance' | 'discussion';

const TABS: { id: Tab; label: string }[] = [
  { id: 'week', label: 'This week' },
  { id: 'learners', label: 'Learners' },
  { id: 'gradebook', label: 'Gradebook' },
  { id: 'attendance', label: 'Attendance' },
  { id: 'discussion', label: 'Discussion' },
];

/**
 * Everything an instructor does to a running cohort, in one place: the
 * full timeline with the next module ready to release, the roster with each
 * learner's live progress and a one-click Issue Certificate, the gradebook
 * with the grader docked beside it, the attendance grid, and the cohort
 * thread. Every write goes through a command; every refusal is shown as the
 * command said it. Data is live realm queries scoped to this cohort.
 */
export class CohortWorkspace extends GlimmerComponent<Signature> {
  @tracked tab: Tab = 'week';
  @tracked selectedSubmission: any | undefined;
  @tracked selectedWeek: TimelineWeek | undefined;
  @tracked busy: string | undefined;
  @tracked error: string | undefined;
  @tracked notice: string | undefined;
  @tracked releaseModuleId: string | undefined;
  @tracked enrollLearner: any | undefined;
  @tracked postBody = '';

  private enrollmentsQ: ReturnType<getCards> | undefined;
  private submissionsQ: ReturnType<getCards> | undefined;
  private attendanceQ: ReturnType<getCards> | undefined;
  private attemptsQ: ReturnType<getCards> | undefined;
  private threadsQ: ReturnType<getCards> | undefined;
  private learnersQ: ReturnType<getCards> | undefined;
  private authoritiesQ: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    let ctx = this.args.context;
    if (!ctx?.getCards) return;
    // Capture everything the query thunks need ONCE. The search resource
    // re-runs `modify` (which writes a tracked property) whenever a thunk's
    // tracked reads invalidate; reading component state here would make any
    // later tracked change assert mid-render.
    let cohortId = this.args.cohort?.id as string | undefined;
    let realmList = this.realms;
    let realms = () => realmList;
    let live = { isLive: true };
    // Lazy + cached: evaluated on the resource's first read (after modules
    // are fully identified), then the same object is returned forever.
    let byType = (cls: any) => () => {
      let ref = identifyCard(cls);
      return ref ? { filter: { type: ref } } : undefined;
    };
    let byLink = (cls: any, path: string) => () => {
      let ref = identifyCard(cls);
      return ref && cohortId
        ? { filter: { on: ref, eq: { [path]: cohortId } } }
        : undefined;
    };
    this.enrollmentsQ = ctx.getCards(
      this,
      byLink(Enrollment, 'cohort.id'),
      realms,
      live,
    );
    this.submissionsQ = ctx.getCards(this, byType(Submission), realms, live);
    this.attendanceQ = ctx.getCards(
      this,
      byType(AttendanceRecord),
      realms,
      live,
    );
    this.attemptsQ = ctx.getCards(this, byType(QuizAttempt), realms, live);
    this.threadsQ = ctx.getCards(
      this,
      byLink(Thread, 'about.id'),
      realms,
      live,
    );
    this.learnersQ = ctx.getCards(this, byType(Learner), realms, live);
    this.authoritiesQ = ctx.getCards(
      this,
      byType(CertificationAuthority),
      realms,
      live,
    );
    // Touch every resource here, in this component's own computation. The
    // search resource is created lazily on first read; if that first read
    // happens inside a nested child (BoxelSelect options), its `modify`
    // writes a tracked property mid-render and Ember asserts.
    for (let q of [
      this.enrollmentsQ,
      this.submissionsQ,
      this.attendanceQ,
      this.attemptsQ,
      this.threadsQ,
      this.learnersQ,
      this.authoritiesQ,
    ]) {
      void q?.instances;
    }
  }

  get cohortId(): string | undefined {
    return this.args.cohort?.id;
  }
  // Cached so getCards sees the same realms array on every read.
  @cached
  get realms(): string[] | undefined {
    let url = this.args.cohort?.[realmURL];
    return url ? [url.href] : undefined;
  }
  get realm(): string | undefined {
    return this.realms?.[0];
  }
  get course() {
    return this.args.cohort?.course;
  }
  // Who acts when the host did not say: the cohort's lead instructor, else its first instructor.
  get actor(): any | undefined {
    if (this.args.actor) return this.args.actor;
    let list = (this.args.cohort?.instructors ?? []) as any[];
    let lead = list.find((i) => i?.role === 'lead') ?? list[0];
    return lead?.instructor;
  }

  get enrollments(): any[] {
    return ((this.enrollmentsQ?.instances ?? []) as any[]).filter(Boolean);
  }
  get enrollmentIds(): Set<string> {
    return new Set(this.enrollments.map((e) => e.id));
  }
  get submissions(): any[] {
    return ((this.submissionsQ?.instances ?? []) as any[]).filter(
      (s) => s && this.enrollmentIds.has(s.enrollment?.id),
    );
  }
  get attendance(): any[] {
    return ((this.attendanceQ?.instances ?? []) as any[]).filter(
      (r) => r && this.enrollmentIds.has(r.enrollment?.id),
    );
  }
  get attempts(): any[] {
    return ((this.attemptsQ?.instances ?? []) as any[]).filter(
      (a) => a && this.enrollmentIds.has(a.enrollment?.id),
    );
  }
  get threads(): any[] {
    return ((this.threadsQ?.instances ?? []) as any[]).filter(Boolean);
  }
  get thread(): any | undefined {
    return this.threads
      .slice()
      .sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0))[0];
  }
  get learners(): any[] {
    return ((this.learnersQ?.instances ?? []) as any[]).filter(Boolean);
  }
  get unenrolledLearners(): any[] {
    let taken = new Set(
      this.enrollments
        .filter((e) => e.enrollmentStatus !== 'withdrawn')
        .map((e) => e.learner?.id),
    );
    return this.learners.filter((l) => !taken.has(l.id));
  }
  get authority(): any | undefined {
    return (
      this.args.authority ?? ((this.authoritiesQ?.instances ?? []) as any[])[0]
    );
  }

  get modules(): any[] {
    return ((this.course?.modules ?? []) as any[])
      .filter(Boolean)
      .sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
  }
  get releasedIds(): string[] {
    return releasedModuleIds(this.args.cohort);
  }
  get releasedModules(): any[] {
    return this.modules.filter((m) => this.releasedIds.includes(m.id));
  }
  get unreleasedModules(): any[] {
    return this.modules.filter((m) => !this.releasedIds.includes(m.id));
  }
  get nextModule(): any | undefined {
    return this.unreleasedModules[0];
  }
  get releasedAssignments(): any[] {
    return this.releasedModules.flatMap((m) =>
      (m.assignments ?? []).filter(Boolean),
    );
  }
  get releasedQuizzes(): any[] {
    return this.releasedModules.flatMap((m) =>
      (m.quizzes ?? []).filter(Boolean),
    );
  }
  get liveLessons(): any[] {
    return this.releasedModules
      .flatMap((m) => (m.lessons ?? []).filter(Boolean))
      .filter((l) => l.kind === 'live')
      .sort(
        (a, b) =>
          new Date(a.liveSessionAt ?? 0).getTime() -
          new Date(b.liveSessionAt ?? 0).getTime(),
      );
  }
  get weeks() {
    return buildCohortWeeks(this.args.cohort);
  }
  get today() {
    return todayPosition(
      this.args.cohort?.term?.start,
      this.args.cohort?.term?.end,
    );
  }
  get thisWeek(): TimelineWeek | undefined {
    if (this.selectedWeek) return this.selectedWeek;
    let idx = this.today.index;
    return idx == null ? this.weeks[0] : this.weeks[idx];
  }
  get awaiting(): any[] {
    return this.submissions.filter((s) => s.submissionStatus === 'submitted');
  }
  get activeCount() {
    return this.enrollments.filter((e) => e.enrollmentStatus === 'active')
      .length;
  }
  get completedCount() {
    return this.enrollments.filter((e) => e.enrollmentStatus === 'completed')
      .length;
  }
  get isRunning() {
    return this.args.cohort?.status === 'running';
  }
  get moduleOptions() {
    return this.unreleasedModules.map((m) => ({
      value: m.id as string,
      label: m.cardTitle as string,
    }));
  }
  get selectedModuleId(): string | undefined {
    return this.releaseModuleId ?? this.nextModule?.id;
  }
  get learnerOptions() {
    return this.unenrolledLearners.map((l) => ({
      value: l.id as string,
      label: (l.name ?? l.cardTitle) as string,
    }));
  }

  get tabOptions() {
    return TABS.map((t) => {
      let n =
        t.id === 'gradebook'
          ? this.awaiting.length
          : t.id === 'learners'
            ? this.activeCount
            : 0;
      return { value: t.id, label: n ? `${t.label} (${n})` : t.label };
    });
  }

  setTab = (t: string) => (this.tab = t as Tab);
  isTab = (t: Tab) => this.tab === t;
  selectWeek = (w: TimelineWeek) => (this.selectedWeek = w);
  open = (card: any) => this.args.onOpenCard?.(card);
  pickSubmission = (s: any) => {
    this.selectedSubmission = s;
    this.tab = 'gradebook';
  };
  clearSubmission = () => (this.selectedSubmission = undefined);
  setReleaseModule = (id: string) => (this.releaseModuleId = id);
  setEnrollLearner = (id: string) =>
    (this.enrollLearner = this.unenrolledLearners.find((l) => l.id === id));
  setPostBody = (v: string) => (this.postBody = v);
  enrollmentHue = (e: any) =>
    statusHue(EnrollmentStatusField, e.enrollmentStatus);
  learnerLabel = (l: any) => l?.name ?? '';

  private async runCommand(key: string, fn: () => Promise<any>) {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      this.error = 'Commands are unavailable in this mode';
      return;
    }
    this.busy = key;
    this.error = undefined;
    this.notice = undefined;
    try {
      let res = await fn();
      this.notice = res?.message ?? 'Done';
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = undefined;
    }
  }

  release = () =>
    this.runCommand('release', async () => {
      let mod = this.unreleasedModules.find(
        (m) => m.id === (this.releaseModuleId ?? this.nextModule?.id),
      );
      if (!mod) throw new Error('Pick a module to release');
      return new ReleaseModuleCommand(this.args.context.commandContext).execute(
        {
          cohort: this.args.cohort,
          module: mod,
          releasedBy: this.actor,
        } as any,
      );
    });

  enroll = () =>
    this.runCommand('enroll', async () => {
      if (!this.enrollLearner) throw new Error('Pick a learner to enrol');
      let res = await new EnrollLearnerCommand(
        this.args.context.commandContext,
      ).execute({
        cohort: this.args.cohort,
        learner: this.enrollLearner,
        existingEnrollments: this.enrollments,
        realm: this.realm,
      } as any);
      this.enrollLearner = undefined;
      return res;
    });

  issue = (enrollment: any) =>
    this.runCommand(`issue-${enrollment.id}`, async () => {
      if (!this.authority)
        throw new Error(
          'No certification authority in this realm — create one first',
        );
      return new IssueCertificateCommand(
        this.args.context.commandContext,
      ).execute({
        enrollment,
        authority: this.authority,
        issuedBy: this.actor,
        submissions: this.submissions,
        attendanceRecords: this.attendance,
        quizAttempts: this.attempts,
        realm: this.realm,
      } as any);
    });

  post = () =>
    this.runCommand('post', async () => {
      if (!this.actor)
        throw new Error('No author — set the workspace actor to post');
      let res = await new PostToThreadCommand(
        this.args.context.commandContext,
      ).execute({
        thread: this.thread,
        about: this.args.cohort,
        title: `${this.args.cohort?.cardTitle} · discussion`,
        author: this.actor,
        body: this.postBody,
        realm: this.realm,
      } as any);
      this.postBody = '';
      return res;
    });

  isBusy = (key: string) => this.busy === key;

  <template>
    <div class='ws' ...attributes>
      <Tabs
        @options={{this.tabOptions}}
        @value={{this.tab}}
        @onValueChange={{this.setTab}}
      />

      {{#if this.error}}<Alert @tone='danger'>{{this.error}}</Alert>{{/if}}
      {{#if this.notice}}<Alert @tone='success'>{{this.notice}}</Alert>{{/if}}

      {{#if (this.isTab 'week')}}
        <section class='panel'>
          <CohortTimeline
            @weeks={{this.weeks}}
            @todayIndex={{this.today.index}}
            @todayFraction={{this.today.fraction}}
            @onSelectWeek={{this.selectWeek}}
            @selectedIndex={{this.thisWeek.index}}
          />
        </section>
        <div class='two'>
          <section class='panel'>
            <h3 class='sec'>{{if
                this.thisWeek
                (concat 'Week ' this.thisWeek.index ' · ' this.thisWeek.label)
                'No term'
              }}</h3>
            {{#if this.thisWeek.marks.length}}
              <ul class='marks'>
                {{#each this.thisWeek.marks as |m|}}
                  <li class='mark {{m.kind}}'>
                    <span class='mk'>{{kindLabel m.kind}}</span>
                    <span class='ml'>{{m.label}}</span>
                    <span class='md'>{{fmtDay m.date}}</span>
                  </li>
                {{/each}}
              </ul>
            {{else}}
              <p class='muted'>Nothing scheduled this week.</p>
            {{/if}}
          </section>
          <section class='panel action'>
            <h3 class='sec'>Release</h3>
            {{#if this.isRunning}}
              {{#if this.unreleasedModules.length}}
                <Select
                  @options={{this.moduleOptions}}
                  @value={{this.selectedModuleId}}
                  @onChange={{this.setReleaseModule}}
                  @placeholder='Choose a module'
                  @label='Module to release'
                />
                <Button
                  class='cta'
                  @tone='primary'
                  @appearance='accent'
                  @busy={{this.isBusy 'release'}}
                  @disabled={{this.isBusy 'release'}}
                  {{on 'click' this.release}}
                >Release module</Button>
                <p class='muted small'>{{this.releasedIds.length}}
                  of
                  {{this.modules.length}}
                  released. Next planned:
                  {{if this.nextModule this.nextModule.cardTitle '—'}}.</p>
              {{else}}
                <p class='muted'>Every module is released.</p>
              {{/if}}
            {{else}}
              <p class='muted'>Cohort is
                {{@cohort.status}}
                — releases happen while running.</p>
            {{/if}}
          </section>
        </div>
        <section class='panel'>
          <h3 class='sec'>Outline</h3>
          <CourseOutline
            @modules={{this.modules}}
            @releasedIds={{this.releasedIds}}
            @collapsed={{true}}
            @onOpenModule={{this.open}}
          />
        </section>

      {{else if (this.isTab 'learners')}}
        <section class='panel action row'>
          <Select
            @options={{this.learnerOptions}}
            @value={{this.enrollLearner.id}}
            @onChange={{this.setEnrollLearner}}
            @placeholder='Add a learner'
            @label='Learner to enrol'
          />
          <Button
            class='cta'
            @tone='primary'
            @appearance='accent'
            @busy={{this.isBusy 'enroll'}}
            @disabled={{or (this.isBusy 'enroll') (not this.enrollLearner)}}
            {{on 'click' this.enroll}}
          >Enrol</Button>
          <span class='muted small'>{{this.activeCount}}
            active ·
            {{this.completedCount}}
            completed{{#if @cohort.capacity}}
              ·
              {{@cohort.capacity}}
              seats{{/if}}</span>
        </section>
        {{#if this.enrollments.length}}
          <ol class='roster'>
            {{#each this.enrollments as |e|}}
              <li class='seat'>
                <header class='seat-head'>
                  <Button
                    class='seat-name'
                    @appearance='link'
                    {{on 'click' (fn this.open e)}}
                  >{{e.learnerName}}</Button>
                  <StatePill
                    @label={{e.statusLabel}}
                    @hue={{this.enrollmentHue e}}
                    @dot={{true}}
                  />
                  {{#if e.certificate}}
                    <span class='cert'>{{e.certificate.number}}</span>
                  {{else if (eq e.enrollmentStatus 'active')}}
                    <Button
                      class='cta'
                      @tone='neutral'
                      @appearance='outlined'
                      @size='xs'
                      @busy={{this.isBusy (concat 'issue-' e.id)}}
                      {{on 'click' (fn this.issue e)}}
                    >Issue certificate</Button>
                  {{/if}}
                </header>
                <LearnerProgress
                  @enrollment={{e}}
                  @context={{@context}}
                  @compact={{true}}
                />
              </li>
            {{/each}}
          </ol>
        {{else}}
          <EmptyState
            @size='s'
            @title='No learners yet'
            @message='Add the first one above.'
          />
        {{/if}}

      {{else if (this.isTab 'gradebook')}}
        <div class='gb-layout {{if this.selectedSubmission "with-grader"}}'>
          <Gradebook
            @enrollments={{this.enrollments}}
            @assignments={{this.releasedAssignments}}
            @submissions={{this.submissions}}
            @quizzes={{this.releasedQuizzes}}
            @attempts={{this.attempts}}
            @gradeScale={{this.course.gradeScale}}
            @onGradeSubmission={{this.pickSubmission}}
            @onOpenSubmission={{this.pickSubmission}}
            @onOpenEnrollment={{this.open}}
          />
          {{#if this.selectedSubmission}}
            <aside class='grader'>
              <div class='grader-bar'>
                <Button
                  @appearance='link'
                  @size='xs'
                  {{on 'click' (fn this.open this.selectedSubmission)}}
                >Open submission ↗</Button>
                <Button
                  @appearance='link'
                  @size='xs'
                  {{on 'click' this.clearSubmission}}
                >Close</Button>
              </div>
              <RubricGrader
                @submission={{this.selectedSubmission}}
                @context={{@context}}
                @gradedBy={{this.actor}}
                @onGraded={{this.clearSubmission}}
              />
            </aside>
          {{/if}}
        </div>

      {{else if (this.isTab 'attendance')}}
        <AttendanceGrid
          @cohort={{@cohort}}
          @enrollments={{this.enrollments}}
          @lessons={{this.liveLessons}}
          @records={{this.attendance}}
          @context={{@context}}
          @markedBy={{this.actor}}
        />

      {{else}}
        <section class='panel'>
          {{#if this.thread}}
            <h3 class='sec'>{{this.thread.cardTitle}}
              ·
              {{this.thread.postCount}}
              posts</h3>
            <div class='posts'>
              {{#each this.thread.posts as |msg|}}
                <div class='post'>
                  <span class='ini'>{{msg.authorInitials}}</span>
                  <div>
                    <div class='post-head'><b>{{msg.authorName}}</b>
                      <span class='muted small'>{{fmtWhen
                          msg.postedAt
                        }}</span></div>
                    <p class='post-body'>{{msg.body}}</p>
                  </div>
                </div>
              {{/each}}
            </div>
          {{else}}
            <p class='muted'>No discussion yet. The first post opens the cohort
              thread.</p>
          {{/if}}
          <div class='compose'>
            <Textarea
              @value={{this.postBody}}
              @onInput={{this.setPostBody}}
              @placeholder='Write to the cohort…'
            />
            <Button
              class='cta'
              @tone='primary'
              @appearance='accent'
              @busy={{this.isBusy 'post'}}
              @disabled={{or (this.isBusy 'post') (not this.postBody)}}
              {{on 'click' this.post}}
            >Post</Button>
          </div>
        </section>
      {{/if}}
    </div>
    <style scoped>
      .cta {
        min-height: 2.75rem;
      }
      .ws {
        container-type: inline-size;
        display: grid;
        gap: var(--boxel-sp);
        color: var(--foreground);
      }
      .panel {
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .panel.action {
        display: grid;
        gap: var(--boxel-sp-xs);
        align-content: start;
      }
      .panel.row {
        grid-template-columns: minmax(12rem, 20rem) auto 1fr;
        align-items: center;
      }
      .two {
        display: grid;
        grid-template-columns: 1.4fr 1fr;
        gap: var(--boxel-sp);
      }
      .sec {
        margin: 0 0 var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--muted-foreground);
      }
      .marks {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .mark {
        display: grid;
        grid-template-columns: 6.5rem 1fr auto;
        gap: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-sm);
        padding: var(--boxel-sp-4xs) 0;
        border-left: 0.1875rem solid var(--border);
        padding-left: var(--boxel-sp-xs);
      }
      .mark.release {
        border-left-color: var(--primary);
      }
      .mark.due {
        border-left-color: var(--warning);
      }
      .mark.live {
        border-left-color: var(--chart-2);
      }
      .mark.quiz {
        border-left-color: var(--chart-4);
      }
      .mk {
        font-size: var(--boxel-font-size-xs);
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--muted-foreground);
      }
      .ml {
        font-weight: 600;
      }
      .md {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .roster {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .seat {
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .seat-head {
        display: flex;
        gap: var(--boxel-sp-sm);
        align-items: center;
      }
      .seat-name {
        font-weight: 700;
        margin-right: auto;
      }
      .cert {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.04em;
        color: var(--success-ink);
      }
      .gb-layout {
        display: grid;
        gap: var(--boxel-sp);
      }
      .gb-layout.with-grader {
        grid-template-columns: minmax(0, 1.2fr) minmax(22rem, 1fr);
        align-items: start;
      }
      .grader {
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        position: sticky;
        top: var(--boxel-sp);
      }
      .grader-bar {
        display: flex;
        justify-content: space-between;
        margin-bottom: var(--boxel-sp-xs);
      }
      .posts {
        display: grid;
        gap: var(--boxel-sp-sm);
        margin-bottom: var(--boxel-sp);
      }
      .post {
        display: grid;
        grid-template-columns: auto 1fr;
        gap: var(--boxel-sp-xs);
      }
      .ini {
        width: 1.75rem;
        height: 1.75rem;
        display: grid;
        place-items: center;
        border-radius: 50%;
        background: color-mix(in oklab, var(--primary) 14%, var(--card));
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .post-body {
        margin: 0.125rem 0 0;
        font-size: var(--boxel-font-size-sm);
        white-space: pre-wrap;
      }
      .compose {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: var(--boxel-sp-xs);
        align-items: end;
      }
      .muted {
        margin: 0;
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-sm);
      }
      .small {
        font-size: var(--boxel-font-size-xs);
      }
      @container (width <= 47.5rem) {
        .two,
        .gb-layout.with-grader {
          grid-template-columns: 1fr;
        }
        .panel.row {
          grid-template-columns: 1fr;
        }
        .grader {
          position: static;
        }
      }
    </style>
  </template>
}

const KIND_LABEL: Record<string, string> = {
  release: 'Release',
  due: 'Due',
  live: 'Live',
  quiz: 'Quiz',
};
function kindLabel(k: string) {
  return KIND_LABEL[k] ?? k;
}
function fmtDay(d: Date) {
  return d.toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}
function fmtWhen(d?: Date | string | null) {
  if (!d) return '';
  return new Date(d).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}
function eq(a: unknown, b: unknown) {
  return a === b;
}
function or(...v: unknown[]) {
  return v.some(Boolean);
}
function not(v: unknown) {
  return !v;
}
function concat(...parts: unknown[]) {
  return parts.map((p) => (p == null ? '' : String(p))).join('');
}

export default CohortWorkspace;
