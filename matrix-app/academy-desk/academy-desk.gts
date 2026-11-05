import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import type Owner from '@ember/owner';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';
import { eq } from '@cardstack/boxel-ui/helpers';
import SchoolIcon from '@cardstack/boxel-icons/school';
import PlusIcon from '@cardstack/boxel-icons/plus';
import BookIcon from '@cardstack/boxel-icons/book-open';
import CalendarIcon from '@cardstack/boxel-icons/calendar';
import UsersIcon from '@cardstack/boxel-icons/users';
import AwardIcon from '@cardstack/boxel-icons/award';
import HomeIcon from '@cardstack/boxel-icons/home';

import { Avatar } from '../../ui-component/components/avatar';
import { Button } from '../../ui-component/components/button';
import { FitTile } from '../../ui-component/components/fit-tile';
import { Card } from '../../ui-component/components/card';
import {
  DataTable,
  type DataColumn,
} from '../../ui-component/components/data-table';
import { EmptyState } from '../../ui-component/components/empty-state';
import { LoadingState } from '../../ui-component/components/loading-state';
import { ProgressBar } from '../../ui-component/components/progress-bar';
import { SearchInput } from '../../ui-component/components/search-input';
import { FilterChips } from '../../ui-component/components/filter-chips';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '../../ui-component/components/sidebar';
import { StatusChip } from '../../ui-component/components/status-chip';
import {
  PageScaffold,
  type PageStat,
} from '../../ui-component/components/page-scaffold';
import { CertificationAuthority } from '../audit/certification-authority';
import { Employee } from '../hr/employee';
import { Course, CourseStatusField, COURSE_STATUSES } from '../academy/course';
import { Cohort, CohortStatusField, COHORT_STATUSES } from '../academy/cohort';
import { Learner } from '../academy/learner';
import { Enrollment } from '../academy/enrollment';
import { Submission } from '../academy/submission';
import {
  Certificate,
  CertificateStatusField,
  CERTIFICATE_STATUSES,
} from '../academy/certificate';
import { statusHue, type StatusOption } from '../../fields/status/status';
import { CohortWorkspace } from '../academy/components/cohort-workspace';

const asOptions = (options: StatusOption[]) =>
  options.map((o) => ({ value: o.value, label: o.label ?? o.value }));

type Tab = 'home' | 'courses' | 'cohorts' | 'learners' | 'certificates';

const TAB_LABELS: Record<Tab, string> = {
  home: 'Home',
  courses: 'Courses',
  cohorts: 'Cohorts',
  learners: 'Learners',
  certificates: 'Certificates',
};

const DAY_MS = 24 * 60 * 60 * 1000;

function daysSince(value?: Date | string | null): number {
  if (!value) {
    return 0;
  }
  let time = new Date(value).getTime();
  return Number.isNaN(time)
    ? 0
    : Math.max(0, Math.floor((Date.now() - time) / DAY_MS));
}

function toDate(value?: Date | string | null): Date | undefined {
  if (!value) {
    return undefined;
  }
  let date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

// Issued certificates carry a timestamp; show the local calendar day.
function formatIssued(value?: Date | string | null): string {
  let date = toDate(value);
  return date
    ? date.toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      })
    : '—';
}

function dayLabel(value?: Date | string | null): string {
  let date = toDate(value);
  return date
    ? date.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })
    : '—';
}

function labelOf(
  options: { value: string; label: string }[],
  value?: string | null,
): string {
  return options.find((o) => o.value === value)?.label ?? value ?? '—';
}

function startOf(cohort: any): number {
  return toDate(cohort.term?.start)?.getTime() ?? 0;
}

// The Cohort Workspace and the record cards are the children; this desk only
// lists them. Every row and button is a real field or action of the record.
class AcademyDeskIsolated extends Component<typeof AcademyDesk> {
  @tracked tab: Tab = 'home';
  @tracked openCohort: Cohort | undefined;
  @tracked query = '';
  @tracked filter = 'all';
  private coursesQ: ReturnType<getCards> | undefined;
  private cohortsQ: ReturnType<getCards> | undefined;
  private learnersQ: ReturnType<getCards> | undefined;
  private certsQ: ReturnType<getCards> | undefined;
  private enrollmentsQ: ReturnType<getCards> | undefined;
  private submissionsQ: ReturnType<getCards> | undefined;
  private cachedRealms: string[] | undefined;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    let ctx = this.args.context;
    if (!ctx?.getCards) {
      return;
    }
    let byType = (cls: typeof CardDef) => () => {
      let ref = identifyCard(cls);
      return ref ? { filter: { type: ref } } : undefined;
    };
    let realmList = this.realms;
    let realms = () => realmList;
    this.coursesQ = ctx.getCards(this, byType(Course), realms, {
      isLive: true,
    });
    this.cohortsQ = ctx.getCards(this, byType(Cohort), realms, {
      isLive: true,
    });
    this.learnersQ = ctx.getCards(this, byType(Learner), realms, {
      isLive: true,
    });
    this.certsQ = ctx.getCards(this, byType(Certificate), realms, {
      isLive: true,
    });
    this.enrollmentsQ = ctx.getCards(this, byType(Enrollment), realms, {
      isLive: true,
    });
    this.submissionsQ = ctx.getCards(this, byType(Submission), realms, {
      isLive: true,
    });
  }

  // getCards needs a stable realms reference across recomputes.
  get realms(): string[] {
    if (!this.cachedRealms) {
      let url = (this.args.model as any)?.[realmURL];
      this.cachedRealms = url ? [url.href] : [];
    }
    return this.cachedRealms;
  }

  private instancesOf(query: ReturnType<getCards> | undefined): any[] {
    return ((query?.instances ?? []) as any[]).filter(Boolean);
  }
  get courses() {
    return this.instancesOf(this.coursesQ);
  }
  get cohorts() {
    return this.instancesOf(this.cohortsQ);
  }
  get learners() {
    return this.instancesOf(this.learnersQ);
  }
  get certificates() {
    return this.instancesOf(this.certsQ);
  }
  get enrollments() {
    return this.instancesOf(this.enrollmentsQ);
  }
  get submissions() {
    return this.instancesOf(this.submissionsQ);
  }

  // ── home data ───────────────────────────────────────────────────────────
  get running() {
    return this.cohorts
      .filter((c) => c.status === 'running')
      .sort((a, b) => startOf(a) - startOf(b));
  }
  get planned() {
    return this.cohorts
      .filter((c) => c.status === 'planned')
      .sort((a, b) => startOf(a) - startOf(b));
  }
  get closed() {
    return this.cohorts.filter((c) => c.status === 'closed');
  }
  get activeLearners() {
    return this.enrollments.filter((e) => e.enrollmentStatus === 'active')
      .length;
  }
  // Submissions waiting for a grade, oldest first.
  get awaiting() {
    return this.submissions
      .filter((s) => s.submissionStatus === 'submitted')
      .sort(
        (a, b) =>
          (toDate(a.submittedAt)?.getTime() ?? 0) -
          (toDate(b.submittedAt)?.getTime() ?? 0),
      );
  }

  // The tab's own query, so a list never shows "0" before it has loaded.
  get tabLoading(): boolean {
    let query = {
      home: undefined,
      courses: this.coursesQ,
      cohorts: this.cohortsQ,
      learners: this.learnersQ,
      certificates: this.certsQ,
    }[this.tab];
    return Boolean(query?.isLoading);
  }

  get loadingLabel(): string {
    return `Loading ${TAB_LABELS[this.tab].toLowerCase()}…`;
  }

  // ── list tabs: one filter (status, or organisation for learners) and search
  get filterSpec():
    | {
        rows: any[];
        read: (row: any) => string | undefined;
        options: { value: string; label: string }[];
      }
    | undefined {
    switch (this.tab) {
      case 'courses':
        return {
          rows: this.courses,
          read: (c) => c.status,
          options: asOptions(COURSE_STATUSES),
        };
      case 'cohorts':
        return {
          rows: this.cohorts,
          read: (c) => c.status,
          options: asOptions(COHORT_STATUSES),
        };
      case 'learners':
        return {
          rows: this.learners,
          read: (l) => l.organisation,
          options: [
            ...new Set(
              this.learners
                .map((l) => l.organisation)
                .filter(Boolean) as string[],
            ),
          ]
            .sort()
            .map((o) => ({ value: o, label: o })),
        };
      case 'certificates':
        return {
          rows: this.certificates,
          read: (c) => c.certStatus,
          options: asOptions(CERTIFICATE_STATUSES),
        };
      default:
        return undefined;
    }
  }

  get chips() {
    let spec = this.filterSpec;
    if (!spec) {
      return [];
    }
    return [
      { id: 'all', label: 'All', count: spec.rows.length },
      ...spec.options.map((o) => ({
        id: o.value,
        label: o.label,
        count: spec.rows.filter((r) => spec.read(r) === o.value).length,
      })),
    ];
  }

  get tabRows(): any[] {
    let spec = this.filterSpec;
    if (!spec) {
      return [];
    }
    let q = this.query.trim().toLowerCase();
    return spec.rows.filter((r) => {
      if (this.filter !== 'all' && spec.read(r) !== this.filter) {
        return false;
      }
      if (!q) {
        return true;
      }
      return [
        r.cardTitle,
        r.code,
        r.title,
        r.learnerName,
        r.organisation,
        r.number,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase()
        .includes(q);
    });
  }

  // ── header ──────────────────────────────────────────────────────────────
  get pageTitle() {
    return TAB_LABELS[this.tab];
  }

  get subtitle(): string {
    if (this.tab === 'home') {
      return `${this.running.length} ${this.running.length === 1 ? 'cohort' : 'cohorts'} running · ${this.awaiting.length} ${this.awaiting.length === 1 ? 'submission' : 'submissions'} waiting`;
    }
    if (this.tabLoading) {
      return 'Loading…';
    }
    return `${this.chips[0]?.count ?? 0} in this realm`;
  }

  get stats(): PageStat[] {
    if (this.tab === 'home') {
      let oldest = daysSince(this.awaiting[0]?.submittedAt);
      return [
        {
          label: 'Cohorts running',
          value: this.running.length,
          hint: `of ${this.cohorts.length} cohorts`,
        },
        {
          label: 'Active learners',
          value: this.activeLearners,
          hint: 'active enrollments',
        },
        {
          label: 'Awaiting grade',
          value: this.awaiting.length,
          hintTone: 'warning',
          hint: this.awaiting.length
            ? `oldest ${oldest} ${oldest === 1 ? 'day' : 'days'} ago`
            : 'nothing waiting',
        },
        {
          label: 'Planned',
          value: this.planned.length,
          hint: this.planned[0]
            ? `next starts ${dayLabel(this.planned[0].term?.start)}`
            : 'none scheduled',
        },
        {
          label: 'Closed',
          value: this.closed.length,
          hint: 'closed cohorts',
        },
      ];
    }
    return this.chips.map((c) => ({
      label: c.id === 'all' ? 'Total' : c.label,
      value: c.count,
    }));
  }

  get primaryLabel(): string | undefined {
    return {
      home: 'New cohort',
      courses: 'New course',
      cohorts: 'New cohort',
      learners: 'New learner',
      certificates: undefined,
    }[this.tab];
  }

  get primaryType(): typeof CardDef | undefined {
    return {
      home: Cohort,
      courses: Course,
      cohorts: Cohort,
      learners: Learner,
      certificates: undefined,
    }[this.tab] as typeof CardDef | undefined;
  }

  get tabNoun() {
    return this.tab.toLowerCase();
  }

  get chipOptions() {
    return this.chips.map((c) => ({
      value: c.id,
      label: c.label,
      count: c.count,
    }));
  }

  get showSearch() {
    return this.tab !== 'home';
  }

  // ── navigation ──────────────────────────────────────────────────────────
  go = (tab: Tab) => {
    this.tab = tab;
    this.openCohort = undefined;
    this.query = '';
    this.filter = 'all';
  };
  showCohort = (cohort: Cohort) => {
    this.openCohort = cohort;
    this.tab = 'cohorts';
  };
  backToCohorts = () => {
    this.openCohort = undefined;
  };
  setQuery = (value: string) => {
    this.query = value;
  };
  setFilter = (value: string) => {
    this.filter = value;
  };
  view = (card: CardDef | URL | undefined) => {
    if (card) {
      this.args.viewCard?.(card as CardDef, 'isolated');
    }
  };
  // The host's createCard opens a new instance of the type, in edit mode, in
  // this realm.
  createFor = (cls: typeof CardDef | undefined) => () => {
    let ref = cls ? identifyCard(cls) : undefined;
    let realm = this.realms[0];
    if (!ref || !realm) {
      return;
    }
    this.args.createCard?.(ref, undefined, { realmURL: new URL(realm) });
  };
  primary = () => {
    this.createFor(this.primaryType)();
  };
  gradeOldest = () => {
    if (this.awaiting[0]) {
      this.view(this.awaiting[0]);
    }
  };

  get sidebarItems() {
    return [
      { id: 'home' as Tab, icon: HomeIcon, badge: undefined },
      { id: 'courses' as Tab, icon: BookIcon, badge: this.courses.length },
      { id: 'cohorts' as Tab, icon: CalendarIcon, badge: this.cohorts.length },
      { id: 'learners' as Tab, icon: UsersIcon, badge: this.learners.length },
      {
        id: 'certificates' as Tab,
        icon: AwardIcon,
        badge: this.certificates.length,
      },
    ].map((item) => ({
      ...item,
      label: TAB_LABELS[item.id],
      badge: item.badge === undefined ? undefined : String(item.badge),
    }));
  }

  // ── cell readings ───────────────────────────────────────────────────────
  courseHue = (c: any) => statusHue(CourseStatusField, c.status);
  cohortHue = (c: any) => statusHue(CohortStatusField, c.status);
  certHue = (c: any) => statusHue(CertificateStatusField, c.certStatus);
  courseLabel = (c: any) => labelOf(asOptions(COURSE_STATUSES), c.status);
  cohortLabel = (c: any) => labelOf(asOptions(COHORT_STATUSES), c.status);
  certLabel = (c: any) =>
    labelOf(asOptions(CERTIFICATE_STATUSES), c.certStatus);
  weekLabel = (c: any) =>
    `${c.currentWeek ? c.currentWeek : '—'}/${c.weekCount}`;
  pileSub = (s: any) =>
    `v${s.version ?? 1} · ${s.enrollment?.cohort?.cardTitle ?? ''}`;
  agoLabel = (d: any) => {
    let days = daysSince(d);
    return days >= 1 ? `${days}d ago` : 'today';
  };
  lateLabel = (s: any) =>
    s.isLate ? `${s.daysLate ?? 0} days late` : 'On time';
  lateTone = (s: any) => (s.isLate ? 'danger' : 'success');

  // ── table columns ───────────────────────────────────────────────────────
  runningColumns: DataColumn<any>[] = [
    { key: 'cohort', label: 'Cohort', width: '14rem' },
    {
      key: 'course',
      label: 'Course',
      value: (c: any) => c.courseCode,
      mono: true,
    },
    { key: 'lead', label: 'Lead', value: (c: any) => c.leadInstructorName },
    { key: 'week', label: 'Week' },
    {
      key: 'released',
      label: 'Released',
      align: 'end',
      value: (c: any) => c.releasedCount,
    },
    { key: 'status', label: 'Status' },
  ];
  pileColumns: DataColumn<any>[] = [
    { key: 'submission', label: 'Submission', width: '16rem' },
    {
      key: 'version',
      label: 'Version',
      value: (s: any) => `v${s.version ?? 1}`,
    },
    {
      key: 'submitted',
      label: 'Waiting',
      align: 'end',
      value: (s: any) => `${daysSince(s.submittedAt)}d`,
    },
    { key: 'late', label: 'Timing' },
  ];
  plannedColumns: DataColumn<any>[] = [
    { key: 'cohort', label: 'Cohort', width: '14rem' },
    {
      key: 'course',
      label: 'Course',
      value: (c: any) => c.courseCode,
      mono: true,
    },
    { key: 'term', label: 'Term', value: (c: any) => c.termLabel },
  ];
  homeCourseColumns: DataColumn<any>[] = [
    {
      key: 'code',
      label: 'Code',
      width: '6rem',
      value: (c: any) => c.code,
      mono: true,
    },
    { key: 'title', label: 'Course', value: (c: any) => c.cardTitle },
    { key: 'status', label: 'Status' },
  ];
  courseColumns: DataColumn<any>[] = [
    {
      key: 'title',
      label: 'Course',
      width: '17rem',
      value: (c: any) => c.cardTitle,
    },
    {
      key: 'code',
      label: 'Code',
      width: '6rem',
      value: (c: any) => c.code,
      mono: true,
    },
    { key: 'level', label: 'Level', value: (c: any) => c.levelLabel },
    {
      key: 'modules',
      label: 'Modules',
      align: 'end',
      value: (c: any) => c.moduleCount,
    },
    {
      key: 'credit',
      label: 'Credit',
      align: 'end',
      value: (c: any) => c.creditHours,
    },
    { key: 'status', label: 'Status' },
  ];
  cohortColumns: DataColumn<any>[] = [
    {
      key: 'name',
      label: 'Cohort',
      width: '14rem',
      value: (c: any) => c.cardTitle,
    },
    {
      key: 'course',
      label: 'Course',
      value: (c: any) => c.courseCode,
      mono: true,
    },
    { key: 'term', label: 'Term', value: (c: any) => c.termLabel },
    { key: 'week', label: 'Week', align: 'end', value: this.weekLabel },
    { key: 'status', label: 'Status' },
  ];
  learnerColumns: DataColumn<any>[] = [
    {
      key: 'name',
      label: 'Learner',
      width: '14rem',
      value: (l: any) => l.title,
    },
    { key: 'email', label: 'Email', value: (l: any) => l.email },
    { key: 'org', label: 'Organisation', value: (l: any) => l.organisation },
    { key: 'tz', label: 'Zone', value: (l: any) => l.timezone },
  ];
  certColumns: DataColumn<any>[] = [
    {
      key: 'number',
      label: 'Number',
      width: '10rem',
      value: (c: any) => c.number,
      mono: true,
    },
    { key: 'learner', label: 'Learner', value: (c: any) => c.learnerName },
    { key: 'course', label: 'Course', value: (c: any) => c.courseTitle },
    {
      key: 'letter',
      label: 'Final',
      align: 'end',
      value: (c: any) => c.finalLetter,
    },
    {
      key: 'issued',
      label: 'Issued',
      value: (c: any) => formatIssued(c.issuedAt),
    },
    { key: 'status', label: 'Status' },
  ];

  cardKey = (row: any) => row.id;

  <template>
    {{#if this.openCohort}}
      <Sidebar
        class='desk'
        @label='Academy'
        @collapsible='offcanvas'
        @width='14.5rem'
        @mobileBreakpoint={{760}}
        @shortcut={{false}}
      >
        <:header>
          <div class='brand'>
            <span class='mark' aria-hidden='true'>A</span>
            <div>
              <p class='brand-title'>{{@model.cardTitle}}</p>
              <p class='brand-sub'>{{if
                  @model.tagline
                  @model.tagline
                  'Course & cohort learning'
                }}</p>
            </div>
          </div>
        </:header>
        <:nav>
          <SidebarGroup @label='Academy'>
            {{#each this.sidebarItems as |item|}}
              <SidebarItem
                @label={{item.label}}
                @badge={{item.badge}}
                @active={{eq this.tab item.id}}
                @onClick={{fn this.go item.id}}
              ><:icon><item.icon
                    width='16'
                    height='16'
                    aria-hidden='true'
                  /></:icon></SidebarItem>
            {{/each}}
          </SidebarGroup>
        </:nav>
        <:default as |bar|>
          <main class='desk-main'>
            <PageScaffold
              @title={{this.openCohort.cardTitle}}
              @subtitle={{this.openCohort.termLabel}}
            >
              <:lead>
                <SidebarTrigger
                  @open={{bar.open}}
                  @onToggle={{bar.toggle}}
                  @controls={{bar.controls}}
                  @label='navigation'
                />
              </:lead>
              <:chips>
                <StatusChip
                  @value={{this.cohortLabel this.openCohort}}
                  @hue={{this.cohortHue this.openCohort}}
                />
              </:chips>
              <:actions>
                <Button
                  @tone='neutral'
                  @appearance='outlined'
                  @size='s'
                  @shape='pill'
                  {{on 'click' this.backToCohorts}}
                >← Cohorts</Button>
                <Button
                  @tone='neutral'
                  @appearance='outlined'
                  @size='s'
                  @shape='pill'
                  {{on 'click' (fn this.view this.openCohort)}}
                >Open card ↗</Button>
              </:actions>
              <:default>
                <CohortWorkspace
                  @cohort={{this.openCohort}}
                  @context={{@context}}
                  @actor={{@model.actor}}
                  @authority={{@model.authority}}
                  @onOpenCard={{this.view}}
                />
              </:default>
            </PageScaffold>
          </main>
        </:default>
      </Sidebar>
    {{else}}
      <Sidebar
        class='desk'
        @label='Academy'
        @collapsible='offcanvas'
        @width='14.5rem'
        @mobileBreakpoint={{760}}
        @shortcut={{false}}
      >
        <:header>
          <div class='brand'>
            <p class='brand-sub'>{{if
                @model.tagline
                @model.tagline
                'Course & cohort learning'
              }}</p>
            <p class='brand-title'>{{@model.cardTitle}}</p>
          </div>
        </:header>
        <:nav>
          <SidebarGroup @label='Academy'>
            {{#each this.sidebarItems as |item|}}
              <SidebarItem
                @label={{item.label}}
                @badge={{item.badge}}
                @active={{eq this.tab item.id}}
                @onClick={{fn this.go item.id}}
              ><:icon><item.icon
                    width='16'
                    height='16'
                    aria-hidden='true'
                  /></:icon></SidebarItem>
            {{/each}}
          </SidebarGroup>
        </:nav>
        <:footer>
          <p class='who' role='status'>
            {{#if @model.actor}}
              <span class='muted'>Acting as</span>
              <b>{{@model.actor.name}}</b>
            {{else}}
              <span class='warn'>No instructor set. Edit the desk to choose who
                is acting.</span>
            {{/if}}
          </p>
        </:footer>
        <:default as |bar|>
          <main class='desk-main'>
            <PageScaffold
              @title={{this.pageTitle}}
              @subtitle={{this.subtitle}}
              @stats={{this.stats}}
            >
              <:lead>
                <SidebarTrigger
                  @open={{bar.open}}
                  @onToggle={{bar.toggle}}
                  @controls={{bar.controls}}
                  @label='navigation'
                />
              </:lead>
              <:actions>
                {{#if this.primaryLabel}}
                  <Button
                    @tone='neutral'
                    @appearance='outlined'
                    @shape='pill'
                    {{on 'click' this.primary}}
                  ><PlusIcon
                      width='14'
                      height='14'
                      aria-hidden='true'
                    />{{this.primaryLabel}}</Button>
                {{/if}}
                {{#if (eq this.tab 'home')}}
                  <Button
                    @tone='primary'
                    @appearance='accent'
                    @shape='pill'
                    @disabled={{if this.awaiting.length false true}}
                    {{on 'click' this.gradeOldest}}
                  >Grade the oldest</Button>
                {{/if}}
              </:actions>
              <:default>
                {{#if this.showSearch}}
                  <div class='list-toolbar'>
                    <SearchInput
                      class='desk-search'
                      @size='s'
                      @controlId='academy-search'
                      @value={{this.query}}
                      @placeholder='Search {{this.tabNoun}}…'
                      @label='Search {{this.tabNoun}}'
                      @onInput={{this.setQuery}}
                    />
                    <FilterChips
                      @appearance='solid'
                      @size='s'
                      @label='Filter {{this.tabNoun}}'
                      @items={{this.chipOptions}}
                      @value={{this.filter}}
                      @onChange={{this.setFilter}}
                    />
                  </div>
                {{/if}}
                {{#if (eq this.tab 'home')}}
                  <div class='main-grid'>
                    <Card class='panel' @title='Running cohorts'>
                      <:action><span
                          class='meta'
                        >{{this.running.length}}</span></:action>
                      <:default>
                        <DataTable
                          @columns={{this.runningColumns}}
                          @rows={{this.running}}
                          @key={{this.cardKey}}
                          @label='Running cohorts'
                          @flush={{true}}
                          @columnMenu={{false}}
                          @sortable={{false}}
                          @striped={{false}}
                        >
                          <:empty><EmptyState
                              @size='s'
                              @texture={{false}}
                              @title='No cohorts running'
                              @message='Planned cohorts appear here once they start.'
                            /></:empty>
                          <:cell as |text row col|>
                            {{#if (eq col.key 'cohort')}}
                              <Button
                                @tone='primary'
                                @appearance='link'
                                @size='s'
                                {{on 'click' (fn this.showCohort row)}}
                              >{{row.cardTitle}}</Button>
                            {{else if (eq col.key 'week')}}
                              <ProgressBar
                                aria-label='Week'
                                @value={{row.currentWeek}}
                                @max={{row.weekCount}}
                                @steps={{true}}
                                @count={{this.weekLabel row}}
                              />
                            {{else if (eq col.key 'status')}}
                              <StatusChip
                                @value={{this.cohortLabel row}}
                                @hue={{this.cohortHue row}}
                              />
                            {{else}}
                              {{text}}
                            {{/if}}
                          </:cell>
                        </DataTable>
                      </:default>
                    </Card>

                    <Card class='panel' @title='Grading pile'>
                      <:action><span class='meta'>{{this.awaiting.length}}
                          waiting</span></:action>
                      <:default>
                        {{#if this.awaiting.length}}
                          <ol class='rows'>
                            {{#each this.awaiting key='id' as |row|}}
                              <li class='row'>
                                <span class='row-main'>
                                  <span class='row-title'><Button
                                      @tone='primary'
                                      @appearance='link'
                                      @size='s'
                                      {{on 'click' (fn this.view row)}}
                                    >{{row.learnerName}}</Button>
                                    ·
                                    {{row.assignmentTitle}}</span>
                                  <span class='row-sub'>{{this.pileSub
                                      row
                                    }}</span>
                                </span>
                                <span class='row-end'>{{this.agoLabel
                                    row.submittedAt
                                  }}{{#if row.isLate}}
                                    ·
                                    <span class='late'>{{row.daysLate}}d late</span>{{/if}}</span>
                              </li>
                            {{/each}}
                          </ol>
                        {{else}}
                          <EmptyState
                            @size='s'
                            @texture={{false}}
                            @title='Nothing waiting for a grade'
                            @message='New submissions land here oldest first.'
                          />
                        {{/if}}
                      </:default>
                    </Card>
                  </div>

                  <div class='ops-grid'>
                    <Card class='panel' @title='Planned'>
                      <:action><span
                          class='meta'
                        >{{this.planned.length}}</span></:action>
                      <:default>
                        {{#if this.planned.length}}
                          <ul class='rows'>
                            {{#each this.planned key='id' as |row|}}
                              <li class='row'>
                                <span class='row-main row-inline'><Button
                                    @tone='primary'
                                    @appearance='link'
                                    @size='s'
                                    {{on 'click' (fn this.showCohort row)}}
                                  >{{row.cardTitle}}</Button>
                                  <span
                                    class='mono muted'
                                  >{{row.courseCode}}</span></span>
                                <span class='row-end'>{{row.termLabel}}</span>
                              </li>
                            {{/each}}
                          </ul>
                        {{else}}
                          <EmptyState
                            @size='s'
                            @texture={{false}}
                            @title='No planned cohorts'
                            @message='Schedule one with New cohort.'
                          />
                        {{/if}}
                      </:default>
                    </Card>

                    <Card class='panel' @title='Courses'>
                      <:action><span
                          class='meta'
                        >{{this.courses.length}}</span></:action>
                      <:default>
                        {{#if this.courses.length}}
                          <ul class='rows'>
                            {{#each this.courses key='id' as |row|}}
                              <li class='row'>
                                <span class='row-main row-inline'><span
                                    class='mono muted'
                                  >{{row.code}}</span>
                                  <Button
                                    @tone='primary'
                                    @appearance='link'
                                    @size='s'
                                    {{on 'click' (fn this.view row)}}
                                  >{{row.cardTitle}}</Button></span>
                                <StatusChip
                                  @value={{this.courseLabel row}}
                                  @hue={{this.courseHue row}}
                                />
                              </li>
                            {{/each}}
                          </ul>
                        {{else}}
                          <EmptyState
                            @size='s'
                            @texture={{false}}
                            @title='No courses yet'
                            @message='Add one from the Courses tab.'
                          />
                        {{/if}}
                      </:default>
                    </Card>
                  </div>

                {{else if this.tabLoading}}
                  <LoadingState @label={{this.loadingLabel}} />

                {{else if (eq this.tab 'courses')}}
                  <Card class='panel' @title='Courses'>
                    <DataTable
                      @columns={{this.courseColumns}}
                      @rows={{this.tabRows}}
                      @key={{this.cardKey}}
                      @label='Courses'
                      @flush={{true}}
                      @columnMenu={{false}}
                      @sortable={{false}}
                      @striped={{false}}
                    >
                      <:empty><EmptyState
                          @size='s'
                          @texture={{false}}
                          @title='No courses match'
                        /></:empty>
                      <:cell as |text row col|>
                        {{#if (eq col.key 'title')}}
                          <Button
                            @tone='primary'
                            @appearance='link'
                            @size='s'
                            {{on 'click' (fn this.view row)}}
                          >{{row.cardTitle}}</Button>
                        {{else if (eq col.key 'status')}}
                          <StatusChip
                            @value={{this.courseLabel row}}
                            @hue={{this.courseHue row}}
                          />
                        {{else}}
                          {{text}}
                        {{/if}}
                      </:cell>
                    </DataTable>
                  </Card>

                {{else if (eq this.tab 'cohorts')}}
                  <Card class='panel' @title='Cohorts'>
                    <DataTable
                      @columns={{this.cohortColumns}}
                      @rows={{this.tabRows}}
                      @key={{this.cardKey}}
                      @label='Cohorts'
                      @flush={{true}}
                      @columnMenu={{false}}
                      @sortable={{false}}
                      @striped={{false}}
                    >
                      <:empty><EmptyState
                          @size='s'
                          @texture={{false}}
                          @title='No cohorts match'
                        /></:empty>
                      <:cell as |text row col|>
                        {{#if (eq col.key 'name')}}
                          <Button
                            @tone='primary'
                            @appearance='link'
                            @size='s'
                            {{on 'click' (fn this.showCohort row)}}
                          >{{row.cardTitle}}</Button>
                        {{else if (eq col.key 'status')}}
                          <StatusChip
                            @value={{this.cohortLabel row}}
                            @hue={{this.cohortHue row}}
                          />
                        {{else}}
                          {{text}}
                        {{/if}}
                      </:cell>
                    </DataTable>
                  </Card>

                {{else if (eq this.tab 'learners')}}
                  <Card class='panel' @title='Learners'>
                    <DataTable
                      @columns={{this.learnerColumns}}
                      @rows={{this.tabRows}}
                      @key={{this.cardKey}}
                      @label='Learners'
                      @flush={{true}}
                      @columnMenu={{false}}
                      @sortable={{false}}
                      @striped={{false}}
                    >
                      <:empty><EmptyState
                          @size='s'
                          @texture={{false}}
                          @title='No learners match'
                        /></:empty>
                      <:cell as |text row col|>
                        {{#if (eq col.key 'name')}}
                          <Button
                            @tone='primary'
                            @appearance='link'
                            @size='s'
                            {{on 'click' (fn this.view row)}}
                          >{{row.title}}</Button>
                        {{else}}
                          {{text}}
                        {{/if}}
                      </:cell>
                    </DataTable>
                  </Card>

                {{else}}
                  <Card class='panel' @title='Certificates'>
                    <DataTable
                      @columns={{this.certColumns}}
                      @rows={{this.tabRows}}
                      @key={{this.cardKey}}
                      @label='Certificates'
                      @flush={{true}}
                      @columnMenu={{false}}
                      @sortable={{false}}
                      @striped={{false}}
                    >
                      <:empty><EmptyState
                          @size='s'
                          @texture={{false}}
                          @title='No certificates match'
                        /></:empty>
                      <:cell as |text row col|>
                        {{#if (eq col.key 'number')}}
                          <Button
                            @tone='primary'
                            @appearance='link'
                            @size='s'
                            {{on 'click' (fn this.view row)}}
                          >{{row.number}}</Button>
                        {{else if (eq col.key 'status')}}
                          <StatusChip
                            @value={{row.statusLabel}}
                            @hue={{this.certHue row}}
                          />
                        {{else}}
                          {{text}}
                        {{/if}}
                      </:cell>
                    </DataTable>
                  </Card>
                {{/if}}
              </:default>
            </PageScaffold>
          </main>
        </:default>
      </Sidebar>
    {{/if}}
    <style scoped>
      @layer PretComponent {
        .desk {
          height: 100%;
          background-color: var(--background);
          color: var(--foreground);
        }
        .desk-main {
          height: 100%;
          min-width: 0;
        }
        .brand {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-4xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .mark {
          width: 2.25rem;
          height: 2.25rem;
          display: grid;
          place-items: center;
          border-radius: var(--radius);
          background-color: var(--primary);
          color: var(--primary-foreground);
          font-weight: 700;
        }
        .brand-title {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 600;
        }
        .brand-sub,
        .muted {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .warn {
          color: var(--warning-ink);
        }
        .who {
          display: flex;
          flex-direction: column;
          margin: 0;
          padding: 0 var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .list-toolbar {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .desk-search {
          flex: 1 1 14rem;
          max-width: 22rem;
        }
        .main-grid {
          display: grid;
          gap: var(--boxel-sp-lg);
          grid-template-columns: minmax(0, 2.2fr) minmax(16.25rem, 1fr);
          align-items: start;
        }
        .ops-grid {
          display: grid;
          gap: var(--boxel-sp-lg);
          grid-template-columns: repeat(auto-fit, minmax(17.5rem, 1fr));
          align-items: start;
        }
        .meta {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .rows {
          margin: 0;
          padding: 0;
          list-style: none;
        }
        .row {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-4xs) var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) 0;
          font-size: var(--boxel-font-size-sm);
        }
        .row + .row {
          border-top: 1px solid var(--border);
        }
        .row-main {
          display: flex;
          flex-direction: column;
          flex: 1 1 10rem;
          min-width: 0;
        }
        .row-title {
          font-weight: 600;
        }
        .row-inline {
          flex-direction: row;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        .row-sub,
        .row-end {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-xs);
        }
        .late {
          color: var(--destructive-ink);
          font-weight: 600;
        }
        .mono {
          font-family: var(--font-mono);
        }
        @container (width < 56rem) {
          .main-grid {
            grid-template-columns: minmax(0, 1fr);
          }
        }
        @container (width < 40rem) {
          .desk-search {
            flex: 1;
            width: auto;
          }
        }
      }
    </style>
  </template>
}

/**
 * Academy Desk: the instructor's desk over a course-and-cohort academy.
 * It stores two settings, the certifying authority and the acting
 * instructor. Home, Courses, Cohorts, Learners and Certificates are live
 * queries over the realm, and a cohort opened from here gets the full Cohort
 * Workspace in place.
 */
export class AcademyDesk extends CardDef {
  static displayName = 'Academy Desk';
  static icon = SchoolIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  @field tagline = contains(StringField);
  @field authority = linksTo(() => CertificationAuthority);
  @field actor = linksTo(() => Employee, {
    description:
      'The instructor acting in this desk: releases, grades, marks and posts are attributed to them.',
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AcademyDesk) {
      return this.title?.trim() || 'Academy Desk';
    },
  });

  static isolated = AcademyDeskIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='ad-emb'>
        <Avatar
          @name={{if @model.cardTitle @model.cardTitle ''}}
          @hue='var(--primary)'
          @size={{32}}
          aria-hidden='true'
        />
        <span class='ad-emb-who'>
          <strong class='ad-emb-name'>{{@model.cardTitle}}</strong>
          <span class='ad-emb-sub'>{{if
              @model.tagline
              @model.tagline
              'Course & cohort learning'
            }}</span>
        </span>
      </div>
      <style scoped>
        .ad-emb {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          min-width: 0;
        }
        .ad-emb-who {
          flex: 1;
          display: grid;
          min-width: 0;
        }
        .ad-emb-name,
        .ad-emb-sub {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .ad-emb-name {
          font-weight: 600;
        }
        .ad-emb-sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='ad-atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .ad-atom {
          white-space: nowrap;
        }
      </style>
    </template>
  };

  // Fitted: who (desk, tagline), then the acting instructor and the
  // certifying authority in their own atom formats.
  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FitTile>
        <:avatar><Avatar
            @name={{if @model.cardTitle @model.cardTitle ''}}
            @hue='var(--primary)'
            @size={{32}}
            aria-hidden='true'
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{if
            @model.tagline
            @model.tagline
            'Course & cohort learning'
          }}</:subtitle>
        <:relations>
          {{#if @model.actor}}
            <@fields.actor @format='atom' @displayContainer={{false}} />
          {{/if}}
          {{#if @model.authority}}
            <@fields.authority @format='atom' @displayContainer={{false}} />
          {{/if}}
        </:relations>
      </FitTile>
    </template>
  };
}

export default AcademyDesk;
