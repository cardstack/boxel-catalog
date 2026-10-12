import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { loaded } from '../utils/loaded';
import { displayTitle } from '../utils/display';
import { WorkOrder } from '../work-order';
import { checklistStats } from '../utils/maintenance';
import { toDay } from '../utils/recurrence';

export class CompleteWorkOrderInput extends CardDef {
  @field workOrder = linksTo(() => WorkOrder, { searchable: true });
  @field completedByName = contains(StringField);
  @field completedAt = contains(DateTimeField, {
    description: 'Defaults to now.',
  });
  @field checklistOverrideReason = contains(StringField, {
    description:
      'Required to complete with an unresolved required checklist item.',
  });
  @field noLabourReason = contains(StringField, {
    description: 'Required to complete with zero labour entries logged.',
  });
}

export class CompleteWorkOrderResult extends CardDef {
  @field message = contains(StringField);
}

/**
 * Closes the work loop on a job: refuses to mark `completed` while a
 * required checklist item is unresolved (unless the caller gives an
 * override reason) and while no labour was logged (unless the caller gives
 * `noLabourReason`) — "complete" always means the same thing everywhere,
 * because this is the only place that writes it. `isComplete` is computed
 * by the SAME `checklistStats` the Checklist Runner UI uses, so the UI and
 * this gate can never disagree about what "done" means.
 *
 * On success: stamps `completedAt`/status, and if this work order came from
 * a Maintenance Plan, advances the plan's `lastCompletedAt` /
 * `lastCompletedMeter` so the next `nextOccurrence` call is correct.
 */
export default class CompleteWorkOrderCommand extends Command<
  typeof CompleteWorkOrderInput,
  typeof CompleteWorkOrderResult
> {
  static actionVerb = 'Complete';
  static displayName = 'Complete Work Order';

  async getInputType() {
    return CompleteWorkOrderInput;
  }

  protected async run(
    input: CompleteWorkOrderInput,
  ): Promise<CompleteWorkOrderResult> {
    let workOrder = await loaded(this.commandContext, input.workOrder);
    if (!workOrder) {
      throw new Error('workOrder is required');
    }
    if (workOrder.status === 'completed' || workOrder.status === 'closed') {
      throw new Error(
        `${displayTitle(workOrder, 'This work order')} is already ${workOrder.status}.`,
      );
    }

    let stats = checklistStats(workOrder.checklist?.items ?? []);
    if (!stats.isComplete && !input.checklistOverrideReason?.trim()) {
      throw new Error(
        `Refused: ${stats.requiredRemaining} required checklist item(s) unresolved. Resolve them or pass checklistOverrideReason.`,
      );
    }

    let hasLabour = (workOrder.labour ?? []).length > 0;
    if (!hasLabour && !input.noLabourReason?.trim()) {
      throw new Error(
        'Refused: no labour logged. Pass noLabourReason or log labour first.',
      );
    }
    if (!hasLabour) {
      workOrder.noLabourReason = input.noLabourReason;
    }

    let completedAt = input.completedAt
      ? new Date(input.completedAt)
      : new Date();
    workOrder.status = 'completed';
    workOrder.completedAt = completedAt;

    await new SaveCardCommand(this.commandContext).execute({
      card: workOrder,
    } as any);

    let plan = workOrder.plan
      ? await loaded(this.commandContext, workOrder.plan)
      : undefined;
    if (plan) {
      plan.lastCompletedAt = toDay(completedAt);
      let meterNow = (workOrder.subjectAsset as any)?.primaryMeterValue;
      if (meterNow != null) {
        plan.lastCompletedMeter = meterNow;
      }
      await new SaveCardCommand(this.commandContext).execute({
        card: plan,
      } as any);
    }

    return new CompleteWorkOrderResult({
      message: `${displayTitle(workOrder, 'Work order')} completed by ${input.completedByName ?? 'unknown'}${
        plan ? ` — plan "${plan.name}" advanced` : ''
      }.`,
    });
  }
}
