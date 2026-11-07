import {
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import GraduationCapIcon from '@cardstack/boxel-icons/graduation-cap';
import type Owner from '@ember/owner';
import {
  realmURL,
  type Query,
  type RealmResourceIdentifier,
  type ResolvedCodeRef,
} from '@cardstack/runtime-common';
import { Avatar } from '@cardstack/pretui/components/avatar';

import { PersonBase } from '../people/person-base';
import { Employee } from '../hr/employee';
import {
  Dot,
  Embed,
  Kv,
  Section,
  Sheet,
  Stat,
} from './components/record-sheet';
import { FitTile } from '../shared/fit-tile';
import { ENROLLMENT_STATUSES } from './enrollment-status-field';
import { SUBMISSION_STATUSES } from './submission-status-field';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { DeskRow, KvList, cardsLinkedTo } from './components/desk-status';

function learnerName(title?: string): string {
  return title ?? 'Unnamed learner';
}

function metaLine(m: any): string {
  return [m?.organisation, m?.timezone].filter(Boolean).join(' · ');
}

function contactItems(m: any) {
  return [
    { key: 'Email', value: m?.email },
    { key: 'Phone', value: m?.phone },
    { key: 'Organisation', value: m?.organisation },
    { key: 'Time zone', value: m?.timezone },
  ];
}

function enrollmentHue(status?: string | null) {
  return ENROLLMENT_STATUSES.find((s) => s.value === status)?.hue;
}

function shortDate(d?: Date | string | null): string {
  if (!d) return '';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function enrollmentMeta(e: any): string {
  return [
    e?.enrolledAt ? `enrolled ${shortDate(e.enrolledAt)}` : '',
    e?.paymentRef,
  ]
    .filter(Boolean)
    .join(' · ');
}

// Enrollment imports Learner, so the search names it by module, not class.
const ENROLLMENT_REF = {
  // @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
  module: new URL('./enrollment', import.meta.url).href,
  name: 'Enrollment',
};

// Work cards link Enrollment, which imports Learner: name them by module too.
const refTo = (module: string, name: string): ResolvedCodeRef => ({
  // @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
  module: new URL(module, import.meta.url).href as RealmResourceIdentifier,
  name,
});
const SUBMISSION_REF = refTo('./submission', 'Submission');
const QUIZ_ATTEMPT_REF = refTo('./quiz-attempt', 'QuizAttempt');
const ATTENDANCE_REF = refTo('./attendance-record', 'AttendanceRecord');

function submissionHue(status?: string | null) {
  return SUBMISSION_STATUSES.find((s) => s.value === status)?.hue;
}

function workMeta(w: any, n: 'version' | 'attemptNumber'): string {
  return [
    w?.[n] ? (n === 'version' ? `v${w[n]}` : `attempt ${w[n]}`) : '',
    shortDate(w?.submittedAt),
    n === 'version' && w?.submittedAt ? (w.isLate ? 'late' : 'on time') : '',
  ]
    .filter(Boolean)
    .join(' · ');
}

const pct = (n?: number | null) => (n == null ? '—' : `${Math.round(n)}%`);

class LearnerIsolated extends Component<typeof Learner> {
  private enrollmentsQ: ReturnType<typeof cardsLinkedTo>;
  private submissionsQ: ReturnType<typeof cardsLinkedTo>;
  private attemptsQ: ReturnType<typeof cardsLinkedTo>;
  private attendanceQ: ReturnType<typeof cardsLinkedTo>;

  constructor(owner: Owner, args: any) {
    super(owner, args);
    this.enrollmentsQ = cardsLinkedTo(
      this,
      this.args.context,
      this.args.model,
      ENROLLMENT_REF,
      'learner.id',
    );
    // Work links Enrollment, not Learner, so match any of this learner's
    // enrollments; the query re-runs as the enrollment search fills in.
    let realms = () => {
      let url = (this.args.model as any)?.[realmURL];
      return url ? [url.href] : undefined;
    };
    let linked = (ref: ResolvedCodeRef) =>
      this.args.context?.getCards(
        this,
        (): Query | undefined => {
          let ids: string[] = this.enrollments
            .map((e) => e.id as string)
            .filter(Boolean);
          return ids.length
            ? { filter: { on: ref, in: { 'enrollment.id': ids } } }
            : undefined;
        },
        realms,
        { isLive: true },
      ) as ReturnType<typeof cardsLinkedTo>;
    this.submissionsQ = linked(SUBMISSION_REF);
    this.attemptsQ = linked(QUIZ_ATTEMPT_REF);
    this.attendanceQ = linked(ATTENDANCE_REF);
  }

  get submissions(): any[] {
    return ((this.submissionsQ?.instances ?? []) as any[]).filter(Boolean);
  }
  get attempts(): any[] {
    return ((this.attemptsQ?.instances ?? []) as any[]).filter(Boolean);
  }
  get attendance(): any[] {
    return ((this.attendanceQ?.instances ?? []) as any[]).filter(Boolean);
  }
  get handedIn() {
    return this.submissions.filter(
      (w) => w.submissionStatus && w.submissionStatus !== 'not_submitted',
    ).length;
  }
  get bestQuiz() {
    let p = this.attempts
      .map((a) => a.scorePct)
      .filter((n): n is number => typeof n === 'number');
    return p.length ? Math.max(...p) : null;
  }
  get attended() {
    return this.attendance.filter((a) =>
      ['present', 'late'].includes(a.attendanceStatus),
    ).length;
  }

  get enrollments(): any[] {
    return ((this.enrollmentsQ?.instances ?? []) as any[]).filter(Boolean);
  }
  count(status: string) {
    return this.enrollments.filter((e) => e.enrollmentStatus === status).length;
  }
  get cohortLabel() {
    let n = this.enrollments.length;
    return `${n} cohort${n === 1 ? '' : 's'}`;
  }
  get stats(): {
    label: string;
    value?: string | null;
    hint?: string | null;
  }[] {
    return [
      {
        label: 'Cohorts',
        value: String(this.enrollments.length),
        hint: this.enrollments[0]?.cohortName || 'not enrolled',
      },
      {
        label: 'Submitted',
        value: `${this.handedIn} / ${this.submissions.length}`,
        hint: 'assignments',
      },
      {
        label: 'Quiz',
        value: pct(this.bestQuiz),
        hint: this.attempts.length
          ? `${this.attempts.length} attempt${this.attempts.length === 1 ? '' : 's'}`
          : 'no attempts',
      },
      {
        label: 'Attendance',
        value: `${this.attended} / ${this.attendance.length}`,
        hint: 'live sessions',
      },
    ];
  }
  get workCount() {
    return this.submissions.length + this.attempts.length;
  }
  get details() {
    let m = this.args.model;
    return [
      ...contactItems(m),
      { key: 'Enrollments', value: String(this.enrollments.length) },
    ];
  }

  <template>
    <Sheet
      @mark={{@model.initials}}
      @title={{@model.title}}
      @meta={{metaLine @model}}
    >
      <:status><Dot
          @hue={{if this.enrollments.length 'green'}}
        >{{this.cohortLabel}}</Dot></:status>
      <:stats>{{#each this.stats as |st|}}<Stat
            @label={{st.label}}
            @value={{st.value}}
            @sub={{st.hint}}
          />{{/each}}</:stats>
      <:main>

        <Section @title='Contact'><KvList
            @items={{contactItems @model}}
          /></Section>
        <Section @title='Enrollments'>
          {{#each this.enrollments as |e|}}
            <DeskRow @title={{e.cohortName}} @meta={{enrollmentMeta e}}>
              <Dot
                @hue={{enrollmentHue e.enrollmentStatus}}
              >{{e.enrollmentStatus}}</Dot>
            </DeskRow>
          {{else}}
            <DeskRow @title='No enrollments' @meta='Enroll from a cohort.' />
          {{/each}}
        </Section>
        <Section @title='Work'>
          {{#each this.submissions as |w|}}
            <DeskRow
              @title={{w.assignmentTitle}}
              @meta={{workMeta w 'version'}}
            >
              <Dot
                @hue={{submissionHue w.submissionStatus}}
              >{{w.statusLabel}}</Dot>
            </DeskRow>
          {{/each}}
          {{#each this.attempts as |a|}}
            <DeskRow
              @title={{a.quizTitle}}
              @meta={{workMeta a 'attemptNumber'}}
            >
              <Dot @hue={{if a.passed 'green' 'red'}}>{{pct a.scorePct}}</Dot>
            </DeskRow>
          {{/each}}
          {{#unless this.workCount}}
            <DeskRow
              @title='No work yet'
              @meta='Submissions and quiz attempts show here.'
            />
          {{/unless}}
        </Section>
        {{#if @model.notes}}
          <Section @title='Notes'><p
              class='notes'
            >{{@model.notes}}</p></Section>
        {{/if}}
      </:main>
      <:side>
        <Section @title='Linked'>
          <Kv @label='Staff record'>{{#if
              @model.linkedEmployee
            }}<@fields.linkedEmployee
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
        </Section>
        <Section @title='Details'><KvList @items={{this.details}} /></Section>
      </:side></Sheet>
    <style scoped>
      .notes {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-top: 1px solid var(--border);
        white-space: pre-wrap;
      }
    </style>
  </template>
}

/**
 * A person who takes cohorts. Extends PersonBase (name, email,
 * phone, photo, initials) and adds only what a learner has that a contact
 * does not. `linkedEmployee` is set when the academy trains its own staff —
 * the learner IS an employee — so attendance can roll up to HR without the
 * Employee card learning anything about courses.
 */
export class Learner extends PersonBase {
  static displayName = 'Learner';
  static icon = GraduationCapIcon;

  @field organisation = contains(StringField);
  @field timezone = contains(StringField, {
    description:
      'IANA zone, e.g. Asia/Kuala_Lumpur. Used to show live lesson times.',
  });
  @field notes = contains(StringField);
  @field linkedEmployee = linksTo(() => Employee);

  @field title = contains(StringField, {
    computeVia: function (this: Learner) {
      return this.name?.trim() || 'Unnamed learner';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Learner) {
      return this.name?.trim() || 'Unnamed learner';
    },
  });

  static isolated = LearnerIsolated;

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <Embed
        @mark={{@model.initials}}
        @title={{@model.title}}
        @meta={{metaLine @model}}
      >
        <:default>
          <KvList @items={{contactItems @model}} />
          {{#if @model.linkedEmployee}}
            <Kv @label='Staff record'><@fields.linkedEmployee
                @format='atom'
                @displayContainer={{false}}
              /></Kv>
          {{/if}}
        </:default>
      </Embed>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'><Avatar
          @name={{learnerName @model.title}}
          @src={{@model.photo.resolvedUrl}}
          @size={{16}}
        /><span class='name'>{{@model.title}}</span></span>
      <style scoped>
        .atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-4xs);
          max-inline-size: 100%;
          min-inline-size: 0;
          font-size: 0.75rem;
          font-weight: 600;
          vertical-align: middle;
        }
        .name {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FitTile>
        <:avatar><Avatar
            @name={{learnerName @model.title}}
            @src={{@model.photo.resolvedUrl}}
            @size={{32}}
          /></:avatar>
        <:title>{{@model.title}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:fact>{{if @model.email @model.email '—'}}</:fact>
        <:relations>{{#if @model.linkedEmployee}}<@fields.linkedEmployee
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
    </template>
  };
}

export default Learner;
