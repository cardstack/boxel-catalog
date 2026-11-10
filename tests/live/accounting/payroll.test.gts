import { module, test } from 'qunit';

import {
  calcPaycheck,
  tableFor,
  ytdOf,
  withheldOf,
  employerTaxOf,
  NO_YTD,
  type TaxTableData,
  type PaySetupData,
} from '../../../cards/accounting/payroll-calc';

const P = (pct: number) => Math.round(pct * 10000);
const br = (status: string, rows: [number, number][]) =>
  rows.map(([overMinor, ratePpm]) => ({
    filingStatus: status,
    overMinor,
    ratePpm,
  }));
const at = '2025-01-01';
// The demo books' 2025 tables, as the PayrollTaxTable cards hold them.
const TABLES: TaxTableData[] = [
  {
    tax: 'federal-income',
    effectiveFrom: at,
    brackets: [
      ...br('single', [
        [0, 0],
        [640000, P(10)],
        [1832500, P(12)],
        [5487500, P(22)],
        [10975000, P(24)],
        [20370000, P(32)],
        [25692500, P(35)],
        [63275000, P(37)],
      ]),
      ...br('married', [
        [0, 0],
        [1710000, P(10)],
        [4095000, P(12)],
        [11405000, P(22)],
        [22380000, P(24)],
      ]),
    ],
  },
  {
    tax: 'social-security',
    effectiveFrom: at,
    ratePpm: 62000,
    employerRatePpm: 62000,
    wageBaseMinor: 17610000,
  },
  {
    tax: 'medicare',
    effectiveFrom: at,
    ratePpm: 14500,
    employerRatePpm: 14500,
    thresholdMinor: 20000000,
    extraRatePpm: 9000,
  },
  {
    tax: 'futa',
    effectiveFrom: at,
    employerRatePpm: 6000,
    wageBaseMinor: 700000,
  },
  {
    tax: 'ny-income',
    effectiveFrom: at,
    allowanceMinor: 100000,
    statusAmounts: [
      { filingStatus: 'single', amountMinor: 740000 },
      { filingStatus: 'married', amountMinor: 795000 },
    ],
    brackets: br('single', [
      [0, P(4)],
      [850000, P(4.5)],
      [1170000, P(5.25)],
      [1390000, P(5.5)],
      [8065000, P(6)],
      [21540000, P(6.85)],
    ]),
  },
  {
    tax: 'ny-suta',
    effectiveFrom: at,
    employerRatePpm: 41000,
    wageBaseMinor: 1280000,
  },
  { tax: 'ny-sdi', effectiveFrom: at, ratePpm: 5000, weeklyCapMinor: 60 },
  { tax: 'ny-pfl', effectiveFrom: at, ratePpm: 3880, annualCapMinor: 35453 },
];

const DANA: PaySetupData = {
  employeeId: 'dana-kim',
  name: 'Dana Kim',
  payType: 'salary',
  annualSalaryMinor: 16500000,
  schedule: 'biweekly',
  expenseAccount: '6100',
  filingStatus: 'single',
  allowances: 1,
  deductions: [
    { label: '401(k)', kind: 'retirement', ratePpm: 50000, account: '2340' },
    {
      label: 'Health plan',
      kind: 'section125',
      amountMinor: 9500,
      account: '2350',
    },
  ],
};

export function runTests() {
  module('Catalog | accounting - payroll calculation', function () {
    test('a salaried paycheck: gross, pre-tax deductions, each tax and net, in whole cents', function (assert) {
      let p = calcPaycheck({
        setup: DANA,
        payDate: '2026-01-16',
        tables: TABLES,
      });
      assert.strictEqual(p.grossMinor, 634615, 'salary over 26 periods');
      assert.deepEqual(
        p.deductions.map((d) => [d.kind, d.amountMinor, d.account]),
        [
          ['retirement', 31731, '2340'],
          ['section125', 9500, '2350'],
        ],
        'the 401(k) is 5% of gross; the health plan a fixed amount',
      );
      assert.strictEqual(
        p.fitWagesMinor,
        593384,
        'both pre-tax deductions come off income tax wages',
      );
      assert.strictEqual(p.fitMinor, 108993, 'federal withholding');
      assert.strictEqual(
        p.ssWagesMinor,
        625115,
        'only section 125 comes off Social Security wages',
      );
      assert.strictEqual(p.ssMinor, 38757);
      assert.strictEqual(p.medicareMinor, 9064);
      assert.strictEqual(p.addlMedicareMinor, 0);
      assert.strictEqual(p.stateMinor, 31479, 'New York withholding');
      assert.strictEqual(p.sdiMinor, 120, 'disability stops at $0.60 a week');
      assert.strictEqual(p.pflMinor, 2462);
      assert.strictEqual(p.netMinor, 402509);
      assert.strictEqual(
        p.grossMinor,
        p.netMinor + withheldOf(p) + 31731 + 9500,
        'gross is net plus what was withheld and deducted',
      );
      assert.deepEqual(
        [p.erSsMinor, p.erMedicareMinor, p.futaMinor, p.sutaMinor],
        [38757, 9064, 3751, 25630],
        'employer Social Security, Medicare, FUTA and New York unemployment',
      );
      assert.strictEqual(employerTaxOf(p), 38757 + 9064 + 3751 + 25630);
      assert.strictEqual(p.ytdGrossMinor, 634615);
    });

    test('year-to-date wages stop Social Security, FUTA, SUTA and PFL at their caps, and start additional Medicare', function (assert) {
      let p = calcPaycheck({
        setup: DANA,
        payDate: '2026-11-20',
        tables: TABLES,
        ytd: {
          ...NO_YTD,
          grossMinor: 19000000,
          ssWagesMinor: 17610000 - 100000,
          medicareWagesMinor: 19900000,
          futaWagesMinor: 700000,
          sutaWagesMinor: 1200000,
          pflMinor: 35000,
        },
      });
      assert.strictEqual(p.ssWagesMinor, 100000, 'what is left of the base');
      assert.strictEqual(p.ssMinor, 6200);
      assert.strictEqual(p.erSsMinor, 6200);
      assert.strictEqual(p.futaWagesMinor, 0, 'FUTA is capped already');
      assert.strictEqual(p.futaMinor, 0);
      assert.strictEqual(p.sutaWagesMinor, 80000);
      assert.strictEqual(p.sutaMinor, 3280);
      assert.strictEqual(
        p.addlMedicareMinor,
        4726,
        '0.9% on the wages above $200,000 for the year',
      );
      assert.strictEqual(p.erMedicareMinor, 9064, 'the employer pays no extra');
      assert.strictEqual(p.pflMinor, 453, 'the rest of the PFL cap');
      assert.strictEqual(p.ytdGrossMinor, 19000000 + 634615);
    });

    test('hourly pay is the rate times the hours worked', function (assert) {
      let p = calcPaycheck({
        setup: {
          employeeId: 'leo-park',
          payType: 'hourly',
          hourlyRateMinor: 3200,
          schedule: 'biweekly',
          expenseAccount: '6100',
          cls: 'Production Overhead',
          filingStatus: 'married',
        },
        payDate: '2026-01-16',
        hoursMilli: 81500,
        tables: TABLES,
      });
      assert.strictEqual(p.grossMinor, 260800, '81.5 hours at $32');
      assert.strictEqual(p.hoursMilli, 81500);
      assert.strictEqual(p.cls, 'Production Overhead');
      assert.strictEqual(
        p.fitMinor,
        21569,
        'married: $67,808 a year withholds $5,607.96, over 26 periods',
      );
      assert.strictEqual(
        p.grossMinor,
        p.netMinor + withheldOf(p),
        'with no deductions, gross is net plus taxes',
      );
    });

    test('the lookup takes the newest table on or before the pay date', function (assert) {
      let tables = [
        { tax: 'futa', effectiveFrom: '2025-01-01', employerRatePpm: 6000 },
        { tax: 'futa', effectiveFrom: '2026-01-01', employerRatePpm: 9000 },
        { tax: 'medicare', effectiveFrom: '2027-01-01' },
      ];
      assert.strictEqual(
        tableFor(tables, 'futa', '2025-12-31')?.employerRatePpm,
        6000,
      );
      assert.strictEqual(
        tableFor(tables, 'futa', '2026-01-01')?.employerRatePpm,
        9000,
      );
      assert.notOk(
        tableFor(tables, 'medicare', '2026-06-30'),
        'a table that takes effect later does not apply',
      );
    });

    test('year to date sums the earlier paychecks of the same year', function (assert) {
      let runs = [
        {
          date: '2025-12-31',
          paychecks: [{ employeeId: 'dana-kim', grossMinor: 999 }],
        },
        {
          date: '2026-01-02',
          paychecks: [
            { employeeId: 'dana-kim', grossMinor: 100, ssWagesMinor: 90 },
            { employeeId: 'leo-park', grossMinor: 5 },
          ],
        },
        {
          date: '2026-01-16',
          paychecks: [{ employeeId: 'dana-kim', grossMinor: 200 }],
        },
      ];
      let ytd = ytdOf('dana-kim', '2026-01-16', runs);
      assert.strictEqual(ytd.grossMinor, 100, 'not last year, not this run');
      assert.strictEqual(ytd.ssWagesMinor, 90);
    });

    test('a paycheck is refused without a schedule, a tax table, or enough pay to cover its deductions', function (assert) {
      assert.throws(
        () =>
          calcPaycheck({
            setup: { ...DANA, schedule: undefined },
            payDate: '2026-01-16',
            tables: TABLES,
          }),
        /Give Dana Kim a pay schedule/,
      );
      assert.throws(
        () =>
          calcPaycheck({
            setup: DANA,
            payDate: '2024-12-31',
            tables: TABLES,
          }),
        /no federal-income tax table for 2024-12-31/,
      );
      assert.throws(
        () =>
          calcPaycheck({
            setup: {
              ...DANA,
              deductions: [
                {
                  label: 'Loan',
                  kind: 'posttax',
                  amountMinor: 900000,
                  account: '2350',
                },
              ],
            },
            payDate: '2026-01-16',
            tables: TABLES,
          }),
        /come to more than their pay/,
      );
    });
  });
}
