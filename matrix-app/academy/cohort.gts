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
import {
  statusField,
  statusHue,
  type StatusOption,
} from '@cardstack/catalog/fields/status/status';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Avatar } from '../../ui-component/components/avatar';
import { FitTile } from '../../ui-component/components/fit-tile';
import {
  KeyValue,
  type KeyValueItem,
} from '../../ui-component/components/key-value';
import { Stat } from '../../ui-component/components/stat';
import { FittedExtras } from '../procurement/vendor';
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

export const CohortStatusField = statusField({
  displayName: 'Cohort Status',
  options: COHORT_STATUSES,
  transitions: {
    planned: ['running'],
    running: ['closed'],
    closed: ['running'],
  },
});

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
    get subtitle() {
      let m = this.args.model;
      return [m?.courseTitle, m?.termLabel].filter(Boolean).join(' · ');
    }
    get weekText() {
      let m = this.args.model;
      return m?.currentWeek && m?.weekCount
        ? `${m.currentWeek} / ${m.weekCount}`
        : '—';
    }
    get releasedText() {
      let m = this.args.model;
      return `${m?.releasedCount ?? 0} / ${m?.course?.moduleCount ?? 0}`;
    }
    get details(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Term', value: m?.termLabel || '—' },
        {
          key: 'Week',
          value:
            m?.currentWeek && m?.weekCount
              ? `${m.currentWeek} of ${m.weekCount}`
              : '—',
        },
        { key: 'Seats', value: m?.capacity ? String(m.capacity) : '—' },
        { key: 'Released', value: this.releasedText },
        { key: 'Lead', value: m?.leadInstructorName || '—' },
      ];
    }
    // The host hands the format component a `viewCard` crud function as an arg.
    view = (card: any) => {
      if (card?.id) (this.args as any).viewCard?.(card, 'isolated');
    };
    <template>
      <article class='cohort'>
        <header class='iso-head'>
          <Avatar
            @name='C h'
            @hue='var(--muted-foreground)'
            @size={{48}}
            aria-hidden='true'
          />
          <div class='iso-id'>
            <h1>{{@model.cardTitle}}</h1>
            <p class='iso-sub'>{{this.subtitle}}</p>
          </div>
          <div class='iso-chips'>
            <StatePill @label={{@model.status}} @hue={{this.hue}} />
            {{#if @model.currentWeek}}
              <StatePill
                @label='week {{@model.currentWeek}} / {{@model.weekCount}}'
                @hue='blue'
              />
            {{/if}}
          </div>
        </header>

        <div class='stat-row'>
          <Stat @label='Week' @value={{this.weekText}} @roll={{false}} />
          <Stat
            @label='Seats'
            @value={{if @model.capacity @model.capacity '—'}}
            @roll={{false}}
          />
          <Stat
            @label='Released'
            @value={{this.releasedText}}
            @roll={{false}}
          />
          <Stat
            @label='Instructors'
            @value={{if @model.instructors.length @model.instructors.length 0}}
            @hint={{@model.leadInstructorName}}
            @roll={{false}}
          />
        </div>

        {{#if @context.getCards}}
          <CohortWorkspace
            @cohort={{@model}}
            @context={{@context}}
            @onOpenCard={{this.view}}
          />
        {{else}}
          <section class='iso-card'>
            <CohortTimeline
              @weeks={{this.weeks}}
              @todayIndex={{this.today.index}}
              @todayFraction={{this.today.fraction}}
            />
          </section>
        {{/if}}

        <div class='iso-body'>
          <div class='iso-col'>
            <section class='iso-card'>
              <h2>Releases</h2>
              {{#if @model.releases.length}}
                <ol class='releases'>
                  {{#each @fields.releases as |R|}}<li><R /></li>{{/each}}
                </ol>
              {{else}}
                <p class='empty'>Nothing released yet.</p>
              {{/if}}
            </section>
            {{#if @model.notes}}
              <section class='iso-card'>
                <h2>Notes</h2>
                <p class='notes'>{{@model.notes}}</p>
              </section>
            {{/if}}
          </div>
          <div class='iso-col'>
            <section class='iso-card'>
              <h2>Linked</h2>
              <dl class='rels'>
                <div><dt>Course</dt><dd>{{#if @model.course}}<@fields.course
                        @format='atom'
                        @displayContainer={{false}}
                      />{{else}}—{{/if}}</dd></div>
                {{#each @fields.instructors as |Ia|}}
                  <div><dt>Instructor</dt><dd><Ia
                        @format='atom'
                        @displayContainer={{false}}
                      /></dd></div>
                {{/each}}
              </dl>
            </section>
            <section class='iso-card'>
              <h2>Details</h2>
              <KeyValue @items={{this.details}} @rows='ruled' />
            </section>
          </div>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
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
          .iso-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp);
          }
          .iso-id {
            flex: 1 1 14rem;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-xl);
            font-weight: 600;
            line-height: 1.25;
          }
          .iso-sub {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .iso-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stat-row {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10.5rem, 1fr));
            gap: var(--boxel-sp);
          }
          .iso-body {
            display: grid;
            grid-template-columns: minmax(0, 2fr) minmax(16rem, 1fr);
            gap: var(--boxel-sp-lg);
            align-items: start;
          }
          .iso-col {
            display: grid;
            gap: var(--boxel-sp-lg);
            min-width: 0;
          }
          .iso-card {
            padding: var(--boxel-sp-lg);
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: var(--shadow-sm);
            min-width: 0;
          }
          h2 {
            margin: 0 0 var(--boxel-sp);
            font-size: var(--boxel-font-size);
            font-weight: 600;
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
            font-size: var(--boxel-font-size-sm);
            white-space: pre-wrap;
          }
          .empty {
            margin: 0;
            color: var(--muted-foreground);
            font-size: var(--boxel-font-size-sm);
          }
          .rels {
            margin: 0;
            display: grid;
            gap: var(--boxel-sp-xs);
          }
          .rels div {
            display: grid;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
          }
          .rels dt {
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .rels dd {
            margin: 0;
            display: flex;
            flex-wrap: wrap;
            min-width: 0;
            max-width: 100%;
          }
          .rels dd > * {
            max-width: 100%;
            min-width: 0;
          }
          @container (width <= 43.75rem) {
            .iso-body {
              grid-template-columns: minmax(0, 1fr);
            }
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return statusHue(CohortStatusField, this.args.model?.status);
    }
    get weekText() {
      let m = this.args.model;
      return m?.currentWeek && m?.weekCount
        ? `week ${m.currentWeek} / ${m.weekCount}`
        : '';
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.courseTitle ?? m?.courseCode, m?.termLabel]
        .filter(Boolean)
        .join(' · ');
    }
    get facts() {
      let m = this.args.model;
      return [
        { key: 'Term', value: m?.termLabel ?? '—' },
        {
          key: 'Week',
          value: m?.currentWeek ? `${m.currentWeek} of ${m.weekCount}` : '—',
        },
        { key: 'Seats', value: m?.capacity ? String(m.capacity) : '—' },
        { key: 'Released', value: String(m?.releasedCount ?? 0) },
        { key: 'Lead', value: m?.leadInstructorName ?? '—' },
      ];
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <Avatar
            @name='Ch'
            @hue='var(--muted-foreground)'
            @size={{40}}
            aria-hidden='true'
          />
          <div class='emb-id'>
            <h4 class='emb-title'>{{@model.cardTitle}}</h4>
            <p class='emb-sub'>{{this.subtitle}}</p>
          </div>
          <div class='emb-chips'>
            <StatePill @label={{@model.status}} @hue={{this.hue}} />
            {{#if this.weekText}}<StatePill
                @label={{this.weekText}}
                @hue='blue'
              />{{/if}}
          </div>
        </header>
        <dl class='emb-kv'>
          {{#each this.facts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        {{#if @model.course}}
          <div class='emb-rels'><span class='emb-rel'>Course
              <@fields.course @format='atom' /></span></div>
        {{/if}}
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-sm);
            font-size: var(--boxel-font-size-sm);
          }
          .emb-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-id {
            flex: 1 1 12rem;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .emb-sub {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-kv {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
            margin: 0;
          }
          .emb-kv dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-kv dd {
            margin: 0;
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-rel {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return statusHue(CohortStatusField, this.args.model?.status);
    }
    <template>
      <span class='cohort-atom'>
        <Avatar
          @name='Ch'
          @hue='var(--muted-foreground)'
          @size={{20}}
          aria-hidden='true'
        />
        <span class='cohort-atom-name'>{{@model.cardTitle}}</span>
        {{#if @model.status}}<span class='cohort-atom-chip'><StatePill
              @label={{@model.status}}
              @hue={{this.hue}}
            /></span>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .cohort-atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.5rem;
            row-gap: 1.5rem;
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .cohort-atom-name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .cohort-atom-chip {
            flex: none;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return statusHue(CohortStatusField, this.args.model?.status);
    }
    get weekText() {
      let m = this.args.model;
      return m?.currentWeek && m?.weekCount
        ? `week ${m.currentWeek} / ${m.weekCount}`
        : '';
    }
    get subtitle() {
      let m = this.args.model;
      return [m?.courseTitle ?? m?.courseCode, m?.termLabel]
        .filter(Boolean)
        .join(' · ');
    }
    get fact() {
      let m = this.args.model;
      let n = m?.releasedCount ?? 0;
      return `${n} ${n === 1 ? 'module' : 'modules'} released`;
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      return [
        { key: 'Term', value: m?.termLabel ?? '' },
        {
          key: 'Week',
          value: m?.currentWeek ? `${m.currentWeek} of ${m.weekCount}` : '—',
        },
        { key: 'Seats', value: m?.capacity ? String(m.capacity) : '—' },
        { key: 'Lead', value: m?.leadInstructorName ?? '—' },
      ];
    }
    get relations() {
      return this.args.model?.course ? ['Course'] : [];
    }
    <template>
      <FittedExtras @facts={{this.facts}} @relations={{this.relations}}>
        <:default>
          <FitTile>
            <:avatar>
              <Avatar
                @name='Ch'
                @hue='var(--muted-foreground)'
                @size={{32}}
                aria-hidden='true'
              />
            </:avatar>
            <:title><span
                class='fit-title'
                role='heading'
                aria-level='3'
              >{{@model.cardTitle}}</span></:title>
            <:subtitle>{{this.subtitle}}</:subtitle>
            <:status>
              <StatePill @label={{@model.status}} @hue={{this.hue}} />
              {{#if this.weekText}}<StatePill
                  @label={{this.weekText}}
                  @hue='blue'
                />{{/if}}
            </:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation>
          <@fields.course @format='atom' />
        </:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
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
