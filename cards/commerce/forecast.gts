import {
  CardDef,
  Component,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import DateField from '@cardstack/base/date';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import TargetIcon from '@cardstack/boxel-icons/target';
import { Territory } from '@cardstack/catalog/cards/commerce/territory';
import { formatMoney } from '@cardstack/catalog/cards/commerce/line-item-totals';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { eq } from '@cardstack/boxel-ui/helpers';

// Forecast — a rolled-up projection of expected revenue for a territory over
// a period.
//
// The projected amount is a stored snapshot, not a live computation: a
// computeVia derives only from this card's own data and can't query every
// open Opportunity. Whatever recalculates it writes `projectedAmount` and
// stamps `calculatedAt`, so a stale forecast reads as stale rather than as
// silently wrong.
export class Forecast extends CardDef {
  static displayName = 'Forecast';
  static icon = TargetIcon;

  @field territory = linksTo(Territory);
  @field period = contains(StringField);
  @field projectedAmount = contains(AmountWithCurrency);
  @field calculatedAt = contains(DateField);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Forecast) {
      let territoryName = this.territory?.name;
      return this.period?.trim()?.length
        ? territoryName
          ? `${territoryName} — ${this.period}`
          : this.period
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Forecast> {
    <template>
      <span class='forecast-atom'>
        <TargetIcon class='fa-icon' width='14' height='14' />
        <span class='fa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .forecast-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: var(--boxel-font-size-xs);
          font-weight: 500;
          color: var(--foreground);
        }
        .fa-icon {
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .fa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Forecast> {
    get amountDisplay() {
      return formatMoney(
        this.args.model?.projectedAmount?.amount,
        this.args.model?.projectedAmount?.currency?.code,
      );
    }
    <template>
      <div class='forecast-row'>
        <TargetIcon class='icon' width='20' height='20' />
        <div class='info'>
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.calculatedAt}}
            <span class='meta'>as of
              <@fields.calculatedAt /></span>
          {{/if}}
        </div>
        {{#if this.amountDisplay}}
          <span class='value'>{{this.amountDisplay}}</span>
        {{/if}}
      </div>
      <style scoped>
        .forecast-row {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.625rem 0.875rem;
          font-size: var(--boxel-font-size-sm);
        }
        .icon {
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .info {
          min-width: 0;
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 0.125rem;
        }
        .name {
          font-weight: 600;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta {
          font-size: var(--boxel-font-size-xs);
          color: var(--muted-foreground);
        }
        .value {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Forecast> {
    get amountDisplay() {
      return (
        formatMoney(
          this.args.model?.projectedAmount?.amount,
          this.args.model?.projectedAmount?.currency?.code,
        ) || '—'
      );
    }
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <TargetIcon class='doc-icon' width='20' height='20' />
          <span class='figure'>{{this.amountDisplay}}</span>
        </div>
        <div class='fmt strip'>
          <TargetIcon class='doc-icon' width='20' height='20' />
          <div class='info'>
            <span class='name'>{{@model.cardTitle}}</span>
          </div>
          <span class='figure'>{{this.amountDisplay}}</span>
        </div>
        <div class='fmt tile'>
          <TargetIcon class='doc-icon' width='20' height='20' />
          <span class='name'>{{@model.cardTitle}}</span>
          <span class='figure figure-lg'>{{this.amountDisplay}}</span>
        </div>
        <div class='fmt card'>
          <div class='col'>
            <div class='row'>
              <TargetIcon class='doc-icon' width='20' height='20' />
              <span class='name name-lg'>{{@model.cardTitle}}</span>
            </div>
            {{#if @model.calculatedAt}}
              <span class='meta'>as of
                <@fields.calculatedAt /></span>
            {{/if}}
          </div>
          <span class='figure figure-lg'>{{this.amountDisplay}}</span>
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
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .name {
          font-weight: 600;
          font-size: var(--boxel-font-size-xs);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
          max-width: 100%;
        }
        .name-lg {
          font-size: var(--boxel-font-size);
        }
        .figure {
          font-weight: 700;
          font-variant-numeric: tabular-nums;
          font-size: var(--boxel-font-size-sm);
          white-space: nowrap;
        }
        .figure-lg {
          font-size: var(--boxel-font-size-md);
        }
        .meta {
          font-size: var(--boxel-font-size-2xs);
          color: var(--muted-foreground);
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

  static isolated = class Isolated extends Component<typeof Forecast> {
    get details() {
      let m = this.args.model;
      let rows = [];
      if (m?.territory) rows.push({ key: 'Territory', value: 'territory' });
      if (m?.calculatedAt)
        rows.push({ key: 'Calculated', value: 'calculatedAt' });
      return rows;
    }
    <template>
      <article class='forecast-page'>
        <header class='fh'>
          <div>
            <p class='doc-kind'>Forecast</p>
            <h1>{{@model.cardTitle}}</h1>
          </div>
          <Money
            class='amount'
            @amount={{@model.projectedAmount.amount}}
            @code={{@model.projectedAmount.currency.code}}
          />
        </header>
        {{#if this.details.length}}
          <section class='panel'>
            <h2>Details</h2>
            <KeyValue @items={{this.details}}>
              <:value as |row|>
                {{#if (eq row.key 'Territory')}}
                  <@fields.territory @format='atom' />
                {{else}}
                  <@fields.calculatedAt />
                {{/if}}
              </:value>
            </KeyValue>
          </section>
        {{/if}}
      </article>
      <style scoped>
        .forecast-page {
          max-width: 40rem;
          margin: 0 auto;
          padding: 2rem 1.5rem;
          display: flex;
          flex-direction: column;
          gap: 1.5rem;
        }
        .fh {
          display: flex;
          align-items: flex-end;
          justify-content: space-between;
          gap: 1rem;
          border-bottom: 2px solid var(--foreground);
          padding-bottom: 1.25rem;
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
        }
        .amount {
          font-size: var(--boxel-font-size-lg);
          font-weight: 700;
          font-variant-numeric: tabular-nums;
        }
        .panel {
          border: 1px solid var(--border);
          border-radius: 0.75rem;
          padding: 1rem 1.25rem;
          background: var(--card);
          color: var(--card-foreground);
        }
        h2 {
          margin: 0 0 0.75rem;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
      </style>
    </template>
  };
}
