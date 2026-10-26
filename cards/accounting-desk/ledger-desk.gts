// Accord: the card-native books as one application, on Pret UI.
// Navigation follows QuickBooks Online's areas (Home, Sales, Purchases, Inventory, Banking, Payroll,
// Accounting, Reports, Close) so it feels familiar; every list is a live query of posted cards,
// every row opens a drawer with the document, what it posts and what can be done next, and the
// command palette (⌘K) reaches any page, report or "New" action in one step.
import {
  CardDef,
  Component,
  field,
  contains,
  linksTo,
  getRelationshipMembershipState,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { realmURL, codeRef, identifyCard } from '@cardstack/runtime-common';
import { tracked } from '@glimmer/tracking';
import { fn, concat } from '@ember/helper';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import BookIcon from '@cardstack/boxel-icons/book-open';
import HouseIcon from '@cardstack/boxel-icons/house';
import ReceiptIcon from '@cardstack/boxel-icons/receipt-text';
import WalletIcon from '@cardstack/boxel-icons/wallet';
import LandmarkIcon from '@cardstack/boxel-icons/landmark';
import UsersIcon from '@cardstack/boxel-icons/users';
import ChartIcon from '@cardstack/boxel-icons/chart-column';
import PackageIcon from '@cardstack/boxel-icons/package';
import ScaleIcon from '@cardstack/boxel-icons/scale';
import ChevronsRightIcon from '@cardstack/boxel-icons/chevrons-right';
import ListTreeIcon from '@cardstack/boxel-icons/list-tree';
import {
  StatementTable,
  type StatementColumn,
  type StatementRow,
} from '../accounting/components/statement-table';
import {
  Sidebar,
  SidebarGroup,
  SidebarItem,
  SidebarTrigger,
} from '@cardstack/pretui/components/sidebar';
import { Breadcrumb } from '@cardstack/pretui/components/breadcrumb';
import { CommandPalette } from '@cardstack/pretui/components/command-palette';
import { Menu } from '@cardstack/pretui/components/menu';
import type { MenuEntry } from '@cardstack/pretui/internal/menu';
import { Token } from '@cardstack/pretui/components/token';
import { Toaster, ToastStore } from '@cardstack/pretui/components/toaster';
import { Kbd } from '@cardstack/pretui/components/kbd';
import { Tabs } from '@cardstack/pretui/components/tabs';
import {
  StepList,
  type StepItem,
} from '@cardstack/pretui/components/step-list';
import { ButtonGroup } from '@cardstack/pretui/components/button-group';
import { Stat } from '@cardstack/pretui/components/stat';
import { Chart } from '@cardstack/pretui/components/chart';
import { BarList } from '@cardstack/pretui/components/bar-list';
import {
  DataTable,
  type DataColumn,
} from '@cardstack/pretui/components/data-table';
import { FilterChips } from '@cardstack/pretui/components/filter-chips';
import { SearchInput } from '@cardstack/pretui/components/search-input';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { Callout } from '@cardstack/pretui/components/callout';
import { Drawer } from '@cardstack/pretui/components/drawer';
import { Descriptions } from '@cardstack/pretui/components/descriptions';
import {
  ReadinessPanel,
  type ReadinessGate,
} from '@cardstack/pretui/components/readiness-panel';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Skeleton } from '@cardstack/pretui/components/skeleton';
import { Button } from '@cardstack/pretui/components/button';
import { Select } from '@cardstack/pretui/components/select';
import { operations } from '@cardstack/base/operations';
import { Ledger, Bill } from '../accounting/ledger-cards';
import {
  Invoice,
  InvoiceApplication,
  CustomerPayment,
  SalesReceipt,
  RefundReceipt,
  Deposit,
  CreditMemo,
  WriteOff,
} from '../accounting/ledger-sales';
import { BillPayment, PaymentApplication } from '../accounting/ledger-payments';
import { dueDateFor, PaymentTerm } from '../accounting/ledger-terms';
import PostToBooksCommand from '../accounting/commands/post-to-books-command';
import {
  isBookable,
  isPayable,
  toMinor,
  unbilledQuantities,
} from '../accounting/ledger-bridge';
import { Quote } from '@cardstack/catalog/cards/commerce/quote';
import { Invoice as CommerceInvoice } from '@cardstack/catalog/cards/commerce/invoice';
import { Payment as CommercePayment } from '@cardstack/catalog/cards/commerce/payment';
import { PurchaseOrder } from '@cardstack/catalog/cards/procurement/purchase-order';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import { VendorCredit, BankPayment } from '../accounting/ledger-cash';
import { Input } from '@cardstack/pretui/components/input';
import { FileTrigger } from '@cardstack/pretui/components/file-trigger';
import {
  BankTransaction,
  BankRule,
  bankLineState,
} from '../accounting/ledger-bank';
import {
  parseCsvStatement,
  parseOfxStatement,
  planImport,
  ruleFor,
  matchCandidates,
  readCsvHeader,
  COLUMN_FIELDS,
  type ColumnMap,
  type ParsedStatement,
  toMinor as statementMinor,
} from '../accounting/ledger-bank-statement';
import {
  bankKey,
  bookAt,
  lastRecOf,
  recFrom,
  recItems,
} from '../accounting/ledger-reconcile';
import {
  ProfitAndLoss,
  BalanceSheet,
  TrialBalance,
  BankReconciliation,
} from '../accounting/ledger-close';
import { Checkbox } from '@cardstack/pretui/components/checkbox';
import { CashFlowStatement, YearClose } from '../accounting/ledger-year';
import { OpenInvoicesReport } from '../accounting/ledger-statements';
import { OpenBillsReport } from '../accounting/ledger-reports';
import { StockOnHandReport, StockLot } from '../accounting/ledger-stock';
import {
  FixedAssetRegister,
  Loan,
  TaxAgency,
  TaxReturn,
} from '../accounting/ledger-registers';
import { Form1099Report } from '../accounting/ledger-tax';
import { PnlForecast } from '../accounting/ledger-forecast';
import {
  Budget,
  BudgetVsActual,
  MarginReport,
} from '../accounting/ledger-analysis';
import {
  SalesByCustomer,
  SalesByItem,
  ExpensesByVendor,
  GeneralLedger,
} from '../accounting/ledger-report-library';
import {
  KIND_LABEL,
  seqText,
  EntryPad,
  JournalMonth,
  journalPostings,
  JOURNAL_KIND,
  journalPostingFor,
} from '../accounting/ledger-journal';
import { settingsOf } from '../accounting/ledger-settings';
import {
  TaxCode,
  taxCodesOf,
  taxByAgency,
  plainTaxLines,
  percent,
  taxLinesFact,
} from '../accounting/ledger-tax-codes';
import { money, toneFor, Lines, AccordMark } from '../accounting/record-kit';

// @ts-expect-error TS1470 -- import.meta is valid in realm-served modules; only the CommonJS type-check rejects it
const here: string = import.meta.url;
type Kind = 'text' | 'mono' | 'money' | 'status' | 'qty' | 'count' | 'accounts';
interface Col {
  key: string;
  label: string;
  kind?: Kind;
  width?: string;
}
interface Row {
  key: string;
  card: any;
  [k: string]: unknown;
}
// `journal` names the posting kinds a page lists when its realm keeps an append-log journal: the rows
// then come from the month cards instead of a card per document ('*' lists every kind).
interface PageDef {
  id: string;
  area: string;
  label: string;
  blurb: string;
  module?: string;
  type?: string;
  cols?: Col[];
  row?: (c: any) => Record<string, unknown>;
  report?: string;
  post?: boolean;
  drafts?: boolean; // lists the drafts query instead of one type
  chips?: string[];
  journal?: string[];
}

// ── how each kind of record reads in a list ─────────────────────────────────
const SALE = (c: any) => ({
  number: c.docNo,
  date: c.date,
  party: c.customerId,
  status: c.state?.() ?? c.status,
  amount: c.totalMinor,
  open: c.openMinor,
});
const DOC = (c: any) => ({
  number: c.docNo,
  date: c.date,
  party: c.party?.() ?? '',
  status: c.state?.() ?? c.status,
  amount: c.totalMinor,
});
const BILL = (c: any) => ({
  number: c.billNo,
  date: c.date,
  party: c.vendorId,
  due: c.due,
  status:
    c.status !== 'posted'
      ? 'Draft'
      : c.voidDate
        ? 'Void'
        : (c.openMinor ?? 0) <= 0
          ? 'Paid'
          : (c.paidMinor ?? 0) > 0
            ? 'Partial'
            : 'Open',
  amount: c.totalMinor,
  open: c.openMinor,
});
const docCols: Col[] = [
  { key: 'number', label: 'No.', kind: 'mono', width: '11rem' },
  { key: 'date', label: 'Date', kind: 'mono', width: '8.25rem' },
  { key: 'party', label: 'Party' },
  { key: 'accounts', label: 'Accounts', kind: 'accounts' },
  { key: 'status', label: 'Status', kind: 'status', width: '8rem' },
  { key: 'amount', label: 'Amount', kind: 'money' },
];
const openCols: Col[] = [
  ...docCols,
  { key: 'open', label: 'Open', kind: 'money' },
];
const journalCols: Col[] = [
  { key: 'number', label: 'No.', kind: 'mono', width: '11rem' },
  { key: 'date', label: 'Date', kind: 'mono', width: '8.25rem' },
  { key: 'kindLabel', label: 'Kind', width: '9rem' },
  { key: 'party', label: 'Party' },
  { key: 'accounts', label: 'Accounts', kind: 'accounts' },
  { key: 'status', label: 'Status', kind: 'status', width: '7rem' },
  { key: 'amount', label: 'Amount', kind: 'money' },
];
const JOURNAL_CHIPS = ['Posted', 'Reversed', 'Reversal'];

const PAGES: PageDef[] = [
  {
    id: 'home',
    area: 'Home',
    label: 'Home',
    blurb: 'What needs doing, and how the business is doing.',
  },
  // Sales
  {
    id: 'invoices',
    area: 'Sales',
    label: 'Invoices',
    blurb:
      'Bills to customers. Paid down by customer payments, credits and write-offs.',
    module: '../accounting/ledger-sales',
    type: 'Invoice',
    cols: openCols,
    row: SALE,
    post: true,
    chips: ['Draft', 'Open', 'Partial', 'Paid', 'Written off', 'Void'],
  },
  {
    id: 'receipts',
    journal: ['sales-receipt'],
    area: 'Sales',
    label: 'Sales receipts',
    blurb: 'Sales paid at the time: the café and online orders.',
    module: '../accounting/ledger-sales',
    type: 'SalesReceipt',
    cols: docCols,
    row: SALE,
    post: true,
    chips: ['Draft', 'Undeposited', 'Deposited'],
  },
  {
    id: 'refunds',
    journal: ['refund-receipt'],
    area: 'Sales',
    label: 'Refund receipts',
    blurb: 'Sales paid back on the spot.',
    module: '../accounting/ledger-sales',
    type: 'RefundReceipt',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'payments',
    journal: ['customer-payment'],
    area: 'Sales',
    label: 'Customer payments',
    blurb:
      'Money received against invoices, waiting in Undeposited Funds until deposited.',
    module: '../accounting/ledger-sales',
    type: 'CustomerPayment',
    cols: docCols,
    row: SALE,
    post: true,
    chips: ['Draft', 'Undeposited', 'Deposited'],
  },
  {
    id: 'deposits',
    journal: ['deposit', 'payout'],
    area: 'Sales',
    label: 'Deposits & payouts',
    blurb: 'Bank deposits and card-processor payouts, net of fees.',
    module: '../accounting/ledger-sales',
    type: 'Deposit',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'credits',
    journal: ['credit-memo'],
    area: 'Sales',
    label: 'Credit memos',
    blurb: 'Allowances against an invoice.',
    module: '../accounting/ledger-sales',
    type: 'CreditMemo',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'writeoffs',
    journal: ['write-off'],
    area: 'Sales',
    label: 'Write-offs',
    blurb: 'Invoices written off as bad debt.',
    module: '../accounting/ledger-sales',
    type: 'WriteOff',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'customers',
    area: 'Sales',
    label: 'Customers',
    blurb: 'Who buys from you.',
    module: '../accounting/ledger-sales',
    type: 'Customer',
    cols: [
      { key: 'name', label: 'Customer' },
      { key: 'id', label: 'Id', kind: 'mono' },
      { key: 'channel', label: 'Channel' },
      { key: 'taxable', label: 'Sales tax' },
    ],
    row: (c) => ({
      name: c.name,
      id: c.customerId,
      channel: c.channel,
      taxable: c.defaultTaxCode
        ? `${c.defaultTaxCode}${c.shipState ? ' · ' + c.shipState : ''}`
        : c.taxable
          ? `Taxable${c.shipState ? ' · ' + c.shipState : ''}`
          : 'Exempt',
    }),
  },
  {
    id: 'taxreturns',
    area: 'Sales',
    label: 'Tax returns',
    blurb:
      "Each agency's sales tax by period. An open return shows the period's sales as they stand; filing records them and locks the period with the agency, and paying drafts the bank payment.",
    module: '../accounting/ledger-registers',
    type: 'TaxReturn',
    cols: [
      { key: 'agency', label: 'Agency', kind: 'mono' },
      { key: 'period', label: 'Period' },
      { key: 'status', label: 'Status' },
      { key: 'due', label: 'Due', kind: 'money' },
      { key: 'open', label: 'Open', kind: 'money' },
    ],
    row: (r) => ({
      agency: r.agencyId,
      period: `${r.periodStart ?? ''} to ${r.periodEnd ?? ''}`,
      status: r.status,
      due: r.dueMinor,
      open: r.openMinor,
    }),
  },
  {
    id: 'taxcodes',
    area: 'Sales',
    label: 'Tax codes',
    blurb:
      "The rates a sale is taxed at. Sales and their lines carry a code, and the books' settings hold the rates the realm checks against.",
    module: '../accounting/ledger-tax-codes',
    type: 'TaxCode',
    cols: [
      { key: 'name', label: 'Tax code' },
      { key: 'code', label: 'Code', kind: 'mono' },
      { key: 'rate', label: 'Rate' },
    ],
    row: (c) => ({
      name: c.name,
      code: c.code,
      rate: (c.rates ?? []).filter(Boolean).length
        ? percent(c.combinedPpm)
        : `Exempt${c.exemptReason ? ' · ' + c.exemptReason : ''}`,
    }),
  },
  // Purchases
  {
    id: 'bills',
    area: 'Purchases',
    label: 'Bills',
    blurb:
      'What vendors bill you. Paid down by bill payments and vendor credits.',
    module: '../accounting/ledger-cards',
    type: 'Bill',
    cols: [
      ...openCols.slice(0, 3),
      { key: 'due', label: 'Due', kind: 'mono', width: '8.25rem' },
      ...openCols.slice(3),
    ],
    row: BILL,
    post: true,
    chips: ['Draft', 'Open', 'Partial', 'Paid', 'Void'],
  },
  {
    id: 'billpayments',
    journal: ['bill-payment'],
    area: 'Purchases',
    label: 'Bill payments',
    blurb: 'Payments to vendors, each applied to the bills it pays.',
    module: '../accounting/ledger-payments',
    type: 'BillPayment',
    cols: docCols,
    row: (c) => ({
      number: c.paymentNo,
      date: c.date,
      party: c.vendorId,
      status:
        c.status === 'posted' || c.status === 'journaled' ? 'Posted' : 'Draft',
      amount: c.totalMinor,
    }),
    post: true,
  },
  {
    id: 'vendorcredits',
    journal: ['vendor-credit'],
    area: 'Purchases',
    label: 'Vendor credits',
    blurb: 'Credits from vendors, applied to their bills.',
    module: '../accounting/ledger-cash',
    type: 'VendorCredit',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'vendors',
    area: 'Purchases',
    label: 'Vendors',
    blurb: 'Who you buy from.',
    module: '../accounting/ledger-cards',
    type: 'Vendor',
    cols: [
      { key: 'name', label: 'Vendor' },
      { key: 'id', label: 'Id', kind: 'mono' },
      { key: 'tracked', label: '1099' },
    ],
    row: (c) => ({
      name: c.name,
      id: c.vendorId,
      tracked: c.track1099 ? 'Tracked' : '',
    }),
  },
  // Inventory
  {
    id: 'lots',
    area: 'Inventory',
    label: 'Stock lots',
    blurb: 'Every FIFO cost layer: what is left and what it cost.',
    module: '../accounting/ledger-stock',
    type: 'StockLot',
    cols: [
      { key: 'sku', label: 'Product', kind: 'mono' },
      { key: 'lot', label: 'Lot', kind: 'mono' },
      { key: 'date', label: 'Received', kind: 'mono', width: '8.25rem' },
      { key: 'status', label: 'Status', kind: 'status', width: '7rem' },
      { key: 'qty', label: 'Remaining', kind: 'qty' },
      { key: 'amount', label: 'Remaining cost', kind: 'money' },
    ],
    row: (c) => ({
      sku: c.sku,
      lot: c.lot,
      date: c.received,
      status: (c.remainingQty ?? 0) > 0 ? 'On hand' : 'Used up',
      qty: c.remainingQty,
      amount: c.remainingCostMinor,
    }),
    chips: ['On hand', 'Used up'],
  },
  {
    id: 'roasts',
    journal: ['roast'],
    area: 'Inventory',
    label: 'Roast batches',
    blurb: 'Green coffee and packaging in, roasted lots out, at cost.',
    module: '../accounting/ledger-stock',
    type: 'RoastBatch',
    cols: docCols,
    row: DOC,
  },
  {
    id: 'fulfillments',
    journal: ['fulfillment'],
    area: 'Inventory',
    label: 'Fulfillments',
    blurb: 'What each sale shipped, and its cost of goods sold.',
    module: '../accounting/ledger-stock',
    type: 'Fulfillment',
    cols: docCols,
    row: DOC,
  },
  {
    id: 'landed',
    journal: ['landed-cost'],
    area: 'Inventory',
    label: 'Landed costs',
    blurb: 'Freight and duty moved into the lots.',
    module: '../accounting/ledger-stock',
    type: 'LandedCost',
    cols: docCols,
    row: DOC,
  },
  {
    id: 'counts',
    journal: ['count'],
    area: 'Inventory',
    label: 'Count adjustments',
    blurb: 'What physical counts found missing.',
    module: '../accounting/ledger-stock',
    type: 'CountAdjustment',
    cols: docCols,
    row: DOC,
  },
  {
    id: 'products',
    area: 'Inventory',
    label: 'Products',
    blurb: 'Green coffee, roasted coffee, packaging and services.',
    module: '../accounting/ledger-cards',
    type: 'Item',
    cols: [
      { key: 'name', label: 'Product' },
      { key: 'sku', label: 'SKU', kind: 'mono' },
      { key: 'type', label: 'Type' },
    ],
    row: (c) => ({ name: c.productName, sku: c.sku, type: c.productType }),
  },
  // Banking
  {
    id: 'bankfeed',
    area: 'Banking',
    label: 'Bank feed',
    blurb:
      'Lines from bank and card statements, waiting to be matched, added to the books or excluded.',
    module: '../accounting/ledger-bank',
    type: 'BankTransaction',
    cols: [
      { key: 'date', label: 'Date', kind: 'mono', width: '8.25rem' },
      { key: 'description', label: 'Description' },
      { key: 'account', label: 'Bank', kind: 'mono', width: '5.5rem' },
      { key: 'suggested', label: 'Suggested', kind: 'mono', width: '7rem' },
      { key: 'status', label: 'Status', kind: 'status', width: '8rem' },
      { key: 'amount', label: 'Amount', kind: 'money' },
    ],
    row: (c) => ({
      number: c.externalId,
      date: c.date,
      description: c.cardTitle,
      account: c.account,
      status: bankLineState(c.status),
      amount: c.amountMinor,
    }),
    chips: ['For review', 'Matched', 'Added', 'Excluded'],
  },
  {
    id: 'bankrules',
    area: 'Banking',
    label: 'Bank rules',
    blurb:
      'What each kind of bank line usually is. Rules suggest an account; a person still adds the line.',
    module: '../accounting/ledger-bank',
    type: 'BankRule',
    cols: [
      { key: 'name', label: 'Rule' },
      { key: 'when', label: 'Description contains' },
      { key: 'category', label: 'Suggests', kind: 'mono', width: '7rem' },
      { key: 'priority', label: 'Priority', kind: 'count', width: '6rem' },
      { key: 'status', label: 'Status', kind: 'status', width: '7rem' },
    ],
    row: (c) => ({
      name: c.cardTitle,
      when: c.descriptionContains ?? '',
      category: c.category,
      priority: c.priority ?? 0,
      status: c.active === false ? 'Inactive' : 'Active',
    }),
    chips: ['Active', 'Inactive'],
  },
  {
    id: 'bankimports',
    area: 'Banking',
    label: 'Statement imports',
    blurb:
      'Each statement file imported: what came in, what was already there, and what was refused.',
    module: '../accounting/ledger-bank',
    type: 'BankStatementImport',
    cols: [
      { key: 'number', label: 'Import', kind: 'mono', width: '11rem' },
      { key: 'date', label: 'Imported', kind: 'mono', width: '8.25rem' },
      { key: 'account', label: 'Bank', kind: 'mono', width: '5.5rem' },
      { key: 'file', label: 'File' },
      { key: 'accepted', label: 'New', kind: 'count', width: '5rem' },
      { key: 'skipped', label: 'Already in', kind: 'count', width: '6rem' },
    ],
    row: (c) => ({
      number: c.importNo,
      date: c.importedOn,
      account: c.account,
      file: c.fileName,
      accepted: c.acceptedCount ?? 0,
      skipped: c.skippedCount ?? 0,
    }),
  },
  {
    id: 'recs',
    area: 'Banking',
    label: 'Reconciliations',
    blurb: 'Each statement against the books. The difference must be $0.',
    module: '../accounting/ledger-close',
    type: 'BankReconciliation',
    cols: [
      { key: 'account', label: 'Account', kind: 'mono', width: '6rem' },
      { key: 'date', label: 'Statement', kind: 'mono', width: '8.25rem' },
      { key: 'status', label: 'Status', kind: 'status', width: '8rem' },
      { key: 'ending', label: 'Statement balance', kind: 'money' },
      { key: 'book', label: 'Book balance', kind: 'money' },
      { key: 'amount', label: 'Difference', kind: 'money' },
    ],
    row: (c) => ({
      account: c.account,
      date: c.statementDate,
      status: c.status === 'reconciled' ? 'Reconciled' : 'Open',
      ending: c.endingBalanceMinor,
      book: c.bookBalanceMinor,
      amount: c.differenceMinor,
    }),
  },
  {
    id: 'transfers',
    journal: ['transfer'],
    area: 'Banking',
    label: 'Transfers',
    blurb: 'Money moved between accounts, including card statement payments.',
    module: '../accounting/ledger-cash',
    type: 'Transfer',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'cardcharges',
    journal: ['card-charge'],
    area: 'Banking',
    label: 'Card charges',
    blurb: 'Purchases on the company card, each with its receipt.',
    module: '../accounting/ledger-cash',
    type: 'CardCharge',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'bankpayments',
    journal: ['bank-payment'],
    area: 'Banking',
    label: 'Taxes & remittances',
    blurb: 'Payroll tax remittances, sales tax payments and owner draws.',
    module: '../accounting/ledger-cash',
    type: 'BankPayment',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'loanpayments',
    journal: ['loan-payment'],
    area: 'Banking',
    label: 'Loan payments',
    blurb: 'Principal and interest on the equipment loan.',
    module: '../accounting/ledger-cash',
    type: 'LoanPayment',
    cols: docCols,
    row: DOC,
    post: true,
  },
  // Payroll
  {
    id: 'payroll',
    journal: ['payroll'],
    area: 'Payroll',
    label: 'Payroll runs',
    blurb:
      'Each pay run synced from Gusto: wages, withholding, employer taxes, net pay.',
    module: '../accounting/ledger-cash',
    type: 'PayrollRun',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'quarters',
    area: 'Payroll',
    label: 'Quarters',
    blurb: 'Payroll by quarter, for the 941.',
    module: '../accounting/ledger-registers',
    type: 'PayrollQuarter',
    cols: [
      { key: 'q', label: 'Quarter', kind: 'mono' },
      { key: 'runs', label: 'Runs', kind: 'count' },
      { key: 'amount', label: 'Gross wages', kind: 'money' },
      { key: 'withheld', label: 'Withheld', kind: 'money' },
      { key: 'employer', label: 'Employer taxes', kind: 'money' },
    ],
    row: (c) => ({
      q: `${c.year} Q${c.quarter}`,
      runs: c.runCount,
      amount: c.grossMinor,
      withheld: c.withholdingMinor,
      employer: c.employerTaxMinor,
    }),
  },
  // Accounting
  {
    id: 'journal',
    journal: ['*'],
    area: 'Accounting',
    label: 'Journal',
    blurb:
      'Every posting in the append-only journal: checked and stamped by the realm as it posted, corrected only by reversing entries.',
    cols: journalCols,
    chips: JOURNAL_CHIPS,
  },
  {
    id: 'journalmonths',
    area: 'Accounting',
    label: 'Journal months',
    blurb:
      'One card per month holds its postings. A closed month is sealed with the hash of its .jsonl export.',
    module: '../accounting/ledger-journal',
    type: 'JournalMonth',
    cols: [
      { key: 'month', label: 'Month', kind: 'mono', width: '6rem' },
      { key: 'status', label: 'Status', kind: 'status', width: '7rem' },
      { key: 'count', label: 'Postings', kind: 'count' },
      { key: 'seal', label: 'Seal', kind: 'mono' },
      { key: 'amount', label: 'Debits', kind: 'money' },
    ],
    row: (c) => ({
      month: c.month,
      status:
        c.status === 'sealed'
          ? 'Sealed'
          : c.status === 'closed'
            ? 'Closed'
            : 'Open',
      count: c.count,
      seal: c.sealHash
        ? `${c.sealCount} lines · ${String(c.sealHash).slice(0, 12)}…`
        : '',
      amount: c.debitMinor,
    }),
  },
  {
    id: 'pads',
    area: 'Accounting',
    label: 'Entry pads',
    blurb:
      'Entries being written. Each pad posts into its month’s journal and clears; nothing on a pad is in the books yet.',
    module: '../accounting/ledger-journal',
    type: 'EntryPad',
    cols: [
      { key: 'kind', label: 'Kind', width: '10rem' },
      { key: 'date', label: 'Date', kind: 'mono', width: '8.25rem' },
      { key: 'memo', label: 'Memo' },
      { key: 'lines', label: 'Lines', kind: 'count' },
      { key: 'last', label: 'Last posted', kind: 'mono' },
    ],
    row: (c) => ({
      kind: KIND_LABEL[c.kind] ?? c.kind,
      date: c.date,
      memo: c.memo ?? '',
      lines: (c.lines ?? []).length,
      last: c.lastPosted ?? '',
    }),
  },
  {
    id: 'inbox',
    area: 'Accounting',
    label: 'From operations',
    blurb:
      'Won quotes, invoices, payments and purchase orders from the rest of the business. Post one to draft it in the books, linked back to where it came from.',
  },
  {
    id: 'drafts',
    area: 'Accounting',
    label: 'Drafts',
    blurb:
      'Everything entered but not posted. Drafts change nothing until they post.',
    drafts: true,
    cols: [
      { key: 'number', label: 'No.', kind: 'mono', width: '11rem' },
      { key: 'date', label: 'Date', kind: 'mono', width: '8.25rem' },
      { key: 'kindLabel', label: 'Kind', width: '9rem' },
      { key: 'party', label: 'Party' },
      { key: 'amount', label: 'Amount', kind: 'money' },
    ],
    row: (c) => ({
      number: c.docNo ?? c.billNo ?? c.paymentNo,
      date: c.date,
      kindLabel: c.constructor?.displayName ?? '',
      party: c.party?.() ?? c.vendorId ?? '',
      status: 'Draft',
      amount: c.totalMinor ?? c.amountMinor,
    }),
    post: true,
  },
  {
    id: 'journals',
    journal: ['journal'],
    area: 'Accounting',
    label: 'Journal entries',
    blurb: 'Adjusting entries. A reviewer is required at or above materiality.',
    module: '../accounting/ledger-cash',
    type: 'JournalEntry',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'coa',
    area: 'Accounting',
    label: 'Chart of accounts',
    blurb:
      'Every account by type, with its balance at the last close. Pick one to read its register.',
  },
  {
    id: 'accounts',
    area: 'Accounting',
    label: 'Chart of accounts (list)',
    blurb: 'Every account, with its balance from the closed months.',
    module: '../accounting/ledger-cards',
    type: 'LedgerAccount',
    cols: [
      { key: 'code', label: 'No.', kind: 'mono', width: '5rem' },
      { key: 'name', label: 'Account' },
      { key: 'type', label: 'Type', width: '8rem' },
      { key: 'amount', label: 'Balance', kind: 'money' },
    ],
    row: (c) => ({ code: c.code, name: c.name, type: c.type }),
  },
  {
    id: 'scheduled',
    journal: ['scheduled'],
    area: 'Accounting',
    label: 'Scheduled entries',
    blurb: 'Prepaids released, deferred revenue earned, accruals reversed.',
    module: '../accounting/ledger-cash',
    type: 'ScheduledEntry',
    cols: docCols,
    row: DOC,
    post: true,
  },
  {
    id: 'schedules',
    area: 'Accounting',
    label: 'Schedules',
    blurb: 'What each schedule has released and what is left.',
    module: '../accounting/ledger-registers',
    type: 'Schedule',
    cols: [
      { key: 'id', label: 'Schedule', kind: 'mono' },
      { key: 'kind', label: 'Kind' },
      { key: 'posted', label: 'Posted' },
      { key: 'amount', label: 'Remaining', kind: 'money' },
    ],
    row: (c) => ({
      id: c.scheduleId,
      kind: c.kind,
      posted: `${c.postedCount ?? 0} of ${c.periods ?? 0}`,
      amount: c.remainingMinor,
    }),
  },
  {
    id: 'assets',
    area: 'Accounting',
    label: 'Fixed assets',
    blurb: 'Cost, depreciation taken and book value.',
    module: '../accounting/ledger-registers',
    type: 'FixedAsset',
    cols: [
      { key: 'name', label: 'Asset' },
      { key: 'id', label: 'Id', kind: 'mono' },
      { key: 'status', label: 'Status', kind: 'status', width: '7rem' },
      { key: 'cost', label: 'Cost', kind: 'money' },
      { key: 'amount', label: 'Book value', kind: 'money' },
    ],
    row: (c) => ({
      name: c.name,
      id: c.assetId,
      status: c.disposedOn ? 'Disposed' : 'In service',
      cost: c.costMinor,
      amount: c.bookValueMinor,
    }),
  },
  {
    id: 'depreciation',
    journal: ['depreciation'],
    area: 'Accounting',
    label: 'Depreciation runs',
    blurb: 'Monthly depreciation by asset.',
    module: '../accounting/ledger-cash',
    type: 'DepreciationRun',
    cols: docCols,
    row: DOC,
    post: true,
  },
  // Reports
  {
    id: 'r-sales-customer',
    area: 'Reports',
    label: 'Sales by customer',
    blurb:
      'Income by customer for a period, on the accrual or cash basis, against an earlier period.',
    report: 'salesByCustomer',
  },
  {
    id: 'r-sales-item',
    area: 'Reports',
    label: 'Sales by product',
    blurb:
      'Quantity and amount sold by product: invoices, and sales less refund receipts.',
    report: 'salesByItem',
  },
  {
    id: 'r-expenses-vendor',
    area: 'Reports',
    label: 'Expenses by vendor',
    blurb:
      'Cost of goods and expenses by vendor for a period, on the accrual or cash basis.',
    report: 'expensesByVendor',
  },
  {
    id: 'r-gl',
    area: 'Reports',
    label: 'General ledger',
    blurb:
      'Every posting in a period, account by account, with running balances.',
    report: 'generalLedger',
  },
  {
    id: 'r-pnl',
    area: 'Reports',
    label: 'Profit and loss',
    blurb: 'Income, cost of goods sold and expenses for 2026.',
    report: 'profitAndLoss',
  },
  {
    id: 'r-bva',
    area: 'Reports',
    label: 'Budget against actuals',
    blurb:
      'Closed months against the budget, with year-to-date variance by account (Excel SUMIF) and the accounts over budget flagged.',
    report: 'budgetVsActual',
  },
  {
    id: 'r-budget',
    area: 'Reports',
    label: 'Budget',
    blurb:
      'The year’s budget: each account’s annual amount, spread over the months with Excel ROUND.',
    report: 'budget',
  },
  {
    id: 'r-margin',
    area: 'Reports',
    label: 'Product and customer margin',
    blurb:
      'Gross margin by product, customer and channel from sale lines and FIFO lot cost, reconciled to the P&L (Excel SUMIF, PERCENTRANK.INC).',
    report: 'margin',
  },
  {
    id: 'r-fc',
    area: 'Reports',
    label: 'P&L forecast · trend',
    blurb:
      'Mid-year forecast: closed months so far, the rest projected with Excel FORECAST, beside how the year actually closed.',
    report: 'forecast',
  },
  {
    id: 'r-fc2',
    area: 'Reports',
    label: 'P&L forecast · run rate',
    blurb: 'The same forecast with AVERAGE as a run rate.',
    report: 'forecastRunRate',
  },
  {
    id: 'r-bs',
    area: 'Reports',
    label: 'Balance sheet',
    blurb: 'Assets, liabilities and equity at year end.',
    report: 'balanceSheet',
  },
  {
    id: 'r-cf',
    area: 'Reports',
    label: 'Cash flows',
    blurb: 'Where the cash came from and went, indirect method.',
    report: 'cashFlows',
  },
  {
    id: 'r-tb',
    area: 'Reports',
    label: 'Trial balance',
    blurb: 'Every account, debits equal to credits.',
    report: 'trialBalance',
  },
  {
    id: 'r-ar',
    area: 'Reports',
    label: 'Receivables aging',
    blurb: 'What customers owe, by how late.',
    report: 'openInvoices',
  },
  {
    id: 'r-ap',
    area: 'Reports',
    label: 'Payables aging',
    blurb: 'What you owe vendors, by how late.',
    report: 'openBills',
  },
  {
    id: 'r-inv',
    area: 'Reports',
    label: 'Inventory valuation',
    blurb: 'What is on hand at FIFO cost.',
    report: 'inventory',
  },
  {
    id: 'r-fa',
    area: 'Reports',
    label: 'Fixed asset register',
    blurb: 'Assets in service, tied to the ledger.',
    report: 'fixedAssets',
  },
  {
    id: 'r-tax',
    area: 'Reports',
    label: 'Sales tax liability',
    blurb: 'Collected, paid and owed, tied to the ledger.',
    report: 'salesTax',
  },
  {
    id: 'r-1099',
    area: 'Reports',
    label: '1099-NEC',
    blurb: 'Vendors to file for, and W-9 status.',
    report: 'form1099',
  },
  {
    id: 'r-loan',
    area: 'Reports',
    label: 'Loan',
    blurb: 'Balance, principal and interest, tied to the ledger.',
    report: 'loan',
  },
  // Close
  {
    id: 'closes',
    area: 'Close',
    label: 'Month close',
    blurb:
      'Each month issued at close with a checklist. Totals are stored, so statements read them.',
    module: '../accounting/ledger-close',
    type: 'MonthClose',
    cols: [
      { key: 'month', label: 'Month', kind: 'mono', width: '6rem' },
      { key: 'status', label: 'Status', kind: 'status', width: '9rem' },
      { key: 'checks', label: 'Checklist' },
      { key: 'by', label: 'Closed by' },
      { key: 'amount', label: 'Posted', kind: 'money' },
    ],
    row: (c) => ({
      month: c.month,
      status: c.closedBy ? 'Closed' : 'Open',
      checks: (c.checks ?? []).length
        ? (c.checks ?? []).every((x: string) => x?.startsWith('pass'))
          ? 'All checks pass'
          : `${(c.checks ?? []).filter((x: string) => !x?.startsWith('pass')).length} to fix`
        : '',
      by: c.closedBy ?? '',
      amount: c.debitMinor,
    }),
  },
  {
    id: 'r-year',
    area: 'Close',
    label: 'Year-end close',
    blurb: 'The year, signed off.',
    report: 'yearClose',
  },
];
// ── workspaces: the rail lists a few places to work, then the things in the current one ─────────
// (the pattern of Nucleus LMS's Classroom Central: the rail is a roster of subjects with live
// figures, picking one scopes every list, and related views open on top or beside in their own stack)
type SubjectKind =
  | 'customers'
  | 'vendors'
  | 'accounts'
  | 'products'
  | 'months'
  | 'reports'
  | 'chart';
interface Launcher {
  label: string;
  page: string;
}
interface Workspace {
  id: string;
  label: string;
  icon: unknown;
  pages: string[];
  subject?: SubjectKind;
  subjectLabel?: string;
  overview?: string;
  launchers: Launcher[];
  pipeline?: boolean;
}
const REPORT_PAGES = PAGES.filter((p) => p.report && p.area === 'Reports').map(
  (p) => p.id,
);
const WORKSPACES: Workspace[] = [
  {
    id: 'today',
    label: 'Today',
    icon: HouseIcon,
    pages: ['home'],
    subject: 'months',
    subjectLabel: 'Months',
    overview: 'Latest month',
    launchers: [
      { label: 'Profit and loss', page: 'r-pnl' },
      { label: 'Balance sheet', page: 'r-bs' },
    ],
    pipeline: true,
  },
  {
    id: 'sales',
    label: 'Sales',
    icon: ReceiptIcon,
    pages: [
      'invoices',
      'receipts',
      'refunds',
      'payments',
      'deposits',
      'credits',
      'writeoffs',
      'customers',
      'taxreturns',
      'taxcodes',
    ],
    subject: 'customers',
    subjectLabel: 'Customers',
    overview: 'All customers',
    launchers: [
      { label: 'Receivables aging', page: 'r-ar' },
      { label: 'Margin', page: 'r-margin' },
    ],
  },
  {
    id: 'purchases',
    label: 'Purchases',
    icon: WalletIcon,
    pages: ['bills', 'billpayments', 'vendorcredits', 'vendors'],
    subject: 'vendors',
    subjectLabel: 'Vendors',
    overview: 'All vendors',
    launchers: [
      { label: 'Payables aging', page: 'r-ap' },
      { label: '1099-NEC', page: 'r-1099' },
    ],
  },
  {
    id: 'banking',
    label: 'Banking',
    icon: LandmarkIcon,
    pages: [
      'bankfeed',
      'recs',
      'transfers',
      'cardcharges',
      'bankpayments',
      'loanpayments',
      'bankrules',
      'bankimports',
    ],
    subject: 'accounts',
    subjectLabel: 'Accounts',
    overview: 'All accounts',
    launchers: [
      { label: 'Cash flows', page: 'r-cf' },
      { label: 'Sales tax', page: 'r-tax' },
      { label: 'Loan', page: 'r-loan' },
    ],
  },
  {
    id: 'stock',
    label: 'Stock',
    icon: PackageIcon,
    pages: ['lots', 'roasts', 'fulfillments', 'landed', 'counts', 'products'],
    subject: 'products',
    subjectLabel: 'Products',
    overview: 'All products',
    launchers: [{ label: 'Inventory valuation', page: 'r-inv' }],
  },
  {
    id: 'payroll',
    label: 'Payroll',
    icon: UsersIcon,
    pages: ['payroll', 'quarters'],
    launchers: [{ label: 'Profit and loss', page: 'r-pnl' }],
  },
  {
    id: 'chart',
    label: 'Accounts',
    icon: ListTreeIcon,
    pages: ['coa'],
    subject: 'chart',
    subjectLabel: 'Accounts',
    overview: 'Whole chart',
    launchers: [
      { label: 'Trial balance', page: 'r-tb' },
      { label: 'Balance sheet', page: 'r-bs' },
      { label: 'Profit and loss', page: 'r-pnl' },
    ],
  },
  {
    id: 'books',
    label: 'Books',
    icon: ScaleIcon,
    pages: [
      'journal',
      'drafts',
      'inbox',
      'journalmonths',
      'pads',
      'journals',
      'scheduled',
      'schedules',
      'assets',
      'depreciation',
      'closes',
      'r-year',
    ],
    subject: 'months',
    subjectLabel: 'Months',
    overview: 'Every month',
    launchers: [
      { label: 'Trial balance', page: 'r-tb' },
      { label: 'Profit and loss', page: 'r-pnl' },
      { label: 'Fixed assets', page: 'r-fa' },
    ],
    pipeline: true,
  },
  {
    id: 'reports',
    label: 'Reports',
    icon: ChartIcon,
    pages: REPORT_PAGES,
    subject: 'reports',
    subjectLabel: 'Statements',
    launchers: [],
  },
];
const spaceById = new Map(WORKSPACES.map((w) => [w.id, w]));
// The chart's sections, in statement order, and which side each one's balance normally sits on.
const CHART_SECTIONS: { key: string; label: string; debit: boolean }[] = [
  { key: 'asset', label: 'Assets', debit: true },
  { key: 'liability', label: 'Liabilities', debit: false },
  { key: 'equity', label: 'Equity', debit: false },
  { key: 'income', label: 'Income', debit: false },
  { key: 'cogs', label: 'Cost of goods sold', debit: true },
  { key: 'expense', label: 'Expenses', debit: true },
];
// The accounts documents post to without being told: posting fails without them.
const CONTROL: [string, string][] = [
  ['1000', 'operating bank'],
  ['1010', 'undeposited funds'],
  ['1100', 'receivables'],
  ['1200', 'green inventory'],
  ['1210', 'roasted inventory'],
  ['2000', 'payables'],
  ['2200', 'sales tax'],
  ['2300', 'payroll liabilities'],
  ['3200', 'retained earnings'],
  ['5000', 'cost of goods'],
  ['5200', 'inventory adjustments'],
];
const spaceOf = (page: string, prefer?: string) =>
  prefer && spaceById.get(prefer)?.pages.includes(page)
    ? prefer
    : (WORKSPACES.find((w) => w.pages.includes(page))?.id ?? 'today');
// A tab says the kind of record; the workspace already says the area.
const TAB: Record<string, string> = {
  receipts: 'Receipts',
  payments: 'Payments',
  deposits: 'Deposits',
  credits: 'Credit memos',
  writeoffs: 'Write-offs',
  billpayments: 'Payments',
  vendorcredits: 'Credits',
  bankfeed: 'Feed',
  bankrules: 'Rules',
  bankimports: 'Imports',
  recs: 'Reconciliations',
  cardcharges: 'Card charges',
  bankpayments: 'Remittances',
  loanpayments: 'Loan',
  lots: 'Lots',
  roasts: 'Roasts',
  landed: 'Landed cost',
  counts: 'Counts',
  payroll: 'Runs',
  journalmonths: 'Months',
  pads: 'Pads',
  journals: 'Entries',
  scheduled: 'Scheduled',
  accounts: 'Chart',
  assets: 'Assets',
  depreciation: 'Depreciation',
  closes: 'Closes',
  'r-year': 'Year end',
};
// A rail figure: short, because the page beside it has the exact one. Zero stays blank.
const compact = (minor: number | undefined) =>
  minor
    ? (minor / 100).toLocaleString('en-US', {
        style: 'currency',
        currency: 'USD',
        notation: 'compact',
        maximumFractionDigits: 1,
      })
    : '';
const monthLabel = (
  ym: string | undefined,
  opts: Intl.DateTimeFormatOptions = { month: 'long', year: 'numeric' },
) => {
  let d = new Date(`${ym}-15T00:00:00Z`);
  return isNaN(d.getTime())
    ? String(ym ?? '')
    : d.toLocaleString('en-US', { ...opts, timeZone: 'UTC' });
};
const pageById = new Map(PAGES.map((p) => [p.id, p]));
const pageByType = new Map(
  PAGES.filter((p) => p.type).map((p) => [p.type as string, p]),
);

const moneyOf = (v: unknown) => (typeof v === 'number' ? money(v) : '');
// The cards a getCards resource holds.
const instancesOf = (r: unknown): any[] =>
  (((r as any)?.instances ?? []) as any[]).filter(Boolean);
const BANK_LINE_PAGE = 500;
const qtyOf = (v: unknown) =>
  typeof v === 'number'
    ? (v / 1000).toLocaleString('en-US', { maximumFractionDigits: 3 })
    : '';
const isKind = (col: unknown, k: Kind) => (col as { kind?: Kind })?.kind === k;
const cellOf = (row: Row, col: unknown) => row[(col as Col).key];
const rowKey = (r: Row) => r.key;
const dollars = (minor: number | undefined) => (minor ?? 0) / 100;
// The most rows a search answers in one page.
const MAX_PAGE = 2000;
const TAKEN_PAGE = MAX_PAGE;
const SECTION: Record<string, string> = {
  bank: 'asset',
  ar: 'asset',
  asset: 'asset',
  inventory: 'asset',
  clearing: 'asset',
  fixed: 'asset',
  contra: 'asset',
  ap: 'liability',
  cc: 'liability',
  liability: 'liability',
  longterm: 'liability',
  equity: 'equity',
  income: 'income',
  cogs: 'cogs',
  expense: 'expense',
  other: 'expense',
};
const MONTH = (ym: string | undefined) => {
  let d = new Date(`${ym}-15T00:00:00Z`);
  return isNaN(d.getTime())
    ? ''
    : d.toLocaleString('en-US', { month: 'short', timeZone: 'UTC' });
};
const addDays = (day: string, n: number) => {
  let t = Date.parse(day + 'T00:00:00Z');
  return isNaN(t) ? '' : new Date(t + n * 864e5).toISOString().slice(0, 10);
};

// Inside the Boxel app an Escape that closes a native <dialog> also reaches the card stack and
// closes the card. While a drawer or the palette is open, take Escape at the window first.
const escapeGuard = modifier(
  (_el: Element, [active, close]: [boolean, () => void]) => {
    if (!active) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopImmediatePropagation();
        close();
      }
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  },
);

class LedgerAppView extends Component<typeof LedgerApp> {
  @tracked page = String((this.args.model as any)?.startPage || 'home');
  @tracked space = spaceOf(this.page);
  @tracked subject = ''; // the customer, vendor, account, product or month the workspace is scoped to
  @tracked query = '';
  @tracked chip = '';
  @tracked selected: Row | undefined;
  @tracked paletteOpen = false;
  @tracked newKind = '';
  @tracked newParty = '';
  @tracked error = '';
  toasts = new ToastStore();
  // Success is a toast; a refusal stays on the page, as an error, until the next action.
  notify = (title: string, message?: string) => {
    this.toasts.show({ title, message, tone: 'success' });
  };
  @tracked busy = false;

  // ── data: the current page's records, the closed months, and the chart ──
  get realms() {
    let r = (this.args.model as any)?.[realmURL]?.href;
    return r ? [r] : [];
  }
  // Reference data (accounts, customers, vendors) can live in the main ledger when this realm holds only the journal.
  get refRealms() {
    let r = this.realms,
      l = (this.args.model.ledger as any)?.[realmURL]?.href;
    return l && !r.includes(l) ? [...r, l] : r;
  }
  get def() {
    return pageById.get(this.page) ?? PAGES[0];
  }
  @tracked pageNo = 0;
  get listQuery() {
    let d = this.def;
    return d.module && d.type
      ? {
          filter: { type: codeRef(here, d.module, d.type) },
          page: { size: 100, number: this.pageNo },
        }
      : {
          filter: {
            type: codeRef(here, '../accounting/ledger-close', 'MonthClose'),
          },
          page: { size: 1 },
        };
  }
  listData = this.args.context?.getCards(
    this,
    () => this.listQuery as never,
    () => this.realms,
    { isLive: true },
  );
  closeData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: codeRef(here, '../accounting/ledger-close', 'MonthClose'),
        },
        page: { size: 100 },
      }) as never,
    () => this.realms,
    { isLive: true },
  );
  accountData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: codeRef(here, '../accounting/ledger-cards', 'LedgerAccount'),
        },
        page: { size: 100 },
      }) as never,
    () => this.refRealms,
    { isLive: true },
  );
  billData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          every: [
            { type: codeRef(here, '../accounting/ledger-cards', 'Bill') },
            {
              on: codeRef(here, '../accounting/ledger-cards', 'Bill'),
              eq: { status: 'posted' },
            },
            {
              on: codeRef(here, '../accounting/ledger-cards', 'Bill'),
              range: { openMinor: { gt: 0 } },
            },
          ],
        },
        page: { size: 100 },
      }) as never,
    () => this.realms,
    { isLive: true },
  );
  // Invoices and bills posted in the open months of books with none closed: they stay cards, so an
  // open month's figures so far add them to its journal's.
  get openFrom() {
    if (this.closes.length) return '';
    let m = this.journalMonths.find((j) => j.status === 'open')?.month;
    return m ? `${m}-01` : '';
  }
  openDocsData = this.args.context?.getCards(
    this,
    () => {
      let from = this.openFrom;
      if (!from) return undefined;
      let posted = (module: string, name: string) => ({
        every: [
          { type: codeRef(here, module, name) },
          { on: codeRef(here, module, name), eq: { status: 'posted' } },
          { on: codeRef(here, module, name), range: { date: { gte: from } } },
        ],
      });
      return {
        filter: {
          any: [
            posted('../accounting/ledger-sales', 'Invoice'),
            posted('../accounting/ledger-cards', 'Bill'),
          ],
        },
        page: { size: 500 },
      } as never;
    },
    () => this.realms,
    { isLive: true },
  );
  invoiceData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          every: [
            { type: codeRef(here, '../accounting/ledger-sales', 'Invoice') },
            {
              on: codeRef(here, '../accounting/ledger-sales', 'Invoice'),
              eq: { status: 'posted' },
            },
            {
              on: codeRef(here, '../accounting/ledger-sales', 'Invoice'),
              range: { openMinor: { gt: 0 } },
            },
          ],
        },
        page: { size: 100 },
      }) as never,
    () => this.realms,
    { isLive: true },
  );
  // ── from operations: commerce and procurement documents, and which are already in the books ──
  opsQuery = (card: typeof CardDef, eq?: Record<string, string>) => () => {
    let type = identifyCard(card);
    return this.page === 'inbox' && type
      ? ({
          filter: eq ? { every: [{ type }, { on: type, eq }] } : { type },
          page: { size: 100 },
        } as never)
      : undefined;
  };
  // Only the books documents made from a source, which is what the inbox reads.
  bookedQuery = (card: typeof CardDef, links: string[]) => () => {
    let type = identifyCard(card);
    return this.page === 'inbox' && type
      ? ({
          filter: {
            every: [
              { type },
              {
                any: links.map((l) => ({
                  on: type,
                  not: { eq: { [`${l}.id`]: null } },
                })),
              },
            ],
          },
          page: { size: 500 },
        } as never)
      : undefined;
  };
  opsQuotes = this.args.context?.getCards(
    this,
    this.opsQuery(Quote, { status: 'won' }),
    () => this.realms,
    { isLive: true },
  );
  opsInvoices = this.args.context?.getCards(
    this,
    this.opsQuery(CommerceInvoice),
    () => this.realms,
    { isLive: true },
  );
  opsPayments = this.args.context?.getCards(
    this,
    this.opsQuery(CommercePayment),
    () => this.realms,
    { isLive: true },
  );
  opsOrders = this.args.context?.getCards(
    this,
    this.opsQuery(PurchaseOrder),
    () => this.realms,
    { isLive: true },
  );
  bookedInvoices = this.args.context?.getCards(
    this,
    this.bookedQuery(Invoice, ['quote', 'sourceInvoice']),
    () => this.realms,
    { isLive: true },
  );
  bookedBills = this.args.context?.getCards(
    this,
    this.bookedQuery(Bill, ['purchaseOrder', 'sourceInvoice']),
    () => this.realms,
    { isLive: true },
  );
  bookedCustomerPayments = this.args.context?.getCards(
    this,
    this.bookedQuery(CustomerPayment, ['sourcePayment']),
    () => this.realms,
    { isLive: true },
  );
  bookedBillPayments = this.args.context?.getCards(
    this,
    this.bookedQuery(BillPayment, ['sourcePayment']),
    () => this.realms,
    { isLive: true },
  );
  get inboxCols(): StatementColumn[] {
    return [
      { key: 'doc', label: 'Document' },
      { key: 'kind', label: 'Kind', width: '10rem' },
      { key: 'amount', label: 'Amount', kind: 'amount', width: '9rem' },
      { key: 'action', label: '', width: '10rem' },
    ];
  }
  // How many books documents link each source.
  get bookedLinks() {
    let list = (r: unknown) =>
      (((r as any)?.instances ?? []) as any[]).filter(Boolean);
    let links = new Map<string, number>();
    for (let [docs, keys] of [
      [this.bookedInvoices, ['quote', 'sourceInvoice']],
      [this.bookedBills, ['purchaseOrder', 'sourceInvoice']],
      [this.bookedCustomerPayments, ['sourcePayment']],
      [this.bookedBillPayments, ['sourcePayment']],
    ] as const)
      for (let d of list(docs))
        for (let k of keys) {
          let id = linkedId(d, k);
          if (id) links.set(id, (links.get(id) ?? 0) + 1);
        }
    return links;
  }
  // A source posted this session, with how many books documents linked it then: until the index
  // shows another, its row reads as in the books, so a second click can't draft it twice.
  @tracked justPosted = new Map<string, number>();
  isPending = (id: string) =>
    this.justPosted.has(id) &&
    this.justPosted.get(id) === (this.bookedLinks.get(id) ?? 0);
  get inboxRows(): StatementRow[] {
    let list = (r: unknown) =>
      (((r as any)?.instances ?? []) as any[]).filter(Boolean);
    let booked = new Set(this.bookedLinks.keys()),
      viaInvoice = new Set<string>();
    // A quote or purchase order is in the books through a commerce invoice raised from it, too.
    for (let i of list(this.opsInvoices))
      if (booked.has(i.id)) {
        let via = linkedId(i, isPayable(i) ? 'purchaseOrder' : 'quote');
        if (via) viaInvoice.add(via);
      }
    let billsByOrder = new Map<string, any[]>();
    for (let b of list(this.bookedBills)) {
      let po = linkedId(b, 'purchaseOrder');
      if (po && !b.voidDate)
        billsByOrder.set(po, [...(billsByOrder.get(po) ?? []), b]);
    }
    let lineTotal = (items: any[] | undefined, quantities?: number[]) =>
      (items ?? []).reduce(
        (n, l, i) =>
          n +
          (Number(quantities ? quantities[i] : l?.quantity) || 0) *
            (Number(l?.unitPrice?.amount) || 0),
        0,
      );
    let row = (
      card: any,
      kind: string,
      total: number,
      inBooks: boolean,
      waiting?: string,
    ) => {
      inBooks ||= this.isPending(card.id);
      return {
        key: card.id,
        selectable: !inBooks && !waiting,
        data: { inbox: card.id },
        cells: {
          doc: card.cardTitle ?? card.id,
          kind,
          amount: toMinor(total),
          action: inBooks ? 'In the books' : (waiting ?? 'Post to the books'),
        },
      };
    };
    return [
      ...list(this.opsQuotes).map((q) =>
        row(
          q,
          'Quote won',
          lineTotal(q.lineItems),
          booked.has(q.id) || viaInvoice.has(q.id),
        ),
      ),
      ...list(this.opsInvoices)
        .filter((i) => isBookable(i))
        .map((i) => {
          let payable = isPayable(i),
            via = linkedId(i, payable ? 'purchaseOrder' : 'quote');
          return row(
            i,
            payable ? 'Vendor invoice' : 'Invoice',
            lineTotal(i.lineItems),
            booked.has(i.id) || (!!via && booked.has(via)),
          );
        }),
      ...list(this.opsPayments).map((p) =>
        row(p, 'Payment', Number(p.amount?.amount) || 0, booked.has(p.id)),
      ),
      ...list(this.opsOrders).map((o) => {
        let toBill = unbilledQuantities(
          o.lineItems ?? [],
          o.receivedQuantities ?? [],
          (billsByOrder.get(o.id) ?? []).flatMap((b) =>
            (b.lines ?? []).filter(Boolean),
          ),
        );
        let amount = lineTotal(o.lineItems, toBill),
          billed = booked.has(o.id);
        return row(
          o,
          'Purchase order',
          amount,
          viaInvoice.has(o.id) || (billed && amount <= 0),
          !billed && amount <= 0 ? 'Nothing received' : undefined,
        );
      }),
    ];
  }
  postToBooks = async (row: StatementRow) => {
    if (this.busy || this.isPending(row.key)) return;
    let card = [
      this.opsQuotes,
      this.opsInvoices,
      this.opsPayments,
      this.opsOrders,
    ]
      .flatMap((r) => ((r as any)?.instances ?? []) as any[])
      .find((c) => c?.id === row.key);
    let commandContext = this.args.context?.commandContext;
    if (!card || !commandContext) return;
    this.busy = true;
    this.error = '';
    try {
      let result = await new PostToBooksCommand(commandContext).execute({
        source: card,
        ledger: this.args.model.ledger,
        date: this.nextOpen || undefined,
      } as never);
      this.justPosted = new Map(this.justPosted).set(
        row.key,
        this.bookedLinks.get(row.key) ?? 0,
      );
      this.notify('Drafted in the books', (result as any)?.message);
      let draft = (result as any)?.draft;
      if (draft) this.args.viewCard?.(draft, 'edit');
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  // Bills and bill payments aren't LedgerDocuments, so their drafts are asked for alongside.
  draftData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          any: [
            ['../accounting/ledger-document', 'LedgerDocument'],
            ['../accounting/ledger-cards', 'Bill'],
            ['../accounting/ledger-payments', 'BillPayment'],
          ].map(([m, t]) => ({
            every: [
              { type: codeRef(here, m, t) },
              { on: codeRef(here, m, t), eq: { status: 'draft' } },
            ],
          })),
        },
        page: { size: 100 },
      }) as never,
    () => this.realms,
    { isLive: true },
  );
  customerData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: codeRef(here, '../accounting/ledger-sales', 'Customer'),
        },
        page: { size: 100 },
      }) as never,
    () => this.refRealms,
    { isLive: true },
  );
  // The documents that stay cards (invoices, bills, the opening balances), for the account registers;
  // the journal months are already loaded. Each register filters these in memory by account.
  docQuery =
    (module: string, type: string, page = 0) =>
    () =>
      ({
        filter: { type: codeRef(here, module, type) },
        page: { size: 100, number: page },
      }) as never;
  regInvoices = this.args.context?.getCards(
    this,
    this.docQuery('../accounting/ledger-sales', 'Invoice'),
    () => this.realms,
    { isLive: true },
  );
  regBills0 = this.args.context?.getCards(
    this,
    this.docQuery('../accounting/ledger-cards', 'Bill', 0),
    () => this.realms,
    { isLive: true },
  );
  regBills1 = this.args.context?.getCards(
    this,
    this.docQuery('../accounting/ledger-cards', 'Bill', 1),
    () => this.realms,
    { isLive: true },
  );
  regOpenings = this.args.context?.getCards(
    this,
    this.docQuery('../accounting/ledger-opening', 'OpeningBalances'),
    () => this.realms,
    { isLive: true },
  );
  get regDocs(): any[] {
    return [
      this.regInvoices,
      this.regBills0,
      this.regBills1,
      this.regOpenings,
    ].flatMap((d) =>
      (((d as any)?.instances ?? []) as any[]).filter(
        (x) => x && x.status === 'posted',
      ),
    );
  }
  itemData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: { type: codeRef(here, '../accounting/ledger-cards', 'Item') },
        page: { size: 100 },
      }) as never,
    () => this.refRealms,
    { isLive: true },
  );
  recData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: codeRef(
            here,
            '../accounting/ledger-close',
            'BankReconciliation',
          ),
        },
        page: { size: 100 },
      }) as never,
    () => this.realms,
    { isLive: true },
  );
  vendorData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: { type: codeRef(here, '../accounting/ledger-cards', 'Vendor') },
        page: { size: 100 },
      }) as never,
    () => this.refRealms,
    { isLive: true },
  );

  journalData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: codeRef(here, '../accounting/ledger-journal', 'JournalMonth'),
        },
        page: { size: 100 },
      }) as never,
    () => this.realms,
    { isLive: true },
  );
  get journalMonths(): any[] {
    return (((this.journalData as any)?.instances ?? []) as any[])
      .filter(Boolean)
      .sort((a, b) =>
        String(a.month ?? '').localeCompare(String(b.month ?? '')),
      );
  }
  get usesJournal() {
    return !!this.def.journal && this.journalMonths.length > 0;
  }
  get loading() {
    if (this.def.journal && (this.journalData as any)?.isLoading !== false)
      return true;
    let data = this.def.drafts ? this.draftData : this.listData;
    return this.usesJournal ? false : (data as any)?.isLoading !== false;
  }
  // A journal page's rows: the postings of the kinds it lists, from every month card. A reversal is
  // listed with the kind of the posting it reverses.
  get journalRows(): Row[] {
    let kinds = this.def.journal ?? [],
      all = kinds.includes('*'),
      names = this.accountTypes,
      out: Row[] = [];
    for (let m of this.journalMonths) {
      let posts = ((m.postings ?? []) as any[]).filter(Boolean),
        bySeq = new Map(posts.map((p) => [p.seq, p])),
        reversed = new Set(posts.map((p) => p.reverses).filter(Boolean));
      for (let p of posts) {
        let kind =
          p.kind === 'reversal'
            ? (bySeq.get(p.reverses)?.kind ?? 'reversal')
            : p.kind;
        if (!all && !kinds.includes(kind)) continue;
        let codes = [
          ...new Set(
            ((p.lines ?? []) as any[]).map((l) => l?.account).filter(Boolean),
          ),
        ].sort() as string[];
        let skus = [
          ...new Set(
            ((p.items ?? []) as any[]).map((i) => i?.sku).filter(Boolean),
          ),
        ].join(' ');
        out.push({
          skus,
          key: `${m.month}#${p.seq}`,
          card: m,
          posting: p,
          month: m,
          number: p.source || seqText(m.month, p.seq),
          seq: seqText(m.month, p.seq),
          date: p.date,
          party: p.party ?? '',
          memo: p.memo ?? '',
          kindLabel: KIND_LABEL[p.kind] ?? p.kind,
          status:
            p.kind === 'reversal'
              ? 'Reversal'
              : reversed.has(p.seq)
                ? 'Reversed'
                : 'Posted',
          amount:
            (p.kind === 'reversal' ? -1 : 1) *
            ((p.lines ?? []) as any[]).reduce(
              (n, l) => n + (l?.debitMinor ?? 0),
              0,
            ),
          accounts: codes.join(' '),
          accountNames: codes
            .map((a) => (names.get(a) as any)?.name ?? '')
            .join(' '),
        });
      }
    }
    return out;
  }
  get chips() {
    return this.usesJournal ? JOURNAL_CHIPS : this.def.chips;
  }

  // ── the bank feed: rules, statement imports, and each line's review ──
  rulesData = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: codeRef(here, '../accounting/ledger-bank', 'BankRule'),
        },
        page: { size: 100 },
      }) as never,
    () => this.refRealms,
    { isLive: true },
  );
  // The open reconciliation's account's matched and added lines in its statement period: the ticks start
  // from them.
  bankLineData = this.args.context?.getCards(
    this,
    () => {
      let r = this.selRec,
        line = codeRef(here, '../accounting/ledger-bank', 'BankTransaction'),
        from = r
          ? recFrom(r as never, instancesOf(this.recData), this.closes)
          : '';
      return {
        filter: {
          every: [
            { type: line },
            { on: line, eq: { account: r?.account ?? '' } },
            {
              on: line,
              range: {
                date: {
                  ...(from ? { gt: from } : {}),
                  lte: r?.statementDate ?? '',
                },
              },
            },
            {
              any: ['matched', 'added'].map((status) => ({
                on: line,
                eq: { status },
              })),
            },
          ],
        },
        page: { size: BANK_LINE_PAGE },
      } as never;
    },
    () => this.realms,
    { isLive: true },
  );
  // Lines on the selected line's account already matched or added near its date: the postings they
  // name aren't offered again, whichever page of the feed they're on.
  takenData = this.args.context?.getCards(
    this,
    () => {
      let c = this.selBank,
        line = codeRef(here, '../accounting/ledger-bank', 'BankTransaction'),
        at = Date.parse(`${c?.date ?? ''}T00:00:00Z`),
        day = (n: number) =>
          Number.isNaN(at)
            ? ''
            : new Date(at + n * 86400000).toISOString().slice(0, 10);
      return {
        filter: {
          every: [
            { type: line },
            { on: line, eq: { account: c?.account ?? '' } },
            { on: line, range: { date: { gte: day(-14), lte: day(14) } } },
            {
              any: ['matched', 'added'].map((status) => ({
                on: line,
                eq: { status },
              })),
            },
          ],
        },
        page: { size: TAKEN_PAGE },
      } as never;
    },
    () => this.realms,
    { isLive: true },
  );
  get bankRules(): BankRule[] {
    return (((this.rulesData as any)?.instances ?? []) as BankRule[]).filter(
      Boolean,
    );
  }
  get chartAccounts(): any[] {
    return (((this.accountData as any)?.instances ?? []) as any[])
      .filter(Boolean)
      .sort((a, b) => String(a.code ?? '').localeCompare(String(b.code ?? '')));
  }
  get bankAccountOptions() {
    return this.chartAccounts
      .filter((a) => a.type === 'bank' || a.type === 'cc')
      .map((a) => ({ value: a.code, label: `${a.code} · ${a.name}` }));
  }
  get isBankFeed() {
    return this.page === 'bankfeed';
  }

  @tracked importOpen = false;
  @tracked importAccount = '';
  @tracked importFile:
    | { name: string; text: string; format: string; hash: string }
    | undefined;
  @tracked importColumns: ColumnMap | undefined;
  @tracked importDayFirst = false;
  @tracked importFlip = false;
  openImport = () => {
    this.importOpen = true;
    this.error = '';
    if (!this.importAccount)
      this.importAccount = this.bankAccountOptions[0]?.value ?? '';
  };
  closeImport = () => {
    this.importOpen = false;
    this.importFile = undefined;
    this.importColumns = undefined;
  };
  setImportAccount = (v: string) => {
    this.importAccount = v;
  };
  pickStatement = async (files: File[]) => {
    let file = files[0];
    if (!file) return;
    let bytes = await file.arrayBuffer(),
      text = new TextDecoder().decode(bytes),
      digest = await crypto.subtle.digest('SHA-256', bytes),
      hash = [...new Uint8Array(digest)]
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('');
    let format =
      /\.(ofx|qfx)$/i.test(file.name) || /<OFX>/i.test(text) ? 'ofx' : 'csv';
    this.importFile = { name: file.name, text, format, hash };
    this.importColumns =
      format === 'csv' ? readCsvHeader(text).columns : undefined;
    // A card statement goes to a card account unless one is already chosen.
    if (format === 'ofx' && parseOfxStatement(text).card) {
      let current = this.chartAccounts.find(
        (a) => a.code === this.importAccount,
      );
      if (current?.type !== 'cc')
        this.importAccount =
          this.chartAccounts.find((a) => a.type === 'cc')?.code ??
          this.importAccount;
    }
  };
  get importHeader(): string[] {
    let f = this.importFile;
    return f?.format === 'csv' ? readCsvHeader(f.text).header : [];
  }
  dateOrderOptions = [
    { value: 'mdy', label: 'Month first (01/31/2027)' },
    { value: 'dmy', label: 'Day first (31/01/2027)' },
  ];
  signOptions = [
    { value: 'negative', label: 'Money out is negative' },
    { value: 'positive', label: 'Money out is positive (some card issuers)' },
  ];
  get dateOrder() {
    return this.importDayFirst ? 'dmy' : 'mdy';
  }
  get signOrder() {
    return this.importFlip ? 'positive' : 'negative';
  }
  setDateOrder = (v: string) => {
    this.importDayFirst = v === 'dmy';
  };
  setSignOrder = (v: string) => {
    this.importFlip = v === 'positive';
  };
  get headerOptions() {
    return [
      { value: '', label: 'Not in this file' },
      ...this.importHeader.map((h, i) => ({ value: String(i), label: h })),
    ];
  }
  get columnChoices() {
    let map = this.importColumns ?? {};
    return COLUMN_FIELDS.map((f) => ({
      key: f.key,
      label: f.label,
      value: map[f.key] == null ? '' : String(map[f.key]),
      set: (v: string) => {
        this.importColumns = {
          ...(this.importColumns ?? {}),
          [f.key]: v === '' ? undefined : Number(v),
        };
      },
    }));
  }
  get parsedStatement(): ParsedStatement | undefined {
    let f = this.importFile;
    if (!f) return undefined;
    let options = {
      columns: this.importColumns ?? {},
      dayFirst: this.importDayFirst,
      flipSigns: this.importFlip,
    };
    return f.format === 'ofx'
      ? parseOfxStatement(f.text, options)
      : parseCsvStatement(f.text, options);
  }
  get importRange() {
    let dates = (this.parsedStatement?.lines ?? []).map((l) => l.date).sort();
    return dates.length ? { first: dates[0], last: dates.at(-1)! } : undefined;
  }
  // The lines already imported for the account under the file's bank IDs: what a re-import is checked
  // against, wherever their dates fall.
  get importIds(): string[] {
    return (this.parsedStatement?.lines ?? []).map((l) => l.externalId);
  }
  knownData = this.args.context?.getCards(
    this,
    () => {
      let ids = this.importIds,
        ref = codeRef(here, '../accounting/ledger-bank', 'BankTransaction');
      return (
        ids.length && this.importAccount
          ? {
              filter: {
                every: [
                  { type: ref },
                  { on: ref, eq: { account: this.importAccount } },
                  {
                    any: ids.map((externalId) => ({
                      on: ref,
                      eq: { externalId },
                    })),
                  },
                ],
              },
              page: { size: Math.min(ids.length, MAX_PAGE) },
            }
          : {
              filter: {
                type: codeRef(here, '../accounting/ledger-close', 'MonthClose'),
              },
              page: { size: 1 },
            }
      ) as never;
    },
    () => this.realms,
    { isLive: true },
  );
  // Only lines of this account and this file count, so a result left over from the previous file or
  // account never stands in for this one's.
  get knownLines(): BankTransaction[] {
    let ids = new Set(this.importIds);
    return (((this.knownData as any)?.instances ?? []) as any[]).filter(
      (c) =>
        c instanceof BankTransaction &&
        c.account === this.importAccount &&
        ids.has(c.externalId ?? ''),
    );
  }
  get importPlan() {
    let parsed = this.parsedStatement;
    if (!parsed) return undefined;
    return planImport(
      parsed,
      this.knownLines.map((k) => ({
        externalId: k.externalId ?? '',
        date: k.date ?? '',
        amountMinor: k.amountMinor ?? 0,
        description: k.description ?? '',
      })),
    );
  }
  get importSummary() {
    let plan = this.importPlan,
      range = this.importRange;
    if (!plan) return [];
    return [
      { label: 'New lines', value: String(plan.accepted.length) },
      { label: 'Already imported', value: String(plan.skipped.length) },
      { label: 'Refused', value: String(plan.rejected.length) },
      ...(range
        ? [{ label: 'Dates', value: `${range.first} to ${range.last}` }]
        : []),
    ];
  }
  get importRefusals() {
    return (this.importPlan?.rejected ?? []).slice(0, 8);
  }
  get importBlocked(): string {
    let plan = this.importPlan;
    if (!this.importAccount) return 'Choose the account this statement is for.';
    if (!plan) return 'Choose a statement file.';
    if (this.importIds.length && (this.knownData as any)?.isLoading)
      return 'Checking what is already imported…';
    if (this.importIds.length > MAX_PAGE)
      return `A file can hold at most ${MAX_PAGE} lines. Split it by month.`;
    if (plan.accepted.length > 400)
      return 'A file can bring in at most 400 new lines. Split it by month.';
    if (!plan.accepted.length) return 'Nothing new to import.';
    return '';
  }
  commitImport = async () => {
    let plan = this.importPlan,
      f = this.importFile,
      ledger = this.args.model.ledger as any;
    if (!plan || !f || this.importBlocked) return;
    this.busy = true;
    this.error = '';
    try {
      if (!ledger) throw new Error('This app is not linked to its ledger.');
      let contentHash = f.hash,
        now = new Date(),
        importedOn = [
          now.getFullYear(),
          String(now.getMonth() + 1).padStart(2, '0'),
          String(now.getDate()).padStart(2, '0'),
        ].join('-');
      let importNo = `IMP-${Date.now().toString(36).toUpperCase()}`,
        account = this.importAccount,
        range = this.importRange!;
      await (operations(ledger) as any).atomic((b: any) => [
        // Lines another import brought in since this file was read refuse the whole batch.
        b
          .on(
            b.find(
              {
                every: [
                  { type: BankTransaction },
                  { on: BankTransaction, eq: { account } },
                  {
                    any: plan!.accepted.map((l) => ({
                      on: BankTransaction,
                      eq: { externalId: l.externalId },
                    })),
                  },
                ],
              },
              { expect: 'many' },
            ),
          )
          .refuseReimport(),
        b.enterBankImport({
          importNo,
          account,
          fileName: f!.name,
          format: f!.format,
          contentHash,
          importedOn,
          firstDate: range.first,
          lastDate: range.last,
          acceptedCount: plan!.accepted.length,
          skippedCount: plan!.skipped.length,
          rejected: plan!.rejected.map((r) => ({
            row: r.row,
            reason: r.reason,
          })),
        }),
        ...plan!.accepted.map((l) =>
          b.enterBankLine({
            account,
            externalId: l.externalId,
            date: l.date,
            description: l.description,
            amountMinor: l.amountMinor,
            reference: l.reference || null,
            payee: l.payee || null,
            importNo,
          }),
        ),
      ]);
      this.notify(
        `Imported ${plan.accepted.length} line${plan.accepted.length === 1 ? '' : 's'}`,
        `${plan.skipped.length} already imported, ${plan.rejected.length} refused. The new lines are waiting for review.`,
      );
      this.closeImport();
      this.chip = 'For review';
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  get selBank(): BankTransaction | undefined {
    return this.sel instanceof BankTransaction ? this.sel : undefined;
  }
  get bankForReview() {
    let c = this.selBank;
    return !!c && (c.status ?? 'for-review') === 'for-review';
  }
  get bankExcluded() {
    return this.selBank?.status === 'excluded';
  }
  get bankSuggestion() {
    let c = this.selBank;
    return c ? ruleFor(this.bankRules, c) : undefined;
  }
  // The choice is kept per line, so opening another line starts from its own suggestion.
  @tracked bankChoice:
    | { id: string; account: string; reason: string }
    | undefined;
  get bankCategory() {
    let c = this.selBank,
      choice = this.bankChoice?.id === c?.id ? this.bankChoice : undefined;
    return choice?.account || this.bankSuggestion?.category || '';
  }
  get bankExcludeReason() {
    return this.bankChoice?.id === this.selBank?.id
      ? (this.bankChoice?.reason ?? '')
      : '';
  }
  setBankCategory = (v: string) => {
    this.bankChoice = {
      id: this.selBank?.id ?? '',
      account: v,
      reason: this.bankExcludeReason,
    };
  };
  setBankExcludeReason = (v: string) => {
    this.bankChoice = {
      id: this.selBank?.id ?? '',
      account: this.bankCategory,
      reason: v,
    };
  };
  // Receivables, payables, inventory and clearing accounts move only through the documents that
  // track them; a bank line added straight to one would leave the agings and stock out of step.
  get categoryOptions() {
    let bank = this.selBank?.account;
    return this.chartAccounts
      .filter(
        (a) =>
          a.code !== bank &&
          !['ar', 'ap', 'inventory', 'clearing'].includes(a.type),
      )
      .map((a) => ({ value: a.code, label: `${a.code} · ${a.name}` }));
  }
  // Money out is a debit to the account chosen and a credit to the bank; money in the other way round.
  get bankEntry() {
    let c = this.selBank,
      account = this.bankCategory;
    if (!c || !account) return undefined;
    let amount = Math.abs(c.amountMinor ?? 0),
      out = (c.amountMinor ?? 0) < 0,
      rule = this.bankSuggestion,
      party = c.payee || rule?.payee || null,
      cls = rule?.category === account ? rule?.cls || null : null;
    let line = (code: string, dr: number, cr: number, extra = {}) => ({
      account: code,
      debitMinor: dr,
      creditMinor: cr,
      date: null,
      cls: null,
      loc: null,
      party: null,
      doc: null,
      ...extra,
    });
    let other = line(account, out ? amount : 0, out ? 0 : amount, {
      cls,
      party,
    });
    let bank = line(c.account ?? '', out ? 0 : amount, out ? amount : 0);
    return {
      key: this.bankKey(c),
      // Money between two of the company's own bank or card accounts is a transfer.
      kind: ['bank', 'cc'].includes(
        (this.accountTypes.get(account) as any)?.type,
      )
        ? 'transfer'
        : out
          ? 'expense'
          : 'bank-deposit',
      date: c.date,
      memo: c.description ?? null,
      party,
      source: c.externalId ?? null,
      lines: out ? [other, bank] : [bank, other],
      facts: [
        { key: 'Bank line', value: c.externalId ?? '' },
        ...(c.reference ? [{ key: 'Reference', value: c.reference }] : []),
        ...(rule?.category === account
          ? [{ key: 'Rule', value: rule?.name ?? '' }]
          : []),
      ],
      items: [],
      preparer: null,
      reviewer: null,
    };
  }
  // A full page may have left out a line that took a posting, so nothing is offered rather than a
  // posting that's already matched.
  get takenFull() {
    return (
      (((this.takenData as any)?.instances ?? []) as any[]).length >= TAKEN_PAGE
    );
  }
  // What's already in the books this line could be: a posting on its account (so a transfer or payout
  // isn't entered twice), or an open invoice or bill it pays in full.
  get bankMatches(): { key: string; label: string; doc?: any }[] {
    let c = this.selBank;
    if (!c || !this.bankForReview || this.takenFull) return [];
    let taken = new Set(
      (((this.takenData as any)?.instances ?? []) as any[])
        .filter((x) => x instanceof BankTransaction && x.matchedKey)
        .map((x) => x.matchedKey as string),
    );
    let postings = this.journalMonths.flatMap((m) => {
      let all = ((m.postings ?? []) as any[]).filter(Boolean),
        reversed = new Set(all.map((p) => p.reverses).filter(Boolean));
      return all.filter((p) => !reversed.has(p.seq) && !p.reverses);
    });
    let amount = c.amountMinor ?? 0;
    let docs = (
      amount > 0
        ? instancesOf(this.invoiceData).filter((i) => i.openMinor === amount)
        : instancesOf(this.billData).filter((b) => b.openMinor === -amount)
    ).map((d) => ({
      key: `doc:${d.id}`,
      label:
        amount > 0
          ? `Invoice ${d.docNo} · ${d.customerId} · ${moneyOf(d.openMinor)} open`
          : `Bill ${d.billNo} · ${d.vendorId} · ${moneyOf(d.openMinor)} open`,
      doc: d,
    }));
    return [
      ...matchCandidates(c, postings, taken).map(({ posting: p }) => ({
        key: p.key as string,
        label: `${KIND_LABEL[p.kind] ?? p.kind} · ${p.date}${p.party ? ' · ' + p.party : ''}${p.memo ? ' · ' + p.memo : ''}`,
      })),
      ...docs,
    ];
  }
  matchBankCandidate = async (m: { key: string; doc?: any }) => {
    let c = this.selBank;
    if (!c) return;
    this.busy = true;
    this.error = '';
    try {
      if (m.doc) await this.payFromBankLine(c, m.doc);
      else
        await (operations(c as never as CardDef) as any).match({ key: m.key });
      this.notify(
        'Matched',
        m.doc
          ? 'The payment is in the journal, applied to the document, and the line points at it.'
          : 'The line points at the posting already in the books.',
      );
      this.selected = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  // Money in against an open invoice is a customer payment deposited to the line's account; money out
  // against an open bill is a bill payment from it. The payment posts into the journal, applies to the
  // document and marks the line matched, in one batch.
  payFromBankLine = async (c: BankTransaction, doc: any) => {
    let month = String(c.date ?? '').slice(0, 7);
    if (
      !this.journalMonths.some(
        (m: any) => m?.month === month && m?.status === 'open',
      )
    )
      throw new Error(
        `There is no open journal month for ${month || 'its date'}, so the payment can't post there.`,
      );
    let amount = Math.abs(c.amountMinor ?? 0),
      no = `BANK-${c.externalId ?? ''}`;
    let pay =
      doc instanceof Invoice
        ? new CustomerPayment({
            docNo: no,
            date: c.date,
            memo: c.description,
            customerId: doc.customerId,
            depositTo: c.account,
            applications: [
              new InvoiceApplication({
                invoiceNo: doc.docNo,
                amountMinor: amount,
              }),
            ],
            status: 'draft',
          })
        : new BillPayment({
            paymentNo: no,
            date: c.date,
            memo: c.description,
            vendorId: doc.vendorId,
            fromAccount: c.account,
            applications: [
              new PaymentApplication({
                billNo: doc.billNo,
                amountMinor: amount,
              }),
            ],
            status: 'draft',
          });
    let type =
      pay instanceof CustomerPayment ? 'CustomerPayment' : 'BillPayment';
    let entry = {
      ...journalPostingFor(pay, type, ''),
      key: this.bankKey(c),
    };
    let ops = this.postPlan(pay);
    await (operations(c as never as CardDef) as any).atomic((b: any) => [
      b.match({ key: entry.key }),
      b
        .on(
          b.find(
            {
              every: [
                { type: JournalMonth },
                { on: JournalMonth, eq: { month, status: 'open' } },
              ],
            },
            { expect: 'one' },
          ),
        )
        .post(entry),
      ...ops.map((op) => op(b)),
    ]);
  };

  // ── reconciling an account against a statement ──
  bookAt = (account: string, date: string, side?: string) =>
    bookAt(account, date, side, this.closes, this.journalMonths);
  lastRecOf = (account: string, before: string, except?: string) =>
    lastRecOf(instancesOf(this.recData), account, before, except);
  get selRec(): BankReconciliation | undefined {
    return this.sel instanceof BankReconciliation ? this.sel : undefined;
  }
  get recDraft() {
    let r = this.selRec;
    return !!r && (r.status ?? 'draft') === 'draft';
  }
  // Only the account's latest finished reconciliation reopens: a later one carried in what this one
  // left outstanding.
  get recFinished() {
    let r = this.selRec;
    return (
      r?.status === 'reconciled' &&
      this.lastRecOf(r.account ?? '', '9999-12-31')?.id === r.id
    );
  }
  get recFeedFull() {
    return instancesOf(this.bankLineData).length >= BANK_LINE_PAGE;
  }
  get recItems(): {
    key: string;
    date: string;
    label: string;
    amountMinor: number;
  }[] {
    let r = this.selRec;
    if (!r) return [];
    return recItems(
      r as never,
      instancesOf(this.recData),
      this.closes,
      this.journalMonths,
    ).map(({ posting: p, ...i }: any) => ({
      ...i,
      label: p
        ? `${KIND_LABEL[p.kind] ?? p.kind}${p.party ? ' · ' + p.party : ''}${p.memo ? ' · ' + p.memo : ''}`
        : `Outstanding · ${i.key}`,
    }));
  }
  // Ticks start from what the bank feed has matched or added: those lines are on a statement.
  @tracked recTicks: { id: string; keys: Set<string> } | undefined;
  get recTicked(): Set<string> {
    let r = this.selRec;
    if (this.recTicks && this.recTicks.id === r?.id) return this.recTicks.keys;
    let fromFeed = new Set(
      this.pageCardsOf(BankTransaction)
        .filter(
          (b) =>
            b.account === r?.account &&
            b.matchedKey &&
            String(b.date ?? '') <= String(r?.statementDate ?? ''),
        )
        .map((b) => b.matchedKey as string),
    );
    return new Set(
      this.recItems.map((i) => i.key).filter((k) => fromFeed.has(k)),
    );
  }
  pageCardsOf = (Def: any): any[] =>
    instancesOf(this.bankLineData).filter((x) => x instanceof Def);
  get recRows() {
    let ticked = this.recTicked;
    return this.recItems.map((i) => ({
      ...i,
      ticked: ticked.has(i.key),
      toggle: (on: boolean) => {
        let keys = new Set(this.recTicked);
        if (on) keys.add(i.key);
        else keys.delete(i.key);
        this.recTicks = { id: this.selRec?.id ?? '', keys };
      },
    }));
  }
  get recBook() {
    let r = this.selRec;
    return r ? this.bookAt(r.account ?? '', r.statementDate ?? '', r.side) : 0;
  }
  get recOutstanding() {
    return this.recRows.filter((i) => !i.ticked);
  }
  get recDifference() {
    let r = this.selRec;
    if (!r) return 0;
    let open = this.recOutstanding.reduce((n, i) => n + i.amountMinor, 0);
    return (r.endingBalanceMinor ?? 0) - (this.recBook - open);
  }
  get recFacts() {
    return [
      {
        label: 'Statement balance',
        value: moneyOf(this.selRec?.endingBalanceMinor),
      },
      { label: 'Book balance', value: moneyOf(this.recBook) },
      {
        label: 'Not yet on the statement',
        value: moneyOf(
          this.recOutstanding.reduce((n, i) => n + i.amountMinor, 0),
        ),
      },
      { label: 'Difference', value: moneyOf(this.recDifference) },
    ];
  }
  finishRec = async () => {
    let r = this.selRec;
    if (!r) return;
    this.busy = true;
    this.error = '';
    try {
      let cleared = this.recRows
        .filter((i) => i.ticked)
        .map((i) => ({
          key: i.key,
          date: i.date || null,
          amountMinor: i.amountMinor,
        }));
      let outstanding = this.recOutstanding.map((i) => ({
        ref: i.key,
        amountMinor: i.amountMinor,
      }));
      await (operations(r as never as CardDef) as any).atomic((b: any) => [
        b.record({ cleared, outstanding }),
        b.finish({ bookBalanceMinor: this.recBook }),
      ]);
      this.notify(
        'Reconciled',
        `${r.account} agrees with the statement at ${r.statementDate}.`,
      );
      this.selected = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  undoRec = async () => {
    let r = this.selRec;
    if (!r) return;
    this.busy = true;
    this.error = '';
    try {
      await (operations(r as never as CardDef) as any).undo();
      this.notify('Reopened', 'Tick the lines again, then finish it.');
      this.selected = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  // A finished reconciliation whose book balance has moved since: something on or before its
  // statement date was entered, changed or reversed after it was finished.
  get recDiscrepancies(): any[] {
    return instancesOf(this.recData).filter(
      (r) =>
        r.status === 'reconciled' &&
        r.finishedBookMinor != null &&
        this.bookAt(r.account ?? '', r.statementDate ?? '', r.side) !==
          r.finishedBookMinor,
    );
  }

  // Starting a reconciliation: the account, the statement's date and its ending balance.
  @tracked recOpen = false;
  @tracked recAccount = '';
  @tracked recDate = '';
  @tracked recEnding = '';
  get isRecs() {
    return this.page === 'recs';
  }
  openRec = () => {
    this.recOpen = true;
    this.error = '';
    if (!this.recAccount)
      this.recAccount = this.bankAccountOptions[0]?.value ?? '';
  };
  closeRec = () => {
    this.recOpen = false;
  };
  setRecAccount = (v: string) => {
    this.recAccount = v;
  };
  setRecDate = (v: string) => {
    this.recDate = v;
  };
  setRecEnding = (v: string) => {
    this.recEnding = v;
  };
  get recStartBlocked(): string {
    if (!this.recAccount) return 'Choose the account.';
    if (!/^\d{4}-\d{2}-\d{2}$/.test(this.recDate))
      return 'Enter the statement date as yyyy-mm-dd.';
    try {
      statementMinor(this.recEnding);
    } catch {
      return 'Enter the statement’s ending balance.';
    }
    if (
      instancesOf(this.recData).some(
        (r) => r.account === this.recAccount && r.status !== 'reconciled',
      )
    )
      return 'This account has a reconciliation in progress. Finish it first.';
    let last = this.lastRecOf(this.recAccount, '9999-12-31');
    if (last && this.recDate <= String(last.statementDate ?? ''))
      return `${this.recAccount} is reconciled through ${last.statementDate}. Start from a later statement.`;
    return '';
  }
  startRec = async () => {
    if (this.recStartBlocked) return;
    this.busy = true;
    this.error = '';
    try {
      let account = this.recAccount,
        type = (this.accountTypes.get(account) as any)?.type;
      // What the last finished reconciliation left outstanding carries into this one.
      let prev = instancesOf(this.recData)
        .filter((r) => r.account === account && r.status === 'reconciled')
        .sort((a, b) =>
          String(a.statementDate ?? '').localeCompare(
            String(b.statementDate ?? ''),
          ),
        )
        .at(-1);
      await this.createHere(BankReconciliation, {
        account,
        side: type === 'cc' ? 'credit' : 'debit',
        statementDate: this.recDate,
        endingBalanceMinor: statementMinor(this.recEnding),
        outstanding: ((prev?.outstanding ?? []) as any[])
          .filter(Boolean)
          .map((o) => ({
            ref: o.ref ?? null,
            amountMinor: o.amountMinor ?? 0,
          })),
        cleared: [],
        status: 'draft',
      });
      this.notify(
        'Reconciliation started',
        'Open it to tick what the statement shows.',
      );
      this.recOpen = false;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  get bankLines() {
    return (this.bankEntry?.lines ?? []).map((l) => ({
      accountCode: l.account,
      accountName: (this.accountTypes.get(l.account) as any)?.name ?? '',
      detail: [l.party].filter(Boolean).join(' · '),
      debitMinor: l.debitMinor,
      creditMinor: l.creditMinor,
    }));
  }
  bankKey = (c: BankTransaction) =>
    bankKey(c.importKey, c.date, this.journalMonths);
  // Adding posts the entry into its journal month and marks the line added, in one batch: the feed
  // and the books can't disagree.
  addBankLine = async () => {
    let c = this.selBank,
      entry = this.bankEntry;
    if (!c || !entry) return;
    let month = String(c.date ?? '').slice(0, 7);
    this.busy = true;
    this.error = '';
    try {
      if (
        !this.journalMonths.some(
          (m: any) => m?.month === month && m?.status === 'open',
        )
      )
        throw new Error(
          `There is no open journal month for ${month || 'its date'}, so the line can't be added there.`,
        );
      await (operations(c as never as CardDef) as any).atomic((b: any) => [
        b.add({ key: entry!.key, category: this.bankCategory }),
        b
          .on(
            b.find(
              {
                every: [
                  { type: JournalMonth },
                  { on: JournalMonth, eq: { month, status: 'open' } },
                ],
              },
              { expect: 'one' },
            ),
          )
          .post(entry),
      ]);
      this.notify(
        'Added to the books',
        `It's in the ${month} journal, and the line is marked added.`,
      );
      this.selected = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  excludeBankLine = async () => {
    let c = this.selBank;
    if (!c) return;
    this.busy = true;
    this.error = '';
    try {
      await (operations(c as never as CardDef) as any).exclude({
        reason: this.bankExcludeReason || null,
      });
      this.notify(
        'Excluded',
        'The line stays in the feed and out of the books.',
      );
      this.selected = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  restoreBankLine = async () => {
    let c = this.selBank;
    if (!c) return;
    this.busy = true;
    this.error = '';
    try {
      await (operations(c as never as CardDef) as any).restore();
      this.notify('Back for review');
      this.selected = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  // ── the journal's months and pads ──
  // A create called on a class lands in the session's default writable realm. Sent as a batch on this
  // app card, it commits in the app's own realm, next to the books.
  createHere = async (Def: unknown, attrs: Record<string, unknown>) => {
    let [created] = await (
      operations(this.args.model as never as CardDef) as any
    ).atomic((b: any) => [b.create(Def, attrs)]);
    return created;
  };
  get openMonths(): any[] {
    return this.journalMonths.filter((m) => m.status === 'open');
  }
  // The month after the latest one the books know: the last journal month, or the last month closed.
  get nextMonth(): string {
    let months = [
      ...this.journalMonths.map((m) => String(m.month ?? '')),
      ...this.closes.map((c) => String(c.month ?? '')),
    ]
      .filter((m) => /^\d{4}-\d{2}$/.test(m))
      .sort();
    let last = months.at(-1);
    if (!last) return new Date().toISOString().slice(0, 7);
    let [y, m] = last.split('-').map(Number);
    return m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`;
  }
  get nextMonthLabel() {
    let d = new Date(`${this.nextMonth}-15T00:00:00Z`);
    return isNaN(d.getTime())
      ? this.nextMonth
      : d.toLocaleString('en-US', {
          month: 'long',
          year: 'numeric',
          timeZone: 'UTC',
        });
  }
  get showJournalActions() {
    return (
      this.page === 'journalmonths' || this.page === 'pads' || this.usesJournal
    );
  }
  get pageKind() {
    let k = this.def.journal ?? [];
    return k.length && !k.includes('*') ? k[0] : 'journal';
  }
  /** Open the next month: a new, empty journal card that postings can go into. */
  openMonth = async () => {
    let month = this.nextMonth,
      [y, m] = month.split('-').map(Number),
      lastDay = new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10);
    if (this.journalMonths.some((j) => j.month === month)) {
      this.toasts.show({ title: `${month} is already open.`, tone: 'info' });
      return;
    }
    let label = this.nextMonthLabel;
    this.busy = true;
    this.error = '';
    try {
      await this.createHere(JournalMonth, {
        month,
        firstDay: `${month}-01`,
        lastDay,
        status: 'open',
        nextSeq: 1,
        postings: [],
      });
      this.notify(`Opened ${label}`, 'Entries dated in it can now post.');
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  /** A new pad for this kind of entry, dated today if today is in an open month, otherwise inside the latest open month. */
  newPad = async (kind: string, party: string | null = null) => {
    let open = this.openMonths.at(-1);
    if (!open) {
      this.error = `No month is open to post into. Open ${this.nextMonthLabel} first.`;
      return;
    }
    let date = new Date().toISOString().slice(0, 10),
      inOpen = this.openMonths.find(
        (m) => date >= m.firstDay && date <= m.lastDay,
      );
    if (!inOpen) date = date > open.lastDay ? open.lastDay : open.firstDay;
    this.busy = true;
    this.error = '';
    try {
      let result: any = await this.createHere(EntryPad, {
        owner: '',
        kind,
        date,
        memo: '',
        party,
        lines: [],
        preparer: '',
        reviewer: '',
      });
      let id = result?.id ?? result?.card?.id ?? result?.data?.id;
      this.paletteOpen = false;
      this.newKind = '';
      this.notify(
        `New ${(KIND_LABEL[kind] ?? kind).toLowerCase()} pad, dated ${date}`,
        'Write the entry, then post it from the pad.',
      );
      if (id) this.args.viewCard?.(new URL(id), 'edit');
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  newPadHere = () => this.newPad(this.pageKind);
  get closes(): any[] {
    return (((this.closeData as any)?.instances ?? []) as any[])
      .filter(Boolean)
      .sort((a, b) => (a.month ?? '').localeCompare(b.month ?? ''));
  }
  get accountTypes() {
    return new Map(
      ((this.accountData as any)?.instances ?? [])
        .filter(Boolean)
        .map((a: any) => [a.code, { type: a.type, name: a.name }]),
    );
  }
  get balances() {
    let net = new Map<string, number>();
    for (let c of this.closes)
      for (let t of c.totals ?? [])
        if (t?.account)
          net.set(
            t.account,
            (net.get(t.account) ?? 0) +
              (t.debitMinor ?? 0) -
              (t.creditMinor ?? 0),
          );
    return net;
  }

  // ── the list on the current page ──
  get pageCards(): any[] {
    return this.def.drafts
      ? this.drafts
      : (((this.listData as any)?.instances ?? []) as any[]).filter(Boolean);
  }
  get rows(): Row[] {
    let d = this.def;
    if (!d.row && !this.usesJournal) return [];
    let bal = this.balances,
      names = this.accountTypes,
      q = this.query.trim().toLowerCase();
    let rows = this.usesJournal
      ? this.journalRows
      : this.pageCards.map((c) => {
          let r: Row = { key: c.id, card: c, ...d.row!(c) };
          let codes = [
            ...new Set(
              ((c.ledgerLines ?? []) as any[])
                .filter(Boolean)
                .map((l) => l.account)
                .filter(Boolean),
            ),
          ].sort() as string[];
          if (codes.length) {
            r.accounts = codes.join(' ');
            r.accountNames = codes
              .map((a) => (names.get(a) as any)?.name ?? '')
              .join(' ');
          }
          if (d.id === 'bankfeed' && c.status !== 'added')
            r.suggested = ruleFor(this.bankRules, c)?.category ?? '';
          if (d.id === 'accounts') {
            let net = bal.get(r.code as string) ?? 0,
              side = SECTION[String(r.type)];
            r.amount = ['asset', 'cogs', 'expense'].includes(side) ? net : -net;
          }
          return r;
        });
    if (this.subject) rows = rows.filter(this.inSubject);
    if (this.chip) rows = rows.filter((r) => r.status === this.chip);
    if (q) {
      let words = q.split(/\s+/);
      rows = rows.filter((r) => {
        let hay = Object.entries(r)
          .filter(([k]) => !['card', 'posting', 'month'].includes(k))
          .map(([, v]) => (v == null ? '' : String(v)))
          .join(' ')
          .toLowerCase();
        return words.every((w) => hay.includes(w));
      });
    }
    return rows.sort(
      (a, b) =>
        String(b.date ?? b.month ?? '').localeCompare(
          String(a.date ?? a.month ?? ''),
        ) ||
        String(a.number ?? a.code ?? a.name ?? '').localeCompare(
          String(b.number ?? b.code ?? b.name ?? ''),
        ),
    );
  }
  get columns(): DataColumn<Row>[] {
    return (this.def.cols ?? []).map(
      (c) =>
        ({
          key: c.key,
          label: c.label,
          width: c.width,
          mono:
            c.kind === 'mono' ||
            c.kind === 'money' ||
            c.kind === 'qty' ||
            c.kind === 'count',
          align:
            c.kind === 'money' || c.kind === 'qty' || c.kind === 'count'
              ? 'end'
              : undefined,
          kind: c.kind,
        }) as DataColumn<Row>,
    );
  }
  get chipOptions() {
    let rows = this.usesJournal
      ? this.journalRows
      : this.pageCards.map(
          (c) => ({ key: c.id, card: c, ...this.def.row!(c) }) as Row,
        );
    if (this.subject) rows = rows.filter(this.inSubject);
    let all = rows.map((r) => r.status as string);
    return [
      { value: '', label: 'All', count: all.length },
      ...(this.chips ?? []).map((s) => ({
        value: s,
        label: s,
        count: all.filter((x) => x === s).length,
      })),
    ];
  }
  get listTotal() {
    return this.rows.reduce(
      (n, r) => n + (typeof r.amount === 'number' ? r.amount : 0),
      0,
    );
  }

  // ── the dashboard ──
  // The closed months. Books with none closed yet show their open months instead: their figures so far.
  get months() {
    let types = this.accountTypes,
      cum = new Map<string, number>(),
      out: any[] = [];
    let closed = new Set(this.closes.map((c) => c.month));
    let periods = [
      ...this.closes.map((c) => ({
        month: c.month,
        totals: c.totals,
        open: false,
      })),
      ...this.journalMonths
        .filter(
          (j) =>
            !this.closes.length && j.status === 'open' && !closed.has(j.month),
        )
        .map((j) => ({
          month: j.month,
          totals: [
            ...(j.totals ?? []),
            ...(((this.openDocsData as any)?.instances ?? []) as any[])
              .filter((d) => String(d?.date ?? '').startsWith(j.month))
              .flatMap((d) => d.ledgerLines ?? []),
          ],
          open: true,
        })),
    ].sort((a, b) => String(a.month).localeCompare(String(b.month)));
    for (let c of periods) {
      let m = {
        month: c.month,
        open: c.open,
        income: 0,
        cogs: 0,
        expense: 0,
        cash: 0,
        ar: 0,
        ap: 0,
        undeposited: 0,
      };
      for (let t of c.totals ?? []) {
        if (!t?.account) continue;
        let v = (t.debitMinor ?? 0) - (t.creditMinor ?? 0),
          s = SECTION[(types.get(t.account) as any)?.type ?? ''];
        cum.set(t.account, (cum.get(t.account) ?? 0) + v);
        if (s === 'income') m.income -= v;
        else if (s === 'cogs') m.cogs += v;
        else if (s === 'expense') m.expense += v;
      }
      m.cash = cum.get('1000') ?? 0;
      m.ar = cum.get('1100') ?? 0;
      m.ap = -(cum.get('2000') ?? 0);
      m.undeposited = cum.get('1010') ?? 0;
      out.push(m);
    }
    return out.filter((m) => m.income || m.expense || m.cogs);
  }
  // Today reads the month picked in the rail, or the latest closed one.
  get scopedIndex() {
    let s = this.space === 'today' ? this.subject : '',
      i = s ? this.months.findIndex((m) => m.month === s) : -1;
    return i >= 0 ? i : this.months.length - 1;
  }
  get latest() {
    return this.months[this.scopedIndex];
  }
  get prior() {
    return this.scopedIndex > 0 ? this.months[this.scopedIndex - 1] : undefined;
  }
  get year() {
    let y = this.latest?.month?.slice(0, 4);
    return this.months.filter((m) => m.month.startsWith(y ?? ''));
  }
  get ytd() {
    let y = this.year;
    let income = y.reduce((n, m) => n + m.income, 0),
      cogs = y.reduce((n, m) => n + m.cogs, 0),
      expense = y.reduce((n, m) => n + m.expense, 0);
    return {
      income,
      cogs,
      expense,
      gross: income - cogs,
      net: income - cogs - expense,
    };
  }
  get margin() {
    let y = this.ytd;
    return y.income
      ? `${((y.gross / y.income) * 100).toFixed(1)}% gross margin`
      : '';
  }
  get trend() {
    return this.months.flatMap((m) => [
      { month: m.month, kind: 'Sales', value: dollars(m.income) },
      {
        month: m.month,
        kind: 'Costs and expenses',
        value: dollars(m.cogs + m.expense),
      },
    ]);
  }
  get expenseBars() {
    let types = this.accountTypes,
      by = new Map<string, number>(),
      y = this.latest?.month?.slice(0, 4) ?? '';
    for (let c of this.closes.filter((c) => (c.month ?? '').startsWith(y)))
      for (let t of c.totals ?? []) {
        let s = SECTION[(types.get(t?.account) as any)?.type ?? ''];
        if (s === 'expense' || s === 'cogs')
          by.set(
            t.account,
            (by.get(t.account) ?? 0) +
              (t.debitMinor ?? 0) -
              (t.creditMinor ?? 0),
          );
      }
    return [...by.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 8)
      .map(([a, v]) => ({
        name: `${a} · ${(types.get(a) as any)?.name ?? ''}`,
        value: dollars(v),
      }));
  }
  get asOf() {
    let m = this.latest?.month;
    if (!m || this.latest?.open || !/^\d{4}-\d{2}$/.test(m)) return '';
    return new Date(Date.UTC(+m.slice(0, 4), +m.slice(5, 7), 0))
      .toISOString()
      .slice(0, 10);
  }
  get nextOpen() {
    let m = this.closes.at(-1)?.month;
    if (!m) return '';
    let [y, mm] = m.split('-').map(Number);
    return mm === 12
      ? `${y + 1}-01-01`
      : `${y}-${String(mm + 1).padStart(2, '0')}-01`;
  }
  get billsDue() {
    let asOf = this.asOf,
      soon = addDays(asOf, 30) || '9999-12-31';
    let open = (((this.billData as any)?.instances ?? []) as any[]).filter(
      (b) => b && (b.openMinor ?? 0) > 0,
    );
    let due = open.filter((b) => (b.due ?? '') <= soon);
    return {
      count: due.length,
      amount: due.reduce((n, b) => n + (b.openMinor ?? 0), 0),
      late: open.filter((b) => (b.due ?? '') < asOf).length,
    };
  }
  get openInvoiceSum() {
    let open = (((this.invoiceData as any)?.instances ?? []) as any[]).filter(
      (i) => i && (i.openMinor ?? 0) > 0,
    );
    return {
      count: open.length,
      amount: open.reduce((n, i) => n + (i.openMinor ?? 0), 0),
    };
  }
  get drafts() {
    return (((this.draftData as any)?.instances ?? []) as any[]).filter(
      Boolean,
    );
  }
  get latestClose() {
    return this.closes.at(-1);
  }
  get gates(): any[] {
    return ((this.latestClose?.checks ?? []) as string[])
      .filter(Boolean)
      .map((c, i) => ({
        id: String(i),
        name: c.replace(/^(pass|FAIL) · /, ''),
        state: c.startsWith('pass') ? 'pass' : 'fail',
      }));
  }
  get allPass() {
    return this.gates.length > 0 && this.gates.every((g) => g.state === 'pass');
  }
  get todo() {
    let b = this.billsDue,
      i = this.openInvoiceSum,
      u = this.latest?.undeposited ?? 0,
      d = this.drafts.length;
    return [
      {
        n: d,
        label: d === 1 ? 'Draft not posted' : 'Drafts not posted',
        note: 'Drafts change nothing until they post. Check each, then post it.',
        page: 'drafts',
        tone: 'attention',
        status: 'Not posted',
        action: 'Review drafts',
      },
      {
        n: b.count,
        label: b.late
          ? `Bills due, ${b.late} past due`
          : 'Bills due within 30 days',
        note: `${money(b.amount)} to pay.`,
        page: 'bills',
        tone: b.late ? 'danger' : 'warning',
        status: b.late ? 'Past due' : 'Due soon',
        action: 'Pay bills',
      },
      {
        n: i.count,
        label: i.count === 1 ? 'Invoice open' : 'Invoices open',
        note: `${money(i.amount)} to collect.`,
        page: 'invoices',
        tone: 'info',
        status: 'Open',
        action: 'Collect',
      },
      {
        n: u ? 1 : 0,
        label: 'Funds not deposited',
        note: `${money(u)} sits in Undeposited Funds.`,
        page: 'deposits',
        tone: 'warning',
        status: 'Not deposited',
        action: 'Deposit',
      },
    ];
  }
  // Only what needs a person: an item with nothing waiting leaves the queue.
  get review() {
    return this.todo.filter((t) => t.n > 0);
  }
  get monthLong() {
    let m = this.latest?.month;
    let d = new Date(`${m}-15T00:00:00Z`);
    return !m || isNaN(d.getTime())
      ? ''
      : d.toLocaleString('en-US', { month: 'long', timeZone: 'UTC' });
  }
  get monthYear() {
    let m = this.latest?.month;
    let d = new Date(`${m}-15T00:00:00Z`);
    return !m || isNaN(d.getTime())
      ? ''
      : d.toLocaleString('en-US', {
          month: 'long',
          year: 'numeric',
          timeZone: 'UTC',
        });
  }
  get title() {
    if (this.page === 'home')
      return this.monthLong ? `${this.monthLong}, in view.` : 'Today';
    if (this.subjectRow && this.ws.subject !== 'reports')
      return this.subjectRow.label;
    return this.ws.subject === 'reports' || this.ws.pages.length < 2
      ? this.def.label
      : this.ws.label;
  }
  get blurb() {
    if (this.page === 'home')
      return this.monthYear
        ? `USD · ${this.monthYear}${this.asOf ? ` · closed through ${this.asOf}` : ''}`
        : '';
    if (this.subjectRow?.detail)
      return `${this.subjectRow.detail} · ${this.def.label}`;
    return this.def.blurb;
  }

  // ── navigation: workspaces, the subject they're scoped to, and views opened on top or beside ──
  get ws() {
    return spaceById.get(this.space) ?? WORKSPACES[0];
  }
  isActive = (id: string) => this.page === id;
  isSpace = (id: string) => this.space === id;
  isSubject = (id: string) =>
    this.ws.subject === 'reports' ? this.page === id : this.subject === id;
  go = (id: string) => {
    this.space = spaceOf(id, this.space);
    if (this.ws.subject === 'reports') this.subject = '';
    this.page = id;
    this.chip = '';
    this.query = '';
    this.selected = undefined;
    this.error = '';
    this.pageNo = 0;
  };
  // A workspace opens on its first view, unscoped.
  goSpace = (id: string) => {
    let w = spaceById.get(id);
    if (!w) return;
    this.space = id;
    this.subject = '';
    this.go(w.pages[0]);
  };
  pickSubject = (id: string) => {
    if (this.ws.subject === 'reports') {
      this.go(id);
      return;
    }
    this.subject = this.subject === id ? '' : id;
    this.selected = undefined;
    this.pageNo = 0;
  };
  get hasMore() {
    return (
      !this.usesJournal &&
      !this.def.drafts &&
      ((this.listData as any)?.instances ?? []).length >= 100
    );
  }
  nextPage = () => {
    this.pageNo += 1;
    this.selected = undefined;
  };
  prevPage = () => {
    this.pageNo = Math.max(0, this.pageNo - 1);
    this.selected = undefined;
  };
  get crumbs() {
    let c: { label: string }[] = [
      { label: this.args.model.company ?? 'Books' },
      { label: this.ws.label },
    ];
    if (this.subjectRow && this.ws.subject !== 'reports')
      c.push({ label: this.subjectRow.label });
    if (this.ws.pages.length > 1 && this.ws.subject !== 'reports')
      c.push({ label: TAB[this.page] ?? this.def.label });
    return this.page === 'home' ? c.slice(0, 1) : c;
  }
  get tabs() {
    let w = this.ws;
    return w.subject === 'reports' || w.pages.length < 2
      ? []
      : w.pages.map((id) => ({
          value: id,
          label: TAB[id] ?? pageById.get(id)?.label ?? id,
        }));
  }
  get spaces() {
    let i = this.openInvoiceSum.count,
      b = this.billsDue.count,
      d = this.drafts.length;
    let badge: Record<string, string> = {
      sales: i ? String(i) : '',
      purchases: b ? String(b) : '',
      books: d ? String(d) : '',
    };
    return WORKSPACES.map((w) => ({ ...w, badge: badge[w.id] ?? '' }));
  }

  // The rail's roster: the things in this workspace, each with the figure that matters about it.
  get subjects(): {
    id: string;
    label: string;
    badge: string;
    detail: string;
  }[] {
    let k = this.ws.subject,
      list = (d: unknown) =>
        (((d as any)?.instances ?? []) as any[]).filter(Boolean);
    if (k === 'customers') {
      let open = new Map<string, number>();
      for (let i of list(this.invoiceData))
        open.set(
          i.customerId,
          (open.get(i.customerId) ?? 0) + (i.openMinor ?? 0),
        );
      return list(this.customerData)
        .map((c) => ({
          id: c.customerId,
          label: c.name ?? c.customerId,
          badge: compact(open.get(c.customerId)),
          detail: open.get(c.customerId)
            ? `${money(open.get(c.customerId))} open`
            : 'Nothing open',
        }))
        .sort((a, b) => a.label.localeCompare(b.label));
    }
    if (k === 'vendors') {
      let owed = new Map<string, number>();
      for (let b of list(this.billData))
        owed.set(b.vendorId, (owed.get(b.vendorId) ?? 0) + (b.openMinor ?? 0));
      return list(this.vendorData)
        .map((v) => ({
          id: v.vendorId,
          label: v.name ?? v.vendorId,
          badge: compact(owed.get(v.vendorId)),
          detail: owed.get(v.vendorId)
            ? `${money(owed.get(v.vendorId))} owed`
            : 'Nothing owed',
        }))
        .sort((a, b) => a.label.localeCompare(b.label));
    }
    if (k === 'accounts') {
      let used = new Set(list(this.recData).map((r) => r.account));
      return [...this.accountTypes.entries()]
        .filter(
          ([code, a]: [any, any]) =>
            ['bank', 'cc'].includes(a.type) || used.has(code),
        )
        .sort(([a], [b]) => String(a).localeCompare(String(b)))
        .map(([code, a]: [any, any]) => ({
          id: code,
          label: `${code} · ${a.name}`,
          badge: compact(this.accountBalance(code)),
          detail: `${money(this.accountBalance(code))} at the last close`,
        }));
    }
    if (k === 'products')
      return list(this.itemData)
        .map((i) => ({
          id: i.sku,
          label: i.productName ?? i.sku,
          badge: '',
          detail: `${i.sku} · ${i.productType ?? ''}`,
        }))
        .sort((a, b) => a.label.localeCompare(b.label));
    if (k === 'months') {
      if (this.space === 'today')
        return [...this.months].reverse().map((m) => ({
          id: m.month,
          label: m.open ? `${monthLabel(m.month)} · open` : monthLabel(m.month),
          badge: compact(m.income - m.cogs - m.expense),
          detail: `Net income ${money(m.income - m.cogs - m.expense)}`,
        }));
      let status = new Map<string, string>();
      for (let c of this.closes) status.set(c.month, 'Closed');
      for (let j of this.journalMonths)
        status.set(
          j.month,
          j.status === 'sealed'
            ? 'Sealed'
            : j.status === 'closed'
              ? 'Closed'
              : 'Open',
        );
      return [...status.entries()]
        .sort(([a], [b]) => b.localeCompare(a))
        .map(([m, st]) => ({
          id: m,
          label: monthLabel(m),
          badge: st === 'Open' ? 'Open' : '',
          detail: st,
        }));
    }
    if (k === 'reports')
      return REPORT_PAGES.map((id) => ({
        id,
        label: pageById.get(id)!.label,
        badge: '',
        detail: '',
      }));
    if (k === 'chart') return this.chartGroups.flatMap((g) => g.accounts);
    return [];
  }
  // ── the chart of accounts: grouped by section, each account with its balance in its natural sign ──
  get chartGroups() {
    let all = [...this.accountTypes.entries()]
      .map(([code, a]: [any, any]) => ({
        code: String(code),
        name: a.name ?? '',
        section: SECTION[a.type ?? ''] ?? 'expense',
      }))
      .sort((a, b) => a.code.localeCompare(b.code));
    return CHART_SECTIONS.map((sec) => ({
      ...sec,
      accounts: all
        .filter((a) => a.section === sec.key)
        .map((a) => ({
          id: a.code,
          label: `${a.code} · ${a.name}`,
          badge: compact(this.accountBalance(a.code)),
          detail: `${sec.label.replace(/s$/, '')} · ${money(this.accountBalance(a.code))} at the last close`,
        })),
    })).filter((g) => g.accounts.length);
  }
  chartCols: StatementColumn[] = [
    { key: 'code', label: 'No.', kind: 'code', width: '5rem' },
    { key: 'name', label: 'Account' },
    { key: 'bal', label: 'Balance', kind: 'amount' },
  ];
  get chartRows(): StatementRow[] {
    return this.chartGroups.flatMap((g) => [
      { key: `h-${g.key}`, role: 'heading' as const, cells: { code: g.label } },
      ...g.accounts.map((a) => ({
        key: a.id,
        depth: 1,
        cells: {
          code: a.id,
          name: a.label.split(' · ').slice(1).join(' · '),
          bal: this.accountBalance(a.id),
        },
        data: { row: true, key: a.id, total: this.accountBalance(a.id) },
      })),
      {
        key: `t-${g.key}`,
        role: 'subtotal' as const,
        cells: {
          name: `Total ${g.label.toLowerCase()}`,
          bal: g.accounts.reduce((n, a) => n + this.accountBalance(a.id), 0),
        },
      },
    ]);
  }
  pickChartRow = (row: StatementRow) => {
    if (row.data?.key) this.pickSubject(String(row.data.key));
  };
  get chartOrder() {
    return this.chartGroups.flatMap((g) => g.accounts.map((a) => a.id));
  }
  get prevAccount() {
    let o = this.chartOrder,
      i = o.indexOf(this.subject);
    return i > 0 ? o[i - 1] : '';
  }
  get nextAccount() {
    let o = this.chartOrder,
      i = o.indexOf(this.subject);
    return i >= 0 && i < o.length - 1 ? o[i + 1] : '';
  }
  stepAccount = (code: string) => {
    if (code) this.subject = code;
  };
  get acctInfo() {
    let a = this.accountTypes.get(this.subject) as any;
    let sec = SECTION[a?.type ?? ''] ?? '';
    return {
      name: a?.name ?? '',
      type: a?.type ?? '',
      section: CHART_SECTIONS.find((x) => x.key === sec),
    };
  }
  // Every posted line on the account: journal postings and the documents that stay cards, with a
  // running balance in the account's natural sign (payables and income read positive).
  get register() {
    let code = this.subject,
      raw: {
        date: string;
        doc: string;
        entry: string;
        party: string;
        dr: number;
        cr: number;
      }[] = [];
    for (let m of this.journalMonths)
      for (let p of ((m.postings ?? []) as any[]).filter(Boolean))
        for (let l of ((p.lines ?? []) as any[]).filter(Boolean))
          if (l.account === code)
            raw.push({
              date: p.date ?? '',
              doc: p.source || seqText(m.month, p.seq),
              entry: KIND_LABEL[p.kind] ?? p.kind,
              party: l.party ?? p.party ?? '',
              dr: l.debitMinor ?? 0,
              cr: l.creditMinor ?? 0,
            });
    for (let c of this.regDocs)
      for (let l of ((c.ledgerLines ?? []) as any[]).filter(Boolean))
        if (l.account === code)
          raw.push({
            date: l.date || c.date || '',
            doc: c.docNo ?? c.billNo ?? c.cardTitle ?? '',
            entry: (c.constructor as any)?.displayName ?? '',
            party: l.party ?? c.customerId ?? c.vendorId ?? '',
            dr: l.debitMinor ?? 0,
            cr: l.creditMinor ?? 0,
          });
    raw.sort(
      (a, b) => a.date.localeCompare(b.date) || a.doc.localeCompare(b.doc),
    );
    let debitSide = this.acctInfo.section?.debit ?? true,
      bal = 0;
    return raw.map((r, i) => {
      bal += debitSide ? r.dr - r.cr : r.cr - r.dr;
      return { ...r, bal, i };
    });
  }
  regCols: StatementColumn[] = [
    { key: 'date', label: 'Date', kind: 'code', width: '8.25rem' },
    { key: 'doc', label: 'Document', kind: 'code' },
    { key: 'entry', label: 'Entry', priority: 'secondary' },
    { key: 'party', label: 'Party', priority: 'secondary' },
    { key: 'dr', label: 'Debit', kind: 'amount' },
    { key: 'cr', label: 'Credit', kind: 'amount' },
    { key: 'bal', label: 'Balance', kind: 'amount' },
  ];
  get regRows(): StatementRow[] {
    let lines = this.register,
      dr = lines.reduce((n, l) => n + l.dr, 0),
      cr = lines.reduce((n, l) => n + l.cr, 0);
    return [
      ...lines.map((l) => ({
        key: `${l.i}`,
        cells: {
          date: l.date,
          doc: l.doc,
          entry: l.entry,
          party: l.party,
          dr: l.dr,
          cr: l.cr,
          bal: l.bal,
        },
        data: { row: true, key: l.doc, total: l.bal },
      })),
      {
        key: 'total',
        role: 'total' as const,
        cells: { doc: 'Totals', dr, cr, bal: lines.at(-1)?.bal ?? 0 },
      },
    ];
  }
  get acctFacts() {
    let a = this.acctInfo,
      lines = this.register;
    return [
      {
        key: 'type',
        label: 'Type',
        value: `${a.section?.label ?? ''} · ${a.type}`,
      },
      {
        key: 'last',
        label: 'Balance at the last close',
        value: money(this.accountBalance(this.subject)),
      },
      {
        key: 'now',
        label: 'Balance with open months',
        value: money(lines.at(-1)?.bal ?? 0),
      },
      { key: 'lines', label: 'Lines', value: String(lines.length) },
    ];
  }
  // A full last page means documents past it are missing, so the running balance is short.
  get regTruncated() {
    return [this.regInvoices, this.regBills1, this.regOpenings].some(
      (d) => ((d as any)?.instances?.length ?? 0) >= 100,
    );
  }
  get regLoading() {
    return [
      this.regInvoices,
      this.regBills0,
      this.regBills1,
      this.regOpenings,
    ].some((d) => (d as any)?.isLoading);
  }

  get subjectRow() {
    return this.subject
      ? this.subjects.find((x) => x.id === this.subject)
      : undefined;
  }
  // Does a row belong to the subject? Each kind of subject is matched on the field rows carry for it.
  inSubject = (r: Row) => {
    let s = this.subject,
      k = this.ws.subject;
    if (k === 'customers' || k === 'vendors')
      return r.party === s || r.id === s;
    if (k === 'accounts')
      return (
        String(r.accounts ?? '')
          .split(' ')
          .includes(s) || r.account === s
      );
    if (k === 'products')
      return (
        r.sku === s ||
        String(r.skus ?? '')
          .split(' ')
          .includes(s) ||
        String(r.number ?? '') === s
      );
    if (k === 'months')
      return String(r.date ?? r.month ?? r.received ?? '').startsWith(s);
    return true;
  };

  // ── the period: what is open now, and the month-end pipeline ──
  get periodOpen() {
    let o = this.openMonths[0]?.month;
    return o
      ? monthLabel(o)
      : this.nextOpen
        ? monthLabel(this.nextOpen.slice(0, 7))
        : '';
  }
  get closedThrough() {
    return this.asOfAll
      ? new Date(this.asOfAll + 'T00:00:00Z').toLocaleString('en-US', {
          month: 'short',
          day: 'numeric',
          year: 'numeric',
          timeZone: 'UTC',
        })
      : '—';
  }
  get asOfAll() {
    let m = this.closes.at(-1)?.month;
    return m
      ? new Date(Date.UTC(+m.slice(0, 4), +m.slice(5, 7), 0))
          .toISOString()
          .slice(0, 10)
      : '';
  }
  // The month the pipeline follows: the one picked in Books, else the first month still open.
  get pipeMonth(): string {
    return (
      (this.space === 'books' && this.subject) ||
      this.openMonths[0]?.month ||
      this.nextOpen.slice(0, 7) ||
      ''
    );
  }
  get closeBy() {
    let m = this.pipeMonth;
    if (!/^\d{4}-\d{2}$/.test(m)) return '';
    let [y, mm] = m.split('-').map(Number);
    return new Date(
      Date.UTC(mm === 12 ? y + 1 : y, mm === 12 ? 0 : mm, 10),
    ).toLocaleString('en-US', {
      month: 'short',
      day: 'numeric',
      timeZone: 'UTC',
    });
  }
  get pipeline(): StepItem[] {
    let m = this.pipeMonth,
      jm = this.journalMonths.find((j) => j.month === m),
      close = this.closes.find((c) => c.month === m);
    let drafts = this.drafts.filter((d) =>
        String(d.date ?? '').startsWith(m),
      ).length,
      posted = jm?.count ?? 0;
    let recs = (((this.recData as any)?.instances ?? []) as any[]).filter(
        Boolean,
      ),
      accounts = new Set(recs.map((r) => r.account)),
      done = new Set(
        recs
          .filter(
            (r) =>
              String(r.statementDate ?? '').startsWith(m) &&
              r.status === 'reconciled',
          )
          .map((r) => r.account),
      );
    let steps: {
      label: string;
      done: boolean;
      busy?: boolean;
      detail: string;
    }[] = [
      {
        label: 'Entries',
        done: !drafts && (posted > 0 || !!close),
        busy: drafts > 0,
        detail: drafts
          ? `${drafts} draft${drafts === 1 ? '' : 's'} to post · ${posted} posted`
          : `${posted || (close ? 'All' : 'Nothing')} posted`,
      },
      {
        label: 'Reconciled',
        done: accounts.size > 0 && done.size >= accounts.size,
        detail: `${done.size} of ${accounts.size} accounts`,
      },
      {
        label: 'Closed',
        done: !!close,
        detail: close
          ? `by ${close.closedBy ?? 'the closer'}`
          : `close by ${this.closeBy}`,
      },
      {
        label: 'Sealed',
        done: jm?.status === 'sealed' || (!jm && !!close),
        detail:
          jm?.status === 'sealed'
            ? `${jm.sealCount} postings hashed`
            : jm
              ? 'after the close'
              : close
                ? 'closed before the journal'
                : '',
      },
    ];
    let current = steps.findIndex((x) => !x.done);
    return steps.map((x, i) => ({
      label: x.label,
      detail: x.detail,
      state: x.done
        ? 'complete'
        : i === current
          ? x.busy
            ? 'in-progress'
            : 'current'
          : 'upcoming',
    }));
  }

  // ── books health: what has to be true before the books can be trusted, checked up front ──
  get health(): ReadinessGate[] {
    let codes = this.accountTypes,
      missing = CONTROL.filter(([code]) => !codes.has(code)).map(
        ([code, role]) => `${code} ${role}`,
      );
    let months = [
      ...new Set([
        ...this.closes.map((c) => String(c.month ?? '')),
        ...this.journalMonths.map((j) => String(j.month ?? '')),
      ]),
    ]
      .filter((m) => /^\d{4}-\d{2}$/.test(m))
      .sort();
    let gaps: string[] = [];
    for (let i = 1; i < months.length; i++) {
      let [y, mm] = months[i - 1].split('-').map(Number),
        next =
          mm === 12 ? `${y + 1}-01` : `${y}-${String(mm + 1).padStart(2, '0')}`;
      if (months[i] !== next) gaps.push(next);
    }
    let unsealed = this.journalMonths
      .filter((j) => j.status === 'closed')
      .map((j) => j.month);
    let ar = (this.args.model.openInvoices as any)?.differenceMinor,
      ap = (this.args.model.openBills as any)?.differenceMinor;
    let recs = (((this.recData as any)?.instances ?? []) as any[]).filter(
      (r) => r && r.status === 'reconciled' && (r.differenceMinor ?? 0) !== 0,
    );
    let stuck = this.drafts.filter(
      (d) => this.asOfAll && String(d.date ?? '') <= this.asOfAll,
    );
    let gate = (
      id: string,
      name: string,
      ok: boolean | undefined,
      detail: string,
    ): ReadinessGate => ({
      id,
      name,
      state: ok === undefined ? 'pending' : ok ? 'pass' : 'fail',
      caption: detail,
    });
    return [
      gate(
        'control',
        'The accounts posting depends on are in the chart',
        missing.length === 0,
        missing.length
          ? `Missing ${missing.join(', ')}`
          : `${CONTROL.length} control accounts`,
      ),
      gate(
        'months',
        'Every month from the first is accounted for',
        gaps.length === 0,
        gaps.length
          ? `No card for ${gaps.join(', ')}`
          : `${months[0] ?? ''} to ${months.at(-1) ?? ''}`,
      ),
      gate(
        'sealed',
        'Every closed journal month is sealed',
        unsealed.length === 0,
        unsealed.length ? `Seal ${unsealed.join(', ')}` : 'Each hash recorded',
      ),
      gate(
        'ar',
        'Receivables aging ties to 1100',
        ar === undefined ? undefined : ar === 0,
        ar ? `Differs by ${money(ar)}` : '',
      ),
      gate(
        'ap',
        'Payables aging ties to 2000',
        ap === undefined ? undefined : ap === 0,
        ap ? `Differs by ${money(ap)}` : '',
      ),
      gate(
        'recs',
        'Every finished reconciliation is at $0.00',
        recs.length === 0,
        recs.length
          ? recs.map((r) => `${r.account} ${r.statementDate}`).join(', ')
          : '',
      ),
      gate(
        'rec-moved',
        'No finished reconciliation has moved since',
        this.recDiscrepancies.length === 0,
        this.recDiscrepancies
          .map(
            (r) =>
              `${r.account} ${r.statementDate} by ${money(this.bookAt(r.account, r.statementDate, r.side) - (r.finishedBookMinor ?? 0))}`,
          )
          .join(', '),
      ),
      gate(
        'stuck',
        'No draft is dated in a closed period',
        stuck.length === 0,
        stuck.length ? `${stuck.length} can never post as dated` : '',
      ),
      this.taxGate(gate),
    ];
  }
  // What the agencies were owed at the last close against 2200 in the closed months. Every agency's
  // card reads the same 2200 balance, since the account holds all of them.
  taxGate = (
    gate: (
      id: string,
      name: string,
      ok: boolean | undefined,
      d: string,
    ) => ReadinessGate,
  ) => {
    let agencies = (
      ((this.agencyData as any)?.instances ?? []) as any[]
    ).filter(Boolean);
    let closed = agencies.filter((a) => a.owedAtCloseMinor !== undefined);
    let owed = closed.reduce((n, a) => n + (a.owedAtCloseMinor ?? 0), 0),
      gl = closed[0]?.glOwedMinor;
    return gate(
      'tax',
      'Sales tax owed ties to 2200',
      !closed.length ? true : owed === gl,
      !agencies.length
        ? 'No tax agencies'
        : !closed.length
          ? 'No month closed yet'
          : owed === gl
            ? `${agencies.length} ${agencies.length === 1 ? 'agency' : 'agencies'}`
            : `Agencies are owed ${money(owed)}; 2200 holds ${money(gl)}`,
    );
  };
  agencyData = this.args.context?.getCards(
    this,
    () => {
      let type = identifyCard(TaxAgency);
      return type
        ? ({ filter: { type }, page: { size: 50 } } as never)
        : undefined;
    },
    () => this.refRealms,
    { isLive: true },
  );
  // ── sales tax returns: file, pay, and start the next ──
  get selReturn(): TaxReturn | undefined {
    return this.sel instanceof TaxReturn ? (this.sel as TaxReturn) : undefined;
  }
  get today() {
    return new Date().toISOString().slice(0, 10);
  }
  // Filing records the figures shown, so it waits until the period's invoices and months are read.
  get canFileReturn() {
    let r = this.selReturn;
    return (
      !!r &&
      r.status === 'open' &&
      String(r.periodEnd ?? '') < this.today &&
      !!getRelationshipMembershipState(r, 'invoices').isLoaded &&
      !!getRelationshipMembershipState(r, 'journal').isLoaded
    );
  }
  // Pay drafts the payment once: while that draft waits to post, the return offers it rather than another.
  get canPayReturn() {
    let r = this.selReturn;
    return (
      !!r &&
      r.status === 'filed' &&
      (r.openMinor ?? 0) > 0 &&
      !this.drafts.some(
        (d: any) =>
          d.returnPeriodEnd === r!.periodEnd && d.payee === r!.agencyId,
      )
    );
  }
  get canStartNextReturn() {
    let r = this.selReturn;
    if (!r || r.status === 'open' || this.busy) return false;
    let agency = this.agencyOf(r.agencyId),
      next = this.nextReturnPeriod(r, agency);
    return (
      !!agency &&
      !!next &&
      !(this.taxReturnData as any)?.isLoading &&
      agency.filedThrough === r.periodEnd &&
      !(((this.taxReturnData as any)?.instances ?? []) as any[]).some(
        (t) => t?.agencyId === r!.agencyId && t?.periodStart === next!.start,
      )
    );
  }
  taxReturnData = this.args.context?.getCards(
    this,
    () => {
      let type = identifyCard(TaxReturn);
      return (this.page === 'taxreturns' || this.selReturn) && type
        ? ({ filter: { type }, page: { size: 100 } } as never)
        : undefined;
    },
    () => this.refRealms,
    { isLive: true },
  );
  nextReturnPeriod = (r: TaxReturn, agency: any) => {
    if (!agency || !r.periodEnd) return undefined;
    let start = new Date(`${r.periodEnd}T00:00:00Z`);
    start.setUTCDate(start.getUTCDate() + 1);
    let months =
      agency.frequency === 'monthly'
        ? 1
        : agency.frequency === 'annual'
          ? 12
          : 3;
    let end = new Date(
      Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + months, 0),
    );
    return {
      start: start.toISOString().slice(0, 10),
      end: end.toISOString().slice(0, 10),
    };
  };
  agencyOf = (agencyId: string | undefined) =>
    (((this.agencyData as any)?.instances ?? []) as any[]).find(
      (a) => a?.agencyId === agencyId,
    );
  fileReturn = async () => {
    let r = this.selReturn;
    if (!r) return;
    this.busy = true;
    this.error = '';
    try {
      await (operations(r as never as CardDef) as any).atomic((b: any) => [
        b.file({
          taxableMinor: r!.taxableMinor ?? 0,
          taxMinor: r!.taxMinor ?? 0,
          filedOn: this.today,
        }),
        b
          .on(
            b.find(this.docMatch(TaxAgency, { agencyId: r!.agencyId! }), {
              expect: 'one',
            }),
          )
          .markFiled({ periodStart: r!.periodStart, periodEnd: r!.periodEnd }),
      ]);
      this.notify(
        'Return filed',
        `Its figures are recorded, and sales dated through ${r.periodEnd} can no longer post for ${r.agencyId}.`,
      );
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  payReturn = async () => {
    let r = this.selReturn,
      ledger = this.args.model.ledger as any;
    if (!r) return;
    this.busy = true;
    this.error = '';
    try {
      if (!ledger) throw new Error('This app is not linked to its ledger.');
      let date = [this.today, this.nextOpen].sort().at(-1)!;
      let result = await (operations(ledger) as any).enterTaxPayment({
        docNo: `STX-${r.agencyId}-${r.periodEnd}-${Date.now().toString(36).toUpperCase()}`,
        date,
        bank: '1000',
        payee: r.agencyId,
        period: `${r.periodStart} to ${r.periodEnd}`,
        returnPeriodEnd: r.periodEnd,
        amountMinor: r.openMinor ?? 0,
      });
      let id = result?.id ?? result?.card?.id ?? result?.data?.id;
      this.notify(
        'Payment drafted',
        'Posting it pays the return and records the payment on it.',
      );
      if (id) this.args.viewCard?.(new URL(id), 'edit');
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  startNextReturn = async () => {
    let r = this.selReturn,
      agency = this.agencyOf(r?.agencyId);
    if (!r || !agency) return;
    this.busy = true;
    this.error = '';
    try {
      let next = this.nextReturnPeriod(r, agency)!;
      await (operations(agency) as any).openReturn({
        periodStart: next.start,
        periodEnd: next.end,
      });
      this.notify(
        'Return started',
        `For ${agency.agencyId}, ${next.start} to ${next.end}.`,
      );
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  get healthy() {
    return this.health.every((g) => g.state === 'pass');
  }

  // Launchers: open a view here, or (») beside this one in its own stack, so the books stay in sight.
  launch = (page: string) => this.go(page);
  launchBeside = (page: string) => {
    let card = (this.args.model as any)?.[pageById.get(page)?.report ?? ''];
    if (card)
      (this.args as any).viewCard?.(card, 'isolated', {
        openCardInRightMostStack: true,
      });
    else this.go(page);
  };
  besideLabel = (label: string) => `Open ${label} beside this`;
  get paletteItems(): MenuEntry[] {
    return [
      {
        kind: 'section' as const,
        label: 'Go to',
        items: PAGES.filter((p) => !p.report).map((p) => ({
          label: p.label,
          description: `${p.area} · ${p.blurb}`,
          keywords: `${p.area} ${p.type ?? ''}`,
          onSelect: () => this.go(p.id),
        })),
      },
      {
        kind: 'section' as const,
        label: 'Reports',
        items: PAGES.filter((p) => p.report).map((p) => ({
          label: p.label,
          description: p.blurb,
          keywords: 'report statement',
          onSelect: () => this.go(p.id),
        })),
      },
      { kind: 'section' as const, label: 'Create', items: this.newItems },
      {
        kind: 'section' as const,
        label: 'Accounts',
        items: [...this.accountTypes.entries()]
          .sort(([a], [b]) => String(a).localeCompare(String(b)))
          .map(([code, a]: [any, any]) => ({
            label: `${code} · ${a.name}`,
            description: `${a.type} · balance ${money(this.accountBalance(code))}`,
            keywords: `${code} account ${a.type}`,
            onSelect: () => this.openAccount(code),
          })),
      },
    ];
  }
  get newItems() {
    return [
      {
        label: 'New invoice',
        description: 'Bill a customer',
        keywords: 'sales',
        onSelect: () => this.startNew('invoice'),
      },
      {
        label: 'New sales receipt',
        description: 'A sale paid on the spot',
        keywords: 'sales cafe',
        onSelect: () => this.startNew('receipt'),
      },
      {
        label: 'New bill',
        description: "Enter a vendor's bill",
        keywords: 'purchases expense',
        onSelect: () => this.startNew('bill'),
      },
      {
        label: 'New journal entry',
        description: 'An adjusting entry',
        keywords: 'accounting',
        onSelect: () => this.startNew('journal'),
      },
      {
        label: 'New transfer',
        description: 'Move money between accounts',
        keywords: 'banking',
        onSelect: () => this.startNew('transfer'),
      },
      {
        label: 'New entry pad',
        description: 'Write an entry, then post it into its month’s journal',
        keywords: 'journal pad post',
        onSelect: () => this.newPad('journal'),
      },
      {
        label: 'Open next month',
        description:
          'Start the next month’s journal so entries can post into it',
        keywords: 'journal month period open',
        onSelect: () => this.openMonth(),
      },
    ];
  }
  get newMenu(): MenuEntry[] {
    let n = this.newItems;
    return [
      { kind: 'section' as const, label: 'Sales', items: [n[0], n[1]] },
      { kind: 'section' as const, label: 'Purchases', items: [n[2]] },
      { kind: 'section' as const, label: 'Banking', items: [n[4]] },
      { kind: 'section' as const, label: 'Accounting', items: [n[3]] },
      { kind: 'section' as const, label: 'Journal', items: [n[5], n[6]] },
    ];
  }
  accountBalance = (code: string) => {
    let net = this.balances.get(code) ?? 0,
      side = SECTION[(this.accountTypes.get(code) as any)?.type ?? ''];
    return ['asset', 'cogs', 'expense'].includes(side) ? net : -net;
  };
  openAccount = (code: string) => {
    this.goSpace('chart');
    this.subject = code;
  };
  openPalette = () => {
    this.paletteOpen = true;
  };
  closePalette = () => {
    this.paletteOpen = false;
  };

  // ── list interactions ──
  setQuery = (v: string) => {
    this.query = v;
  };
  searchAccount = (code: string) => {
    this.query = code;
    this.chip = '';
  };
  acctChips = (v: unknown) =>
    String(v ?? '')
      .split(' ')
      .filter(Boolean)
      .map((code) => {
        let name = `${code} · ${(this.accountTypes.get(code) as any)?.name ?? ''}`;
        return { code, name, label: `Filter to ${name}` };
      });
  setChip = (v: string) => {
    this.chip = v;
  };
  inspect = (row: Row) => {
    this.selected = row;
    this.error = '';
    this.voiding = false;
  };
  closeDrawer = () => {
    this.selected = undefined;
    this.voiding = false;
  };
  get drawerOpen() {
    return !!this.selected;
  }
  get sel() {
    return this.selected?.card;
  }
  get selStatus(): string {
    return String(this.selected?.status ?? '');
  }
  get selPosting(): any {
    return this.selected?.posting;
  }
  get selTitle(): string {
    let p = this.selPosting;
    return p
      ? `${KIND_LABEL[p.kind] ?? p.kind} ${p.source || this.selected?.seq}`
      : String(this.sel?.cardTitle ?? 'Record');
  }
  get selFacts() {
    let c = this.sel;
    if (!c) return [];
    let p = this.selPosting;
    if (p) {
      let m = this.selected!.month as any,
        rev = ((m.postings ?? []) as any[]).find((x) => x?.reverses === p.seq);
      return [
        { label: 'Journal no.', value: String(this.selected!.seq) },
        { label: 'Kind', value: KIND_LABEL[p.kind] ?? p.kind },
        { label: 'Date', value: p.date ?? '' },
        { label: 'Source', value: p.source ?? '' },
        { label: 'Party', value: p.party ?? '' },
        { label: 'Memo', value: p.memo ?? '' },
        ...((p.facts ?? []) as any[])
          .filter(Boolean)
          .map((f) => ({ label: f.key, value: f.value })),
        ...(p.preparer ? [{ label: 'Prepared by', value: p.preparer }] : []),
        ...(p.reviewer ? [{ label: 'Reviewed by', value: p.reviewer }] : []),
        ...(p.reverses
          ? [{ label: 'Reverses', value: seqText(m.month, p.reverses) }]
          : []),
        ...(rev
          ? [
              {
                label: 'Reversed by',
                value: `${seqText(m.month, rev.seq)} on ${rev.date}`,
              },
            ]
          : []),
        {
          label: 'Posted by',
          value: `${p.postedBy ?? ''} · ${p.postedAt ?? ''}`,
        },
        { label: 'Month', value: `${m.cardTitle} (${m.status})` },
      ];
    }
    let facts = typeof c.facts === 'function' ? c.facts() : [];
    if (facts.length)
      return facts.map((f: any) => ({ label: f.key, value: f.value }));
    return (this.def.cols ?? []).map((col) => {
      let v = this.selected![col.key];
      return {
        label: col.label,
        value:
          col.kind === 'money'
            ? moneyOf(v)
            : col.kind === 'qty'
              ? qtyOf(v)
              : String(v ?? ''),
      };
    });
  }
  get selLines() {
    return ((this.selPosting?.lines ?? this.sel?.ledgerLines ?? []) as any[])
      .filter(Boolean)
      .map((l) => ({
        accountCode: l.account,
        accountName: (this.accountTypes.get(l.account) as any)?.name ?? '',
        detail: [l.party, l.doc].filter(Boolean).join(' · '),
        debitMinor: l.debitMinor ?? 0,
        creditMinor: l.creditMinor ?? 0,
      }));
  }
  get selIsDraft() {
    return !this.selPosting && this.sel?.status === 'draft';
  }
  get canReverse() {
    let p = this.selPosting,
      m = this.selected?.month as any;
    return (
      !!p &&
      m?.status === 'open' &&
      p.kind !== 'reversal' &&
      p.kind !== 'void' &&
      this.selected?.status === 'Posted'
    );
  }
  get openLabel() {
    return this.selPosting ? 'Open month' : 'Open card';
  }
  // A correction is a new entry: the realm checks the lines are the original's with sides swapped,
  // that it hasn't been reversed already, and that the month is still open. A posting that changed
  // other cards is reversed together with the undoing of those changes, in one batch: the payment
  // comes off the invoice, the stock goes back into its lot. The realm checks the list matches.
  get depositedIn() {
    let m = new Map<string, string>();
    for (let p of journalPostings(this.journalMonths, ['deposit', 'payout']))
      for (let i of p.items)
        if (i?.ref) m.set(i.ref, p.source || seqText(p.month, p.seq));
    return m;
  }
  get roastShare() {
    let m = new Map<string, number>();
    for (let p of journalPostings(this.journalMonths, ['roast'])) {
      let p5000 = p.num('outputPart5000Minor'),
        p5100 = p.num('outputPart5100Minor');
      if (p.fact('outputLot') && p5000 + p5100 > 0)
        m.set(
          `${p.fact('outputSku')}|${p.fact('outputLot')}`,
          p5100 / (p5000 + p5100),
        );
    }
    return m;
  }
  unwindPlan = (p: any) => {
    let fact = (k: string) =>
      String(((p.facts ?? []) as any[]).find((f) => f?.key === k)?.value ?? '');
    let items = ((p.items ?? []) as any[]).filter(Boolean),
      src = p.source ?? '';
    let unwound: any[] = [],
      ops: ((b: any) => unknown)[] = [];
    let doc = (Def: unknown, eq: Record<string, string>) => ({
      every: [{ type: Def }, { on: Def, eq }],
    });
    let byItems = () => {
      unwound = items.map((i) => ({
        ref: i.ref ?? null,
        lot: i.lot ?? null,
        amountMinor: i.amountMinor ?? null,
      }));
    };
    // A draw's cost goes back split the way it came out: packaging lots (1220) to 5100, green (1200) to
    // 5000, a roasted lot by the packaging share its roast recorded, else the posting's average share.
    let lines = ((p.lines ?? []) as any[]).filter(Boolean),
      total = items.reduce((n, i) => n + (i.amountMinor ?? 0), 0);
    let pkg = lines
      .filter((l) => l.account === '5100')
      .reduce((n, l) => n + (l.debitMinor ?? 0), 0);
    let split = (i: any) => {
      let c = i.amountMinor ?? 0,
        s5100 =
          i.account === '1220'
            ? c
            : i.account === '1200'
              ? 0
              : this.roastShare.has(`${i.sku}|${i.lot}`)
                ? Math.round(c * this.roastShare.get(`${i.sku}|${i.lot}`)!)
                : total
                  ? Math.round((c * pkg) / total)
                  : 0;
      return { part5000Minor: c - s5100, part5100Minor: s5100 };
    };
    let lot = (i: any) => doc(StockLot, { sku: i.sku, lot: i.lot });
    switch (p.kind) {
      case 'customer-payment': {
        let cust = fact('customerId') || p.party;
        byItems();
        for (let i of items)
          ops.push((b) =>
            b
              .on(b.find(doc(Invoice, { docNo: i.ref }), { expect: 'one' }))
              .unapplyPayment({
                amountMinor: i.amountMinor,
                paymentNo: src,
                customerId: cust,
              }),
          );
        break;
      }
      case 'bill-payment': {
        let vend = fact('vendorId') || p.party;
        byItems();
        for (let i of items)
          ops.push((b) =>
            b
              .on(
                b.find(doc(Bill, { billNo: i.ref, vendorId: vend }), {
                  expect: 'one',
                }),
              )
              .unapplyPayment({
                amountMinor: i.amountMinor,
                paymentNo: src,
                vendorId: vend,
              }),
          );
        break;
      }
      case 'deposit':
      case 'payout':
        byItems();
        for (let i of items)
          ops.push((b) =>
            b
              .on(
                b.find(
                  {
                    any: [
                      doc(CustomerPayment, { docNo: i.ref, depositNo: src }),
                      doc(SalesReceipt, { docNo: i.ref, depositNo: src }),
                    ],
                  },
                  { expect: 'one' },
                ),
              )
              .unmarkDeposited({ depositNo: src }),
          );
        break;
      case 'bank-payment':
        if (fact('returnPeriodEnd'))
          ops.push((b) =>
            b
              .on(
                b.find(
                  doc(TaxReturn, {
                    agencyId: fact('payee'),
                    periodEnd: fact('returnPeriodEnd'),
                  }),
                  { expect: 'one' },
                ),
              )
              .unmarkPaid({
                paymentNo: src,
                amountMinor: Number(fact('amountMinor')) || 0,
              }),
          );
        break;
      case 'credit-memo':
      case 'write-off': {
        let inv = fact('invoiceNo'),
          cust = fact('customerId') || p.party,
          amt = Number(fact('amountMinor')) || 0,
          op = p.kind === 'credit-memo' ? 'unapplyCredit' : 'unapplyWriteOff';
        unwound = inv ? [{ ref: inv }] : [];
        if (inv)
          ops.push((b) =>
            b
              .on(b.find(doc(Invoice, { docNo: inv }), { expect: 'one' }))
              [op]({ amountMinor: amt, docNo: src, customerId: cust }),
          );
        break;
      }
      case 'vendor-credit': {
        let bill = fact('billNo'),
          vend = fact('vendorId') || p.party,
          amt = Number(fact('amountMinor')) || 0;
        unwound = bill ? [{ ref: bill }] : [];
        if (bill)
          ops.push((b) =>
            b
              .on(
                b.find(doc(Bill, { billNo: bill, vendorId: vend }), {
                  expect: 'one',
                }),
              )
              .unapplyPayment({
                amountMinor: amt,
                paymentNo: src,
                vendorId: vend,
              }),
          );
        break;
      }
      case 'fulfillment':
      case 'count':
      case 'roast':
        byItems();
        for (let i of items)
          ops.push((b) =>
            b.on(b.find(lot(i), { expect: 'one' })).restore({
              qty: i.qty,
              costMinor: i.amountMinor,
              ...split(i),
              docNo: src,
            }),
          );
        if (p.kind === 'roast' && fact('outputLot'))
          ops.push((b) =>
            b
              .on(
                b.find(
                  lot({ sku: fact('outputSku'), lot: fact('outputLot') }),
                  { expect: 'one' },
                ),
              )
              .retire({ docNo: `reverse:${src}` }),
          );
        break;
      case 'landed-cost':
        byItems();
        for (let i of items)
          ops.push((b) =>
            b
              .on(b.find(lot(i), { expect: 'one' }))
              .removeCost({ amountMinor: i.amountMinor, docNo: src }),
          );
        break;
    }
    return { unwound, ops };
  };
  reverse = async () => {
    let p = this.selPosting,
      m = this.selected?.month as any;
    if (!p || !m) return;
    this.busy = true;
    this.error = '';
    try {
      if (p.kind === 'void')
        throw new Error(
          'A void can’t be reversed. Enter the document again instead.',
        );
      let inDeposit = ['customer-payment', 'sales-receipt'].includes(p.kind)
        ? this.depositedIn.get(p.source)
        : undefined;
      if (inDeposit)
        throw new Error(
          `This is in deposit ${inDeposit}. Reverse the deposit first, then this.`,
        );
      let lines = ((p.lines ?? []) as any[]).map((l) => ({
        account: l.account,
        debitMinor: l.creditMinor ?? 0,
        creditMinor: l.debitMinor ?? 0,
        cls: l.cls ?? null,
        loc: l.loc ?? null,
        party: l.party ?? null,
        doc: l.doc ?? null,
      }));
      let today = new Date().toISOString().slice(0, 10),
        date =
          today < m.firstDay
            ? m.firstDay
            : today > m.lastDay
              ? m.lastDay
              : today;
      let { unwound, ops } = this.unwindPlan(p);
      // A bank line matched to or added as this posting goes back for review with it.
      if (p.key)
        ops.push((b) =>
          b
            .on(
              b.find(
                {
                  every: [
                    { type: BankTransaction },
                    { on: BankTransaction, eq: { matchedKey: p.key } },
                  ],
                },
                { expect: 'many' },
              ),
            )
            .unmatch(),
        );
      // Reversing a sale gives its tax back on the reversal's date, which a filed period refuses.
      if (p.kind === 'sales-receipt' || p.kind === 'refund-receipt') {
        let fact = (k: string) =>
          String(
            ((p.facts ?? []) as any[]).find((f) => f?.key === k)?.value ?? '',
          );
        ops.push(
          ...this.taxLocks(
            {
              agencyId: fact('agencyId'),
              taxCode: fact('taxCode'),
              taxMinor: Number(fact('taxMinor')) || 0,
              taxLines: taxLinesFact(fact('taxLines')),
              lines: p.items ?? [],
            },
            date,
          ),
        );
      }
      let entry = {
        seq: p.seq,
        key: `reverse:${m.month}:${p.seq}`,
        date,
        memo: `Reverses ${seqText(m.month, p.seq)}${p.source ? ' · ' + p.source : ''}`,
        party: p.party ?? null,
        source: p.source ?? null,
        lines,
        unwound,
      };
      await (operations(m) as any).atomic((b: any) => [
        b.reverse(entry),
        ...ops.map((op) => op(b)),
      ]);
      this.notify(
        'Reversed',
        ops.length
          ? `The reversing entry posted, and ${ops.length} linked card${ops.length === 1 ? '' : 's'} were put back in the same batch.`
          : 'The realm appended the reversing entry; the original stays as it was.',
      );
      this.selected = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  // ── void: an invoice or bill is never deleted; the void posts its mirror into an open month ──
  @tracked voiding = false;
  @tracked voidReason = '';
  get canVoid() {
    let c = this.sel;
    return (
      !this.selPosting &&
      !!c &&
      c.status === 'posted' &&
      !c.voidDate &&
      c.kind !== 'opening' &&
      ['invoices', 'bills'].includes(this.page) &&
      !(
        (c.paidMinor ?? 0) ||
        (c.creditedMinor ?? 0) ||
        (c.writtenOffMinor ?? 0)
      )
    );
  }
  startVoid = () => {
    this.voiding = true;
    this.voidReason = '';
    this.error = '';
  };
  cancelVoid = () => {
    this.voiding = false;
  };
  setVoidReason = (v: string) => {
    this.voidReason = v;
  };
  confirmVoid = async () => {
    let c = this.sel;
    if (!c) return;
    let docNo = c.docNo ?? c.billNo,
      reason = this.voidReason.trim();
    if (!reason) {
      this.error = 'Say why it is void.';
      return;
    }
    let today = new Date().toISOString().slice(0, 10),
      month =
        this.openMonths.find(
          (m) => today >= m.firstDay && today <= m.lastDay,
        ) ?? this.openMonths.find((m) => m.lastDay >= (c.date ?? ''));
    if (!month) {
      this.error = `No month is open to post the void into. Open ${this.nextMonthLabel} first.`;
      return;
    }
    let date =
      today >= month.firstDay && today <= month.lastDay
        ? today
        : month.firstDay < (c.date ?? '')
          ? c.date
          : month.firstDay;
    let lines = ((c.ledgerLines ?? []) as any[]).filter(Boolean).map((l) => ({
      account: l.account,
      debitMinor: l.creditMinor ?? 0,
      creditMinor: l.debitMinor ?? 0,
      cls: l.cls ?? null,
      loc: l.loc ?? null,
      party: l.party ?? null,
      doc: l.doc ?? docNo,
    }));
    this.busy = true;
    this.error = '';
    try {
      await (operations(month) as any).atomic((b: any) => [
        b.post({
          key: `void:${docNo}`,
          kind: 'void',
          date,
          memo: `Void ${docNo} · ${reason}`,
          party: c.customerId ?? c.vendorId ?? null,
          source: docNo,
          lines,
          facts: [
            { key: 'reason', value: reason },
            { key: 'voids', value: this.page === 'bills' ? 'bill' : 'invoice' },
          ],
          items: [{ ref: docNo, amountMinor: c.totalMinor ?? 0 }],
          preparer: null,
          reviewer: null,
        }),
        b.on(c).void({ date, reason }),
        ...(c instanceof Invoice ? this.taxLocks(c, date) : []).map((op) =>
          op(b),
        ),
      ]);
      this.notify(
        `Voided ${docNo}`,
        `The mirror entry posted on ${date}; the original stays in its month.`,
      );
      this.voiding = false;
      this.selected = undefined;
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  // A sale with tax codes carries its tax lines from the books' rates; posting refuses until they're current.
  get canCalculateTax() {
    let c = this.sel as any;
    return (
      this.selIsDraft &&
      !!c?.constructor?.calculateTax &&
      (taxCodesOf(c).length > 0 ||
        ((c.taxLines ?? []) as any[]).filter(Boolean).length > 0)
    );
  }
  get taxCodesMissing() {
    let ledger = this.args.model.ledger as any;
    return (
      !!ledger?.settings &&
      !settingsOf(ledger).taxCodes &&
      !!this.sel &&
      taxCodesOf(this.sel as any).length > 0
    );
  }
  calculateTax = async () => {
    let c = this.sel;
    if (!c) return;
    this.busy = true;
    this.error = '';
    try {
      await (operations(c as never as CardDef) as any).calculateTax();
      this.notify(
        'Tax calculated',
        "From its tax codes and the books' rates. Post it when it's ready.",
      );
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  get canPost() {
    return (
      this.selIsDraft &&
      !!this.def.post &&
      (!this.selJournalBacked || this.selJournalable)
    );
  }
  get selType(): string {
    return (this.sel as any)?.constructor?.name ?? '';
  }
  // In books kept in journal months, the kinds the journal records post as journal entries: posting
  // the card alone would mark it posted while no month, register or statement included it.
  get selJournalBacked() {
    return (
      this.journalMonths.length > 0 &&
      (!!JOURNAL_KIND[this.selType] || !!pageByType.get(this.selType)?.journal)
    );
  }
  // Such a draft posts into the open journal month of its date, in one batch with the card itself.
  get selJournalable() {
    return this.selJournalBacked && !!JOURNAL_KIND[this.selType];
  }
  get selMonth() {
    return String((this.sel as any)?.date ?? '').slice(0, 7);
  }
  // The drawer is a modal <dialog> in the top layer: close it before opening a card, or its scrim
  // stays over the card that opens and every click lands on the scrim.
  openCard = () => {
    let c = this.sel;
    this.selected = undefined;
    if (c) this.args.viewCard?.(c, 'isolated');
  };
  openCardBeside = () => {
    let c = this.sel;
    this.selected = undefined;
    if (c)
      (this.args as any).viewCard?.(c, 'isolated', {
        openCardInRightMostStack: true,
      });
  };
  editCard = () => {
    let c = this.sel;
    this.selected = undefined;
    if (c) this.args.viewCard?.(c, 'edit');
  };

  // Posting runs the document's own operation; documents that change other cards when they post
  // (a payment and the invoices it pays) send those changes in the same all-or-nothing batch.
  // Each agency a sale owes refuses a date in a period filed with it: sent with the sale's post, its
  // void and its reversal alike. The agencies have to be read first, so the check is never skipped.
  taxLocks = (sale: any, date: string): ((b: any) => unknown)[] => {
    if ((this.agencyData as any)?.isLoading)
      throw new Error(
        'The tax agencies are still loading. Try again in a moment.',
      );
    let doc = this.docMatch;
    return taxByAgency(sale)
      .filter((t) => this.agencyOf(t.agencyId))
      .map(
        (t) => (b: any) =>
          b
            .on(
              b.find(doc(TaxAgency, { agencyId: t.agencyId }), {
                expect: 'one',
              }),
            )
            .checkOpen({ date }),
      );
  };
  docMatch = (Def: unknown, eq: Record<string, string>) => ({
    every: [{ type: Def }, { on: Def, eq }],
  });
  postPlan = (c: any) => {
    let ops: ((b: any) => unknown)[] = [];
    let doc = (Def: unknown, eq: Record<string, string>) => ({
      every: [{ type: Def }, { on: Def, eq }],
    });
    let apps = ((c.applications ?? []) as any[]).filter(Boolean);
    if (c instanceof CustomerPayment)
      for (let a of apps)
        ops.push((b) =>
          b
            .on(b.find(doc(Invoice, { docNo: a.invoiceNo }), { expect: 'one' }))
            .applyPayment({
              amountMinor: a.amountMinor,
              paymentNo: c.docNo,
              customerId: c.customerId,
            }),
        );
    else if (c instanceof BillPayment)
      for (let a of apps)
        ops.push((b) =>
          b
            .on(
              b.find(doc(Bill, { billNo: a.billNo, vendorId: c.vendorId }), {
                expect: 'one',
              }),
            )
            .applyPayment({
              amountMinor: a.amountMinor,
              paymentNo: c.paymentNo,
              vendorId: c.vendorId,
            }),
        );
    else if (c instanceof VendorCredit)
      ops.push((b) =>
        b
          .on(
            b.find(doc(Bill, { billNo: c.billNo, vendorId: c.vendorId }), {
              expect: 'one',
            }),
          )
          .applyPayment({
            amountMinor: c.amountMinor,
            paymentNo: c.docNo,
            vendorId: c.vendorId,
          }),
      );
    else if (c instanceof CreditMemo || c instanceof WriteOff) {
      let op = c instanceof CreditMemo ? 'applyCredit' : 'applyWriteOff';
      ops.push((b) =>
        b
          .on(b.find(doc(Invoice, { docNo: c.invoiceNo }), { expect: 'one' }))
          [op]({
            amountMinor: c.amountMinor,
            docNo: c.docNo,
            customerId: c.customerId,
          }),
      );
    } else if (c instanceof Deposit)
      for (let i of ((c.items ?? []) as any[]).filter(Boolean))
        ops.push((b) =>
          b
            .on(
              b.find(
                {
                  any: [
                    doc(CustomerPayment, { docNo: i.docNo }),
                    doc(SalesReceipt, { docNo: i.docNo }),
                  ],
                },
                { expect: 'one' },
              ),
            )
            .markDeposited({ depositNo: c.docNo, amountMinor: i.amountMinor }),
        );
    // A sale can't post into a period its tax has been filed for, with any agency it owes.
    if (
      c instanceof Invoice ||
      c instanceof SalesReceipt ||
      c instanceof RefundReceipt
    )
      ops.push(...this.taxLocks(c, c.date ?? ''));
    if (c instanceof BankPayment && c.returnPeriodEnd)
      ops.push((b) =>
        b
          .on(
            b.find(
              doc(TaxReturn, {
                agencyId: c.payee ?? '',
                periodEnd: c.returnPeriodEnd!,
              }),
              { expect: 'one' },
            ),
          )
          .markPaid({ paymentNo: c.docNo, amountMinor: c.amountMinor }),
      );
    return ops;
  };
  post = async () => {
    let c = this.sel;
    if (!c) return;
    this.busy = true;
    this.error = '';
    try {
      let ops = this.postPlan(c);
      if (this.selJournalable) {
        let month = this.selMonth;
        if (
          !this.journalMonths.some(
            (m: any) => m?.month === month && m?.status === 'open',
          )
        )
          throw new Error(
            `There is no open journal month for ${month || 'its date'}, so it can't post there.`,
          );
        let entry = journalPostingFor(c, this.selType, (c as any).id);
        // A sale's journal checks the entry's tax lines, read from this copy of the card, are stored.
        let taxed = c instanceof SalesReceipt || c instanceof RefundReceipt;
        await (operations(c as never as CardDef) as any).atomic((b: any) => [
          taxed ? b.journal({ taxLines: plainTaxLines(c) }) : b.journal(),
          b
            .on(
              b.find(
                {
                  every: [
                    { type: JournalMonth },
                    { on: JournalMonth, eq: { month, status: 'open' } },
                  ],
                },
                { expect: 'one' },
              ),
            )
            .post(entry),
          ...ops.map((op) => op(b)),
        ]);
        this.notify(
          'Posted',
          `It's in the ${month} journal, and the card is marked journaled${ops.length ? `; ${ops.length} linked card${ops.length === 1 ? ' was' : 's were'} updated in the same batch` : ''}.`,
        );
        return;
      }
      if (ops.length)
        await (operations(c as never as CardDef) as any).atomic((b: any) => [
          b.post(),
          ...ops.map((op) => op(b)),
        ]);
      else await operations(c as never as CardDef).post();
      this.notify(
        'Posted',
        ops.length
          ? `The realm checked it, stamped who posted it, and updated ${ops.length} linked card${ops.length === 1 ? '' : 's'} in the same batch.`
          : 'The realm checked it and stamped who posted it.',
      );
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };
  get postNote() {
    if (this.taxCodesMissing)
      return "This sale has tax codes, but the books' settings have none, so it can't post. Add taxCodes to the settings, or clear its codes and give it a single rate.";
    if (this.selJournalBacked && !this.selJournalable)
      return "These books keep a journal, and the desk can't post a draft of this kind into it yet: stock movements also draw from their lots.";
    if (this.selJournalable)
      return `These books keep a journal: posting adds this to the ${this.selMonth} journal and marks the card journaled, in one batch${this.sel && this.postPlan(this.sel).length ? ' with the documents it pays, credits or deposits' : ''}. If anything refuses, nothing posts.`;
    if (this.sel && this.postPlan(this.sel).length)
      return 'Posting this also updates the documents it pays, credits or deposits, in the same batch. If any of them refuses, nothing posts.';
    return '';
  }

  // ── creating a draft: the realm creates it, stamps who entered it, and it opens to edit ──
  // The payment terms, read while the New drawer is open, so a draft's due date comes from its
  // party's default terms even when that link isn't loaded on the party.
  termsData = this.args.context?.getCards(
    this,
    () => {
      let type = identifyCard(PaymentTerm);
      return this.newKind && type
        ? ({ filter: { type }, page: { size: 100 } } as never)
        : undefined;
    },
    () => this.refRealms,
    { isLive: true },
  );
  // Rate by address, the stand-in for a tax service: the tax code for the customer's ship-to state.
  taxCodeData = this.args.context?.getCards(
    this,
    () => {
      let type = identifyCard(TaxCode);
      return this.newKind && type
        ? ({ filter: { type }, page: { size: 100 } } as never)
        : undefined;
    },
    () => this.refRealms,
    { isLive: true },
  );
  addressTaxCode = (customer: any) =>
    customer?.shipState
      ? ((((this.taxCodeData as any)?.instances ?? []) as any[]).find(
          (t) => t?.region && t.region === customer.shipState,
        )?.code as string | undefined)
      : undefined;
  termOf = (party: any) => {
    let id = party ? linkedId(party, 'defaultTerms') : null;
    return id
      ? (((this.termsData as any)?.instances ?? []) as any[]).find(
          (t) => t?.id === id,
        )
      : undefined;
  };
  // The party's default terms are linked but not read yet, so Create waits rather than guess a due date.
  get termsPending() {
    let party =
      this.newKind === 'invoice'
        ? (((this.customerData as any)?.instances ?? []) as any[]).find(
            (c) => c?.customerId === this.newParty,
          )
        : this.newKind === 'bill'
          ? (((this.vendorData as any)?.instances ?? []) as any[]).find(
              (v) => v?.vendorId === this.newParty,
            )
          : undefined;
    // Once the terms have loaded without it (outside these realms, deleted), Create goes ahead and
    // the due date is the document date.
    if (
      party &&
      linkedId(party, 'defaultTerms') &&
      !this.termOf(party) &&
      (this.termsData as any)?.isLoading
    )
      return true;
    // A sale for a customer without a default tax code waits for the codes, to find its address's.
    let customer =
      this.newKind === 'invoice' || this.newKind === 'receipt'
        ? (((this.customerData as any)?.instances ?? []) as any[]).find(
            (c) => c?.customerId === this.newParty,
          )
        : undefined;
    return (
      !!customer &&
      !customer.defaultTaxCode &&
      !!customer.shipState &&
      !!(this.taxCodeData as any)?.isLoading
    );
  }
  // The …OnTerms variant links the terms the due date came from; a party with none takes the plain one.
  enterOnTerms = (ops: any, name: string, party: any, values: object) => {
    let term = this.termOf(party),
      date = (values as { date: string }).date,
      due = dueDateFor(date, term) || date;
    return term
      ? ops[`${name}OnTerms`]({ ...values, due, terms: term.id })
      : ops[name]({ ...values, due });
  };
  startNew = (kind: string) => {
    this.newKind = kind;
    this.newParty = '';
    this.paletteOpen = false;
    this.error = '';
  };
  closeNew = () => {
    this.newKind = '';
  };
  get newOpen() {
    return !!this.newKind;
  }
  get newTitle() {
    return (
      (
        {
          invoice: 'New invoice',
          receipt: 'New sales receipt',
          bill: 'New bill',
          journal: 'New journal entry',
          transfer: 'New transfer',
        } as Record<string, string>
      )[this.newKind] ?? 'New'
    );
  }
  // Once the realm keeps a journal, write-once entries are written on an entry pad and posted into it.
  get padKind() {
    return this.journalMonths.length
      ? ((
          {
            journal: 'journal',
            transfer: 'transfer',
            receipt: 'sales-receipt',
          } as Record<string, string>
        )[this.newKind] ?? '')
      : '';
  }
  get newNeedsCustomer() {
    return (
      this.newKind === 'invoice' ||
      (this.newKind === 'receipt' && !this.padKind)
    );
  }
  get newNeedsVendor() {
    return this.newKind === 'bill';
  }
  get customerOptions() {
    return (((this.customerData as any)?.instances ?? []) as any[])
      .filter(Boolean)
      .map((c) => ({ value: c.customerId, label: c.name }));
  }
  get vendorOptions() {
    return (((this.vendorData as any)?.instances ?? []) as any[])
      .filter(Boolean)
      .map((v) => ({ value: v.vendorId, label: v.name }));
  }
  setParty = (v: string) => {
    this.newParty = v;
  };
  get newReady() {
    return !(this.newNeedsCustomer || this.newNeedsVendor) || !!this.newParty;
  }
  createDraft = async () => {
    let stamp = Date.now().toString(36).toUpperCase(),
      date = this.nextOpen || new Date().toISOString().slice(0, 10),
      kind = this.newKind;
    this.busy = true;
    this.error = '';
    try {
      let result: any;
      if (this.padKind) {
        this.busy = false;
        await this.newPad(
          this.padKind,
          this.padKind === 'sales-receipt' ? this.newParty || null : null,
        );
        return;
      }
      if (kind === 'invoice' || kind === 'receipt') {
        let customer = (
          ((this.customerData as any)?.instances ?? []) as any[]
        ).find((c) => c?.customerId === this.newParty);
        // The sale's tax code: its customer's default, or the code for the customer's address.
        let taxCode =
          customer?.defaultTaxCode || this.addressTaxCode(customer) || null;
        let docNo = `${kind === 'invoice' ? 'INV' : 'SR'}-${stamp}`;
        result =
          kind === 'invoice'
            ? await this.enterOnTerms(
                operations(customer),
                'enterInvoice',
                customer,
                {
                  docNo,
                  date,
                  kind: 'sale',
                  memo: '',
                  lines: [],
                  agencyId: null,
                  taxRatePpm: 0,
                  taxMinor: 0,
                  taxCode,
                },
              )
            : await (operations(customer) as any).enterSalesReceipt({
                docNo,
                date,
                memo: '',
                lines: [],
                agencyId: null,
                taxRatePpm: 0,
                taxMinor: 0,
                depositTo: '1010',
                taxCode,
              });
      } else {
        let ledger = this.args.model.ledger as any;
        if (!ledger) throw new Error('This app is not linked to its ledger.');
        let vendor = (
          ((this.vendorData as any)?.instances ?? []) as any[]
        ).find((v) => v?.vendorId === this.newParty);
        if (kind === 'bill')
          result = await this.enterOnTerms(
            operations(ledger),
            'enterBill',
            vendor,
            {
              billNo: `B-${stamp}`,
              vendorId: this.newParty,
              date,
              memo: '',
              lines: [],
            },
          );
        else if (kind === 'journal')
          result = await (operations(ledger) as any).enterJournal({
            docNo: `JE-${stamp}`,
            date,
            memo: '',
            preparer: '',
            reviewer: '',
            support: '',
            lines: [],
          });
        else
          result = await (operations(ledger) as any).enterTransfer({
            docNo: `TR-${stamp}`,
            date,
            memo: '',
            fromAccount: '1000',
            toAccount: '2100',
            amountMinor: 0,
          });
      }
      let id = result?.id ?? result?.card?.id ?? result?.data?.id;
      this.newKind = '';
      this.notify('Draft created', 'Fill it in, then post it from its list.');
      if (id) this.args.viewCard?.(new URL(id), 'edit');
    } catch (e: any) {
      this.error = e?.detail ?? e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  };

  <template>
    <div
      class='lx'
      {{escapeGuard this.drawerOpen this.closeDrawer}}
      {{escapeGuard this.newOpen this.closeNew}}
    >
      <Sidebar
        @label='Ledger'
        @collapsible='offcanvas'
        @width='15.5rem'
        @mobileBreakpoint={{760}}
        @shortcut={{false}}
      >
        <:header>
          <Button
            @tone='neutral'
            @appearance='plain'
            class='brand'
            {{on 'click' (fn this.go 'home')}}
          ><span class='brand-in'>
              <AccordMark class='brand-mark' />
              <span class='brand-name'>Accord</span>
              <span class='brand-sub'>{{if
                  @model.company
                  @model.company
                  'Books'
                }}
                · USD</span>
            </span></Button>
          <div class='anchor'>
            <Button
              @tone='neutral'
              @appearance='plain'
              class='anchor-cell'
              {{on 'click' (fn this.goSpace 'books')}}
            ><span class='anchor-in'><span class='eyebrow'>Books open</span><b
                >{{this.periodOpen}}</b></span></Button>
            <div class='anchor-cell anchor-end'><span class='eyebrow'>Closed
                through</span><b class='mono'>{{this.closedThrough}}</b></div>
          </div>
          <Button
            @tone='neutral'
            @appearance='outlined'
            class='find'
            {{on 'click' this.openPalette}}
          ><span class='find-in'><span>Search or jump to…</span><Kbd
                @value='Mod+K'
              /></span></Button>
        </:header>
        <:nav>
          <SidebarGroup @label='Workspaces'>
            {{#each this.spaces as |w|}}
              <SidebarItem
                @label={{w.label}}
                @badge={{w.badge}}
                @active={{this.isSpace w.id}}
                @onClick={{fn this.goSpace w.id}}
              ><:icon><w.icon
                    width='100%'
                    height='100%'
                  /></:icon></SidebarItem>
            {{/each}}
          </SidebarGroup>
          {{#if (eq this.ws.subject 'chart')}}
            <SidebarGroup @label=''><SidebarItem
                @label='Whole chart'
                @active={{if this.subject false true}}
                @onClick={{fn this.pickSubject ''}}
              /></SidebarGroup>
            {{#each this.chartGroups as |g|}}
              <SidebarGroup @label={{g.label}}>
                {{#each g.accounts as |x|}}
                  <SidebarItem
                    @label={{x.label}}
                    @badge={{x.badge}}
                    @active={{this.isSubject x.id}}
                    @onClick={{fn this.pickSubject x.id}}
                  />
                {{/each}}
              </SidebarGroup>
            {{/each}}
          {{else if this.ws.subject}}
            <SidebarGroup @label={{this.ws.subjectLabel}}>
              {{#if this.ws.overview}}<SidebarItem
                  @label={{this.ws.overview}}
                  @active={{if this.subject false true}}
                  @onClick={{fn this.pickSubject ''}}
                />{{/if}}
              {{#each this.subjects as |x|}}
                <SidebarItem
                  @label={{x.label}}
                  @badge={{x.badge}}
                  @active={{this.isSubject x.id}}
                  @onClick={{fn this.pickSubject x.id}}
                />
              {{/each}}
            </SidebarGroup>
          {{/if}}
        </:nav>
        <:footer><p class='rail-foot'>{{#if this.asOf}}Every figure is computed
              from posted cards. Books closed through
              {{this.asOf}}.{{else if this.journalMonths.length}}An append-only
              journal:
              {{this.journalMonths.length}}
              month cards, corrected only by reversing entries.{{else}}Every
              figure is computed from posted cards.{{/if}}</p></:footer>
        <:default as |bar|>
          <div class='page'>
            <header class='masthead'>
              <SidebarTrigger
                @open={{bar.open}}
                @onToggle={{bar.toggle}}
                @controls={{bar.controls}}
                @label='navigation'
              />
              <div class='masthead-text'>
                <Breadcrumb @items={{this.crumbs}} />
                <h1>{{this.title}}</h1>
                <p class='blurb'>{{this.blurb}}</p>
              </div>
              <div class='masthead-actions'>
                {{#each this.ws.launchers as |l|}}
                  <ButtonGroup
                    @label={{l.label}}
                    @tone='neutral'
                    @appearance='outlined'
                    @size='s'
                  >
                    <Button
                      @tone='neutral'
                      @appearance='outlined'
                      @size='s'
                      {{on 'click' (fn this.launch l.page)}}
                    >{{l.label}}</Button>
                    <Button
                      @tone='neutral'
                      @appearance='outlined'
                      @size='s'
                      aria-label={{this.besideLabel l.label}}
                      title={{this.besideLabel l.label}}
                      {{on 'click' (fn this.launchBeside l.page)}}
                    ><ChevronsRightIcon
                        class='beside-glyph'
                        aria-hidden='true'
                      /></Button>
                  </ButtonGroup>
                {{/each}}
                <Menu @items={{this.newMenu}} @align='end' @label='New'>
                  <:trigger as |open toggle|><Button
                      @tone='primary'
                      @appearance='accent'
                      aria-expanded={{if open 'true' 'false'}}
                      {{on 'click' toggle}}
                    >+ New</Button></:trigger>
                </Menu>
              </div>
            </header>

            {{#if this.error}}<Callout
                @tone='danger'
                @title='The realm refused this'
              >{{this.error}}</Callout>{{/if}}

            {{#if this.ws.pipeline}}
              <section class='pipe' aria-label='Month-end'>
                <div class='pipe-head'><h2>Close ·
                    {{monthLabel this.pipeMonth}}</h2>{{#if this.closeBy}}<span
                      class='muted'
                    >Close by {{this.closeBy}}</span>{{/if}}</div>
                <StepList
                  @steps={{this.pipeline}}
                  @variant='track'
                  @label='Month-end close'
                />
              </section>
            {{/if}}

            {{#if (eq this.space 'books')}}
              <ReadinessPanel
                @title='Books health'
                @summary={{if
                  this.healthy
                  'The books can be trusted as they stand.'
                  'Fix these before relying on the figures.'
                }}
                @gates={{this.health}}
                @verdictText={{if this.healthy 'Every check passes' 'Not yet'}}
              />
            {{/if}}

            {{#if this.tabs.length}}
              <div class='tabs-wrap'><Tabs
                  class='tabs'
                  @options={{this.tabs}}
                  @value={{this.page}}
                  @onValueChange={{this.go}}
                /></div>
            {{/if}}

            {{#if (eq this.page 'home')}}
              <section class='figures' aria-label='The month in figures'>
                <Button
                  @appearance='plain'
                  class='fig'
                  {{on 'click' (fn this.go 'recs')}}
                ><Stat
                    @label='Cash available'
                    @value={{dollars this.latest.cash}}
                    @style='currency'
                    @currency='USD'
                    @maximumFractionDigits={{0}}
                    @delta={{if
                      this.prior
                      (dollars (sub this.latest.cash this.prior.cash))
                    }}
                    @deltaFormat={{this.fmtChange}}
                    @hint='Operating checking, reconciled'
                  /></Button>
                <Button
                  @appearance='plain'
                  class='fig'
                  {{on 'click' (fn this.go 'invoices')}}
                ><Stat
                    @label='Receivables'
                    @value={{dollars this.latest.ar}}
                    @style='currency'
                    @currency='USD'
                    @maximumFractionDigits={{0}}
                    @hint='Open invoices'
                  /></Button>
                <Button
                  @appearance='plain'
                  class='fig'
                  {{on 'click' (fn this.go 'bills')}}
                ><Stat
                    @label='Payables'
                    @value={{dollars this.latest.ap}}
                    @style='currency'
                    @currency='USD'
                    @maximumFractionDigits={{0}}
                    @hint='Open bills'
                  /></Button>
                <Button
                  @appearance='plain'
                  class='fig'
                  {{on 'click' (fn this.go 'receipts')}}
                ><Stat
                    @label='Sales · {{MONTH this.latest.month}}{{if
                      this.latest.open
                      " so far"
                    }}'
                    @value={{dollars this.latest.income}}
                    @style='currency'
                    @currency='USD'
                    @maximumFractionDigits={{0}}
                    @delta={{if
                      this.prior
                      (dollars (sub this.latest.income this.prior.income))
                    }}
                    @deltaFormat={{this.fmtChange}}
                  /></Button>
                <Button
                  @appearance='plain'
                  class='fig'
                  {{on 'click' (fn this.go 'r-pnl')}}
                ><Stat
                    @label='Net income · year to date'
                    @value={{dollars this.ytd.net}}
                    @style='currency'
                    @currency='USD'
                    @maximumFractionDigits={{0}}
                    @hint={{this.margin}}
                  /></Button>
              </section>

              <div class='grid-2'>
                <section class='panel'>
                  <div class='panel-head'><h2>Needs review</h2><span
                      class='muted'
                    >as of {{this.asOf}}</span></div>
                  {{#if this.review.length}}
                    <ul class='todo'>
                      {{#each this.review as |t|}}
                        <li><span class='todo-n'>{{t.n}}</span><span><b
                            >{{t.label}}</b><small
                            >{{t.note}}</small></span><span
                            class='todo-status'
                          ><StatusChip
                              @value={{t.status}}
                              @tone={{t.tone}}
                            /></span><Button
                            @tone='neutral'
                            @size='s'
                            @appearance='outlined'
                            {{on 'click' (fn this.go t.page)}}
                          >{{t.action}}</Button></li>
                      {{/each}}
                    </ul>
                  {{else}}
                    <p class='muted'>Nothing needs review. Every draft is
                      posted, every receipt deposited.</p>
                  {{/if}}
                </section>
                <ReadinessPanel
                  @title='Close · {{this.latestClose.month}}'
                  @summary={{if
                    this.latestClose.closedBy
                    (concat 'Closed by ' this.latestClose.closedBy)
                    'Not closed yet'
                  }}
                  @gates={{this.gates}}
                  @verdictText={{if
                    this.allPass
                    'Every check passes'
                    'Fix these before closing'
                  }}
                >
                  <:actions><Button
                      @tone='neutral'
                      @size='s'
                      @appearance='outlined'
                      {{on 'click' (fn this.go 'closes')}}
                    >Month close</Button></:actions>
                </ReadinessPanel>
              </div>

              <div class='grid-2 wide-left'>
                <section class='panel'>
                  <div class='panel-head'><h2>Sales against costs</h2><span
                      class='muted'
                    >{{this.latest.month}} year by month</span></div>
                  <Chart
                    @rows={{this.trend}}
                    @mark='bar'
                    @x='month'
                    @y='value'
                    @series='kind'
                    @xLabel='Month'
                    @yLabel='USD'
                    @label='Sales against cost of goods and expenses, by month'
                    @height={{240}}
                  />
                </section>
                <section class='panel'>
                  <div class='panel-head'><h2>Where the money goes</h2><Button
                      @tone='neutral'
                      @size='s'
                      @appearance='plain'
                      {{on 'click' (fn this.go 'r-pnl')}}
                    >P&amp;L</Button></div>
                  <BarList
                    @rows={{this.expenseBars}}
                    @format={{this.fmtDollars}}
                    @label='Largest costs this year'
                    @ranked={{true}}
                  />
                </section>
              </div>

            {{else if (eq this.page 'inbox')}}
              {{#if this.inboxRows.length}}
                <StatementTable
                  @label='From operations'
                  @columns={{this.inboxCols}}
                  @rows={{this.inboxRows}}
                  @onRowSelect={{this.postToBooks}}
                  @selectColumn='action'
                />
              {{else}}
                <EmptyState
                  @title='Nothing from operations'
                  @message='Won quotes, commerce invoices and payments, and purchase orders in this realm show here, ready to post to the books.'
                />
              {{/if}}
            {{else if (eq this.page 'coa')}}
              {{#if this.subject}}
                <section class='acct'>
                  <div class='acct-head'>
                    <Descriptions
                      @items={{this.acctFacts}}
                      @columns={{4}}
                      @size='s'
                    />
                    <span class='acct-step'>
                      <Button
                        @tone='neutral'
                        @appearance='outlined'
                        @size='s'
                        @disabled={{if this.prevAccount false true}}
                        {{on 'click' (fn this.stepAccount this.prevAccount)}}
                      >←
                        {{if
                          this.prevAccount
                          this.prevAccount
                          'First'
                        }}</Button>
                      <Button
                        @tone='neutral'
                        @appearance='outlined'
                        @size='s'
                        @disabled={{if this.nextAccount false true}}
                        {{on 'click' (fn this.stepAccount this.nextAccount)}}
                      >{{if this.nextAccount this.nextAccount 'Last'}}
                        →</Button>
                    </span>
                  </div>
                  {{#if this.regLoading}}<div class='skeletons'>{{#each
                        (array 1 2 3 4)
                        as |_|
                      }}<Skeleton @height='2rem' />{{/each}}</div>
                  {{else}}{{#if this.regTruncated}}<Callout @tone='warning'>This
                        register reads only the first page of each kind of
                        document, and one came back full, so later lines and the
                        running balance are missing.</Callout>{{/if}}<StatementTable
                      @label='Register for {{this.subject}}'
                      @columns={{this.regCols}}
                      @rows={{this.regRows}}
                      @density='compact'
                      @zero='blank'
                    />{{/if}}
                </section>
              {{else}}
                <StatementTable
                  @label='Chart of accounts'
                  @columns={{this.chartCols}}
                  @rows={{this.chartRows}}
                  @onRowSelect={{this.pickChartRow}}
                  @selectColumn='code'
                />
              {{/if}}

            {{else if this.def.report}}
              <section class='report'>
                {{#if
                  (eq this.def.report 'profitAndLoss')
                }}<@fields.profitAndLoss @format='isolated' />
                {{else if
                  (eq this.def.report 'balanceSheet')
                }}<@fields.balanceSheet @format='isolated' />
                {{else if (eq this.def.report 'cashFlows')}}<@fields.cashFlows
                    @format='isolated'
                  />
                {{else if
                  (eq this.def.report 'trialBalance')
                }}<@fields.trialBalance @format='isolated' />
                {{else if
                  (eq this.def.report 'openInvoices')
                }}<@fields.openInvoices @format='isolated' />
                {{else if (eq this.def.report 'openBills')}}<@fields.openBills
                    @format='isolated'
                  />
                {{else if (eq this.def.report 'inventory')}}<@fields.inventory
                    @format='isolated'
                  />
                {{else if
                  (eq this.def.report 'fixedAssets')
                }}<@fields.fixedAssets @format='isolated' />
                {{else if (eq this.def.report 'salesTax')}}<@fields.salesTax
                    @format='isolated'
                  />
                {{else if (eq this.def.report 'form1099')}}<@fields.form1099
                    @format='isolated'
                  />
                {{else if (eq this.def.report 'loan')}}<@fields.loan
                    @format='isolated'
                  />
                {{else if (eq this.def.report 'yearClose')}}<@fields.yearClose
                    @format='isolated'
                  />
                {{else if (eq this.def.report 'forecast')}}<@fields.forecast
                    @format='isolated'
                  />
                {{else if
                  (eq this.def.report 'forecastRunRate')
                }}<@fields.forecastRunRate @format='isolated' />
                {{else if
                  (eq this.def.report 'budgetVsActual')
                }}<@fields.budgetVsActual @format='isolated' />
                {{else if (eq this.def.report 'budget')}}<@fields.budget
                    @format='isolated'
                  />
                {{else if (eq this.def.report 'margin')}}<@fields.margin
                    @format='isolated'
                  />
                {{else if
                  (eq this.def.report 'salesByCustomer')
                }}<@fields.salesByCustomer @format='isolated' />
                {{else if
                  (eq this.def.report 'salesByItem')
                }}<@fields.salesByItem @format='isolated' />
                {{else if
                  (eq this.def.report 'expensesByVendor')
                }}<@fields.expensesByVendor @format='isolated' />
                {{else if
                  (eq this.def.report 'generalLedger')
                }}<@fields.generalLedger @format='isolated' />{{/if}}
              </section>

            {{else}}
              <section class='toolbar'>
                {{#if this.chips}}<FilterChips
                    @options={{this.chipOptions}}
                    @value={{this.chip}}
                    @onValueChange={{this.setChip}}
                    @label='Status'
                  />{{/if}}
                <div class='search'><SearchInput
                    @value={{this.query}}
                    @onInput={{this.setQuery}}
                    @placeholder='Filter by number, party or account…'
                    @clearable={{true}}
                  /></div>
                <span class='muted count'>{{this.rows.length}}
                  shown{{#if this.listTotal}}
                    ·
                    {{money this.listTotal}}{{/if}}</span>
                {{#if this.pageNo}}<Button
                    @tone='neutral'
                    @size='s'
                    @appearance='outlined'
                    {{on 'click' this.prevPage}}
                  >← Previous 100</Button>{{/if}}
                {{#if this.hasMore}}<Button
                    @tone='neutral'
                    @size='s'
                    @appearance='outlined'
                    {{on 'click' this.nextPage}}
                  >Next 100 →</Button>{{/if}}
                {{#if this.isRecs}}<Button
                    @size='s'
                    @tone='primary'
                    @appearance='accent'
                    {{on 'click' this.openRec}}
                  >Start reconciliation</Button>{{/if}}
                {{#if this.isBankFeed}}<Button
                    @size='s'
                    @tone='primary'
                    @appearance='accent'
                    {{on 'click' this.openImport}}
                  >Import statement</Button>{{/if}}
                {{#if this.showJournalActions}}
                  <span class='journal-actions'>
                    <Button
                      @tone='neutral'
                      @size='s'
                      @appearance='outlined'
                      @busy={{this.busy}}
                      {{on 'click' this.openMonth}}
                    >Open {{this.nextMonthLabel}}</Button>
                    <Button
                      @size='s'
                      @tone='primary'
                      @appearance='accent'
                      @busy={{this.busy}}
                      {{on 'click' this.newPadHere}}
                    >New pad</Button>
                  </span>
                {{/if}}
              </section>
              {{#if this.loading}}
                <div class='skeletons'>{{#each
                    (array 1 2 3 4 5 6)
                    as |_|
                  }}<Skeleton @height='2.25rem' />{{/each}}</div>
              {{else if this.rows.length}}
                <DataTable
                  @columns={{this.columns}}
                  @rows={{this.rows}}
                  @key={{rowKey}}
                  @label={{this.def.label}}
                  @itemNoun='record'
                  @size='s'
                  @minWidth='52rem'
                >
                  <:cell as |text row col|>
                    {{#if (isKind col 'status')}}<StatusChip
                        @value={{text}}
                        @tone={{toneFor text}}
                      />
                    {{else if (isKind col 'money')}}{{moneyOf (cellOf row col)}}
                    {{else if (isKind col 'qty')}}{{qtyOf (cellOf row col)}}
                    {{else if (isKind col 'accounts')}}<span
                        class='acct-list'
                      >{{#each (this.acctChips (cellOf row col)) as |a|}}<Button
                            @tone='neutral'
                            @size='xs'
                            @appearance='plain'
                            title={{a.name}}
                            aria-label={{a.label}}
                            {{on 'click' (fn this.searchAccount a.code)}}
                          ><Token @value={{a.code}} /></Button>{{/each}}</span>
                    {{else if (eq col.key this.firstKey)}}<Button
                        @tone='neutral'
                        @size='s'
                        @appearance='link'
                        {{on 'click' (fn this.inspect row)}}
                      ><Token @value={{text}} /></Button>
                    {{else}}{{text}}{{/if}}
                  </:cell>
                </DataTable>
              {{else}}
                <EmptyState
                  @title='Nothing here'
                  @message={{if
                    this.query
                    'No records match that filter.'
                    'No records of this kind yet.'
                  }}
                />
              {{/if}}
            {{/if}}
          </div>
        </:default>
      </Sidebar>

      <Drawer
        @open={{this.drawerOpen}}
        @onClose={{this.closeDrawer}}
        @label={{this.selTitle}}
        @placement='end'
      >
        <:title>{{this.selTitle}}</:title>
        <:default>
          {{#if this.sel}}
            {{#if this.selStatus}}<p class='drawer-status'><StatusChip
                  @value={{this.selStatus}}
                  @tone={{toneFor this.selStatus}}
                /></p>{{/if}}
            <Descriptions @items={{this.selFacts}} @columns={{1}} @size='s' />
            {{#if this.recDraft}}
              <h3 class='drawer-h'>Tick what the statement shows</h3>
              <Descriptions @items={{this.recFacts}} @columns={{1}} @size='s' />
              {{#each this.recRows as |i|}}<div class='rec-row'><Checkbox
                    @label={{i.label}}
                    @checked={{i.ticked}}
                    @onCheckedChange={{i.toggle}}
                  /><span class='rec-meta'>{{i.date}}
                    {{moneyOf i.amountMinor}}</span></div>{{else}}<p
                  class='muted'
                >Nothing on the books to tick for this period.</p>{{/each}}
              {{#if this.recFeedFull}}<Callout @tone='info'>More bank lines than
                  the desk reads at once fall in this period, so some lines on
                  the statement may start unticked.</Callout>{{/if}}
            {{/if}}
            {{#if this.selRec}}{{#if this.error}}<Callout
                  @tone='danger'
                >{{this.error}}</Callout>{{/if}}{{/if}}
            {{#if this.bankMatches.length}}
              <h3 class='drawer-h'>Already in the books?</h3>
              {{#each this.bankMatches as |m|}}<div class='bank-match'><span
                    class='muted'
                  >{{m.label}}</span><Button
                    @size='s'
                    @tone='primary'
                    @appearance='outlined'
                    @busy={{this.busy}}
                    {{on 'click' (fn this.matchBankCandidate m)}}
                  >Match</Button></div>{{/each}}
            {{else if this.takenFull}}
              <p class='muted'>Too many lines on this account near this date to
                check what's already matched. Add or exclude it instead.</p>
            {{/if}}
            {{#if this.bankForReview}}
              <h3 class='drawer-h'>Add to the books</h3>
              {{#if this.bankSuggestion}}<p class='muted'>Rule “{{this.bankSuggestion.cardTitle}}”
                  suggests
                  {{this.bankSuggestion.category}}.</p>{{/if}}
              <label class='field'>Account<Select
                  @options={{this.categoryOptions}}
                  @value={{this.bankCategory}}
                  @onChange={{this.setBankCategory}}
                  @placeholder='Choose an account'
                /></label>
              {{#if this.bankLines.length}}<Lines
                  @lines={{this.bankLines}}
                />{{/if}}
              <label class='field'>Or exclude it, because<Input
                  @value={{this.bankExcludeReason}}
                  @onInput={{this.setBankExcludeReason}}
                  @placeholder='A duplicate, a personal charge…'
                /></label>
            {{/if}}
            {{#if this.selBank}}{{#if this.error}}<Callout
                  @tone='danger'
                >{{this.error}}</Callout>{{/if}}{{/if}}
            {{#if this.selLines.length}}
              <h3 class='drawer-h'>Posts to the ledger</h3>
              <Lines @lines={{this.selLines}} />
            {{/if}}
            {{#if this.postNote}}{{#if this.selIsDraft}}<Callout
                  @tone='info'
                >{{this.postNote}}</Callout>{{/if}}{{/if}}
            {{#if this.voiding}}
              <div class='void-box'>
                <p class='muted'>Voiding keeps this record and posts its mirror
                  entry into an open month, so the books net to nothing. It
                  can't be undone; enter it again if it was right.</p>
                <Input
                  @value={{this.voidReason}}
                  @onInput={{this.setVoidReason}}
                  @placeholder='Why is it void?'
                  aria-label='Reason for the void'
                />
                {{#if this.error}}<Callout
                    @tone='danger'
                  >{{this.error}}</Callout>{{/if}}
                <div class='drawer-actions'><Button
                    @tone='neutral'
                    @appearance='outlined'
                    {{on 'click' this.cancelVoid}}
                  >Keep it</Button><Button
                    @tone='danger'
                    @appearance='accent'
                    @busy={{this.busy}}
                    {{on 'click' this.confirmVoid}}
                  >Void {{this.selTitle}}</Button></div>
              </div>
            {{/if}}
          {{/if}}
        </:default>
        <:footer>
          <div class='drawer-actions'>
            <ButtonGroup
              @label={{this.openLabel}}
              @tone='neutral'
              @appearance='outlined'
            >
              <Button
                @tone='neutral'
                @appearance='outlined'
                {{on 'click' this.openCard}}
              >{{this.openLabel}}</Button>
              <Button
                @tone='neutral'
                @appearance='outlined'
                aria-label='Open beside this'
                title='Open beside this'
                {{on 'click' this.openCardBeside}}
              ><ChevronsRightIcon
                  class='beside-glyph'
                  aria-hidden='true'
                /></Button>
            </ButtonGroup>
            {{#if this.canReverse}}<Button
                @tone='danger'
                @appearance='outlined'
                @busy={{this.busy}}
                {{on 'click' this.reverse}}
              >Reverse</Button>{{/if}}
            {{#if this.canVoid}}{{#unless this.voiding}}<Button
                  @tone='danger'
                  @appearance='outlined'
                  {{on 'click' this.startVoid}}
                >Void</Button>{{/unless}}{{/if}}
            {{#if this.selIsDraft}}<Button
                @tone='neutral'
                @appearance='outlined'
                {{on 'click' this.editCard}}
              >Edit draft</Button>{{/if}}
            {{#if this.canFileReturn}}<Button
                @tone='primary'
                @appearance='accent'
                @busy={{this.busy}}
                {{on 'click' this.fileReturn}}
              >File return</Button>{{/if}}
            {{#if this.canPayReturn}}<Button
                @tone='primary'
                @appearance='accent'
                @busy={{this.busy}}
                {{on 'click' this.payReturn}}
              >Pay</Button>{{/if}}
            {{#if this.canStartNextReturn}}<Button
                @tone='neutral'
                @appearance='outlined'
                @busy={{this.busy}}
                {{on 'click' this.startNextReturn}}
              >Start the next return</Button>{{/if}}
            {{#if this.canCalculateTax}}<Button
                @tone='neutral'
                @appearance='outlined'
                @busy={{this.busy}}
                {{on 'click' this.calculateTax}}
              >Calculate tax</Button>{{/if}}
            {{#if this.canPost}}<Button
                @tone='primary'
                @appearance='accent'
                @busy={{this.busy}}
                {{on 'click' this.post}}
              >Post</Button>{{/if}}
            {{#if this.recDraft}}<Button
                @tone='primary'
                @appearance='accent'
                @busy={{this.busy}}
                @disabled={{if this.recDifference true false}}
                {{on 'click' this.finishRec}}
              >Finish</Button>{{/if}}
            {{#if this.recFinished}}<Button
                @tone='neutral'
                @appearance='outlined'
                @busy={{this.busy}}
                {{on 'click' this.undoRec}}
              >Reopen</Button>{{/if}}
            {{#if this.bankForReview}}<Button
                @tone='neutral'
                @appearance='outlined'
                @busy={{this.busy}}
                {{on 'click' this.excludeBankLine}}
              >Exclude</Button><Button
                @tone='primary'
                @appearance='accent'
                @busy={{this.busy}}
                @disabled={{if this.bankCategory false true}}
                {{on 'click' this.addBankLine}}
              >Add to the books</Button>{{/if}}
            {{#if this.bankExcluded}}<Button
                @tone='neutral'
                @appearance='outlined'
                @busy={{this.busy}}
                {{on 'click' this.restoreBankLine}}
              >Put back for review</Button>{{/if}}
          </div>
        </:footer>
      </Drawer>

      <Drawer
        @open={{this.newOpen}}
        @onClose={{this.closeNew}}
        @label={{this.newTitle}}
        @placement='end'
      >
        <:title>{{this.newTitle}}</:title>
        <:default>
          <p class='muted'>The realm creates the draft, stamps who entered it,
            and it opens for you to fill in. Nothing reaches the books until it
            posts. It's dated
            {{this.nextOpen}}, the first open day after the close.</p>
          {{#if this.termsPending}}<p class='muted'>Reading the payment terms,
              for the due date…</p>{{/if}}
          {{#if this.newNeedsCustomer}}<label class='field'>Customer<Select
                @options={{this.customerOptions}}
                @value={{this.newParty}}
                @onChange={{this.setParty}}
                @placeholder='Choose a customer'
              /></label>{{/if}}
          {{#if this.newNeedsVendor}}<label class='field'>Vendor<Select
                @options={{this.vendorOptions}}
                @value={{this.newParty}}
                @onChange={{this.setParty}}
                @placeholder='Choose a vendor'
              /></label>{{/if}}
        </:default>
        <:footer><div class='drawer-actions'><Button
              @tone='neutral'
              @appearance='outlined'
              {{on 'click' this.closeNew}}
            >Cancel</Button><Button
              @tone='primary'
              @appearance='accent'
              @disabled={{if
                this.newReady
                (if this.termsPending true false)
                true
              }}
              @busy={{this.busy}}
              {{on 'click' this.createDraft}}
            >Create draft</Button></div></:footer>
      </Drawer>

      <Drawer
        @open={{this.importOpen}}
        @onClose={{this.closeImport}}
        @label='Import a statement'
        @placement='end'
      >
        <:title>Import a statement</:title>
        <:default>
          <p class='muted'>A CSV or OFX file from the bank. Lines already
            imported are skipped; a bank ID that comes back with a different
            date or amount is refused for a person to look at. New lines wait
            for review and change nothing in the books until they're added.</p>
          <label class='field'>Account<Select
              @options={{this.bankAccountOptions}}
              @value={{this.importAccount}}
              @onChange={{this.setImportAccount}}
              @placeholder='Choose the bank or card account'
            /></label>
          <div class='field'><FileTrigger
              @accept='.csv,.ofx,.qfx,text/csv'
              @label={{if this.importFile this.importFile.name 'Choose a file'}}
              @tone='neutral'
              @appearance='outlined'
              @size='s'
              @onSelect={{this.pickStatement}}
            /></div>
          {{#if this.importFile}}
            <label class='field'>Dates<Select
                @options={{this.dateOrderOptions}}
                @value={{this.dateOrder}}
                @onChange={{this.setDateOrder}}
              /></label>
            <label class='field'>Amounts<Select
                @options={{this.signOptions}}
                @value={{this.signOrder}}
                @onChange={{this.setSignOrder}}
              /></label>
          {{/if}}
          {{#if this.importHeader.length}}
            <h3 class='drawer-h'>Columns</h3>
            {{#each this.columnChoices as |c|}}<label
                class='field'
              >{{c.label}}<Select
                  @options={{this.headerOptions}}
                  @value={{c.value}}
                  @onChange={{c.set}}
                /></label>{{/each}}
          {{/if}}
          {{#if this.importPlan}}
            <h3 class='drawer-h'>What this file brings in</h3>
            <Descriptions
              @items={{this.importSummary}}
              @columns={{1}}
              @size='s'
            />
            {{#each this.importRefusals as |r|}}<p class='muted'>Row
                {{r.row}}:
                {{r.reason}}</p>{{/each}}
          {{/if}}
          {{#if this.importBlocked}}<Callout
              @tone='info'
            >{{this.importBlocked}}</Callout>{{/if}}
          {{#if this.error}}<Callout
              @tone='danger'
            >{{this.error}}</Callout>{{/if}}
        </:default>
        <:footer><div class='drawer-actions'><Button
              @tone='neutral'
              @appearance='outlined'
              {{on 'click' this.closeImport}}
            >Cancel</Button><Button
              @tone='primary'
              @appearance='accent'
              @busy={{this.busy}}
              @disabled={{if this.importBlocked true false}}
              {{on 'click' this.commitImport}}
            >Import</Button></div></:footer>
      </Drawer>

      <Drawer
        @open={{this.recOpen}}
        @onClose={{this.closeRec}}
        @label='Start a reconciliation'
        @placement='end'
      >
        <:title>Start a reconciliation</:title>
        <:default>
          <p class='muted'>One account against one statement. What the last
            reconciliation left outstanding carries in; tick what this statement
            shows, and finish when the difference is $0.00.</p>
          <label class='field'>Account<Select
              @options={{this.bankAccountOptions}}
              @value={{this.recAccount}}
              @onChange={{this.setRecAccount}}
            /></label>
          <label class='field'>Statement date<Input
              @value={{this.recDate}}
              @onInput={{this.setRecDate}}
              @placeholder='2027-01-31'
            /></label>
          <label class='field'>Ending balance<Input
              @value={{this.recEnding}}
              @onInput={{this.setRecEnding}}
              @placeholder='1,801,782.00'
            /></label>
          {{#if this.recStartBlocked}}<Callout
              @tone='info'
            >{{this.recStartBlocked}}</Callout>{{/if}}
          {{#if this.error}}<Callout
              @tone='danger'
            >{{this.error}}</Callout>{{/if}}
        </:default>
        <:footer><div class='drawer-actions'><Button
              @tone='neutral'
              @appearance='outlined'
              {{on 'click' this.closeRec}}
            >Cancel</Button><Button
              @tone='primary'
              @appearance='accent'
              @busy={{this.busy}}
              @disabled={{if this.recStartBlocked true false}}
              {{on 'click' this.startRec}}
            >Start</Button></div></:footer>
      </Drawer>

      <Toaster @store={{this.toasts}} @placement='bottom-end' />
      <CommandPalette
        @items={{this.paletteItems}}
        @open={{this.paletteOpen}}
        @onOpen={{this.openPalette}}
        @onClose={{this.closePalette}}
        @placeholder='Jump to a page, report or account (e.g. 6450), or create something…'
        @label='Command palette'
      />
    </div>
    <style scoped>
      .lx {
        height: 100%;
        min-height: 52rem;
        background: var(--background);
        color: var(--foreground);
      }
      .brand {
        width: 100%;
        height: auto;
        justify-content: start;
        padding: 0.4rem 0.25rem 0.75rem;
      }
      .brand-in {
        display: grid;
        grid-template-columns: auto 1fr;
        column-gap: 0.6rem;
        align-items: center;
        justify-items: start;
        text-align: start;
      }
      .brand-mark {
        grid-row: span 2;
        width: 1.75rem;
        height: 1.75rem;
        color: var(--foreground);
      }
      .brand-name {
        font: 600 1.25rem/1.2 var(--font-sans);
        letter-spacing: -0.005em;
        color: var(--foreground);
      }
      .brand-sub {
        font: 400 0.8125rem/1.4 var(--font-sans);
        color: var(--muted-foreground);
      }
      .eyebrow {
        font: 600 0.75rem/1.33 var(--font-sans);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .find {
        width: 100%;
        margin-bottom: 0.25rem;
      }
      .anchor {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: 0.5rem;
        align-items: end;
        padding: 0 0.25rem 0.6rem;
      }
      .anchor-cell {
        display: grid;
        gap: 0.1rem;
        min-width: 0;
        height: auto;
        padding: 0;
        justify-content: start;
      }
      .anchor-in {
        display: grid;
        gap: 0.1rem;
        justify-items: start;
        text-align: start;
      }
      .anchor-end {
        justify-items: end;
        text-align: end;
      }
      .anchor b {
        font: 600 0.875rem/1.3 var(--font-sans);
        color: var(--foreground);
      }
      .anchor b.mono {
        font-family: var(--font-mono);
        font-weight: 500;
        font-variant-numeric: tabular-nums;
      }
      .beside-glyph {
        width: 0.9rem;
        height: 0.9rem;
      }
      .pipe {
        display: grid;
        gap: 0.6rem;
      }
      .pipe-head {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
        gap: 1rem;
        flex-wrap: wrap;
      }
      .tabs-wrap {
        overflow-x: auto;
        min-width: 0;
      }
      .acct {
        display: grid;
        gap: 1rem;
        min-width: 0;
      }
      .acct-head {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: 1rem;
        align-items: start;
      }
      .acct-step {
        display: inline-flex;
        gap: 0.5rem;
      }
      .tabs {
        width: max-content;
        min-width: 100%;
        white-space: nowrap;
      }
      .find-in {
        display: flex;
        width: 100%;
        justify-content: space-between;
        align-items: center;
        gap: 0.5rem;
      }
      .rail-foot {
        margin: 0;
        padding: 0.75rem 0.25rem;
        font-size: 0.6875rem;
        line-height: 1.5;
        color: var(--muted-foreground);
        border-top: 1px solid var(--border);
      }
      .page {
        container: lx-page / inline-size;
        display: grid;
        gap: 1.25rem;
        padding: 1.25rem 2rem 3rem;
        max-width: 82rem;
        min-width: 0;
      }
      .masthead {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto;
        gap: 1rem;
        align-items: end;
        padding-bottom: 1rem;
        border-bottom: 1px solid var(--border);
      }
      .masthead > :first-child {
        align-self: start;
        margin-top: 0.1rem;
      }
      .masthead h1 {
        font: 400 2rem/1.25 var(--font-serif);
        letter-spacing: -0.01em;
        margin: 0.35rem 0 0.2rem;
      }
      .blurb {
        margin: 0;
        font-size: 0.8125rem;
        color: var(--muted-foreground);
        max-width: 60ch;
        font-variant-numeric: tabular-nums;
      }
      .masthead-actions {
        display: flex;
        gap: 0.5rem;
        align-items: center;
      }
      .journal-actions {
        display: inline-flex;
        gap: 0.5rem;
        margin-inline-start: auto;
      }
      h2 {
        font: 600 1.25rem/1.4 var(--font-sans);
        margin: 0;
      }
      .muted {
        color: var(--muted-foreground);
        font-size: 0.8125rem;
      }
      .figures {
        display: grid;
        grid-template-columns: repeat(5, minmax(0, 1fr));
        border-bottom: 1px solid var(--border);
      }
      .fig {
        display: grid;
        min-width: 0;
        min-height: 0;
        padding: 0.75rem 1rem 1rem;
        border: 0;
        border-inline-start: 1px solid var(--border);
        border-radius: 0;
        color: inherit;
        font-size: inherit;
        font-weight: inherit;
        letter-spacing: inherit;
        text-align: start;
        white-space: normal;
      }
      .fig:first-child {
        border-inline-start: 0;
        padding-inline-start: 0;
      }
      .grid-2 {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        gap: 1.25rem;
        align-items: start;
      }
      .grid-2.wide-left {
        grid-template-columns: minmax(0, 1.5fr) minmax(0, 1fr);
      }
      .panel {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        padding: 1.1rem 1.25rem;
        min-width: 0;
        display: grid;
        gap: 0.75rem;
      }
      .panel-head {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
        gap: 1rem;
        flex-wrap: wrap;
      }
      .todo {
        list-style: none;
        margin: 0;
        padding: 0;
        display: grid;
      }
      .todo li {
        display: grid;
        grid-template-columns: 2.5rem minmax(0, 1fr) auto auto;
        gap: 0.75rem;
        align-items: center;
        min-height: 2.75rem;
        padding: 0.5rem 0;
        border-top: 1px solid var(--border);
      }
      .todo li:first-child {
        border-top: 0;
      }
      .todo small {
        display: block;
        color: var(--muted-foreground);
        font-size: 0.75rem;
        margin-top: 0.1rem;
      }
      .todo-n {
        font: 500 1.25rem/1 var(--font-mono);
        font-variant-numeric: tabular-nums;
        text-align: end;
      }
      .toolbar {
        display: flex;
        flex-wrap: wrap;
        gap: 0.75rem 1rem;
        align-items: center;
      }
      .search {
        flex: 1 1 14rem;
        max-width: 22rem;
      }
      .count {
        margin-inline-start: auto;
        font-variant-numeric: tabular-nums;
      }
      .skeletons {
        display: grid;
        gap: 0.4rem;
      }
      .report {
        min-width: 0;
      }
      .acct-list {
        display: inline-flex;
        flex-wrap: wrap;
        gap: 0.25rem;
      }
      .drawer-status {
        margin: 0 0 0.75rem;
      }
      .drawer-h {
        font: 600 0.75rem/1.33 var(--font-sans);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        margin: 1.25rem 0 0.4rem;
      }
      .lines small {
        display: block;
        color: var(--muted-foreground);
        font-size: 0.6875rem;
      }
      .lines .n {
        text-align: right;
        font-family: var(--font-mono);
        white-space: nowrap;
      }
      .lines .m {
        font-family: var(--font-mono);
        color: var(--muted-foreground);
      }
      .drawer-actions {
        display: flex;
        gap: 0.5rem;
        justify-content: flex-end;
        flex-wrap: wrap;
      }
      .void-box {
        display: grid;
        gap: 0.6rem;
        margin-top: 1rem;
        padding-top: 0.9rem;
        border-top: 1px solid var(--border);
      }
      .rec-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp-4xs);
      }
      .rec-meta {
        font-family: var(--font-mono);
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground);
        white-space: nowrap;
      }
      .bank-match {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--boxel-sp-xs);
        margin-top: var(--boxel-sp-xs);
      }
      .field {
        display: grid;
        gap: 0.35rem;
        margin-top: 1rem;
        font-size: 0.8125rem;
        font-weight: 600;
      }
      @container lx-page (max-width: 64rem) {
        .figures {
          grid-template-columns: repeat(3, minmax(0, 1fr));
        }
        .fig:nth-child(4) {
          border-inline-start: 0;
          padding-inline-start: 0;
        }
        .fig:nth-child(n + 4) {
          border-top: 1px solid var(--border);
        }
      }
      @container lx-page (max-width: 48rem) {
        .grid-2,
        .grid-2.wide-left {
          grid-template-columns: minmax(0, 1fr);
        }
        .figures {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }
        .fig {
          border-inline-start: 0;
          padding-inline-start: 0;
          border-top: 1px solid var(--border);
        }
        .todo li {
          grid-template-columns: 2.5rem minmax(0, 1fr) auto;
        }
        .todo-status {
          display: none;
        }
        .masthead {
          grid-template-columns: auto minmax(0, 1fr);
        }
        .masthead-actions {
          grid-column: 1 / -1;
        }
      }
    </style>
  </template>

  fmtDollars = (v: number) =>
    v.toLocaleString('en-US', {
      style: 'currency',
      currency: 'USD',
      maximumFractionDigits: 0,
    });
  // A change carries its sign, never accounting parentheses.
  fmtChange = (v: number) =>
    v.toLocaleString('en-US', {
      style: 'currency',
      currency: 'USD',
      maximumFractionDigits: 0,
      signDisplay: 'exceptZero',
    });
  get firstKey() {
    return this.def.cols?.[0]?.key ?? '';
  }
}

export class LedgerApp extends CardDef {
  static displayName = 'Accord';
  static icon = BookIcon;
  static prefersWideFormat = true;
  @field company = contains(StringField);
  @field startPage = contains(StringField); // the page it opens on: 'home', or 'journal' in a journal-only realm
  @field ledger = linksTo(() => Ledger);
  @field profitAndLoss = linksTo(() => ProfitAndLoss);
  @field balanceSheet = linksTo(() => BalanceSheet);
  @field cashFlows = linksTo(() => CashFlowStatement);
  @field trialBalance = linksTo(() => TrialBalance);
  @field openInvoices = linksTo(() => OpenInvoicesReport);
  @field openBills = linksTo(() => OpenBillsReport);
  @field inventory = linksTo(() => StockOnHandReport);
  @field fixedAssets = linksTo(() => FixedAssetRegister);
  @field salesTax = linksTo(() => TaxAgency);
  @field form1099 = linksTo(() => Form1099Report);
  @field loan = linksTo(() => Loan);
  @field yearClose = linksTo(() => YearClose);
  @field forecast = linksTo(() => PnlForecast);
  @field forecastRunRate = linksTo(() => PnlForecast);
  @field budget = linksTo(() => Budget);
  @field budgetVsActual = linksTo(() => BudgetVsActual);
  @field margin = linksTo(() => MarginReport);
  @field salesByCustomer = linksTo(() => SalesByCustomer);
  @field salesByItem = linksTo(() => SalesByItem);
  @field expensesByVendor = linksTo(() => ExpensesByVendor);
  @field generalLedger = linksTo(() => GeneralLedger);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: LedgerApp) {
      return this.company ?? 'Accord';
    },
  });

  static isolated = LedgerAppView;

  static embedded = class extends Component<typeof LedgerApp> {
    <template>
      <div class='e'><span class='eyebrow'>Accord</span><b>{{if
            @model.company
            @model.company
            'Books'
          }}</b></div><style scoped>
        .e {
          display: grid;
          gap: 0.2rem;
          padding: 0.9rem 1rem;
        }
        .eyebrow {
          font: 600 0.75rem/1.33 var(--font-sans);
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        b {
          font: 400 1.25rem/1.25 var(--font-serif);
        }
      </style>
    </template>
  };
  static fitted = class extends Component<typeof LedgerApp> {
    <template>
      <div class='f'><span class='eyebrow'>Accord</span><b
        >{{@model.company}}</b></div><style scoped>
        .f {
          height: 100%;
          display: grid;
          align-content: center;
          gap: 0.2rem;
          padding: 0.6rem 0.8rem;
          overflow: hidden;
        }
        .eyebrow {
          font: 600 0.6875rem/1.3 var(--font-sans);
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: var(--muted-foreground);
        }
        b {
          font: 400 1.05rem/1.25 var(--font-serif);
        }
      </style>
    </template>
  };
}

const sub = (a: number | undefined, b: number | undefined) =>
  (a ?? 0) - (b ?? 0);
const array = (...xs: unknown[]) => xs;
