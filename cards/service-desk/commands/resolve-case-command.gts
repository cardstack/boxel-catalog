import {
  CardDef,
  contains,
  field,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import { Command } from '@cardstack/runtime-common';
import { loaded } from '../record-helpers';
import { displayTitle } from '../record-helpers';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Case } from '../case';
import { CustomerReply } from '../customer-reply';
import { Sla } from '../sla';

export const RESOLUTION_KINDS = [
  'solved',
  'workaround',
  'wont-fix',
  'duplicate-of',
] as const;

export class ResolveCaseInput extends CardDef {
  @field case = linksTo(() => Case, { searchable: true });
  @field resolutionKind = contains(StringField, {
    description: 'solved | workaround | wont-fix | duplicate-of',
  });
  @field resolutionNote = contains(TextAreaField);
  @field replies = linksToMany(() => CustomerReply, {
    description:
      "The case's replies, CALLER-loaded (commands cannot search the realm). The gate: at least one outbound must exist.",
  });
  @field duplicateOf = linksTo(() => Case, {
    description: 'Required when resolutionKind is duplicate-of.',
  });
  @field sla = linksTo(() => Sla, {
    description:
      "The case's applied SLA, if one exists — its running clocks are stamped satisfied.",
  });
}

export class ResolveCaseResult extends CardDef {
  @field message = contains(StringField);
}

/**
 * The professional ending, enforced: a case is never resolved silently.
 *
 * THE GATE — at least one OUTBOUND Customer Reply must exist among the
 * caller-loaded `replies`, or the command refuses and its message names the
 * rule and the fixing action. `duplicate-of` additionally requires the
 * duplicate target.
 *
 * On success: the case's status moves to `resolved` (the realm's own
 * CASE_STATUSES vocabulary — no parallel ladder), `resolvedOn` is stamped,
 * the resolution note lands on the case, and every still-running timer on the
 * linked SLA is stamped `satisfiedAt` so both clocks stop.
 */
export default class ResolveCaseCommand extends Command<
  typeof ResolveCaseInput,
  typeof ResolveCaseResult
> {
  static actionVerb = 'Resolve';
  static displayName = 'Resolve Case';

  async getInputType() {
    return ResolveCaseInput;
  }

  protected async run(input: ResolveCaseInput): Promise<ResolveCaseResult> {
    let kase = await loaded(this.commandContext, input.case);
    if (!kase) {
      throw new Error('case is required');
    }
    let kind = input.resolutionKind;
    if (!kind || !RESOLUTION_KINDS.includes(kind as any)) {
      throw new Error(
        `resolutionKind must be one of: ${RESOLUTION_KINDS.join(', ')}`,
      );
    }
    if (kase.status === 'resolved' || kase.status === 'closed') {
      throw new Error(
        `${displayTitle(kase, 'This case')} is already ${kase.status}.`,
      );
    }

    let outbound = (input.replies ?? []).some(
      (r) => r?.direction === 'outbound',
    );
    if (!outbound) {
      throw new Error(
        'Refused: send the customer a reply first — resolving silently is not allowed. Record an outbound Customer Reply, then resolve.',
      );
    }
    if (kind === 'duplicate-of' && !input.duplicateOf?.id) {
      throw new Error('duplicate-of needs the case this one duplicates.');
    }

    (kase as any).status = 'resolved';
    (kase as any).resolvedOn = new Date();
    let note = [
      `Resolved as ${kind}`,
      input.duplicateOf?.cardTitle
        ? `duplicate of ${input.duplicateOf.cardTitle}`
        : null,
      input.resolutionNote || null,
    ]
      .filter(Boolean)
      .join(' — ');
    (kase as any).resolution = note;
    await new SaveCardCommand(this.commandContext).execute({
      card: kase,
    } as any);

    let stopped = 0;
    if (input.sla?.id) {
      let sla = await loaded(this.commandContext, input.sla);
      let now = new Date();
      for (let timer of (sla as any).timers ?? []) {
        if (!timer.satisfiedAt) {
          timer.satisfiedAt = now;
          stopped++;
        }
      }
      if (stopped > 0) {
        await new SaveCardCommand(this.commandContext).execute({
          card: sla,
        } as any);
      }
    }

    return new ResolveCaseResult({
      message: `${displayTitle(kase, 'Case')} resolved as ${kind}${
        stopped ? `; ${stopped} clock(s) stopped` : ''
      }.`,
    });
  }
}
