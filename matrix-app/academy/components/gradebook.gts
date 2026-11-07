import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { tracked } from '@glimmer/tracking';

import { letterFor } from '../grade-scale-field';
import { Button } from '@cardstack/pretui/components/button';
import { EmptyState } from '@cardstack/pretui/components/empty-state';

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
                  <Button
                    @tone='neutral'
                    @appearance='plain'
                    @size='xs'
                    {{on 'click' (fn this.sortBy 'name')}}
                  >Learner
                    {{sortGlyph this.sortKey 'name' this.sortDesc}}</Button>
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
                  <Button
                    @tone='neutral'
                    @appearance='plain'
                    @size='xs'
                    {{on 'click' (fn this.sortBy 'overall')}}
                  >Overall
                    {{sortGlyph this.sortKey 'overall' this.sortDesc}}</Button>
                </th>
              </tr>
            </thead>
            <tbody>
              {{#each this.rows as |e|}}
                <tr>
                  <th scope='row' class='td-name'>
                    {{#if @onOpenEnrollment}}
                      <Button
                        @appearance='link'
                        @size='s'
                        {{on 'click' (fn @onOpenEnrollment e)}}
                      >{{e.learnerName}}</Button>
                    {{else}}
                      {{e.learnerName}}
                    {{/if}}
                  </th>
                  {{#each this.assignments as |a|}}
                    {{#let (this.cell e a) as |c|}}
                      <td class='cell {{c.state}}'>
                        {{#if (eq c.state 'graded')}}
                          <Button
                            class='g'
                            @tone='success'
                            @appearance='filled'
                            @size='xs'
                            title='{{c.total}}/{{c.max}} · {{c.pct}}%'
                            {{on
                              'click'
                              (fn (or @onOpenSubmission noop) c.submission)
                            }}
                          >
                            <b>{{if c.letter c.letter c.pct}}</b><span
                              class='g-pct'
                            >{{c.pct}}%</span>
                          </Button>
                        {{else if (eq c.state 'submitted')}}
                          <Button
                            @tone='primary'
                            @appearance='accent'
                            @size='xs'
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
                          </Button>
                        {{else if (eq c.state 'returned')}}
                          <Button
                            class='g'
                            @tone='warning'
                            @appearance='filled'
                            @size='xs'
                            {{on
                              'click'
                              (fn (or @onOpenSubmission noop) c.submission)
                            }}
                          >Returned</Button>
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
        <EmptyState
          @size='s'
          @title='No active learners'
          @message='Enrol someone and the gradebook fills in.'
        />
      {{/if}}
    </div>
    <style scoped>
      .gb {
        color: var(--foreground);
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
        display: flex;
        gap: var(--boxel-sp-sm);
        align-items: center;
      }
      .await-n {
        padding: 0.0625rem var(--boxel-sp-xs);
        border-radius: 62.4375rem;
        background: color-mix(in oklab, var(--warning) 16%, var(--card));
        color: var(--warning-ink);
        font-weight: 700;
      }
      th,
      td {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
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
      }
      thead .th-name {
        background: var(--muted);
      }
      .td-name {
        font-weight: 600;
      }
      .th-a {
        display: table-cell;
      }
      .a-code {
        display: block;
        font-family: var(--font-mono);
      }
      .a-pts,
      .a-wait {
        display: block;
        font-size: var(--boxel-font-size-2xs);
        font-weight: 400;
        color: var(--muted-foreground);
      }
      .a-wait {
        color: var(--warning-ink);
        font-weight: 600;
      }
      .g {
        min-width: 3.25rem;
        gap: var(--boxel-sp-4xs);
      }
      .g b {
        font-size: var(--boxel-font-size);
      }
      .g-pct {
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
        font-variant-numeric: tabular-nums;
      }
      .late {
        font-size: var(--boxel-font-size-2xs);
        font-weight: 600;
        color: var(--warning-ink);
      }
      .dash {
        color: var(--muted-foreground);
      }
      .dash.over {
        color: var(--destructive-ink);
        font-weight: 800;
      }
      .q-passed .qv {
        color: var(--success-ink);
        font-weight: 700;
      }
      .q-failed .qv {
        color: var(--destructive-ink);
        font-weight: 700;
      }
      .td-ov {
        font-variant-numeric: tabular-nums;
        border-left: 2px solid var(--border);
      }
      .th-ov {
        border-left: 2px solid var(--border);
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
