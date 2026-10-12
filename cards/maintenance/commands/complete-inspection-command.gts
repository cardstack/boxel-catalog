import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { loaded } from '../utils/loaded';
import { displayTitle } from '../utils/display';
import { WorkOrder } from '../work-order';
import { InspectionFindingField } from '@cardstack/catalog/cards/audit/inspection-finding-field';
import { checklistStats } from '../utils/maintenance';

export class CompleteInspectionInput extends CardDef {
  @field workOrder = linksTo(() => WorkOrder, { searchable: true });
  @field completedByName = contains(StringField);
  @field completedAt = contains(DateTimeField);
  @field newFindings = containsMany(InspectionFindingField, {
    description:
      'Findings raised by this inspection (each failed/measured checklist item that needs follow-up becomes one of these, stamped by the caller before invoking this command).',
  });
}

export class CompleteInspectionResult extends CardDef {
  @field findingCount = contains(NumberField);
  @field message = contains(StringField);
}

/**
 * An Inspection is a Work Order with `kind = inspection` — this is its
 * Complete Work Order, specialised to also attach the findings the
 * inspector raised. Shares the checklist gate with Complete Work Order
 * (same `checklistStats`) but does not accept an override: an inspection
 * with unresolved required items is not done.
 */
export default class CompleteInspectionCommand extends Command<
  typeof CompleteInspectionInput,
  typeof CompleteInspectionResult
> {
  static actionVerb = 'Complete';
  static displayName = 'Complete Inspection';

  async getInputType() {
    return CompleteInspectionInput;
  }

  protected async run(
    input: CompleteInspectionInput,
  ): Promise<CompleteInspectionResult> {
    let workOrder = await loaded(this.commandContext, input.workOrder);
    if (!workOrder) {
      throw new Error('workOrder is required');
    }
    if (workOrder.kind !== 'inspection') {
      throw new Error(
        `${displayTitle(workOrder, 'This work order')} is kind="${workOrder.kind}" — Complete Inspection only completes inspection work orders.`,
      );
    }
    if (workOrder.status === 'completed' || workOrder.status === 'closed') {
      throw new Error(
        `${displayTitle(workOrder, 'This inspection')} is already ${workOrder.status}.`,
      );
    }

    let stats = checklistStats(workOrder.checklist?.items ?? []);
    if (!stats.isComplete) {
      throw new Error(
        `Refused: ${stats.requiredRemaining} required checklist item(s) unresolved — an inspection cannot complete with open items.`,
      );
    }

    let findings = (input.newFindings ?? []).filter(Boolean);
    workOrder.findings = [...(workOrder.findings ?? []), ...findings];

    let completedAt = input.completedAt
      ? new Date(input.completedAt)
      : new Date();
    workOrder.status = 'completed';
    workOrder.completedAt = completedAt;

    await new SaveCardCommand(this.commandContext).execute({
      card: workOrder,
    } as any);

    return new CompleteInspectionResult({
      findingCount: findings.length,
      message: `${displayTitle(workOrder, 'Inspection')} completed by ${input.completedByName ?? 'unknown'} with ${findings.length} finding(s).`,
    });
  }
}
