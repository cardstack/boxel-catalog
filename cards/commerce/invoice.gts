import { Button } from '@cardstack/pretui/components/button';
import { RichFittedCard, Detail, Metric } from '../shared/rich-fitted-card';
import { on } from '@ember/modifier';
import {
  CardDef,
  Component,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BooleanField from '@cardstack/base/boolean';
import DateField from '@cardstack/base/date';
import { tracked } from '@glimmer/tracking';
import { concat } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
// Payment Status is its own module so it is a standalone, Spec-able block;
// Invoice uses it under the invoice-side name.
import { PaymentStatusField as InvoiceStatusField } from './payment-status-field';
import { TaxBreakdownField } from './tax-breakdown-field';
import FileInvoiceIcon from '@cardstack/boxel-icons/file-invoice';
import { Account } from '../crm/account';
import { User } from '../crm/user';
import { LineItem } from './line-item';
import { Order } from './order';
import { Quote } from './quote';
import { Subscription } from './subscription';
import { Payment } from './payment';
import { lineTotal, sumLineItems } from './line-item-totals';
import { realmURL } from '@cardstack/runtime-common';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Table } from '@cardstack/pretui/components/table';
import { Money } from '../crm/money';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Chip } from '@cardstack/pretui/components/chip';
import { Stat } from '@cardstack/pretui/components/stat';
import { formatMoney } from '../crm/utils';
import { fmtDate } from './compact-parts';
import DueDateField from '@cardstack/catalog/fields/due-date/due-date';
// ---- AP (buy-side) leg.
import { PurchaseOrder } from '../procurement/purchase-order';
import {
  VarianceResolutionField,
  matchLines,
  resolutionFor,
  type ResolutionLike,
} from '../procurement/three-way-match';
import { ThreeWayMatchPanel } from '../procurement/components/three-way-match-panel';
import { IsoFrame } from '../shared/compact-sheet';

// Overdue is not a state anyone sets — it is what being unpaid past the due
// date looks like, so it is derived rather than stored and cannot drift from
// the balance and the calendar. The status vocabulary lives in
// `payment-status-field.gts`.

// The invoice-side name for Payment Status. Its transition graph carries both
// legs: the sell-side ladder and the AP match flow (Received → Matching →
// Matched / Exception → Approved for Payment → Paid).
export { PaymentStatusField as InvoiceStatusField } from './payment-status-field';

interface InvoiceLike {
  lineItems?: any[];
  taxBreakdown?: { taxAmount?: number | null } | null;
  payments?: ({ amount?: { amount?: number | null } | null } | undefined)[];
  purchaseOrder?: {
    lineItems?: any[];
    receivedQuantities?: (number | undefined)[];
  } | null;
  varianceResolutions?: (ResolutionLike | undefined)[];
}

/**
 * What an invoice is for and what is still owed, in one place for every view
 * and the overdue check. Tax is added from the Tax Breakdown. On a vendor
 * invoice, a `short-pay` resolution pays the PO price (the line's variance is
 * not owed) and a `reject-line` resolution drops the line; the tax scales with
 * the payable subtotal, so tax on an amount that isn't paid isn't paid either.
 */
// Payments are recorded in cents, so derived amounts are too: a fraction of a
// cent would leave an invoice paid its displayed total with a balance.
function toCents(n: number) {
  return Math.round(n * 100) / 100;
}

export function invoiceAmounts(invoice?: InvoiceLike | null) {
  let { total: subtotal, code } = sumLineItems(invoice?.lineItems);
  let tax = invoice?.taxBreakdown?.taxAmount ?? 0;
  let adjustment = 0;
  let resolutions = (invoice?.varianceResolutions ?? []).filter(Boolean);
  let po = invoice?.purchaseOrder;
  if (po && resolutions.length) {
    let rows = matchLines(
      po.lineItems ?? [],
      po.receivedQuantities ?? [],
      invoice?.lineItems ?? [],
    );
    for (let row of rows) {
      let r = resolutionFor(row, resolutions);
      if (!r || row.state === 'clean') continue;
      if (r.action === 'short-pay')
        adjustment += Math.max(row.varianceAmount, 0);
      if (r.action === 'reject-line') adjustment += row.invTotal ?? 0;
    }
  }
  if (adjustment > 0 && subtotal > 0) {
    tax = toCents((tax * Math.max(subtotal - adjustment, 0)) / subtotal);
  }
  adjustment = toCents(adjustment);
  let total = toCents(subtotal + tax - adjustment);
  let paid = (invoice?.payments ?? []).reduce(
    (acc, p) => acc + (p?.amount?.amount ?? 0),
    0,
  );
  return {
    subtotal,
    tax,
    adjustment,
    total,
    paid,
    balance: Math.max(toCents(total - paid), 0),
    code,
  };
}

// What every compact format reads off the invoice, in one place.
function invoiceFacts(m?: Invoice) {
  let a = invoiceAmounts(m as any);
  let code = a.code;
  let money = (n: number) => formatMoney(n, code);
  let status = m?.displayStatus ?? '';
  let days = m?.daysOverdue ?? 0;
  let tone =
    status === 'overdue' ? 'danger' : status === 'paid' ? 'success' : 'info';
  let due = fmtDate(m?.dueDate);
  let sent = m?.status ? `${m.status}${a.balance > 0 ? ', not paid' : ''}` : '';
  let rate = m?.taxBreakdown?.rateApplied;
  let sub = [m?.account?.cardTitle, m?.owner?.cardTitle]
    .filter(Boolean)
    .join(' · ');
  return {
    a,
    code,
    number: m?.invoiceNumber?.trim() || 'Draft',
    sub,
    status,
    days,
    balance: money(a.balance),
    total: money(a.total),
    subtotal: money(a.subtotal),
    taxText: a.tax ? `${money(a.tax)}${rate ? ` · ${rate}%` : ''}` : '',
    issued: fmtDate(m?.issueDate),
    due,
    fact: [`${money(a.balance)}${due ? ` due ${due}` : ''}`, sent]
      .filter(Boolean)
      .join(' · '),
    tags: [
      ...(status ? [{ label: status, tone }] : []),
      ...(days > 0 ? [{ label: `${days} days`, tone: 'danger' }] : []),
    ] as { label: string; tone: any }[],
  };
}

class InvoiceIsolated extends Component<typeof Invoice> {
  @tracked busy = false;
  get balance() {
    let m = this.args.model as Invoice;
    // Same figure as the Balance due stat and record-payment: tax and variance resolutions included.
    return invoiceAmounts(m as any).balance;
  }
  // Loaded on click: the command imports this module's neighbours, so a
  // static import would close an import cycle.
  recordPayment = async () => {
    let ctx = (this.args.context as any)?.commandContext;
    let m = this.args.model as any;
    let realm = m?.[realmURL]?.href;
    if (!ctx || !realm || this.balance <= 0) return;
    this.busy = true;
    try {
      let { default: RecordPayment } =
        await import('./commands/record-payment.gts');
      await new RecordPayment(ctx).execute({
        invoice: m,
        amount: this.balance,
        method: 'bank transfer',
        reference: `CARD-${Date.now()}`,
        realm,
      } as any);
    } finally {
      this.busy = false;
    }
  };
  get f() {
    return invoiceFacts(this.args.model as Invoice);
  }
  get rows() {
    return (this.args.model?.lineItems ?? []).map((item) => ({
      description: item?.description || '—',
      quantity: item?.quantity ?? 0,
      total: lineTotal(item),
      code: item?.unitPrice?.currency?.code ?? undefined,
    }));
  }
  get linked(): KeyValueItem[] {
    let m = this.args.model;
    let rows: KeyValueItem[] = [];
    if (m?.account) rows.push({ key: 'Account', value: '' });
    if (m?.quote) rows.push({ key: 'Quote', value: '' });
    if (m?.owner) rows.push({ key: 'Owner', value: '' });
    if (m?.order) rows.push({ key: 'Order', value: '' });
    if (m?.subscription) rows.push({ key: 'Subscription', value: '' });
    if (m?.taxBreakdown?.jurisdiction) {
      rows.push({ key: 'Tax jurisdiction', value: '' });
    }
    return rows;
  }
  get details(): KeyValueItem[] {
    let m = this.args.model;
    let rows: KeyValueItem[] = [
      { key: 'Total', value: this.f.total },
      { key: 'Balance due', value: this.f.balance },
      { key: 'Subtotal', value: this.f.subtotal },
    ];
    if (this.f.taxText) rows.push({ key: 'Tax', value: this.f.taxText });
    if (this.f.issued) rows.push({ key: 'Issued', value: this.f.issued });
    if (this.f.due) rows.push({ key: 'Due', value: this.f.due });
    if (this.f.days)
      rows.push({ key: 'Days overdue', value: `${this.f.days}` });
    if (m?.status) rows.push({ key: 'Status', value: m.status });
    return rows;
  }
  <template>
    <IsoFrame>
      <article class='ip'>
        <header class='ih'>
          <Avatar @name='Invoice' @shape='square' @size={{24}} />
          <div class='id'>
            <h1>{{this.f.number}}</h1>
            <p class='meta'>{{this.f.sub}}</p>
          </div>
          <span class='tags'>{{#each this.f.tags as |t|}}<Chip
                @label={{t.label}}
                @tone={{t.tone}}
                @appearance='plain'
              />{{/each}}</span>
          {{#if this.balance}}
            <Button
              @appearance='filled'
              @disabled={{this.busy}}
              {{on 'click' this.recordPayment}}
            >Record payment</Button>
          {{/if}}
        </header>
        <div class='stats'>
          <Stat
            @label='Balance due'
            @tone={{if (eq this.f.status 'overdue') 'danger' 'info'}}
            @value={{this.f.a.balance}}
            @style='currency'
            @currency={{this.f.code}}
            @maximumFractionDigits={{0}}
            @roll={{false}}
            @hint={{if this.f.a.paid 'part paid' 'nothing paid'}}
          />
          <Stat
            @label='Days overdue'
            @tone={{if this.f.days 'warning'}}
            @value={{this.f.days}}
            @roll={{false}}
            @hint={{if this.f.due (concat 'due ' this.f.due)}}
          />
          <Stat
            @label='Tax'
            @value={{this.f.a.tax}}
            @style='currency'
            @currency={{this.f.code}}
            @maximumFractionDigits={{0}}
            @roll={{false}}
            @hint={{if this.f.taxText this.f.taxText}}
          />
        </div>
        <div class='cols'>
          <div>
            <section>
              <h2>Line items</h2>
              {{#if this.rows.length}}
                <Table class='lines' @label='Line items'>
                  <:head>
                    <tr>
                      <th scope='col'>Description</th>
                      <th scope='col' class='num'>Qty</th>
                      <th scope='col' class='num'>Amount</th>
                    </tr>
                  </:head>
                  <:body>
                    {{#each this.rows as |row|}}
                      <tr>
                        <td>{{row.description}}</td>
                        <td class='num'>{{row.quantity}}</td>
                        <td class='num'><Money
                            @amount={{row.total}}
                            @code={{row.code}}
                          /></td>
                      </tr>
                    {{/each}}
                    {{#if this.f.taxText}}
                      <tr>
                        <td>Tax</td>
                        <td></td>
                        <td class='num'><Money
                            @amount={{this.f.a.tax}}
                            @code={{this.f.code}}
                          /></td>
                      </tr>
                    {{/if}}
                    <tr class='total'>
                      <td>Total</td>
                      <td></td>
                      <td class='num'>{{this.f.total}}</td>
                    </tr>
                  </:body>
                </Table>
              {{else}}
                <p class='empty-note'>No line items yet</p>
              {{/if}}
            </section>
            {{#if @model.purchaseOrder}}
              <section>
                <h2>Three-way match · vs {{@model.purchaseOrder.poNumber}}</h2>
                <ThreeWayMatchPanel @invoice={{@model}} @context={{@context}} />
              </section>
            {{/if}}
            <section>
              <h2>Payments</h2>
              {{#if @model.payments.length}}
                <@fields.payments @format='embedded' />
              {{else}}
                <p class='empty-note'>No payments recorded</p>
              {{/if}}
            </section>
          </div>
          <div>
            <section>
              <h2>Linked</h2>
              <KeyValue
                @items={{this.linked}}
                @divided={{true}}
                @labelStyle='eyebrow'
                class='kv'
              >
                <:value as |row|>
                  {{#if (eq row.key 'Account')}}<@fields.account
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else if (eq row.key 'Quote')}}<@fields.quote
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else if (eq row.key 'Owner')}}<@fields.owner
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else if (eq row.key 'Order')}}<@fields.order
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else if (eq row.key 'Subscription')}}<@fields.subscription
                      @format='atom'
                      @displayContainer={{false}}
                    />
                  {{else}}<@fields.taxBreakdown.jurisdiction
                      @format='atom'
                      @displayContainer={{false}}
                    />{{/if}}
                </:value>
              </KeyValue>
            </section>
            <section>
              <h2>Details</h2>
              <KeyValue
                @items={{this.details}}
                @divided={{true}}
                @labelStyle='eyebrow'
                class='kv'
              />
            </section>
          </div>
        </div>
      </article>
    </IsoFrame>
    <style scoped>
      .empty-note {
        margin: 0;
        padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .ip {
        font-size: var(--boxel-font-size-xs);
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
        font-size: var(--boxel-font-size-xs);
        line-height: 1.25;
        color: var(--card-foreground);
      }
      .ih {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs);
      }
      .id {
        flex: 1;
        min-inline-size: 0;
      }
      h1 {
        font-family: var(--font-sans);
        margin: 0;
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .meta {
        margin: 0;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .tags {
        display: flex;
        gap: var(--boxel-sp-xs);
      }
      .stats {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
        border-block-start: 1px solid var(--border);
      }
      .stats > :not(:first-child) {
        border-inline-start: 1px solid var(--border);
      }
      .stats > * {
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
      }
      .cols {
        display: grid;
        grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
        border-block-start: 1px solid var(--border);
      }
      .cols > div {
        min-inline-size: 0;
      }
      .cols > div + div {
        border-inline-start: 1px solid var(--border);
      }
      @container (width < 40rem) {
        .cols {
          grid-template-columns: minmax(0, 1fr);
        }
        .cols > div + div {
          border-inline-start: 0;
          border-block-start: 1px solid var(--border);
        }
      }
      h2 {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-xs) var(--boxel-sp-4xs);
        font-size: var(--boxel-font-size-xs);
        font-weight: 700;
      }
      .lines {
        font-size: var(--boxel-font-size-2xs);
      }
      .num {
        text-align: end;
        font-variant-numeric: tabular-nums;
      }
      .total td {
        font-weight: 700;
      }
      .kv {
        --pretui-kv-pad-inline: var(--boxel-sp-sm);
        row-gap: 0;
      }
    </style>
  </template>
}

export class Invoice extends CardDef {
  static displayName = 'Invoice';
  static icon = FileInvoiceIcon;

  @field invoiceNumber = contains(StringField);
  @field account = linksTo(Account);
  @field owner = linksTo(User);
  @field issueDate = contains(DateField);
  @field sentDate = contains(DateField);
  @field dueDate = contains(DueDateField);
  @field status = contains(InvoiceStatusField);
  @field lineItems = containsMany(LineItem);
  @field order = linksTo(() => Order);
  // The quote this invoice was converted from, if any.
  @field quote = linksTo(() => Quote);
  @field subscription = linksTo(() => Subscription);
  @field payments = linksToMany(() => Payment);
  // ---- AP leg: a VENDOR invoice names the PO it bills against, which is
  // what makes the three-way match possible. Sell-side invoices leave both
  // empty.
  @field purchaseOrder = linksTo(() => PurchaseOrder);
  @field varianceResolutions = containsMany(VarianceResolutionField);
  // Optional (not every invoice is taxed); its `taxAmount` is added to the
  // total by `invoiceAmounts`.
  @field taxBreakdown = contains(TaxBreakdownField);

  // What is still owed, tax and variance resolutions included. Cards that
  // query invoices read it instead of importing `invoiceAmounts`.
  @field balanceDue = contains(NumberField, {
    computeVia: function (this: Invoice) {
      return invoiceAmounts(this as any).balance;
    },
  });

  @field daysOverdue = contains(NumberField, {
    computeVia: function (this: Invoice) {
      if (!this.dueDate) return 0;
      if (['paid', 'void'].includes(this.status ?? '')) return 0;
      // Paid in full is not overdue, whatever the stored status says.
      if (invoiceAmounts(this as any).balance <= 0) return 0;
      let days = Math.floor(
        (Date.now() - new Date(this.dueDate).getTime()) / 86400000,
      );
      return days > 0 ? days : 0;
    },
  });

  @field isOverdue = contains(BooleanField, {
    computeVia: function (this: Invoice) {
      return (this.daysOverdue ?? 0) > 0;
    },
  });

  // What every consumer should render and filter on: the stored status except
  // when the calendar overrides it.
  @field displayStatus = contains(StringField, {
    computeVia: function (this: Invoice) {
      return this.isOverdue ? 'overdue' : this.status;
    },
  });

  @field cardTitle = contains(StringField, {
    computeVia: function (this: Invoice) {
      return this.invoiceNumber?.trim()?.length
        ? `Invoice ${this.invoiceNumber}`
        : `Untitled ${this.constructor.displayName}`;
    },
  });

  static atom = class Atom extends Component<typeof Invoice> {
    <template>
      <span class='atom'>
        <Avatar @name='Invoice' @shape='square' @size={{16}} />
        <span class='name'>{{if
            @model.invoiceNumber
            @model.invoiceNumber
            'Draft'
          }}</span>
      </span>
      <style scoped>
        .atom {
          font-size: 0.6875rem;
          font-weight: 600;
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          min-inline-size: 0;
        }
        .name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Invoice> {
    get f() {
      return invoiceFacts(this.args.model as Invoice);
    }
    <template>
      <RichFittedCard>
        <:avatar><Avatar
            @name='Invoice'
            @shape='square'
            @size={{20}}
          /></:avatar>
        <:title>{{this.f.number}}</:title>
        <:status>{{#each this.f.tags as |t|}}<Chip
              @label={{t.label}}
              @tone={{t.tone}}
              @appearance='plain'
            />{{/each}}</:status>
        <:subtitle>{{this.f.sub}}</:subtitle>
        <:fact>{{this.f.fact}}</:fact>
        <:metric><Metric
            @value={{this.f.balance}}
            @label='Balance due'
          /></:metric>
        <:details>
          <Detail @label='Total' @value={{this.f.total}} />
          <Detail @label='Subtotal' @value={{this.f.subtotal}} />
          {{#if @model.account}}<Detail @label='Account'><@fields.account
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if this.f.taxText}}<Detail
              @label='Tax'
              @value={{this.f.taxText}}
            />{{/if}}
          {{#if this.f.issued}}<Detail
              @label='Issued'
              @value={{this.f.issued}}
            />{{/if}}
          {{#if @model.quote}}<Detail @label='Quote'><@fields.quote
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if this.f.due}}<Detail @label='Due' @value={{this.f.due}} />{{/if}}
          {{#if @model.owner}}<Detail @label='Owner'><@fields.owner
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
          {{#if @model.taxBreakdown.jurisdiction}}<Detail
              @label='Tax jurisdiction'
            ><@fields.taxBreakdown.jurisdiction
                @format='atom'
                @displayContainer={{false}}
              /></Detail>{{/if}}
        </:details>
      </RichFittedCard>
    </template>
  };

  static embedded = class Embedded extends Component<typeof Invoice> {
    get f() {
      return invoiceFacts(this.args.model as Invoice);
    }
    get items(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [
        { key: 'Total', value: this.f.total },
        { key: 'Subtotal', value: this.f.subtotal },
      ];
      if (this.f.taxText) rows.push({ key: 'Tax', value: this.f.taxText });
      if (this.f.issued) rows.push({ key: 'Issued', value: this.f.issued });
      if (this.f.due) rows.push({ key: 'Due', value: this.f.due });
      if (m?.account) rows.push({ key: 'Account', value: '' });
      if (m?.quote) rows.push({ key: 'Quote', value: '' });
      if (m?.owner) rows.push({ key: 'Owner', value: '' });
      return rows;
    }
    <template>
      <article class='emb'>
        <header class='eh'>
          <Avatar @name='Invoice' @shape='square' @size={{24}} />
          <div class='id'>
            <strong>{{this.f.number}}</strong>
            <span class='meta'>{{this.f.sub}}</span>
          </div>
          {{#each this.f.tags as |t i|}}{{#if (eq i 0)}}<Chip
                @label={{t.label}}
                @tone={{t.tone}}
                @appearance='plain'
              />{{/if}}{{/each}}
        </header>
        <p class='fact'>{{this.f.fact}}</p>
        <KeyValue
          @items={{this.items}}
          @divided={{true}}
          @labelStyle='eyebrow'
          class='kv'
        >
          <:value as |row|>
            {{#if (eq row.key 'Account')}}<@fields.account
                @format='atom'
                @displayContainer={{false}}
              />
            {{else if (eq row.key 'Quote')}}<@fields.quote
                @format='atom'
                @displayContainer={{false}}
              />
            {{else if (eq row.key 'Owner')}}<@fields.owner
                @format='atom'
                @displayContainer={{false}}
              />
            {{else}}{{row.value}}{{/if}}
          </:value>
        </KeyValue>
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
          font-size: 0.75rem;
          line-height: 1.25;
        }
        .eh {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          padding: 0.5rem 0.625rem;
        }
        .id {
          flex: 1;
          min-inline-size: 0;
          display: flex;
          flex-direction: column;
        }
        .id strong,
        .meta {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .meta,
        .fact {
          font-size: 0.6875rem;
          color: var(--muted-foreground);
        }
        .fact {
          margin: 0;
          padding: 0 0.625rem 0.5rem;
        }
        .kv {
          --pretui-kv-pad-inline: var(--boxel-sp-sm);
          row-gap: 0;
        }
      </style>
    </template>
  };

  static isolated = InvoiceIsolated;

  // AP/AR document form grouped by how the clerk works the invoice: identify
  // the document → who it involves → what's on it → does it match the PO →
  // how it got paid. Never schema order.
}
