import {
  CardDef,
  field,
  contains,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import NumberField from '@cardstack/base/number';
import { Command, identifyCard } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';

import { Candidate } from '@cardstack/catalog/cards/hr/candidate';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { OnboardingTemplate } from '../onboarding-template';
import { CreateOnboardingChecklistCommand } from './create-onboarding-checklist-command';
import HireCandidateCommand from './hire-candidate-command';

class ApproveOfferInput extends CardDef {
  @field candidate = linksTo(() => Candidate, { searchable: true });
  @field approver = linksTo(() => Employee, { searchable: true });
  @field salary = contains(NumberField);
  @field startDate = contains(DateField);
}

class ApproveOfferResult extends CardDef {
  @field message = contains(StringField);
  @field employee = linksTo(() => Employee);
}

export class ApproveOfferCommand extends Command<
  typeof ApproveOfferInput,
  typeof ApproveOfferResult
> {
  static actionVerb = 'Approve';
  static displayName = 'Approve Job Offer';

  async getInputType() {
    return ApproveOfferInput;
  }

  protected async run(input: ApproveOfferInput): Promise<ApproveOfferResult> {
    let { candidate, salary, startDate } = input;
    if (!candidate) {
      throw new Error('candidate is required');
    }
    if (candidate.id) {
      candidate = (await new GetCardCommand(this.commandContext).execute({
        cardId: candidate.id,
      })) as Candidate;
    }
    if (candidate.status !== 'offer') {
      throw new Error(
        `Only candidates at the "offer" stage can be approved (current stage: ${
          candidate.status ?? 'none'
        })`,
      );
    }
    let offer = candidate.offer;
    if (!offer) {
      throw new Error('No offer on this candidate — extend one first');
    }
    if (offer.status !== 'extended') {
      throw new Error(
        `Only an extended offer can be approved (this one is "${offer.status ?? 'draft'}")`,
      );
    }

    // An approval chain with at least one step is a sign-off gate: hiring
    // waits until it reads 'approved'. An offer with no steps has no gate.
    let chain = offer.approvalChain;
    if (chain?.steps?.length && chain.status !== 'approved') {
      throw new Error(
        `This offer's approval chain is not fully approved yet (status: ${chain.status}). Resolve all approval steps before hiring.`,
      );
    }

    // The caller may settle the final terms; Hire Candidate reads them from
    // the accepted offer, so they go onto the offer first.
    if (salary != null) {
      offer.salary = salary;
    }
    if (startDate) {
      offer.startDate = startDate;
    }
    offer.status = 'accepted';
    offer.decisionDate = new Date();
    await new SaveCardCommand(this.commandContext).execute({ card: offer });

    let hired = await new HireCandidateCommand(this.commandContext).execute({
      candidate,
    } as any);
    let employee = hired.employee as Employee;

    // Onboarding starts from the first Onboarding Template the search finds.
    // A failure here never blocks the hire; the message says so instead.
    let onboarding = 'an onboarding checklist was started';
    try {
      let templateRef = identifyCard(OnboardingTemplate);
      let found = templateRef
        ? await new SearchCardsByQueryCommand(this.commandContext).execute({
            query: { filter: { type: templateRef } },
          } as any)
        : undefined;
      let template = (found?.instances ?? [])[0] as
        | OnboardingTemplate
        | undefined;
      if (template) {
        await new CreateOnboardingChecklistCommand(this.commandContext).execute(
          { employee, template } as any,
        );
      } else {
        onboarding =
          'no onboarding template exists, so no checklist was started';
      }
    } catch (err) {
      onboarding = `the onboarding checklist could not be started (${
        err instanceof Error ? err.message : String(err)
      })`;
    }

    return new ApproveOfferResult({
      message: `Offer approved — ${
        candidate.name ?? 'candidate'
      } is now an onboarding employee, and ${onboarding}.`,
      employee,
    });
  }
}
