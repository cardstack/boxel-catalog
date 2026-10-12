import {
  CardDef,
  contains,
  field,
  linksTo,
  realmURL,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import MarkdownField from '@cardstack/base/markdown';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { inputCard } from '@cardstack/catalog/utils/find-card';
import { WorkOrder } from '../work-order';
import { Asset } from '../asset';
import { Location } from '@cardstack/catalog/cards/events/location';
import {
  RecordIdentifierField,
  mintIdentifier,
} from '@cardstack/catalog/fields/record-identifier/record-identifier-field';
import { RecordOwnerField } from '@cardstack/catalog/fields/record-owner/record-owner-field';

export class RaiseWorkOrderInput extends CardDef {
  @field subjectAsset = linksTo(() => Asset, { searchable: true });
  @field subjectLocation = linksTo(() => Location);
  @field kind = contains(StringField, {
    description:
      'corrective | inspection | project (preventive work orders come from Generate PM Work Orders).',
  });
  @field priority = contains(StringField, { description: 'P1–P4' });
  @field title = contains(StringField);
  @field description = contains(MarkdownField);
  @field requestedByName = contains(StringField);
  @field scheduledFor = contains(DateField);
  @field dueBy = contains(DateField);
  @field teamName = contains(StringField, {
    description:
      'Initial queue — a stub on a brand-new record, not a reassignment.',
  });
  @field identifierPattern = contains(StringField);
  @field seq = contains(NumberField);
  @field realm = contains(StringField);
}

export class RaiseWorkOrderResult extends CardDef {
  @field workOrderId = contains(StringField);
  @field message = contains(StringField);
}

/**
 * Ad-hoc work order creation — the corrective / inspection / project path
 * that isn't driven by a Maintenance Plan (those come from Generate PM Work
 * Orders instead, which sets `planDueKey`). Requires either a subject asset
 * or a subject location; refuses a work order about nothing.
 */
export default class RaiseWorkOrderCommand extends Command<
  typeof RaiseWorkOrderInput,
  typeof RaiseWorkOrderResult
> {
  static actionVerb = 'Raise';
  static displayName = 'Raise Work Order';

  async getInputType() {
    return RaiseWorkOrderInput;
  }

  protected async run(
    input: RaiseWorkOrderInput,
  ): Promise<RaiseWorkOrderResult> {
    let subjectAsset = await inputCard<Asset>(
      this.commandContext,
      input,
      'subjectAsset',
    );
    let subjectLocation = await inputCard<Location>(
      this.commandContext,
      input,
      'subjectLocation',
    );
    if (!subjectAsset && !subjectLocation) {
      throw new Error(
        'Refused: a work order needs a subject asset or location.',
      );
    }
    if (!input.title?.trim()) {
      throw new Error('title is required');
    }
    let kind = input.kind || 'corrective';
    if (kind === 'preventive') {
      throw new Error(
        'Refused: preventive work orders come from Generate PM Work Orders, which sets planDueKey for idempotency.',
      );
    }
    let today = new Date();
    let pattern = input.identifierPattern?.trim() || 'WO-{seq4}';

    let workOrder = new WorkOrder({
      identifier: new RecordIdentifierField({
        value: mintIdentifier(pattern, input.seq ?? 1, today),
        pattern,
        issuedAt: today,
      }),
      subjectAsset,
      subjectLocation,
      kind,
      priority: input.priority || 'P3',
      status: 'requested',
      title: input.title,
      description: input.description,
      requestedByName: input.requestedByName ?? 'Unknown requester',
      requestedAt: today,
      scheduledFor: input.scheduledFor,
      dueBy: input.dueBy,
      ownership: input.teamName
        ? new RecordOwnerField({ teamName: input.teamName })
        : undefined,
    } as any);

    let saved = (await new SaveCardCommand(this.commandContext).execute({
      card: workOrder,
      realm:
        input.realm ||
        ((subjectAsset ?? subjectLocation) as any)?.[realmURL]?.href,
    } as any)) as WorkOrder;

    return new RaiseWorkOrderResult({
      workOrderId: saved.id,
      message: `${saved.identifier?.value ?? 'Work order'} raised: ${input.title}`,
    });
  }
}
