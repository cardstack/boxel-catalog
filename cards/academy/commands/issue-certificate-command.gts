import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import { Command, identifyCard } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';

import { Enrollment } from '../enrollment';
import { Certificate } from '../certificate';
import { CertificationAuthority } from '@cardstack/catalog/cards/audit/certification-authority';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Submission } from '../submission';
import { AttendanceRecord } from '../attendance-record';
import { QuizAttempt } from '../quiz-attempt';
import { evaluateCompletion } from '../completion-evaluation-field';
import { letterFor } from '../grade-scale-field';
import { nextCertificateNumber } from '../certificate-number-field';

export class IssueCertificateInput extends CardDef {
  @field enrollment = linksTo(() => Enrollment, { searchable: true });
  @field authority = linksTo(() => CertificationAuthority, {
    searchable: true,
  });
  @field issuedBy = linksTo(() => Employee, { searchable: true });
  /** The caller's already-loaded facts for this enrolment (any cohort's lists are fine; filtered here). */
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
 * verbatim unless forced, takes the next number from the authority (single
 * writer of the sequence), snapshots the printed facts onto the Certificate,
 * links it from the Enrollment, and marks the enrolment completed.
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

  protected async run(
    input: IssueCertificateInput,
  ): Promise<IssueCertificateResult> {
    let { enrollment, authority, issuedBy, force, realm } = input;
    if (!enrollment?.id) throw new Error('An enrollment is required');
    if (!authority?.id)
      throw new Error('A certification authority is required');
    if (!realm) throw new Error('A realm is required');
    enrollment = (await new GetCardCommand(this.commandContext).execute({
      cardId: enrollment.id,
    })) as Enrollment;
    authority = (await new GetCardCommand(this.commandContext).execute({
      cardId: authority.id,
    })) as CertificationAuthority;

    if (
      enrollment.certificate?.id &&
      (enrollment.certificate as any).certStatus !== 'revoked'
    ) {
      throw new Error(
        `${enrollment.learnerName || 'This learner'} already holds ${(enrollment.certificate as any).number ?? 'a certificate'} for this cohort`,
      );
    }
    if (enrollment.enrollmentStatus === 'withdrawn') {
      throw new Error(
        `${enrollment.learnerName || 'This learner'} withdrew from the cohort`,
      );
    }

    let cohort = enrollment.cohort as any;
    let course = cohort?.course;
    if (!course)
      throw new Error('The enrollment has no course to certify against');

    // The caller passes the enrolment's already-loaded submissions, attendance
    // records and quiz attempts (block-factory: commands take the consumer's
    // loaded instances — SearchCardsByQuery only sees the user's own realms).
    // A realm search is attempted only when nothing was supplied.
    let mine = (list: any[] | undefined) =>
      (list ?? []).filter((x) => x && x.enrollment?.id === enrollment!.id);
    let search = async (cls: any) => {
      let ref = identifyCard(cls);
      if (!ref) return [] as any[];
      let r = (await new SearchCardsByQueryCommand(this.commandContext).execute(
        {
          query: {
            filter: { on: ref, eq: { 'enrollment.id': enrollment!.id } },
          },
        } as any,
      )) as any;
      return (r?.instances ?? []) as any[];
    };
    let subs = input.submissions?.length
      ? mine(input.submissions as any[])
      : await search(Submission);
    let marks = input.attendanceRecords?.length
      ? mine(input.attendanceRecords as any[])
      : await search(AttendanceRecord);
    let attempts = input.quizAttempts?.length
      ? mine(input.quizAttempts as any[])
      : await search(QuizAttempt);

    let releasedIds = new Set(
      ((cohort.releases ?? []) as any[])
        .map((r) => r?.module?.id)
        .filter(Boolean),
    );
    let modules = ((course.modules ?? []) as any[]).filter(
      (m) => m && releasedIds.has(m.id),
    );
    let assignments = modules.flatMap((m) =>
      (m.assignments ?? []).filter(Boolean),
    );
    let now = Date.now();
    let liveHeld = modules
      .flatMap((m) => (m.lessons ?? []).filter(Boolean))
      .filter(
        (l: any) =>
          l.kind === 'live' &&
          (!l.liveSessionAt || new Date(l.liveSessionAt).getTime() <= now),
      ).length;
    let graded = subs.filter((s) => s.submissionStatus === 'graded');
    // Caller-supplied instances may not have their `grade` link loaded yet;
    // re-fetch those so the totals below see real numbers.
    graded = await Promise.all(
      graded.map(async (s) =>
        s.grade || !s.id
          ? s
          : (((await new GetCardCommand(this.commandContext).execute({
              cardId: s.id,
            })) as any) ?? s),
      ),
    );
    let gradedIds = assignments
      .filter((a) => graded.some((s) => s.assignment?.id === a.id))
      .map((a) => a.id);
    let passed = new Set(
      attempts.filter((a) => a.passed && a.quiz?.id).map((a) => a.quiz.id),
    ).size;
    let scored = graded.filter((s) => s.grade);
    let earned = scored.reduce((n, s) => n + (s.grade.total ?? 0), 0);
    let max = scored.reduce((n, s) => n + (s.grade.maxPoints ?? 0), 0);
    let pct = max ? Math.round((earned / max) * 100) : undefined;
    let letter = letterFor(pct, course.gradeScale);

    let clauses = evaluateCompletion(course.completionRule, {
      attendanceRecords: marks,
      liveLessonsHeld: liveHeld,
      requiredAssignments: assignments
        .filter((a) => a.required)
        .map((a) => ({ id: a.id, title: a.cardTitle })),
      gradedRequiredAssignmentIds: gradedIds,
      quizzesPassed: passed,
      overallLetter: letter,
      scale: course.gradeScale,
    });
    let unmet = clauses.filter((c) => !c.satisfied);
    if (unmet.length && !force) {
      throw new Error(
        `Not eligible — ${unmet.map((c) => `${c.rule}: ${c.actual} of ${c.required} (${c.evidence})`).join('; ')}`,
      );
    }

    let year = new Date().getFullYear();
    let { number, sequence } = nextCertificateNumber(
      authority.numberPrefix,
      year,
      authority.lastSequence,
    );
    let issuedAt = new Date();

    let certificate = (await new SaveCardCommand(this.commandContext).execute({
      card: new Certificate({
        number,
        enrollment,
        authority,
        issuedBy: issuedBy ?? undefined,
        issuedAt,
        certStatus: 'issued',
        learnerName: enrollment.learnerName || enrollment.learner?.name || '',
        courseTitle: course.cardTitle,
        cohortName: cohort.cardTitle,
        creditHours: course.creditHours ?? undefined,
        finalLetter: letter ?? undefined,
      }),
      realm,
    } as any)) as Certificate;

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: CertificationAuthority,
    }).execute({
      cardId: authority.id,
      patch: { attributes: { lastSequence: sequence } },
    });

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: Enrollment,
    }).execute({
      cardId: enrollment.id,
      patch: {
        attributes: {
          enrollmentStatus: 'completed',
          completedAt: enrollment.completedAt
            ? undefined
            : issuedAt.toISOString(),
        },
        relationships: { certificate: { links: { self: certificate.id } } },
      },
    });

    let forced = unmet.length
      ? ` (forced: ${unmet.map((c) => c.rule).join(', ')} unmet)`
      : '';
    return new IssueCertificateResult({
      certificate,
      message: `${number} issued to ${certificate.learnerName}${letter ? ` · final ${letter}` : ''}${forced}.`,
    });
  }
}
