import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq, gt } from '@cardstack/boxel-ui/helpers';
import type { CardDef } from '@cardstack/base/card-api';
import { Button } from '@cardstack/pretui/components/button';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import { StatePill } from '../../../components/state-pill';
import { Table, type TableColumn } from '../../../components/table';
import { ExportButton, type ExportColumn } from '../../../components/export';
import { ImportButton, type ImportColumn } from '../../../components/import';
import {
  formatDay,
  toDate,
} from '../../../fields/effective-period/effective-period-field';
import { Invoice } from '../../commerce/invoice';
import {
  formatMoney,
  outstandingBalance,
  sumLineItems,
} from '../../commerce/line-item-totals';
import {
  BASE_CURRENCY,
  INVOICE_FILTERS,
  INVOICE_IMPORT_STATUSES,
  OPEN_INVOICE_STATUSES,
  asCalendarDay,
  invoiceHue,
  invoiceStatus,
  isBaseInvoice,
  stopThen,
} from '../revenue-os-data';
import type { RevenueOsConsole } from '../revenue-os';

interface Signature {
  Args: {
    console: RevenueOsConsole;
  };
}

// The Invoices tab: aging by bucket, a filterable table with import and
// export, and per-row payment and duplicate actions.
export class InvoicesPane extends Component<Signature> {
  // ── invoices ──────────────────────────────────────────────────────
  invoiceColumns: TableColumn[] = [
    {
      key: 'number',
      label: 'Invoice #',
      value: (item) => (item as Invoice).invoiceNumber,
    },
    {
      key: 'account',
      label: 'Account',
      custom: true,
      value: (item) => (item as Invoice).account?.name,
    },
    {
      key: 'amount',
      label: 'Amount',
      align: 'right',
      value: (item) => {
        let { total, code } = sumLineItems((item as Invoice).lineItems);
        return total ? formatMoney(total, code) : undefined;
      },
      sortValue: (item) => sumLineItems((item as Invoice).lineItems).total,
    },
    {
      key: 'status',
      label: 'Status',
      custom: true,
      value: (item) => (item as Invoice).displayStatus,
    },
    {
      key: 'due',
      label: 'Due',
      value: (item) => {
        let d = (item as Invoice).dueDate;
        return d ? formatDay(d) : undefined;
      },
      sortValue: (item) => toDate((item as Invoice).dueDate)?.getTime(),
    },
    {
      key: 'overdue',
      label: 'Days overdue',
      align: 'right',
      value: (item) => (item as Invoice).daysOverdue || undefined,
    },
    {
      key: 'actions',
      label: '',
      align: 'right',
      custom: true,
      sortable: false,
      value: () => '',
    },
  ];

  // The Table's own column definitions carry the CSV — same columns, same
  // labels — except money, which exports as a raw number so the column sums.
  invoiceType = Invoice;

  get exportColumns(): ExportColumn<CardDef>[] {
    return this.invoiceColumns
      .filter((c) => c.key !== 'actions')
      .map((c) => ({
        key: c.key,
        label: c.label,
        value: (item: CardDef) => {
          let v = c.value?.(item);
          return typeof v === 'string' || typeof v === 'number'
            ? v
            : v == null
              ? null
              : String(v);
        },
        exportValue:
          c.key === 'amount'
            ? (item: CardDef) => sumLineItems((item as Invoice).lineItems).total
            : undefined,
      }));
  }

  get exportFilename(): string {
    return `invoices-${this.args.console.invoiceFilter}`;
  }

  // Deliberately the same headers Export writes, so a file that leaves this
  // table can come back into it.
  importColumns: ImportColumn[] = [
    { header: 'Invoice #', field: 'invoiceNumber', required: true },
    {
      header: 'Status',
      field: 'status',
      parse: (raw) => {
        let value = raw.toLowerCase();
        // Overdue is derived here, so a file carrying it describes an unpaid
        // invoice rather than a status this card can store.
        if (value === 'overdue') return 'sent';
        if (!INVOICE_IMPORT_STATUSES.includes(value)) {
          throw new Error(`"${raw}" is not an invoice status`);
        }
        return value;
      },
    },
    {
      header: 'Due',
      field: 'dueDate',
      parse: (raw) => {
        let at = toDate(raw.trim());
        if (!at || Number.isNaN(at.getTime())) {
          throw new Error(`"${raw}" is not a date`);
        }
        return asCalendarDay(at);
      },
    },
  ];

  get filteredInvoices(): Invoice[] {
    let f = this.args.console.invoiceFilter;
    if (f === 'all') return this.args.console.invoices;
    if (f === 'paid')
      return this.args.console.invoices.filter((i) => i.status === 'paid');
    if (f === 'overdue') {
      return this.args.console.invoices.filter((i) => i.isOverdue);
    }
    return this.args.console.invoices.filter((i) =>
      OPEN_INVOICE_STATUSES.includes(i.status ?? ''),
    );
  }

  get aging() {
    let buckets = { current: 0, b30: 0, b60: 0, b90: 0 };
    for (let inv of this.args.console.invoices) {
      if (!OPEN_INVOICE_STATUSES.includes(inv.status ?? '')) continue;
      if (!isBaseInvoice(inv)) continue;
      let balance = outstandingBalance(inv.lineItems, inv.payments);
      let days = inv.daysOverdue ?? 0;
      if (days <= 0) buckets.current += balance;
      else if (days <= 30) buckets.b30 += balance;
      else if (days <= 60) buckets.b60 += balance;
      else buckets.b90 += balance;
    }
    let f = (n: number) => formatMoney(n, BASE_CURRENCY);
    let tone = (n: number, level: string) => (n > 0 ? level : 'zero');
    return [
      { label: 'Current', value: f(buckets.current), tone: 'ok' },
      {
        label: '1–30 days',
        value: f(buckets.b30),
        tone: tone(buckets.b30, 'warn'),
      },
      {
        label: '31–60 days',
        value: f(buckets.b60),
        tone: tone(buckets.b60, 'late'),
      },
      {
        label: '60+ days',
        value: f(buckets.b90),
        tone: tone(buckets.b90, 'late'),
      },
    ];
  }

  accountOf = (item: CardDef) => (item as Invoice).account;

  balanceOf = (item: CardDef) => {
    let inv = item as Invoice;
    return outstandingBalance(inv.lineItems, inv.payments);
  };
  balanceDisplay = (item: CardDef) => {
    let { code } = sumLineItems((item as Invoice).lineItems);
    return formatMoney(this.balanceOf(item), code);
  };

  <template>
    <section class='pane'>
      <div class='pane-head'>
        <h2>Invoices</h2>
        <span class='row-actions'>
          {{#if @console.realm}}
            <ImportButton
              @cardType={{this.invoiceType}}
              @columns={{this.importColumns}}
              @commandContext={{@console.commandContext}}
              @realm={{@console.realm}}
              @onComplete={{@console.reportImport}}
            />
          {{/if}}
          <ExportButton
            @rows={{this.filteredInvoices}}
            @columns={{this.exportColumns}}
            @filename={{this.exportFilename}}
          />
          <Button
            @appearance='outlined'
            @size='sm'
            {{on 'click' @console.newInvoice}}
          >New invoice</Button>
        </span>
      </div>
      {{#if @console.queriesSettled}}
        <div class='aging-strip'>
          {{#each this.aging as |bucket|}}
            <div class='metric metric-flat'>
              <span class='m-label'>{{bucket.label}}</span>
              <span class='m-value tone-{{bucket.tone}}'>{{bucket.value}}</span>
            </div>
          {{/each}}
        </div>
        <SegmentedControl
          class='filters'
          @label='Invoice filter'
          @options={{INVOICE_FILTERS}}
          @value={{@console.invoiceFilter}}
          @onValueChange={{@console.setInvoiceFilter}}
        />
        <Table
          @items={{this.filteredInvoices}}
          @columns={{this.invoiceColumns}}
          @onRowClick={{@console.openCard}}
          @emptyMessage='No invoices match this filter'
        >
          <:cell as |item column|>
            {{#if (eq column.key 'status')}}
              {{#let (invoiceStatus item) as |status|}}
                <StatePill @label={{status}} @hue={{invoiceHue status}} />
              {{/let}}
            {{else if (eq column.key 'account')}}
              {{#let (this.accountOf item) as |account|}}
                {{#if account}}
                  <Button
                    class='cell-account'
                    @appearance='plain'
                    @size='sm'
                    title='Open {{account.name}} in Accounts'
                    {{on 'click' (stopThen (fn @console.openAccountFor item))}}
                  >{{account.name}}</Button>
                {{/if}}
              {{/let}}
            {{else if (eq column.key 'actions')}}
              <span class='row-actions'>
                {{#if (gt (this.balanceOf item) 0)}}
                  <Button
                    @appearance='outlined'
                    @size='sm'
                    @disabled={{@console.busy}}
                    {{on
                      'click'
                      (stopThen (fn @console.recordBalancePayment item))
                    }}
                  >Record
                    {{this.balanceDisplay item}}</Button>
                {{/if}}
                {{#let (@console.booksStateOf item) as |books|}}
                  {{#if (eq books 'booked')}}
                    <span class='in-books'>In the books</span>
                  {{else if (eq books 'drafted')}}
                    <span class='in-books'>Drafted in the books</span>
                  {{else if (eq books 'post')}}
                    <Button
                      @appearance='outlined'
                      @size='sm'
                      @disabled={{@console.busy}}
                      {{on 'click' (stopThen (fn @console.postToBooks item))}}
                    >Post to the books</Button>
                  {{else if (eq books 'payments')}}
                    <Button
                      @appearance='outlined'
                      @size='sm'
                      @disabled={{@console.busy}}
                      {{on 'click' (stopThen (fn @console.postToBooks item))}}
                    >Post payments to the books</Button>
                  {{/if}}
                {{/let}}
                <Button
                  @appearance='plain'
                  @size='sm'
                  @disabled={{@console.busy}}
                  {{on 'click' (stopThen (fn @console.duplicateCard item))}}
                >Duplicate</Button>
              </span>
            {{/if}}
          </:cell>
        </Table>
      {{else}}
        <p class='loading' role='status'>Loading invoices…</p>
      {{/if}}
    </section>
    <style scoped>
      .in-books {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
      }
      .loading {
        margin: 0;
        color: var(--muted-foreground);
      }
      .pane {
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }
      .pane-head {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 1rem;
        flex-wrap: wrap;
      }
      h2 {
        margin: 0;
        font-size: 1.0625rem;
        font-family: var(--font-sans);
      }
      .aging-strip {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8.5rem, 1fr));
        gap: 0.75rem;
      }
      .metric {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        border: 1px solid var(--border);
        border-radius: 0.75rem;
        padding: 0.875rem 1rem;
        background: var(--card);
      }
      .metric-flat {
        border: none;
        background: var(--muted);
      }
      .tone-warn {
        color: var(--warning-ink);
      }
      .tone-late {
        color: var(--destructive-ink);
      }
      .tone-zero {
        color: var(--muted-foreground);
      }
      /* the account atom is wider than the bare name it replaced; cap it so
         the row action stays in view instead of scrolling off */
      .row-actions {
        display: inline-flex;
        gap: 0.25rem;
        align-items: center;
        justify-content: flex-end;
      }
      .cell-account {
        display: inline-flex;
        max-width: 11rem;
      }
      .m-label {
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--muted-foreground);
      }
      .m-value {
        font-size: 1.25rem;
        font-weight: 700;
        font-variant-numeric: tabular-nums;
        line-height: 1.1;
      }
      .filters {
        display: flex;
        gap: 0.375rem;
        flex-wrap: wrap;
      }
    </style>
  </template>
}
