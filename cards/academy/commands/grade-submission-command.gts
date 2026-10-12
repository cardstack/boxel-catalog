import {
  CardDef,
  FieldDef,
  StringField,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import { RichMarkdownField } from '@cardstack/base/rich-markdown';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { Submission } from '../submission';
import { Grade } from '../grade';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { latePenalty } from '../late-policy-field';
import { letterFor } from '../grade-scale-field';
import { round1 } from '../rubric-criterion-field';

/** The grader's pick per criterion, by criterion name and level label. */
export class GradePickField extends FieldDef {
  @field criterionName = contains(StringField);
  @field levelLabel = contains(StringField);
  @field comment = contains(StringField);
}

export class GradeSubmissionInput extends CardDef {
  @field submission = linksTo(() => Submission, { searchable: true });
  @field gradedBy = linksTo(() => Employee, { searchable: true });
  @field picks = containsMany(GradePickField);
  @field feedback = contains(RichMarkdownField);
  @field waiveLatePenalty = contains(BooleanField);
  @field overridePoints = contains(NumberField);
  @field returnForRevision = contains(BooleanField, {
    description: 'Send back with feedback instead of grading.',
  });
  @field realm = contains(StringField);
}

export class GradeSubmissionResult extends CardDef {
  @field grade = linksTo(() => Grade);
  @field message = contains(StringField);
}

/**
 * Turns rubric picks into a Grade and moves the submission to `graded` (or
 * `returned` when the grader asks for another version). Refuses when the
 * assignment has no rubric, when a pick names a criterion or level the
 * rubric does not have, or when a criterion is left unscored — a partial
 * rubric is not a grade. Late deduction is computed from the course policy
 * and stored on the Grade as the applied decision; `waiveLatePenalty`
 * zeroes it.
 */
export default class GradeSubmissionCommand extends Command<
  typeof GradeSubmissionInput,
  typeof GradeSubmissionResult
> {
  static actionVerb = 'Grade';
  static displayName = 'Grade Submission';

  async getInputType() {
    return GradeSubmissionInput;
  }

  protected async run(
    input: GradeSubmissionInput,
  ): Promise<GradeSubmissionResult> {
    let {
      submission,
      gradedBy,
      picks,
      feedback,
      waiveLatePenalty,
      overridePoints,
      returnForRevision,
      realm,
    } = input;
    if (!submission?.id) throw new Error('A submission is required');
    if (!realm) throw new Error('A realm is required');
    submission = (await new GetCardCommand(this.commandContext).execute({
      cardId: submission.id,
    })) as Submission;

    if (submission.submissionStatus !== 'submitted') {
      throw new Error(
        `Only submitted work can be graded — this submission is "${submission.submissionStatus ?? 'not submitted'}"`,
      );
    }

    if (returnForRevision) {
      await new PatchCardInstanceCommand(this.commandContext, {
        cardType: Submission,
      }).execute({
        cardId: submission.id,
        patch: { attributes: { submissionStatus: 'returned' } },
      });
      return new GradeSubmissionResult({
        message: `${submission.cardTitle} returned for revision.`,
      });
    }

    let assignment = submission.assignment as any;
    let rubric = assignment?.rubric;
    if (!rubric)
      throw new Error(
        `${assignment?.cardTitle ?? 'This assignment'} has no rubric — link one before grading`,
      );
    let criteria = (rubric.criteria ?? []) as any[];
    if (!criteria.length)
      throw new Error(`${rubric.cardTitle} has no criteria`);

    let scores = criteria.map((c) => {
      let pick = (picks ?? []).find(
        (p: any) =>
          p?.criterionName?.trim().toLowerCase() ===
          c.name?.trim().toLowerCase(),
      );
      if (!pick) throw new Error(`No level picked for criterion "${c.name}"`);
      let level = (c.levels ?? []).find(
        (l: any) =>
          l?.label?.trim().toLowerCase() ===
          pick.levelLabel?.trim().toLowerCase(),
      );
      if (!level) {
        throw new Error(
          `"${pick.levelLabel}" is not a level of "${c.name}" (levels: ${(c.levels ?? []).map((l: any) => l.label).join(', ')})`,
        );
      }
      return {
        criterionName: c.name,
        levelLabel: level.label,
        points: round1((level.points ?? 0) * (c.weight ?? 1)),
        maxPoints: c.maxPoints ?? 0,
        comment: pick.comment ?? undefined,
      };
    });

    let course = (submission.enrollment as any)?.cohort?.course;
    let late = latePenalty(
      course?.latePolicy,
      assignment?.dueWindow?.dueAt,
      submission.submittedAt,
    );
    let penaltyPct = waiveLatePenalty ? 0 : late.penaltyPct;
    let maxPoints =
      assignment?.effectiveMaxPoints ??
      rubric.totalPoints ??
      scores.reduce((n, s) => n + s.maxPoints, 0);
    let raw = round1(scores.reduce((n, s) => n + s.points, 0));
    let total =
      overridePoints != null
        ? overridePoints
        : round1(raw * (1 - penaltyPct / 100));
    let pct = maxPoints ? Math.round((total / maxPoints) * 100) : 0;
    let letter = letterFor(pct, course?.gradeScale);

    let grade = (await new SaveCardCommand(this.commandContext).execute({
      card: new Grade({
        submission,
        gradedBy: gradedBy ?? undefined,
        gradedAt: new Date(),
        maxPoints,
        daysLate: late.daysLate,
        penaltyPct,
        overridePoints: overridePoints ?? undefined,
        letter,
        feedback: feedback ?? undefined,
      }),
      realm,
    } as any)) as Grade;

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: Grade,
    }).execute({
      cardId: grade.id,
      patch: { attributes: { criterionScores: scores } },
    });

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: Submission,
    }).execute({
      cardId: submission.id,
      patch: {
        attributes: { submissionStatus: 'graded' },
        relationships: { grade: { links: { self: grade.id } } },
      },
    });

    let lateNote = penaltyPct
      ? ` (−${penaltyPct}% late)`
      : waiveLatePenalty && late.penaltyPct
        ? ' (late penalty waived)'
        : '';
    return new GradeSubmissionResult({
      grade,
      message: `${submission.learnerName || 'Learner'}: ${total}/${maxPoints} · ${letter ?? '—'}${lateNote}.`,
    });
  }
}
