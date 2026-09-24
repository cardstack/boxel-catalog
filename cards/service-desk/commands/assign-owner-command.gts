import {
  CardDef,
  contains,
  field,
  linksTo,
  linksToMany,
  StringField,
  getFields,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import { loaded } from '../record-helpers';
import { displayTitle } from '../record-helpers';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Team } from '@cardstack/catalog/cards/hr/team';

export class AssignOwnerInput extends CardDef {
  @field card = linksTo(CardDef, {
    searchable: true,
    description: 'Any card carrying a Record Owner field named `ownership`.',
  });
  @field owner = linksTo(() => Employee, {
    description: 'The new owner. Omit with strategy=round-robin.',
  });
  @field team = linksTo(() => Team);
  @field teamName = contains(StringField, {
    description:
      'Queue name to route to. With strategy="routed" the owner is kept and only the queue changes.',
  });
  @field strategy = contains(StringField, {
    description:
      '"assigned" (default), "claimed", "round-robin" or "escalation" — recorded as ownership provenance.',
  });
  @field candidates = linksToMany(() => Employee, {
    description:
      'For round-robin: the pool, CALLER-loaded (commands cannot search the realm). The least-recently-used candidate wins.',
  });
}

export class AssignOwnerResult extends CardDef {
  @field message = contains(StringField);
  @field ownerName = contains(StringField);
}

// Round-robin memory for THIS session: cycles through the candidate pool in
// order. Durable fairness across sessions would need a counter on a card;
// recorded as a known limit, not hidden.
let rrCursor = 0;

/**
 * THE single writer of ownership. Writes the subject's `ownership`
 * (RecordOwnerField): owner name+id, team, since, how, previousOwner — so
 * "who owns this and since when" is always answerable and reassignment always
 * leaves a trace.
 *
 * Generic: the subject is any card whose schema carries
 * `@field ownership = contains(RecordOwnerField)`. A card without one is
 * refused by name, not silently skipped.
 */
export default class AssignOwnerCommand extends Command<
  typeof AssignOwnerInput,
  typeof AssignOwnerResult
> {
  static actionVerb = 'Assign';
  static displayName = 'Assign Owner';

  async getInputType() {
    return AssignOwnerInput;
  }

  protected async run(input: AssignOwnerInput): Promise<AssignOwnerResult> {
    let card = await loaded(this.commandContext, input.card);
    if (!card) {
      throw new Error('card is required');
    }
    let ownership = (card as any).ownership;
    if (!ownership) {
      throw new Error(
        `${displayTitle(card, 'This card')} has no ownership field — add "@field ownership = contains(RecordOwnerField)" to its type before assigning.`,
      );
    }

    let strategy = input.strategy || 'assigned';
    if (strategy === 'routed') {
      // Routing moves the record between queues without touching who owns
      // it — the drag on the Queues lanes. Provenance still records the move.
      let teamName = (input.teamName ?? (input.team?.name as string))?.trim();
      if (!teamName) {
        throw new Error('routed needs a teamName (the destination queue)');
      }
      let fromQueue = (ownership.teamName as string | undefined) ?? 'Unrouted';
      if (fromQueue === teamName) {
        throw new Error(
          `${displayTitle(card, 'Record')} is already in ${teamName}`,
        );
      }
      ownership.teamName = teamName === 'Unrouted' ? undefined : teamName;
      ownership.since = new Date();
      ownership.how = 'routed';
      await new SaveCardCommand(this.commandContext).execute({ card } as any);
      return new AssignOwnerResult({
        ownerName: ownership.ownerName,
        message: `${displayTitle(card, 'Record')} routed ${fromQueue} → ${teamName}`,
      });
    }
    let owner = input.owner;
    if (!owner && strategy === 'round-robin') {
      let pool = (input.candidates ?? []).filter(Boolean);
      if (!pool.length) {
        throw new Error('round-robin needs a non-empty candidates pool');
      }
      owner = pool[rrCursor++ % pool.length]!;
    }
    if (!owner) {
      throw new Error(
        'owner is required (or pass strategy=round-robin with candidates)',
      );
    }

    let previous = ownership.ownerName as string | undefined;
    ownership.previousOwnerName = previous ?? undefined;
    ownership.ownerId = owner.id;
    ownership.ownerName = (owner.title as string) ?? owner.id;
    ownership.teamName = (input.team?.name as string) ?? ownership.teamName;
    ownership.since = new Date();
    ownership.how = strategy;
    // A card that also links its owner (Case) gets the link in the same save,
    // so the view's owner and the ownership record cannot disagree.
    if ('owner' in getFields(card)) {
      (card as any).owner = owner;
    }

    await new SaveCardCommand(this.commandContext).execute({ card } as any);

    return new AssignOwnerResult({
      ownerName: ownership.ownerName,
      message: `${displayTitle(card, 'Record')} → ${ownership.ownerName} (via ${strategy}${
        previous ? `, previously ${previous}` : ''
      })`,
    });
  }
}
