import {
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import ClipboardCheckIcon from '@cardstack/boxel-icons/clipboard-check';

import type { CompletionRuleField } from './completion-rule-field';
import { letterAtLeast, type GradeScaleField } from './grade-scale-field';
import { countsAsAttended } from './attendance-status-field';

/** One clause of the rule, judged: what was required, what happened, and the verdict. */
export class CompletionClauseField extends FieldDef {
  static displayName = 'Completion Clause';
  @field rule = contains(StringField);
  @field required = contains(StringField);
  @field actual = contains(StringField);
  @field satisfied = contains(BooleanField);
  @field evidence = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='clause {{if @model.satisfied "ok" "miss"}}'>
        <span class='mark' aria-hidden='true'>{{if
            @model.satisfied
            '✓'
            '✕'
          }}</span>
        <span class='rule'>{{@model.rule}}</span>
        <span class='nums'>{{@model.actual}}
          <span class='req'>/ {{@model.required}}</span></span>
      </div>
      <style scoped>
        .clause {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: baseline;
          font-size: var(--boxel-font-size-sm);
        }
        .mark {
          font-weight: 700;
          width: 1.1em;
          text-align: center;
        }
        .ok .mark {
          color: var(--success-ink);
        }
        .miss .mark {
          color: var(--destructive-ink);
        }
        .rule {
          color: var(--foreground);
        }
        .nums {
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .req {
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}

/**
 * The verdict of a Completion Rule for one enrollment — never stored, always
 * recomputed by `evaluateCompletion()`. Each clause carries its own evidence
 * so an instructor can answer "why isn't Priya complete?" without opening
 * five cards, and Issue Certificate can print the refusal reason verbatim.
 */
export class CompletionEvaluationField extends FieldDef {
  static displayName = 'Completion Evaluation';
  static icon = ClipboardCheckIcon;

  @field clauses = containsMany(CompletionClauseField);
  @field satisfied = contains(BooleanField, {
    computeVia: function (this: CompletionEvaluationField) {
      let c = this.clauses ?? [];
      return c.length > 0 && c.every((x: any) => x?.satisfied);
    },
  });
  @field summary = contains(StringField, {
    computeVia: function (this: CompletionEvaluationField) {
      let c = this.clauses ?? [];
      if (!c.length) return 'No requirements';
      let met = c.filter((x: any) => x?.satisfied).length;
      return `${met} of ${c.length} met`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='eval'>
        <div class='eval-head {{if @model.satisfied "ok"}}'>
          {{if @model.satisfied 'Complete' 'Not yet complete'}}
          <span class='eval-sum'>{{@model.summary}}</span>
        </div>
        <div class='eval-clauses'>
          {{#each @fields.clauses as |Clause|}}
            <Clause />
          {{else}}
            <span class='eval-empty'>This course has no completion requirements.</span>
          {{/each}}
        </div>
      </div>
      <style scoped>
        .eval {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .eval-head {
          display: flex;
          justify-content: space-between;
          font-weight: 600;
          color: var(--foreground);
        }
        .eval-head.ok {
          color: var(--success-ink);
        }
        .eval-sum {
          font-weight: 400;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .eval-clauses {
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
        .eval-empty {
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span
        class='eval-atom {{if @model.satisfied "ok"}}'
      >{{@model.summary}}</span>
      <style scoped>
        .eval-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
        .eval-atom.ok {
          color: var(--success-ink);
        }
      </style>
    </template>
  };
}

/** Everything the rule needs to know about one learner, already resolved by the caller. */
export interface CompletionFacts {
  attendanceRecords: { attendanceStatus?: string | null }[];
  liveLessonsHeld: number;
  requiredAssignments: { id?: string; title?: string }[];
  gradedRequiredAssignmentIds: string[];
  quizzesPassed: number;
  overallLetter?: string;
  scale?: Partial<GradeScaleField> | null;
}

export interface CompletionClause {
  rule: string;
  required: string;
  actual: string;
  satisfied: boolean;
  evidence: string;
}

/**
 * Pure. Turns a rule plus the facts into judged clauses. Nothing here reads
 * a card or a clock — the caller (Enrollment's computed field, or Issue
 * Certificate) gathers the facts, so the UI and the command cannot disagree.
 */
export function evaluateCompletion(
  rule: Partial<CompletionRuleField> | null | undefined,
  facts: CompletionFacts,
): CompletionClause[] {
  let out: CompletionClause[] = [];
  if (!rule) return out;

  if (rule.minAttendancePct != null) {
    let attended = facts.attendanceRecords.filter((r) =>
      countsAsAttended(r.attendanceStatus),
    ).length;
    let pct =
      facts.liveLessonsHeld > 0
        ? Math.round((attended / facts.liveLessonsHeld) * 100)
        : 0;
    out.push({
      rule: 'Attendance',
      required: `${rule.minAttendancePct}%`,
      actual: `${pct}%`,
      satisfied: pct >= rule.minAttendancePct,
      evidence: `${attended} of ${facts.liveLessonsHeld} live lessons attended`,
    });
  }

  if (rule.requireAllRequiredAssignments) {
    let total = facts.requiredAssignments.length;
    let done = facts.requiredAssignments.filter(
      (a) => a.id && facts.gradedRequiredAssignmentIds.includes(a.id),
    );
    let missing = facts.requiredAssignments
      .filter((a) => !a.id || !facts.gradedRequiredAssignmentIds.includes(a.id))
      .map((a) => a.title ?? 'untitled');
    out.push({
      rule: 'Required assignments graded',
      required: `${total}`,
      actual: `${done.length}`,
      satisfied: done.length >= total,
      evidence: missing.length
        ? `Missing: ${missing.join(', ')}`
        : 'All graded',
    });
  }

  if (rule.minQuizPassCount) {
    out.push({
      rule: 'Quizzes passed',
      required: `${rule.minQuizPassCount}`,
      actual: `${facts.quizzesPassed}`,
      satisfied: facts.quizzesPassed >= rule.minQuizPassCount,
      evidence: `${facts.quizzesPassed} passing attempt${facts.quizzesPassed === 1 ? '' : 's'}`,
    });
  }

  if (rule.minGradeLetter) {
    let ok = letterAtLeast(
      facts.overallLetter,
      rule.minGradeLetter,
      facts.scale,
    );
    out.push({
      rule: 'Overall grade',
      required: `${rule.minGradeLetter} or better`,
      actual: facts.overallLetter ?? '—',
      satisfied: ok,
      evidence: facts.overallLetter
        ? `Current letter ${facts.overallLetter}`
        : 'No graded work yet',
    });
  }

  return out;
}

export function allSatisfied(clauses: CompletionClause[]): boolean {
  return clauses.length > 0 && clauses.every((c) => c.satisfied);
}

export default CompletionEvaluationField;
