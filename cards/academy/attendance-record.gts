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
import { Employee } from '../hr/employee';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { FittedCard } from '@cardstack/boxel-ui/components';

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
          color: var(--foreground);
          background: var(--background);
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          line-height: 1.15;
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          display: flex;
          gap: var(--boxel-sp-sm);
          align-items: center;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .facts {
          margin: 0;
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        .wide {
          grid-column: 1 / -1;
        }
        dt {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
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
          color: var(--muted-foreground);
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
      <FittedCard @titleTag='h3'>
        <:eyebrow>{{@model.lessonTitle}}</:eyebrow>
        <:title>{{if @model.learnerName @model.learnerName 'Learner'}}</:title>
        <:subtitle>{{fmtDate @model.sessionDate}}</:subtitle>
        <:badgeRight><StatePill
            @label={{@model.statusLabel}}
            @hue={{attendanceHue @model.attendanceStatus}}
          /></:badgeRight>
        <:footer>{{@model.note}}</:footer>
      </FittedCard>
    </template>
  };
}

export function fmtDate(d?: Date | string | null): string {
  if (!d) return '—';
  return toDate(d)!.toLocaleDateString(undefined, {
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
