import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import DatetimeField from '@cardstack/base/datetime';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CreditCardIcon from '@cardstack/boxel-icons/credit-card';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Token } from '@cardstack/pretui/components/token';
import { Invoice } from './invoice';
import { formatMoney } from './line-item-totals';
import { fmtDate } from './compact-parts';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import { Money } from '../crm/money';
import { hasNumber } from '../crm/utils';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { ID_TOKEN_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { IsoFrame } from '../shared/compact-sheet';

// Payment Method lives in payment-method-field.gts (Payment Terms reuses it as
// the preferred rail) and is re-exported here; defining it in this module put
// it inside the payment↔invoice cycle, which left PaymentTermsField
// unresolvable.
export { PaymentMethodField } from './payment-method-field';
import { PaymentMethodField } from './payment-method-field';

export class Payment extends CardDef {
  static displayName = 'Payment';
  static icon = CreditCardIcon;

  @field invoice = linksTo(() => Invoice);
  @field amount = contains(AmountWithCurrency);
  @field method = contains(PaymentMethodField);
  @field paidAt = contains(DatetimeField);
  @field reference = contains(StringField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Payment) {
      let amt = formatMoney(this.amount?.amount, this.amount?.currency?.code);
      return amt
        ? `Payment ${amt}`
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static embedded = class Embedded extends Component<typeof Payment> {
    <template>
      <div class='payment'>
        <CreditCardIcon class='icon' />
        <span class='title'>{{@model.cardTitle}}</span>
        {{#if @model.method}}
          <StatePill class='method' @label={{@model.method}} />
        {{/if}}
        <span class='when'><@fields.paidAt /></span>
      </div>
      <style scoped>
        .payment {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .title {
          font-weight: 600;
        }
        .method {
          flex-shrink: 0;
        }
        .when {
          margin-inline-start: auto;
          color: var(--muted-foreground);
          font-size: var(--boxel-font-size-xs);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Payment> {
    <template>
      <span class='payment-atom'>
        <CreditCardIcon class='pa-icon' />
        <span class='pa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .payment-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .pa-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .pa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Payment> {
    get money() {
      let a = this.args.model?.amount;
      return formatMoney(a?.amount, a?.currency?.code);
    }
    <template>
      <RichFittedCard>
        <:avatar><CreditCardIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status>{{#if @model.method}}<StatePill
              @label={{@model.method}}
            />{{/if}}</:status>
        <:subtitle>{{#if @model.invoice.cardTitle}}Applied to
            {{@model.invoice.cardTitle}}{{/if}}</:subtitle>
        <:fact>{{#if @model.paidAt}}Paid
            {{fmtDate @model.paidAt}}{{/if}}</:fact>
        <:metric><Metric @value={{this.money}} @label='Amount' /></:metric>
        <:details>
          {{#if @model.reference}}<Detail
              @label='Reference'
              @value={{@model.reference}}
            />{{/if}}
          {{#if @model.invoice}}<Detail @label='Invoice'><@fields.invoice
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
        </:details>
      </RichFittedCard>
      <style scoped>
        .mark {
          inline-size: var(--pretui-avatar-size);
          block-size: var(--pretui-avatar-size);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Payment> {
    get rows(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.paidAt) rows.push({ key: 'Paid at', value: 'paidAt' });
      if (m?.reference) rows.push({ key: 'Reference', value: 'reference' });
      if (m?.invoice) rows.push({ key: 'Applied to', value: 'invoice' });
      return rows;
    }
    <template>
      <IsoFrame>
        <article class='receipt-wrap'>
          <div class='receipt'>
            <header class='r-head'>
              <p class='r-label'>Payment received</p>
              <h1 class='r-amount'>{{#if
                  (hasNumber @model.amount.amount)
                }}<Money
                    @amount={{@model.amount.amount}}
                    @code={{@model.amount.currency.code}}
                  />{{else}}—{{/if}}</h1>
              {{#if @model.method}}
                <StatePill @label={{@model.method}} />
              {{/if}}
            </header>
            <div class='tear' aria-hidden='true'></div>
            {{#if this.rows.length}}
              <KeyValue
                class='r-rows kv-pad'
                @items={{this.rows}}
                @valueAlign='end'
              >
                <:value as |row|>
                  {{#if (eq row.value 'paidAt')}}
                    <@fields.paidAt />
                  {{else if (eq row.value 'reference')}}
                    <Token
                      @value={{@model.reference}}
                      style={{ID_TOKEN_STYLE.sm}}
                    />
                  {{else}}
                    <@fields.invoice @format='atom' />
                  {{/if}}
                </:value>
              </KeyValue>
            {{/if}}
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .kv-pad {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
        }

        .receipt-wrap {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          padding: var(--boxel-sp-2xl) var(--boxel-sp-lg);
          display: flex;
          justify-content: center;
        }
        .receipt {
          width: 100%;
          max-width: 24rem;
          background-color: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          box-shadow: var(--shadow-md);
          overflow: hidden;
        }
        .r-head {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg) var(--boxel-sp-lg);
          text-align: center;
        }
        .r-label {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .r-amount {
          font-size: var(--boxel-font-size-2xl);
          line-height: 1.1;
          font-variant-numeric: tabular-nums;
          font-family: var(--boxel-heading-font-family);
        }
        .tear {
          border-top: 0.125rem dashed var(--border);
          margin: 0 var(--boxel-sp);
          position: relative;
        }
        .tear::before,
        .tear::after {
          content: '';
          position: absolute;
          top: -0.5rem;
          width: 1rem;
          height: 1rem;
          border-radius: 50%;
          background-color: var(--background);
          border: 1px solid var(--border);
        }
        .tear::before {
          left: -1.5rem;
        }
        .tear::after {
          right: -1.5rem;
        }
        /* Pret UI KeyValue rows, spaced for the receipt, with
           the values set against the receipt's right edge. */
        .r-rows {
          row-gap: var(--boxel-sp-xs);
          padding: var(--boxel-sp-lg) var(--boxel-sp-lg) var(--boxel-sp-xl);
          font-weight: 600;
        }
        /* shortcut: KeyValue has no value min-width knob, so a long value would widen its 1fr column; drop once KeyValue exposes one. */
        .r-rows :deep(dd) {
          min-width: 0;
        }
      </style>
    </template>
  };

  // Two-step form matching how a payment is recorded: what money arrived
  // (amount / rail / when / reference) → what it settles. No rail — two
  // sections don't need wayfinding.
}
