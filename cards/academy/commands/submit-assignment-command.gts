import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import MarkdownField from '@cardstack/base/markdown';
import { Command, identifyCard } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';

import { Enrollment } from '../enrollment';
import { Assignment } from '../assignment';
import { Submission } from '../submission';
import { latePenalty, hardCloseAt } from '../late-policy-field';

export class SubmitAssignmentInput extends CardDef {
  @field enrollment = linksTo(() => Enrollment, { searchable: true });
  @field assignment = linksTo(() => Assignment, { searchable: true });
  @field text = contains(MarkdownField);
  /** The caller's already-loaded submissions for this enrolment (versioning + supersede). */
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
    let { enrollment, assignment, text, realm } = input;
    if (!enrollment?.id) throw new Error('An enrollment is required');
    if (!assignment?.id) throw new Error('An assignment is required');
    if (!realm) throw new Error('A realm is required');
    enrollment = (await new GetCardCommand(this.commandContext).execute({
      cardId: enrollment.id,
    })) as Enrollment;
    assignment = (await new GetCardCommand(this.commandContext).execute({
      cardId: assignment.id,
    })) as Assignment;

    if (enrollment.enrollmentStatus !== 'active') {
      throw new Error(
        `${enrollment.learnerName || 'This learner'} is ${enrollment.enrollmentStatus ?? 'not active'} in this cohort — only active enrolments can submit`,
      );
    }

    let now = new Date();
    let policy = (enrollment.cohort as any)?.course?.latePolicy;
    let dueAt = assignment.dueWindow?.dueAt;
    let closeAt =
      assignment.dueWindow?.hardCloseAt ?? hardCloseAt(policy, dueAt);
    if (closeAt && now.getTime() > new Date(closeAt).getTime()) {
      throw new Error(
        `The drop box for ${assignment.cardTitle} closed on ${new Date(closeAt).toLocaleDateString()}`,
      );
    }
    if (
      assignment.dueWindow?.opensAt &&
      now.getTime() < new Date(assignment.dueWindow.opensAt).getTime()
    ) {
      throw new Error(`${assignment.cardTitle} is not open yet`);
    }

    let prior: Submission[];
    if (input.priorSubmissions?.length) {
      prior = (input.priorSubmissions as Submission[]).filter(
        (s) => s?.enrollment?.id === enrollment!.id,
      );
    } else {
      let ref = identifyCard(Submission);
      prior = ref
        ? (((
            (await new SearchCardsByQueryCommand(this.commandContext).execute({
              query: {
                filter: { on: ref, eq: { 'enrollment.id': enrollment.id } },
              },
            } as any)) as any
          )?.instances ?? []) as Submission[])
        : [];
    }
    prior = prior.filter((s) => s.assignment?.id === assignment!.id);
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
        text: text ?? undefined,
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
