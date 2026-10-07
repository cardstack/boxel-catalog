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
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';
import { tracked } from '@glimmer/tracking';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Token } from '@cardstack/pretui/components/token';
import { Invoice } from './invoice';
import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { hasNumber } from '@cardstack/catalog/cards/crm/utils';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { ID_TOKEN_STYLE } from '@cardstack/catalog/components/pretui-helpers';

// Payment Method lives in payment-method-field.gts (Payment Terms reuses it as
// the preferred rail) and is re-exported here; defining it in this module put
// it inside the payment↔invoice cycle, which left PaymentTermsField
// unresolvable.
export { PaymentMethodField } from './payment-method-field';
import { PaymentMethodField } from './payment-method-field';

class PaymentEdit extends Component<typeof Payment> {
  @tracked activeSection = 'details';

  sections = [
    { id: 'details', label: 'Payment details' },
    { id: 'allocation', label: 'Allocation' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.payment-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='payment-edit'>
      <div class='edit-body'>
        <EditSectionNav
          @sections={{this.sections}}
          @activeId={{this.activeSection}}
          @onSelect={{this.goTo}}
          class='sect-nav'
        />
        <div class='sects'>
          <section
            class='sect details
              {{if (eq this.activeSection "details") "focused"}}'
            data-sect='details'
          >
            <h3>Payment details</h3>
            <div class='row'>
              <FieldContainer @label='Amount' @vertical={{true}}>
                <@fields.amount />
              </FieldContainer>
              <FieldContainer @label='Method' @vertical={{true}}>
                <@fields.method />
              </FieldContainer>
              <FieldContainer @label='Paid at' @vertical={{true}}>
                <@fields.paidAt />
              </FieldContainer>
            </div>
            <FieldContainer @label='Reference' @vertical={{true}}>
              <@fields.reference />
            </FieldContainer>
          </section>

          <section
            class='sect {{if (eq this.activeSection "allocation") "focused"}}'
            data-sect='allocation'
          >
            <h3>Allocation
              <span class='sect-hint'>the invoice this payment settles</span></h3>
            <FieldContainer @label='Invoice' @vertical={{true}}>
              <@fields.invoice />
            </FieldContainer>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .payment-edit {
        container-type: inline-size;
        container-name: edit;
        height: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp);
        background-color: var(--background);
        color: var(--foreground);
        /* family ink, declared ONCE */
        --pay-ink: var(--procurement-ink, var(--primary-ink));
        --pay-ink-fg: var(--procurement-ink-fg, var(--card));
      }
      .edit-body {
        display: grid;
        grid-template-columns: 9.5rem minmax(0, 1fr);
        align-items: start;
        gap: var(--boxel-sp);
      }
      .sect-nav {
        position: sticky;
        top: 0;
        --edit-section-nav-ink: var(--pay-ink);
        --edit-section-nav-ink-fg: var(--pay-ink-fg);
      }
      .sects {
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
      }
      .sect {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        padding: var(--boxel-sp);
        display: grid;
        gap: var(--boxel-sp-sm);
        transition:
          outline-color 160ms ease,
          box-shadow 160ms ease;
        outline: 0.125rem solid transparent;
        outline-offset: 0.125rem;
      }
      .sect.focused {
        outline-color: var(--pay-ink);
        box-shadow: 0 0 0 0.25rem
          color-mix(in oklch, var(--pay-ink) 12%, transparent);
      }
      .sect.details {
        border-left: 0.1875rem solid var(--pay-ink);
      }
      h3 {
        margin: 0;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
        display: flex;
        align-items: baseline;
        gap: var(--boxel-sp-xs);
        flex-wrap: wrap;
      }
      .sect-hint {
        text-transform: none;
        letter-spacing: normal;
        font-size: 0.75rem;
        font-weight: 400;
        font-style: italic;
      }
      .row {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: var(--boxel-sp-sm);
        align-items: start;
      }
      @container edit (width < 640px) {
        .row {
          grid-template-columns: 1fr;
        }
        .edit-body {
          grid-template-columns: 1fr;
        }
        .sect-nav {
          position: static;
          flex-direction: row;
          flex-wrap: wrap;
        }
        .sect-nav::before {
          display: none;
        }
      }
    </style>
  </template>
}

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
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
          font-size: 0.875rem;
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
          margin-left: auto;
          color: var(--muted-foreground);
          font-size: 0.75rem;
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
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
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
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <CreditCardIcon class='doc-icon' />
          <Money
            class='figure'
            @amount={{@model.amount.amount}}
            @code={{@model.amount.currency.code}}
          />
          {{#if @model.method}}
            <StatePill class='chip' @label={{@model.method}} />
          {{/if}}
        </div>
        <div class='fmt strip'>
          <CreditCardIcon class='doc-icon' />
          <div class='info'>
            <Money
              class='figure'
              @amount={{@model.amount.amount}}
              @code={{@model.amount.currency.code}}
            />
            {{#if @model.method}}
              <StatePill class='chip' @label={{@model.method}} />
            {{/if}}
          </div>
          {{#if @model.paidAt}}
            <span class='meta'><@fields.paidAt /></span>
          {{/if}}
        </div>
        <div class='fmt tile'>
          <CreditCardIcon class='doc-icon' />
          <Money
            class='figure figure-lg'
            @amount={{@model.amount.amount}}
            @code={{@model.amount.currency.code}}
          />
          {{#if @model.method}}
            <StatePill class='chip' @label={{@model.method}} />
          {{/if}}
          {{#if @model.paidAt}}
            <span class='meta'><@fields.paidAt /></span>
          {{/if}}
        </div>
        <div class='fmt card'>
          <div class='col'>
            <div class='row'>
              <CreditCardIcon class='doc-icon' />
              <Money
                class='figure figure-lg'
                @amount={{@model.amount.amount}}
                @code={{@model.amount.currency.code}}
              />
              {{#if @model.method}}
                <StatePill class='chip' @label={{@model.method}} />
              {{/if}}
            </div>
            {{#if @model.invoice.cardTitle}}
              <span class='meta'>Applied to {{@model.invoice.cardTitle}}</span>
            {{/if}}
            {{#if @model.reference}}
              <span class='meta'>Ref {{@model.reference}}</span>
            {{/if}}
          </div>
          {{#if @model.paidAt}}
            <span class='meta'><@fields.paidAt /></span>
          {{/if}}
        </div>
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          color: var(--foreground);
        }
        .fmt {
          display: none;
          width: 100%;
          height: 100%;
          box-sizing: border-box;
          overflow: hidden;
        }
        .doc-icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .figure {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          font-size: 0.875rem;
          white-space: nowrap;
        }
        .figure-lg {
          font-size: 1.25rem;
        }
        .chip {
          flex-shrink: 0;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .row {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          min-width: 0;
        }
        .col,
        .info {
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
          min-width: 0;
          flex: 1;
        }
        @container fitted-card (max-width: 150px) and (max-height: 169px) {
          .badge {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 0.375rem;
            padding: 0.5rem;
            text-align: center;
          }
        }
        @container fitted-card (min-width: 151px) and (max-height: 169px) {
          .strip {
            display: flex;
            align-items: center;
            gap: 0.625rem;
            padding: 0.625rem 0.75rem;
          }
          .strip .info {
            gap: 0.125rem;
          }
          .strip .chip {
            align-self: flex-start;
          }
        }
        @container fitted-card (max-width: 399px) and (min-height: 170px) {
          .tile {
            display: flex;
            flex-direction: column;
            align-items: flex-start;
            justify-content: center;
            gap: 0.375rem;
            padding: 0.875rem;
          }
        }
        @container fitted-card (min-width: 400px) and (min-height: 170px) {
          .card {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 1rem;
            padding: 1.25rem;
          }
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
      <article class='receipt-wrap'>
        <div class='receipt'>
          <header class='r-head'>
            <p class='r-label'>Payment received</p>
            <h1 class='r-amount'>{{#if (hasNumber @model.amount.amount)}}<Money
                  @amount={{@model.amount.amount}}
                  @code={{@model.amount.currency.code}}
                />{{else}}—{{/if}}</h1>
            {{#if @model.method}}
              <StatePill @label={{@model.method}} />
            {{/if}}
          </header>
          <div class='tear' aria-hidden='true'></div>
          {{#if this.rows.length}}
            <KeyValue class='r-rows' @items={{this.rows}}>
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
      <style scoped>
        /* A linked card sizes to its content. The card container's base
           height: 100% would otherwise fill a stretched grid panel and spill
           past the heading above it. */
        .receipt-wrap :deep(.field-component-card.embedded-format) {
          height: auto;
        }
        .receipt-wrap {
          padding: 2.5rem 1.5rem;
          display: flex;
          justify-content: center;
        }
        .receipt {
          width: 100%;
          max-width: 24rem;
          background-color: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          box-shadow: var(--shadow-md);
          overflow: hidden;
        }
        .r-head {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.5rem;
          padding: 2rem 1.5rem 1.5rem;
          text-align: center;
        }
        .r-label {
          margin: 0;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .r-amount {
          margin: 0;
          font-size: 2.25rem;
          line-height: 1.1;
          font-variant-numeric: tabular-nums;
          font-family: var(--boxel-heading-font-family);
        }
        .tear {
          border-top: 0.125rem dashed var(--border);
          margin: 0 1rem;
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
        /* Pret UI KeyValue at the receipt's text size and column gap, with
           the values set against the receipt's right edge. */
        .r-rows {
          --text-ui: 0.875rem;
          --text-ui-md: 0.875rem;
          --space-6: 1.25rem;
          row-gap: 0.625rem;
          padding: 1.25rem 1.5rem 1.75rem;
        }
        .r-rows :deep(dd) {
          justify-content: flex-end;
          min-width: 0;
          font-weight: 500;
        }
      </style>
    </template>
  };

  // Two-step form matching how a payment is recorded: what money arrived
  // (amount / rail / when / reference) → what it settles. No rail — two
  // sections don't need wayfinding.
  static edit = PaymentEdit;
}
