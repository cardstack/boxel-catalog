import {
  CardDef,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { findCards } from '@cardstack/catalog/utils/find-card';
import { linkedId } from '@cardstack/catalog/utils/linked-id';

import { Enrollment } from '../enrollment';
import { Quiz } from '../quiz';
import { QuizAnswerField, QuizAttempt, scoreOf } from '../quiz-attempt';
import { byId, realmOf, typedCard } from './links';

export class TakeQuizAnswerField extends FieldDef {
  @field questionIndex = contains(NumberField);
  @field selectedKeys = containsMany(StringField);
  @field text = contains(StringField);
}

export class TakeQuizInput extends CardDef {
  @field enrollment = linksTo(() => Enrollment, { searchable: true });
  @field quiz = linksTo(() => Quiz, { searchable: true });
  @field answers = containsMany(TakeQuizAnswerField);
  @field startedAt = contains(StringField, {
    description: 'ISO instant the runner opened, for the time limit.',
  });
  /** Attempts the caller has loaded, counted with the realm's own. */
  @field priorAttempts = linksToMany(() => QuizAttempt);
  @field realm = contains(StringField);
}

export class TakeQuizResult extends CardDef {
  @field attempt = linksTo(() => QuizAttempt);
  @field scorePct = contains(NumberField);
  @field message = contains(StringField);
}

/**
 * Records one sitting. Refuses when the enrolment is not active, when the
 * learner has used every allowed attempt, or when the sitting overran the
 * time limit (with a one-minute grace for the round trip). Scoring is not
 * done here — the attempt computes it from the quiz key, so this command
 * only writes facts: which answers, when.
 */
export default class TakeQuizCommand extends Command<
  typeof TakeQuizInput,
  typeof TakeQuizResult
> {
  static actionVerb = 'Submit quiz';
  static displayName = 'Take Quiz';

  async getInputType() {
    return TakeQuizInput;
  }

  protected async run(input: TakeQuizInput): Promise<TakeQuizResult> {
    let { answers, startedAt } = input;
    let enrollmentId = linkedId(input, 'enrollment');
    let quizId = linkedId(input, 'quiz');
    if (!enrollmentId) throw new Error('An enrollment is required');
    if (!quizId) throw new Error('A quiz is required');
    let enrollment = await typedCard(
      this.commandContext,
      enrollmentId,
      Enrollment,
    );
    let quiz = await typedCard(this.commandContext, quizId, Quiz);
    let realm = input.realm || realmOf(enrollment);
    if (!realm) throw new Error('A realm is required');

    if (enrollment.enrollmentStatus !== 'active') {
      throw new Error(
        `${enrollment.learnerName || 'This learner'} is not active in this cohort`,
      );
    }
    if (!(quiz.questions ?? []).length)
      throw new Error(`${quiz.cardTitle} has no questions`);

    let prior = byId(
      await findCards<QuizAttempt>(
        this.commandContext,
        QuizAttempt,
        { 'enrollment.id': enrollmentId, 'quiz.id': quizId },
        realm,
      ),
      ((input.priorAttempts ?? []) as QuizAttempt[]).filter(
        (a) =>
          a &&
          linkedId(a, 'enrollment') === enrollmentId &&
          linkedId(a, 'quiz') === quizId,
      ),
    );
    if (quiz.attemptsAllowed && prior.length >= quiz.attemptsAllowed) {
      throw new Error(
        `No attempts left: ${prior.length} of ${quiz.attemptsAllowed} used`,
      );
    }

    let now = new Date();
    let started = startedAt ? new Date(startedAt) : now;
    let limitMin = quizMinutes(quiz.timeLimit);
    if (
      limitMin &&
      now.getTime() - started.getTime() > (limitMin + 1) * 60_000
    ) {
      throw new Error(`Time limit of ${limitMin} minutes exceeded`);
    }

    // Answers go in the same save as the attempt, so an interrupted run can't
    // leave an answerless attempt that costs the learner one of their tries.
    let attempt = (await new SaveCardCommand(this.commandContext).execute({
      card: new QuizAttempt({
        enrollment,
        quiz,
        attemptNumber: prior.length + 1,
        startedAt: started,
        submittedAt: now,
        answers: (answers ?? []).map(
          (a: any) =>
            new QuizAnswerField({
              questionIndex: a.questionIndex ?? 0,
              selectedKeys: (a.selectedKeys ?? []).map((k: string) =>
                k.toLowerCase(),
              ),
              text: a.text ?? null,
            }),
        ),
      }),
      realm,
    } as any)) as QuizAttempt;

    let s = scoreOf({
      quiz,
      answers: (answers ?? []) as any,
    } as Partial<QuizAttempt>);
    return new TakeQuizResult({
      attempt,
      scorePct: s.pct,
      message: `${s.pct}% — ${s.passed ? 'passed' : 'not passed'} (${s.correct} of ${(quiz.questions ?? []).length} correct, attempt ${prior.length + 1}).`,
    });
  }
}

function quizMinutes(d: any): number {
  if (!d?.value) return 0;
  let f: Record<string, number> = { minutes: 1, hours: 60, days: 1440 };
  return d.value * (f[d.unit ?? 'minutes'] ?? 1);
}
