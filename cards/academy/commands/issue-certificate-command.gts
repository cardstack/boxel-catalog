import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import {
  findCard,
  findCards,
  getCard,
  inputCard,
} from '@cardstack/catalog/utils/find-card';
import { linkedId, linkedIds } from '@cardstack/catalog/utils/linked-id';

import { Assignment } from '../assignment';
import { Cohort, type ModuleReleaseField } from '../cohort';
import { Course } from '../course';
import { Module } from '../course-module';
import { Enrollment } from '../enrollment';
import { Grade } from '../grade';
import { Learner } from '../learner';
import { Lesson } from '../lesson';
import { Quiz } from '../quiz';
import { Certificate } from '../certificate';
import { CertificationAuthority } from '../../audit/certification-authority';
import { Employee } from '../../hr/employee';
import { Submission } from '../submission';
import { AttendanceRecord } from '../attendance-record';
import { QuizAttempt, scoreOf } from '../quiz-attempt';
import {
  allSatisfied,
  evaluateCompletion,
  type CompletionClause,
  type CompletionFacts,
} from '../completion-evaluation-field';
import { letterFor } from '../grade-scale-field';
import { nextCertificateNumber } from '../certificate-number-field';
import { byId, linkedCard, linkedCards, realmOf, typedCard } from './links';

export class IssueCertificateInput extends CardDef {
  @field enrollment = linksTo(() => Enrollment, { searchable: true });
  @field authority = linksTo(() => CertificationAuthority, {
    searchable: true,
  });
  @field issuedBy = linksTo(() => Employee, { searchable: true });
  /** Facts the caller has loaded, judged with the realm's own. */
  @field submissions = linksToMany(() => Submission);
  @field attendanceRecords = linksToMany(() => AttendanceRecord);
  @field quizAttempts = linksToMany(() => QuizAttempt);
  @field force = contains(BooleanField, {
    description:
      'Issue even if the completion rule is not met (recorded in the message).',
  });
  @field realm = contains(StringField);
}

export class IssueCertificateResult extends CardDef {
  @field certificate = linksTo(() => Certificate);
  @field message = contains(StringField);
}

/**
 * The ceremony. Re-evaluates completion from the realm with the SAME pure
 * function the Learner Progress panel uses, refuses with the unmet clauses
 * verbatim unless forced, claims the next number from the authority (see
 * `claimNumber`), snapshots the printed facts onto the Certificate, links it
 * from the Enrollment, and marks the enrolment completed.
 */
export default class IssueCertificateCommand extends Command<
  typeof IssueCertificateInput,
  typeof IssueCertificateResult
> {
  static actionVerb = 'Issue';
  static displayName = 'Issue Certificate';

  async getInputType() {
    return IssueCertificateInput;
  }

  // Runs against one authority go one at a time in this host, so two
  // workspaces (or stacks) issuing at once take distinct numbers and see each
  // other's certificates.
  protected async run(
    input: IssueCertificateInput,
  ): Promise<IssueCertificateResult> {
    let authorityId = linkedId(input, 'authority');
    return authorityId
      ? oneAtATime(authorityId, () => this.issue(input))
      : this.issue(input);
  }

  private async issue(
    input: IssueCertificateInput,
  ): Promise<IssueCertificateResult> {
    let enrollmentId = linkedId(input, 'enrollment');
    let authorityId = linkedId(input, 'authority');
    if (!enrollmentId) throw new Error('An enrollment is required');
    if (!authorityId) throw new Error('A certification authority is required');
    let ctx = this.commandContext;
    let enrollment = await typedCard(ctx, enrollmentId, Enrollment);
    let authority = await typedCard(ctx, authorityId, CertificationAuthority);
    let realm = input.realm || realmOf(enrollment);
    if (!realm) throw new Error('A realm is required');
    let issuedBy = await inputCard<Employee>(ctx, input, 'issuedBy');
    let learner = await linkedCard<Learner>(ctx, enrollment, 'learner');
    let learnerName = learner?.name || enrollment.learnerName || 'This learner';

    if (enrollment.enrollmentStatus === 'withdrawn') {
      throw new Error(`${learnerName} withdrew from the cohort`);
    }

    // The enrolment's live certificate: the linked one, or one an earlier run
    // saved before it was interrupted, which this run finishes.
    let linked = await linkedCard<Certificate>(ctx, enrollment, 'certificate');
    if (linked && linked.certStatus !== 'revoked') {
      throw new Error(
        `${learnerName} already holds ${linked.number ?? 'a certificate'} for this cohort`,
      );
    }
    let certificate = await findCard<Certificate>(
      ctx,
      Certificate,
      { 'enrollment.id': enrollmentId, certStatus: 'issued' },
      realm,
    );

    let cohort = await linkedCard<Cohort>(ctx, enrollment, 'cohort');
    let course = cohort
      ? await linkedCard<Course>(ctx, cohort, 'course')
      : undefined;
    if (!cohort || !course)
      throw new Error('The enrollment has no course to certify against');

    let unmet: CompletionClause[] = [];
    let noRule = false;
    if (!certificate) {
      let facts = await this.completionFacts(
        input,
        enrollmentId,
        cohort,
        course,
        realm,
      );
      let clauses = evaluateCompletion(course.completionRule, facts);
      unmet = clauses.filter((c) => !c.satisfied);
      // Same verdict as Learner Progress: a course with no completion rule
      // has nothing to certify against, so it needs `force` too.
      if (!allSatisfied(clauses) && !input.force) {
        throw new Error(
          clauses.length
            ? `Not eligible — ${unmet.map((c) => `${c.rule}: ${c.actual} of ${c.required} (${c.evidence})`).join('; ')}`
            : `Not eligible — ${course.cardTitle} has no completion rule`,
        );
      }
      noRule = !clauses.length;

      let number = await this.claimNumber(authorityId, realm);
      try {
        certificate = (await new SaveCardCommand(ctx).execute({
          card: new Certificate({
            number,
            enrollment,
            authority,
            issuedBy,
            issuedAt: new Date(),
            certStatus: 'issued',
            learnerName: learner?.name || enrollment.learnerName || '',
            courseTitle: course.cardTitle,
            cohortName: cohort.cardTitle,
            creditHours: course.creditHours ?? undefined,
            finalLetter: facts.overallLetter ?? undefined,
          }),
          realm,
        } as any)) as Certificate;
      } catch (e) {
        await this.releaseNumber(authorityId, number);
        throw e;
      }
    }

    // A certificate an interrupted run saved can be ahead of the authority.
    let sequence = sequenceOf(certificate.number);
    let current = await typedCard(ctx, authorityId, CertificationAuthority);
    if (sequence > (current.lastSequence ?? 0)) {
      await new PatchCardInstanceCommand(ctx, {
        cardType: CertificationAuthority,
      }).execute({
        cardId: authorityId,
        patch: { attributes: { lastSequence: sequence } },
      });
    }

    await new PatchCardInstanceCommand(ctx, {
      cardType: Enrollment,
    }).execute({
      cardId: enrollmentId,
      patch: {
        attributes: {
          enrollmentStatus: 'completed',
          completedAt: enrollment.completedAt
            ? undefined
            : new Date().toISOString(),
        },
        relationships: { certificate: { links: { self: certificate.id } } },
      },
    });

    let letter = certificate.finalLetter;
    let forced = unmet.length
      ? ` (forced: ${unmet.map((c) => c.rule).join(', ')} unmet)`
      : noRule
        ? ' (forced: no completion rule)'
        : '';
    return new IssueCertificateResult({
      certificate,
      message: `${certificate.number} issued to ${certificate.learnerName}${letter ? ` · final ${letter}` : ''}${forced}.`,
    });
  }

  // The realm has no transaction, so a number is claimed before the
  // certificate is saved: skip any number a certificate already carries,
  // write the sequence, then re-read the authority and start over if another
  // writer moved it in between. Within this host `oneAtATime` already orders
  // the runs; across hosts this narrows the window to the claim itself.
  private async claimNumber(authorityId: string, realm: string) {
    let ctx = this.commandContext;
    let year = new Date().getFullYear();
    for (let attempt = 0; attempt < 5; attempt++) {
      let authority = await typedCard(ctx, authorityId, CertificationAuthority);
      let next = nextCertificateNumber(
        authority.numberPrefix,
        year,
        authority.lastSequence,
      );
      while (
        await findCard<Certificate>(
          ctx,
          Certificate,
          { number: next.number },
          realm,
        )
      ) {
        next = nextCertificateNumber(
          authority.numberPrefix,
          year,
          next.sequence,
        );
      }
      await new PatchCardInstanceCommand(ctx, {
        cardType: CertificationAuthority,
      }).execute({
        cardId: authorityId,
        patch: { attributes: { lastSequence: next.sequence } },
      });
      let claimed = await typedCard(ctx, authorityId, CertificationAuthority);
      if (claimed.lastSequence === next.sequence) {
        return next.number;
      }
    }
    throw new Error(
      'Another issue is numbering certificates for this authority; try again',
    );
  }

  // Gives a claimed number back when its certificate could not be saved,
  // unless another run has already claimed past it.
  private async releaseNumber(authorityId: string, number: string) {
    let ctx = this.commandContext;
    let sequence = sequenceOf(number);
    try {
      let authority = await typedCard(ctx, authorityId, CertificationAuthority);
      if (authority.lastSequence === sequence) {
        await new PatchCardInstanceCommand(ctx, {
          cardType: CertificationAuthority,
        }).execute({
          cardId: authorityId,
          patch: { attributes: { lastSequence: sequence - 1 } },
        });
      }
    } catch {
      // The save's own error is the one to report.
    }
  }

  // Everything the completion rule judges, read from the realm by stored id.
  // The caller's loaded lists are kept alongside the search, which can miss
  // cards that aren't indexed yet.
  private async completionFacts(
    input: IssueCertificateInput,
    enrollmentId: string,
    cohort: Cohort,
    course: Course,
    realm: string,
  ): Promise<CompletionFacts> {
    let ctx = this.commandContext;
    let mine = <T extends CardDef>(list: T[] | undefined) =>
      (list ?? []).filter(
        (x) => x && linkedId(x, 'enrollment') === enrollmentId,
      );
    let find = <T extends CardDef>(type: typeof CardDef) =>
      findCards<T>(ctx, type, { 'enrollment.id': enrollmentId }, realm);

    let subs = byId(
      await find<Submission>(Submission),
      mine(input.submissions as Submission[]),
    );
    let marks = byId(
      await find<AttendanceRecord>(AttendanceRecord),
      mine(input.attendanceRecords as AttendanceRecord[]),
    );
    let attempts = byId(
      await find<QuizAttempt>(QuizAttempt),
      mine(input.quizAttempts as QuizAttempt[]),
    );

    let released = new Set(
      ((cohort.releases ?? []) as ModuleReleaseField[])
        .map((r) => linkedId(cohort, 'module', r))
        .filter(Boolean),
    );
    let modules = await Promise.all(
      linkedIds(course, 'modules')
        .filter((id) => released.has(id))
        .map((id) => getCard<Module>(ctx, id)),
    );
    let assignments = (
      await Promise.all(
        modules.map((m) => linkedCards<Assignment>(ctx, m, 'assignments')),
      )
    ).flat();
    let lessons = (
      await Promise.all(
        modules.map((m) => linkedCards<Lesson>(ctx, m, 'lessons')),
      )
    ).flat();
    let now = Date.now();
    let liveLessonsHeld = lessons.filter(
      (l) =>
        l.kind === 'live' &&
        (!l.liveSessionAt || new Date(l.liveSessionAt).getTime() <= now),
    ).length;

    let graded = subs.filter((s) => s.submissionStatus === 'graded');
    let gradedAssignments = new Set(
      graded.map((s) => linkedId(s, 'assignment')),
    );
    let grades = (
      await Promise.all(graded.map((s) => linkedCard<Grade>(ctx, s, 'grade')))
    ).filter((g): g is Grade => Boolean(g));
    let earned = grades.reduce((n, g) => n + (g.total ?? 0), 0);
    let max = grades.reduce((n, g) => n + (g.maxPoints ?? 0), 0);
    let pct = max ? Math.round((earned / max) * 100) : undefined;

    // An attempt's `passed` is computed from its quiz link, so score it here
    // against the fetched quiz.
    let passedQuizzes = new Set<string>();
    for (let attempt of attempts) {
      let quiz = await linkedCard<Quiz>(ctx, attempt, 'quiz');
      if (
        quiz?.id &&
        scoreOf({ quiz, answers: attempt.answers } as Partial<QuizAttempt>)
          .passed
      ) {
        passedQuizzes.add(quiz.id);
      }
    }

    return {
      attendanceRecords: marks,
      liveLessonsHeld,
      requiredAssignments: assignments
        .filter((a) => a.required)
        .map((a) => ({ id: a.id, title: a.cardTitle ?? '' })),
      gradedRequiredAssignmentIds: assignments
        .filter((a) => gradedAssignments.has(a.id))
        .map((a) => a.id),
      quizzesPassed: passedQuizzes.size,
      overallLetter: letterFor(pct, course.gradeScale),
      scale: course.gradeScale,
    };
  }
}

const queues = new Map<string, Promise<unknown>>();

function oneAtATime<T>(key: string, fn: () => Promise<T>): Promise<T> {
  let run = (queues.get(key) ?? Promise.resolve()).catch(() => {}).then(fn);
  queues.set(key, run);
  return run.finally(() => {
    if (queues.get(key) === run) queues.delete(key);
  });
}

function sequenceOf(number?: string | null): number {
  let match = /-(\d+)$/.exec(number ?? '');
  return match ? Number(match[1]) : 0;
}
