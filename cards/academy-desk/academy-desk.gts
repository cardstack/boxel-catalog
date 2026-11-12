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
import HouseIcon from '@cardstack/boxel-icons/house';
import BookIcon from '@cardstack/boxel-icons/book';
import UsersIcon from '@cardstack/boxel-icons/users';
import UserIcon from '@cardstack/boxel-icons/user';
import AwardIcon from '@cardstack/boxel-icons/award';
import ArrowLeftIcon from '@cardstack/boxel-icons/arrow-left';

import { Button } from '@cardstack/pretui/components/button';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { RichFittedCard } from '../shared/rich-fitted-card';
import { CertificationAuthority } from '../audit/certification-authority';
import { Employee } from '../hr/employee';
import { Course, CourseStatusField, COURSE_STATUSES } from '../academy/course';
import { Cohort, CohortStatusField, COHORT_STATUSES } from '../academy/cohort';
import { Learner } from '../academy/learner';
import {
  Certificate,
  CertificateStatusField,
  CERTIFICATE_STATUSES,
} from '../academy/certificate';
import { statusHue } from '@cardstack/catalog/fields/status/status';
import { AcademyHome } from '../academy/components/academy-home';
import { CohortWorkspace } from '../academy/components/cohort-workspace';
import {
  DeskList,
  type DeskColumn,
  type DeskStat,
} from '../academy/components/desk-parts';

type Tab = 'home' | 'courses' | 'cohorts' | 'learners' | 'certificates';

interface TabSpec {
  id: Tab;
  label: string;
  icon: typeof HouseIcon;
}
const TABS: TabSpec[] = [
  { id: 'home', label: 'Home', icon: HouseIcon },
  { id: 'courses', label: 'Courses', icon: BookIcon },
  { id: 'cohorts', label: 'Cohorts', icon: UsersIcon },
  { id: 'learners', label: 'Learners', icon: UserIcon },
  { id: 'certificates', label: 'Certificates', icon: AwardIcon },
];

// Issued certificates carry a timestamp; show the local calendar day.
function formatIssued(value?: Date | string | null): string {
  if (!value) {
    return '—';
  }
  let date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }
  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function countBy(items: any[], field: string, value: string) {
  return items.filter((i) => i?.[field] === value).length;
}

// "All · 6" then one chip per status.
function statusChips(
  items: any[],
  field: string,
  options: { value: string; label?: string }[],
) {
  return [
    { value: 'all', label: 'All', count: items.length },
    ...options.map((o) => ({
      value: o.value,
      label: o.label ?? o.value,
      count: countBy(items, field, o.value),
    })),
  ];
}

function matches(row: any, text: string, keys: string[]) {
  if (!text) return true;
  let t = text.toLowerCase();
  return keys.some((k) =>
    String(row?.[k] ?? '')
      .toLowerCase()
      .includes(t),
  );
}

// The isolated desk, hoisted out of the card class so its fields can be
// @tracked.
class AcademyDeskIsolated extends Component<typeof AcademyDesk> {
  tabs = TABS;
  @tracked tab: Tab = 'home';
  @tracked openCohort: Cohort | undefined;
  @tracked search = '';
  @tracked chip = 'all';
  private coursesQ: ReturnType<getCards> | undefined;
  private cohortsQ: ReturnType<getCards> | undefined;
  private learnersQ: ReturnType<getCards> | undefined;
  private certsQ: ReturnType<getCards> | undefined;
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
    return `Loading ${this.tab}…`;
  }

  countOf = (id: Tab): string | undefined => {
    let list = {
      home: undefined,
      courses: this.coursesQ,
      cohorts: this.cohortsQ,
      learners: this.learnersQ,
      certificates: this.certsQ,
    }[id];
    return list?.instances ? String(this.instancesOf(list).length) : undefined;
  };

  get current(): TabSpec {
    return TABS.find((t) => t.id === this.tab) ?? TABS[0]!;
  }

  get subtitle(): string {
    switch (this.tab) {
      case 'home':
        return this.args.model.tagline ?? 'Course & cohort learning';
      case 'courses':
        return `${this.courses.length} in this realm`;
      case 'cohorts':
        return `${this.cohorts.length} cohorts across every course`;
      case 'learners':
        return `${this.learners.length} learners enrolled or invited`;
      default:
        return `${this.certificates.length} certificates issued by this academy`;
    }
  }

  // Rows after the chip and the search box.
  private narrow(rows: any[], field: string, keys: string[]) {
    let text = this.search.trim();
    return rows.filter(
      (r) =>
        (this.chip === 'all' || r?.[field] === this.chip) &&
        matches(r, text, keys),
    );
  }

  courseColumns: DeskColumn[] = [
    { key: 'cardTitle', label: 'Course', name: true },
    { key: 'code', label: 'Code', mono: true },
    { key: 'levelLabel', label: 'Level' },
    { key: 'moduleCount', label: 'Modules', align: 'end', mono: true },
    { key: 'creditHours', label: 'Credit', align: 'end', mono: true },
    { key: 'status', label: 'Status', status: true },
  ];
  cohortColumns: DeskColumn[] = [
    { key: 'cardTitle', label: 'Cohort', name: true },
    { key: 'courseCode', label: 'Course', mono: true },
    { key: 'termLabel', label: 'Term', mono: true },
    {
      key: 'week',
      label: 'Week',
      align: 'end',
      mono: true,
      value: (c: any) =>
        `${c.currentWeek ? c.currentWeek : '—'}/${c.weekCount}`,
    },
    { key: 'status', label: 'Status', status: true },
  ];
  learnerColumns: DeskColumn[] = [
    { key: 'title', label: 'Learner', name: true },
    { key: 'email', label: 'Email', mono: true },
    { key: 'organisation', label: 'Organization' },
    { key: 'timezone', label: 'Zone', mono: true },
  ];
  certColumns: DeskColumn[] = [
    { key: 'number', label: 'Number', name: true },
    { key: 'learnerName', label: 'Learner' },
    { key: 'courseTitle', label: 'Course' },
    { key: 'finalLetter', label: 'Final', align: 'end', mono: true },
    {
      key: 'issued',
      label: 'Issued',
      mono: true,
      value: (c: any) => formatIssued(c.issuedAt),
    },
    { key: 'certStatus', label: 'Status', status: true },
  ];

  courseStatus = (c: any) => ({
    label: c.status,
    hue: statusHue(CourseStatusField, c.status),
  });
  cohortStatus = (c: any) => ({
    label: c.status,
    hue: statusHue(CohortStatusField, c.status),
  });
  certStatus = (c: any) => ({
    label: c.statusLabel,
    hue: statusHue(CertificateStatusField, c.certStatus),
  });

  // Status counts in the strip, the same numbers as the chips.
  private statusStats(
    items: any[],
    field: string,
    options: { value: string; label?: string; hue?: string }[],
    fieldClass: any,
  ): DeskStat[] {
    return [
      { label: 'Total', value: items.length },
      ...options.map((o) => ({
        label: o.label ?? o.value,
        value: countBy(items, field, o.value),
        hue: statusHue(fieldClass, o.value),
      })),
    ];
  }

  get courseStats() {
    return this.statusStats(
      this.courses,
      'status',
      COURSE_STATUSES,
      CourseStatusField,
    );
  }
  get cohortStats() {
    return this.statusStats(
      this.cohorts,
      'status',
      COHORT_STATUSES,
      CohortStatusField,
    );
  }
  get certStats() {
    return this.statusStats(
      this.certificates,
      'certStatus',
      CERTIFICATE_STATUSES,
      CertificateStatusField,
    );
  }
  get orgs(): string[] {
    return [
      ...new Set(
        this.learners.map((l) => l.organisation).filter(Boolean) as string[],
      ),
    ].sort();
  }
  get learnerStats(): DeskStat[] {
    return [
      { label: 'Total', value: this.learners.length },
      ...this.orgs.slice(0, 4).map((o) => ({
        label: o,
        value: countBy(this.learners, 'organisation', o),
      })),
    ];
  }

  get courseChips() {
    return statusChips(this.courses, 'status', COURSE_STATUSES);
  }
  get cohortChips() {
    return statusChips(this.cohorts, 'status', COHORT_STATUSES);
  }
  get certChips() {
    return statusChips(this.certificates, 'certStatus', CERTIFICATE_STATUSES);
  }
  get learnerChips() {
    return [
      { value: 'all', label: 'All', count: this.learners.length },
      ...this.orgs.map((o) => ({
        value: o,
        label: o,
        count: countBy(this.learners, 'organisation', o),
      })),
    ];
  }

  get courseRows() {
    return this.narrow(this.courses, 'status', ['cardTitle', 'code']);
  }
  get cohortRows() {
    return this.narrow(this.cohorts, 'status', ['cardTitle', 'courseCode']);
  }
  get learnerRows() {
    return this.narrow(this.learners, 'organisation', [
      'title',
      'email',
      'organisation',
    ]);
  }
  get certRows() {
    return this.narrow(this.certificates, 'certStatus', [
      'number',
      'learnerName',
      'courseTitle',
    ]);
  }

  setTab = (value: Tab) => {
    this.tab = value;
    this.openCohort = undefined;
    this.search = '';
    this.chip = 'all';
  };
  // On the phone the rail is a drawer; picking a tab closes it.
  navTo = (bar: { mobile?: boolean; toggle?: () => void }, id: Tab) => {
    this.setTab(id);
    if (bar.mobile) bar.toggle?.();
  };
  setSearch = (v: string) => {
    this.search = v;
  };
  setChip = (v: string) => {
    this.chip = v;
  };
  showCohort = (cohort: Cohort) => {
    this.openCohort = cohort;
    this.tab = 'cohorts';
  };
  backToCohorts = () => {
    this.openCohort = undefined;
  };
  view = (card: CardDef | URL | undefined) => {
    if (card) {
      this.args.viewCard?.(card as CardDef, 'isolated');
    }
  };

  // The host's createCard opens a new instance of the type, in edit mode, in
  // this realm.
  createFor = (cls: typeof CardDef) => () => {
    let ref = identifyCard(cls);
    let realm = this.realms[0];
    if (!ref || !realm) {
      return;
    }
    this.args.createCard?.(ref, undefined, { realmURL: new URL(realm) });
  };

  <template>
    <div class='app'>
      <Sidebar
        class='shell'
        @label='Academy Desk'
        @collapsible='rail'
        @railBreakpoint={{1100}}
        @mobileBreakpoint={{720}}
        @bordered={{true}}
        @scroll='content'
        @resizable={{true}}
      >
        <:header as |bar|>
          <div class='brand'>
            <span class='brand-mark' aria-hidden='true'>Ad</span>
            {{#unless bar.collapsed}}
              <span class='brand-name'><small>Course &amp; cohort learning</small>{{@model.cardTitle}}</span>
            {{/unless}}
          </div>
        </:header>
        <:nav as |bar|>
          <SidebarGroup @label='Academy' @hideLabel={{bar.collapsed}}>
            {{#each this.tabs as |t|}}
              <SidebarItem
                @label={{t.label}}
                @badge={{unless bar.collapsed (this.countOf t.id)}}
                @active={{eq t.id this.tab}}
                @collapsed={{bar.collapsed}}
                @onClick={{fn this.navTo bar t.id}}
                @icon={{t.icon}}
              />
            {{/each}}
          </SidebarGroup>
        </:nav>
        <:footer as |bar|>
          {{#unless bar.collapsed}}
            <p class='who'>
              <span class='cap'>Acting as</span>
              {{#if @model.actor}}
                <b>{{@model.actor.name}}</b>
              {{else}}
                <span class='warn'>No instructor set. Edit the desk to choose
                  who is acting.</span>
              {{/if}}
            </p>
          {{/unless}}
        </:footer>
        <:default as |bar|>
          <main class='main'>
            {{#if bar.mobile}}
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='Menu'
              />
            {{/if}}

            {{#if this.openCohort}}
              <header class='head'>
                <p class='cap'>Academy Desk · Cohorts</p>
                <h1>{{this.openCohort.cardTitle}}</h1>
                <p class='sub'>{{this.openCohort.courseCode}}
                  ·
                  {{this.openCohort.termLabel}}</p>
              </header>
              <div class='crumb'>
                <Button
                  @icon={{ArrowLeftIcon}}
                  @tone='neutral'
                  @appearance='outlined'
                  @size='s'
                  {{on 'click' this.backToCohorts}}
                >Cohorts</Button>
                <Button
                  @tone='neutral'
                  @appearance='outlined'
                  @size='s'
                  {{on 'click' (fn this.view this.openCohort)}}
                >Open card</Button>
              </div>
              <CohortWorkspace
                @cohort={{this.openCohort}}
                @context={{@context}}
                @actor={{@model.actor}}
                @authority={{@model.authority}}
                @onOpenCard={{this.view}}
              />
            {{else}}
              <header class='head'>
                <p class='cap'>Academy Desk · {{this.current.label}}</p>
                <h1>{{this.current.label}}</h1>
                <p class='sub'>{{this.subtitle}}</p>
              </header>

              {{#if (eq this.tab 'home')}}
                <AcademyHome
                  @context={{@context}}
                  @realms={{this.realms}}
                  @onOpenCohort={{this.showCohort}}
                  @onOpenCourse={{this.view}}
                  @onOpenSubmission={{this.view}}
                  @onNewCohort={{this.createFor Cohort}}
                />
              {{else if this.tabLoading}}
                <LoadingState class='loading' @label={{this.loadingLabel}} />
              {{else if (eq this.tab 'courses')}}
                <DeskList
                  @title='Courses'
                  @noun='courses'
                  @mark='Co'
                  @stats={{this.courseStats}}
                  @chips={{this.courseChips}}
                  @chip={{this.chip}}
                  @onChip={{this.setChip}}
                  @search={{this.search}}
                  @onSearch={{this.setSearch}}
                  @newLabel='New course'
                  @onNew={{this.createFor Course}}
                  @rows={{this.courseRows}}
                  @columns={{this.courseColumns}}
                  @statusOf={{this.courseStatus}}
                  @onOpen={{this.view}}
                />
              {{else if (eq this.tab 'cohorts')}}
                <DeskList
                  @title='Cohorts'
                  @noun='cohorts'
                  @mark='Ch'
                  @stats={{this.cohortStats}}
                  @chips={{this.cohortChips}}
                  @chip={{this.chip}}
                  @onChip={{this.setChip}}
                  @search={{this.search}}
                  @onSearch={{this.setSearch}}
                  @newLabel='New cohort'
                  @onNew={{this.createFor Cohort}}
                  @rows={{this.cohortRows}}
                  @columns={{this.cohortColumns}}
                  @statusOf={{this.cohortStatus}}
                  @onOpen={{this.showCohort}}
                />
              {{else if (eq this.tab 'learners')}}
                <DeskList
                  @title='Learners'
                  @noun='learners'
                  @mark='Le'
                  @avatar={{true}}
                  @stats={{this.learnerStats}}
                  @chips={{this.learnerChips}}
                  @chip={{this.chip}}
                  @onChip={{this.setChip}}
                  @search={{this.search}}
                  @onSearch={{this.setSearch}}
                  @newLabel='New learner'
                  @onNew={{this.createFor Learner}}
                  @rows={{this.learnerRows}}
                  @columns={{this.learnerColumns}}
                  @onOpen={{this.view}}
                />
              {{else}}
                <DeskList
                  @title='Certificates'
                  @noun='certificates'
                  @mark='Ce'
                  @stats={{this.certStats}}
                  @chips={{this.certChips}}
                  @chip={{this.chip}}
                  @onChip={{this.setChip}}
                  @search={{this.search}}
                  @onSearch={{this.setSearch}}
                  @rows={{this.certRows}}
                  @columns={{this.certColumns}}
                  @statusOf={{this.certStatus}}
                  @onOpen={{this.view}}
                />
              {{/if}}
            {{/if}}
          </main>
        </:default>
      </Sidebar>
    </div>
    <style scoped>
      .app {
        container-type: inline-size;
        block-size: 100%;
        min-block-size: 0;
        overflow: hidden;
        background: var(--background);
        color: var(--foreground);
        font-family: var(--font-sans);
        font-size: var(--boxel-font-size-xs);
      }
      .shell {
        block-size: 100%;
        min-block-size: 0;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
      }
      .brand-mark {
        display: grid;
        place-items: center;
        inline-size: 1.75rem;
        block-size: 1.75rem;
        border-radius: var(--radius);
        background: var(--muted);
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: var(--boxel-font-size-xs);
        flex: none;
      }
      .brand-name {
        display: grid;
        font-weight: 700;
        font-size: var(--boxel-font-size-sm);
      }
      .brand-name small,
      .cap {
        margin: 0;
        font-family: var(--font-mono);
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs, var(--boxel-font-size-xs));
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .who {
        display: grid;
        gap: var(--boxel-sp-5xs);
        padding: var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
      }
      .warn {
        color: var(--muted-foreground);
      }
      .main {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-lg);
        min-width: 0;
      }
      .head {
        display: grid;
        gap: var(--boxel-sp-5xs);
      }
      h1 {
        font-weight: 400;
        font-size: var(--boxel-font-size-2xl);
        line-height: var(--boxel-line-height-xl);
        text-transform: uppercase;
      }
      .sub {
        margin: 0;
        color: var(--muted-foreground);
      }
      .crumb {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        --control-height: 1.625rem;
      }
      .loading {
        align-self: center;
        padding: var(--boxel-sp-xl);
      }
      @container (width <= 45rem) {
        .main {
          padding: var(--boxel-sp);
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
      <div class='row'>
        <span class='mark' aria-hidden='true'>A</span>
        <div class='text'>
          <span class='title'>{{@model.cardTitle}}</span>
          <span class='sub'>{{if
              @model.tagline
              @model.tagline
              'Course & cohort learning'
            }}</span>
        </div>
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .mark {
          width: 2.25rem;
          height: 2.25rem;
          display: grid;
          place-items: center;
          border-radius: var(--radius);
          background: var(--primary);
          color: var(--primary-foreground);
          font-weight: 800;
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.cardTitle}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <RichFittedCard>
        <:avatar><SchoolIcon class='app-mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{if
            @model.tagline
            @model.tagline
            'Course & cohort learning'
          }}</:subtitle>
        <:fact>{{#if @model.actor}}Acting as
            {{@model.actor.name}}{{/if}}</:fact>
      </RichFittedCard>
      <style scoped>
        .app-mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

export default AcademyDesk;
