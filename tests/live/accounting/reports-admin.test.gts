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
  applySettings,
} from '../../../cards/accounting/ledger-report-custom';
import {
  customizationOf,
  NO_CUSTOMIZATION,
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

      // A statement reopens with the saved settings put back on its card.
      let pnl = new ProfitAndLoss({ fromMonth: '2026-01', toMonth: '2026-12' });
      applySettings(pnl, settings);
      assert.strictEqual(pnl.fromMonth, '2027-01');
      assert.strictEqual(pnl.toMonth, '2027-03');
      assert.deepEqual(
        [pnl.view?.basis, pnl.view?.columns, pnl.view?.compare],
        ['cash', 'month', 'previous-year'],
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
      // Each exported cell is the text that cell shows.
      let shown = Array.from(table.rows).map((tr) =>
        Array.from(tr.cells).map((c) => {
          let visible = Array.from(c.childNodes)
            .filter(
              (n) =>
                !(
                  n instanceof HTMLElement &&
                  n.hasAttribute('data-statement-sr')
                ),
            )
            .map((n) => n.textContent)
            .join('');
          return visible.replace(/\s+/g, ' ').trim();
        }),
      );
      assert.deepEqual(tableCells(table), shown);
      assert.strictEqual(elementCsv(el), csvText(shown));
    });
  });

  module('Catalog | accounting - saved reports', function (hooks) {
    setupRenderingTest(hooks);
    setupLocalIndexing(hooks);

    const realmURL = 'http://test-realm/saved-reports/';
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
