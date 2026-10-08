import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import { Command } from '@cardstack/runtime-common';
import { displayTitle } from '@cardstack/catalog/cards/service-desk/record-helpers';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Workflow } from '@cardstack/catalog/cards/service-desk/workflow';
import AssignOwnerCommand from '@cardstack/catalog/cards/service-desk/commands/assign-owner-command';
import RunWorkflowCommand from '@cardstack/catalog/cards/service-desk/commands/run-workflow-command';
import ArchiveRecordCommand from '@cardstack/catalog/fields/record-status/commands/archive-record';

export const BATCH_OPERATIONS = [
  'assign-owner',
  'run-workflow',
  'archive',
] as const;

export class BatchTransformInput extends CardDef {
  @field cards = linksToMany(CardDef, {
    description:
      'The selection, CALLER-loaded (commands cannot search the realm).',
  });
  @field operation = contains(StringField, {
    description: 'assign-owner | run-workflow | archive',
  });
  @field owner = linksTo(() => Employee, {
    description: 'For assign-owner. Omit with strategy=round-robin.',
  });
  @field strategy = contains(StringField);
  @field candidates = linksToMany(() => Employee);
  @field workflow = linksTo(() => Workflow, {
    description: 'For run-workflow.',
  });
  @field toStateKey = contains(StringField);
  @field note = contains(StringField);
  @field actorName = contains(StringField);
}

export class BatchTransformResult extends CardDef {
  @field okCount = contains(StringField);
  @field refusedCount = contains(StringField);
  @field results = containsMany(StringField, {
    description:
      'One line per item: "ok <title>: …" or "refused <title>: <the rule>".',
  });
}

/**
 * Bulk operations WITHOUT a second writer: every item goes through the same
 * single-writer command the one-at-a-time path uses (Assign Owner,
 * Run Workflow, Archive Record) — so a batch can never do something the
 * individual action could not.
 *
 * PER-ITEM RESULTS, always: a refused item (a terminal case under archive, a
 * guarded transition) is REPORTED with its rule, never silently skipped, and
 * one refusal does not stop the rest. The board's multi-select feeds this.
 */
export default class BatchTransformCommand extends Command<
  typeof BatchTransformInput,
  typeof BatchTransformResult
> {
  static actionVerb = 'Apply';
  static displayName = 'Batch Transform';

  async getInputType() {
    return BatchTransformInput;
  }

  protected async run(
    input: BatchTransformInput,
  ): Promise<BatchTransformResult> {
    let cards = (input.cards ?? []).filter(Boolean);
    if (!cards.length) {
      throw new Error('cards is required — pass the loaded selection');
    }
    let op = input.operation;
    if (!op || !BATCH_OPERATIONS.includes(op as any)) {
      throw new Error(
        `operation must be one of: ${BATCH_OPERATIONS.join(', ')}`,
      );
    }
    if (op === 'run-workflow' && (!input.workflow || !input.toStateKey)) {
      throw new Error('run-workflow needs workflow and toStateKey');
    }

    let results: string[] = [];
    let ok = 0;
    let refused = 0;
    for (let card of cards) {
      let label = displayTitle(card, card.id ?? 'untitled');
      try {
        if (op === 'assign-owner') {
          await new AssignOwnerCommand(this.commandContext).execute({
            card,
            owner: input.owner,
            strategy: input.strategy,
            candidates: input.candidates,
          } as any);
        } else if (op === 'run-workflow') {
          await new RunWorkflowCommand(this.commandContext).execute({
            card,
            workflow: input.workflow,
            toStateKey: input.toStateKey,
            note: input.note,
            actorName: input.actorName,
          } as any);
        } else {
          await new ArchiveRecordCommand(this.commandContext).execute({
            card,
          } as any);
        }
        ok++;
        results.push(`ok ${label}`);
      } catch (e: any) {
        refused++;
        results.push(`refused ${label}: ${e?.message ?? e}`);
      }
    }

    return new BatchTransformResult({
      okCount: String(ok),
      refusedCount: String(refused),
      results,
    });
  }
}
