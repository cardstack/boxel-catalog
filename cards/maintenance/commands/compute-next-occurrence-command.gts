import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import DateTimeField from '@cardstack/base/datetime';
import { Command } from '@cardstack/runtime-common';

import { inputCard } from '@cardstack/catalog/utils/find-card';
import { MaintenancePlan, planNext } from '../maintenance-plan';

export class ComputeNextOccurrenceInput extends CardDef {
  @field plan = linksTo(() => MaintenancePlan, {
    searchable: true,
    description: 'The plan to evaluate.',
  });
  @field asOf = contains(DateTimeField, {
    description: 'Evaluate as of this instant. Defaults to now.',
  });
}

export class ComputeNextOccurrenceResult extends CardDef {
  @field dueDate = contains(DateField);
  @field dueMeter = contains(NumberField);
  @field decidedBy = contains(StringField);
  @field daysUntil = contains(NumberField);
  @field meterRemaining = contains(NumberField);
  @field isDue = contains(BooleanField);
  @field generateOn = contains(DateField);
  @field label = contains(StringField);
}

/**
 * Read-only wrapper around `planNext` (maintenance-plan.gts → utils/recurrence's
 * `nextOccurrence`) — the ONE rhythm calculation every consumer shares. Never
 * duplicates the math; just re-shapes it for a caller (a command-driven UI
 * action, an AI tool call) that wants the answer without reading the plan's
 * own computeds directly.
 *
 * Pure: never writes. `asOf` lets a caller ask "was this due last Tuesday"
 * without waiting for the wall clock.
 */
export default class ComputeNextOccurrenceCommand extends Command<
  typeof ComputeNextOccurrenceInput,
  typeof ComputeNextOccurrenceResult
> {
  static actionVerb = 'Compute';
  static displayName = 'Compute Next Occurrence';

  async getInputType() {
    return ComputeNextOccurrenceInput;
  }

  protected async run(
    input: ComputeNextOccurrenceInput,
  ): Promise<ComputeNextOccurrenceResult> {
    let plan = await inputCard<MaintenancePlan>(
      this.commandContext,
      input,
      'plan',
    );
    if (!plan) {
      throw new Error('plan is required');
    }
    let today = input.asOf ? new Date(input.asOf) : new Date();
    let n = planNext(plan, today);
    let label =
      n.decidedBy === 'none'
        ? 'No rhythm set'
        : n.isDue
          ? 'Due now'
          : n.daysUntil != null
            ? `Due in ${n.daysUntil} d`
            : n.meterRemaining != null
              ? `${n.meterRemaining} remaining`
              : 'Scheduled';
    return new ComputeNextOccurrenceResult({
      dueDate: n.dueDate,
      dueMeter: n.dueMeter,
      decidedBy: n.decidedBy,
      daysUntil: n.daysUntil,
      meterRemaining: n.meterRemaining,
      isDue: n.isDue,
      generateOn: n.generateOn,
      label,
    });
  }
}
