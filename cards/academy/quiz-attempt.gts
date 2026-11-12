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
import { concat } from '@ember/helper';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import {
  AtomChip,
  Dot,
  Embed,
  Kv,
  Mark,
  Section,
  Sheet,
  Stat,
} from './components/record-sheet';
import { IsoFrame } from '../shared/compact-sheet';

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
      <IsoFrame>
        <Sheet @mark='Qz' @title={{headline @model}} @meta={{metaLine @model}}>
          <:status>
            <Dot @hue={{if @model.passed 'green' 'red'}}>{{if
                @model.passed
                'passed'
                'not passed'
              }}</Dot>
            <Dot @hue='blue'>{{@model.scorePct}}%</Dot>
          </:status>
          <:stats>
            <Stat
              @label='Score'
              @value={{concat @model.scorePct '%'}}
              @sub={{concat
                @model.scorePoints
                ' of '
                (dash @model.quiz.totalPoints)
                ' points'
              }}
            />
            <Stat
              @label='Correct'
              @value={{concat
                @model.correctCount
                ' / '
                (dash @model.quiz.questionCount)
              }}
              @sub='questions'
            />
            <Stat
              @label='Time'
              @value={{elapsed @model}}
              @sub='start to submit'
            />
          </:stats>
          <:main>
            <Section @title='Answers'>
              {{#each this.results as |r i|}}
                <div class='ans'>
                  <span class='q'>
                    <span class='prompt'>{{inc i}}
                      ·
                      {{r.prompt}}</span>
                    <span class='given'>{{r.given}}{{#unless r.correct}}
                        · expected
                        {{r.expected}}{{/unless}}</span>
                  </span>
                  <Dot @hue={{if r.correct 'green' 'red'}}>{{r.earned}}
                    /
                    {{r.points}}</Dot>
                </div>
              {{else}}
                <p class='empty'>No questions on the linked quiz.</p>
              {{/each}}
            </Section>
          </:main>
          <:side>
            <Section @title='Linked'>
              <Kv @label='Enrollment'>{{#if
                  @model.enrollment
                }}<@fields.enrollment
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</Kv>
              <Kv @label='Quiz'>{{#if @model.quiz}}<@fields.quiz
                    @format='atom'
                    @displayContainer={{false}}
                  />{{else}}—{{/if}}</Kv>
            </Section>
            <Section @title='Details'>
              <Kv @label='Quiz'>{{dash @model.quizTitle}}</Kv>
              <Kv @label='Attempt' @mono={{true}}>{{attemptOf @model}}</Kv>
              <Kv @label='Score' @mono={{true}}>{{@model.scorePoints}}
                /
                {{dash @model.quiz.totalPoints}}</Kv>
              <Kv @label='Correct' @mono={{true}}>{{@model.correctCount}}
                of
                {{dash @model.quiz.questionCount}}</Kv>
              <Kv @label='Started' @mono={{true}}>{{fmtDateTime
                  @model.startedAt
                }}</Kv>
              <Kv @label='Submitted' @mono={{true}}>{{fmtDateTime
                  @model.submittedAt
                }}</Kv>
              <Kv @label='Pass mark' @mono={{true}}>{{passMark @model}}</Kv>
            </Section>
          </:side>
        </Sheet>
      </IsoFrame>
      <style scoped>
        .ans {
          display: flex;
          align-items: center;
          justify-content: space-between;
          gap: var(--boxel-sp-sm);
          min-block-size: 1.75rem;
          padding: var(--boxel-sp-5xs) var(--boxel-sp-sm);
          border-block-start: 1px solid var(--border);
        }
        .q {
          display: flex;
          flex-direction: column;
          min-inline-size: 0;
        }
        .prompt {
          font-weight: 600;
        }
        .given {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
        }
        .empty {
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          border-block-start: 1px solid var(--border);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <Embed @mark='Qz' @title={{headline @model}} @meta={{metaLine @model}}>
        <:status>
          <Dot @hue={{if @model.passed 'green' 'red'}}>{{if
              @model.passed
              'passed'
              'not passed'
            }}</Dot>
          <Dot @hue='blue'>{{@model.scorePct}}%</Dot>
        </:status>
        <:fact><strong>{{@model.scorePoints}}
            /
            {{dash @model.quiz.totalPoints}}</strong>
          points · pass mark
          {{passMark @model}}</:fact>
        <:default>
          <Kv @label='Quiz'>{{dash @model.quizTitle}}</Kv>
          <Kv @label='Attempt' @mono={{true}}>{{attemptOf @model}}</Kv>
          <Kv @label='Correct' @mono={{true}}>{{@model.correctCount}}
            of
            {{dash @model.quiz.questionCount}}</Kv>
          <Kv @label='Started' @mono={{true}}>{{fmtDateTime
              @model.startedAt
            }}</Kv>
          <Kv @label='Submitted' @mono={{true}}>{{fmtDateTime
              @model.submittedAt
            }}</Kv>
          <Kv @label='Enrollment'>{{#if @model.enrollment}}<@fields.enrollment
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
          <Kv @label='Quiz'>{{#if @model.quiz}}<@fields.quiz
                @format='atom'
                @displayContainer={{false}}
              />{{else}}—{{/if}}</Kv>
        </:default>
      </Embed>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <AtomChip @mark='Qz' @title={{headline @model}}><Dot
          @hue={{if @model.passed 'green' 'red'}}
        >{{@model.scorePct}}%</Dot></AtomChip>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <RichFittedCard>
        <:avatar><Mark @text='Qz' /></:avatar>
        <:title>{{headline @model}}</:title>
        <:subtitle>{{metaLine @model}}</:subtitle>
        <:status><Dot @hue={{if @model.passed 'green' 'red'}}>{{if
              @model.passed
              'passed'
              'not passed'
            }}</Dot></:status>
        <:fact>{{@model.scorePoints}}
          /
          {{dash @model.quiz.totalPoints}}
          points · pass mark
          {{passMark @model}}</:fact>
        <:metric><Metric
            @value='{{@model.scorePct}}%'
            @label='Score'
          /></:metric>
        <:details>
          <Detail
            @label='Correct'
            @value='{{@model.correctCount}} / {{dash
              @model.quiz.questionCount
            }}'
          />
          <Detail @label='Time' @value={{elapsed @model}} />
          <Detail @label='Attempt' @value={{attemptOf @model}} />
        </:details>
        <:relations>{{#if @model.enrollment}}<@fields.enrollment
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}{{#if @model.quiz}}<@fields.quiz
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </RichFittedCard>
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

function headline(m?: Partial<QuizAttempt> | null): string {
  return (
    [m?.learnerName, m?.quizTitle].filter(Boolean).join(' · ') || 'Quiz attempt'
  );
}
function metaLine(m?: Partial<QuizAttempt> | null): string {
  let parts = [`Attempt ${m?.attemptNumber ?? 1}`];
  if (m?.submittedAt) {
    parts.push(
      new Date(m.submittedAt).toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
      }),
    );
  }
  let t = elapsed(m);
  if (t !== '—') parts.push(t);
  return parts.join(' · ');
}
function elapsed(m?: Partial<QuizAttempt> | null): string {
  if (!m?.startedAt || !m?.submittedAt) return '—';
  let s = Math.round(
    (new Date(m.submittedAt).getTime() - new Date(m.startedAt).getTime()) /
      1000,
  );
  if (s < 0) return '—';
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
function attemptOf(m?: Partial<QuizAttempt> | null): string {
  let n = m?.attemptNumber ?? 1;
  let of = (m?.quiz as any)?.attemptsAllowed;
  return of ? `${n} of ${of}` : String(n);
}
function passMark(m?: Partial<QuizAttempt> | null): string {
  let p = (m?.quiz as any)?.passMarkPct;
  return p == null ? '—' : `${p}%`;
}
function dash(v: unknown): string {
  return v == null || v === '' ? '—' : String(v);
}

function inc(n?: number | null) {
  return (n ?? 0) + 1;
}

function join(list?: string[] | null) {
  return (list ?? []).join(', ');
}

export default QuizAttempt;
