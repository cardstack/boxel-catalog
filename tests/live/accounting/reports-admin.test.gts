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
import {
  accrualEntries,
  ReportView,
} from '../../../cards/accounting/ledger-report-settings';
import { seqText } from '../../../cards/accounting/ledger-journal';
import { ProfitAndLoss } from '../../../cards/accounting/ledger-close';
import { OpenInvoicesReport } from '../../../cards/accounting/ledger-statements';
import {
  detailLines,
  customTable,
  tableCells,
  elementCsv,
  csvText,
  saveParams,
  statementCopy,
  settingsOfCard,
  formulaSafe,
  isMonth,
  ReportActions,
} from '../../../cards/accounting/ledger-report-custom';
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
        statement: '',
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

    test("a saved statement keeps its own date and year, and its view's defaults", function (assert) {
      let aging = new OpenInvoicesReport({ asOf: '2026-09-15' });
      let saved = settingsOfCard(aging);
      assert.deepEqual(JSON.parse(saved.statement), { asOf: '2026-09-15' });
      let shared = new OpenInvoicesReport({ asOf: '2026-12-31' });
      assert.strictEqual(
        (statementCopy(shared, saved) as OpenInvoicesReport).asOf,
        '2026-09-15',
      );

      let pnl = new ProfitAndLoss({ fromMonth: '2026-01', toMonth: '2026-12' });
      let plain = settingsOfCard(pnl);
      pnl.view = new ReportView({
        basis: 'cash',
        columns: 'month',
        compare: 'previous-year',
      });
      let copy = statementCopy(pnl, plain) as ProfitAndLoss;
      assert.deepEqual(
        [copy.view?.basis, copy.view?.columns, copy.view?.compare],
        ['accrual', 'total', 'none'],
        'a report saved with no view reopens with the defaults',
      );
    });

    test('sorting by date honours the order, and a month must be whole', function (assert) {
      let t = customTable(
        LINES,
        custom({ sortDir: 'desc', columns: ['date', 'amount'] }),
        period,
      );
      let dates = t.rows.filter((r) => !r.role).map((r) => r.cells.date);
      assert.strictEqual(dates[0], '2027-01-20');
      assert.strictEqual(dates.at(-1), '2027-01-05');
      assert.true(isMonth('2027-01'));
      assert.false(isMonth(''));
      assert.false(isMonth('2027-13'));
    });

    test('a CSV text cell a spreadsheet would run as a formula is kept as text', function (assert) {
      assert.deepEqual(
        ['=1+1', '+SUM(A1)', '-cmd', '@x', '\tlead', 'plain'].map(formulaSafe),
        ["'=1+1", "'+SUM(A1)", "'-cmd", "'@x", "'\tlead", 'plain'],
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
        { key: 'x', cells: { account: '=HYPERLINK("x")', amount: -100 } },
        {
          key: 't',
          role: 'total' as const,
          cells: { account: 'Net income, after "costs"', amount: -2500 },
        },
      ];
      let exportButton = () =>
        Array.from(
          document.querySelectorAll<HTMLButtonElement>(
            '[data-report-actions] button',
          ),
        ).find((b) => b.textContent?.includes('Export CSV'));
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
        await waitUntil(() => exportButton());
        await click(exportButton()!);
      } finally {
        URL.createObjectURL = create;
      }
      assert.strictEqual(blobs.length, 1, 'one file is downloaded');
      assert.strictEqual(
        await blobs[0].text(),
        'Account,Amount\r\n' +
          'Income,\r\n' +
          '4000 Sales,"$12,345.67"\r\n' +
          '"\'=HYPERLINK(""x"")",($1.00)\r\n' +
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
        statement: '',
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
