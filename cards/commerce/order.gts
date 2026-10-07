import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import DateField from '@cardstack/base/date';
import AddressField from '@cardstack/base/address';
import enumField from '@cardstack/base/enum';
import PackageIcon from '@cardstack/boxel-icons/package';
import PercentageField from '@cardstack/base/percentage';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { Contract } from '@cardstack/catalog/cards/legal/contract';
import { LineItem } from '@cardstack/catalog/cards/commerce/line-item';
import {
  lineTotal,
  orderTotals,
} from '@cardstack/catalog/cards/commerce/line-item-totals';
import { eq } from '@cardstack/boxel-ui/helpers';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import {
  StepList,
  type StepItem,
  type StepState,
} from '@cardstack/pretui/components/step-list';
import { Table } from '@cardstack/pretui/components/table';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';

const OrderStatusField = enumField(StringField, {
  options: ['pending', 'paid', 'shipped', 'delivered', 'canceled'],
  displayName: 'Order Status',
});

const STATUS_HUE: Record<string, Hue> = {
  pending: 'amber',
  paid: 'blue',
  shipped: 'blue',
  delivered: 'green',
  canceled: 'red',
};

function statusHue(status: string | null | undefined): Hue {
  return (status && STATUS_HUE[status]) || 'slate';
}

export class Order extends CardDef {
  static displayName = 'Order';
  static icon = PackageIcon;

  @field orderNumber = contains(StringField);
  @field account = linksTo(Account);
  @field orderDate = contains(DateField);
  @field shippingAddress = contains(AddressField);
  @field status = contains(OrderStatusField);
  @field lineItems = containsMany(LineItem);
  @field taxRate = contains(PercentageField);
  // The agreement this order is placed under, when there is one.
  @field contract = linksTo(() => Contract);

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Order) {
      return this.orderNumber?.trim()?.length
        ? `Order ${this.orderNumber}`
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static embedded = class Embedded extends Component<typeof Order> {
    get totals() {
      return orderTotals(this.args.model?.lineItems, this.args.model?.taxRate);
    }
    <template>
      <div class='order-row'>
        <PackageIcon class='icon' />
        <span class='number'>{{@model.cardTitle}}</span>
        {{#if @model.status}}
          <StatePill
            @label={{@model.status}}
            @hue={{statusHue @model.status}}
            @dot={{true}}
          />
        {{/if}}
        <Money
          class='total'
          @amount={{this.totals.total}}
          @code={{this.totals.code}}
        />
      </div>
      <style scoped>
        .order-row {
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
        .number {
          font-weight: 600;
        }
        .total {
          margin-left: auto;
          font-weight: 600;
          font-variant-numeric: tabular-nums;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof Order> {
    <template>
      <span class='order-atom'>
        <PackageIcon class='oa-icon' />
        <span class='oa-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .order-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .oa-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .oa-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Order> {
    get totals() {
      return orderTotals(this.args.model?.lineItems, this.args.model?.taxRate);
    }
    get destination() {
      let a = this.args.model?.shippingAddress;
      return [a?.city, a?.country?.name].filter(Boolean).join(', ');
    }
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <PackageIcon class='doc-icon' />
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
          <PackageIcon class='doc-icon' />
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
          <Money
            class='figure'
            @amount={{this.totals.total}}
            @code={{this.totals.code}}
          />
        </div>
        <div class='fmt tile'>
          <div class='row'>
            <PackageIcon class='doc-icon' />
            {{#if @model.status}}
              <StatePill
                class='status'
                @label={{@model.status}}
                @hue={{statusHue @model.status}}
              />
            {{/if}}
          </div>
          <span class='name'>{{@model.cardTitle}}</span>
          <Money
            class='figure figure-lg'
            @amount={{this.totals.total}}
            @code={{this.totals.code}}
          />
          {{#if this.destination}}
            <span class='meta'>To {{this.destination}}</span>
          {{/if}}
        </div>
        <div class='fmt card'>
          <div class='col'>
            <div class='row'>
              <PackageIcon class='doc-icon' />
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
            {{#if this.destination}}
              <span class='meta'>To {{this.destination}}</span>
            {{/if}}
          </div>
          <Money
            class='figure figure-lg'
            @amount={{this.totals.total}}
            @code={{this.totals.code}}
          />
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
          font-size: 1.25rem;
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

  static isolated = class Isolated extends Component<typeof Order> {
    fulfilmentSteps = ['pending', 'paid', 'shipped', 'delivered'];
    // Reaching the last stage completes the whole run; a status off the path
    // leaves every stage upcoming.
    get steps(): StepItem[] {
      let current = this.fulfilmentSteps.indexOf(this.args.model?.status ?? '');
      let last = this.fulfilmentSteps.length - 1;
      return this.fulfilmentSteps.map((label, i) => {
        let state: StepState =
          current < 0 || i > current
            ? 'upcoming'
            : i < current || current === last
              ? 'complete'
              : 'current';
        return { label, state };
      });
    }
    get isCanceled() {
      return this.args.model?.status === 'canceled';
    }
    get rows() {
      return (this.args.model?.lineItems ?? []).map((item) => ({
        description: item?.description || '—',
        quantity: item?.quantity ?? 0,
        unit: item?.unitPrice?.amount ?? undefined,
        total: lineTotal(item),
        code: item?.unitPrice?.currency?.code ?? undefined,
      }));
    }
    get number() {
      return this.args.model?.orderNumber?.trim() || 'Draft';
    }
    get totals() {
      return orderTotals(this.args.model?.lineItems, this.args.model?.taxRate);
    }
    // The totals block as KeyValue rows; each value names the figure the
    // <:value> block renders.
    get totalsFacts(): KeyValueItem[] {
      let rows: KeyValueItem[] = [];
      if (this.totals.tax) {
        rows.push({ key: 'Subtotal', value: 'subtotal' });
        rows.push({ key: `Tax (${this.args.model?.taxRate}%)`, value: 'tax' });
      }
      rows.push({ key: 'Total', value: 'total' });
      return rows;
    }
    get facts(): KeyValueItem[] {
      return [{ key: 'Ordered', value: 'orderDate' }];
    }
    <template>
      <article class='order-doc'>
        <header class='doc-head'>
          <div>
            <p class='doc-kind'>Order</p>
            <h1>{{this.number}}</h1>
          </div>
          {{#if this.isCanceled}}
            <StatePill
              class='status'
              @label='canceled'
              @hue='red'
              @dot={{true}}
            />
          {{/if}}
        </header>

        {{#unless this.isCanceled}}
          <StepList
            class='stepper'
            @steps={{this.steps}}
            @variant='track'
            @label='Order progress'
          />
        {{/unless}}

        <section class='doc-meta'>
          <div class='party'>
            <span class='label'>Account</span>
            <@fields.account @format='embedded' />
          </div>
          <KeyValue class='facts' @items={{this.facts}}>
            <:value>
              <@fields.orderDate />
            </:value>
          </KeyValue>
        </section>

        <section class='items'>
          {{#if this.rows.length}}
            <Table class='lines' @label='Line items'>
              <:head>
                <tr>
                  <th scope='col'>Item</th>
                  <th scope='col' class='t-num'>Qty</th>
                  <th scope='col' class='t-num'>Unit</th>
                  <th scope='col' class='t-num'>Amount</th>
                </tr>
              </:head>
              <:body>
                {{#each this.rows as |row|}}
                  <tr>
                    <td>{{row.description}}</td>
                    <td class='t-num'>{{row.quantity}}</td>
                    <td class='t-num'><Money
                        @amount={{row.unit}}
                        @code={{row.code}}
                      /></td>
                    <td class='t-num t-strong'><Money
                        @amount={{row.total}}
                        @code={{row.code}}
                      /></td>
                  </tr>
                {{/each}}
              </:body>
            </Table>
            <KeyValue class='totals' @items={{this.totalsFacts}}>
              <:value as |row|>
                {{#if (eq row.value 'subtotal')}}
                  <Money
                    @amount={{this.totals.subtotal}}
                    @code={{this.totals.code}}
                  />
                {{else if (eq row.value 'tax')}}
                  <Money
                    @amount={{this.totals.tax}}
                    @code={{this.totals.code}}
                  />
                {{else}}
                  <Money
                    @amount={{this.totals.total}}
                    @code={{this.totals.code}}
                  />
                {{/if}}
              </:value>
            </KeyValue>
          {{else}}
            <EmptyState
              style={{COMPACT_EMPTY_STYLE}}
              @texture={{false}}
              @title='No items yet'
            />
          {{/if}}
        </section>

        <section class='ship'>
          <span class='label'>Ship to</span>
          <@fields.shippingAddress />
        </section>
      </article>
      <style scoped>
        /* A linked card sizes to its content. The card container's base
           height: 100% would otherwise fill a stretched grid panel and spill
           past the heading above it. */
        .order-doc :deep(.field-component-card.embedded-format) {
          height: auto;
        }
        .order-doc {
          max-width: 46rem;
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
        /* Pret UI StepList, track variant. The knobs put every mark on a
           guaranteed pair with the page: the current step's number takes
           --foreground, and its bar and the complete check take ink tokens.
           The defaults (--primary-foreground with no disc behind it, a
           --primary bar) fall below 4.5:1 on one scheme or the other. */
        .stepper {
          --pretui-step-current-marker-fg: var(--foreground);
          --pretui-step-current-bar: var(--primary-ink);
          --pretui-step-complete-marker-fg: var(--success-ink);
          text-transform: capitalize;
        }
        .doc-meta {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: 1.5rem;
          flex-wrap: wrap;
        }
        .party {
          flex: 1 1 20rem;
          min-width: 15rem;
          max-width: 26rem;
        }
        .label {
          display: block;
          font-family: var(--boxel-eyebrow-font-family);
          font-size: var(--boxel-eyebrow-font-size);
          font-weight: var(--boxel-eyebrow-font-weight);
          line-height: var(--boxel-eyebrow-line-height);
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          margin-bottom: 0.375rem;
        }
        /* Pret UI KeyValue at the document's text size */
        .facts {
          --text-ui: 0.875rem;
          --text-ui-md: 0.875rem;
          --space-6: 1rem;
          font-weight: 500;
        }
        .items {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }
        .lines {
          font-size: 0.875rem;
        }
        .lines :deep(.t-num) {
          text-align: right;
          font-variant-numeric: tabular-nums;
          white-space: nowrap;
        }
        .lines :deep(.t-strong) {
          font-weight: 600;
        }
        /* Pret UI KeyValue for the totals, right-aligned under the lines with
           the grand total set heavier above a rule. */
        .totals {
          --text-ui: 0.875rem;
          --text-ui-md: 0.875rem;
          --space-6: 1.5rem;
          justify-content: end;
          font-variant-numeric: tabular-nums;
        }
        .totals :deep(dd) {
          justify-content: flex-end;
          font-weight: 500;
        }
        .totals :deep(dt:last-of-type),
        .totals :deep(dd:last-of-type) {
          padding-top: 0.5rem;
          border-top: 0.125rem solid var(--foreground);
          color: var(--foreground);
          font-size: 1.125rem;
          font-weight: 700;
        }
        /* The rule runs across both columns: both cells fill the row, and the
           value cell reaches back across the column gap. */
        .totals :deep(dt:last-of-type) {
          align-self: stretch;
        }
        .totals :deep(dd:last-of-type) {
          align-self: stretch;
          margin-inline-start: calc(-1 * var(--space-6));
          padding-inline-start: var(--space-6);
        }
        .ship {
          border: 1px solid var(--border);
          border-radius: 0.5rem;
          padding: 1rem;
          background-color: var(--card);
          color: var(--card-foreground);
        }
      </style>
    </template>
  };
}
