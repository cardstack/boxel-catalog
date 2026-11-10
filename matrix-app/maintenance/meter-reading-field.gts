import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import DateTimeField from '@cardstack/base/datetime';
import QuantityField from '@cardstack/catalog/fields/quantity/quantity';
import GaugeIcon from '@cardstack/boxel-icons/gauge';

import { ReadingSourceField } from './maintenance-vocabulary';
import { absoluteStamp } from './utils/relative-time';

/**
 * One observation of a meter — value, when, by whom, from where.
 *
 * Readings are appended, never edited: the Record Meter Reading command is
 * the single writer and refuses a cumulative reading lower than the previous
 * one. `delta` against the previous reading is computed on the Meter card
 * (which owns the ordered list), not here.
 *
 * `value` uses the catalog Quantity field (stepper UI) with `min` opened up
 * to allow negative readings — a temperature gauge can read below zero,
 * unlike a part count.
 */
export class MeterReadingField extends FieldDef {
  static displayName = 'Meter Reading';
  static icon = GaugeIcon;

  @field value = contains(QuantityField, {
    configuration: { options: { min: -Infinity } },
  });
  @field unit = contains(StringField);
  @field readAt = contains(DateTimeField);
  @field readByName = contains(StringField);
  @field source = contains(ReadingSourceField);
  @field note = contains(StringField);

  @field title = contains(StringField, {
    computeVia: function (this: MeterReadingField) {
      if (this.value == null) return 'No reading';
      return `${this.value.toLocaleString()} ${this.unit ?? ''}`.trim();
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get when() {
      return absoluteStamp(this.args.model.readAt ?? undefined);
    }
    <template>
      <div class='mr'>
        <span class='mr-value'>{{@model.title}}</span>
        <span class='mr-meta'>
          {{#if this.when}}{{this.when}}{{/if}}
          {{#if @model.readByName}}· {{@model.readByName}}{{/if}}
          {{#if @model.source}}· {{@model.source}}{{/if}}
        </span>
      </div>
      <style scoped>
        .mr {
          display: flex;
          align-items: baseline;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          flex-wrap: wrap;
        }
        .mr-value {
          font-variant-numeric: tabular-nums;
          font-weight: 600;
          color: var(--foreground);
        }
        .mr-meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='mr-atom'>{{@model.title}}</span>
      <style scoped>
        .mr-atom {
          font-variant-numeric: tabular-nums;
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };
}

export default MeterReadingField;
