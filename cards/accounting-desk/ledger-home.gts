// The books' home: headline figures computed from the statements and registers it links, and every
// report, register and closed month one click away. Nothing here is stored but the links.
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  linksToMany,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import BookIcon from '@cardstack/boxel-icons/book-open';
import { OpenBillsReport } from '../accounting/ledger-reports';
import { OpenInvoicesReport } from '../accounting/ledger-statements';
import { StockOnHandReport } from '../accounting/ledger-stock';
import {
  MonthClose,
  TrialBalance,
  ProfitAndLoss,
  BalanceSheet,
} from '../accounting/ledger-close';
import {
  FixedAssetRegister,
  Loan,
  TaxAgency,
  PayrollQuarter,
} from '../accounting/ledger-registers';
import { Form1099Report } from '../accounting/ledger-tax';
import { CashFlowStatement, YearClose } from '../accounting/ledger-year';
import {
  Sheet,
  Part,
  Strip,
  Fit,
  money,
  toneFor,
} from '../accounting/record-kit';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import {
  StatementTable,
  type StatementColumn as Col,
  type StatementRow as Line,
} from '../accounting/components/statement-table';

export class BooksHome extends CardDef {
  static displayName = 'Books';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field company = contains(StringField);
  @field profitAndLoss = linksTo(() => ProfitAndLoss);
  @field balanceSheet = linksTo(() => BalanceSheet);
  @field trialBalance = linksTo(() => TrialBalance);
  @field cashFlows = linksTo(() => CashFlowStatement);
  @field yearClose = linksTo(() => YearClose);
  @field openInvoices = linksTo(() => OpenInvoicesReport);
  @field openBills = linksTo(() => OpenBillsReport);
  @field inventory = linksTo(() => StockOnHandReport);
  @field fixedAssets = linksTo(() => FixedAssetRegister);
  @field form1099 = linksTo(() => Form1099Report);
  @field salesTax = linksTo(() => TaxAgency);
  @field loan = linksTo(() => Loan);
  @field closes = linksToMany(() => MonthClose, {
    query: { page: { size: 24 } },
  });
  @field payroll = linksToMany(() => PayrollQuarter, {
    query: { page: { size: 8 } },
  });
  @field cashMinor = contains(NumberField, {
    computeVia: function (this: BooksHome) {
      return (this.balanceSheet?.rows ?? [])
        .filter((r) => r?.account === '1000')
        .reduce((n, r) => n + (r!.amountMinor ?? 0), 0);
    },
  });
  @field closedCount = contains(NumberField, {
    computeVia: function (this: BooksHome) {
      return (this.closes ?? []).filter((c) => c?.closedBy).length;
    },
  });
  @field cardTitle = contains(StringField, {
    computeVia: function (this: BooksHome) {
      return this.company ?? 'Books';
    },
  });

  static isolated = class extends Component<typeof BooksHome> {
    get months() {
      return (
        (this.args.model.closes ?? []).filter(Boolean) as MonthClose[]
      ).sort((a, b) => (b.month ?? '').localeCompare(a.month ?? ''));
    }
    monthCols: Col[] = [
      { key: 'month', label: 'Month', kind: 'code' },
      { key: 'posted', label: 'Posted', kind: 'amount' },
      { key: 'checks', label: 'Checklist', kind: 'custom' },
      { key: 'by', label: 'Closed by', priority: 'secondary' },
    ];
    get monthRows(): Line[] {
      return this.months.map((c) => ({
        key: c.month ?? '',
        cells: {
          month: c.month,
          posted: c.debitMinor,
          checks: c.ready ? 'All checks pass' : 'Not ready',
          by: c.closedBy ?? 'Open',
        },
      }));
    }
    status = (v: unknown) => String(v ?? '');
    get tiles() {
      let m = this.args.model,
        p = m.profitAndLoss,
        b = m.balanceSheet,
        latest = this.months[0]?.month;
      let margin = p?.incomeMinor
        ? `${(((p.grossProfitMinor ?? 0) / p.incomeMinor) * 100).toFixed(1)}% gross margin`
        : '';
      return [
        {
          label: 'Net income',
          value: money(p?.netIncomeMinor),
          note: p?.cardTitle ?? '',
        },
        { label: 'Sales', value: money(p?.incomeMinor), note: margin },
        {
          label: 'Total assets',
          value: money(b?.assetsMinor),
          note: b?.balanced
            ? 'Balance sheet balances'
            : 'Balance sheet does not balance',
        },
        {
          label: 'Cash',
          value: money(m.cashMinor),
          note: 'Operating checking',
        },
        {
          label: 'Customers owe',
          value: money(m.openInvoices?.totalOpenMinor),
          note: 'Open invoices',
        },
        {
          label: 'We owe vendors',
          value: money(m.openBills?.totalOpenMinor),
          note: 'Open bills',
        },
        {
          label: 'Inventory',
          value: money(m.inventory?.totalCostMinor),
          note: 'At cost, FIFO',
        },
        {
          label: 'Months closed',
          value: String(m.closedCount ?? 0),
          note: latest ? `Through ${latest}` : '',
        },
      ];
    }
    <template>
      <Sheet
        @eyebrow='Books'
        @title={{@model.cardTitle}}
        @note='Every figure here is computed from posted cards: documents roll up into months, closed months into statements.'
      >
        <div class='tiles'>{{#each this.tiles as |t|}}<div class='tile'><span
                class='l'
              >{{t.label}}</span><b>{{t.value}}</b><span
                class='n'
              >{{t.note}}</span></div>{{/each}}</div>
        <Part @title='Statements'><div class='grid'><@fields.profitAndLoss
              @format='embedded'
            /><@fields.balanceSheet @format='embedded' /><@fields.trialBalance
              @format='embedded'
            /><@fields.cashFlows @format='embedded' /><@fields.yearClose
              @format='embedded'
            /></div></Part>
        <Part @title='Who owes what'><div class='grid'><@fields.openInvoices
              @format='embedded'
            /><@fields.openBills @format='embedded' /><@fields.salesTax
              @format='embedded'
            /><@fields.loan @format='embedded' /></div></Part>
        <Part @title='Registers and returns'><div
            class='grid'
          ><@fields.inventory @format='embedded' /><@fields.fixedAssets
              @format='embedded'
            /><@fields.form1099 @format='embedded' /></div></Part>
        <Part @title='Payroll'><div class='grid'>{{#each
              @fields.payroll
              as |Q|
            }}<Q @format='embedded' />{{/each}}</div></Part>
        <Part @title='Closed months'>
          <StatementTable
            @label='Closed months'
            @columns={{this.monthCols}}
            @rows={{this.monthRows}}
            @density='compact'
          >
            <:cell as |value|><StatusChip
                @value={{this.status value}}
                @tone={{toneFor (this.status value)}}
              /></:cell>
          </StatementTable>
        </Part>
      </Sheet>
      <style scoped>
        .tiles {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr));
          gap: 0.75rem;
          margin-bottom: 1.5rem;
        }
        .tile {
          display: grid;
          gap: 0.2rem;
          padding: 0.85rem 1rem;
          background: var(--muted);
          border-radius: var(--radius);
        }
        .tile .l {
          font-size: 0.6875rem;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        .tile b {
          font-family: var(--font-serif);
          font-size: 1.35rem;
          font-weight: 500;
        }
        .tile .n {
          font-size: 0.75rem;
          color: var(--muted-foreground);
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr));
          gap: 0.75rem;
        }
      </style>
    </template>
  };
  static embedded = class extends Component<typeof BooksHome> {
    <template>
      <Strip
        @eyebrow='Books'
        @title={{@model.cardTitle}}
        @figure={{money @model.cashMinor}}
        @meta='Cash'
      />
    </template>
  };
  static fitted = class extends Component<typeof BooksHome> {
    <template>
      <Fit
        @eyebrow='Books'
        @title={{@model.cardTitle}}
        @figure={{money @model.cashMinor}}
        @meta='Cash'
      />
    </template>
  };
}
