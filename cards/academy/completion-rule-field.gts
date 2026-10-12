import {
  Component,
  FieldDef,
  StringField,
  contains,
  field,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import PercentageField from '@cardstack/base/percentage';
import CheckupListIcon from '@cardstack/boxel-icons/checkup-list';

/**
 * What a learner must have done for a cohort to count as completed.
 *
 * Four clauses, each optional; an unset clause is not required. The rule is
 * declared once on the Course and evaluated per Enrollment by
 * `evaluateCompletion()` (completion-evaluation-field.gts), which turns each
 * clause into a satisfied/unsatisfied line with the evidence that decided it.
 * Nothing about a learner is stored here — this is the contract, not the result.
 */
export class CompletionRuleField extends FieldDef {
  static displayName = 'Completion Rule';
  static icon = CheckupListIcon;

  @field minAttendancePct = contains(PercentageField, {
    description:
      'Minimum share of live lessons attended (present, late or excused).',
  });
  @field requireAllRequiredAssignments = contains(BooleanField, {
    description: 'Every assignment marked required must be graded.',
  });
  @field minQuizPassCount = contains(NumberField, {
    description: 'Number of quizzes that must be passed.',
  });
  @field minGradeLetter = contains(StringField, {
    description:
      'Lowest acceptable overall letter (per the course grade scale).',
  });
  @field customNote = contains(StringField, {
    description: 'Anything the rule cannot express; shown to instructors only.',
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <ul class='rule'>
        {{#each (describeCompletionRule @model) as |line|}}
          <li>{{line}}</li>
        {{else}}
          <li class='empty'>No completion requirements</li>
        {{/each}}
      </ul>
      <style scoped>
        .rule {
          margin: 0;
          padding-left: var(--boxel-sp);
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground, var(--boxel-dark));
        }
        .empty {
          list-style: none;
          margin-left: calc(-1 * var(--boxel-sp));
          color: var(--muted-foreground, var(--boxel-450));
          font-style: italic;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='rule-atom'>{{ruleClauseCount @model}}</span>
      <style scoped>
        .rule-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground, var(--boxel-450));
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export function describeCompletionRule(
  rule: Partial<CompletionRuleField> | null | undefined,
): string[] {
  if (!rule) return [];
  let out: string[] = [];
  if (rule.minAttendancePct != null) {
    out.push(`Attend at least ${rule.minAttendancePct}% of live lessons`);
  }
  if (rule.requireAllRequiredAssignments) {
    out.push('Have every required assignment graded');
  }
  if (rule.minQuizPassCount) {
    out.push(
      `Pass ${rule.minQuizPassCount} ${rule.minQuizPassCount === 1 ? 'quiz' : 'quizzes'}`,
    );
  }
  if (rule.minGradeLetter) {
    out.push(`Finish with an overall ${rule.minGradeLetter} or better`);
  }
  return out;
}

export function ruleClauseCount(
  rule: Partial<CompletionRuleField> | null | undefined,
): string {
  let n = describeCompletionRule(rule).length;
  return n
    ? `${n} ${n === 1 ? 'requirement' : 'requirements'}`
    : 'no requirements';
}

export default CompletionRuleField;
