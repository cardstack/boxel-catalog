import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import CoinsIcon from '@cardstack/boxel-icons/coins';

import { MoneyDisplay } from '../money-display';

export class MoneyDisplayRow extends FieldDef {
  static displayName = 'Money Display Row';

  @field label = contains(StringField);
  @field amount = contains(NumberField);
  @field currency = contains(StringField);
  @field baseAmount = contains(NumberField);
  @field baseCurrency = contains(StringField);
  @field emphatic = contains(BooleanField);
}

class MoneyDisplayTable extends Component<typeof MoneyDisplayExample> {
  <template>
    <table class='money-table'>
      <tbody>
        {{#each @model.rows as |entry|}}
          <tr>
            <th scope='row'>{{entry.label}}</th>
            <td>
              <MoneyDisplay
                @amount={{entry.amount}}
                @currency={{entry.currency}}
                @baseAmount={{entry.baseAmount}}
                @baseCurrency={{entry.baseCurrency}}
                @emphatic={{entry.emphatic}}
              />
            </td>
          </tr>
        {{/each}}
      </tbody>
    </table>
    <style scoped>
      .money-table {
        width: 100%;
        border-collapse: collapse;
        font-size: var(--boxel-font-size-sm);
      }
      th {
        text-align: left;
        font-weight: 400;
        color: var(--muted-foreground, var(--boxel-450));
      }
      th,
      td {
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border-bottom: 1px solid var(--border, var(--boxel-200));
      }
      td {
        text-align: right;
      }
    </style>
  </template>
}

/**
 * One Money Display per precision and sign case, so the component's rules are
 * visible side by side.
 */
export class MoneyDisplayExample extends CardDef {
  static displayName = 'Money Display Example';
  static icon = CoinsIcon;

  @field rows = containsMany(MoneyDisplayRow);

  static isolated = MoneyDisplayTable;
  static embedded = MoneyDisplayTable;
}
