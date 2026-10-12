import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';

import { letterFor } from '../grade-scale-field';

interface Signature {
  Args: {
    enrollments: any[];
    assignments: any[];
    submissions: any[];
    quizzes?: any[];
    attempts?: any[];
    gradeScale?: any;
    onOpenSubmission?: (submission: any) => void;
    onGradeSubmission?: (submission: any) => void;
    onOpenEnrollment?: (enrollment: any) => void;
  };
  Element: HTMLElement;
}

type Cell =
  | {
      state: 'graded';
      submission: any;
      letter?: string;
      pct: number;
      total: number;
      max: number;
    }
  | { state: 'submitted'; submission: any; late: boolean }
  | { state: 'returned'; submission: any }
  | { state: 'overdue' }
  | { state: 'missing' };

/**
 * Learners down, assignments across, one cell per pair — the view every
 * instructor asks for and every LMS buries. Cells are the submission's
 * state, coloured as data: graded shows the letter, awaiting shows a button
 * that opens the grader, overdue-and-missing is a red dash. Row tail is the
 * points-weighted overall; column head shows how many await grading so the
 * grader knows where the pile is. Sort by name or by overall.
 */
export class Gradebook extends GlimmerComponent<Signature> {
  @tracked sortKey: 'name' | 'overall' = 'name';
  @tracked sortDesc = false;

  get assignments(): any[] {
    return (this.args.assignments ?? []).filter(Boolean);
  }
  get quizzes(): any[] {
    return (this.args.quizzes ?? []).filter(Boolean);
  }

  latestFor(enrollmentId: string, assignmentId: string): any | undefined {
    let subs = (this.args.submissions ?? []).filter(
      (s) =>
        s?.enrollment?.id === enrollmentId &&
        s?.assignment?.id === assignmentId,
    );
    if (!subs.length) return undefined;
    let graded = subs.find((s) => s.submissionStatus === 'graded' && s.grade);
    if (graded) return graded;
    return subs.slice().sort((a, b) => (b.version ?? 0) - (a.version ?? 0))[0];
  }

  cell = (enrollment: any, assignment: any): Cell => {
    let s = this.latestFor(enrollment.id, assignment.id);
    if (!s) {
      let due = assignment.dueWindow?.dueAt;
      return due && new Date(due).getTime() < Date.now()
        ? { state: 'overdue' }
        : { state: 'missing' };
    }
    if (s.submissionStatus === 'graded') {
      let g = s.grade ?? {};
      let max = g.maxPoints ?? assignment.effectiveMaxPoints ?? 0;
      let total = g.total ?? 0;
      return {
        state: 'graded',
        submission: s,
        letter: g.letter,
        pct: max ? Math.round((total / max) * 100) : 0,
        total,
        max,
      };
    }
    if (s.submissionStatus === 'returned')
      return { state: 'returned', submission: s };
    return { state: 'submitted', submission: s, late: !!s.isLate };
  };

  quizCell = (enrollment: any, quiz: any) => {
    let attempts = (this.args.attempts ?? []).filter(
      (a) => a?.enrollment?.id === enrollment.id && a?.quiz?.id === quiz.id,
    );
    if (!attempts.length) return { state: 'missing' as const };
    let best = attempts
      .slice()
      .sort((a, b) => (b.scorePct ?? 0) - (a.scorePct ?? 0))[0];
    return {
      state: best.passed ? ('passed' as const) : ('failed' as const),
      pct: best.scorePct ?? 0,
      tries: attempts.length,
    };
  };

  overall = (enrollment: any): { pct?: number; letter?: string } => {
    let earned = 0;
    let max = 0;
    for (let a of this.assignments) {
      let c = this.cell(enrollment, a);
      if (c.state === 'graded') {
        earned += c.total;
        max += c.max;
      }
    }
    if (!max) return {};
    let pct = Math.round((earned / max) * 100);
    return { pct, letter: letterFor(pct, this.args.gradeScale) };
  };

  awaiting = (assignment: any) =>
    (this.args.enrollments ?? []).filter(
      (e) => this.cell(e, assignment).state === 'submitted',
    ).length;

  get rows(): any[] {
    let rows = (this.args.enrollments ?? []).filter(
      (e) => e && e.enrollmentStatus !== 'withdrawn',
    );
    let dir = this.sortDesc ? -1 : 1;
    return rows.slice().sort((a, b) => {
      if (this.sortKey === 'overall') {
        return (
          ((this.overall(a).pct ?? -1) - (this.overall(b).pct ?? -1)) * dir
        );
      }
      return (a.learnerName ?? '').localeCompare(b.learnerName ?? '') * dir;
    });
  }

  get totalAwaiting() {
    return this.assignments.reduce((n, a) => n + this.awaiting(a), 0);
  }

  sortBy = (key: 'name' | 'overall') => {
    if (this.sortKey === key) this.sortDesc = !this.sortDesc;
    else {
      this.sortKey = key;
      this.sortDesc = key === 'overall';
    }
  };

  ariaSort = (key: string) =>
    this.sortKey === key
      ? this.sortDesc
        ? 'descending'
        : 'ascending'
      : 'none';

  <template>
    <div class='gb' ...attributes>
      {{#if this.rows.length}}
        <div class='scroll'>
          <table class='table'>
            <caption class='cap'>
              Gradebook ·
              {{this.rows.length}}
              learners ·
              {{this.assignments.length}}
              assignments
              {{#if this.totalAwaiting}}<span
                  class='await-n'
                >{{this.totalAwaiting}} awaiting grade</span>{{/if}}
            </caption>
            <thead>
              <tr>
                <th
                  scope='col'
                  class='th-name'
                  aria-sort={{this.ariaSort 'name'}}
                >
                  <button
                    type='button'
                    class='sort'
                    {{on 'click' (fn this.sortBy 'name')}}
                  >Learner
                    {{sortGlyph this.sortKey 'name' this.sortDesc}}</button>
                </th>
                {{#each this.assignments as |a|}}
                  <th scope='col' class='th-a' title={{a.cardTitle}}>
                    <span class='a-code'>{{if a.code a.code 'A'}}</span>
                    <span class='a-pts'>{{a.effectiveMaxPoints}} pts</span>
                    {{#if (this.awaiting a)}}<span
                        class='a-wait'
                      >{{this.awaiting a}} to grade</span>{{/if}}
                  </th>
                {{/each}}
                {{#each this.quizzes as |q|}}
                  <th scope='col' class='th-a quiz' title={{q.cardTitle}}>
                    <span class='a-code'>Quiz</span>
                    <span class='a-pts'>pass
                      {{if q.passMarkPct q.passMarkPct 0}}%</span>
                  </th>
                {{/each}}
                <th
                  scope='col'
                  class='th-ov'
                  aria-sort={{this.ariaSort 'overall'}}
                >
                  <button
                    type='button'
                    class='sort'
                    {{on 'click' (fn this.sortBy 'overall')}}
                  >Overall
                    {{sortGlyph this.sortKey 'overall' this.sortDesc}}</button>
                </th>
              </tr>
            </thead>
            <tbody>
              {{#each this.rows as |e|}}
                <tr>
                  <th scope='row' class='td-name'>
                    {{#if @onOpenEnrollment}}
                      <button
                        type='button'
                        class='name-btn'
                        {{on 'click' (fn @onOpenEnrollment e)}}
                      >{{e.learnerName}}</button>
                    {{else}}
                      {{e.learnerName}}
                    {{/if}}
                  </th>
                  {{#each this.assignments as |a|}}
                    {{#let (this.cell e a) as |c|}}
                      <td class='cell {{c.state}}'>
                        {{#if (eq c.state 'graded')}}
                          <button
                            type='button'
                            class='g'
                            title='{{c.total}}/{{c.max}} · {{c.pct}}%'
                            {{on
                              'click'
                              (fn (or @onOpenSubmission noop) c.submission)
                            }}
                          >
                            <b>{{if c.letter c.letter c.pct}}</b><span
                              class='g-pct'
                            >{{c.pct}}%</span>
                          </button>
                        {{else if (eq c.state 'submitted')}}
                          <button
                            type='button'
                            class='g grade-now'
                            {{on
                              'click'
                              (fn
                                (or @onGradeSubmission @onOpenSubmission noop)
                                c.submission
                              )
                            }}
                          >
                            Grade{{#if c.late}}
                              <span class='late'>late</span>{{/if}}
                          </button>
                        {{else if (eq c.state 'returned')}}
                          <button
                            type='button'
                            class='g ret'
                            {{on
                              'click'
                              (fn (or @onOpenSubmission noop) c.submission)
                            }}
                          >Returned</button>
                        {{else if (eq c.state 'overdue')}}
                          <span
                            class='dash over'
                            title='Overdue, nothing submitted'
                          >—</span>
                        {{else}}
                          <span class='dash'>—</span>
                        {{/if}}
                      </td>
                    {{/let}}
                  {{/each}}
                  {{#each this.quizzes as |q|}}
                    {{#let (this.quizCell e q) as |c|}}
                      <td class='cell q-{{c.state}}'>
                        {{#if (eq c.state 'missing')}}<span
                            class='dash'
                          >—</span>{{else}}<span
                            class='qv'
                            title='{{c.tries}} attempt(s)'
                          >{{c.pct}}%</span>{{/if}}
                      </td>
                    {{/let}}
                  {{/each}}
                  {{#let (this.overall e) as |o|}}
                    <td class='td-ov'>
                      {{#if o.letter}}<b>{{o.letter}}</b>
                        <span class='g-pct'>{{o.pct}}%</span>{{else}}<span
                          class='dash'
                        >—</span>{{/if}}
                    </td>
                  {{/let}}
                </tr>
              {{/each}}
            </tbody>
          </table>
        </div>
      {{else}}
        <p class='empty'>No active learners in this cohort yet. Enrol someone
          and the gradebook fills in.</p>
      {{/if}}
    </div>
    <style scoped>
      .gb {
        color: var(--foreground, var(--boxel-dark));
      }
      .scroll {
        overflow-x: auto;
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
        background: var(--card, var(--boxel-light));
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
        color: var(--muted-foreground, var(--boxel-450));
        display: flex;
        gap: var(--boxel-sp-sm);
        align-items: center;
      }
      .await-n {
        padding: 1px var(--boxel-sp-xs);
        border-radius: 999px;
        background: color-mix(
          in oklab,
          var(--boxel-warning) 16%,
          var(--card, var(--boxel-light))
        );
        color: color-mix(
          in oklab,
          var(--boxel-warning) 50%,
          var(--card-foreground, var(--boxel-dark))
        );
        font-weight: 700;
      }
      th,
      td {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-top: 1px solid var(--border, var(--boxel-200));
        text-align: center;
        white-space: nowrap;
      }
      thead th {
        border-top: 0;
        background: var(--muted, var(--boxel-100));
        font-weight: 600;
        vertical-align: bottom;
      }
      .th-name,
      .td-name {
        text-align: start;
        position: sticky;
        left: 0;
        background: var(--card, var(--boxel-light));
        z-index: 1;
      }
      thead .th-name {
        background: var(--muted, var(--boxel-100));
      }
      .td-name {
        font-weight: 600;
      }
      .sort,
      .name-btn {
        border: 0;
        background: none;
        padding: 0;
        color: inherit;
        font: inherit;
        font-weight: inherit;
        cursor: pointer;
      }
      .sort:focus-visible,
      .name-btn:focus-visible,
      .g:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: 2px;
      }
      .name-btn:hover {
        color: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 60%,
          var(--foreground, var(--boxel-dark))
        );
      }
      .th-a {
        display: table-cell;
      }
      .a-code {
        display: block;
        font-family: var(--font-mono, ui-monospace, monospace);
      }
      .a-pts,
      .a-wait {
        display: block;
        font-size: 11px;
        font-weight: 400;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .a-wait {
        color: color-mix(
          in oklab,
          var(--boxel-warning) 50%,
          var(--card-foreground, var(--boxel-dark))
        );
        font-weight: 600;
      }
      .g {
        display: inline-grid;
        justify-items: center;
        min-width: 3.25rem;
        padding: 2px var(--boxel-sp-xs);
        border: 1px solid transparent;
        border-radius: var(--boxel-border-radius-sm);
        background: transparent;
        color: inherit;
        font: inherit;
        cursor: pointer;
        line-height: 1.15;
      }
      .g b {
        font-size: var(--boxel-font-size);
      }
      .g-pct {
        font-size: 11px;
        color: var(--muted-foreground, var(--boxel-450));
        font-variant-numeric: tabular-nums;
      }
      .cell.graded .g {
        background: color-mix(
          in oklab,
          var(--boxel-success) 12%,
          var(--card, var(--boxel-light))
        );
      }
      .cell.graded .g:hover {
        border-color: var(--boxel-success);
      }
      .grade-now {
        background: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 14%,
          var(--card, var(--boxel-light))
        );
        color: color-mix(
          in oklab,
          var(--primary, var(--boxel-highlight)) 60%,
          var(--card-foreground, var(--boxel-dark))
        );
        font-weight: 700;
      }
      .grade-now:hover {
        border-color: var(--primary, var(--boxel-highlight));
      }
      .late {
        font-size: 11px;
        font-weight: 600;
        color: color-mix(
          in oklab,
          var(--boxel-warning) 55%,
          var(--card-foreground, var(--boxel-dark))
        );
      }
      .ret {
        background: color-mix(
          in oklab,
          var(--boxel-warning) 14%,
          var(--card, var(--boxel-light))
        );
        font-size: var(--boxel-font-size-xs);
      }
      .dash {
        color: var(--muted-foreground, var(--boxel-450));
      }
      .dash.over {
        color: var(--boxel-danger);
        font-weight: 800;
      }
      .q-passed .qv {
        color: color-mix(
          in oklab,
          var(--boxel-success) 50%,
          var(--card-foreground, var(--boxel-dark))
        );
        font-weight: 700;
      }
      .q-failed .qv {
        color: color-mix(
          in oklab,
          var(--boxel-danger) 55%,
          var(--card-foreground, var(--boxel-dark))
        );
        font-weight: 700;
      }
      .td-ov {
        font-variant-numeric: tabular-nums;
        border-left: 2px solid var(--border, var(--boxel-200));
      }
      .th-ov {
        border-left: 2px solid var(--border, var(--boxel-200));
      }
      .empty {
        margin: 0;
        padding: var(--boxel-sp);
        color: var(--muted-foreground, var(--boxel-450));
        font-style: italic;
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}

function eq(a: unknown, b: unknown) {
  return a === b;
}
function or(...v: any[]) {
  return v.find(Boolean);
}
function noop() {}
function sortGlyph(current: string, key: string, desc: boolean) {
  if (current !== key) return '';
  return desc ? '↓' : '↑';
}

export default Gradebook;
