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
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { Enrollment } from './enrollment';
import { Lesson } from './lesson';
import { Employee } from '@cardstack/catalog/cards/hr/employee';

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
    <template>
      <article class='ar'>
        <header class='hero'>
          <div class='hero-text'>
            <span class='eyebrow'>Attendance ·
              {{fmtDate @model.sessionDate}}</span>
            <h1>{{if
                @model.learnerName
                @model.learnerName
                'Unlinked learner'
              }}</h1>
            <p class='meta'>
              <StatePill
                @label={{@model.statusLabel}}
                @hue={{attendanceHue @model.attendanceStatus}}
                @dot={{true}}
              />
              {{#if @model.lesson}}<span><@fields.lesson
                    @format='atom'
                  /></span>{{/if}}
            </p>
          </div>
        </header>
        <dl class='facts'>
          {{#if @model.markedBy}}<div><dt>Marked by</dt><dd
              >{{@model.markedBy.name}}</dd></div>{{/if}}
          {{#if @model.markedAt}}<div><dt>Marked at</dt><dd>{{fmtDateTime
                  @model.markedAt
                }}</dd></div>{{/if}}
          {{#if @model.note}}<div class='wide'><dt>Note</dt><dd
              >{{@model.note}}</dd></div>{{/if}}
        </dl>
      </article>
      <style scoped>
        .ar {
          max-width: 40rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground, var(--boxel-dark));
          background: var(--background, var(--boxel-light));
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font: 700 var(--boxel-font-size-xl) / 1.15
            var(--font-heading, var(--boxel-font-family));
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          display: flex;
          gap: var(--boxel-sp-sm);
          align-items: center;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground, var(--boxel-450));
        }
        .facts {
          margin: 0;
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp);
          border: 1px solid var(--border, var(--boxel-200));
          border-radius: var(--radius, var(--boxel-border-radius));
          background: var(--card, var(--boxel-light));
        }
        .wide {
          grid-column: 1 / -1;
        }
        dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
        }
        dd {
          margin: 0;
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <div class='text'>
          <span class='title'>{{if
              @model.learnerName
              @model.learnerName
              'Learner'
            }}</span>
          <span class='sub'>{{@model.lessonTitle}}
            ·
            {{fmtDate @model.sessionDate}}</span>
        </div>
        <StatePill
          @label={{@model.statusLabel}}
          @hue={{attendanceHue @model.attendanceStatus}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: 1fr auto;
          gap: var(--boxel-sp-xs);
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
          color: var(--muted-foreground, var(--boxel-450));
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <StatePill
        @label={{@model.statusLabel}}
        @hue={{attendanceHue @model.attendanceStatus}}
      />
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <article class='fit'>
        <div class='fit-top'>
          <div class='fit-head'>
            <h3 class='fit-name'>{{if
                @model.learnerName
                @model.learnerName
                'Learner'
              }}</h3>
            <span class='fit-eb'>{{@model.lessonTitle}}</span>
          </div>
          <span class='fit-pill'><StatePill
              @label={{@model.statusLabel}}
              @hue={{attendanceHue @model.attendanceStatus}}
            /></span>
        </div>
        <dl class='fit-add'>
          <div><dt>Session</dt><dd>{{fmtDate @model.sessionDate}}</dd></div>
          {{#if @model.note}}<div><dt>Note</dt><dd
              >{{@model.note}}</dd></div>{{/if}}
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
          font-size: 11px;
          color: var(--muted-foreground, var(--boxel-450));
        }
        .fit-pill {
          flex: none;
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
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        @container fitted-card (height <= 80px) {
          .fit-top {
            align-items: center;
          }
          .fit-name {
            -webkit-line-clamp: 1;
          }
        }
        @container fitted-card (width <= 220px) {
          .fit-pill {
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

export function fmtDate(d?: Date | string | null): string {
  if (!d) return '—';
  return new Date(d).toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
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
