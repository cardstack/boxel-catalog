import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import enumField from '@cardstack/base/enum';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import TagIcon from '@cardstack/boxel-icons/tag';
import { Plan } from './plan';
import { Service } from './service';
import { formatMoney } from './line-item-totals';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import { StatePill } from '@cardstack/catalog/components/state-pill';
import { IsoFrame } from '../shared/compact-sheet';

// Price — a specific amount + currency + billing interval for a Plan or a
// Service. Kept separate from both so a Plan can carry monthly AND annual
// price points without duplicating the Plan itself. Links to exactly one of
// `plan`/`service` — never both, never neither; enforced at the command
// layer (Convert Quote to Invoice), not the schema, matching this realm's
// existing convention of guarding invariants in commands rather than field
// validators.

const BillingIntervalField = enumField(StringField, {
  options: ['one-time', 'monthly', 'annual'],
  displayName: 'Billing Interval',
});

export class Price extends CardDef {
  static displayName = 'Price';
  static icon = TagIcon;

  @field amount = contains(AmountWithCurrency);
  @field billingInterval = contains(BillingIntervalField);
  @field plan = linksTo(Plan);
  @field service = linksTo(Service);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Price) {
      let amt = formatMoney(this.amount?.amount, this.amount?.currency?.code);
      let subject = this.plan?.cardTitle ?? this.service?.cardTitle;
      if (!amt) return `Untitled ${this.constructor.displayName}`;
      return subject ? `${amt} — ${subject}` : amt;
    },
  });

  static atom = class Atom extends Component<typeof Price> {
    <template>
      <span class='price-atom'>
        <TagIcon class='pa-icon' />
        <span class='pa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .price-atom {
          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-2xs);
          font-size: var(--boxel-font-size-xs);
          font-weight: 600;
          color: var(--foreground);
        }
        .pa-icon {
          width: 14px;
          height: 14px;
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

  static embedded = class Embedded extends Component<typeof Price> {
    get amountDisplay() {
      return formatMoney(
        this.args.model?.amount?.amount,
        this.args.model?.amount?.currency?.code,
      );
    }
    <template>
      <div class='price-row'>
        <TagIcon class='icon' />
        <span class='figure'>{{this.amountDisplay}}</span>
        {{#if @model.billingInterval}}
          <span class='chip'>{{@model.billingInterval}}</span>
        {{/if}}
      </div>
      <style scoped>
        .price-row {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-sm);
          padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .icon {
          width: 20px;
          height: 20px;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .figure {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .chip {
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.04em;
          padding: var(--boxel-sp-6xs) var(--boxel-sp-xs);
          border-radius: 999px;
          background: var(--muted);
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Price> {
    get amountDisplay() {
      return (
        formatMoney(
          this.args.model?.amount?.amount,
          this.args.model?.amount?.currency?.code,
        ) || '—'
      );
    }
    <template>
      <RichFittedCard>
        <:avatar><TagIcon class='mark' aria-hidden='true' /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:status>{{#if @model.billingInterval}}<StatePill
              @label={{@model.billingInterval}}
            />{{/if}}</:status>
        <:subtitle>{{this.amountDisplay}}</:subtitle>
        <:metric><Metric
            @value={{this.amountDisplay}}
            @label={{@model.billingInterval}}
          /></:metric>
        <:details>
          {{#if @model.plan}}<Detail @label='Plan'><@fields.plan
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.service}}<Detail @label='Service'><@fields.service
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

  static isolated = class Isolated extends Component<typeof Price> {
    get amountDisplay() {
      return (
        formatMoney(
          this.args.model?.amount?.amount,
          this.args.model?.amount?.currency?.code,
        ) || '—'
      );
    }
    <template>
      <IsoFrame>
        <article class='price-page'>
          <header class='ph'>
            <p class='doc-kind'>Price</p>
            <h1>{{this.amountDisplay}}</h1>
            {{#if @model.billingInterval}}
              <span class='chip'>{{@model.billingInterval}}</span>
            {{/if}}
          </header>
          {{#if @model.plan}}
            <div class='subject'><@fields.plan @format='atom' /></div>
          {{/if}}
          {{#if @model.service}}
            <div class='subject'><@fields.service @format='atom' /></div>
          {{/if}}
        </article>
      </IsoFrame>
      <style scoped>
        .price-page {
          background: var(--card);
          color: var(--card-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          max-width: 32rem;
          margin: 0 auto;
          inline-size: 100%;
          padding: var(--boxel-sp-xl) var(--boxel-sp-lg);
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp);
        }
        .ph {
          display: flex;
          flex-direction: column;
          gap: var(--boxel-sp-xs);
          border-bottom: 2px solid var(--foreground);
          padding-bottom: var(--boxel-sp-lg);
        }
        .doc-kind {
          font-size: var(--boxel-font-size-2xs);
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: 0.14em;
          color: var(--muted-foreground);
        }
        h1 {
          font-size: var(--boxel-font-size-xl);
          line-height: 1.1;
          font-variant-numeric: tabular-nums;
        }
        .chip {
          align-self: flex-start;
          font-size: var(--boxel-font-size-2xs);
          font-weight: 600;
          text-transform: uppercase;
          padding: var(--boxel-sp-5xs) var(--boxel-sp-xs);
          border-radius: 999px;
          background: var(--muted);
          color: var(--muted-foreground);
        }
        .subject {
          border: 1px solid var(--border);
          border-radius: var(--radius);
        }
      </style>
    </template>
  };
}
