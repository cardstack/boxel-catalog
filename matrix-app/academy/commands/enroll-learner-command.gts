import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { findCards } from '@cardstack/catalog/utils/find-card';
import { linkedId } from '@cardstack/catalog/utils/linked-id';

import { Cohort } from '../cohort';
import { Learner } from '../learner';
import { Enrollment } from '../enrollment';
import { byId, realmOf, typedCard } from './links';

export class EnrollLearnerInput extends CardDef {
  @field cohort = linksTo(() => Cohort, { searchable: true });
  @field learner = linksTo(() => Learner, { searchable: true });
  @field paymentRef = contains(StringField);
  /** Enrolments the caller has loaded, counted with the realm's own. */
  @field existingEnrollments = linksToMany(() => Enrollment);
  /** Where the enrolment is saved; defaults to the cohort's realm. */
  @field realm = contains(StringField);
}

export class EnrollLearnerResult extends CardDef {
  @field enrollment = linksTo(() => Enrollment);
  @field message = contains(StringField);
}

/**
 * Gives a learner a seat. Refuses when the cohort is closed, when the
 * learner already holds a seat in it, or when every seat is taken — the
 * three ways an enrolment list goes wrong by hand. Creates the Enrollment
 * as `active`; invitations that must be accepted first are a consumer flow.
 */
export default class EnrollLearnerCommand extends Command<
  typeof EnrollLearnerInput,
  typeof EnrollLearnerResult
> {
  static actionVerb = 'Enroll';
  static displayName = 'Enroll Learner';

  async getInputType() {
    return EnrollLearnerInput;
  }

  protected async run(input: EnrollLearnerInput): Promise<EnrollLearnerResult> {
    let cohortId = linkedId(input, 'cohort');
    let learnerId = linkedId(input, 'learner');
    if (!cohortId) throw new Error('A cohort is required');
    if (!learnerId) throw new Error('A learner is required');
    let cohort = await typedCard(this.commandContext, cohortId, Cohort);
    let learner = await typedCard(this.commandContext, learnerId, Learner);
    let realm = input.realm || realmOf(cohort);
    if (!realm) throw new Error('A realm is required');

    if (cohort.status === 'closed') {
      throw new Error(`${cohort.cardTitle} is closed — no new enrolments`);
    }

    let pool = byId(
      await findCards<Enrollment>(
        this.commandContext,
        Enrollment,
        { 'cohort.id': cohortId },
        realm,
      ),
      ((input.existingEnrollments ?? []) as Enrollment[]).filter(
        (e) => e && linkedId(e, 'cohort') === cohortId,
      ),
    );
    let seats = pool.filter((e) => e.enrollmentStatus !== 'withdrawn');
    if (seats.some((e) => linkedId(e, 'learner') === learnerId)) {
      throw new Error(
        `${learner.name ?? 'This learner'} already has a seat in ${cohort.cardTitle}`,
      );
    }
    if (cohort.capacity && seats.length >= cohort.capacity) {
      throw new Error(
        `${cohort.cardTitle} is full (${seats.length}/${cohort.capacity})`,
      );
    }

    let enrollment = (await new SaveCardCommand(this.commandContext).execute({
      card: new Enrollment({
        learner,
        cohort,
        enrollmentStatus: 'active',
        enrolledAt: new Date(),
        paymentRef: input.paymentRef ?? undefined,
      }),
      realm,
    } as any)) as Enrollment;

    return new EnrollLearnerResult({
      enrollment,
      message: `${learner.name ?? 'Learner'} enrolled in ${cohort.cardTitle} (${seats.length + 1}${cohort.capacity ? `/${cohort.capacity}` : ''} seats).`,
    });
  }
}
