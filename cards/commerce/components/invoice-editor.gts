import GlimmerComponent from '@glimmer/component';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { guidFor } from '@ember/object/internals';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import PlusIcon from '@cardstack/boxel-icons/plus';
import XIcon from '@cardstack/boxel-icons/x';
import { Button } from '@cardstack/pretui/components/button';
import { IconButton } from '@cardstack/pretui/components/icon-button';
import { Input } from '@cardstack/pretui/components/input';
import { Table } from '@cardstack/pretui/components/table';

import { LineItem } from '@cardstack/catalog/cards/commerce/line-item';
import {
  lineTotal,
  sumLineItems,
} from '@cardstack/catalog/cards/commerce/line-item-totals';
import { Money } from '@cardstack/catalog/cards/crm/money';

// Invoice Editor — the line items of an invoice before it is sent, as an
// editing surface: add, remove and adjust rows with a running total. It
// takes `@lineItems` and hands every change to `@onChange`; the consumer
// decides when to save.

interface InvoiceEditorSignature {
  Args: {
    lineItems?: LineItem[];
    onChange: (lineItems: LineItem[]) => void;
  };
  Element: HTMLElement;
}

function amount(value: number, code: string) {
  return new AmountWithCurrency({
    amount: value,
    currency: new CurrencyField({ code }),
  });
}

function toNumber(value: string): number {
  let n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

export default class InvoiceEditor extends GlimmerComponent<InvoiceEditorSignature> {
  captionId = `${guidFor(this)}-caption`;

  get currency(): string {
    return sumLineItems(this.args.lineItems ?? []).code ?? 'USD';
  }

  get rows() {
    return (this.args.lineItems ?? []).map((item, index) => ({
      index,
      number: index + 1,
      description: item?.description ?? '',
      quantity: String(item?.quantity ?? 0),
      unitAmount: String(item?.unitPrice?.amount ?? 0),
      total: lineTotal(item),
      code: item?.unitPrice?.currency?.code ?? this.currency,
    }));
  }

  get total() {
    return sumLineItems(this.args.lineItems ?? []).total;
  }

  updateDescription = (index: number, value: string) => {
    this.patchRow(index, { description: value });
  };

  updateQuantity = (index: number, value: string) => {
    this.patchRow(index, { quantity: toNumber(value) });
  };

  updateUnitAmount = (index: number, value: string) => {
    let code = this.args.lineItems?.[index]?.unitPrice?.currency?.code;
    this.patchRow(index, {
      unitPrice: amount(toNumber(value), code ?? this.currency),
    });
  };

  removeRow = (index: number) => {
    let items = [...(this.args.lineItems ?? [])];
    items.splice(index, 1);
    this.args.onChange(items);
  };

  addRow = () => {
    this.args.onChange([
      ...(this.args.lineItems ?? []),
      new LineItem({
        description: '',
        quantity: 1,
        unitPrice: amount(0, this.currency),
      }),
    ]);
  };

  private patchRow(
    index: number,
    patch: {
      description?: string;
      quantity?: number;
      unitPrice?: AmountWithCurrency;
    },
  ) {
    let items = [...(this.args.lineItems ?? [])];
    let current = items[index];
    let price = patch.unitPrice ?? current?.unitPrice;
    items[index] = new LineItem({
      description: patch.description ?? current?.description,
      quantity: patch.quantity ?? current?.quantity,
      unitPrice: amount(
        price?.amount ?? 0,
        price?.currency?.code ?? this.currency,
      ),
    });
    this.args.onChange(items);
  }

  <template>
    <div class='invoice-editor' ...attributes>
      <p class='caption' id={{this.captionId}}>Line items</p>
      <Table @labelledBy={{this.captionId}}>
        <:head>
          <tr>
            <th scope='col'>Description</th>
            <th scope='col' class='num'>Qty</th>
            <th scope='col' class='num'>Unit</th>
            <th scope='col' class='num'>Amount</th>
            <th scope='col'><span class='visually-hidden'>Remove</span></th>
          </tr>
        </:head>
        <:body>
          {{#each this.rows key='index' as |row|}}
            <tr>
              <td class='desc'>
                <Input
                  @value={{row.description}}
                  @onInput={{fn this.updateDescription row.index}}
                  aria-label='Line {{row.number}} description'
                />
              </td>
              <td class='num'>
                <Input
                  class='num-input'
                  @type='number'
                  @value={{row.quantity}}
                  @onInput={{fn this.updateQuantity row.index}}
                  min='0'
                  aria-label='Line {{row.number}} quantity'
                />
              </td>
              <td class='num'>
                <Input
                  class='num-input'
                  @type='number'
                  @value={{row.unitAmount}}
                  @onInput={{fn this.updateUnitAmount row.index}}
                  min='0'
                  step='0.01'
                  aria-label='Line {{row.number}} unit price'
                />
              </td>
              <td class='num amount'>
                <Money @amount={{row.total}} @code={{row.code}} />
              </td>
              <td class='action'>
                <IconButton
                  @label='Remove line {{row.number}}'
                  @variant='ghost'
                  @size='xs'
                  {{on 'click' (fn this.removeRow row.index)}}
                ><XIcon /></IconButton>
              </td>
            </tr>
          {{/each}}
        </:body>
      </Table>
      <div class='foot'>
        <Button
          @appearance='outlined'
          @size='s'
          {{on 'click' this.addRow}}
        ><PlusIcon class='btn-icon' />Add line item</Button>
        <p class='total'>
          <span class='total-label'>Total</span>
          <Money @amount={{this.total}} @code={{this.currency}} />
        </p>
      </div>
    </div>
    <style scoped>
      .invoice-editor {
        display: grid;
        gap: var(--boxel-sp-sm);
      }
      .caption {
        margin: 0;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .num {
        text-align: end;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }
      .desc {
        min-width: 12rem;
      }
      .num-input {
        width: 6rem;
        text-align: end;
      }
      .amount {
        font-weight: 600;
      }
      .action {
        width: 1%;
      }
      .foot {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-sm);
      }
      .btn-icon {
        width: 1em;
        height: 1em;
      }
      .total {
        margin: 0;
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-lg);
        font-weight: 700;
        font-variant-numeric: tabular-nums;
      }
      .total-label {
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
        color: var(--muted-foreground);
      }
      .visually-hidden {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
        white-space: nowrap;
      }
    </style>
  </template>
}
