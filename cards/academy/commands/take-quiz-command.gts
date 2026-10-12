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
import { Command, identifyCard } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';

import { Enrollment } from '../enrollment';
import { Quiz } from '../quiz';
import { QuizAttempt, scoreOf } from '../quiz-attempt';

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
  /** The caller's already-loaded attempts for this enrolment (attempt numbering + limit). */
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
    let { enrollment, quiz, answers, startedAt, realm } = input;
    if (!enrollment?.id) throw new Error('An enrollment is required');
    if (!quiz?.id) throw new Error('A quiz is required');
    if (!realm) throw new Error('A realm is required');
    enrollment = (await new GetCardCommand(this.commandContext).execute({
      cardId: enrollment.id,
    })) as Enrollment;
    quiz = (await new GetCardCommand(this.commandContext).execute({
      cardId: quiz.id,
    })) as Quiz;

    if (enrollment.enrollmentStatus !== 'active') {
      throw new Error(
        `${enrollment.learnerName || 'This learner'} is not active in this cohort`,
      );
    }
    if (!(quiz.questions ?? []).length)
      throw new Error(`${quiz.cardTitle} has no questions`);

    let pool: QuizAttempt[];
    if (input.priorAttempts?.length) {
      pool = (input.priorAttempts as QuizAttempt[]).filter(
        (a) => a?.enrollment?.id === enrollment!.id,
      );
    } else {
      let ref = identifyCard(QuizAttempt);
      pool = ref
        ? (((
            (await new SearchCardsByQueryCommand(this.commandContext).execute({
              query: {
                filter: { on: ref, eq: { 'enrollment.id': enrollment.id } },
              },
            } as any)) as any
          )?.instances ?? []) as QuizAttempt[])
        : [];
    }
    let prior = pool.filter((a) => a.quiz?.id === quiz!.id);
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

    let attempt = (await new SaveCardCommand(this.commandContext).execute({
      card: new QuizAttempt({
        enrollment,
        quiz,
        attemptNumber: prior.length + 1,
        startedAt: started,
        submittedAt: now,
      }),
      realm,
    } as any)) as QuizAttempt;

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: QuizAttempt,
    }).execute({
      cardId: attempt.id,
      patch: {
        attributes: {
          answers: (answers ?? []).map((a: any) => ({
            questionIndex: a.questionIndex ?? 0,
            selectedKeys: (a.selectedKeys ?? []).map((k: string) =>
              k.toLowerCase(),
            ),
            text: a.text ?? null,
          })),
        },
      },
    });

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
