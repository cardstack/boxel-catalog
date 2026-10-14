import {
  CardDef,
  Component,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import PercentageField from '@cardstack/base/percentage';
import CircleCheckIcon from '@cardstack/boxel-icons/circle-check';

import { Enrollment } from './enrollment';
import { Quiz } from './quiz';
import { scoreAnswer } from './quiz-question-field';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { FittedCard } from '@cardstack/boxel-ui/components';

/** One recorded answer: which question, which option keys, or free text. */
export class QuizAnswerField extends FieldDef {
  static displayName = 'Quiz Answer';
  @field questionIndex = contains(NumberField);
  @field selectedKeys = containsMany(StringField);
  @field text = contains(StringField);

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='ans'>Q{{inc @model.questionIndex}}:
        {{if @model.text @model.text (join @model.selectedKeys)}}</span>
      <style scoped>
        .ans {
          font-size: var(--boxel-font-size-sm);
        }
      </style>
    </template>
  };
}

/**
 * One sitting of one quiz by one enrolment. Answers are stored; the score
 * is not — `scorePoints`, `scorePct` and `passed` are recomputed from the
 * quiz's current answer key, so fixing a mis-keyed option re-marks every
 * attempt without touching them.
 */
export class QuizAttempt extends CardDef {
  static displayName = 'Quiz Attempt';
  static icon = CircleCheckIcon;

  @field enrollment = linksTo(() => Enrollment);
  @field quiz = linksTo(() => Quiz);
  @field attemptNumber = contains(NumberField);
  @field startedAt = contains(DateTimeField);
  @field submittedAt = contains(DateTimeField);
  @field answers = containsMany(QuizAnswerField);

  @field scorePoints = contains(NumberField, {
    computeVia: function (this: QuizAttempt): number {
      return scoreOf(this).points;
    },
  });
  @field scorePct = contains(PercentageField, {
    computeVia: function (this: QuizAttempt): number {
      return scoreOf(this).pct;
    },
  });
  @field passed = contains(BooleanField, {
    computeVia: function (this: QuizAttempt): boolean {
      return scoreOf(this).passed;
    },
  });
  @field correctCount = contains(NumberField, {
    computeVia: function (this: QuizAttempt): number {
      return scoreOf(this).correct;
    },
  });
  @field learnerName = contains(StringField, {
    computeVia: function (this: QuizAttempt) {
      return this.enrollment?.learnerName ?? '';
    },
  });
  @field quizTitle = contains(StringField, {
    computeVia: function (this: QuizAttempt) {
      return this.quiz?.cardTitle ?? '';
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: QuizAttempt) {
      return `${this.enrollment?.learnerName ?? 'Learner'} · ${this.quiz?.cardTitle ?? 'Quiz'} · attempt ${this.attemptNumber ?? 1}`;
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    get results() {
      return perQuestion(this.args.model);
    }
    <template>
      <article class='attempt'>
        <header class='hero'>
          <div class='score-box {{if @model.passed "pass" "fail"}}'>
            <span class='score'>{{@model.scorePct}}%</span>
            <span class='verdict'>{{if
                @model.passed
                'Passed'
                'Not passed'
              }}</span>
          </div>
          <div class='hero-text'>
            <span class='eyebrow'>Attempt
              {{if @model.attemptNumber @model.attemptNumber 1}}
              ·
              {{#if @model.quiz}}<@fields.quiz @format='atom' />{{/if}}</span>
            <h1>{{if
                @model.learnerName
                @model.learnerName
                'Unlinked learner'
              }}</h1>
            <p class='meta'>
              <span>{{@model.correctCount}}
                of
                {{@model.quiz.questionCount}}
                correct ·
                {{@model.scorePoints}}
                /
                {{@model.quiz.totalPoints}}
                pts</span>
              {{#if @model.submittedAt}}<span>submitted
                  {{fmtDateTime @model.submittedAt}}</span>{{/if}}
              {{#if @model.quiz.passMarkPct}}<span>pass mark
                  {{@model.quiz.passMarkPct}}%</span>{{/if}}
            </p>
          </div>
        </header>
        <ol class='results'>
          {{#each this.results as |r|}}
            <li class='{{if r.correct "ok" "miss"}}'>
              <span class='mark'>{{if r.correct '✓' '✕'}}</span>
              <div class='r-body'>
                <span class='r-prompt'>{{r.prompt}}</span>
                <span class='r-given'>Answered: {{r.given}}</span>
                {{#unless r.correct}}<span class='r-correct'>Correct:
                    {{r.expected}}</span>{{/unless}}
              </div>
              <span class='r-pts'>{{r.earned}}/{{r.points}}</span>
            </li>
          {{else}}
            <p class='empty'>No answers recorded.</p>
          {{/each}}
        </ol>
      </article>
      <style scoped>
        .attempt {
          max-width: 48rem;
          margin: 0 auto;
          container-type: inline-size;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: grid;
          gap: var(--boxel-sp-lg);
          color: var(--foreground);
          background: var(--background);
        }
        .hero {
          display: grid;
          grid-template-columns: auto 1fr;
          gap: var(--boxel-sp);
          align-items: center;
        }
        .score-box {
          width: 5.5rem;
          height: 5rem;
          display: grid;
          place-content: center;
          justify-items: center;
          border-radius: var(--radius);
          background: var(--muted);
        }
        .score-box.pass {
          background: color-mix(in oklab, var(--success) 14%, var(--card));
        }
        .score-box.fail {
          background: color-mix(in oklab, var(--destructive) 14%, var(--card));
        }
        .score {
          font-size: var(--boxel-font-size-xl);
          font-weight: 800;
          line-height: 1;
          font-variant-numeric: tabular-nums;
        }
        .verdict {
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }
        .eyebrow {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        h1 {
          margin: var(--boxel-sp-4xs) 0 0;
          font-size: var(--boxel-font-size-xl);
          font-weight: 700;
          line-height: 1.15;
        }
        .meta {
          margin: var(--boxel-sp-xs) 0 0;
          display: flex;
          gap: var(--boxel-sp-sm);
          flex-wrap: wrap;
          font-size: var(--boxel-font-size-sm);
          color: var(--muted-foreground);
        }
        .results {
          list-style: none;
          margin: 0;
          padding: 0;
          display: grid;
          gap: var(--boxel-sp-xs);
        }
        .results li {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-sm);
          align-items: start;
          padding: var(--boxel-sp-sm) var(--boxel-sp);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          background: var(--card);
        }
        .mark {
          font-weight: 800;
        }
        .ok .mark {
          color: var(--success-ink);
        }
        .miss .mark {
          color: var(--destructive-ink);
        }
        .r-body {
          display: grid;
          gap: 0.125rem;
          font-size: var(--boxel-font-size-sm);
        }
        .r-prompt {
          font-weight: 600;
        }
        .r-given,
        .r-correct {
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-xs);
        }
        .r-pts {
          font-variant-numeric: tabular-nums;
          font-weight: 600;
        }
        .empty {
          color: var(--muted-foreground);
          font-style: italic;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='row'>
        <span class='n'>#{{if
            @model.attemptNumber
            @model.attemptNumber
            1
          }}</span>
        <div class='text'>
          <span class='title'>{{if
              @model.learnerName
              @model.learnerName
              'Learner'
            }}
            ·
            {{@model.quizTitle}}</span>
          <span class='sub'>{{@model.scorePoints}}
            pts ·
            {{fmtDateTime @model.submittedAt}}</span>
        </div>
        <StatePill
          @label='{{@model.scorePct}}%'
          @hue={{if @model.passed 'green' 'red'}}
          @dot={{true}}
        />
      </div>
      <style scoped>
        .row {
          display: grid;
          grid-template-columns: auto 1fr auto;
          gap: var(--boxel-sp-xs);
          align-items: center;
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        }
        .n {
          min-width: 2.25rem;
          height: 2.25rem;
          display: grid;
          place-items: center;
          border-radius: var(--boxel-border-radius-sm);
          background: var(--muted);
          font-size: var(--boxel-font-size-xs);
          font-weight: 700;
          font-family: var(--font-mono);
        }
        .text {
          display: grid;
          min-width: 0;
        }
        .title {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .sub {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='atom'>{{@model.quizTitle}}
        ·
        {{@model.scorePct}}%
        {{if @model.passed '✓' '✕'}}</span>
      <style scoped>
        .atom {
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <FittedCard @titleTag='h3'>
        <:eyebrow>{{@model.quizTitle}}
          · attempt
          {{if @model.attemptNumber @model.attemptNumber 1}}</:eyebrow>
        <:title>{{if @model.learnerName @model.learnerName 'Learner'}}</:title>
        <:subtitle>{{@model.scorePct}}% ·
          {{@model.scorePoints}}
          points</:subtitle>
        <:badgeRight><StatePill
            @label={{if @model.passed 'Passed' 'Not passed'}}
            @hue={{if @model.passed 'green' 'red'}}
          /></:badgeRight>
        <:footer>{{fmtDateTime @model.submittedAt}}</:footer>
      </FittedCard>
    </template>
  };
}

export function scoreOf(a: Partial<QuizAttempt> | null | undefined) {
  let questions = ((a?.quiz as any)?.questions ?? []) as any[];
  let answers = (a?.answers ?? []) as any[];
  let points = 0;
  let correct = 0;
  questions.forEach((q, i) => {
    let ans = answers.find((x) => x?.questionIndex === i);
    let r = scoreAnswer(
      q,
      ans
        ? {
            questionIndex: i,
            selectedKeys: ans.selectedKeys ?? [],
            text: ans.text,
          }
        : undefined,
    );
    points += r.earned;
    if (r.correct) correct += 1;
  });
  let total =
    (a?.quiz as any)?.totalPoints ??
    questions.reduce((n, q) => n + (q?.points ?? 1), 0);
  let pct = total ? Math.round((points / total) * 100) : 0;
  let passMark = (a?.quiz as any)?.passMarkPct ?? 0;
  return {
    points,
    pct,
    correct,
    passed: questions.length > 0 && pct >= passMark,
  };
}

function perQuestion(a: Partial<QuizAttempt> | null | undefined) {
  let questions = ((a?.quiz as any)?.questions ?? []) as any[];
  let answers = (a?.answers ?? []) as any[];
  return questions.map((q, i) => {
    let ans = answers.find((x) => x?.questionIndex === i);
    let r = scoreAnswer(
      q,
      ans
        ? {
            questionIndex: i,
            selectedKeys: ans.selectedKeys ?? [],
            text: ans.text,
          }
        : undefined,
    );
    let labelFor = (k: string) =>
      (q.options ?? []).find(
        (o: any) => (o.value || o.label || '').toLowerCase() === k,
      )?.label ?? k;
    return {
      prompt: (q.prompt ?? '').replace(/[#*_>`]/g, ''),
      given: ans
        ? ans.text || (ans.selectedKeys ?? []).map(labelFor).join(', ') || '—'
        : '—',
      expected:
        q.kind === 'short_text'
          ? (q.acceptedAnswers ?? []).join(' / ')
          : (q.options ?? [])
              .filter((o: any) => o.isCorrect)
              .map((o: any) => o.label)
              .join(', '),
      correct: r.correct,
      earned: r.earned,
      points: q.points ?? 1,
    };
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

function inc(n?: number | null) {
  return (n ?? 0) + 1;
}

function join(list?: string[] | null) {
  return (list ?? []).join(', ');
}

export default QuizAttempt;
