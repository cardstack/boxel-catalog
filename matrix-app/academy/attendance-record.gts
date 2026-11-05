import {
  CardDef,
  Component,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import DateTimeField from '@cardstack/base/datetime';
import UserCheckIcon from '@cardstack/boxel-icons/user-check';

import {
  AttendanceStatusField,
  attendanceLabel,
  attendanceHue,
} from './attendance-status-field';
import { eq } from '@cardstack/boxel-ui/helpers';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Enrollment } from './enrollment';
import { Lesson } from './lesson';
import { Employee } from '../hr/employee';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { FitTile } from '../../ui-component/components/fit-tile';
import type { KeyValueItem } from '../../ui-component/components/key-value';
import { FittedExtras } from '../procurement/vendor';

/**
 * One learner × one live lesson × one mark. Small on purpose: the Attendance
 * Grid renders hundreds of these, Mark Attendance upserts them one per
 * enrolment per lesson, and the completion rule counts them. `sessionDate`
 * is stored even though the lesson has a date, because a lesson can be
 * re-run and the mark belongs to the day it was taken.
 */
export class AttendanceRecord extends CardDef {
  static displayName = 'Attendance Record';
  static icon = UserCheckIcon;

  @field enrollment = linksTo(() => Enrollment);
  @field lesson = linksTo(() => Lesson);
  @field sessionDate = contains(DateField);
  @field attendanceStatus = contains(AttendanceStatusField);
  @field note = contains(StringField);
  @field markedBy = linksTo(() => Employee);
  @field markedAt = contains(DateTimeField);

  @field learnerName = contains(StringField, {
    computeVia: function (this: AttendanceRecord) {
      return this.enrollment?.learnerName ?? '';
    },
  });
  @field lessonTitle = contains(StringField, {
    computeVia: function (this: AttendanceRecord) {
      return this.lesson?.cardTitle ?? '';
    },
  });
  @field statusLabel = contains(StringField, {
    computeVia: function (this: AttendanceRecord) {
      return attendanceLabel(this.attendanceStatus);
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: AttendanceRecord) {
      return `${this.enrollment?.learnerName ?? 'Learner'} · ${this.lesson?.cardTitle ?? 'lesson'} · ${attendanceLabel(this.attendanceStatus)}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get hue() {
      return attendanceHue(this.args.model?.attendanceStatus);
    }
    get sessionLine() {
      return sessionLine(this.args.model);
    }
    <template>
      <article class='ar'>
        <header class='hero'>
          <span class='mark' aria-hidden='true'>At</span>
          <div class='hero-id'>
            <h1>{{if @model.learnerName @model.learnerName 'Unlinked learner'}}
              ·
              {{@model.lessonTitle}}</h1>
            <p class='hero-sub'>{{this.sessionLine}}</p>
          </div>
          <div class='chips'>
            <StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
              @dot={{true}}
            />
          </div>
        </header>
        <dl class='stats'>
          <div><dt>Status</dt><dd>{{@model.statusLabel}}</dd></div>
          <div><dt>Session</dt><dd>{{dateLong @model.sessionDate}}</dd></div>
          {{#if @model.lesson}}<div><dt>Lesson</dt><dd
              >{{@model.lessonTitle}}</dd></div>{{/if}}
        </dl>
        {{#if @model.note}}
          <section class='panel'>
            <h2>Note</h2>
            <p>{{@model.note}}</p>
          </section>
        {{/if}}
        <div class='cols'>
          <section class='panel'>
            <h2>Record</h2>
            <dl class='kv'>
              <div><dt>Session date</dt><dd>{{dateLong
                    @model.sessionDate
                  }}</dd></div>
              <div><dt>Status</dt><dd>{{@model.statusLabel}}</dd></div>
              {{#if @model.markedBy}}<div><dt>Marked by</dt><dd
                  >{{@model.markedBy.name}}</dd></div>{{/if}}
              {{#if @model.markedAt}}<div><dt>Marked at</dt><dd>{{fmtDateTime
                      @model.markedAt
                    }}</dd></div>{{/if}}
            </dl>
          </section>
          <section class='panel'>
            <h2>Linked</h2>
            <ul class='rels'>
              {{#if @model.enrollment}}<li><span
                  >Enrollment</span><@fields.enrollment
                    @format='atom'
                  /></li>{{/if}}
              {{#if @model.lesson}}<li><span>Lesson</span><@fields.lesson
                    @format='atom'
                  /></li>{{/if}}
              {{#if @model.markedBy}}<li><span>Marked by</span><@fields.markedBy
                    @format='atom'
                  /></li>{{/if}}
            </ul>
          </section>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .ar {
            max-width: 56rem;
            margin: 0 auto;
            container-type: inline-size;
            padding: var(--boxel-sp-lg);
            display: grid;
            gap: var(--boxel-sp-lg);
            color: var(--foreground);
            background: var(--background);
          }
          .hero {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 3rem;
            block-size: 3rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .hero-id {
            flex: 1 1 14rem;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
          }
          .hero-sub {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stats {
            margin: 0;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
            gap: var(--boxel-sp);
          }
          .stats > div {
            padding: var(--boxel-sp);
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: var(--shadow-sm);
          }
          .stats dt,
          .kv dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .stats dd {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            color: var(--primary);
          }
          .cols {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
            gap: var(--boxel-sp-lg);
          }
          .panel {
            padding: var(--boxel-sp-lg);
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: var(--shadow-sm);
            min-width: 0;
          }
          .panel h2 {
            margin: 0 0 var(--boxel-sp);
            font-size: var(--boxel-font-size);
            font-weight: 600;
          }
          .panel p {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
          }
          .kv {
            margin: 0;
            display: grid;
            gap: var(--boxel-sp-xs);
            font-size: var(--boxel-font-size-sm);
          }
          .kv > div {
            display: flex;
            justify-content: space-between;
            gap: var(--boxel-sp-sm);
          }
          .kv dd {
            margin: 0;
            font-weight: 600;
          }
          .rels {
            list-style: none;
            margin: 0;
            padding: 0;
            display: grid;
            gap: var(--boxel-sp-xs);
            font-size: var(--boxel-font-size-sm);
          }
          .rels li {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs);
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return attendanceHue(this.args.model?.attendanceStatus);
    }
    get sessionLine() {
      return sessionLine(this.args.model);
    }
    get facts() {
      return factsOf(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <span class='mark' aria-hidden='true'>At</span>
          <div class='emb-id'>
            <h4 class='emb-title'>{{if
                @model.learnerName
                @model.learnerName
                'Learner'
              }}
              ·
              {{@model.lessonTitle}}</h4>
            <p class='emb-sub'>{{this.sessionLine}}</p>
          </div>
          <div class='emb-chips'>
            <StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
              @dot={{true}}
            />
          </div>
        </header>
        {{#if @model.note}}<p class='emb-note'>{{@model.note}}</p>{{/if}}
        <dl class='emb-kv'>
          {{#each this.facts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <div class='emb-rels'>
          {{#if @model.enrollment}}<span class='emb-rel'>Enrollment
              <@fields.enrollment @format='atom' /></span>{{/if}}
          {{#if @model.lesson}}<span class='emb-rel'>Lesson
              <@fields.lesson @format='atom' /></span>{{/if}}
          {{#if @model.markedBy}}<span class='emb-rel'>Marked by
              <@fields.markedBy @format='atom' /></span>{{/if}}
        </div>
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
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2.5rem;
            block-size: 2.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
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
          .emb-sub,
          .emb-note {
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
      return attendanceHue(this.args.model?.attendanceStatus);
    }
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>At</span>
        <span class='atom-name'>{{if
            @model.learnerName
            @model.learnerName
            'Learner'
          }}
          ·
          {{@model.lessonTitle}}</span>
        {{#if @model.attendanceStatus}}<span class='atom-chip'><StatePill
              @label={{@model.statusLabel}}
              @hue={{this.hue}}
            /></span>{{/if}}
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
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
          .mark {
            display: inline-grid;
            place-items: center;
            flex: none;
            inline-size: 1.25rem;
            block-size: 1.25rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: 0.625rem;
            font-weight: 600;
            line-height: 1;
          }
          .atom-name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .atom-chip {
            flex: none;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return attendanceHue(this.args.model?.attendanceStatus);
    }
    get sessionLine() {
      return sessionLine(this.args.model);
    }
    get facts(): KeyValueItem[] {
      return factsOf(this.args.model);
    }
    get relations() {
      let m = this.args.model;
      return [
        ...(m?.enrollment ? ['Enrollment'] : []),
        ...(m?.lesson ? ['Lesson'] : []),
        ...(m?.markedBy ? ['Marked by'] : []),
      ];
    }
    <template>
      <FittedExtras @facts={{this.facts}} @relations={{this.relations}}>
        <:default>
          <FitTile>
            <:avatar><span class='mark' aria-hidden='true'>At</span></:avatar>
            <:title><span class='fit-title' role='heading' aria-level='3'>{{if
                  @model.learnerName
                  @model.learnerName
                  'Learner'
                }}</span></:title>
            <:subtitle>{{@model.lessonTitle}}</:subtitle>
            <:status>
              <StatePill
                @label={{@model.statusLabel}}
                @hue={{this.hue}}
                @dot={{true}}
              />
            </:status>
            <:fact>{{this.sessionLine}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Enrollment')}}<@fields.enrollment
              @format='atom'
            />{{else if (eq label 'Lesson')}}<@fields.lesson
              @format='atom'
            />{{else}}<@fields.markedBy @format='atom' />{{/if}}
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
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };
}

function sessionLine(m?: Partial<AttendanceRecord> | null): string {
  let lesson = m?.lesson as any;
  return [
    dateLong(m?.sessionDate),
    [lesson?.kindLabel?.toLowerCase(), lesson?.durationLabel]
      .filter(Boolean)
      .join(', '),
  ]
    .filter(Boolean)
    .join(' · ');
}

function factsOf(m?: Partial<AttendanceRecord> | null): KeyValueItem[] {
  return [
    { key: 'Learner', value: m?.learnerName || '—' },
    { key: 'Lesson', value: m?.lessonTitle || '—' },
    { key: 'Session', value: dateLong(m?.sessionDate) },
    { key: 'Status', value: m?.statusLabel || '—' },
    { key: 'Marked by', value: (m?.markedBy as any)?.name || '—' },
    { key: 'Marked at', value: fmtDateTime(m?.markedAt) },
    ...(m?.note ? [{ key: 'Note', value: m.note }] : []),
  ];
}

export function fmtDate(d?: Date | string | null): string {
  if (!d) return '—';
  return toDate(d)!.toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}

function dateLong(d?: Date | string | null): string {
  if (!d) return '—';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function fmtDateTime(d?: Date | string | null): string {
  if (!d) return '—';
  return new Date(d).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

export default AttendanceRecord;
