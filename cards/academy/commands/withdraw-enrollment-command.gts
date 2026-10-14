import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import { canTransition } from '@cardstack/catalog/fields/status/status';

import { Enrollment } from '../enrollment';
import { EnrollmentStatusField } from '../enrollment-status-field';
import { linkedCard, typedCard } from './links';
import { Learner } from '../learner';

export class WithdrawEnrollmentInput extends CardDef {
  @field enrollment = linksTo(() => Enrollment, { searchable: true });
}

export class WithdrawEnrollmentResult extends CardDef {
  @field enrollment = linksTo(() => Enrollment);
  @field message = contains(StringField);
}

/**
 * Takes a learner out of a cohort: the seat is freed and their work is kept.
 * Refuses a completed enrolment, which is final, and one already withdrawn.
 */
export default class WithdrawEnrollmentCommand extends Command<
  typeof WithdrawEnrollmentInput,
  typeof WithdrawEnrollmentResult
> {
  static actionVerb = 'Withdraw';
  static displayName = 'Withdraw Enrollment';

  async getInputType() {
    return WithdrawEnrollmentInput;
  }

  protected async run(
    input: WithdrawEnrollmentInput,
  ): Promise<WithdrawEnrollmentResult> {
    let enrollmentId = linkedId(input, 'enrollment');
    if (!enrollmentId) throw new Error('An enrollment is required');
    let ctx = this.commandContext;
    let enrollment = await typedCard(ctx, enrollmentId, Enrollment);
    let learner = await linkedCard<Learner>(ctx, enrollment, 'learner');
    let learnerName = learner?.name || enrollment.learnerName || 'This learner';

    let from = enrollment.enrollmentStatus ?? 'active';
    if (from === 'completed') {
      throw new Error(`${learnerName} has completed the cohort`);
    }
    if (!canTransition(EnrollmentStatusField, from, 'withdrawn')) {
      throw new Error(`${learnerName} is already ${from}`);
    }

    await new PatchCardInstanceCommand(ctx, {
      cardType: Enrollment,
    }).execute({
      cardId: enrollmentId,
      patch: {
        attributes: {
          enrollmentStatus: 'withdrawn',
          withdrawnAt: new Date().toISOString(),
        },
      },
    });

    return new WithdrawEnrollmentResult({
      enrollment,
      message: `${learnerName} withdrawn; their work is kept.`,
    });
  }
}
