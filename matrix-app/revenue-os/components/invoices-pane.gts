import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn, get } from '@ember/helper';
import { gt } from '@cardstack/boxel-ui/helpers';
import type { CardDef } from '@cardstack/base/card-api';
import { Button } from '@cardstack/pretui/components/button';
import { SegmentedControl } from '@cardstack/pretui/components/segmented-control';
import PlusIcon from '@cardstack/boxel-icons/plus';
import { Table } from '@cardstack/pretui/components/table';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { LayoutControl } from '@cardstack/pretui/components/layout-control';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';
import { PageHead } from './page-head';
import { StatStrip } from './stat-strip';

interface TableColumn {
  key: string;
  label: string;
  align?: string;
  custom?: boolean;
  sortable?: boolean;
  value: (item: CardDef) => unknown;
  sortValue?: (item: CardDef) => unknown;
}
import {
  ExportButton,
  type ExportColumn,
} from '@cardstack/catalog/components/export';
import {
  ImportButton,
  type ImportColumn,
} from '@cardstack/catalog/components/import';
import {
  formatDay,
  toDate,
} from '@cardstack/catalog/fields/effective-period/effective-period-field';
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
  invoiceStatus,
  isBaseInvoice,
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
    return formatMoney(this.balanceOf(item), code).replace(/\.00$/, '');
  };

  invoiceTone = (item: CardDef) => {
    let s = invoiceStatus(item);
    return s === 'overdue'
      ? 'danger'
      : s === 'paid'
        ? 'success'
        : s === 'partial'
          ? 'warning'
          : s === 'sent' || s === 'viewed'
            ? 'info'
            : 'neutral';
  };
  amountOf = (item: CardDef) => {
    let { total, code } = sumLineItems((item as Invoice).lineItems);
    return total ? formatMoney(total, code).replace(/\.00$/, '') : '';
  };
  dueOf = (item: CardDef) => {
    let d = (item as Invoice).dueDate;
    return d ? formatDay(d) : '';
  };
  FORMS = [
    { name: 'full', minWidth: 9 },
    { name: 'menu', minWidth: 0 },
  ];
  PRIMARY_FORMS = [{ name: 'full', minWidth: 8 }];

  get stats() {
    let all = this.args.console.invoices;
    let open = all.filter((i) =>
      OPEN_INVOICE_STATUSES.includes(i.status ?? ''),
    );
    let balance = open
      .filter((i) => isBaseInvoice(i))
      .reduce((a, i) => a + outstandingBalance(i.lineItems, i.payments), 0);
    return [
      {
        label: 'Unpaid',
        value: open.length,
        hint: 'sent, viewed or part paid',
        tone: 'warning',
      },
      {
        label: 'Outstanding',
        value: formatMoney(balance, BASE_CURRENCY),
        hint: 'balance still due',
        tone: 'danger',
      },
      {
        label: 'Invoices',
        value: all.length,
        hint: 'on file',
        tone: 'neutral',
      },
    ];
  }

  get agingStats() {
    let tones: Record<string, string> = {
      ok: 'success',
      warn: 'warning',
      late: 'danger',
      zero: 'neutral',
    };
    return this.aging.map((b) => ({
      label: b.label,
      value: b.value,
      tone: tones[b.tone],
    }));
  }

  <template>
    <section class='pane'>
      <PageHead
        @title='Invoices'
        @subtitle='{{get (get this.stats '0') 'value'}} unpaid invoices'
      />
      {{#if @console.queriesSettled}}
        <StatStrip @stats={{this.stats}} @label='Invoice totals' />
        <StatStrip @stats={{this.agingStats}} @label='Aging' />
        <LayoutControl @label='Invoice filters and actions' as |lc|>
          <lc.Slot
            @id='filter'
            @priority={{2}}
            @forms={{this.FORMS}}
            @label='Show'
          >
            <SegmentedControl
              @label='Invoice filter'
              @options={{INVOICE_FILTERS}}
              @value={{@console.invoiceFilter}}
              @onValueChange={{@console.setInvoiceFilter}}
            />
          </lc.Slot>
          <span class='spacer'></span>
          {{#if @console.realm}}
            <lc.Slot
              @id='import'
              @priority={{1}}
              @forms={{this.FORMS}}
              @label='Import'
            >
              <ImportButton
                @cardType={{this.invoiceType}}
                @columns={{this.importColumns}}
                @commandContext={{@console.commandContext}}
                @realm={{@console.realm}}
                @onComplete={{@console.reportImport}}
              />
            </lc.Slot>
          {{/if}}
          <lc.Slot
            @id='export'
            @priority={{1}}
            @forms={{this.FORMS}}
            @label='Export'
          >
            <ExportButton
              @rows={{this.filteredInvoices}}
              @columns={{this.exportColumns}}
              @filename={{this.exportFilename}}
            />
          </lc.Slot>
          <lc.Slot
            @id='new'
            @priority={{0}}
            @pinned={{true}}
            @forms={{this.PRIMARY_FORMS}}
            @label='New invoice'
          >
            <Button
              @icon={{PlusIcon}}
              @appearance='solid'
              {{on 'click' @console.newInvoice}}
            >New invoice</Button>
          </lc.Slot>
        </LayoutControl>
        <div class='block'>
          <Table @label='Invoices' @framed={{false}}>
            <:head>
              <tr>
                <th scope='col'>Invoice #</th>
                <th scope='col'>Account</th>
                <th scope='col' class='num'>Amount</th>
                <th scope='col'>Status</th>
                <th scope='col'>Due</th>
                <th scope='col'><VisuallyHidden>Actions</VisuallyHidden></th>
              </tr>
            </:head>
            <:body>
              {{#each this.filteredInvoices key='id' as |item|}}
                <tr>
                  <td class='mono'>
                    <Button
                      @appearance='plain'
                      {{on 'click' (fn @console.openCard item)}}
                    >{{item.invoiceNumber}}</Button>
                  </td>
                  <td>
                    {{#let (this.accountOf item) as |account|}}
                      {{#if account}}
                        <Button
                          @appearance='plain'
                          title='Open {{account.name}} in Accounts'
                          {{on 'click' (fn @console.openAccountFor item)}}
                        >{{account.name}}</Button>
                      {{/if}}
                    {{/let}}
                  </td>
                  <td class='num mono'>{{this.amountOf item}}</td>
                  <td><StatusChip
                      @value={{invoiceStatus item}}
                      @tone={{this.invoiceTone item}}
                      @appearance='plain'
                    /></td>
                  <td class='mono'>{{this.dueOf item}}</td>
                  <td>
                    <span class='row-actions'>
                      {{#if (gt (this.balanceOf item) 0)}}
                        <Button
                          @appearance='outlined'
                          @disabled={{@console.busy}}
                          {{on 'click' (fn @console.recordBalancePayment item)}}
                        >Record {{this.balanceDisplay item}}</Button>
                      {{/if}}
                      <Button
                        @appearance='plain'
                        @disabled={{@console.busy}}
                        {{on 'click' (fn @console.duplicateCard item)}}
                      >Duplicate</Button>
                    </span>
                  </td>
                </tr>
              {{else}}
                <tr><td colspan='6' class='empty'>No invoices match this filter</td></tr>
              {{/each}}
            </:body>
          </Table>
        </div>
      {{else}}
        <p class='loading' role='status'>Loading invoices…</p>
      {{/if}}
    </section>
    <style scoped>
      .pane {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-sm);
      }
      .block {
        border: 1px solid var(--border);
        border-radius: var(--radius);
        background: var(--card);
        overflow-x: auto;
      }
      .spacer {
        flex: 1;
      }
      .num {
        text-align: end;
      }
      .mono {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        white-space: nowrap;
      }
      .row-actions {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        white-space: nowrap;
      }
      .empty,
      .loading {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .loading {
        margin: 0;
      }
    </style>
  </template>
}
