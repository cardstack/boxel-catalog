import { markDefinition } from '@cardstack/base/mark-definition';
import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import DateRangeField from '@cardstack/base/date-range-field';
import NumberField from '@cardstack/base/number';
import UsersIcon from '@cardstack/boxel-icons/users';
import { FieldContainer } from '@cardstack/boxel-ui/components';

import { SectionedEdit } from '@cardstack/catalog/components/sectioned-edit';

import {
  statusField,
  statusHue,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { InstructorAssignmentField } from './instructor-assignment-field';
import { plannedReleaseDate } from './release-rule-field';
import { Course } from './course';
import { Module } from './course-module';
import { Employee } from '../hr/employee';
import {
  CohortTimeline,
  type TimelineMark,
  type TimelineWeek,
} from './components/cohort-timeline';
import { CohortWorkspace } from './components/cohort-workspace';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';

export const COHORT_STATUSES: StatusOption[] = [
  {
    value: 'planned',
    label: 'Planned',
    hue: 'slate',
    meaning: 'Dates set, seats open, nothing released yet.',
  },
  {
    value: 'running',
    label: 'Running',
    hue: 'teal',
    meaning: 'Between start and end. Modules release, work is due.',
  },
  {
    value: 'closed',
    label: 'Closed',
    hue: 'green',
    meaning: 'Finished. Certificates issued; no new enrolments.',
    terminal: true,
  },
];

export const CohortStatusField = markDefinition(
  statusField({
    displayName: 'Cohort Status',
    options: COHORT_STATUSES,
    transitions: {
      planned: ['running'],
      running: ['closed'],
      closed: ['running'],
    },
  }),
);

/** The event: a module was released to this cohort, by whom, when. */
export class ModuleReleaseField extends FieldDef {
  static displayName = 'Module Release';
  @field module = linksTo(() => Module);
  @field releasedAt = contains(DateTimeField);
  @field releasedBy = linksTo(() => Employee);

  @field moduleTitle = contains(StringField, {
    computeVia: function (this: ModuleReleaseField) {
      return this.module?.cardTitle ?? '';
    },
  });
  @field releasedByName = contains(StringField, {
    computeVia: function (this: ModuleReleaseField) {
      return this.releasedBy?.name ?? '';
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='rel'>
        <span class='rel-mod'>{{@model.moduleTitle}}</span>
        <span class='rel-when'>{{fmtDate @model.releasedAt}}{{#if
            @model.releasedByName
          }} · {{@model.releasedByName}}{{/if}}</span>
      </span>
      <style scoped>
        .rel {
          display: inline-flex;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
          font-size: var(--boxel-font-size-sm);
        }
        .rel-mod {
          font-weight: 600;
        }
        .rel-when {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

/**
 * One run of a Course with real dates, real people and a seat count. The
 * cohort is the operational unit of the academy: it is what you release a
 * module TO, take attendance IN, and close. Everything that happens to a
 * learner hangs off an Enrollment in a cohort, never off the course.
 *
 * `releases[]` are events (written by Release Module). The planned week for
 * each module comes from the module's Release Rule; the timeline draws both,
 * hollow until the release actually happened.
 */
export class Cohort extends CardDef {
  static displayName = 'Cohort';
  static icon = UsersIcon;

  @field name = contains(StringField);
  @field course = linksTo(() => Course);
  @field term = contains(DateRangeField);
  @field capacity = contains(NumberField);
  @field status = contains(CohortStatusField);
  @field instructors = containsMany(InstructorAssignmentField);
  @field releases = containsMany(ModuleReleaseField);
  @field notes = contains(StringField);

  @field courseTitle = contains(StringField, {
    computeVia: function (this: Cohort) {
      return this.course?.cardTitle ?? '';
    },
  });
  @field courseCode = contains(StringField, {
    computeVia: function (this: Cohort) {
      return this.course?.code ?? '';
    },
  });
  @field weekCount = contains(NumberField, {
    computeVia: function (this: Cohort) {
      return weekCountOf(this.term?.start, this.term?.end);
    },
  });
  @field currentWeek = contains(NumberField, {
    computeVia: function (this: Cohort) {
      return currentWeekOf(this.term?.start, this.term?.end);
    },
  });
  @field termLabel = contains(StringField, {
    computeVia: function (this: Cohort) {
      return termLabel(this.term?.start, this.term?.end);
    },
  });
  @field releasedCount = contains(NumberField, {
    computeVia: function (this: Cohort) {
      return (this.releases ?? []).length;
    },
  });
  @field leadInstructorName = contains(StringField, {
    computeVia: function (this: Cohort) {
      let lead =
        (this.instructors ?? []).find((i: any) => i?.role === 'lead') ??
        (this.instructors ?? [])[0];
      return (lead as any)?.instructorName ?? '';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Cohort) {
      return this.name?.trim() || 'Unnamed cohort';
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get hue() {
      return statusHue(CohortStatusField, this.args.model?.status);
    }
    get weeks() {
      return buildCohortWeeks(this.args.model);
    }
    get today() {
      return todayPosition(
        this.args.model?.term?.start,
        this.args.model?.term?.end,
      );
    }
    // The host hands the format component a `viewCard` crud function as an arg.
    view = (card: any) => {
      if (card?.id) (this.args as any).viewCard?.(card, 'isolated');
    };
    <template>
      <article class='cohort'>
        <header class='hero'>
          <div class='hero-text'>
            <span class='eyebrow'>
              {{#if @model.course}}<@fields.course @format='atom' />{{else}}No
                course linked{{/if}}
              <StatePill
                @label={{@model.status}}
                @hue={{this.hue}}
                @dot={{true}}
              />
            </span>
            <h1>{{@model.cardTitle}}</h1>
            <p class='term'>{{@model.termLabel}}{{#if @model.weekCount}}
                ·
                {{@model.weekCount}}
                weeks{{/if}}{{#if @model.currentWeek}}
                ·
                <b>week {{@model.currentWeek}}</b>{{/if}}</p>
          </div>
          <dl class='facts'>
            <div><dt>Seats</dt><dd>{{if
                  @model.capacity
                  @model.capacity
                  '—'
                }}</dd></div>
            <div><dt>Released</dt><dd>{{@model.releasedCount}}<span
                  class='of'
                >/{{@model.course.moduleCount}}</span></dd></div>
            {{#if @model.leadInstructorName}}<div><dt>Lead</dt><dd
                >{{@model.leadInstructorName}}</dd></div>{{/if}}
          </dl>
        </header>

        {{#if @context.getCards}}
          <CohortWorkspace
            @cohort={{@model}}
            @context={{@context}}
            @onOpenCard={{this.view}}
          />
        {{else}}
          <section class='rail-wrap'>
            <CohortTimeline
              @weeks={{this.weeks}}
              @todayIndex={{this.today.index}}
              @todayFraction={{this.today.fraction}}
            />
          </section>
        {{/if}}

        <div class='cols'>
          <section class='panel'>
            <h2>Instructors</h2>
            {{#if @model.instructors.length}}
              <div class='stack'>
                {{#each @fields.instructors as |Ia|}}<div class='ia-row'><Ia
                    /></div>{{/each}}
              </div>
            {{else}}
              <p class='empty'>No instructors assigned.</p>
            {{/if}}
          </section>
          <section class='panel'>
            <h2>Releases</h2>
            {{#if @model.releases.length}}
              <ol class='releases'>
                {{#each @fields.releases as |R|}}<li><R /></li>{{/each}}
              </ol>
            {{else}}
              <p class='empty'>Nothing released yet. Use Release Module above.</p>
            {{/if}}
          </section>
        </div>
        {{#if @model.notes}}
          <section class='panel'><h2>Notes</h2><p
              class='notes'
            >{{@model.notes}}</p></section>
        {{/if}}
      </article>
      <style scoped>
        .cohort {
          max-width: 60rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .hero {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-lg);
          align-items: start;
        }
        .eyebrow {
          display: inline-flex;
          gap: var(--boxel-sp-xs);
          align-items: center;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-xs) 0 0;
          font-size: var(--boxel-font-size-2xl);
          font-weight: 700;
          line-height: 1.1;
          letter-spacing: -0.015em;
        }
        .term {
          margin: var(--boxel-sp-xs) 0 0;
          color: var(--muted-foreground);
        }
        .term b {
          color: var(--foreground);
        }
        .facts {
          margin: 0;
          display: flex;
          gap: var(--boxel-sp);
          padding: var(--boxel-sp) var(--boxel-sp-lg);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        dd {
          margin: 0;
          font-weight: 700;
          font-size: var(--boxel-font-size-lg);
          font-variant-numeric: tabular-nums;
        }
        .of {
          font-size: var(--boxel-font-size-sm);
          font-weight: 400;
          color: var(--muted-foreground);
        }
        .rail-wrap {
          padding: var(--boxel-sp) var(--boxel-sp-lg);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        .cols {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--boxel-sp-sm);
        }
        .panel {
          padding: var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        h2 {
          margin: 0 0 var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-sm);
          text-transform: uppercase;
          letter-spacing: 0.06em;
          color: var(--muted-foreground);
        }
        .stack {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .releases {
          margin: 0;
          padding: 0;
          list-style: none;
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
        .notes {
          margin: 0;
          white-space: pre-wrap;
        }
        .empty {
          margin: 0;
          color: var(--muted-foreground);
          font-style: italic;
          font-size: var(--boxel-font-size-sm);
        }
        @container (width <= 43.75rem) {
          .hero,
          .cols {
            grid-template-columns: 1fr;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return statusHue(CohortStatusField, this.args.model?.status);
    }
    get weeks() {
      return buildCohortWeeks(this.args.model, { attributesOnly: true });
    }
    get today() {
      return todayPosition(
        this.args.model?.term?.start,
        this.args.model?.term?.end,
      );
    }
    <template>
      <div class='row'>
        <div class='text'>
          <span class='title'>{{@model.cardTitle}}</span>
          <span class='sub'>{{#if @model.courseCode}}{{@model.courseCode}}
              ·
            {{/if}}{{@model.termLabel}}</span>
        </div>
        <div class='mini'>
          <CohortTimeline
            @weeks={{this.weeks}}
            @todayIndex={{this.today.index}}
            @todayFraction={{this.today.fraction}}
            @compact={{true}}
          />
        </div>
        <StatePill @label={{@model.status}} @hue={{this.hue}} />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: minmax(10rem, 1fr) minmax(8rem, 1.2fr) auto;
          gap: var(--boxel-sp-sm);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .mini {
          min-width: 0;
        }
        @container (width <= 30rem) {
          .row {
            grid-template-columns: 1fr auto;
          }
          .mini {
            display: none;
          }
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

  static edit = class Edit extends Component<typeof this> {
    sections = [
      { id: 'identity', label: 'Identity' },
      { id: 'term', label: 'Term & seats' },
      { id: 'instructors', label: 'Instructors' },
      { id: 'releases', label: 'Releases' },
      { id: 'notes', label: 'Notes' },
    ];
    <template>
      <SectionedEdit
        @sections={{this.sections}}
        @ariaLabel='Cohort sections'
        as |e|
      >
        <e.Section @id='identity' @title='Identity' @cols={{3}}>
          <FieldContainer @label='Name' @vertical={{true}}><@fields.name
            /></FieldContainer>
          <FieldContainer @label='Course' @vertical={{true}}><@fields.course
            /></FieldContainer>
          <FieldContainer @label='Status' @vertical={{true}}><@fields.status
            /></FieldContainer>
        </e.Section>
        <e.Section
          @id='term'
          @title='Term & seats'
          @hint='the term draws the timeline weeks'
          @cols={{2}}
        >
          <FieldContainer @label='Term' @vertical={{true}}><@fields.term
            /></FieldContainer>
          <FieldContainer
            @label='Capacity (seats)'
            @vertical={{true}}
          ><@fields.capacity /></FieldContainer>
        </e.Section>
        <e.Section @id='instructors' @title='Instructors' @cols={{1}}>
          <FieldContainer
            @label='Teaching roles'
            @vertical={{true}}
          ><@fields.instructors /></FieldContainer>
        </e.Section>
        <e.Section
          @id='releases'
          @title='Releases'
          @hint='set by Release Module'
          @cols={{1}}
        >
          <FieldContainer
            @label='Release events'
            @vertical={{true}}
          ><@fields.releases @format='atom' /></FieldContainer>
        </e.Section>
        <e.Section @id='notes' @title='Notes' @cols={{1}}>
          <FieldContainer
            @label='Internal notes'
            @vertical={{true}}
          ><@fields.notes /></FieldContainer>
        </e.Section>
      </SectionedEdit>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(CohortStatusField, this.args.model?.status);
    }
    get weeks() {
      // Prerendered fitted does not resolve links: weeks come from the term
      // and the stored release events only, never from the course.
      return buildCohortWeeks(this.args.model, { attributesOnly: true });
    }
    get today() {
      return todayPosition(
        this.args.model?.term?.start,
        this.args.model?.term?.end,
      );
    }
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <div class='fit-head'>
            <h3 class='fit-name'>{{@model.cardTitle}}</h3>
            <span class='fit-eb'>{{#if @model.courseCode}}{{@model.courseCode}}
                ·
              {{/if}}{{@model.termLabel}}</span>
          </div>
          <span class='fit-pill'><StatePill
              @label={{@model.status}}
              @hue={{this.hue}}
            /></span>
        </div>
        <div class='fit-rail'>
          <CohortTimeline
            @weeks={{this.weeks}}
            @todayIndex={{this.today.index}}
            @todayFraction={{this.today.fraction}}
            @compact={{true}}
          />
        </div>
        <dl class='fit-add'>
          <div><dt>Week</dt><dd>{{if @model.currentWeek @model.currentWeek '—'}}
              of
              {{@model.weekCount}}</dd></div>
          <div><dt>Released</dt><dd>{{@model.releasedCount}} modules</dd></div>
          {{#if @model.leadInstructorName}}<div><dt>Lead</dt><dd
              >{{@model.leadInstructorName}}</dd></div>{{/if}}
          <div><dt>Seats</dt><dd>{{if
                @model.capacity
                @model.capacity
                '—'
              }}</dd></div>
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
        .fit-head {
          min-width: 0;
          flex: 1;
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
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .fit-pill {
          flex: none;
        }
        .fit-rail {
          display: none;
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
          padding: 0.125rem 0;
          border-top: 1px solid var(--border);
        }
        dt {
          color: var(--muted-foreground);
        }
        dd {
          margin: 0;
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
        @container fitted-card (height <= 5rem) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 13.75rem) {
          .fit-pill {
            display: none;
          }
        }
        @container fitted-card (min-width: 8.75rem) and (min-height: 6.875rem) {
          .fit-rail {
            display: block;
          }
        }
        @container fitted-card (width <= 7.5rem) {
          .fit-top {
            flex-direction: column;
            align-items: flex-start;
          }
          .fit-eb {
            display: none;
          }
        }
        @container fitted-card (min-width: 15.625rem) and (min-height: 7.5rem) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
        @container fitted-card (min-width: 9.375rem) and (min-height: 11.875rem) {
          .fit-add {
            display: block;
            margin-top: auto;
          }
        }
      </style>
    </template>
  };
}

const DAY = 86_400_000;
const WEEK = 7 * DAY;

export function weekCountOf(
  start?: Date | string | null,
  end?: Date | string | null,
): number {
  if (!start || !end) return 0;
  let s = toDate(start)!.getTime();
  let e = toDate(end)!.getTime();
  if (e <= s) return 0;
  return Math.max(1, Math.ceil((e - s + DAY) / WEEK));
}

export function currentWeekOf(
  start?: Date | string | null,
  end?: Date | string | null,
  now = new Date(),
): number | undefined {
  let pos = todayPosition(start, end, now);
  return pos.index == null ? undefined : pos.index + 1;
}

export function todayPosition(
  start?: Date | string | null,
  end?: Date | string | null,
  now = new Date(),
): { index?: number; fraction?: number } {
  let n = weekCountOf(start, end);
  if (!n || !start) return {};
  let s = toDate(start)!.getTime();
  let t = now.getTime();
  if (t < s || t > s + n * WEEK) return {};
  let idx = Math.floor((t - s) / WEEK);
  let fraction = ((t - s) % WEEK) / WEEK;
  return { index: Math.min(idx, n - 1), fraction };
}

export function termLabel(
  start?: Date | string | null,
  end?: Date | string | null,
): string {
  if (!start && !end) return 'No term set';
  let f = (d: Date | string) =>
    toDate(d)!.toLocaleDateString(undefined, {
      month: 'short',
      day: 'numeric',
    });
  if (start && end)
    return `${f(start)} – ${f(end)}, ${toDate(end)!.getFullYear()}`;
  return start ? `From ${f(start)}` : `Until ${f(end!)}`;
}

/**
 * Turns a cohort into timeline weeks. With `attributesOnly` (fitted/embedded,
 * where links are not resolved) only the term and the stored release events
 * are used; otherwise the course's modules add planned releases, due dates,
 * live lessons and quizzes.
 */
export function buildCohortWeeks(
  cohort: Partial<Cohort> | null | undefined,
  opts?: { attributesOnly?: boolean },
): TimelineWeek[] {
  let start = cohort?.term?.start;
  let end = cohort?.term?.end;
  let n = weekCountOf(start, end);
  if (!n || !start) return [];
  let s = toDate(start)!;
  s.setHours(0, 0, 0, 0);
  let weeks: TimelineWeek[] = [];
  for (let i = 0; i < n; i++) {
    let ws = new Date(s.getTime() + i * WEEK);
    let we = new Date(ws.getTime() + WEEK - 1);
    weeks.push({
      index: i + 1,
      start: ws,
      end: we,
      label: `${ws.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}`,
      marks: [],
    });
  }
  let place = (m: TimelineMark) => {
    let idx = Math.floor((m.date.getTime() - s.getTime()) / WEEK);
    if (idx >= 0 && idx < n) weeks[idx].marks.push(m);
  };

  let releasedIds = new Set<string>();
  for (let r of (cohort?.releases ?? []) as any[]) {
    if (!r?.releasedAt) continue;
    let id = r.module?.id;
    if (id) releasedIds.add(id);
    place({
      kind: 'release',
      label: r.moduleTitle || r.module?.cardTitle || 'Module',
      date: new Date(r.releasedAt),
      done: true,
    });
  }

  if (!opts?.attributesOnly) {
    let modules = ((cohort?.course as any)?.modules ?? []) as any[];
    for (let m of modules) {
      if (!m) continue;
      if (!m.id || !releasedIds.has(m.id)) {
        let planned = plannedReleaseDate(m.releaseRule, start);
        if (planned) {
          place({
            kind: 'release',
            label: m.cardTitle ?? 'Module',
            date: planned,
            done: false,
          });
        }
      }
      for (let a of (m.assignments ?? []) as any[]) {
        let due = a?.dueWindow?.dueAt;
        if (due)
          place({
            kind: 'due',
            label: a.cardTitle ?? 'Assignment',
            date: new Date(due),
          });
      }
      for (let l of (m.lessons ?? []) as any[]) {
        if (l?.kind === 'live' && l.liveSessionAt) {
          place({
            kind: 'live',
            label: l.cardTitle ?? 'Live lesson',
            date: new Date(l.liveSessionAt),
          });
        }
      }
      for (let q of (m.quizzes ?? []) as any[]) {
        // A quiz has no date of its own; it opens with its module.
        let planned = plannedReleaseDate(m.releaseRule, start);
        if (q && planned)
          place({ kind: 'quiz', label: q.cardTitle ?? 'Quiz', date: planned });
      }
    }
  }
  for (let w of weeks)
    w.marks.sort((a, b) => a.date.getTime() - b.date.getTime());
  return weeks;
}

export function releasedModuleIds(
  cohort: Partial<Cohort> | null | undefined,
): string[] {
  return ((cohort?.releases ?? []) as any[])
    .map((r) => r?.module?.id)
    .filter((id): id is string => !!id);
}

function fmtDate(d?: Date | string | null): string {
  if (!d) return '';
  return toDate(d)!.toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}

export default Cohort;
