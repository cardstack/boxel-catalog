import { click, waitUntil } from '@ember/test-helpers';
import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import type { CardDef } from '@cardstack/base/card-api';
import { operations } from '@cardstack/base/operations';

import {
  setupLocalIndexing,
  setupIntegrationTestRealm,
  realmConfigCardJSON,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { renderComponent } from '@cardstack/host/tests/helpers/render-component';
import { setupRenderingTest } from '@cardstack/host/tests/helpers/setup';

import { StatementTable } from '../../../cards/accounting/components/statement-table';
import { accrualEntries } from '../../../cards/accounting/ledger-report-settings';
import { seqText } from '../../../cards/accounting/ledger-journal';
import { ProfitAndLoss } from '../../../cards/accounting/ledger-close';
import {
  detailLines,
  customTable,
  tableCells,
  elementCsv,
  csvText,
  saveParams,
  statementCopy,
  PRESETS,
  presetTable,
  presetCustomization,
  ReportActions,
} from '../../../cards/accounting/ledger-report-custom';
import {
  auditEvents,
  filterAudit,
} from '../../../cards/accounting/ledger-audit';
import {
  openDocOf,
  openDocAsOf,
  settledAfter,
  openDocumentsTable,
  lotsTable,
  timeTable,
  projectTable,
} from '../../../cards/accounting/ledger-report-lists';
import {
  customizationOf,
  NO_CUSTOMIZATION,
  SavedReport,
  type Customization,
  type SavedSettings,
} from '../../../cards/accounting/ledger-saved-report';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const TEST_USER = '@testuser:localhost';

// A month of postings: a journal entry and a bill payment in the journal, an invoice and a bill
// still posted as cards.
const SOURCE = {
  journal: [
    {
      month: '2027-01',
      postings: [
        {
          seq: 1,
          kind: 'journal',
          date: '2027-01-05',
          party: '',
          source: '',
          lines: [
            { account: '6000', debitMinor: 3000, cls: 'Retail' },
            { account: '1000', creditMinor: 3000 },
          ],
          items: [],
        },
        {
          seq: 2,
          kind: 'bill-payment',
          date: '2027-01-20',
          party: 'roastery',
          source: 'BP-1',
          lines: [
            { account: '2000', debitMinor: 5000 },
            { account: '1000', creditMinor: 5000 },
          ],
          items: [],
        },
      ],
    },
  ],
  invoices: [
    {
      docNo: 'INV-1',
      customerId: 'harbor',
      date: '2027-01-10',
      ledgerLines: [
        { account: '1100', debitMinor: 12000, date: '2027-01-10' },
        {
          account: '4000',
          creditMinor: 12000,
          cls: 'Wholesale',
          project: 'PRJ-A',
          date: '2027-01-10',
        },
      ],
    },
  ],
  bills: [
    {
      billNo: 'B-1',
      vendorId: 'roastery',
      date: '2027-01-08',
      ledgerLines: [
        {
          account: '6000',
          debitMinor: 5000,
          cls: 'Retail',
          date: '2027-01-08',
        },
        { account: '2000', creditMinor: 5000, date: '2027-01-08' },
      ],
    },
  ],
};
const ACCOUNTS = new Map([
  ['1000', { name: 'Operating bank', section: 'asset' }],
  ['1100', { name: 'Receivables', section: 'asset' }],
  ['2000', { name: 'Payables', section: 'liability' }],
  ['4000', { name: 'Sales', section: 'income' }],
  ['6000', { name: 'Supplies', section: 'expense' }],
]);
const LINES = detailLines(accrualEntries(SOURCE), ACCOUNTS);
const custom = (patch: Partial<Customization>): Customization => ({
  ...NO_CUSTOMIZATION,
  ...patch,
});
const period = { from: '2027-01', to: '2027-01' };

export function runTests() {
  module('Catalog | accounting - custom reports', function () {
    test('grouping by account subtotals each account, and the total balances', function (assert) {
      let t = customTable(LINES, custom({ groupBy: 'account' }), period);
      assert.strictEqual(t.count, 8);
      assert.deepEqual(Object.fromEntries(t.groups), {
        '1000': { debit: 0, credit: 8000, amount: -8000 },
        '1100': { debit: 12000, credit: 0, amount: 12000 },
        '2000': { debit: 5000, credit: 5000, amount: 0 },
        '4000': { debit: 0, credit: 12000, amount: -12000 },
        '6000': { debit: 8000, credit: 0, amount: 8000 },
      });
      assert.deepEqual(t.totals, { debit: 25000, credit: 25000, amount: 0 });
      assert.strictEqual(
        t.rows.length,
        5 + 8 + 5 + 1,
        'a heading, the lines and a subtotal for each account, then the total',
      );
      let sub = t.rows.find((r) => r.key === 's-6000');
      assert.strictEqual(sub?.cells.debit, 8000);
      assert.strictEqual(sub?.cells.date, 'Total for 6000 Supplies');
    });

    test('filters keep only the lines of a class, a vendor, a customer or a project', function (assert) {
      let retail = customTable(
        LINES,
        custom({ filters: [{ dimension: 'cls', value: 'Retail' }] }),
        period,
      );
      assert.strictEqual(retail.count, 2);
      assert.deepEqual(retail.totals, { debit: 8000, credit: 0, amount: 8000 });

      let roastery = customTable(
        LINES,
        custom({ filters: [{ dimension: 'vendor', value: 'roastery' }] }),
        period,
      );
      assert.strictEqual(roastery.count, 4, 'the bill and its payment');
      assert.strictEqual(roastery.totals.amount, 0);

      let both = customTable(
        LINES,
        custom({
          filters: [
            { dimension: 'customer', value: 'harbor' },
            { dimension: 'project', value: 'PRJ-A' },
          ],
        }),
        period,
      );
      assert.strictEqual(both.count, 1);
      assert.deepEqual(both.totals, {
        debit: 0,
        credit: 12000,
        amount: -12000,
      });

      let outside = customTable(LINES, custom({}), {
        from: '2027-02',
        to: '2027-02',
      });
      assert.strictEqual(
        outside.count,
        0,
        'a line outside the period is left out',
      );
    });

    test('sort orders the lines by a column, and the columns are the ones chosen', function (assert) {
      let t = customTable(
        LINES,
        custom({
          sortBy: 'amount',
          sortDir: 'desc',
          columns: ['account', 'amount'],
        }),
        period,
      );
      assert.deepEqual(
        t.cols.map((c) => c.key),
        ['account', 'amount'],
      );
      let lines = t.rows.filter((r) => r.role !== 'total');
      assert.strictEqual(lines[0].cells.amount, 12000);
      assert.strictEqual(lines[0].cells.account, '1100');
      assert.strictEqual(lines.at(-1)?.cells.amount, -12000);
      assert.deepEqual(t.rows.at(-1)?.cells, { account: 'Total', amount: 0 });

      let grouped = customTable(
        LINES,
        custom({ groupBy: 'account', columns: ['amount', 'account'] }),
        period,
      );
      assert.deepEqual(
        grouped.rows.find((r) => r.key === 's-6000')?.cells,
        { account: 'Total for 6000 Supplies', amount: 8000 },
        'a subtotal is labelled in the first column that holds text',
      );
    });

    test('a saved customization and settings read back as they were saved', function (assert) {
      let c = custom({
        columns: ['date', 'account', 'amount'],
        filters: [{ dimension: 'cls', value: 'Retail' }],
        groupBy: 'account',
        sortBy: 'amount',
        sortDir: 'desc',
      });
      let settings: SavedSettings = {
        fromMonth: '2027-01',
        toMonth: '2027-03',
        asOfMonth: '',
        basis: 'cash',
        columns: 'month',
        compare: 'previous-year',
        account: '',
      };
      let p = saveParams({
        name: 'Retail spend',
        kind: 'custom',
        kindLabel: 'Custom report',
        settings,
        custom: c,
        visibility: 'private',
      });
      assert.deepEqual(customizationOf(p), c);

      // A statement reopens as its own copy with the saved settings; the shared card is untouched.
      let pnl = new ProfitAndLoss({ fromMonth: '2026-01', toMonth: '2026-12' });
      let copy = statementCopy(pnl, settings) as ProfitAndLoss;
      assert.true(copy instanceof ProfitAndLoss);
      assert.notStrictEqual(copy, pnl);
      assert.strictEqual(copy.fromMonth, '2027-01');
      assert.strictEqual(copy.toMonth, '2027-03');
      assert.deepEqual(
        [copy.view?.basis, copy.view?.columns, copy.view?.compare],
        ['cash', 'month', 'previous-year'],
      );
      assert.deepEqual(
        [pnl.fromMonth, pnl.toMonth, pnl.view?.columns],
        ['2026-01', '2026-12', undefined],
        'the shared card keeps its own settings',
      );
    });

    test('a quoted CSV value keeps its commas and quotes', function (assert) {
      assert.strictEqual(
        csvText([
          ['Name', 'Amount'],
          ['Harbor, Inc.', 'Say "hi"'],
        ]),
        'Name,Amount\r\n"Harbor, Inc.","Say ""hi"""\r\n',
      );
    });
  });

  module('Catalog | accounting - report library', function () {
    const preset = (kind: string, from = '2027-01', to = '2027-01') =>
      presetTable(
        LINES,
        PRESETS[kind],
        presetCustomization(PRESETS[kind]),
        from,
        to,
      );

    test('profit and loss detail lists the income and expense lines by account', function (assert) {
      let t = preset('pnl-detail');
      assert.strictEqual(t.count, 3);
      assert.deepEqual(Object.fromEntries(t.groups), {
        '4000': { debit: 0, credit: 12000, amount: -12000 },
        '6000': { debit: 8000, credit: 0, amount: 8000 },
      });
      assert.strictEqual(t.totals.amount, -4000, 'a profit of $40.00');
    });

    test('balance sheet detail reads the balance accounts only', function (assert) {
      let t = preset('bs-detail');
      assert.deepEqual([...t.groups.keys()], ['1000', '1100', '2000']);
      assert.strictEqual(
        t.totals.amount,
        4000,
        'the profit, still in the books',
      );
    });

    test('customer and vendor balance detail carry every posting up to the period end', function (assert) {
      let customers = preset('customer-balance-detail', '2027-02', '2027-02');
      assert.strictEqual(customers.count, 1, "January's invoice is still owed");
      assert.deepEqual(Object.fromEntries(customers.groups), {
        harbor: { debit: 12000, credit: 0, amount: 12000 },
      });
      let vendors = preset('vendor-balance-detail');
      assert.deepEqual(Object.fromEntries(vendors.groups), {
        roastery: { debit: 5000, credit: 5000, amount: 0 },
      });
    });

    test('the journal lists each entry in date order with its lines', function (assert) {
      let t = preset('journal');
      assert.deepEqual(
        t.rows.filter((r) => r.role === 'heading').map((r) => r.cells.date),
        [seqText('2027-01', 1), 'B-1', 'INV-1', 'BP-1 · J-2027-01-0002'],
      );
      assert.deepEqual(t.totals, { debit: 25000, credit: 25000, amount: 0 });
    });

    test('transaction detail by account subtotals every account', function (assert) {
      let t = preset('transaction-detail');
      assert.strictEqual(t.groups.size, 5);
      assert.strictEqual(t.groups.get('1000')?.amount, -8000);
    });

    const DOCS = [
      {
        docNo: 'INV-1',
        customerId: 'harbor',
        date: '2027-01-10',
        due: '2027-02-09',
        totalMinor: 12000,
        openMinor: 12000,
      },
      {
        docNo: 'INV-2',
        customerId: 'harbor',
        date: '2027-02-01',
        due: '2027-03-03',
        totalMinor: 5000,
        openMinor: 2000,
      },
      {
        docNo: 'INV-3',
        customerId: 'juniper',
        date: '2027-01-15',
        due: '2027-01-30',
        totalMinor: 8000,
        openMinor: 0,
      },
      {
        docNo: 'INV-4',
        customerId: 'juniper',
        date: '2027-03-05',
        due: '2027-04-04',
        totalMinor: 3000,
        openMinor: 3000,
      },
    ].map(openDocOf);

    test('open invoices lists each invoice with a balance on the date, by customer', function (assert) {
      let t = openDocumentsTable(DOCS, '2027-02-20', 'open-invoices');
      assert.strictEqual(t.count, 2);
      assert.strictEqual(t.totalMinor, 14000);
      let sub = t.rows.find((r) => r.key === 's-harbor');
      assert.strictEqual(sub?.cells.open, 14000);
    });

    test('collections keeps only the invoices past due, with the days late', function (assert) {
      let t = openDocumentsTable(DOCS, '2027-02-20', 'collections');
      assert.strictEqual(t.count, 1);
      assert.strictEqual(t.totalMinor, 12000);
      let line = t.rows.find((r) => r.key === 'harbor-INV-1');
      assert.strictEqual(line?.cells.late, 11);
    });

    test('the journal keeps an entry apart from a reversal or void of the same document', function (assert) {
      let lines = detailLines(
        accrualEntries({
          journal: [
            {
              month: '2027-02',
              postings: [
                {
                  seq: 1,
                  kind: 'sales-receipt',
                  date: '2027-02-02',
                  source: 'SR-1',
                  lines: [
                    { account: '1000', debitMinor: 900 },
                    { account: '4000', creditMinor: 900 },
                  ],
                  items: [],
                },
                {
                  seq: 2,
                  kind: 'void',
                  date: '2027-02-03',
                  source: 'SR-1',
                  lines: [
                    { account: '4000', debitMinor: 900 },
                    { account: '1000', creditMinor: 900 },
                  ],
                  items: [],
                },
              ],
            },
          ],
        }),
        ACCOUNTS,
      );
      let t = presetTable(
        lines,
        PRESETS.journal,
        presetCustomization(PRESETS.journal),
        '2027-02',
        '2027-02',
      );
      assert.deepEqual(
        t.rows.filter((r) => r.role === 'heading').map((r) => r.cells.date),
        ['SR-1 · J-2027-02-0001', 'SR-1 · J-2027-02-0002'],
      );
    });

    test('open invoices as of a date add back what was paid, credited or written off after it', function (assert) {
      let invoices = [
        {
          docNo: 'INV-1',
          customerId: 'harbor',
          date: '2027-01-10',
          due: '2027-02-09',
          totalMinor: 12000,
          openMinor: 0,
        },
        {
          docNo: 'INV-2',
          customerId: 'harbor',
          date: '2027-01-12',
          due: '2027-02-11',
          totalMinor: 4000,
          openMinor: 1000,
        },
        {
          docNo: 'INV-3',
          customerId: 'juniper',
          date: '2027-01-15',
          due: '2027-01-30',
          totalMinor: 8000,
          openMinor: 0,
          voidDate: '2027-02-01',
        },
      ];
      let after = settledAfter('2027-02-20', {
        customerPayments: [
          {
            status: 'posted',
            date: '2027-03-01',
            applications: [{ invoiceNo: 'INV-1', amountMinor: 7000 }],
          },
          {
            status: 'posted',
            date: '2027-02-15',
            applications: [{ invoiceNo: 'INV-2', amountMinor: 3000 }],
          },
        ],
        credits: [
          {
            status: 'posted',
            date: '2027-03-02',
            invoiceNo: 'INV-1',
            amountMinor: 1000,
          },
        ],
        journal: [
          // A payment made before the date and reversed after it settled INV-2 on the date.
          {
            month: '2027-02',
            postings: [
              {
                seq: 1,
                kind: 'customer-payment',
                date: '2027-02-10',
                party: 'harbor',
                lines: [],
                items: [{ ref: 'INV-2', amountMinor: 500 }],
              },
              {
                seq: 2,
                kind: 'reversal',
                reverses: 1,
                date: '2027-03-01',
                party: 'harbor',
                lines: [],
                items: [],
              },
            ],
          },
          {
            month: '2027-03',
            postings: [
              {
                seq: 1,
                kind: 'customer-payment',
                date: '2027-03-05',
                party: 'harbor',
                lines: [],
                items: [{ ref: 'INV-1', amountMinor: 4000 }],
              },
            ],
          },
        ],
      });
      assert.deepEqual(Object.fromEntries(after), {
        'invoice:INV-1': 12000,
        'invoice:INV-2': -500,
      });
      let docs = invoices
        .map((d) => openDocAsOf(d, '2027-02-20', after))
        .filter((d): d is NonNullable<typeof d> => !!d);
      assert.deepEqual(
        docs.map((d) => [d.number, d.openMinor]),
        [
          ['INV-1', 12000],
          ['INV-2', 500],
        ],
        'a payment after the date counts as open, one reversed after it as paid; the voided invoice is gone',
      );
      let collections = openDocumentsTable(docs, '2027-02-20', 'collections');
      assert.deepEqual(
        collections.rows
          .filter((r) => r.data?.openDoc)
          .map((r) => [r.cells.number, r.cells.late, r.cells.open]),
        [
          ['INV-1', 11, 12000],
          ['INV-2', 9, 500],
        ],
      );
    });

    test('unpaid bills reads the bills the same way', function (assert) {
      let t = openDocumentsTable(
        [
          openDocOf({
            billNo: 'B-1',
            vendorId: 'roastery',
            date: '2027-01-08',
            due: '2027-02-07',
            totalMinor: 5000,
            openMinor: 5000,
            rateMicros: 1_100_000,
          }),
        ],
        '2027-02-20',
        'unpaid-bills',
      );
      assert.strictEqual(
        t.totalMinor,
        5500,
        'in the home currency at the booked rate',
      );
    });

    test('inventory valuation detail values each lot with stock left', function (assert) {
      let t = lotsTable([
        {
          sku: 'ETH',
          lot: 'A',
          received: '2027-01-02',
          remainingQty: 2000,
          remainingCostMinor: 3000,
        },
        {
          sku: 'ETH',
          lot: 'B',
          received: '2027-01-10',
          remainingQty: 500,
          remainingCostMinor: 1000,
        },
        {
          sku: 'COL',
          lot: 'C',
          received: '2027-01-03',
          remainingQty: 0,
          remainingCostMinor: 0,
        },
      ]);
      assert.strictEqual(t.count, 2);
      assert.strictEqual(t.totalMinor, 4000);
      assert.deepEqual(
        t.rows.filter((r) => !r.role).map((r) => r.cells.unit),
        [1500, 2000],
      );
      assert.deepEqual(t.rows.find((r) => r.key === 's-ETH')?.cells, {
        lot: 'Total for ETH',
        qty: 2500,
        value: 4000,
      });
    });

    test('time by customer adds up hours and what is still to bill', function (assert) {
      let t = timeTable(
        [
          {
            date: '2027-01-05',
            customerId: 'harbor',
            worker: 'ana',
            hours: 2500,
            billable: true,
            billed: true,
            amountMinor: 25000,
          },
          {
            date: '2027-01-06',
            customerId: 'harbor',
            worker: 'ana',
            hours: 1000,
            billable: true,
            billed: false,
            amountMinor: 10000,
          },
          {
            date: '2027-01-07',
            customerId: 'juniper',
            worker: 'ben',
            hours: 500,
            billable: false,
            billed: false,
            amountMinor: 0,
          },
          {
            date: '2027-02-01',
            customerId: 'harbor',
            worker: 'ana',
            hours: 9999,
            billable: true,
            billed: false,
            amountMinor: 99990,
          },
        ],
        '2027-01',
        '2027-01',
      );
      assert.deepEqual(t.rows.find((r) => r.key === 'harbor')?.cells, {
        customer: 'harbor',
        hours: 3500,
        billable: 3500,
        billed: 2500,
        unbilled: 10000,
      });
      assert.deepEqual(t.rows.at(-1)?.cells, {
        customer: 'Total',
        hours: 4000,
        billable: 3500,
        billed: 2500,
        unbilled: 10000,
      });
    });

    test('profit by project totals its projects', function (assert) {
      let t = projectTable([
        {
          project: 'PRJ-A',
          incomeMinor: 50000,
          costMinor: 23000,
          laborMinor: 12333,
          profitMinor: 14667,
        },
        {
          project: 'PRJ-B',
          incomeMinor: 0,
          costMinor: 0,
          laborMinor: 3752,
          profitMinor: -3752,
        },
      ]);
      assert.strictEqual(t.totalMinor, 10915);
      assert.strictEqual(t.rows.at(-1)?.cells.labor, 16085);
    });
  });

  module('Catalog | accounting - audit log', function () {
    const SOURCES = {
      journal: [
        {
          month: '2027-01',
          lastDay: '2027-01-31',
          closedBy: '@owner:books',
          postings: [
            {
              seq: 1,
              kind: 'journal',
              date: '2027-01-05',
              source: 'JE-1',
              preparer: '@ana:books',
              reviewer: '@ben:books',
              postedBy: '@ana:books',
              postedAt: '2027-01-05 09:00:00',
              lines: [
                { account: '6000', debitMinor: 3000 },
                { account: '1000', creditMinor: 3000 },
              ],
            },
            {
              seq: 2,
              kind: 'reversal',
              reverses: 1,
              date: '2027-01-06',
              source: 'JE-1',
              postedBy: '@ben:books',
              postedAt: '2027-01-06 14:30:00',
              lines: [
                { account: '1000', debitMinor: 3000 },
                { account: '6000', creditMinor: 3000 },
              ],
            },
            {
              seq: 3,
              kind: 'void',
              date: '2027-01-07',
              source: 'INV-9',
              postedBy: '@ana:books',
              postedAt: '2027-01-07 08:15:00',
              lines: [
                { account: '4000', debitMinor: 1200 },
                { account: '1100', creditMinor: 1200 },
              ],
            },
          ],
        },
      ],
      documents: [
        {
          docNo: 'INV-1',
          date: '2027-01-03',
          status: 'posted',
          enteredBy: '@cy:books',
          postedBy: '@ana:books',
          totalMinor: 12000,
          rateMicros: 1_100_000,
        },
        // Voided in the journal: its void is logged once, from the journal.
        {
          docNo: 'INV-9',
          date: '2027-01-02',
          status: 'journaled',
          voidDate: '2027-01-07',
          voidedBy: '@ana:books',
          totalMinor: 1200,
        },
      ],
      closes: [{ month: '2026-12', closedBy: '@owner:books', debitMinor: 500 }],
    };

    test('the log lists postings, reversals, voids and closes newest first, with who and when', function (assert) {
      let events = auditEvents(SOURCES);
      assert.deepEqual(
        events.map((e) => [e.kind, e.who, e.at || e.date, e.doc]),
        [
          ['closed', '@owner:books', '2027-01-31', 'Journal 2027-01'],
          ['void', '@ana:books', '2027-01-07 08:15:00', 'INV-9'],
          ['reversal', '@ben:books', '2027-01-06 14:30:00', 'JE-1'],
          ['posted', '@ana:books', '2027-01-05 09:00:00', 'JE-1'],
          ['entered', '@cy:books', '2027-01-03', 'INV-1'],
          ['posted', '@ana:books', '2027-01-03', 'INV-1'],
          ['closed', '@owner:books', '2026-12-31', 'Month close 2026-12'],
        ],
      );
      assert.strictEqual(
        events.find((e) => e.kind === 'entered')?.amountMinor,
        13200,
        'a document in another currency is logged in the home currency',
      );
      let reversal = events.find((e) => e.kind === 'reversal');
      assert.strictEqual(reversal?.amountMinor, 3000);
      assert.ok(
        reversal?.detail.startsWith(`Reverses ${seqText('2027-01', 1)}`),
      );
      let posted = events.find((e) => e.at === '2027-01-05 09:00:00');
      assert.ok(posted?.detail.includes('reviewed by @ben:books'));
    });

    test('the log filters by user, kind and period', function (assert) {
      let events = auditEvents(SOURCES);
      assert.deepEqual(
        filterAudit(events, { who: '@ana:books' }).map((e) => e.kind),
        ['void', 'posted', 'posted'],
      );
      assert.strictEqual(filterAudit(events, { kind: 'closed' }).length, 2);
      assert.deepEqual(
        filterAudit(events, { from: '2027-01-05', to: '2027-01-06' }).map(
          (e) => e.kind,
        ),
        ['reversal', 'posted'],
      );
    });
  });

  module('Rendering | Catalog | accounting - report CSV', function (hooks) {
    setupRenderingTest(hooks);

    test('the CSV is the table as shown, negative amounts in their parentheses', async function (assert) {
      let t = customTable(
        LINES,
        custom({
          columns: ['account', 'doc', 'credit', 'amount'],
          filters: [{ dimension: 'account', value: '1000' }],
        }),
        period,
      );
      const cols = t.cols,
        rows = t.rows;
      await renderComponent(
        <template>
          <div data-test-report>
            <StatementTable @label='Bank' @columns={{cols}} @rows={{rows}} />
          </div>
        </template>,
      );
      let el = document.querySelector('[data-test-report]')!;
      let table = el.querySelector('table') as HTMLTableElement;
      assert.deepEqual(tableCells(table), [
        ['Account', 'No.', 'Credit', 'Amount'],
        ['1000', seqText('2027-01', 1), '$30.00', '($30.00)'],
        ['1000', 'BP-1', '$50.00', '($50.00)'],
        ['Total', '', '$80.00', '($80.00)'],
      ]);
      assert.strictEqual(
        elementCsv(el),
        'Account,No.,Credit,Amount\r\n' +
          '1000,J-2027-01-0001,$30.00,($30.00)\r\n' +
          '1000,BP-1,$50.00,($50.00)\r\n' +
          'Total,,$80.00,($80.00)\r\n',
      );
    });

    test('Export CSV on a desk statement downloads its tables as shown', async function (assert) {
      const cols = [
        { key: 'account', label: 'Account', kind: 'code' as const },
        { key: 'amount', label: 'Amount', kind: 'amount' as const },
      ];
      const rows = [
        { key: 'h', role: 'heading' as const, cells: { account: 'Income' } },
        { key: '4000', cells: { account: '4000 Sales', amount: 1234567 } },
        {
          key: 't',
          role: 'total' as const,
          cells: { account: 'Net income, after "costs"', amount: -2500 },
        },
      ];
      let blobs: Blob[] = [];
      let create = URL.createObjectURL;
      URL.createObjectURL = (b: Blob | MediaSource) => {
        blobs.push(b as Blob);
        return 'blob:test';
      };
      try {
        await renderComponent(
          <template>
            <section data-report-body>
              <ReportActions @kind='r-pnl' @kindLabel='Profit and loss' />
              <StatementTable @label='P&L' @columns={{cols}} @rows={{rows}} />
            </section>
          </template>,
        );
        await click('[data-test-export-csv]');
      } finally {
        URL.createObjectURL = create;
      }
      assert.strictEqual(blobs.length, 1, 'one file is downloaded');
      assert.strictEqual(
        await blobs[0].text(),
        'Account,Amount\r\n' +
          'Income,\r\n' +
          '4000 Sales,"$12,345.67"\r\n' +
          '"Net income, after ""costs""",($25.00)\r\n',
      );
    });
  });

  module('Catalog | accounting - saved reports', function (hooks) {
    setupRenderingTest(hooks);
    setupLocalIndexing(hooks);

    const realmURL = 'http://test-realm/saved-reports/';
    const COLLEAGUE = '@colleague:localhost';
    const savedJSON = (name: string, visibility: string, savedBy: string) => ({
      data: {
        type: 'card',
        attributes: { name, kind: 'custom', visibility, savedBy },
        meta: {
          adoptsFrom: {
            module: `${catalogRealmURL}cards/accounting/ledger-saved-report`,
            name: 'SavedReport',
          },
        },
      },
    });
    let mockMatrixUtils = setupMockMatrix(hooks, {
      loggedInAs: TEST_USER,
      activeRealms: [realmURL],
      autostart: true,
    });

    hooks.beforeEach(async function () {
      await setupIntegrationTestRealm({
        mockMatrixUtils,
        realmURL,
        enforcePermissions: true,
        permissions: { [TEST_USER]: ['read', 'write', 'realm-owner'] },
        contents: {
          'realm.json': realmConfigCardJSON({ name: 'Books' }),
          'SavedReport/shared.json': savedJSON('Shared', 'shared', COLLEAGUE),
          'SavedReport/theirs.json': savedJSON('Theirs', 'private', COLLEAGUE),
          'SavedReport/mine.json': savedJSON('Mine', 'private', TEST_USER),
          'Ledger/books.json': {
            data: {
              type: 'card',
              attributes: { company: 'Test books' },
              meta: {
                adoptsFrom: {
                  module: `${catalogRealmURL}cards/accounting/ledger-cards`,
                  name: 'Ledger',
                },
              },
            },
          },
        },
      });
      await getService('realm').login(realmURL);
      getService('operations');
    });

    test('a private report lists only for the user who saved it; a shared one for everyone', async function (assert) {
      let found = operations(SavedReport).visibleReports(
        {},
        { realms: [realmURL] },
      );
      await waitUntil(() => !found.isLoading && found.entries.length > 0, {
        timeout: 15000,
      });
      assert.deepEqual(
        found.entries.map((e) => e.id).sort(),
        [`${realmURL}SavedReport/mine`, `${realmURL}SavedReport/shared`],
        "the colleague's private report isn't listed",
      );
    });

    test('a saved report reopens with its settings and customization, stamped with who saved it', async function (assert) {
      let store = getService('store');
      let ledger = (await store.get(`${realmURL}Ledger/books`)) as CardDef;
      let c = custom({
        columns: ['date', 'account', 'debit', 'credit'],
        filters: [
          { dimension: 'cls', value: 'Retail' },
          { dimension: 'vendor', value: 'roastery' },
        ],
        groupBy: 'account',
        sortBy: 'debit',
        sortDir: 'desc',
      });
      let settings: SavedSettings = {
        fromMonth: '2027-01',
        toMonth: '2027-06',
        asOfMonth: '',
        basis: 'cash',
        columns: '',
        compare: '',
        account: '',
      };
      let result: any = await (operations(ledger) as any).saveReport(
        saveParams({
          name: 'Retail from the roastery',
          kind: 'custom',
          kindLabel: 'Custom report',
          settings,
          custom: c,
          visibility: 'shared',
        }),
      );
      let saved: any = await store.get(result.id);
      assert.strictEqual(saved.name, 'Retail from the roastery');
      assert.strictEqual(saved.kind, 'custom');
      assert.strictEqual(
        saved.savedBy,
        TEST_USER,
        'the realm stamps the saver',
      );
      assert.deepEqual(saved.settings(), settings);
      assert.deepEqual(saved.customization(), c);
      // And the report it reopens reads those lines the same way.
      let reopened = customTable(LINES, saved.customization(), period);
      assert.deepEqual(reopened.totals, {
        debit: 5000,
        credit: 0,
        amount: 5000,
      });
    });
  });
}
