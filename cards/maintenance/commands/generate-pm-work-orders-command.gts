import {
  CardDef,
  contains,
  containsMany,
  field,
  linksToMany,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { findCard, getCard } from '@cardstack/catalog/utils/find-card';
import { linkedId, linkedIds } from '@cardstack/catalog/utils/linked-id';
import { MaintenancePlan, planNext } from '../maintenance-plan';
import { WorkOrder } from '../work-order';
import type { Asset } from '../asset';
import { ChecklistField, ChecklistItemField } from '../checklist-field';
import {
  RecordIdentifierField,
  mintIdentifier,
} from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import { toDay, dayKey } from '../utils/recurrence';
import { cloneChecklistItems, planDueKey } from '../utils/maintenance';

export class GeneratePmWorkOrdersInput extends CardDef {
  @field plans = linksToMany(() => MaintenancePlan, {
    searchable: true,
    description: 'Active plans to evaluate.',
  });
  @field openWorkOrders = linksToMany(() => WorkOrder, {
    description:
      'Open work orders the caller already holds. Their planDueKey is checked before the realm is searched for one.',
  });
  @field horizonDays = contains(NumberField, {
    description:
      'Generate a work order when its due date falls within this many days.',
  });
  @field requestedByName = contains(StringField);
  @field identifierPattern = contains(StringField, {
    description: 'e.g. "WO-{seq4}". Defaults to WO-{seq4}.',
  });
  @field startSeq = contains(NumberField, {
    description: 'First sequence number to mint from.',
  });
  @field realm = contains(StringField, {
    description:
      "Optional target realm URL; omit to save into each plan's own realm.",
  });
}

export class GeneratePmWorkOrdersResult extends CardDef {
  @field createdCount = contains(NumberField);
  @field skippedCount = contains(NumberField);
  @field createdIds = containsMany(StringField);
  @field message = contains(StringField);
}

/**
 * The generator. Reads each plan's `nextDueAt` (via `planNext` — the SAME
 * math the plan's own computeds and the Maintenance Calendar use), and for
 * every plan whose `generateOn` has arrived within `horizonDays`, mints one
 * WorkOrder — UNLESS a work order already exists for that (plan, due day)
 * pair, checked via `planDueKey`. Re-running this command with the same
 * inputs creates nothing new: the only thing that makes a new work order is
 * a new due day.
 *
 * The checklist is copied onto the work order as fresh, unanswered items
 * (`cloneChecklistItems`) — results never flow back to the plan's template.
 */
export default class GeneratePmWorkOrdersCommand extends Command<
  typeof GeneratePmWorkOrdersInput,
  typeof GeneratePmWorkOrdersResult
> {
  static actionVerb = 'Generate';
  static displayName = 'Generate PM Work Orders';

  async getInputType() {
    return GeneratePmWorkOrdersInput;
  }

  protected async run(
    input: GeneratePmWorkOrdersInput,
  ): Promise<GeneratePmWorkOrdersResult> {
    let planIds = linkedIds(input, 'plans');
    if (!planIds.length) {
      throw new Error('plans is required (pass every active MaintenancePlan)');
    }
    let horizon = input.horizonDays ?? 14;
    let today = new Date();
    let horizonEnd = new Date(today.getTime() + horizon * 86_400_000);

    let openWorkOrders = await Promise.all(
      linkedIds(input, 'openWorkOrders').map((id) =>
        getCard<WorkOrder>(this.commandContext, id),
      ),
    );
    let existingKeys = new Set(
      openWorkOrders
        .map((wo) => wo?.planDueKey)
        .filter((k): k is string => !!k),
    );

    let pattern = input.identifierPattern?.trim() || 'WO-{seq4}';
    let seq = input.startSeq ?? 1;

    let createdIds: string[] = [];
    let skipped = 0;

    for (let planId of planIds) {
      let plan = await getCard<MaintenancePlan>(this.commandContext, planId);
      if (!plan || plan.active === false) {
        skipped++;
        continue;
      }
      let occurrence = planNext(plan, today);
      let dueDate = occurrence.dueDate;
      if (!dueDate) {
        skipped++;
        continue;
      }
      let generateOn = occurrence.generateOn ?? dueDate;
      if (toDay(generateOn)!.getTime() > toDay(horizonEnd)!.getTime()) {
        skipped++;
        continue;
      }
      let key = planDueKey(plan.id, dueDate);
      let realm = input.realm || (plan as any)[realmURL]?.href;
      if (
        existingKeys.has(key) ||
        (realm &&
          (await findCard(
            this.commandContext,
            WorkOrder,
            { planDueKey: key },
            realm,
          )))
      ) {
        skipped++;
        continue;
      }

      let assetId = linkedId(plan, 'asset');
      let asset = assetId
        ? await getCard<Asset>(this.commandContext, assetId)
        : undefined;
      let checklist = plan.checklist
        ? new ChecklistField({
            title: plan.checklist.title,
            items: cloneChecklistItems(plan.checklist.items ?? []).map(
              (i) => new ChecklistItemField(i as any),
            ),
          })
        : undefined;

      let workOrder = new WorkOrder({
        identifier: new RecordIdentifierField({
          value: mintIdentifier(pattern, seq++, today),
          pattern,
          issuedAt: today,
        }),
        subjectAsset: asset,
        plan,
        planDueKey: key,
        kind: plan.kind === 'inspection' ? 'inspection' : 'preventive',
        priority: plan.priority,
        status: 'requested',
        title: `${plan.checklist?.title ?? plan.name ?? 'Maintenance'} — ${asset?.name ?? 'Untitled asset'}`,
        requestedByName: input.requestedByName ?? 'Generate PM Work Orders',
        requestedAt: today,
        scheduledFor: dueDate,
        dueBy: dueDate,
        checklist,
      } as any);

      let saved = (await new SaveCardCommand(this.commandContext).execute({
        card: workOrder,
        realm,
      } as any)) as WorkOrder;
      createdIds.push(saved.id);
      existingKeys.add(key);
    }

    return new GeneratePmWorkOrdersResult({
      createdCount: createdIds.length,
      skippedCount: skipped,
      createdIds,
      message: `${createdIds.length} work order(s) generated, ${skipped} plan(s) skipped (not yet due or already generated).`,
    });
  }
}

// re-exported so a caller can compute the same key locally for display
export { dayKey };
