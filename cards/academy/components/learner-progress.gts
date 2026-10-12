import GlimmerComponent from '@glimmer/component';
import { cached } from '@glimmer/tracking';
import type Owner from '@ember/owner';
import {
  identifyCard,
  realmURL,
  type getCards,
} from '@cardstack/runtime-common';

import {
  DonutChart,
  type DonutSegment,
} from '@cardstack/catalog/components/donut-chart';
import {
  evaluateCompletion,
  type CompletionClause,
} from '../completion-evaluation-field';
import { countsAsAttended } from '../attendance-status-field';
import { letterFor } from '../grade-scale-field';
import { Submission } from '../submission';
import { AttendanceRecord } from '../attendance-record';
import { QuizAttempt } from '../quiz-attempt';

interface Signature {
  Args: {
    enrollment: any;
    context?: any;
    /** Hide the donut and show only the completion clauses (for dense lists). */
    compact?: boolean;
  };
  Element: HTMLElement;
}

const HUES = {
  done: 'var(--boxel-success)',
  pending: 'var(--boxel-warning)',
  missing: 'var(--muted, var(--boxel-200))',
};

/**
 * One learner's standing in one cohort, computed live from the realm: how
 * much of the released course is done (the donut, via the shared Donut Chart
 * block), attendance, current letter, and the completion verdict clause by
 * clause. Nothing here is stored — the Enrollment stays a seat record and
 * this block is the reporting view, per the rollup rule for unbounded sets.
 *
 * Closes the loop with `evaluateCompletion()`: Issue Certificate runs the same
 * pure function over the same facts, so the panel and the command agree.
 */
export class LearnerProgress extends GlimmerComponent<Signature> {
  private submissions: ReturnType<getCards> | undefined;
  private attendance: ReturnType<getCards> | undefined;
  private attempts: ReturnType<getCards> | undefined;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    let ctx = this.args.context;
    if (!ctx?.getCards) return;
    // Captured once: thunks must not read tracked state (see cohort-workspace).
    let eid = this.enrollmentId;
    let realmList = this.realms;
    let realms = () => realmList;
    let lazy = (cls: any) => () => {
      let ref = identifyCard(cls);
      return ref && eid
        ? { filter: { on: ref, eq: { 'enrollment.id': eid } } }
        : undefined;
    };
    this.submissions = ctx.getCards(this, lazy(Submission), realms, {
      isLive: true,
    });
    this.attendance = ctx.getCards(this, lazy(AttendanceRecord), realms, {
      isLive: true,
    });
    this.attempts = ctx.getCards(this, lazy(QuizAttempt), realms, {
      isLive: true,
    });
  }

  private get enrollmentId(): string | undefined {
    return this.args.enrollment?.id;
  }

  // Cached so getCards sees the same realms array on every read.
  @cached
  private get realms(): string[] | undefined {
    let url = this.args.enrollment?.[realmURL];
    return url ? [url.href] : undefined;
  }

  get isLoading() {
    return !!(
      this.submissions?.isLoading ||
      this.attendance?.isLoading ||
      this.attempts?.isLoading
    );
  }

  get cohort() {
    return this.args.enrollment?.cohort;
  }
  get course() {
    return this.cohort?.course;
  }

  /** Modules the cohort has released; falls back to all modules when none recorded. */
  get releasedModules(): any[] {
    let mods = (this.course?.modules ?? []).filter(Boolean);
    let released = new Set(
      ((this.cohort?.releases ?? []) as any[])
        .map((r) => r?.module?.id)
        .filter(Boolean),
    );
    let out = mods.filter((m: any) => released.has(m.id));
    return out.length ? out : [];
  }

  get releasedAssignments(): any[] {
    return this.releasedModules.flatMap((m: any) =>
      (m.assignments ?? []).filter(Boolean),
    );
  }
  get releasedQuizzes(): any[] {
    return this.releasedModules.flatMap((m: any) =>
      (m.quizzes ?? []).filter(Boolean),
    );
  }
  get liveLessonsHeld(): number {
    let now = Date.now();
    return this.releasedModules
      .flatMap((m: any) => (m.lessons ?? []).filter(Boolean))
      .filter(
        (l: any) =>
          l.kind === 'live' &&
          (!l.liveSessionAt || new Date(l.liveSessionAt).getTime() <= now),
      ).length;
  }

  get subs(): any[] {
    return (this.submissions?.instances ?? []) as any[];
  }
  get marks(): any[] {
    return (this.attendance?.instances ?? []) as any[];
  }
  get quizAttempts(): any[] {
    return (this.attempts?.instances ?? []) as any[];
  }

  gradedFor = (assignmentId?: string) =>
    this.subs.find(
      (s) =>
        s.assignment?.id === assignmentId && s.submissionStatus === 'graded',
    );

  get gradedAssignmentIds(): string[] {
    return this.releasedAssignments
      .filter((a) => this.gradedFor(a.id))
      .map((a) => a.id);
  }
  get submittedAssignmentIds(): string[] {
    return this.releasedAssignments
      .filter(
        (a) =>
          !this.gradedFor(a.id) &&
          this.subs.some(
            (s) =>
              s.assignment?.id === a.id &&
              s.submissionStatus !== 'not_submitted',
          ),
      )
      .map((a) => a.id);
  }
  get passedQuizIds(): string[] {
    let ids = new Set<string>();
    for (let at of this.quizAttempts)
      if (at.passed && at.quiz?.id) ids.add(at.quiz.id);
    return [...ids];
  }

  get attendancePct(): number | undefined {
    let held = this.liveLessonsHeld;
    if (!held) return undefined;
    let attended = this.marks.filter((m) =>
      countsAsAttended(m.attendanceStatus),
    ).length;
    return Math.round((Math.min(attended, held) / held) * 100);
  }

  /** Points-weighted percentage across graded work, lettered by the course scale. */
  get overallPct(): number | undefined {
    let graded = this.subs.filter(
      (s) => s.submissionStatus === 'graded' && s.grade,
    );
    let earned = graded.reduce((n, s) => n + (s.grade.total ?? 0), 0);
    let max = graded.reduce((n, s) => n + (s.grade.maxPoints ?? 0), 0);
    return max ? Math.round((earned / max) * 100) : undefined;
  }
  get overallLetter(): string | undefined {
    return letterFor(this.overallPct, this.course?.gradeScale);
  }

  get segments(): DonutSegment[] {
    let a = this.releasedAssignments.length;
    let q = this.releasedQuizzes.length;
    let total = a + q;
    if (!total)
      return [{ label: 'Nothing released', value: 1, color: HUES.missing }];
    let done = this.gradedAssignmentIds.length + this.passedQuizIds.length;
    let pending = this.submittedAssignmentIds.length;
    let missing = Math.max(0, total - done - pending);
    return [
      { label: 'Done', value: done, color: HUES.done },
      { label: 'Awaiting grade', value: pending, color: HUES.pending },
      { label: 'Not started', value: missing, color: HUES.missing },
    ].filter((s) => s.value > 0);
  }
  get progressPct(): number {
    let total = this.releasedAssignments.length + this.releasedQuizzes.length;
    if (!total) return 0;
    return Math.round(
      ((this.gradedAssignmentIds.length + this.passedQuizIds.length) / total) *
        100,
    );
  }

  get clauses(): CompletionClause[] {
    return evaluateCompletion(this.course?.completionRule, {
      attendanceRecords: this.marks,
      liveLessonsHeld: this.liveLessonsHeld,
      requiredAssignments: this.releasedAssignments
        .filter((a) => a.required)
        .map((a) => ({ id: a.id, title: a.cardTitle })),
      gradedRequiredAssignmentIds: this.gradedAssignmentIds,
      quizzesPassed: this.passedQuizIds.length,
      overallLetter: this.overallLetter,
      scale: this.course?.gradeScale,
    });
  }
  get complete(): boolean {
    return this.clauses.length > 0 && this.clauses.every((c) => c.satisfied);
  }
  get metCount() {
    return this.clauses.filter((c) => c.satisfied).length;
  }
  get atRisk(): boolean {
    let minAtt = this.course?.completionRule?.minAttendancePct;
    let att = this.attendancePct;
    if (minAtt != null && att != null && att < minAtt) return true;
    let overdue = this.releasedAssignments.filter((a) => {
      let due = a.dueWindow?.dueAt;
      return (
        due &&
        new Date(due).getTime() < Date.now() &&
        !this.gradedFor(a.id) &&
        !this.submittedAssignmentIds.includes(a.id)
      );
    }).length;
    return overdue >= 2;
  }

  <template>
    <div class='lp {{if @compact "compact"}}' ...attributes>
      {{#if this.isLoading}}
        <p class='muted'>Loading progress…</p>
      {{else}}
        {{#unless @compact}}
          <div class='donut'>
            <DonutChart
              @segments={{this.segments}}
              @centerValue='{{this.progressPct}}%'
              @centerLabel='of released work'
            />
          </div>
        {{/unless}}
        <div class='facts'>
          <div class='stat'>
            <span class='n'>{{if
                (isNum this.attendancePct)
                (pct this.attendancePct)
                '—'
              }}</span>
            <span class='l'>attendance</span>
          </div>
          <div class='stat'>
            <span class='n'>{{if
                this.overallLetter
                this.overallLetter
                '—'
              }}</span>
            <span class='l'>{{if
                (isNum this.overallPct)
                (pct this.overallPct)
                'no grades yet'
              }}</span>
          </div>
          <div class='stat'>
            <span class='n'>{{this.gradedAssignmentIds.length}}<span
                class='of'
              >/{{this.releasedAssignments.length}}</span></span>
            <span class='l'>assignments graded</span>
          </div>
          <div class='stat'>
            <span class='n'>{{this.passedQuizIds.length}}<span
                class='of'
              >/{{this.releasedQuizzes.length}}</span></span>
            <span class='l'>quizzes passed</span>
          </div>
        </div>
        <div
          class='verdict {{if this.complete "ok"}} {{if this.atRisk "risk"}}'
        >
          <div class='verdict-head'>
            <span>{{if
                this.complete
                'Complete'
                (if this.atRisk 'At risk' 'In progress')
              }}</span>
            <span class='muted'>{{this.metCount}}
              of
              {{this.clauses.length}}
              requirements met</span>
          </div>
          <ul class='clauses'>
            {{#each this.clauses as |c|}}
              <li class='{{if c.satisfied "ok" "miss"}}'>
                <span class='mark'>{{if c.satisfied '✓' '✕'}}</span>
                <span class='rule'>{{c.rule}}</span>
                <span class='nums'>{{c.actual}}
                  <span class='muted'>/ {{c.required}}</span></span>
                <span class='ev'>{{c.evidence}}</span>
              </li>
            {{else}}
              <li class='muted'>This course has no completion rule.</li>
            {{/each}}
          </ul>
        </div>
      {{/if}}
    </div>
    <style scoped>
      .lp {
        display: grid;
        grid-template-columns: 12rem 1fr;
        grid-template-areas: 'donut facts' 'donut verdict';
        gap: var(--boxel-sp) var(--boxel-sp-lg);
        align-items: start;
        color: var(--foreground, var(--boxel-dark));
      }
      .lp.compact {
        grid-template-columns: 1fr;
        grid-template-areas: 'facts' 'verdict';
      }
      .donut {
        grid-area: donut;
        max-width: 12rem;
      }
      .facts {
        grid-area: facts;
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: var(--boxel-sp-sm);
      }
      .stat {
        display: grid;
        padding: var(--boxel-sp-sm);
        border: 1px solid var(--border, var(--boxel-200));
        border-radius: var(--radius, var(--boxel-border-radius));
        background: var(--card, var(--boxel-light));
      }
      .n {
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1.1;
      }
      .of {
        font-size: var(--boxel-font-size-sm);
        font-weight: 400;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .l {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .verdict {
        grid-area: verdict;
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        border: 1px solid var(--border, var(--boxel-200));
        border-left: 4px solid var(--boxel-warning);
        border-radius: var(--radius, var(--boxel-border-radius));
        background: var(--card, var(--boxel-light));
      }
      .verdict.ok {
        border-left-color: var(--boxel-success);
      }
      .verdict.risk {
        border-left-color: var(--boxel-danger);
      }
      .verdict-head {
        display: flex;
        justify-content: space-between;
        font-weight: 700;
        margin-bottom: var(--boxel-sp-xs);
      }
      .clauses {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
        gap: var(--boxel-sp-4xs);
      }
      .clauses li {
        display: grid;
        grid-template-columns: auto 1fr auto;
        gap: 0 var(--boxel-sp-xs);
        align-items: baseline;
        font-size: var(--boxel-font-size-sm);
      }
      .mark {
        font-weight: 800;
      }
      .ok .mark {
        color: var(--boxel-success);
      }
      .miss .mark {
        color: var(--boxel-danger);
      }
      .nums {
        font-variant-numeric: tabular-nums;
        font-weight: 600;
      }
      .ev {
        grid-column: 2 / -1;
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .muted {
        color: var(--muted-foreground, var(--boxel-450));
        font-weight: 400;
        font-size: var(--boxel-font-size-sm);
      }
      @container (width <= 640px) {
        .lp {
          grid-template-columns: 1fr;
          grid-template-areas: 'donut' 'facts' 'verdict';
        }
        .donut {
          margin: 0 auto;
        }
        .facts {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
      }
    </style>
  </template>
}

function isNum(n: unknown): n is number {
  return typeof n === 'number' && !Number.isNaN(n);
}

function pct(n: number) {
  return `${n}%`;
}

export default LearnerProgress;
