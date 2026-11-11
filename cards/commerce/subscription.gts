import { eq } from '@cardstack/boxel-ui/helpers';
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
import { Avatar } from '@cardstack/pretui/components/avatar';
import { KeyValue } from '@cardstack/pretui/components/key-value';
import { Stat } from '@cardstack/pretui/components/stat';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { FitTile } from '../shared/fit-tile';
import { Account } from '../crm/account';
import { Contract } from '../legal/contract';
import { Money } from '../crm/money';
import { hasNumber } from '../crm/utils';
import { orEmpty } from './compact-parts';
import { IsoFrame } from '../shared/compact-sheet';

const BillingCycleField = enumField(StringField, {
  options: ['monthly', 'yearly'],
  displayName: 'Billing Cycle',
});

const SubscriptionStatusField = enumField(StringField, {
  options: ['trial', 'active', 'paused', 'canceled'],
  displayName: 'Subscription Status',
});

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

  static atom = class Atom extends Component<typeof Subscription> {
    <template>
      <span class='atom'>
        <Avatar @name='Subscription' @shape='square' @size={{16}} />
        <span class='name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .atom {
          font-size: 0.6875rem;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-width: 0;
          max-width: 100%;
          color: var(--foreground);
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Subscription> {
    get rows() {
      return subRows(this.args.model as Subscription);
    }
    <template>
      <article class='emb'>
        <header>
          <Avatar @name='Subscription' @shape='square' @size={{28}} />
          <div class='id'>
            <h3>{{@model.cardTitle}}</h3>
            <p>{{@model.account.cardTitle}} · {{@model.billingCycle}}</p>
          </div>
          {{#if @model.status}}<StatusChip
              @value={{@model.status}}
              @appearance='plain'
            />{{/if}}
        </header>
        <KeyValue
          @items={{this.rows}}
          @labelStyle='eyebrow'
          @divided={{true}}
        />
        {{#if @model.account}}
          <div class='linked'>
            <span class='cap'>Account</span>
            <@fields.account @format='atom' @displayContainer={{false}} />
          </div>
        {{/if}}
      </article>
      <style scoped>
        .emb {
          font-size: 0.75rem;
          line-height: 1.4;
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          display: flex;
          flex-direction: column;
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.625rem;
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h3 {
          margin: 0;
          font-size: var(--boxel-font-size-sm, 0.8125rem);
          font-weight: 600;
        }
        p {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .linked {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.375rem 0.625rem;
          border-top: 1px solid var(--border);
        }
        .cap {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          min-width: 5rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Subscription> {
    <template>
      <FitTile>
        <:avatar><Avatar
            @name='Subscription'
            @shape='square'
            @size={{32}}
          /></:avatar>
        <:title>{{@model.cardTitle}}</:title>
        <:subtitle>{{@model.account.cardTitle}}
          ·
          {{@model.billingCycle}}</:subtitle>
        <:status>{{#if @model.status}}<StatusChip
              @value={{@model.status}}
              @appearance='plain'
            />{{/if}}</:status>
        <:fact><Money
            @amount={{@model.price.amount}}
            @code={{@model.price.currency.code}}
          />
          /
          {{@model.billingCycle}}</:fact>
        <:relations>{{#if @model.account}}<@fields.account
              @format='atom'
              @displayContainer={{false}}
            />{{/if}}</:relations>
      </FitTile>
    </template>
  };

  static isolated = class Isolated extends Component<typeof Subscription> {
    get statuses() {
      let cur = this.args.model?.status;
      return ['trial', 'active', 'past_due', 'canceled'].map((label) => ({
        label,
        current: label === cur ? 'true' : undefined,
      }));
    }
    get planRows() {
      let m = this.args.model as Subscription;
      return [
        { key: 'Plan', value: m?.planName ?? '—' },
        {
          key: 'Price',
          value:
            m?.price?.amount != null
              ? `$${Number(m.price.amount).toLocaleString('en-US')}`
              : '—',
        },
        { key: 'Billing cycle', value: m?.billingCycle ?? '—' },
        { key: 'Start date', value: fmtDate(m?.startDate) || '—' },
        { key: 'Renewal date', value: fmtDate(m?.renewalDate) || '—' },
      ];
    }
    get rows() {
      return subRows(this.args.model as Subscription);
    }
    get mrr() {
      let m = this.args.model;
      let a = m?.price?.amount;
      return hasNumber(a)
        ? Math.round(
            m.billingCycle === 'yearly' ? (a as number) / 12 : (a as number),
          )
        : undefined;
    }
    <template>
      <IsoFrame>
        <article class='page'>
          <header>
            <Avatar @name='Subscription' @shape='square' @size={{32}} />
            <div class='id'>
              <h1>{{@model.cardTitle}}</h1>
              <p>{{@model.account.cardTitle}} · {{@model.billingCycle}}</p>
            </div>
            {{#if @model.status}}<StatusChip
                @value={{@model.status}}
                @appearance='plain'
              />{{/if}}
          </header>
          <div class='stats'>
            <Stat
              @label='Price'
              @tone='neutral'
              @value={{orEmpty @model.price.amount}}
              @style='currency'
              @maximumFractionDigits={{0}}
              @currency={{@model.price.currency.code}}
              @hint={{if
                (eq @model.billingCycle 'yearly')
                'per year'
                'per month'
              }}
              @roll={{false}}
            />
            <Stat
              @label='MRR'
              @tone='neutral'
              @value={{orEmpty this.mrr}}
              @style='currency'
              @maximumFractionDigits={{0}}
              @currency={{@model.price.currency.code}}
              @hint='counts toward the dashboard'
              @roll={{false}}
            />
            <Stat
              @label='Renews'
              @tone='neutral'
              @value={{fmtDate @model.renewalDate}}
              @roll={{false}}
            />
          </div>
          <div class='cols'>
            <div class='main'>
              <section>
                <h2>Status</h2>
                <div class='steps'>
                  {{#each this.statuses as |st|}}
                    <span class='step' data-current={{st.current}}><StatusChip
                        @value={{st.label}}
                        @appearance='plain'
                      /></span>
                  {{/each}}
                </div>
              </section>
              <section>
                <h2>Plan</h2>
                <KeyValue
                  @items={{this.planRows}}
                  @labelStyle='eyebrow'
                  @divided={{true}}
                  class='kv'
                />
              </section>
            </div>
            <div class='side'>
              <section>
                <h2>Linked</h2>
                <div class='linked'><span class='cap'>Account</span>
                  <@fields.account
                    @format='atom'
                    @displayContainer={{false}}
                  /></div>
                <div class='linked'><span class='cap'>Contract</span>
                  <@fields.contract
                    @format='atom'
                    @displayContainer={{false}}
                  /></div>
              </section>
              <section>
                <h2>Details</h2>
                <KeyValue
                  @items={{this.rows}}
                  @labelStyle='eyebrow'
                  @divided={{true}}
                />
              </section>
            </div>
          </div>
        </article>
      </IsoFrame>
      <style scoped>
        .stats > * {
          padding: 0.4375rem 0.625rem;
        }
        .stats > * + * {
          border-inline-start: 1px solid var(--border);
        }
        .kv {
          padding-inline: 0.625rem;
        }
        .linked .cap {
          font-family: var(--font-mono);
          font-size: 0.5625rem;
          font-weight: 600;
          letter-spacing: 0.13em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .cols {
          display: grid;
          grid-template-columns: minmax(0, 3fr) minmax(16rem, 2fr);
          align-items: stretch;
        }
        .main,
        .side {
          min-inline-size: 0;
        }
        .side {
          border-inline-start: 1px solid var(--border);
        }
        .steps {
          display: flex;
          flex-wrap: wrap;
          gap: 0.75rem;
          padding: 0.4375rem 0.625rem;
          color: var(--muted-foreground);
        }
        .step[data-current] {
          color: var(--foreground);
          font-weight: 700;
        }
        .kv {
          padding-inline: 0.625rem;
        }
        .page {
          font-size: 0.75rem;
          line-height: 1.4;
          --text-stat: 1.375rem;
          --text-ui-xs: 0.6875rem;
          --boxel-sp-xs: 0.35rem;
          --boxel-sp-lg: 0.75rem;
          --pretui-kv-label-font-size: 0.5625rem;
          --pretui-kv-label-color: var(--muted-foreground);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          overflow: hidden;
          display: flex;
          flex-direction: column;
          background: var(--card);
          color: var(--foreground);
        }
        header {
          display: flex;
          align-items: center;
          gap: 0.625rem;
          padding: 0.75rem;
          border-bottom: 1px solid var(--border);
        }
        .id {
          flex: 1;
          min-width: 0;
        }
        h1 {
          font-family: var(--font-sans);
          margin: 0;
          font-size: 1rem;
          font-weight: 700;
        }
        p {
          margin: 0;
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .stats {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(12rem, 1fr));
          border-bottom: 1px solid var(--border);
        }
        section h2 {
          margin: 0;
          padding: 0.5rem 0.75rem;
          font-size: 0.75rem;
          font-weight: 700;
          border-bottom: 1px solid var(--border);
        }
        .linked {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          padding: 0.375rem 0.75rem;
          border-bottom: 1px solid var(--border);
        }
        .cap {
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          min-width: 5rem;
        }
      </style>
    </template>
  };
}

function fmtDate(d?: Date | string | null) {
  if (!d) return '—';
  return new Date(d).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function subRows(s: Subscription) {
  let rows = [];
  if (hasNumber(s?.price?.amount))
    rows.push({
      key: 'Price',
      value:
        `${s.price.currency?.code ?? ''} ${s.price.amount.toLocaleString('en-US')} / ${s.billingCycle ?? ''}`.trim(),
    });
  if (s?.billingCycle)
    rows.push({ key: 'Billing cycle', value: s.billingCycle });
  if (s?.startDate)
    rows.push({ key: 'Start date', value: fmtDate(s.startDate) });
  if (s?.renewalDate)
    rows.push({ key: 'Renewal', value: fmtDate(s.renewalDate) });
  if (s?.status) rows.push({ key: 'Status', value: s.status });
  return rows;
}
