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
  countsAsAttended,
} from './attendance-status-field';
import { Enrollment } from './enrollment';
import { Lesson } from './lesson';
import { Employee } from '../hr/employee';
import { toDate } from '@cardstack/catalog/fields/effective-period/effective-period-field';
import { RichFittedCard, Detail } from '../shared/rich-fitted-card';
import {
  AtomChip,
  Dot,
  Embed,
  Kv,
  Mark,
  Section,
  Sheet,
  Stat,
} from './components/record-sheet';
import { IsoFrame } from '../shared/compact-sheet';

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
      <IsoFrame>
        <Sheet @mark='At' @title={{headline @model}} @meta={{metaLine @model}}>
          <:status>
            <Dot @hue={{attendanceHue @model.attendanceStatus}}>{{lower
                @model.statusLabel
              }}</Dot>
          </:status>
          <:stats>
            <Stat
              @label='Status'
              @value={{@model.statusLabel}}
              @sub={{attendedLine @model.attendanceStatus}}
            />
            <Stat
              @label='Session'
              @value={{fmtShort @model.sessionDate}}
              @sub={{@model.lessonTitle}}
            />
            <Stat
              @label='Marked'
              @value={{fmtShort @model.markedAt}}
              @sub={{@model.markedBy.name}}
            />
          </:stats>
          <:main>
            <Section @title='Note'>
              <p class='note'>{{if @model.note @model.note '—'}}</p>
            </Section>
            <Section @title='Record'>
              <Kv @label='Session date' @mono={{true}}>{{fmtLong
                  @model.sessionDate
                }}</Kv>
              <Kv @label='Status'><Dot
                  @hue={{attendanceHue @model.attendanceStatus}}
                >{{lower @model.statusLabel}}</Dot></Kv>
              <Kv @label='Marked by'>{{if
                  @model.markedBy
                  @model.markedBy.name
                  '—'
                }}</Kv>
              <Kv @label='Marked at' @mono={{true}}>{{fmtDateTime
                  @model.markedAt
                }}</Kv>
            </Section>
          </:main>
          <:side>
            <Section @title='Linked'>
              <Kv @label='Enrollment'>{{#if
                  @model.enrollment
                }}<@fields.enrollment
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</Kv>
              <Kv @label='Lesson'>{{#if @model.lesson}}<@fields.lesson
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</Kv>
              <Kv @label='Marked by'>{{#if @model.markedBy}}<@fields.markedBy
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</Kv>
            </Section>
            <Section @title='Details'>
              <Kv @label='Learner'>{{dash @model.learnerName}}</Kv>
              <Kv @label='Lesson'>{{dash @model.lessonTitle}}</Kv>
              <Kv @label='Session' @mono={{true}}>{{fmtLong
                  @model.sessionDate
                }}</Kv>
              <Kv @label='Status'>{{@model.statusLabel}}</Kv>
              <Kv @label='Marked at' @mono={{true}}>{{fmtDateTime
                  @model.markedAt
                }}</Kv>
            </Section>
          </:side>
        </Sheet>
      </IsoFrame>
      <style scoped>
        .note {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-block-start: 1px solid var(--border);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <Embed @mark='At' @title={{headline @model}} @meta={{metaLine @model}}>
        <:status>
          <Dot @hue={{attendanceHue @model.attendanceStatus}}>{{lower
              @model.statusLabel
            }}</Dot>
        </:status>
        <:fact>{{if @model.note @model.note '—'}}</:fact>
        <:default>
          <Kv @label='Learner'>{{dash @model.learnerName}}</Kv>
          <Kv @label='Lesson'>{{dash @model.lessonTitle}}</Kv>
          <Kv @label='Session' @mono={{true}}>{{fmtLong
              @model.sessionDate
            }}</Kv>
          <Kv @label='Status'>{{@model.statusLabel}}</Kv>
          <Kv @label='Marked by'>{{#if @model.markedBy}}<@fields.markedBy
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
          <Kv @label='Marked at' @mono={{true}}>{{fmtDateTime
              @model.markedAt
            }}</Kv>
          <Kv @label='Enrollment'>{{#if @model.enrollment}}<@fields.enrollment
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
        </:default>
      </Embed>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AtomChip @mark='At' @title={{headline @model}}><Dot
          @hue={{attendanceHue @model.attendanceStatus}}
        >{{lower @model.statusLabel}}</Dot></AtomChip>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <RichFittedCard>
        <:avatar><Mark @text='At' /></:avatar>
        <:title>{{headline @model}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><Dot @hue={{attendanceHue @model.attendanceStatus}}>{{lower
              @model.statusLabel
            }}</Dot></:status>
        <:fact>{{if
            @model.note
            @model.note
            (attendedLine @model.attendanceStatus)
          }}</:fact>
        <:relations>{{#if @model.enrollment}}<@fields.enrollment
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}{{#if @model.lesson}}<@fields.lesson
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
        <:details>
          {{#if @model.markedBy}}<Detail @label='Marked by'><@fields.markedBy
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.markedAt}}<Detail
              @label='Marked at'
              @value={{fmtDateTime @model.markedAt}}
            />{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };
}

function headline(m?: Partial<AttendanceRecord> | null): string {
  return (
    [m?.learnerName, m?.lessonTitle].filter(Boolean).join(' · ') ||
    'Attendance record'
  );
}
function metaLine(m?: Partial<AttendanceRecord> | null): string {
  return m?.sessionDate ? fmtLong(m.sessionDate) : 'No session date';
}
function attendedLine(v?: string | null): string {
  if (!v) return 'not marked';
  return countsAsAttended(v) ? 'counts as attended' : 'does not count';
}
function fmtShort(d?: Date | string | null): string {
  if (!d) return '';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });
}
function fmtLong(d?: Date | string | null): string {
  if (!d) return '—';
  return toDate(d)!.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}
function dash(v: unknown): string {
  return v == null || v === '' ? '—' : String(v);
}
function lower(v?: string | null) {
  return (v ?? '').toLowerCase();
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
