import {
  FieldDef,
  Component,
  field,
  contains,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import QuantityField from '@cardstack/catalog/fields/quantity/quantity';
import PackageIcon from '@cardstack/boxel-icons/package';

import { formatMoneyDisplay } from '@cardstack/catalog/components/money-display';

/**
 * A spare part consumed by one job — which part, how many, at what unit
 * cost (snapshotted at use, because list prices drift), and whether it came
 * from stock (Complete Work Order decrements Inventory Stock for those).
 */
export class PartUsageField extends FieldDef {
  static displayName = 'Part Usage';
  static icon = PackageIcon;

  @field partId = contains(StringField, {
    description: 'Card id of the Spare Part.',
  });
  @field partNumber = contains(StringField);
  @field partName = contains(StringField);
  @field quantity = contains(QuantityField);
  @field unitCost = contains(AmountWithCurrency);
  @field fromStock = contains(BooleanField, {
    description:
      'Taken from stock (decrements on completion) vs bought for this job.',
  });

  @field cost = contains(NumberField, {
    computeVia: function (this: PartUsageField) {
      let q = this.quantity ?? 0;
      let u = this.unitCost?.amount;
      if (u == null) return undefined;
      return Math.round(q * u * 100) / 100;
    },
  });

  @field title = contains(StringField, {
    computeVia: function (this: PartUsageField) {
      return `${this.partNumber ?? this.partName ?? 'Part'} × ${this.quantity ?? 0}`;
    },
  });

  static embedded = class Embedded extends Component<typeof this> {
    get cost() {
      let m = this.args.model;
      return m.cost != null
        ? formatMoneyDisplay(m.cost, m.unitCost?.currency?.code)
        : undefined;
    }
    <template>
      <div class='pu'>
        <PackageIcon class='pu-icon' />
        <code class='pu-pn'>{{@model.partNumber}}</code>
        <span class='pu-name'>{{@model.partName}}</span>
        <span class='pu-qty'>× {{@model.quantity}}</span>
        {{#if @model.fromStock}}<span class='pu-stock'>from stock</span>{{/if}}
        {{#if this.cost}}<span class='pu-cost'>{{this.cost}}</span>{{/if}}
      </div>
      <style scoped>
        .pu {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          min-width: 0;
          font-size: var(--boxel-font-size-sm);
          color: var(--foreground);
        }
        .pu-icon {
          width: 0.9rem;
          height: 0.9rem;
          color: var(--muted-foreground);
        }
        .pu-pn {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
        }
        .pu-name {
          flex: 1;
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .pu-qty,
        .pu-cost {
          font-variant-numeric: tabular-nums;
        }
        .pu-stock {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='pu-atom'>{{@model.title}}</span>
      <style scoped>
        .pu-atom {
          font-size: var(--boxel-font-size-xs);
          font-family: var(--font-mono);
        }
      </style>
    </template>
  };
}

export default PartUsageField;
