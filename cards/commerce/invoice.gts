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
import { eq } from '@cardstack/boxel-ui/helpers';
import { FieldContainer } from '@cardstack/boxel-ui/components';
import { EditSectionNav } from '@cardstack/catalog/components/edit-section-nav';
// Payment Status is its own module so it is a standalone, Spec-able block;
// Invoice uses it under the invoice-side name.
import { PaymentStatusField as InvoiceStatusField } from './payment-status-field';
import { TaxBreakdownField } from './tax-breakdown-field';
import FileInvoiceIcon from '@cardstack/boxel-icons/file-invoice';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { User } from '@cardstack/catalog/cards/crm/user';
import { LineItem } from '@cardstack/catalog/cards/commerce/line-item';
import { Order } from './order';
import { Subscription } from './subscription';
import { Payment } from './payment';
import {
  lineTotal,
  sumLineItems,
} from '@cardstack/catalog/cards/commerce/line-item-totals';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { Table } from '@cardstack/pretui/components/table';
import { Money } from '@cardstack/catalog/cards/crm/money';
import { StatePill, type Hue } from '@cardstack/catalog/components/state-pill';
import { COMPACT_EMPTY_STYLE } from '@cardstack/catalog/components/pretui-helpers';
import { statusHue } from '@cardstack/catalog/fields/status/status';
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

// The due-date pill states calendar facts it cannot square with the invoice's
// lifecycle, so terminal invoices render the plain date instead of the field.
function plainDate(value: Date | null | undefined): string {
  if (!value) return '';
  return new Intl.DateTimeFormat(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(value);
}

function isTerminal(status: string | null | undefined): boolean {
  return ['paid', 'void'].includes(status ?? '');
}

// The pill hue for what an invoice displays: the status field's own hue, and
// red for the derived `overdue`, which is not one of the field's options.
function displayHue(status: string | null | undefined): Hue {
  return status === 'overdue' ? 'red' : statusHue(InvoiceStatusField, status);
}

// Overdue is not a state anyone sets — it is what being unpaid past the due
// date looks like, so it is derived rather than stored and cannot drift from
// the balance and the calendar. The status vocabulary lives in
// `payment-status-field.gts`.

// The invoice-side name for Payment Status. Its transition graph carries both
// legs: the sell-side ladder and the AP match flow (Received → Matching →
// Matched / Exception → Approved for Payment → Paid).
export { PaymentStatusField as InvoiceStatusField } from './payment-status-field';

class InvoiceEdit extends Component<typeof Invoice> {
  @tracked activeSection = 'identity';

  sections = [
    { id: 'identity', label: 'Invoice' },
    { id: 'parties', label: 'Parties' },
    { id: 'items', label: 'Line items' },
    { id: 'matching', label: 'Matching' },
    { id: 'payment', label: 'Payment' },
  ];

  goTo = (id: string, event: Event) => {
    this.activeSection = id;
    let root = (event.currentTarget as HTMLElement).closest('.invoice-edit');
    root
      ?.querySelector(`[data-sect='${id}']`)
      ?.scrollIntoView({ block: 'start', behavior: 'smooth' });
  };

  <template>
    <div class='invoice-edit'>
      {{! the container element cannot be restyled by its own query —
          the responsive grid lives on this inner wrapper instead }}
      <div class='edit-body'>
        <EditSectionNav
          @sections={{this.sections}}
          @activeId={{this.activeSection}}
          @onSelect={{this.goTo}}
          class='sect-nav'
        />
        <div class='sects'>
          <section
            class='sect {{if (eq this.activeSection "identity") "focused"}}'
            data-sect='identity'
          >
            <h3>Invoice</h3>
            <div class='row identity'>
              <FieldContainer @label='Invoice number' @vertical={{true}}>
                <@fields.invoiceNumber />
              </FieldContainer>
              <FieldContainer @label='Status' @vertical={{true}}>
                <@fields.status />
              </FieldContainer>
            </div>
            <div class='row'>
              <FieldContainer @label='Issued' @vertical={{true}}>
                <@fields.issueDate />
              </FieldContainer>
              <FieldContainer @label='Sent' @vertical={{true}}>
                <@fields.sentDate />
              </FieldContainer>
              <FieldContainer @label='Due' @vertical={{true}}>
                <@fields.dueDate />
              </FieldContainer>
            </div>
          </section>

          <section
            class='sect {{if (eq this.activeSection "parties") "focused"}}'
            data-sect='parties'
          >
            <h3>Parties</h3>
            <div class='row'>
              <FieldContainer @label='Account (billed to)' @vertical={{true}}>
                <@fields.account />
              </FieldContainer>
              <FieldContainer @label='Owner' @vertical={{true}}>
                <@fields.owner />
              </FieldContainer>
            </div>
            <div class='row'>
              <FieldContainer @label='Order' @vertical={{true}}>
                <@fields.order />
              </FieldContainer>
              <FieldContainer @label='Subscription' @vertical={{true}}>
                <@fields.subscription />
              </FieldContainer>
            </div>
          </section>

          <section
            class='sect {{if (eq this.activeSection "items") "focused"}}'
            data-sect='items'
          >
            <h3>Line items</h3>
            <FieldContainer @label='Items' @vertical={{true}}>
              <@fields.lineItems />
            </FieldContainer>
            <FieldContainer @label='Tax breakdown' @vertical={{true}}>
              <@fields.taxBreakdown />
            </FieldContainer>
            <p class='sect-note'>Tax is added to the total; record the
              calculated amount here.</p>
          </section>

          <section
            class='sect matching
              {{if (eq this.activeSection "matching") "focused"}}'
            data-sect='matching'
          >
            <h3>Matching
              <span class='sect-hint'>the three-way match reads these</span></h3>
            <FieldContainer @label='Purchase order' @vertical={{true}}>
              <@fields.purchaseOrder />
            </FieldContainer>
            <FieldContainer @label='Variance resolutions' @vertical={{true}}>
              <@fields.varianceResolutions />
            </FieldContainer>
            <p class='sect-note'>Resolutions are normally written by the Resolve
              Variance command — edit here only for corrections.</p>
          </section>

          <section
            class='sect {{if (eq this.activeSection "payment") "focused"}}'
            data-sect='payment'
          >
            <h3>Payment</h3>
            <FieldContainer @label='Payments applied' @vertical={{true}}>
              <@fields.payments />
            </FieldContainer>
          </section>
        </div>
      </div>
    </div>
    <style scoped>
      .invoice-edit {
        container-type: inline-size;
        container-name: edit;
        height: 100%;
        overflow-y: auto;
        padding: var(--boxel-sp);
        background-color: var(--background);
        color: var(--foreground);
        /* family ink, declared ONCE — a linked Theme overrides via
           --procurement-ink */
        --inv-ink: var(--procurement-ink, var(--primary-ink));
        --inv-ink-fg: var(--procurement-ink-fg, var(--card));
      }
      .edit-body {
        display: grid;
        grid-template-columns: 9.5rem minmax(0, 1fr);
        align-items: start;
        gap: var(--boxel-sp);
      }
      /* the root is the scroller, so sticky pins the nav to its top */
      .sect-nav {
        position: sticky;
        top: 0;
        --edit-section-nav-ink: var(--inv-ink);
        --edit-section-nav-ink-fg: var(--inv-ink-fg);
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
        outline-color: var(--inv-ink);
        box-shadow: 0 0 0 0.25rem
          color-mix(in oklch, var(--inv-ink) 12%, transparent);
      }
      .sect.matching {
        border-left: 0.1875rem solid var(--inv-ink);
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
      .sect-note {
        margin: 0;
        font-size: 0.75rem;
        font-style: italic;
        color: var(--muted-foreground);
      }
      .row {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: var(--boxel-sp-sm);
        align-items: start;
      }
      .identity {
        grid-template-columns: 2fr 1fr;
      }
      @container edit (width < 640px) {
        .row,
        .identity {
          grid-template-columns: 1fr;
        }
        .edit-body {
          grid-template-columns: 1fr;
        }
        /* narrow: the rail flips horizontal */
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
 * not owed) and a `reject-line` resolution drops the line.
 */
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
  let total = subtotal + tax - adjustment;
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
    balance: Math.max(total - paid, 0),
    code,
  };
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

  static embedded = class Embedded extends Component<typeof Invoice> {
    get amounts() {
      return invoiceAmounts(this.args.model as any);
    }
    <template>
      <div class='invoice-row'>
        <FileInvoiceIcon class='icon' />
        <span class='number'>{{@model.cardTitle}}</span>
        {{#if @model.displayStatus}}
          <StatePill
            @label={{@model.displayStatus}}
            @hue={{displayHue @model.displayStatus}}
            @dot={{true}}
          />
        {{/if}}
        <Money
          class='total'
          @amount={{this.amounts.total}}
          @code={{this.amounts.code}}
        />
      </div>
      <style scoped>
        .invoice-row {
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

  static atom = class Atom extends Component<typeof Invoice> {
    <template>
      <span class='invoice-atom'>
        <FileInvoiceIcon class='ia-icon' />
        <span class='ia-name'>{{@model.cardTitle}}</span>
      </span>
      <style scoped>
        .invoice-atom {
          display: inline-flex;
          align-items: center;
          gap: 0.375rem;
          font-size: 0.8125rem;
          font-weight: 500;
          color: var(--foreground);
        }
        .ia-icon {
          width: 0.875rem;
          height: 0.875rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }
        .ia-name {
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof Invoice> {
    get amounts() {
      return invoiceAmounts(this.args.model as any);
    }
    get itemCount() {
      return this.args.model?.lineItems?.length ?? 0;
    }
    get dueLabel() {
      return plainDate(this.args.model?.dueDate);
    }
    <template>
      <div class='fitted'>
        <div class='fmt badge'>
          <FileInvoiceIcon class='doc-icon' />
          <span class='name'>{{@model.cardTitle}}</span>
          {{#if @model.displayStatus}}
            <StatePill
              class='status'
              @label={{@model.displayStatus}}
              @hue={{displayHue @model.displayStatus}}
            />
          {{/if}}
        </div>
        <div class='fmt strip'>
          <FileInvoiceIcon class='doc-icon' />
          <div class='info'>
            <span class='name'>{{@model.cardTitle}}</span>
            {{#if @model.displayStatus}}
              <StatePill
                class='status'
                @label={{@model.displayStatus}}
                @hue={{displayHue @model.displayStatus}}
              />
            {{/if}}
          </div>
          <Money
            class='figure'
            @amount={{this.amounts.total}}
            @code={{this.amounts.code}}
          />
        </div>
        <div class='fmt tile'>
          <div class='row'>
            <FileInvoiceIcon class='doc-icon' />
            {{#if @model.displayStatus}}
              <StatePill
                class='status'
                @label={{@model.displayStatus}}
                @hue={{displayHue @model.displayStatus}}
              />
            {{/if}}
          </div>
          <span class='name'>{{@model.cardTitle}}</span>
          <Money
            class='figure figure-lg'
            @amount={{this.amounts.total}}
            @code={{this.amounts.code}}
          />
          {{#if @model.dueDate}}
            <span class='meta'>Due {{this.dueLabel}}</span>
          {{/if}}
        </div>
        <div class='fmt card'>
          <div class='col'>
            <div class='row'>
              <FileInvoiceIcon class='doc-icon' />
              <span class='name name-lg'>{{@model.cardTitle}}</span>
              {{#if @model.displayStatus}}
                <StatePill
                  class='status'
                  @label={{@model.displayStatus}}
                  @hue={{displayHue @model.displayStatus}}
                />
              {{/if}}
            </div>
            {{#if @model.account.name}}
              <span class='meta'>Billed to {{@model.account.name}}</span>
            {{/if}}
            <span class='meta'>{{this.itemCount}}
              item{{unless (eq this.itemCount 1) 's'}}{{#if @model.dueDate}}
                · due
                {{this.dueLabel}}{{/if}}</span>
          </div>
          <Money
            class='figure figure-lg'
            @amount={{this.amounts.total}}
            @code={{this.amounts.code}}
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

  static isolated = class Isolated extends Component<typeof Invoice> {
    get showDueness() {
      return !isTerminal(this.args.model?.status);
    }
    get dueLabel() {
      return plainDate(this.args.model?.dueDate);
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
    get amounts() {
      return invoiceAmounts(this.args.model as any);
    }
    get number() {
      return this.args.model?.invoiceNumber?.trim() || 'Draft';
    }
    get paidSum() {
      let sum = 0;
      let code: string | undefined;
      for (let p of this.args.model?.payments ?? []) {
        sum += p?.amount?.amount ?? 0;
        code = code ?? p?.amount?.currency?.code ?? undefined;
      }
      return { sum, code };
    }
    get balance() {
      let due = this.amounts.total - this.paidSum.sum;
      return due > 0 ? due : 0;
    }
    get balanceCode() {
      return this.paidSum.code ?? this.amounts.code;
    }
    get facts(): KeyValueItem[] {
      let m = this.args.model;
      let rows: KeyValueItem[] = [{ key: 'Issued', value: 'issueDate' }];
      if (m?.sentDate) rows.push({ key: 'Sent', value: 'sentDate' });
      rows.push({ key: 'Due', value: 'dueDate' });
      if (m?.owner) rows.push({ key: 'Owner', value: 'owner' });
      if (m?.order) rows.push({ key: 'Order', value: 'order' });
      if (m?.subscription) {
        rows.push({ key: 'Subscription', value: 'subscription' });
      }
      return rows;
    }
    // The totals block as KeyValue rows; each value names the figure the
    // <:value> block renders.
    get totalsFacts(): KeyValueItem[] {
      let rows: KeyValueItem[] = [{ key: 'Total', value: 'total' }];
      if (this.paidSum.sum) {
        rows.push({ key: 'Paid', value: 'paid' });
        rows.push({ key: 'Balance due', value: 'balance' });
      }
      return rows;
    }
    <template>
      <article class='invoice-doc'>
        <header class='doc-head'>
          <div>
            <p class='doc-kind'>Invoice</p>
            <h1>{{this.number}}</h1>
          </div>
          {{#if @model.displayStatus}}
            <StatePill
              class='status'
              @label={{@model.displayStatus}}
              @hue={{displayHue @model.displayStatus}}
              @dot={{true}}
            />
          {{/if}}
        </header>

        <section class='doc-meta'>
          <div class='party'>
            <span class='label'>Billed to</span>
            <@fields.account @format='embedded' />
          </div>
          <KeyValue class='dates' @items={{this.facts}}>
            <:value as |row|>
              {{#if (eq row.value 'issueDate')}}
                <@fields.issueDate />
              {{else if (eq row.value 'sentDate')}}
                <@fields.sentDate />
              {{else if (eq row.value 'dueDate')}}
                {{#if this.showDueness}}
                  <@fields.dueDate />
                {{else}}
                  {{this.dueLabel}}
                {{/if}}
              {{else if (eq row.value 'owner')}}
                <@fields.owner @format='atom' />
              {{else if (eq row.value 'order')}}
                <@fields.order @format='atom' />
              {{else}}
                <@fields.subscription @format='atom' />
              {{/if}}
            </:value>
          </KeyValue>
        </section>

        <section class='items'>
          {{#if this.rows.length}}
            <Table class='lines' @label='Line items'>
              <:head>
                <tr>
                  <th scope='col'>Description</th>
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
                {{#if (eq row.value 'total')}}
                  <Money
                    @amount={{this.amounts.total}}
                    @code={{this.amounts.code}}
                  />
                {{else if (eq row.value 'paid')}}
                  <Money
                    @amount={{this.paidSum.sum}}
                    @code={{this.paidSum.code}}
                  />
                {{else}}
                  <Money @amount={{this.balance}} @code={{this.balanceCode}} />
                {{/if}}
              </:value>
            </KeyValue>
          {{else}}
            <EmptyState
              style={{COMPACT_EMPTY_STYLE}}
              @texture={{false}}
              @title='No line items yet'
            />
          {{/if}}
        </section>

        {{#if @model.purchaseOrder}}
          <section class='match'>
            <span class='label'>Three-way match · vs
              {{@model.purchaseOrder.poNumber}}</span>
            <ThreeWayMatchPanel @invoice={{@model}} @context={{@context}} />
          </section>
        {{/if}}

        {{#if @model.payments.length}}
          <section class='payments'>
            <span class='label'>Payments</span>
            <@fields.payments @format='embedded' />
          </section>
        {{/if}}
      </article>
      <style scoped>
        .invoice-doc {
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
        .dates {
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
        .totals :deep(dt:first-of-type),
        .totals :deep(dd:first-of-type) {
          padding-top: 0.5rem;
          border-top: 0.125rem solid var(--foreground);
          color: var(--foreground);
          font-size: 1.125rem;
          font-weight: 700;
        }
        .totals :deep(dd:nth-of-type(3)) {
          font-weight: 600;
        }
      </style>
    </template>
  };

  // AP/AR document form grouped by how the clerk works the invoice: identify
  // the document → who it involves → what's on it → does it match the PO →
  // how it got paid. Never schema order.
  static edit = InvoiceEdit;
}
