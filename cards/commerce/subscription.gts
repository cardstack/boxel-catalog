import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import DateField from '@cardstack/base/date';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import enumField from '@cardstack/base/enum';
import RefreshIcon from '@cardstack/boxel-icons/refresh';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { Contract } from '@cardstack/catalog/cards/legal/contract';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { hasNumber } from '@cardstack/catalog/cards/crm/utils';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';

const BillingCycleField = enumField(StringField, {
  options: ['monthly', 'yearly'],
  displayName: 'Billing Cycle',
});

const SubscriptionStatusField = enumField(StringField, {
  options: ['trial', 'active', 'paused', 'canceled'],
  displayName: 'Subscription Status',
});

const STATUS_HUE: Record<string, Hue> = {
  trial: 'blue',
  active: 'green',
  paused: 'amber',
  canceled: 'red',
};

function statusHue(status: string | null | undefined): Hue {
  return (status && STATUS_HUE[status]) || 'slate';
}

export class Subscription extends CardDef {
  static displayName = 'Subscription';
  static icon = RefreshIcon;

  @field account = linksTo(Account);
  @field planName = contains(StringField);
  @field price = contains(AmountWithCurrency);
  @field billingCycle = contains(BillingCycleField);
  @field startDate = contains(DateField);
  @field status = contains(SubscriptionStatusField);
  // Written whenever status becomes canceled. Without it a cancellation is
  // undated, and any history recomputed from these records silently rewrites
  // itself every time a customer churns.
  @field canceledAt = contains(DateField);
  // What this subscription is sold under, when there is a signed agreement.
  @field contract = linksTo(() => Contract);

  @field renewalDate = contains(DateField, {
    computeVia: function (this: Subscription) {
      if (!this.startDate) return undefined;
      if (!['trial', 'active'].includes(this.status ?? '')) return undefined;
      let start = new Date(this.startDate);
      let months = this.billingCycle === 'yearly' ? 12 : 1;
      // Each cycle is counted from the start date and clamped to the target
      // month's last day, so Jan 31 renews on Feb 28 and then Mar 31.
      let anniversary = (n: number) => {
        let target = new Date(
          start.getFullYear(),
          start.getMonth() + n * months,
          1,
        );
        let lastDay = new Date(
          target.getFullYear(),
          target.getMonth() + 1,
          0,
        ).getDate();
        target.setDate(Math.min(start.getDate(), lastDay));
        return target;
      };
      let now = new Date();
      let n = 1;
      let next = anniversary(n);
      while (next <= now) next = anniversary(++n);
      return next;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Subscription) {
      return this.planName?.trim()?.length
        ? this.planName
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static embedded = class Embedded extends Component<typeof Subscription> {
    <template>
      <div class='subscription'>
        <RefreshIcon class='icon' />
        <span class='plan'>{{@model.cardTitle}}</span>
        {{#if @model.status}}
          <StatePill
            @label={{@model.status}}
            @hue={{statusHue @model.status}}
            @dot={{true}}
          />
        {{/if}}
        <span class='price'><Money
            @amount={{@model.price.amount}}
            @code={{@model.price.currency.code}}
          />
          /
          {{@model.billingCycle}}</span>
      </div>
      <style scoped>
        .subscription {
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
        .plan {
          font-weight: 600;
        }
        .price {
          margin-left: auto;
          font-variant-numeric: tabular-nums;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Subscription> {
    <template>
      <span class='subscription-atom'>
        <RefreshIcon class='sa-icon' />
        <span class='sa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .subscription-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .sa-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .sa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Subscription> {
    get hasPrice() {
      return hasNumber(this.args.model?.price?.amount);
    }
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <RefreshIcon class='doc-icon' />
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.status}}
            <StatePill
              class='status'
              @label={{@model.status}}
              @hue={{statusHue @model.status}}
            />
          {{/if}}
        </div>
        <div class='fmt strip'>
          <RefreshIcon class='doc-icon' />
          <div class='info'>
            <span class='name'>{{@model.cardTitle}}</span>
            {{#if @model.status}}
              <StatePill
                class='status'
                @label={{@model.status}}
                @hue={{statusHue @model.status}}
              />
            {{/if}}
          </div>
          <span class='figure'>{{#if this.hasPrice}}<Money
                @amount={{@model.price.amount}}
                @code={{@model.price.currency.code}}
              />{{#if @model.billingCycle}}
                /
                {{@model.billingCycle}}{{/if}}{{else}}—{{/if}}</span>
        </div>
        <div class='fmt tile'>
          <div class='row'>
            <RefreshIcon class='doc-icon' />
            {{#if @model.status}}
              <StatePill
                class='status'
                @label={{@model.status}}
                @hue={{statusHue @model.status}}
              />
            {{/if}}
          </div>
          <span class='name'>{{@model.cardTitle}}</span>
          <span class='figure figure-lg'>{{#if this.hasPrice}}<Money
                @amount={{@model.price.amount}}
                @code={{@model.price.currency.code}}
              />{{#if @model.billingCycle}}
                /
                {{@model.billingCycle}}{{/if}}{{else}}—{{/if}}</span>
          {{#if @model.startDate}}
            <span class='meta'>Since <@fields.startDate /></span>
          {{/if}}
        </div>
        <div class='fmt card'>
          <div class='col'>
            <div class='row'>
              <RefreshIcon class='doc-icon' />
              <span class='name name-lg'>{{@model.cardTitle}}</span>
              {{#if @model.status}}
                <StatePill
                  class='status'
                  @label={{@model.status}}
                  @hue={{statusHue @model.status}}
                />
              {{/if}}
            </div>
            {{#if @model.account.name}}
              <span class='meta'>{{@model.account.name}}</span>
            {{/if}}
            {{#if @model.startDate}}
              <span class='meta'>Since <@fields.startDate /></span>
            {{/if}}
            {{#if @model.renewalDate}}
              <span class='meta'>Renews <@fields.renewalDate /></span>
            {{/if}}
          </div>
          <span class='figure figure-lg'>{{#if this.hasPrice}}<Money
                @amount={{@model.price.amount}}
                @code={{@model.price.currency.code}}
              />{{#if @model.billingCycle}}
                /
                {{@model.billingCycle}}{{/if}}{{else}}—{{/if}}</span>
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
        .name {
          font-weight: 600;
          font-size: 0.8125rem;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .name-lg {
          font-size: 0.9375rem;
        }
        .figure {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          font-size: 0.875rem;
          white-space: nowrap;
        }
        .figure-lg {
          font-size: 1.125rem;
        }
        .meta {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .status {
          flex-shrink: 0;
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
          .strip .status {
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
          .tile .row {
            width: 100%;
            justify-content: space-between;
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

  static isolated = class Isolated extends Component<typeof Subscription> {
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [];
      if (m?.startDate) rows.push({ key: 'Started', value: 'startDate' });
      if (m?.renewalDate) rows.push({ key: 'Renews', value: 'renewalDate' });
      if (m?.account) rows.push({ key: 'Account', value: 'account' });
      return rows;
    }
    <template>
      <article class='sub-page'>
        <header class='doc-head'>
          <div>
            <p class='doc-kind'>Subscription</p>
            <h1>{{@model.cardTitle}}</h1>
          </div>
          {{#if @model.status}}
            <StatePill
              class='status'
              @label={{@model.status}}
              @hue={{statusHue @model.status}}
              @dot={{true}}
            />
          {{/if}}
        </header>

        <section class='price-hero'>
          <Money
            class='ph-amount'
            @amount={{@model.price.amount}}
            @code={{@model.price.currency.code}}
          />
          {{#if @model.billingCycle}}
            <span class='ph-cycle'>/ {{@model.billingCycle}}</span>
          {{/if}}
        </section>

        {{#if this.facts.length}}
          <section class='facts-panel'>
            <KeyValue class='facts' @items={{this.facts}}>
              <:value as |row|>
                {{#if (eq row.value 'startDate')}}
                  <@fields.startDate />
                {{else if (eq row.value 'renewalDate')}}
                  <@fields.renewalDate />
                {{else}}
                  <div class='cust'><@fields.account @format='embedded' /></div>
                {{/if}}
              </:value>
            </KeyValue>
          </section>
        {{/if}}
      </article>
      <style scoped>
        /* A linked card sizes to its content. The card container's base
           height: 100% would otherwise fill a stretched grid panel and spill
           past the heading above it. */
        .sub-page :deep(.field-component-card.embedded-format) {
          height: auto;
        }
        .sub-page {
          max-width: 40rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
        }
        .doc-head {
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 1rem;
          border-bottom: 0.125rem solid var(--foreground);
          padding-bottom: 1rem;
        }
        .doc-kind {
          margin: 0 0 0.125rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        h1 {
          margin: 0;
          font-size: 1.75rem;
          line-height: 1.1;
        }
        .status {
          flex-shrink: 0;
          margin-bottom: 0.25rem;
        }
        .price-hero {
          display: flex;
          align-items: baseline;
          justify-content: center;
          gap: 0.5rem;
          padding: 2rem 1.5rem;
          background-color: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          box-shadow: var(--shadow-xs);
        }
        .ph-amount {
          font-size: 2.5rem;
          font-weight: 700;
          line-height: 1;
          font-variant-numeric: tabular-nums;
          font-family: var(--boxel-heading-font-family);
        }
        .ph-cycle {
          font-size: 1rem;
          color: var(--muted-foreground);
        }
        .facts-panel {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: 1rem 1.25rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }
        /* Pret UI KeyValue at the panel's text size and column gap */
        .facts {
          --text-ui: 0.875rem;
          --text-ui-md: 0.875rem;
          --space-6: 1.25rem;
        }
        .cust {
          flex: 1;
          min-width: 0;
        }
        .cust :deep(.account) {
          padding: 0;
        }
      </style>
    </template>
  };
}
