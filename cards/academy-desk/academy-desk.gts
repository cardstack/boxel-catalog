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
import { identifyCard, realmURL, type getCards } from '@cardstack/runtime-common';
import SchoolIcon from '@cardstack/boxel-icons/school';

import { CertificationAuthority } from '../audit/certification-authority';
import { Employee } from '../hr/employee';
import { Course, CourseStatusField } from '../academy/course';
import { Cohort, CohortStatusField } from '../academy/cohort';
import { Learner } from '../academy/learner';
import { Certificate, CertificateStatusField } from '../academy/certificate';
import { statusHue } from '../../fields/status/status';
import { type TableColumn } from '../../components/table';
import { StatePill } from '../../components/state-pill';
import { AcademyHome } from '../academy/components/academy-home';
import { CohortWorkspace } from '../academy/components/cohort-workspace';
import { CollectionShell, type CollectionBadge } from '../../components/collection-shell';
import { COURSE_STATUSES } from '../academy/course';
import { COHORT_STATUSES } from '../academy/cohort';
import { CERTIFICATE_STATUSES } from '../academy/certificate';

type Tab = 'home' | 'courses' | 'cohorts' | 'learners' | 'certificates';
const TABS: { id: Tab; label: string }[] = [
  { id: 'home', label: 'Home' },
  { id: 'courses', label: 'Courses' },
  { id: 'cohorts', label: 'Cohorts' },
  { id: 'learners', label: 'Learners' },
  { id: 'certificates', label: 'Certificates' },
];

/**
 * Academy Desk — the app that composes the Course & Cohort Learning kit.
 * It owns two settings (the certifying authority and the acting
 * instructor) and otherwise holds nothing: Home, Courses, Cohorts, Learners
 * and Certificates are live queries over the realm, and a cohort opened
 * from here gets the full Cohort Workspace in place. Blocks are consumed
 * unchanged; anything the app needed and could not get was pushed upstream
 * into the block, never patched here.
 */
export class AcademyDesk extends CardDef {
  static displayName = 'Academy Desk';
  static icon = SchoolIcon;
  static prefersWideFormat = true;

  @field title = contains(StringField);
  @field tagline = contains(StringField);
  @field authority = linksTo(() => CertificationAuthority);
  @field actor = linksTo(() => Employee, {
    description: 'The instructor acting in this desk: releases, grades, marks and posts are attributed to them.',
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: AcademyDesk) {
      return this.title?.trim() || 'Academy Desk';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    @tracked tab: Tab = 'home';
    @tracked openCohort: any | undefined;
    private coursesQ: ReturnType<getCards> | undefined;
    private cohortsQ: ReturnType<getCards> | undefined;
    private learnersQ: ReturnType<getCards> | undefined;
    private certsQ: ReturnType<getCards> | undefined;


    constructor(owner: Owner, args: any) {
      super(owner, args);
      let ctx = this.args.context;
      if (!ctx?.getCards) return;
      let byType = (cls: any) => () => {
        let ref = identifyCard(cls);
        return ref ? { filter: { type: ref } } : undefined;
      };
      let realmList = this.realms;
      let realms = () => realmList;
      this.coursesQ = ctx.getCards(this, byType(Course), realms, { isLive: true });
      this.cohortsQ = ctx.getCards(this, byType(Cohort), realms, { isLive: true });
      this.learnersQ = ctx.getCards(this, byType(Learner), realms, { isLive: true });
      this.certsQ = ctx.getCards(this, byType(Certificate), realms, { isLive: true });
      // First read in this component's own computation (see cohort-workspace).
      for (let q of [this.coursesQ, this.cohortsQ, this.learnersQ, this.certsQ]) {
        void q?.instances;
      }
    }

    // Memoised: getCards needs a stable realms reference across recomputes.
    private cachedRealms: string[] | undefined;
    get realms(): string[] | undefined {
      if (!this.cachedRealms) {
        let url = (this.args.model as any)?.[realmURL];
        this.cachedRealms = url ? [url.href] : undefined;
      }
      return this.cachedRealms;
    }
    get courses(): any[] {
      return ((this.coursesQ?.instances ?? []) as any[]).filter(Boolean);
    }
    get cohorts(): any[] {
      return ((this.cohortsQ?.instances ?? []) as any[]).filter(Boolean);
    }
    get learners(): any[] {
      return ((this.learnersQ?.instances ?? []) as any[]).filter(Boolean);
    }
    get certificates(): any[] {
      return ((this.certsQ?.instances ?? []) as any[]).filter(Boolean);
    }

    courseColumns: TableColumn[] = [
      { key: 'code', label: 'Code', width: '6rem', value: (c: any) => c.code },
      { key: 'title', label: 'Course', value: (c: any) => c.cardTitle },
      { key: 'level', label: 'Level', showAbove: 640, value: (c: any) => c.levelLabel },
      { key: 'modules', label: 'Modules', align: 'end', value: (c: any) => c.moduleCount },
      { key: 'credit', label: 'Credit', align: 'end', showAbove: 480, value: (c: any) => c.creditHours },
      { key: 'status', label: 'Status', custom: true, sortValue: (c: any) => c.status },
    ];
    cohortColumns: TableColumn[] = [
      { key: 'name', label: 'Cohort', value: (c: any) => c.cardTitle },
      { key: 'course', label: 'Course', showAbove: 640, value: (c: any) => c.courseCode },
      { key: 'term', label: 'Term', value: (c: any) => c.termLabel, sortValue: (c: any) => new Date(c.term?.start ?? 0).getTime() },
      { key: 'week', label: 'Week', align: 'end', value: (c: any) => (c.currentWeek ? `${c.currentWeek}/${c.weekCount}` : `—/${c.weekCount}`) },
      { key: 'status', label: 'Status', custom: true, sortValue: (c: any) => c.status },
    ];
    learnerColumns: TableColumn[] = [
      { key: 'name', label: 'Learner', value: (l: any) => l.title },
      { key: 'email', label: 'Email', showAbove: 640, value: (l: any) => l.email },
      { key: 'org', label: 'Organisation', showAbove: 480, value: (l: any) => l.organisation },
      { key: 'tz', label: 'Zone', showAbove: 900, value: (l: any) => l.timezone },
    ];
    certColumns: TableColumn[] = [
      { key: 'number', label: 'Number', value: (c: any) => c.number },
      { key: 'learner', label: 'Learner', value: (c: any) => c.learnerName },
      { key: 'course', label: 'Course', showAbove: 640, value: (c: any) => c.courseTitle },
      { key: 'letter', label: 'Final', align: 'end', showAbove: 480, value: (c: any) => c.finalLetter },
      { key: 'issued', label: 'Issued', value: (c: any) => fmtDate(c.issuedAt), sortValue: (c: any) => new Date(c.issuedAt ?? 0).getTime() },
      { key: 'status', label: 'Status', custom: true, sortValue: (c: any) => c.certStatus },
    ];

    setTab = (t: Tab) => {
      this.tab = t;
      this.openCohort = undefined;
    };
    isTab = (t: Tab) => this.tab === t && !this.openCohort;
    showCohort = (c: any) => {
      this.openCohort = c;
      this.tab = 'cohorts';
    };
    backToCohorts = () => (this.openCohort = undefined);
    // The host hands the format component a `viewCard` crud function as an arg.
    view = (card: any) => {
      if (card instanceof URL || card?.id) (this.args as any).viewCard?.(card, 'isolated');
    };
    openFromRow = (card: any) => {
      if (card && (card as any).constructor === Cohort) this.showCohort(card);
      else this.view(card);
    };
    courseHue = (c: any) => statusHue(CourseStatusField, c.status);
    cohortHue = (c: any) => statusHue(CohortStatusField, c.status);
    certHue = (c: any) => statusHue(CertificateStatusField, c.certStatus);

    // Collection badges: 'all' is index 0, every badge carries its count.
    private statusBadges(items: any[], field: string, options: { value: string; label: string }[]): CollectionBadge[] {
      return [
        { id: 'all', label: 'All', count: items.length },
        ...options.map((o) => ({ id: o.value, label: o.label, count: items.filter((i) => i?.[field] === o.value).length, field, value: o.value })),
      ];
    }
    get courseBadges() {
      return this.statusBadges(this.courses, 'status', COURSE_STATUSES.map((s) => ({ value: s.value, label: s.label ?? s.value })));
    }
    get cohortBadges() {
      return this.statusBadges(this.cohorts, 'status', COHORT_STATUSES.map((s) => ({ value: s.value, label: s.label ?? s.value })));
    }
    get learnerBadges(): CollectionBadge[] {
      let orgs = [...new Set(this.learners.map((l) => l.organisation).filter(Boolean))].sort();
      return [
        { id: 'all', label: 'All', count: this.learners.length },
        ...orgs.map((o) => ({ id: o, label: o, count: this.learners.filter((l) => l.organisation === o).length, field: 'organisation', value: o })),
      ];
    }
    get certBadges() {
      return this.statusBadges(this.certificates, 'certStatus', CERTIFICATE_STATUSES.map((s) => ({ value: s.value, label: s.label ?? s.value })));
    }
    refOf = (cls: any) => identifyCard(cls) as { module: string; name: string } | undefined;
    // "+ Add <Noun>": the host's createCard opens a new instance of the type in edit mode, in this realm.
    createFor = (cls: any) => async () => {
      let ref = identifyCard(cls);
      let realm = this.realms?.[0];
      if (!ref) return;
      // Same crud-function contract as viewCard: the host passes `createCard` as a component arg.
      await (this.args as any).createCard?.(ref, undefined, realm ? { realmURL: new URL(realm) } : undefined);
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
          <nav class='tabs' role='tablist' aria-label='Academy sections'>
            {{#each TABS as |t|}}
              <button type='button' role='tab' class='tab {{if (this.isTab t.id) "on"}} {{if (and (eq t.id "cohorts") this.openCohort) "on"}}' aria-selected={{if (this.isTab t.id) 'true' 'false'}} {{on 'click' (fn this.setTab t.id)}}>{{t.label}}</button>
            {{/each}}
          </nav>
          <div class='who'>
            {{#if @model.actor}}<span class='who-l'>Acting as</span> <b>{{@model.actor.name}}</b>{{else}}<span class='who-l warn'>No actor set — open edit to choose the instructor</span>{{/if}}
          </div>
        </header>

        <main class='body'>
          {{#if this.openCohort}}
            <div class='crumb'>
              <button type='button' class='link' {{on 'click' this.backToCohorts}}>← Cohorts</button>
              <span class='crumb-name'>{{this.openCohort.cardTitle}}</span>
              <StatePill @label={{this.openCohort.status}} @hue={{this.cohortHue this.openCohort}} @dot={{true}} />
              <span class='muted'>{{this.openCohort.termLabel}}</span>
              <button type='button' class='link right' {{on 'click' (fn this.view this.openCohort)}}>Open card ↗</button>
            </div>
            <CohortWorkspace @cohort={{this.openCohort}} @context={{@context}} @actor={{@model.actor}} @authority={{@model.authority}} @onOpenCard={{this.view}} />

          {{else if (this.isTab 'home')}}
            <AcademyHome @context={{@context}} @realms={{this.realms}} @onOpenCohort={{this.showCohort}} @onOpenCourse={{this.view}} @onOpenSubmission={{this.view}} />

          {{else if (this.isTab 'courses')}}
            <CollectionShell @noun='courses' @singular='Course' @cardTypeRef={{this.refOf Course}} @items={{this.courses}} @realms={{this.realms}} @context={{@context}} @badges={{this.courseBadges}} @columns={{this.courseColumns}} @onOpen={{this.view}} @onAdd={{this.createFor Course}}>
              <:cell as |c col|>
                {{#if (eq col.key 'status')}}<StatePill @label={{c.status}} @hue={{this.courseHue c}} />{{/if}}
              </:cell>
            </CollectionShell>

          {{else if (this.isTab 'cohorts')}}
            <CollectionShell @noun='cohorts' @singular='Cohort' @cardTypeRef={{this.refOf Cohort}} @items={{this.cohorts}} @realms={{this.realms}} @context={{@context}} @badges={{this.cohortBadges}} @columns={{this.cohortColumns}} @onOpen={{this.showCohort}} @onAdd={{this.createFor Cohort}}>
              <:cell as |c col|>
                {{#if (eq col.key 'status')}}<StatePill @label={{c.status}} @hue={{this.cohortHue c}} />{{/if}}
              </:cell>
            </CollectionShell>

          {{else if (this.isTab 'learners')}}
            <CollectionShell @noun='learners' @singular='Learner' @cardTypeRef={{this.refOf Learner}} @items={{this.learners}} @realms={{this.realms}} @context={{@context}} @badges={{this.learnerBadges}} @columns={{this.learnerColumns}} @onOpen={{this.view}} @onAdd={{this.createFor Learner}} />

          {{else}}
            <CollectionShell @noun='certificates' @singular='Certificate' @cardTypeRef={{this.refOf Certificate}} @items={{this.certificates}} @realms={{this.realms}} @context={{@context}} @badges={{this.certBadges}} @columns={{this.certColumns}} @onOpen={{this.view}}>
              <:cell as |c col|>
                {{#if (eq col.key 'status')}}<StatePill @label={{c.statusLabel}} @hue={{this.certHue c}} />{{/if}}
              </:cell>
            </CollectionShell>
          {{/if}}
        </main>
      </div>
      <style scoped>
        .desk {
          --desk-accent: var(--primary, var(--boxel-highlight));
          min-height: 100%;
          display: grid;
          grid-template-rows: auto 1fr;
          color: var(--foreground, var(--boxel-dark));
          background: var(--background, var(--boxel-light));
          container-type: inline-size;
        }
        .top {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-lg);
          align-items: center;
          padding: var(--boxel-sp) var(--boxel-sp-lg);
          border-bottom: 1px solid var(--border, var(--boxel-200));
          background: var(--card, var(--boxel-light));
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
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--desk-accent);
          color: var(--primary-foreground, var(--boxel-light));
          font: 800 1.25rem var(--font-heading, var(--boxel-font-family));
        }
        h1 {
          margin: 0;
          font: 700 var(--boxel-font-size-lg) / 1.1 var(--font-heading, var(--boxel-font-family));
        }
        .tag {
          margin: 0;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .tabs {
          display: flex;
          gap: var(--boxel-sp-4xs);
          justify-content: center;
        }
        .tab {
          min-height: 44px;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border: 0;
          border-radius: 999px;
          background: none;
          color: var(--muted-foreground, var(--boxel-450));
          font: 600 var(--boxel-font-size-sm) inherit;
          cursor: pointer;
        }
        .tab.on {
          background: color-mix(in oklab, var(--desk-accent) 14%, var(--card, var(--boxel-light)));
          color: var(--foreground, var(--boxel-dark));
        }
        @media (prefers-reduced-motion: no-preference) {
          .tab {
            transition: background 140ms ease, color 140ms ease, transform 120ms ease;
          }
          .tab:active {
            transform: scale(0.97);
          }
          .body > * {
            animation: desk-enter 220ms cubic-bezier(0.2, 0.8, 0.2, 1) both;
          }
        }
        @keyframes desk-enter {
          from {
            opacity: 0;
            transform: translateY(6px);
          }
          to {
            opacity: 1;
            transform: none;
          }
        }
        .tab:focus-visible,
        .link:focus-visible {
          outline: 2px solid var(--ring, var(--boxel-highlight));
          outline-offset: 2px;
        }
        .who {
          font-size: var(--boxel-font-size-sm);
          text-align: end;
        }
        .who-l {
          color: var(--muted-foreground, var(--boxel-450));
        }
        .who-l.warn {
          color: color-mix(in oklab, var(--boxel-warning) 55%, var(--card-foreground, var(--boxel-dark)));
        }
        .body {
          padding: var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp);
          align-content: start;
        }
        .crumb {
          display: flex;
          gap: var(--boxel-sp-sm);
          align-items: center;
          font-size: var(--boxel-font-size-sm);
        }
        .crumb-name {
          font: 700 var(--boxel-font-size-lg) var(--font-heading, var(--boxel-font-family));
        }
        .link {
          border: 0;
          background: none;
          padding: 0;
          color: var(--desk-accent);
          font: 600 var(--boxel-font-size-sm) inherit;
          cursor: pointer;
        }
        .right {
          margin-left: auto;
        }
        .muted {
          color: var(--muted-foreground, var(--boxel-450));
        }
        @container (width <= 760px) {
          .top {
            grid-template-columns: 1fr;
            gap: var(--boxel-sp-sm);
          }
          .tabs {
            justify-content: flex-start;
            flex-wrap: wrap;
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
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='mark'>A</span>
        <div class='text'>
          <span class='title'>{{@model.cardTitle}}</span>
          <span class='sub'>{{if @model.tagline @model.tagline 'Course & cohort learning'}}</span>
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
          border-radius: var(--boxel-border-radius-sm);
          background: var(--primary, var(--boxel-highlight));
          color: var(--primary-foreground, var(--boxel-light));
          font-weight: 800;
        }
        .text {
          display: grid;
        }
        .title {
          font-weight: 600;
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
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
      <article class='fit'>
        <div class='fit-top'>
          <span class='mark'>A</span>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.cardTitle}}</h3>
            <span class='fit-eb'>{{if @model.tagline @model.tagline 'Course & cohort learning'}}</span>
          </div>
        </div>
        <dl class='fit-add'>
          {{#if @model.authority}}<div><dt>Authority</dt><dd>{{@model.authority.name}}</dd></div>{{/if}}
          {{#if @model.actor}}<div><dt>Acting as</dt><dd>{{@model.actor.name}}</dd></div>{{/if}}
        </dl>
      </article>
      <style scoped>
        .fit {
          height: 100%;
          padding: var(--boxel-sp-xs);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          overflow: hidden;
        }
        .fit-top {
          display: flex;
          gap: var(--boxel-sp-xs);
          align-items: flex-start;
          min-width: 0;
        }
        .mark {
          flex: none;
          width: 2rem;
          height: 2rem;
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: var(--primary, var(--boxel-highlight));
          color: var(--primary-foreground, var(--boxel-light));
          font-weight: 800;
        }
        .fit-head {
          min-width: 0;
        }
        .fit-name {
          margin: 0;
          font-size: var(--boxel-font-size-sm);
          font-weight: 700;
          line-height: 1.2;
          display: -webkit-box;
          -webkit-line-clamp: 2;
          -webkit-box-orient: vertical;
          overflow: hidden;
        }
        .fit-eb {
          font-size: 11px;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-add {
          display: none;
          margin: 0;
          font-size: var(--boxel-font-size-xs);
        }
        .fit-add div {
          display: flex;
          justify-content: space-between;
          gap: var(--boxel-sp-xs);
          padding: 2px 0;
          border-top: 1px solid var(--border, var(--boxel-200));
        }
        dt {
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 150px) {
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (width <= 120px) {
          .fit-top {
            flex-direction: column;
            align-items: flex-start;
          }
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (min-width: 250px) and (min-height: 120px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 150px) and (min-height: 190px) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
      </style>
    </template>
  };
}

function eq(a: unknown, b: unknown) {
  return a === b;
}
function and(...v: unknown[]) {
  return v.every(Boolean);
}
function fmtDate(d?: Date | string | null) {
  if (!d) return '—';
  return new Date(d).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

export default AcademyDesk;
