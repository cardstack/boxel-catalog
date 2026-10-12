import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { findCards, getCard } from '@cardstack/catalog/utils/find-card';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import { formatDay } from '@cardstack/catalog/fields/effective-period/effective-period-field';

import { Cohort } from '../cohort';
import { Course } from '../course';
import { Enrollment } from '../enrollment';
import { Assignment } from '../assignment';
import { Submission } from '../submission';
import { latePenalty, hardCloseAt } from '../late-policy-field';
import { byId, linkedCard, realmOf } from './links';

export class SubmitAssignmentInput extends CardDef {
  @field enrollment = linksTo(() => Enrollment, { searchable: true });
  @field assignment = linksTo(() => Assignment, { searchable: true });
  @field text = contains(MarkdownField);
  /** Submissions the caller has loaded, counted with the realm's own. */
  @field priorSubmissions = linksToMany(() => Submission);
  @field realm = contains(StringField);
}

export class SubmitAssignmentResult extends CardDef {
  @field submission = linksTo(() => Submission);
  @field message = contains(StringField);
}

/**
 * Hands work in. Creates Submission v(n+1) as `submitted`; an earlier
 * `returned` version is left as history. Refuses after the hard close (the
 * assignment's own, else the course late policy), when the enrolment is
 * not active, or when a graded version exists and the assignment does not
 * allow resubmission. Late is reported, not blocked — the penalty is the
 * grader's decision at grading time.
 */
export default class SubmitAssignmentCommand extends Command<
  typeof SubmitAssignmentInput,
  typeof SubmitAssignmentResult
> {
  static actionVerb = 'Submit';
  static displayName = 'Submit Assignment';

  async getInputType() {
    return SubmitAssignmentInput;
  }

  protected async run(
    input: SubmitAssignmentInput,
  ): Promise<SubmitAssignmentResult> {
    let enrollmentId = linkedId(input, 'enrollment');
    let assignmentId = linkedId(input, 'assignment');
    if (!enrollmentId) throw new Error('An enrollment is required');
    if (!assignmentId) throw new Error('An assignment is required');
    let enrollment = await getCard<Enrollment>(
      this.commandContext,
      enrollmentId,
    );
    let assignment = await getCard<Assignment>(
      this.commandContext,
      assignmentId,
    );
    let realm = input.realm || realmOf(enrollment);
    if (!realm) throw new Error('A realm is required');

    if (enrollment.enrollmentStatus !== 'active') {
      throw new Error(
        `${enrollment.learnerName || 'This learner'} is ${enrollment.enrollmentStatus ?? 'not active'} in this cohort — only active enrolments can submit`,
      );
    }

    let now = new Date();
    let cohort = await linkedCard<Cohort>(
      this.commandContext,
      enrollment,
      'cohort',
    );
    let course = cohort
      ? await linkedCard<Course>(this.commandContext, cohort, 'course')
      : undefined;
    let policy = course?.latePolicy;
    let dueAt = assignment.dueWindow?.dueAt;
    let closeAt =
      assignment.dueWindow?.hardCloseAt ?? hardCloseAt(policy, dueAt);
    if (closeAt && now.getTime() > new Date(closeAt).getTime()) {
      throw new Error(
        `The drop box for ${assignment.cardTitle} closed on ${formatDay(closeAt)}`,
      );
    }
    if (
      assignment.dueWindow?.opensAt &&
      now.getTime() < new Date(assignment.dueWindow.opensAt).getTime()
    ) {
      throw new Error(`${assignment.cardTitle} is not open yet`);
    }

    let prior = byId(
      await findCards<Submission>(
        this.commandContext,
        Submission,
        { 'enrollment.id': enrollmentId, 'assignment.id': assignmentId },
        realm,
      ),
      ((input.priorSubmissions ?? []) as Submission[]).filter(
        (s) =>
          s &&
          linkedId(s, 'enrollment') === enrollmentId &&
          linkedId(s, 'assignment') === assignmentId,
      ),
    );
    let graded = prior.find((s) => s.submissionStatus === 'graded');
    if (graded && !assignment.allowResubmission) {
      throw new Error(
        `${assignment.cardTitle} has already been graded and does not allow resubmission`,
      );
    }
    let version = prior.reduce((n, s) => Math.max(n, s.version ?? 0), 0) + 1;

    let submission = (await new SaveCardCommand(this.commandContext).execute({
      card: new Submission({
        enrollment,
        assignment,
        version,
        submittedAt: now,
        text: input.text ?? undefined,
        submissionStatus: 'submitted',
      }),
      realm,
    } as any)) as Submission;

    // Supersede an open earlier version so the gradebook shows one live row.
    for (let s of prior) {
      if (s.id && s.submissionStatus === 'submitted') {
        await new PatchCardInstanceCommand(this.commandContext, {
          cardType: Submission,
        }).execute({
          cardId: s.id,
          patch: { attributes: { submissionStatus: 'returned' } },
        });
      }
    }

    let late = latePenalty(policy, dueAt, now);
    let lateNote = late.daysLate
      ? ` — ${late.daysLate} day${late.daysLate === 1 ? '' : 's'} late (−${late.penaltyPct}% if applied)`
      : '';
    return new SubmitAssignmentResult({
      submission,
      message: `Submitted ${assignment.cardTitle} v${version}${lateNote}.`,
    });
  }
}
