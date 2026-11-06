import { module, test } from 'qunit';

import {
  profitBy,
  profitByProject,
  type ProfitSource,
} from '../../../cards/accounting/ledger-dimensions';

const SOURCE: ProfitSource = {
  fromDate: '2027-01-01',
  toDate: '2027-01-31',
  accounts: [
    { code: '1000', type: 'bank' },
    { code: '4000', type: 'income' },
    { code: '5000', type: 'cogs' },
    { code: '6000', type: 'expense' },
  ],
  invoices: [
    {
      ledgerLines: [
        { account: '1000', debitMinor: 50000 },
        {
          account: '4000',
          creditMinor: 50000,
          cls: 'Wholesale',
          project: 'PRJ-A',
        },
      ],
    },
    {
      ledgerLines: [
        { account: '1000', debitMinor: 12000 },
        { account: '4000', creditMinor: 12000, cls: 'Retail' },
      ],
    },
  ],
  bills: [
    {
      ledgerLines: [
        {
          account: '5000',
          debitMinor: 20000,
          cls: 'Wholesale',
          project: 'PRJ-A',
        },
        { account: '1000', creditMinor: 20000 },
      ],
    },
  ],
  journal: [
    {
      ledgerLines: [
        {
          account: '6000',
          date: '2027-01-15',
          debitMinor: 3000,
          cls: 'Wholesale',
          project: 'PRJ-A',
        },
        { account: '1000', date: '2027-01-15', creditMinor: 3000 },
        { account: '6000', date: '2027-01-20', debitMinor: 1500 },
        { account: '1000', date: '2027-01-20', creditMinor: 1500 },
        {
          account: '6000',
          date: '2027-02-01',
          debitMinor: 9999,
          cls: 'Retail',
          project: 'PRJ-A',
        },
        { account: '1000', date: '2027-02-01', creditMinor: 9999 },
      ],
    },
  ],
};

export function runTests() {
  module('Catalog | accounting - profit by class and project', function () {
    test('profit by class groups income, cost of goods and expenses by class', function (assert) {
      assert.deepEqual(profitBy(SOURCE, 'cls'), [
        { key: '(none)', incomeMinor: 0, cogsMinor: 0, expenseMinor: 1500 },
        { key: 'Retail', incomeMinor: 12000, cogsMinor: 0, expenseMinor: 0 },
        {
          key: 'Wholesale',
          incomeMinor: 50000,
          cogsMinor: 20000,
          expenseMinor: 3000,
        },
      ]);
    });

    test('profit by project subtracts costs and labor, and gives a labor-only project a row', function (assert) {
      let rows = profitByProject(SOURCE, [
        { projectId: 'PRJ-A', hours: 2500, costRateMinor: 3333 },
        { projectId: 'PRJ-A', hours: 1000, costRateMinor: 4000 },
        { projectId: 'PRJ-B', hours: 1500, costRateMinor: 2501 },
        { hours: 8000, costRateMinor: 5000 },
        undefined,
      ]);
      assert.deepEqual(rows, [
        {
          project: 'PRJ-A',
          incomeMinor: 50000,
          costMinor: 23000,
          laborMinor: 8333 + 4000,
          profitMinor: 50000 - 23000 - 12333,
        },
        {
          project: 'PRJ-B',
          incomeMinor: 0,
          costMinor: 0,
          laborMinor: 3752,
          profitMinor: -3752,
        },
      ]);
    });
  });
}
