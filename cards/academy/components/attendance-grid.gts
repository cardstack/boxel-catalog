import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { realmURL } from '@cardstack/runtime-common';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';

import MarkAttendanceCommand, {
  AttendanceMarkField,
} from '../commands/mark-attendance-command';
import {
  ATTENDANCE_STATUSES,
  ATTENDANCE_HUES,
  countsAsAttended,
} from '../attendance-status-field';
import { stateColor } from '@cardstack/catalog/components/state-pill';
import { EmptyState } from '@cardstack/pretui/components/empty-state';

interface Signature {
  Args: {
    cohort: any;
    enrollments: any[];
    /** Live lessons of released modules, in order. */
    lessons: any[];
    records: any[];
    context?: any;
    markedBy?: any;
    onSaved?: (message: string) => void;
  };
  Element: HTMLElement;
}

const CYCLE = ['present', 'late', 'absent', 'excused'];

/**
 * Learners down, live sessions across; click a cell to cycle the mark,
 * "All present" to fill a column, Save to write the column through Mark
 * Attendance (one upsert per learner). Edits stay local until saved and a
 * dirty column says so. Row tail is the learner's attendance share against
 * sessions held so far — the number the completion rule reads.
 */
export class AttendanceGrid extends GlimmerComponent<Signature> {
  /** lessonId → enrollmentId → status (pending edits). */
  @tracked pending: Record<string, Record<string, string>> = {};
  @tracked busyLesson: string | undefined;
  @tracked error: string | undefined;
  @tracked notice: string | undefined;

  get rows(): any[] {
    return (this.args.enrollments ?? [])
      .filter((e) => e && e.enrollmentStatus !== 'withdrawn')
      .slice()
      .sort((a, b) => (a.learnerName ?? '').localeCompare(b.learnerName ?? ''));
  }
  get lessons(): any[] {
    return (this.args.lessons ?? []).filter(Boolean);
  }
  get heldLessons(): any[] {
    let now = Date.now();
    return this.lessons.filter(
      (l) => !l.liveSessionAt || new Date(l.liveSessionAt).getTime() <= now,
    );
  }

  saved = (enrollment: any, lesson: any): string | undefined =>
    (this.args.records ?? []).find(
      (r) => r?.enrollment?.id === enrollment.id && r?.lesson?.id === lesson.id,
    )?.attendanceStatus;

  mark = (enrollment: any, lesson: any): string | undefined =>
    this.pending[lesson.id]?.[enrollment.id] ?? this.saved(enrollment, lesson);

  isDirty = (enrollment: any, lesson: any) => {
    let p = this.pending[lesson.id]?.[enrollment.id];
    return p != null && p !== this.saved(enrollment, lesson);
  };
  columnDirty = (lesson: any) => this.rows.some((e) => this.isDirty(e, lesson));
  columnMarked = (lesson: any) =>
    this.rows.filter((e) => this.mark(e, lesson)).length;
  isFuture = (lesson: any) =>
    lesson.liveSessionAt &&
    new Date(lesson.liveSessionAt).getTime() > Date.now();

  cycle = (enrollment: any, lesson: any) => {
    let cur = this.mark(enrollment, lesson);
    let next = CYCLE[(CYCLE.indexOf(cur ?? '') + 1) % CYCLE.length];
    this.setMark(lesson.id, enrollment.id, next);
  };
  allPresent = (lesson: any) => {
    let col = { ...(this.pending[lesson.id] ?? {}) };
    for (let e of this.rows) if (!this.mark(e, lesson)) col[e.id] = 'present';
    this.pending = { ...this.pending, [lesson.id]: col };
  };
  private setMark(lessonId: string, enrollmentId: string, status: string) {
    this.pending = {
      ...this.pending,
      [lessonId]: { ...(this.pending[lessonId] ?? {}), [enrollmentId]: status },
    };
  }
  discard = (lesson: any) => {
    let next = { ...this.pending };
    delete next[lesson.id];
    this.pending = next;
  };

  save = async (lesson: any) => {
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      this.error = 'Commands are unavailable in this mode';
      return;
    }
    let realm = this.args.cohort?.[realmURL]?.href;
    if (!realm) {
      this.error = 'Could not determine the realm';
      return;
    }
    let col = this.pending[lesson.id] ?? {};
    let marks = Object.entries(col)
      .filter(([eid, status]) => status !== this.saved({ id: eid }, lesson))
      .map(
        ([enrollmentId, status]) =>
          new AttendanceMarkField({ enrollmentId, status }),
      );
    if (!marks.length) return;
    this.busyLesson = lesson.id;
    this.error = undefined;
    this.notice = undefined;
    try {
      let res = (await new MarkAttendanceCommand(ctx).execute({
        lesson,
        sessionDate: lesson.liveSessionAt
          ? new Date(lesson.liveSessionAt)
          : new Date(),
        marks,
        markedBy: this.args.markedBy,
        existingRecords: this.args.records ?? [],
        realm,
      } as any)) as any;
      this.notice = res?.message;
      this.discard(lesson);
      this.args.onSaved?.(this.notice ?? '');
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busyLesson = undefined;
    }
  };

  pct = (enrollment: any): number | undefined => {
    let held = this.heldLessons;
    if (!held.length) return undefined;
    let attended = held.filter((l) =>
      countsAsAttended(this.mark(enrollment, l)),
    ).length;
    return Math.round((attended / held.length) * 100);
  };

  style = (status?: string) => {
    if (!status) return '';
    let c = stateColor(ATTENDANCE_HUES[status] ?? 'slate');
    return `background:${c.bg};color:${c.fg};`;
  };
  label = (status?: string) =>
    ATTENDANCE_STATUSES.find((s) => s.value === status)?.label ?? 'Unmarked';
  short = (status?: string) => (status ? this.label(status)[0] : '·');

  <template>
    <div class='ag' ...attributes>
      {{#if this.lessons.length}}
        {{#if this.rows.length}}
          <div class='scroll'>
            <table class='table'>
              <caption class='cap'>Attendance ·
                {{this.rows.length}}
                learners ·
                {{this.heldLessons.length}}
                of
                {{this.lessons.length}}
                sessions held</caption>
              <thead>
                <tr>
                  <th scope='col' class='th-name'>Learner</th>
                  {{#each this.lessons as |l|}}
                    <th
                      scope='col'
                      class='th-l {{if (this.isFuture l) "future"}}'
                      title={{l.cardTitle}}
                    >
                      <span class='l-date'>{{fmtDay l.liveSessionAt}}</span>
                      <span class='l-title'>{{l.cardTitle}}</span>
                      <span class='l-count'>{{this.columnMarked
                          l
                        }}/{{this.rows.length}}</span>
                    </th>
                  {{/each}}
                  <th scope='col' class='th-pct'>Attend.</th>
                </tr>
              </thead>
              <tbody>
                {{#each this.rows as |e|}}
                  <tr>
                    <th scope='row' class='td-name'>{{e.learnerName}}</th>
                    {{#each this.lessons as |l|}}
                      {{#let (this.mark e l) as |m|}}
                        <td class='cell'>
                          <button
                            type='button'
                            class='m
                              {{if (this.isDirty e l) "dirty"}}
                              {{unless m "empty"}}'
                            style={{htmlSafeStyle (this.style m)}}
                            aria-label='{{e.learnerName}}, {{l.cardTitle}}: {{this.label
                              m
                            }}. Click to change.'
                            title={{this.label m}}
                            {{on 'click' (fn this.cycle e l)}}
                          >{{this.short m}}</button>
                        </td>
                      {{/let}}
                    {{/each}}
                    {{#let (this.pct e) as |p|}}
                      <td
                        class='td-pct
                          {{if
                            (low
                              p @cohort.course.completionRule.minAttendancePct
                            )
                            "low"
                          }}'
                      >{{if (isNum p) (concat p '%') '—'}}</td>
                    {{/let}}
                  </tr>
                {{/each}}
              </tbody>
              <tfoot>
                <tr>
                  <td class='td-name foot-l'>Column actions</td>
                  {{#each this.lessons as |l|}}
                    <td class='foot'>
                      <button
                        type='button'
                        class='mini'
                        {{on 'click' (fn this.allPresent l)}}
                      >All present</button>
                      {{#if (this.columnDirty l)}}
                        <Button
                          @tone='primary'
                          @appearance='accent'
                          @size='xs'
                          @busy={{eq this.busyLesson l.id}}
                          @disabled={{eq this.busyLesson l.id}}
                          {{on 'click' (fn this.save l)}}
                        >Save</Button>
                        <button
                          type='button'
                          class='mini'
                          {{on 'click' (fn this.discard l)}}
                        >Undo</button>
                      {{/if}}
                    </td>
                  {{/each}}
                  <td></td>
                </tr>
              </tfoot>
            </table>
          </div>
          <div class='legend' aria-hidden='true'>
            {{#each ATTENDANCE_STATUSES as |s|}}
              <span class='lg'><i
                  style={{htmlSafeStyle (this.style s.value)}}
                >{{this.short s.value}}</i>{{s.label}}</span>
            {{/each}}
            <span class='lg'><i class='dirty-dot'></i>unsaved</span>
          </div>
          {{#if this.error}}<Alert @tone='danger'>{{this.error}}</Alert>{{/if}}
          {{#if this.notice}}<Alert
              @tone='success'
            >{{this.notice}}</Alert>{{/if}}
        {{else}}
          <EmptyState
            @size='s'
            @title='No active learners'
            @message='Enrol learners in the cohort to mark their attendance.'
          />
        {{/if}}
      {{else}}
        <EmptyState
          @size='s'
          @title='No live lessons yet'
          @message='Attendance starts with the first released module that has a live session.'
        />
      {{/if}}
    </div>
    <style scoped>
      .ag {
        color: var(--foreground);
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .scroll {
        overflow-x: auto;
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .table {
        border-collapse: separate;
        border-spacing: 0;
        width: 100%;
        font-size: var(--boxel-font-size-sm);
      }
      .cap {
        caption-side: top;
        text-align: start;
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      th,
      td {
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        border-top: 1px solid var(--border);
        text-align: center;
        white-space: nowrap;
      }
      thead th {
        border-top: 0;
        background: var(--muted);
        font-weight: 600;
        vertical-align: bottom;
      }
      .th-name,
      .td-name {
        text-align: start;
        position: sticky;
        left: 0;
        background: var(--card);
        z-index: 1;
        padding-left: var(--boxel-sp);
      }
      thead .th-name {
        background: var(--muted);
      }
      .td-name {
        font-weight: 600;
      }
      .th-l.future {
        opacity: 0.55;
      }
      .l-date {
        display: block;
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
      }
      .l-title {
        display: block;
        max-width: 7rem;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: var(--boxel-font-size-2xs);
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .l-count {
        display: block;
        font-size: var(--boxel-font-size-2xs);
        font-weight: 400;
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .m {
        width: 2rem;
        height: 2rem;
        border: 1px solid transparent;
        border-radius: var(--boxel-border-radius-sm);
        background: var(--muted);
        color: var(--muted-foreground);
        font: 700 var(--boxel-font-size-sm) inherit;
        cursor: pointer;
        position: relative;
      }
      .m.empty {
        background: transparent;
        border-color: var(--border);
      }
      .m:hover {
        border-color: var(--primary);
      }
      .m:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 1px;
      }
      .m.dirty::after,
      .dirty-dot {
        content: '';
        position: absolute;
        top: -0.1875rem;
        right: -0.1875rem;
        width: 0.5rem;
        height: 0.5rem;
        border-radius: 50%;
        background: var(--primary);
        box-shadow: 0 0 0 2px var(--card);
      }
      .dirty-dot {
        position: static;
        display: inline-block;
        box-shadow: none;
      }
      .td-pct {
        font-variant-numeric: tabular-nums;
        font-weight: 600;
        border-left: 2px solid var(--border);
      }
      .th-pct {
        border-left: 2px solid var(--border);
      }
      .td-pct.low {
        color: var(--destructive-ink);
      }
      tfoot td {
        background: var(--muted);
        vertical-align: top;
      }
      .foot {
        display: table-cell;
      }
      .foot-l {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        font-weight: 400;
      }
      .mini {
        display: block;
        margin: 0.125rem auto;
        border: 0;
        background: none;
        padding: 0;
        color: var(--primary-ink);
        font-weight: 600;
        font-size: var(--boxel-font-size-2xs);
        cursor: pointer;
      }
      .legend {
        display: flex;
        gap: var(--boxel-sp-sm);
        flex-wrap: wrap;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .lg {
        display: inline-flex;
        gap: 0.25rem;
        align-items: center;
      }
      .lg i {
        width: 1rem;
        height: 1rem;
        display: grid;
        place-items: center;
        border-radius: 0.1875rem;
        font-weight: 700;
        font-size: var(--boxel-font-size-2xs);
        font-style: normal;
      }
    </style>
  </template>
}

function htmlSafeStyle(s: string) {
  return htmlSafe(s);
}
function fmtDay(d?: Date | string | null) {
  if (!d) return 'TBD';
  return new Date(d).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
  });
}
function eq(a: unknown, b: unknown) {
  return a === b;
}
function isNum(n: unknown) {
  return typeof n === 'number';
}
function concat(a: unknown, b: unknown) {
  return `${a}${b}`;
}
function low(p?: number, min?: number) {
  return p != null && min != null && p < min;
}

export default AttendanceGrid;
