import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { tracked } from '@glimmer/tracking';
import { realmURL } from '@cardstack/runtime-common';
import { Alert } from '@cardstack/pretui/components/alert';
import { Button } from '@cardstack/pretui/components/button';

import { QuizQuestionInput, type QuestionValue } from './quiz-question-input';
import TakeQuizCommand, {
  TakeQuizAnswerField,
} from '../commands/take-quiz-command';
import { scoreAnswer } from '../quiz-question-field';

interface Signature {
  Args: {
    quiz: any;
    enrollment: any;
    context?: any;
    attemptsUsed?: number;
    /** The enrolment's already-loaded attempts; passed through to Take Quiz. */
    priorAttempts?: any[];
    onSubmitted?: (result: { scorePct: number; message: string }) => void;
  };
  Element: HTMLElement;
}

type Phase = 'intro' | 'running' | 'done';

/**
 * Takes a learner through a quiz: intro (rules, attempts left), one question
 * at a time with a progress rail and an optional countdown, then the result
 * with every question revealed. Writes through Take Quiz — the runner never
 * scores for real; the preview score after submit uses the same
 * `scoreAnswer` the attempt card uses, so the two never disagree.
 */
export class QuizRunner extends GlimmerComponent<Signature> {
  @tracked phase: Phase = 'intro';
  @tracked current = 0;
  @tracked answers: Record<number, QuestionValue> = {};
  @tracked startedAt: Date | undefined;
  @tracked now = Date.now();
  @tracked busy = false;
  @tracked error: string | undefined;
  @tracked result: { scorePct: number; message: string } | undefined;
  private timer: ReturnType<typeof setInterval> | undefined;

  willDestroy() {
    super.willDestroy();
    if (this.timer) clearInterval(this.timer);
  }

  get questions(): any[] {
    return (this.args.quiz?.questions ?? []).filter(Boolean);
  }
  get total() {
    return this.questions.length;
  }
  get question() {
    return this.questions[this.current];
  }
  get value(): QuestionValue {
    return this.answers[this.current] ?? { selectedKeys: [] };
  }
  get answeredCount() {
    return Object.values(this.answers).filter(
      (v) => v.selectedKeys.length || v.text?.trim(),
    ).length;
  }
  get isLast() {
    return this.current >= this.total - 1;
  }
  get attemptsLeft(): number | undefined {
    let allowed = this.args.quiz?.attemptsAllowed;
    if (!allowed) return undefined;
    return Math.max(0, allowed - (this.args.attemptsUsed ?? 0));
  }
  get canStart() {
    return (
      this.total > 0 &&
      (this.attemptsLeft == null || this.attemptsLeft > 0) &&
      this.args.enrollment?.enrollmentStatus === 'active'
    );
  }
  get limitMs(): number | undefined {
    let d = this.args.quiz?.timeLimit;
    if (!d?.value) return undefined;
    let f: Record<string, number> = { minutes: 1, hours: 60, days: 1440 };
    return d.value * (f[d.unit ?? 'minutes'] ?? 1) * 60_000;
  }
  get remainingMs(): number | undefined {
    if (!this.limitMs || !this.startedAt) return undefined;
    return Math.max(0, this.limitMs - (this.now - this.startedAt.getTime()));
  }
  get remainingLabel() {
    let ms = this.remainingMs;
    if (ms == null) return '';
    let s = Math.ceil(ms / 1000);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  }
  get timeLow() {
    return this.remainingMs != null && this.remainingMs < 60_000;
  }
  get progressStyle() {
    return htmlSafe(
      `width: ${this.total ? Math.round(((this.current + 1) / this.total) * 100) : 0}%`,
    );
  }

  get preview() {
    let pts = 0;
    let correct = 0;
    this.questions.forEach((q, i) => {
      let a = this.answers[i];
      let r = scoreAnswer(
        q,
        a
          ? { questionIndex: i, selectedKeys: a.selectedKeys, text: a.text }
          : undefined,
      );
      pts += r.earned;
      if (r.correct) correct += 1;
    });
    return { pts, correct };
  }

  start = () => {
    this.answers = {};
    this.current = 0;
    this.error = undefined;
    this.startedAt = new Date();
    this.phase = 'running';
    // A prerender has no one to answer, so the countdown never starts there.
    if (this.limitMs && !(globalThis as any).__boxelRenderContext) {
      this.timer = setInterval(() => {
        this.now = Date.now();
        if (this.remainingMs === 0) this.submit();
      }, 500);
    }
  };

  setAnswer = (v: QuestionValue) => {
    this.answers = { ...this.answers, [this.current]: v };
  };

  go = (i: number) => {
    if (i >= 0 && i < this.total) this.current = i;
  };
  next = () => this.go(this.current + 1);
  prev = () => this.go(this.current - 1);

  submit = async () => {
    if (this.busy) return;
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
    let ctx = this.args.context?.commandContext;
    if (!ctx) {
      this.error = 'Commands are unavailable in this mode';
      return;
    }
    let realm = this.args.enrollment?.[realmURL]?.href;
    if (!realm) {
      this.error = 'Could not determine the realm for the attempt';
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      let res = (await new TakeQuizCommand(ctx).execute({
        enrollment: this.args.enrollment,
        quiz: this.args.quiz,
        answers: this.questions.map(
          (_q, i) =>
            new TakeQuizAnswerField({
              questionIndex: i,
              selectedKeys: this.answers[i]?.selectedKeys ?? [],
              text: this.answers[i]?.text ?? undefined,
            }),
        ),
        startedAt: this.startedAt?.toISOString(),
        priorAttempts: this.args.priorAttempts ?? [],
        realm,
      } as any)) as any;
      this.result = {
        scorePct: res?.scorePct ?? 0,
        message: res?.message ?? '',
      };
      this.phase = 'done';
      this.args.onSubmitted?.(this.result);
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  reset = () => {
    this.phase = 'intro';
    this.result = undefined;
    this.error = undefined;
  };

  <template>
    <section class='runner' ...attributes>
      {{#if (eq this.phase 'intro')}}
        <div class='intro'>
          <h2>{{@quiz.cardTitle}}</h2>
          {{#if @quiz.instructions}}<p
              class='instr'
            >{{@quiz.instructions}}</p>{{/if}}
          <dl class='rules'>
            <div><dt>Questions</dt><dd>{{this.total}}</dd></div>
            <div><dt>Pass mark</dt><dd>{{if
                  @quiz.passMarkPct
                  @quiz.passMarkPct
                  0
                }}%</dd></div>
            <div><dt>Time limit</dt><dd>{{if
                  @quiz.timeLimit.value
                  (durLabel @quiz.timeLimit)
                  'None'
                }}</dd></div>
            <div><dt>Attempts left</dt><dd>{{if
                  (isNum this.attemptsLeft)
                  this.attemptsLeft
                  'Unlimited'
                }}</dd></div>
          </dl>
          {{#unless this.canStart}}
            <p class='warn'>
              {{#if (eq this.total 0)}}This quiz has no questions yet.
              {{else if (eq this.attemptsLeft 0)}}No attempts left.
              {{else}}Only active enrolments can take quizzes.{{/if}}
            </p>
          {{/unless}}
          <Button
            class='cta'
            @tone='primary'
            @appearance='accent'
            @disabled={{not this.canStart}}
            {{on 'click' this.start}}
          >Start quiz</Button>
        </div>

      {{else if (eq this.phase 'running')}}
        <header class='bar'>
          <div class='track' aria-hidden='true'><span
              class='fill'
              style={{this.progressStyle}}
            ></span></div>
          <div class='bar-row'>
            <span class='count'>Question
              {{inc this.current}}
              of
              {{this.total}}
              ·
              {{this.answeredCount}}
              answered</span>
            {{#if this.remainingLabel}}
              <span
                class='timer {{if this.timeLow "low"}}'
                role='timer'
                aria-live='polite'
              >{{this.remainingLabel}}</span>
            {{/if}}
          </div>
        </header>
        <div class='body'>
          <QuizQuestionInput
            @question={{this.question}}
            @index={{this.current}}
            @value={{this.value}}
            @onChange={{this.setAnswer}}
            @groupId='run-{{this.current}}'
          />
        </div>
        <nav class='dots' aria-label='Jump to question'>
          {{#each this.questions as |_q i|}}
            <button
              type='button'
              class='dot
                {{if (eq i this.current) "here"}}
                {{if (has this.answers i) "filled"}}'
              aria-label='Question {{inc i}}'
              aria-current={{if (eq i this.current) 'true' 'false'}}
              {{on 'click' (fn this.go i)}}
            >{{inc i}}</button>
          {{/each}}
        </nav>
        {{#if this.error}}<Alert @tone='danger'>{{this.error}}</Alert>{{/if}}
        <footer class='foot'>
          <Button
            class='cta'
            @tone='neutral'
            @appearance='outlined'
            @disabled={{eq this.current 0}}
            {{on 'click' this.prev}}
          >Back</Button>
          {{#if this.isLast}}
            <Button
              class='cta'
              @tone='primary'
              @appearance='accent'
              @busy={{this.busy}}
              @disabled={{this.busy}}
              {{on 'click' this.submit}}
            >Submit quiz</Button>
          {{else}}
            <Button
              class='cta'
              @tone='primary'
              @appearance='accent'
              {{on 'click' this.next}}
            >Next</Button>
          {{/if}}
        </footer>

      {{else}}
        <div
          class='done
            {{if
              (passed this.result.scorePct @quiz.passMarkPct)
              "pass"
              "fail"
            }}'
        >
          <span class='big'>{{this.result.scorePct}}%</span>
          <span class='verdict'>{{if
              (passed this.result.scorePct @quiz.passMarkPct)
              'Passed'
              'Not passed'
            }}</span>
          <p class='msg'>{{this.result.message}}</p>
        </div>
        <div class='review'>
          {{#each this.questions as |q i|}}
            <div class='review-q'>
              <QuizQuestionInput
                @question={{q}}
                @index={{i}}
                @value={{lookup this.answers i}}
                @onChange={{noop}}
                @disabled={{true}}
                @reveal={{true}}
                @groupId='rev-{{i}}'
              />
            </div>
          {{/each}}
        </div>
        <footer class='foot end'>
          <Button
            class='cta'
            @tone='neutral'
            @appearance='outlined'
            {{on 'click' this.reset}}
          >Back to quiz</Button>
        </footer>
      {{/if}}
    </section>
    <style scoped>
      .cta {
        min-height: 2.75rem;
      }
      .runner {
        display: grid;
        gap: var(--boxel-sp);
        color: var(--foreground);
      }
      .intro {
        display: grid;
        gap: var(--boxel-sp-sm);
        justify-items: start;
      }
      h2 {
        margin: 0;
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
      }
      .instr {
        margin: 0;
        color: var(--muted-foreground);
      }
      .rules {
        margin: 0;
        display: flex;
        gap: var(--boxel-sp);
        flex-wrap: wrap;
      }
      .rules dt {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .rules dd {
        margin: 0;
        font-weight: 600;
      }
      .warn {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--destructive-ink);
      }
      .track {
        height: 0.25rem;
        border-radius: 2px;
        background: var(--muted);
        overflow: hidden;
      }
      .fill {
        display: block;
        height: 100%;
        background: var(--primary);
        transition: width 200ms ease;
      }
      .bar-row {
        display: flex;
        justify-content: space-between;
        margin-top: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .timer {
        font-family: var(--font-mono);
        font-weight: 700;
        color: var(--foreground);
      }
      .timer.low {
        color: var(--destructive-ink);
      }
      .body {
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
      .dots {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
      }
      .dot {
        width: 1.75rem;
        height: 1.75rem;
        border: 1px solid var(--border);
        border-radius: 50%;
        background: var(--card);
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        cursor: pointer;
      }
      .dot.filled {
        background: color-mix(in oklab, var(--primary) 14%, var(--card));
        color: var(--foreground);
      }
      .dot.here {
        border-color: var(--primary);
        box-shadow: 0 0 0 2px
          color-mix(in oklab, var(--primary) 30%, transparent);
      }
      .dot:focus-visible {
        outline: 2px solid var(--ring);
        outline-offset: 2px;
      }
      .foot {
        display: flex;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
      }
      .foot.end {
        justify-content: flex-start;
      }
      .done {
        display: grid;
        justify-items: center;
        gap: var(--boxel-sp-4xs);
        padding: var(--boxel-sp-lg);
        border-radius: var(--radius);
        background: var(--muted);
        text-align: center;
      }
      .done.pass {
        background: color-mix(in oklab, var(--success) 14%, var(--card));
      }
      .done.fail {
        background: color-mix(in oklab, var(--destructive) 12%, var(--card));
      }
      .big {
        font-size: var(--boxel-font-size-2xl);
        font-weight: 800;
        line-height: 1;
        font-variant-numeric: tabular-nums;
      }
      .verdict {
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        font-size: var(--boxel-font-size-sm);
      }
      .msg {
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground);
      }
      .review {
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .review-q {
        padding: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
      }
    </style>
  </template>
}

function eq(a: unknown, b: unknown) {
  return a === b;
}
function not(v: unknown) {
  return !v;
}
function inc(i: number) {
  return i + 1;
}
function isNum(n: unknown) {
  return typeof n === 'number';
}
function has(map: Record<number, QuestionValue>, i: number) {
  let v = map[i];
  return !!v && (v.selectedKeys.length > 0 || !!v.text?.trim());
}
function lookup(map: Record<number, QuestionValue>, i: number) {
  return map[i] ?? { selectedKeys: [] };
}
function noop() {}
function passed(pct?: number, passMark?: number) {
  return (pct ?? 0) >= (passMark ?? 0);
}
function durLabel(d: any) {
  return d?.label || `${d?.value} ${d?.unit ?? 'minutes'}`;
}

export default QuizRunner;
