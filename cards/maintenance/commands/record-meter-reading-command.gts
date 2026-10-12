import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { loaded } from '../utils/loaded';
import { displayTitle } from '../utils/display';
import { Meter } from '../meter';
import { MeterReadingField } from '../meter-reading-field';

export class RecordMeterReadingInput extends CardDef {
  @field meter = linksTo(() => Meter, { searchable: true });
  @field value = contains(NumberField);
  @field readAt = contains(DateTimeField, { description: 'Defaults to now.' });
  @field readByName = contains(StringField);
  @field source = contains(StringField, {
    description: 'manual | import | sensor',
  });
  @field note = contains(StringField);
  @field isPrimary = contains(BooleanField, {
    description:
      "Stamp this meter's value onto the asset's primaryMeterValue/Unit. Defaults true.",
  });
}

export class RecordMeterReadingResult extends CardDef {
  @field message = contains(StringField);
}

/**
 * The single writer of `Meter.readings`. A cumulative meter (odometer,
 * runtime hours, cycle counter) can only go up — a lower reading is refused
 * rather than silently accepted, since meter-based Maintenance Trigger math
 * assumes monotonic values. A gauge meter (temperature, pressure) has no
 * such constraint.
 *
 * When `isPrimary` (the default), also stamps the owning Asset's
 * `primaryMeterValue`/`primaryMeterUnit` so fitted tiles can show the
 * reading without resolving the Meter link.
 */
export default class RecordMeterReadingCommand extends Command<
  typeof RecordMeterReadingInput,
  typeof RecordMeterReadingResult
> {
  static actionVerb = 'Record';
  static displayName = 'Record Meter Reading';

  async getInputType() {
    return RecordMeterReadingInput;
  }

  protected async run(
    input: RecordMeterReadingInput,
  ): Promise<RecordMeterReadingResult> {
    let meter = await loaded(this.commandContext, input.meter);
    if (!meter) {
      throw new Error('meter is required');
    }
    if (input.value == null || isNaN(input.value)) {
      throw new Error('value is required');
    }
    if (
      meter.kind === 'cumulative' &&
      meter.current != null &&
      input.value < meter.current
    ) {
      throw new Error(
        `Refused: ${displayTitle(meter, 'This meter')} is cumulative — ${input.value} is below the last reading (${meter.current}).`,
      );
    }

    let readAt = input.readAt ? new Date(input.readAt) : new Date();
    let reading = new MeterReadingField({
      value: input.value,
      unit: meter.unit,
      readAt,
      readByName: input.readByName,
      source: input.source || 'manual',
      note: input.note,
    });
    meter.readings = [...(meter.readings ?? []), reading];
    await new SaveCardCommand(this.commandContext).execute({
      card: meter,
    } as any);

    let stampedAsset = false;
    if (input.isPrimary !== false) {
      let asset = meter.asset
        ? await loaded(this.commandContext, meter.asset)
        : undefined;
      if (asset) {
        asset.primaryMeterValue = input.value;
        asset.primaryMeterUnit = meter.unit;
        await new SaveCardCommand(this.commandContext).execute({
          card: asset,
        } as any);
        stampedAsset = true;
      }
    }

    return new RecordMeterReadingResult({
      message:
        `${displayTitle(meter, 'Meter')} reading recorded: ${input.value} ${meter.unit ?? ''}${
          stampedAsset ? ' (asset primary meter updated)' : ''
        }`.trim(),
    });
  }
}
