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
import { eq } from '@cardstack/boxel-ui/helpers';
import { FitTile } from '../../ui-component/components/fit-tile';
import type { KeyValueItem } from '../../ui-component/components/key-value';
import { FittedExtras, type FittedStat } from '../procurement/vendor';

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
    get hue() {
      return this.args.model?.passed ? 'green' : 'red';
    }
    get subtitle() {
      return attemptLine(this.args.model);
    }
    get facts() {
      return attemptFacts(this.args.model);
    }
    get timeUsed() {
      return clock(secondsUsed(this.args.model));
    }
    <template>
      <article class='attempt'>
        <header class='bar'>
          <span class='mark' aria-hidden='true'>Qz</span>
          <div class='bar-id'>
            <h1>{{if @model.learnerName @model.learnerName 'Unlinked learner'}}
              ·
              {{@model.quizTitle}}</h1>
            <p class='bar-sub'>{{this.subtitle}}</p>
          </div>
          <div class='chips'>
            <StatePill
              @label={{if @model.passed 'passed' 'not passed'}}
              @hue={{this.hue}}
              @dot={{true}}
            />
            <StatePill @label='{{@model.scorePct}}%' @hue='blue' />
          </div>
        </header>
        <dl class='stats'>
          <div><dt>Score</dt><dd>{{@model.scorePct}}%</dd><dd
              class='foot'
            >{{@model.scorePoints}}
              of
              {{@model.quiz.totalPoints}}
              points</dd></div>
          <div><dt>Correct</dt><dd>{{@model.correctCount}}
              /
              {{@model.quiz.questionCount}}</dd><dd
              class='foot'
            >questions</dd></div>
          <div><dt>Time</dt><dd>{{this.timeUsed}}</dd>{{#if
              @model.quiz.timeLimit.value
            }}<dd class='foot'>of
                {{@model.quiz.timeLimit.value}}
                min</dd>{{/if}}</div>
        </dl>
        <section class='panel'>
          <h2>Answers</h2>
          <ol class='results'>
            {{#each this.results as |r index|}}
              <li class='{{if r.correct "ok" "miss"}}'>
                <span class='n'>{{inc index}}</span>
                <div class='r-body'>
                  <span class='r-prompt'>{{r.prompt}}</span>
                  <span class='r-given'>{{r.given}}</span>
                  {{#unless r.correct}}<span class='r-correct'>Correct:
                      {{r.expected}}</span>{{/unless}}
                </div>
                <span class='r-pts'>{{r.earned}}
                  /
                  {{r.points}}</span>
              </li>
            {{else}}
              <li class='empty'>No answers recorded.</li>
            {{/each}}
          </ol>
        </section>
        <div class='cols'>
          <section class='panel'>
            <h2>Details</h2>
            <dl class='kv'>
              {{#each this.facts as |f|}}
                <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
              {{/each}}
            </dl>
          </section>
          <section class='panel'>
            <h2>Linked</h2>
            <ul class='rels'>
              {{#if @model.enrollment}}<li><span
                  >Enrollment</span><@fields.enrollment
                    @format='atom'
                  /></li>{{/if}}
              {{#if @model.quiz}}<li><span>Quiz</span><@fields.quiz
                    @format='atom'
                  /></li>{{/if}}
            </ul>
          </section>
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .attempt {
            max-width: 56rem;
            margin: 0 auto;
            container-type: inline-size;
            padding: var(--boxel-sp-lg);
            display: grid;
            gap: var(--boxel-sp-lg);
            color: var(--foreground);
            background: var(--background);
          }
          .bar {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-sm);
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 3rem;
            block-size: 3rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .bar-id {
            flex: 1 1 14rem;
            min-width: 0;
          }
          h1 {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            line-height: 1.25;
          }
          .bar-sub {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            color: var(--muted-foreground);
          }
          .chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .stats {
            margin: 0;
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(10rem, 1fr));
            gap: var(--boxel-sp);
          }
          .stats > div {
            padding: var(--boxel-sp);
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: var(--shadow-sm);
          }
          .stats dt,
          .kv dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .stats dd {
            margin: 0;
            font-size: var(--boxel-font-size-lg);
            font-weight: 600;
            color: var(--primary);
            font-variant-numeric: tabular-nums;
          }
          .stats dd.foot {
            font-size: var(--boxel-font-size-xs);
            font-weight: 400;
            color: var(--muted-foreground);
          }
          .cols {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
            gap: var(--boxel-sp-lg);
          }
          .panel {
            padding: var(--boxel-sp-lg);
            border-radius: var(--radius);
            background: var(--card);
            box-shadow: var(--shadow-sm);
            min-width: 0;
          }
          .panel h2 {
            margin: 0 0 var(--boxel-sp);
            font-size: var(--boxel-font-size);
            font-weight: 600;
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
            grid-template-columns: auto minmax(0, 1fr) auto;
            gap: var(--boxel-sp-sm);
            align-items: start;
            font-size: var(--boxel-font-size-sm);
          }
          .n {
            font-weight: 600;
            color: var(--muted-foreground);
          }
          .miss .n {
            color: var(--destructive-ink);
          }
          .r-body {
            display: grid;
            gap: var(--boxel-sp-5xs);
            min-width: 0;
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
          }
          .kv {
            margin: 0;
            display: grid;
            gap: var(--boxel-sp-xs);
            font-size: var(--boxel-font-size-sm);
          }
          .kv > div {
            display: flex;
            justify-content: space-between;
            gap: var(--boxel-sp-sm);
          }
          .kv dd {
            margin: 0;
            font-weight: 600;
            text-align: end;
          }
          .rels {
            list-style: none;
            margin: 0;
            padding: 0;
            display: grid;
            gap: var(--boxel-sp-xs);
            font-size: var(--boxel-font-size-sm);
          }
          .rels li {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs);
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get hue() {
      return this.args.model?.passed ? 'green' : 'red';
    }
    get subtitle() {
      return attemptLine(this.args.model);
    }
    get facts() {
      return attemptFacts(this.args.model);
    }
    <template>
      <article class='emb'>
        <header class='emb-head'>
          <span class='mark' aria-hidden='true'>Qz</span>
          <div class='emb-id'>
            <h4 class='emb-title'>{{if
                @model.learnerName
                @model.learnerName
                'Learner'
              }}
              ·
              {{@model.quizTitle}}</h4>
            <p class='emb-sub'>{{this.subtitle}}</p>
          </div>
          <div class='emb-chips'>
            <StatePill
              @label={{if @model.passed 'passed' 'not passed'}}
              @hue={{this.hue}}
              @dot={{true}}
            />
            <StatePill @label='{{@model.scorePct}}%' @hue='blue' />
          </div>
        </header>
        <p class='emb-sub'>{{@model.scorePoints}}
          /
          {{@model.quiz.totalPoints}}
          points · pass mark
          {{@model.quiz.passMarkPct}}%</p>
        <dl class='emb-kv'>
          {{#each this.facts as |f|}}
            <div><dt>{{f.key}}</dt><dd>{{f.value}}</dd></div>
          {{/each}}
        </dl>
        <div class='emb-rels'>
          {{#if @model.enrollment}}<span class='emb-rel'>Enrollment
              <@fields.enrollment @format='atom' /></span>{{/if}}
          {{#if @model.quiz}}<span class='emb-rel'>Quiz
              <@fields.quiz @format='atom' /></span>{{/if}}
        </div>
      </article>
      <style scoped>
        @layer PretComponent {
          .emb {
            display: flex;
            flex-direction: column;
            gap: var(--boxel-sp-sm);
            padding: var(--boxel-sp-sm);
            font-size: var(--boxel-font-size-sm);
          }
          .emb-head {
            display: flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2.5rem;
            block-size: 2.5rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
          .emb-id {
            flex: 1 1 12rem;
            min-width: 0;
          }
          .emb-title {
            margin: 0;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
          }
          .emb-sub {
            margin: 0;
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-chips {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-4xs);
          }
          .emb-kv {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
            margin: 0;
          }
          .emb-kv dt {
            font-size: var(--boxel-font-size-xs);
            color: var(--muted-foreground);
          }
          .emb-kv dd {
            margin: 0;
            font-weight: 600;
            font-variant-numeric: tabular-nums;
          }
          .emb-rels {
            display: flex;
            flex-wrap: wrap;
            gap: var(--boxel-sp-xs) var(--boxel-sp-sm);
          }
          .emb-rel {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            min-width: 0;
            color: var(--muted-foreground);
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get hue() {
      return this.args.model?.passed ? 'green' : 'red';
    }
    <template>
      <span class='atom'>
        <span class='mark' aria-hidden='true'>Qz</span>
        <span class='atom-name'>{{if
            @model.learnerName
            @model.learnerName
            'Learner'
          }}
          ·
          {{@model.quizTitle}}</span>
        <span class='atom-chip'><StatePill
            @label={{if @model.passed 'passed' 'not passed'}}
            @hue={{this.hue}}
          /></span>
      </span>
      <style scoped>
        @layer PretComponent {
          .atom {
            display: inline-flex;
            align-items: center;
            gap: var(--boxel-sp-4xs);
            max-width: 100%;
            min-width: 0;
            /* a chip that cannot fit whole wraps onto a clipped second line
               instead of showing half a word */
            flex-wrap: wrap;
            align-content: flex-start;
            block-size: 1.5rem;
            row-gap: 1.5rem;
            overflow: hidden;
            vertical-align: middle;
            font-size: var(--boxel-font-size-sm);
            font-weight: 600;
            line-height: 1.5;
            color: var(--foreground);
            white-space: nowrap;
          }
          .mark {
            display: inline-grid;
            place-items: center;
            flex: none;
            inline-size: 1.25rem;
            block-size: 1.25rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: 0.625rem;
            font-weight: 600;
            line-height: 1;
          }
          .atom-name {
            flex: 1 1 4rem;
            min-width: 0;
            overflow: hidden;
            text-overflow: ellipsis;
          }
          .atom-chip {
            flex: none;
          }
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    get hue() {
      return this.args.model?.passed ? 'green' : 'red';
    }
    get subtitle() {
      return attemptLine(this.args.model);
    }
    get fact() {
      let m = this.args.model;
      return `${m?.scorePoints ?? 0} / ${m?.quiz?.totalPoints ?? 0} points · pass mark ${m?.quiz?.passMarkPct ?? 0}%`;
    }
    get facts(): KeyValueItem[] {
      return attemptFacts(this.args.model);
    }
    get stats(): FittedStat[] {
      let m = this.args.model;
      return [
        { key: 'Score', value: `${m?.scorePct ?? 0}%` },
        {
          key: 'Correct',
          value: `${m?.correctCount ?? 0} / ${m?.quiz?.questionCount ?? 0}`,
        },
        { key: 'Time', value: clock(secondsUsed(m)) },
      ];
    }
    get relations() {
      let m = this.args.model;
      return [
        ...(m?.enrollment ? ['Enrollment'] : []),
        ...(m?.quiz ? ['Quiz'] : []),
      ];
    }
    <template>
      <FittedExtras
        @facts={{this.facts}}
        @stats={{this.stats}}
        @relations={{this.relations}}
      >
        <:default>
          <FitTile>
            <:avatar><span class='mark' aria-hidden='true'>Qz</span></:avatar>
            <:title><span class='fit-title' role='heading' aria-level='3'>{{if
                  @model.learnerName
                  @model.learnerName
                  'Learner'
                }}
                ·
                {{@model.quizTitle}}</span></:title>
            <:subtitle>{{this.subtitle}}</:subtitle>
            <:status>
              <StatePill
                @label={{if @model.passed 'passed' 'not passed'}}
                @hue={{this.hue}}
                @dot={{true}}
              />
              <StatePill @label='{{@model.scorePct}}%' @hue='blue' />
            </:status>
            <:fact>{{this.fact}}</:fact>
          </FitTile>
        </:default>
        <:relation as |label|>
          {{#if (eq label 'Enrollment')}}<@fields.enrollment
              @format='atom'
            />{{else}}<@fields.quiz @format='atom' />{{/if}}
        </:relation>
      </FittedExtras>
      <style scoped>
        @layer PretComponent {
          .fit-title {
            display: block;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .mark {
            display: inline-grid;
            place-items: center;
            inline-size: 2rem;
            block-size: 2rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--muted);
            color: var(--primary);
            font-size: var(--boxel-font-size-xs);
            font-weight: 600;
          }
        }
      </style>
    </template>
  };
}

function secondsUsed(m?: Partial<QuizAttempt> | null): number {
  if (!m?.startedAt || !m?.submittedAt) return 0;
  return Math.max(
    0,
    Math.round(
      (new Date(m.submittedAt).getTime() - new Date(m.startedAt).getTime()) /
        1000,
    ),
  );
}

function clock(sec: number): string {
  return `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
}

function spoken(sec: number): string {
  let min = Math.floor(sec / 60);
  let rest = sec % 60;
  return [min ? `${min} min` : '', rest ? `${rest} s` : '']
    .filter(Boolean)
    .join(' ');
}

function attemptLine(m?: Partial<QuizAttempt> | null): string {
  let used = secondsUsed(m);
  return [
    `Attempt ${m?.attemptNumber ?? 1}`,
    m?.submittedAt ? fmtDay(m.submittedAt) : '',
    used ? spoken(used) : '',
  ]
    .filter(Boolean)
    .join(' · ');
}

function attemptFacts(m?: Partial<QuizAttempt> | null): KeyValueItem[] {
  let quiz = m?.quiz as any;
  return [
    { key: 'Quiz', value: m?.quizTitle || '—' },
    {
      key: 'Attempt',
      value: quiz?.attemptsAllowed
        ? `${m?.attemptNumber ?? 1} of ${quiz.attemptsAllowed}`
        : String(m?.attemptNumber ?? 1),
    },
    {
      key: 'Score',
      value: `${m?.scorePoints ?? 0} / ${quiz?.totalPoints ?? 0}`,
    },
    {
      key: 'Correct',
      value: `${m?.correctCount ?? 0} of ${quiz?.questionCount ?? 0}`,
    },
    { key: 'Started', value: fmtDateTime(m?.startedAt) },
    { key: 'Submitted', value: fmtDateTime(m?.submittedAt) },
    {
      key: 'Pass mark',
      value: quiz?.passMarkPct ? `${quiz.passMarkPct}%` : '—',
    },
  ];
}

function fmtDay(d: Date | string): string {
  return new Date(d).toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
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
