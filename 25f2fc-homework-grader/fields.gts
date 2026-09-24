import {
  Component,
  contains,
  containsMany,
  field,
  FieldDef,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import StringField from '@cardstack/base/string';

// True when a returned grade is structurally consistent with the assignment:
// a letter grade plus per-question points (and feedbacks, when present)
// matching the question count. Exported so live tests can hit it directly.
export function isGradeConsistent(
  grade:
    | {
        overallGrade?: string | null;
        questionPoints?: (number | null)[];
        questionFeedbacks?: (string | null)[];
      }
    | null
    | undefined,
  questionCount: number,
): boolean {
  if (!grade?.overallGrade) return false;
  if ((grade.questionPoints?.length ?? 0) !== questionCount) return false;
  let feedbacks = grade.questionFeedbacks;
  if (feedbacks && feedbacks.length > 0 && feedbacks.length !== questionCount) {
    return false;
  }
  return true;
}

// letter grades the grading skill is allowed to award (see the skill's
// grading scale) — an enum so the edit UI is a picker, not free text
export const LetterGradeField = enumField(StringField, {
  options: ['A', 'B', 'C', 'D', 'E', 'F'].map((g) => ({ value: g, label: g })),
});

export class GradeField extends FieldDef {
  @field overallGrade = contains(LetterGradeField);
  @field overallFeedback = contains(MarkdownField);
  @field questionPoints = containsMany(NumberField);
  // one feedback entry per question, same order/length as questionPoints
  @field questionFeedbacks = containsMany(MarkdownField);

  @field overallPoints = contains(NumberField, {
    computeVia: function (this: GradeField) {
      return this.questionPoints.reduce((acc, num) => acc + (num || 0), 0);
    },
  });

  static edit = class Edit extends Component<typeof GradeField> {
    <template>
      <div class='g-edit'>
        <label class='g-edit-field g-edit-grade'>
          <span class='g-edit-label'>Overall grade</span>
          <@fields.overallGrade @format='edit' />
        </label>
        <label class='g-edit-field'>
          <span class='g-edit-label'>Overall feedback</span>
          <@fields.overallFeedback @format='edit' />
        </label>
        <label class='g-edit-field'>
          <span class='g-edit-label'>Points per question</span>
          <@fields.questionPoints @format='edit' />
        </label>
        <label class='g-edit-field'>
          <span class='g-edit-label'>Feedback per question</span>
          <@fields.questionFeedbacks @format='edit' />
        </label>
      </div>
      <style scoped>
        .g-edit {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          color: var(--foreground);
        }
        .g-edit-grade {
          max-width: 8.75rem;
        }
        .g-edit-field {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          min-width: 0;
        }
        .g-edit-label {
          font-size: 0.6875rem;
          font-weight: 700;
          letter-spacing: 0.07em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .g-edit-field:focus-within .g-edit-label {
          color: var(--primary-ink);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof GradeField> {
    get gradeClass() {
      return `grade-${(this.args.model?.overallGrade ?? 'unknown').toUpperCase()}`;
    }

    <template>
      <div class='grade-layout'>
        {{#if @model.overallGrade}}
          <div class='grade-circle {{this.gradeClass}}'>
            {{@model.overallGrade}}
          </div>
        {{/if}}

        <div class='details-column'>
          {{#if @model.overallFeedback}}
            <div class='feedback-row'>
              <span class='detail-label'>Feedback</span>
              <div class='feedback-content'>
                <@fields.overallFeedback />
              </div>
            </div>
          {{/if}}
        </div>
      </div>

      <style scoped>
        .grade-layout {
          display: flex;
          flex-direction: column;
          gap: 1.25rem;
          font-family:
            -apple-system, BlinkMacSystemFont, 'Inter', 'Segoe UI', sans-serif;
        }

        .grade-circle {
          flex-shrink: 0;
          width: 3rem;
          height: 3rem;
          border-radius: 50%;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 1.25rem;
          font-weight: 800;
          color: var(--primary-foreground);
          background-color: var(--primary);
        }

        .grade-circle.grade-A {
          background-color: var(--success);
          color: var(--success-foreground);
        }

        .grade-circle.grade-B {
          background-color: var(--primary);
          color: var(--primary-foreground);
        }

        .grade-circle.grade-C {
          background-color: var(--warning);
          color: var(--warning-foreground);
        }

        .grade-circle.grade-D,
        .grade-circle.grade-E,
        .grade-circle.grade-F {
          background-color: var(--destructive);
          color: var(--destructive-foreground);
        }

        .details-column {
          display: flex;
          flex-direction: column;
          gap: 1rem;
          flex: 1;
        }

        .feedback-row {
          display: flex;
          flex-direction: column;
          gap: 0.625rem;
        }

        .detail-label {
          font-size: 0.6875rem;
          font-weight: 600;
          color: var(--primary-ink);
          text-transform: uppercase;
          letter-spacing: 0.07em;
          white-space: nowrap;
        }

        .feedback-content {
          flex: 1;
          font-size: 0.875rem;
          line-height: 1.75;
          color: var(--foreground);
        }

        .feedback-content :deep(.markdown-content) {
          display: flex;
          flex-direction: column;
          gap: 0.875rem;
        }

        .feedback-content :deep(.markdown-content h1),
        .feedback-content :deep(.markdown-content h2),
        .feedback-content :deep(.markdown-content h3) {
          font-size: 0.9375rem;
          font-weight: 700;
          color: var(--foreground);
          margin: 0;
          padding-bottom: 0.5rem;
          border-bottom: 1px solid var(--border);
        }

        .feedback-content :deep(.markdown-content h4) {
          font-size: 0.8125rem;
          font-weight: 600;
          color: var(--foreground);
          margin: 0;
        }

        .feedback-content :deep(.markdown-content p) {
          margin: 0;
          font-size: 0.875rem;
          line-height: 1.75;
          color: var(--foreground);
        }

        .feedback-content :deep(.markdown-content strong) {
          color: var(--foreground);
          font-weight: 700;
        }

        .feedback-content :deep(.markdown-content em) {
          color: var(--muted-foreground);
        }

        .feedback-content :deep(.markdown-content ul),
        .feedback-content :deep(.markdown-content ol) {
          padding-left: 1.25rem;
          margin: 0;
          display: flex;
          flex-direction: column;
          gap: 0.3125rem;
        }

        .feedback-content :deep(.markdown-content li) {
          font-size: 0.875rem;
          line-height: 1.65;
          color: var(--foreground);
        }

        .feedback-content :deep(.markdown-content blockquote) {
          border-left: 3px solid var(--primary);
          padding: 0.5rem 0.875rem;
          background-color: var(--card);
          border-radius: 0 0.375rem 0.375rem 0;
          margin: 0;
          color: var(--primary-ink);
          font-style: italic;
        }
      </style>
    </template>
  };
}

export class QuestionField extends FieldDef {
  static displayName = 'Question';

  @field cardTitle = contains(StringField);
  @field questionText = contains(MarkdownField);
  @field answer = contains(MarkdownField);
  @field maxPoints = contains(NumberField);

  @field isAnswered = contains(BooleanField, {
    computeVia: function (this: QuestionField) {
      return this.answer?.length > 0;
    },
  });

  static edit = class Edit extends Component<typeof QuestionField> {
    <template>
      <div class='q-edit'>
        <label class='q-edit-field'>
          <span class='q-edit-label'>Question</span>
          <@fields.questionText @format='edit' />
        </label>
        <label class='q-edit-field q-edit-points'>
          <span class='q-edit-label'>Max points</span>
          <@fields.maxPoints @format='edit' />
        </label>
      </div>
      <style scoped>
        .q-edit {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
          color: var(--foreground);
        }
        .q-edit-points {
          max-width: 7.5rem;
        }
        .q-edit-field {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          min-width: 0;
        }
        .q-edit-label {
          font-size: 0.6875rem;
          font-weight: 700;
          letter-spacing: 0.07em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .q-edit-field :deep(.boxel-input),
        .q-edit-field :deep(input),
        .q-edit-field :deep(textarea) {
          font-size: 0.8125rem;
        }
        .q-edit-field:focus-within .q-edit-label {
          color: var(--primary-ink);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof QuestionField> {
    <template>
      <div class='embedded-question'>
        <div class='question-preview'>
          <@fields.questionText />
        </div>
        {{#if @model.answer}}
          <div class='answer-preview'>
            <span class='answer-label'>Answer:</span>
            <span class='answer-text'>{{@model.answer}}</span>
          </div>
        {{/if}}
      </div>
    </template>
  };

  static fitted = class Fitted extends Component<typeof QuestionField> {
    <template>
      <div class='fitted-question' data-answered='{{@model.isAnswered}}'>
        <div class='question-block'>
          <@fields.questionText />
        </div>
        <div class='answer-section'>
          <span class='answer-label'>Your answer</span>
          <@fields.answer @format='edit' />
        </div>
      </div>

      <style scoped>
        .fitted-question {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-sm);
          height: 100%;
        }

        .question-block {
          background-color: var(--boxel-100);
          border-radius: var(--boxel-border-radius-sm);
          border-left: 3px solid var(--boxel-purple);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
          line-height: 1.5;
        }

        .fitted-question[data-answered='true'] .question-block {
          border-left-color: var(--boxel-dark-green);
        }

        .answer-label {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--boxel-500);
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .answer-section {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          flex: 1;
        }
      </style>
    </template>
  };
}
