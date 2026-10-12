import {
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import enumField from '@cardstack/base/enum';
import HelpCircleIcon from '@cardstack/boxel-icons/help-circle';

import {
  ChoiceOptionField,
  optionKey,
} from '@cardstack/catalog/fields/choice-option/choice-option-field';

export const QUESTION_KINDS = [
  { value: 'single', label: 'Single choice' },
  { value: 'multiple', label: 'Multiple choice' },
  { value: 'true_false', label: 'True / false' },
  { value: 'short_text', label: 'Short text' },
];

export const QuestionKindField = enumField(StringField, {
  displayName: 'Question Kind',
  options: QUESTION_KINDS,
});

/**
 * One scored question. Options are Choice Option fields so the same block
 * serves a survey; here their `isCorrect` flags drive `scoreAnswer()`.
 * Short-text questions match `acceptedAnswers` case-insensitively; anything
 * more lenient is a grader's job, not a quiz's.
 */
export class QuizQuestionField extends FieldDef {
  static displayName = 'Quiz Question';
  static icon = HelpCircleIcon;

  @field prompt = contains(MarkdownField);
  @field kind = contains(QuestionKindField);
  @field options = containsMany(ChoiceOptionField);
  @field acceptedAnswers = containsMany(StringField, {
    description: 'Short text only: any of these, case-insensitive, is correct.',
  });
  @field points = contains(NumberField);
  @field explanation = contains(MarkdownField, {
    description: 'Shown after the attempt is submitted.',
  });

  @field correctCount = contains(NumberField, {
    computeVia: function (this: QuizQuestionField) {
      return (this.options ?? []).filter((o: any) => o?.isCorrect).length;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='qq'>
        <div class='qq-head'>
          <span class='qq-kind'>{{kindLabel @model.kind}}</span>
          <span class='qq-pts'>{{pointsOf @model}} pts</span>
        </div>
        <div class='qq-prompt'><@fields.prompt /></div>
        {{#if @model.options.length}}
          <ul class='qq-opts'>
            {{#each @fields.options as |Opt|}}
              <li><Opt /></li>
            {{/each}}
          </ul>
        {{/if}}
      </div>
      <style scoped>
        .qq {
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .qq-head {
          display: flex;
          justify-content: space-between;
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .qq-kind {
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }
        .qq-pts {
          font-variant-numeric: tabular-nums;
        }
        .qq-prompt {
          color: var(--foreground);
        }
        .qq-opts {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-4xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='qq-atom'>{{kindLabel @model.kind}}
        ·
        {{pointsOf @model}}
        pts</span>
      <style scoped>
        .qq-atom {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
          white-space: nowrap;
        }
      </style>
    </template>
  };
}

export function kindLabel(kind?: string | null): string {
  return QUESTION_KINDS.find((k) => k.value === kind)?.label ?? 'Question';
}

export function pointsOf(q: Partial<QuizQuestionField> | null | undefined) {
  return q?.points ?? 1;
}

export interface Answer {
  questionIndex: number;
  selectedKeys?: string[];
  text?: string;
}

/**
 * Points earned by one answer. Single/true-false: the one selected key must
 * be the one correct option. Multiple: exact set match, all or nothing —
 * partial credit is a rubric's concept, not a quiz's.
 */
export function scoreAnswer(
  q: Partial<QuizQuestionField> | null | undefined,
  a: Answer | null | undefined,
): { earned: number; correct: boolean } {
  let pts = pointsOf(q);
  if (!q || !a) return { earned: 0, correct: false };
  if (q.kind === 'short_text') {
    let given = (a.text ?? '').trim().toLowerCase();
    let ok =
      !!given &&
      (q.acceptedAnswers ?? []).some(
        (x: string) => x?.trim().toLowerCase() === given,
      );
    return { earned: ok ? pts : 0, correct: ok };
  }
  let correctKeys = (q.options ?? [])
    .filter((o: any) => o?.isCorrect)
    .map((o: any) => optionKey(o))
    .sort();
  let chosen = [
    ...new Set((a.selectedKeys ?? []).map((k) => k.toLowerCase())),
  ].sort();
  let ok =
    correctKeys.length > 0 &&
    chosen.length === correctKeys.length &&
    chosen.every((k, i) => k === correctKeys[i]);
  return { earned: ok ? pts : 0, correct: ok };
}

export default QuizQuestionField;
