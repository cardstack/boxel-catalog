import { FieldDef, Component, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { hasNumber } from '@cardstack/catalog/cards/crm/utils';
import { lineTotal } from './line-item-totals';

export class LineItem extends FieldDef {
  static displayName = 'Line Item';

  @field description = contains(StringField);
  @field quantity = contains(NumberField);
  @field unitPrice = contains(AmountWithCurrency);

  static embedded = class Embedded extends Component<typeof LineItem> {
    // No unit price means no total either, so both read as a dash.
    get total() {
      let model = this.args.model;
      return hasNumber(model?.unitPrice?.amount) ? lineTotal(model) : undefined;
    }
    <template>
      <div class='line-item'>
        <span class='desc'>{{@model.description}}</span>
        <span class='qty'>{{@model.quantity}}
          ×
          <Money
            @amount={{@model.unitPrice.amount}}
            @code={{@model.unitPrice.currency.code}}
          /></span>
        <Money
          class='total'
          @amount={{this.total}}
          @code={{@model.unitPrice.currency.code}}
        />
      </div>
      <style scoped>
        .line-item {
          display: grid;
          grid-template-columns: 1fr auto auto;
          gap: 1rem;
          align-items: baseline;
          font-size: 0.875rem;
          padding: 0.25rem 0;
        }
        .qty {
          color: var(--muted-foreground);
          font-variant-numeric: tabular-nums;
        }
        .total {
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };
}
