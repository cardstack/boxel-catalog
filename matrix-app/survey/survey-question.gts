import {
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import BooleanField from '@cardstack/base/boolean';
import enumField from '@cardstack/base/enum';

export const QuestionKindField = enumField(StringField, {
  displayName: 'Question Kind',
  options: [
    { value: 'short-text', label: 'Short text' },
    { value: 'long-text', label: 'Long text' },
    { value: 'single-choice', label: 'Single choice' },
    { value: 'multi-choice', label: 'Multiple choice' },
    { value: 'rating', label: 'Rating (1–5)' },
    { value: 'yes-no', label: 'Yes / No' },
  ],
});

const KIND_LABELS: Record<string, string> = {
  'short-text': 'Short text',
  'long-text': 'Long text',
  'single-choice': 'Single choice',
  'multi-choice': 'Multi-choice',
  rating: 'Rating',
  'yes-no': 'Yes / no',
};

/** "Multi-choice · 5 options" / "Rating · 1 = poor, 5 = excellent" */
export function questionSummary(q?: SurveyQuestion | null): string {
  if (!q) return '';
  let kind = KIND_LABELS[q.kind ?? ''] ?? 'Question';
  let n = q.options?.length ?? 0;
  let extra = n ? `${n} options` : q.helpText;
  return extra ? `${kind} · ${extra}` : kind;
}

function plural(n: number, word: string) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

/** Counts a survey's card formats show: totals and how many of each kind. */
export function questionFacts(questions?: SurveyQuestion[] | null) {
  let qs = (questions ?? []).filter(Boolean);
  let of = (...kinds: string[]) =>
    qs.filter((q) => kinds.includes(q.kind ?? '')).length;
  let required = qs.filter((q) => q.required).length;
  return {
    total: qs.length,
    required,
    totalLabel: plural(qs.length, 'question'),
    summary: `${plural(qs.length, 'question')} · ${required} required`,
    rating: plural(of('rating'), 'question'),
    text: plural(of('short-text', 'long-text'), 'question'),
    choice: plural(of('single-choice', 'multi-choice'), 'question'),
    yesNo: plural(of('yes-no'), 'question'),
  };
}

export class SurveyQuestion extends FieldDef {
  static displayName = 'Survey Question';

  @field prompt = contains(StringField);
  @field helpText = contains(StringField);
  @field kind = contains(QuestionKindField);
  @field options = containsMany(StringField);
  @field required = contains(BooleanField);

  @field title = contains(StringField, {
    computeVia: function (this: SurveyQuestion) {
      return this.prompt ?? 'Untitled question';
    },
  });

  static embedded = class Embedded extends Component<typeof SurveyQuestion> {
    get summary() {
      return questionSummary(this.args.model as SurveyQuestion);
    }
    <template>
      <div class='sq-row'>
        <span class='sq-prompt'>{{if
            @model.prompt
            @model.prompt
            'Untitled question'
          }}</span>
        <span class='sq-meta'>{{this.summary}}
          <span class='dot-text {{if @model.required "req"}}'><span
              class='dot'
            ></span>{{if @model.required 'required' 'optional'}}</span></span>
      </div>
      <style scoped>
        .sq-row {
          display: grid;
          grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
          gap: var(--boxel-sp-sm);
          align-items: center;
          font-size: var(--boxel-font-size-xs);
          color: var(--card-foreground);
        }
        .sq-prompt {
          font-weight: 600;
        }
        .sq-meta {
          display: flex;
          flex-wrap: wrap;
          align-items: center;
          gap: var(--boxel-sp-xs);
          color: var(--muted-foreground);
        }
        .dot-text {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-5xs);
          font-weight: 600;
          color: var(--card-foreground);
        }
        .dot {
          width: 0.375rem;
          height: 0.375rem;
          border-radius: 50%;
          background-color: var(--muted-foreground);
        }
        .req .dot {
          background-color: var(--warning);
        }
      </style>
    </template>
  };
}
