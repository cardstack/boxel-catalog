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

import { getCard, inputCard } from '@cardstack/catalog/utils/find-card';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import type { Asset } from '../asset';
import type { MaintenancePlan } from '../maintenance-plan';
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
    let workOrder = await inputCard<WorkOrder>(
      this.commandContext,
      input,
      'workOrder',
    );
    if (!workOrder) {
      throw new Error('workOrder is required');
    }

    // A re-run after an interrupted one finds the order already completed and
    // goes on to the plan step it may have missed.
    let alreadyDone =
      workOrder.status === 'completed' || workOrder.status === 'closed';
    if (!alreadyDone) {
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

      workOrder.status = 'completed';
      workOrder.completedAt = input.completedAt
        ? new Date(input.completedAt)
        : new Date();

      await new SaveCardCommand(this.commandContext).execute({
        card: workOrder,
      } as any);
    }
    let completedDay = toDay(workOrder.completedAt ?? new Date());

    let planId = linkedId(workOrder, 'plan');
    let plan = planId
      ? await getCard<MaintenancePlan>(this.commandContext, planId)
      : undefined;
    let planAdvanced = false;
    if (
      plan &&
      completedDay &&
      (!plan.lastCompletedAt ||
        toDay(plan.lastCompletedAt)!.getTime() < completedDay.getTime())
    ) {
      plan.lastCompletedAt = completedDay;
      let assetId = linkedId(workOrder, 'subjectAsset');
      let asset = assetId
        ? await getCard<Asset>(this.commandContext, assetId)
        : undefined;
      let meterNow = (asset as any)?.primaryMeterValue;
      if (meterNow != null) {
        plan.lastCompletedMeter = meterNow;
      }
      await new SaveCardCommand(this.commandContext).execute({
        card: plan,
      } as any);
      planAdvanced = true;
    }

    return new CompleteWorkOrderResult({
      message: `${displayTitle(workOrder, 'Work order')} completed by ${input.completedByName ?? 'unknown'}${
        planAdvanced ? ` — plan "${plan?.name}" advanced` : ''
      }.`,
    });
  }
}
