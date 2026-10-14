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
import { FittedCard } from '@cardstack/boxel-ui/components';
import SchoolIcon from '@cardstack/boxel-icons/school';

import { Button } from '@cardstack/pretui/components/button';
import { LoadingState } from '@cardstack/pretui/components/loading-state';
import { Tabs } from '@cardstack/pretui/components/tabs';
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
import { statusHue } from '../../fields/status/status';
import { type TableColumn } from '../../components/table';
import { StatePill } from '../../components/state-pill';
import { AcademyHome } from '../academy/components/academy-home';
import { CohortWorkspace } from '../academy/components/cohort-workspace';
import {
  CollectionShell,
  type CollectionBadge,
} from '../../components/collection-shell';

type Tab = 'home' | 'courses' | 'cohorts' | 'learners' | 'certificates';
const TABS: { value: Tab; label: string }[] = [
  { value: 'home', label: 'Home' },
  { value: 'courses', label: 'Courses' },
  { value: 'cohorts', label: 'Cohorts' },
  { value: 'learners', label: 'Learners' },
  { value: 'certificates', label: 'Certificates' },
];

function eq(a: unknown, b: unknown) {
  return a === b;
}

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

function statusBadges(
  items: any[],
  field: string,
  options: { value: string; label?: string }[],
): CollectionBadge[] {
  return [
    { id: 'all', label: 'All', count: items.length },
    ...options.map((o) => ({
      id: o.value,
      label: o.label ?? o.value,
      count: items.filter((i) => i?.[field] === o.value).length,
      field,
      value: o.value,
    })),
  ];
}

// The isolated desk, hoisted out of the card class so its fields can be
// @tracked.
class AcademyDeskIsolated extends Component<typeof AcademyDesk> {
  @tracked tab: Tab = 'home';
  @tracked openCohort: Cohort | undefined;
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

  courseColumns: TableColumn[] = [
    { key: 'code', label: 'Code', width: '6rem', value: (c: any) => c.code },
    { key: 'title', label: 'Course', value: (c: any) => c.cardTitle },
    {
      key: 'level',
      label: 'Level',
      showAbove: 640,
      value: (c: any) => c.levelLabel,
    },
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
      showAbove: 480,
      value: (c: any) => c.creditHours,
    },
    {
      key: 'status',
      label: 'Status',
      custom: true,
      sortValue: (c: any) => c.status,
    },
  ];
  cohortColumns: TableColumn[] = [
    { key: 'name', label: 'Cohort', value: (c: any) => c.cardTitle },
    {
      key: 'course',
      label: 'Course',
      showAbove: 640,
      value: (c: any) => c.courseCode,
    },
    {
      key: 'term',
      label: 'Term',
      value: (c: any) => c.termLabel,
      sortValue: (c: any) => c.term?.start ?? '',
    },
    {
      key: 'week',
      label: 'Week',
      align: 'end',
      value: (c: any) =>
        `${c.currentWeek ? c.currentWeek : '—'}/${c.weekCount}`,
    },
    {
      key: 'status',
      label: 'Status',
      custom: true,
      sortValue: (c: any) => c.status,
    },
  ];
  learnerColumns: TableColumn[] = [
    { key: 'name', label: 'Learner', value: (l: any) => l.title },
    {
      key: 'email',
      label: 'Email',
      showAbove: 640,
      value: (l: any) => l.email,
    },
    {
      key: 'org',
      label: 'Organisation',
      showAbove: 480,
      value: (l: any) => l.organisation,
    },
    {
      key: 'tz',
      label: 'Zone',
      showAbove: 900,
      value: (l: any) => l.timezone,
    },
  ];
  certColumns: TableColumn[] = [
    { key: 'number', label: 'Number', value: (c: any) => c.number },
    { key: 'learner', label: 'Learner', value: (c: any) => c.learnerName },
    {
      key: 'course',
      label: 'Course',
      showAbove: 640,
      value: (c: any) => c.courseTitle,
    },
    {
      key: 'letter',
      label: 'Final',
      align: 'end',
      showAbove: 480,
      value: (c: any) => c.finalLetter,
    },
    {
      key: 'issued',
      label: 'Issued',
      value: (c: any) => formatIssued(c.issuedAt),
      sortValue: (c: any) => new Date(c.issuedAt ?? 0).getTime(),
    },
    {
      key: 'status',
      label: 'Status',
      custom: true,
      sortValue: (c: any) => c.certStatus,
    },
  ];

  setTab = (value: string) => {
    this.tab = value as Tab;
    this.openCohort = undefined;
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

  courseHue = (c: any) => statusHue(CourseStatusField, c.status);
  cohortHue = (c: any) => statusHue(CohortStatusField, c.status);
  certHue = (c: any) => statusHue(CertificateStatusField, c.certStatus);

  get courseBadges() {
    return statusBadges(this.courses, 'status', COURSE_STATUSES);
  }
  get cohortBadges() {
    return statusBadges(this.cohorts, 'status', COHORT_STATUSES);
  }
  get learnerBadges(): CollectionBadge[] {
    let orgs = [
      ...new Set(
        this.learners.map((l) => l.organisation).filter(Boolean) as string[],
      ),
    ].sort();
    return [
      { id: 'all', label: 'All', count: this.learners.length },
      ...orgs.map((o) => ({
        id: o,
        label: o,
        count: this.learners.filter((l) => l.organisation === o).length,
        field: 'organisation',
        value: o,
      })),
    ];
  }
  get certBadges() {
    return statusBadges(this.certificates, 'certStatus', CERTIFICATE_STATUSES);
  }

  refOf = (cls: typeof CardDef) =>
    identifyCard(cls) as { module: string; name: string } | undefined;

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
    <div class='desk'>
      <header class='top'>
        <div class='brand'>
          <span class='mark' aria-hidden='true'>A</span>
          <div>
            <h1>{{@model.cardTitle}}</h1>
            {{#if @model.tagline}}<p class='tag'>{{@model.tagline}}</p>{{/if}}
          </div>
        </div>
        <Tabs
          class='tabs'
          aria-label='Academy sections'
          @options={{TABS}}
          @value={{this.tab}}
          @onValueChange={{this.setTab}}
        />
        <p class='who' role='status'>
          {{#if @model.actor}}
            <span class='who-l'>Acting as</span>
            <b>{{@model.actor.name}}</b>
          {{else}}
            <span class='who-l warn'>No instructor set. Edit the desk to choose
              who is acting.</span>
          {{/if}}
        </p>
      </header>

      <main class='body'>
        {{#if this.openCohort}}
          <div class='crumb'>
            <Button
              @tone='neutral'
              @appearance='plain'
              @size='s'
              {{on 'click' this.backToCohorts}}
            >← Cohorts</Button>
            <span class='crumb-name'>{{this.openCohort.cardTitle}}</span>
            <StatePill
              @label={{this.openCohort.status}}
              @hue={{this.cohortHue this.openCohort}}
              @dot={{true}}
            />
            <span class='muted'>{{this.openCohort.termLabel}}</span>
            <Button
              class='right'
              @tone='neutral'
              @appearance='plain'
              @size='s'
              {{on 'click' (fn this.view this.openCohort)}}
            >Open card ↗</Button>
          </div>
          <CohortWorkspace
            @cohort={{this.openCohort}}
            @context={{@context}}
            @actor={{@model.actor}}
            @authority={{@model.authority}}
            @onOpenCard={{this.view}}
          />

        {{else if (eq this.tab 'home')}}
          <AcademyHome
            @context={{@context}}
            @realms={{this.realms}}
            @onOpenCohort={{this.showCohort}}
            @onOpenCourse={{this.view}}
            @onOpenSubmission={{this.view}}
          />

        {{else if this.tabLoading}}
          <LoadingState class='loading' @label={{this.loadingLabel}} />

        {{else if (eq this.tab 'courses')}}
          <CollectionShell
            @noun='courses'
            @singular='Course'
            @cardTypeRef={{this.refOf Course}}
            @items={{this.courses}}
            @realms={{this.realms}}
            @context={{@context}}
            @badges={{this.courseBadges}}
            @columns={{this.courseColumns}}
            @onOpen={{this.view}}
            @onAdd={{this.createFor Course}}
          >
            <:cell as |c col|>
              {{#if (eq col.key 'status')}}
                <StatePill @label={{c.status}} @hue={{this.courseHue c}} />
              {{/if}}
            </:cell>
          </CollectionShell>

        {{else if (eq this.tab 'cohorts')}}
          <CollectionShell
            @noun='cohorts'
            @singular='Cohort'
            @cardTypeRef={{this.refOf Cohort}}
            @items={{this.cohorts}}
            @realms={{this.realms}}
            @context={{@context}}
            @badges={{this.cohortBadges}}
            @columns={{this.cohortColumns}}
            @onOpen={{this.showCohort}}
            @onAdd={{this.createFor Cohort}}
          >
            <:cell as |c col|>
              {{#if (eq col.key 'status')}}
                <StatePill @label={{c.status}} @hue={{this.cohortHue c}} />
              {{/if}}
            </:cell>
          </CollectionShell>

        {{else if (eq this.tab 'learners')}}
          <CollectionShell
            @noun='learners'
            @singular='Learner'
            @cardTypeRef={{this.refOf Learner}}
            @items={{this.learners}}
            @realms={{this.realms}}
            @context={{@context}}
            @badges={{this.learnerBadges}}
            @columns={{this.learnerColumns}}
            @onOpen={{this.view}}
            @onAdd={{this.createFor Learner}}
          />

        {{else}}
          <CollectionShell
            @noun='certificates'
            @singular='Certificate'
            @cardTypeRef={{this.refOf Certificate}}
            @items={{this.certificates}}
            @realms={{this.realms}}
            @context={{@context}}
            @badges={{this.certBadges}}
            @columns={{this.certColumns}}
            @onOpen={{this.view}}
          >
            <:cell as |c col|>
              {{#if (eq col.key 'status')}}
                <StatePill @label={{c.statusLabel}} @hue={{this.certHue c}} />
              {{/if}}
            </:cell>
          </CollectionShell>
        {{/if}}
      </main>
    </div>
    <style scoped>
      .desk {
        min-height: 100%;
        display: grid;
        grid-template-rows: auto 1fr;
        color: var(--foreground);
        background: var(--background);
        container-type: inline-size;
      }
      .top {
        display: grid;
        grid-template-columns: auto 1fr auto;
        gap: var(--boxel-sp-lg);
        align-items: center;
        padding: var(--boxel-sp) var(--boxel-sp-lg);
        border-bottom: 1px solid var(--border);
        background: var(--card);
      }
      .brand {
        display: flex;
        gap: var(--boxel-sp-sm);
        align-items: center;
      }
      .mark {
        width: 2.5rem;
        height: 2.5rem;
        display: grid;
        place-items: center;
        border-radius: var(--radius);
        background: var(--primary);
        color: var(--primary-foreground);
        font-size: var(--boxel-font-size-md);
        font-weight: 800;
      }
      .tag {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .tabs {
        justify-self: center;
      }
      .who {
        font-size: var(--boxel-font-size-sm);
        text-align: end;
      }
      .who-l {
        color: var(--muted-foreground);
      }
      .who-l.warn {
        color: var(--warning-ink);
      }
      .body {
        padding: var(--boxel-sp-lg);
        display: grid;
        gap: var(--boxel-sp);
        align-content: start;
      }
      .loading {
        justify-self: center;
        padding: var(--boxel-sp-xl);
      }
      .crumb {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-sm);
        align-items: center;
        font-size: var(--boxel-font-size-sm);
      }
      .crumb-name {
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
      }
      .right {
        margin-left: auto;
      }
      .muted {
        color: var(--muted-foreground);
      }
      @media (prefers-reduced-motion: no-preference) {
        .body > * {
          animation: desk-enter 220ms cubic-bezier(0.2, 0.8, 0.2, 1) both;
        }
      }
      @keyframes desk-enter {
        from {
          opacity: 0;
          transform: translateY(0.375rem);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      @container (width <= 47.5rem) {
        .top {
          grid-template-columns: 1fr;
          gap: var(--boxel-sp-sm);
        }
        .tabs {
          justify-self: start;
          max-width: 100%;
          overflow-x: auto;
        }
        .who {
          text-align: start;
        }
        .body {
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
      <FittedCard @titleTag='h3'>
        <:eyebrow>Academy desk</:eyebrow>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{if
            @model.tagline
            @model.tagline
            'Course & cohort learning'
          }}</:subtitle>
        <:meta>
          {{#if @model.actor}}
            <span>Acting as {{@model.actor.name}}</span>
          {{/if}}
        </:meta>
      </FittedCard>
    </template>
  };
}

export default AcademyDesk;
