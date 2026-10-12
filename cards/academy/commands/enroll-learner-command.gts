import {
  CardDef,
  StringField,
  contains,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import { Command, identifyCard } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';

import { Cohort } from '../cohort';
import { Learner } from '../learner';
import { Enrollment } from '../enrollment';

export class EnrollLearnerInput extends CardDef {
  @field cohort = linksTo(() => Cohort, { searchable: true });
  @field learner = linksTo(() => Learner, { searchable: true });
  @field paymentRef = contains(StringField);
  /** The caller's already-loaded enrolments for this cohort (seat count + duplicate check). */
  @field existingEnrollments = linksToMany(() => Enrollment);
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
    let { cohort, learner, paymentRef, realm } = input;
    if (!cohort?.id) throw new Error('A cohort is required');
    if (!learner?.id) throw new Error('A learner is required');
    if (!realm) throw new Error('A realm is required');
    cohort = (await new GetCardCommand(this.commandContext).execute({
      cardId: cohort.id,
    })) as Cohort;

    if (cohort.status === 'closed') {
      throw new Error(`${cohort.cardTitle} is closed — no new enrolments`);
    }

    // Prefer the caller's loaded enrolments; fall back to a realm search
    // (which only sees the user's own realms).
    let pool: Enrollment[];
    if (input.existingEnrollments?.length) {
      pool = (input.existingEnrollments as Enrollment[]).filter(
        (e) => e?.cohort?.id === cohort!.id,
      );
    } else {
      let ref = identifyCard(Enrollment);
      let existing = ref
        ? ((await new SearchCardsByQueryCommand(this.commandContext).execute({
            query: { filter: { on: ref, eq: { 'cohort.id': cohort.id } } },
          } as any)) as any)
        : undefined;
      pool = (existing?.instances ?? []) as Enrollment[];
    }
    let seats = pool.filter((e) => e.enrollmentStatus !== 'withdrawn');
    if (seats.some((e) => e.learner?.id === learner!.id)) {
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
        paymentRef: paymentRef ?? undefined,
      }),
      realm,
    } as any)) as Enrollment;

    return new EnrollLearnerResult({
      enrollment,
      message: `${learner.name ?? 'Learner'} enrolled in ${cohort.cardTitle} (${seats.length + 1}${cohort.capacity ? `/${cohort.capacity}` : ''} seats).`,
    });
  }
}
