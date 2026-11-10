import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import type { CardDef } from '@cardstack/base/card-api';
import { operations } from '@cardstack/base/operations';

import {
  setupLocalIndexing,
  setupOnSave,
  setupAuthEndpoints,
  setupUserSubscription,
  setupAcceptanceTestRealm,
  SYSTEM_CARD_FIXTURE_CONTENTS,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

import { PayrollRun, AmountLine } from '../../../cards/accounting/ledger-cash';
import {
  Paycheck,
  PaycheckDeduction,
} from '../../../cards/accounting/ledger-payroll';
import {
  journalPostingFor,
  journalPostings,
} from '../../../cards/accounting/ledger-journal';
import {
  formFigures,
  agencyOwed,
  liabilityBalance,
  w2s,
  PAYROLL_TAX_KIND,
} from '../../../cards/accounting/payroll-forms';
import {
  calcPaycheck,
  runTotals,
  paycheckPostings,
  standingRuns,
  periodFor,
  runBlocker,
  staleEmployees,
  PAYROLL_LIABILITIES,
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
    statusAmounts: [
      { filingStatus: 'single', amountMinor: 860000 },
      { filingStatus: 'married', amountMinor: 1290000 },
    ],
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

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/payroll/';
const accounting = `${catalogRealmURL}cards/accounting/`;
// `post` also stamps `actor()`, which this realm's in-browser dispatch can't supply, so the checks a
// run with paychecks adds to `post` are run here on their own, as an operation of a PayrollRun subclass.
const RUN_PROBE = `
  import { operation } from '@cardstack/base/operations';
  import { PayrollRun } from '${accounting}ledger-cash';
  import { PAYCHECK_CHECKS } from '${accounting}ledger-payroll';
  export class CheckedRun extends PayrollRun {
    @operation static checkPaychecks = {
      base: 'transform',
      transformations: { $bxl: PAYCHECK_CHECKS },
    };
  }
`;

// `file` stamps `actor()` too, so its checks run here on their own.
const FILING_PROBE = `
  import { operation } from '@cardstack/base/operations';
  import NumberField from '@cardstack/base/number';
  import StringField from '@cardstack/base/string';
  import { PayrollFiling, FILE_CHECKS } from '${accounting}ledger-payroll-filings';
  export class CheckedFiling extends PayrollFiling {
    @operation static checkFile = {
      base: 'transform',
      params: { dueMinor: NumberField, filedOn: StringField },
      transformations: { $bxl: FILE_CHECKS },
    };
  }
`;

type Row = { account?: string; debitMinor?: number; creditMinor?: number };
const net = (lines: Row[], account: string) =>
  lines
    .filter((l) => l.account === account)
    .reduce((n, l) => n + (l.debitMinor ?? 0) - (l.creditMinor ?? 0), 0);
const unbalanced = (lines: Row[]) =>
  lines.reduce((n, l) => n + (l.debitMinor ?? 0) - (l.creditMinor ?? 0), 0);

const LEO: PaySetupData = {
  employeeId: 'leo-park',
  name: 'Leo Park',
  payType: 'hourly',
  hourlyRateMinor: 3200,
  schedule: 'biweekly',
  expenseAccount: '6100',
  cls: 'Production Overhead',
  filingStatus: 'single',
};
const runChecks = () => [
  calcPaycheck({ setup: DANA, payDate: '2026-01-16', tables: TABLES }),
  calcPaycheck({
    setup: LEO,
    payDate: '2026-01-16',
    hoursMilli: 80000,
    tables: TABLES,
  }),
];
/** A run's attributes, as the desk drafts it from its paychecks. */
const runAttrs = (checks = runChecks()) => ({
  docNo: 'PR-TEST',
  date: '2026-01-16',
  status: 'draft',
  bank: '1000',
  employerTaxAccount: '6120',
  liabilityAccount: '2310',
  schedule: 'biweekly',
  periodStart: '2026-01-03',
  periodEnd: '2026-01-16',
  ...runTotals(checks),
  paychecks: checks,
});
const runCard = (checks = runChecks()) => {
  let a = runAttrs(checks);
  return new PayrollRun({
    ...a,
    wages: a.wages.map((w) => new AmountLine(w as any)),
    paychecks: checks.map(
      (p) =>
        new Paycheck({
          ...p,
          deductions: p.deductions.map((d) => new PaycheckDeduction(d)),
        } as any),
    ),
  } as any);
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
      assert.strictEqual(
        p.fitMinor,
        101054,
        'federal withholding: $154,279.84 a year less the $8,600 step 1g amount',
      );
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
      assert.strictEqual(p.netMinor, 410448);
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
        15615,
        'married: $67,808 a year less $12,900 withholds $4,059.96, over 26 periods',
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

    test('year to date sums the paychecks of the same year up to the pay date', function (assert) {
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
      assert.strictEqual(
        ytd.grossMinor,
        300,
        'not last year, but a run on the same pay date counts',
      );
      assert.strictEqual(ytd.ssWagesMinor, 90);
      assert.strictEqual(ytdOf('dana-kim', '2026-01-15', runs).grossMinor, 100);
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

  module('Catalog | accounting - payroll runs', function () {
    test("a run's totals are the sums of its paychecks", function (assert) {
      let checks = runChecks(),
        t = runTotals(checks);
      let sum = (f: (p: any) => number) => checks.reduce((n, p) => n + f(p), 0);
      assert.deepEqual(
        t.wages.map((w) => [w.account, w.cls, w.amountMinor]),
        [
          ['6100', null, checks[0].grossMinor],
          ['6100', 'Production Overhead', checks[1].grossMinor],
        ],
        'wages by expense account and class',
      );
      assert.strictEqual(
        t.netMinor,
        sum((p) => p.netMinor),
      );
      assert.strictEqual(t.withholdingMinor, sum(withheldOf));
      assert.strictEqual(t.employerTaxMinor, sum(employerTaxOf));
      assert.strictEqual(t.headcount, 2);
      assert.strictEqual(
        t.wages.reduce((n, w) => n + w.amountMinor, 0),
        t.netMinor + t.withholdingMinor + t.deductionsMinor,
        'gross is net plus what was withheld and deducted',
      );
    });

    test("a run's entry balances and owes each tax to its agency's liability", function (assert) {
      let checks = runChecks(),
        t = runTotals(checks);
      let lines = paycheckPostings({ ...runAttrs(checks), bank: '1000' });
      assert.strictEqual(unbalanced(lines), 0, 'the entry balances');
      let sum = (f: (p: any) => number) => checks.reduce((n, p) => n + f(p), 0);
      assert.strictEqual(
        net(lines, '6100'),
        sum((p) => p.grossMinor),
      );
      assert.strictEqual(net(lines, '6120'), t.employerTaxMinor);
      assert.strictEqual(net(lines, '1000'), -t.netMinor, 'net from the bank');
      assert.strictEqual(
        net(lines, PAYROLL_LIABILITIES.federal.account),
        -sum(
          (p) =>
            p.fitMinor +
            p.ssMinor +
            p.erSsMinor +
            p.medicareMinor +
            p.erMedicareMinor +
            p.addlMedicareMinor,
        ),
        'federal withholding, Social Security and Medicare, both halves',
      );
      assert.strictEqual(net(lines, '2315'), -sum((p) => p.futaMinor));
      assert.strictEqual(
        net(lines, '2320'),
        -sum((p) => p.stateMinor + p.sutaMinor),
      );
      assert.strictEqual(
        net(lines, '2330'),
        -sum((p) => p.sdiMinor + p.pflMinor),
      );
      assert.strictEqual(net(lines, '2340'), -31731, 'the 401(k)');
      assert.strictEqual(net(lines, '2350'), -9500, 'the health plan');
    });

    test("the run card posts its paychecks' entry, and journals the totals the filings read", function (assert) {
      let run = runCard();
      let lines = (run.ledgerLines ?? []).map((l) => ({
        account: l.account,
        debitMinor: l.debitMinor,
        creditMinor: l.creditMinor,
      }));
      assert.strictEqual(unbalanced(lines), 0);
      assert.strictEqual(net(lines, '1000'), -(run.netMinor ?? 0));
      let entry = journalPostingFor(run, 'PayrollRun', 'x');
      assert.strictEqual(entry.kind, 'payroll');
      let fact = (k: string) => entry.facts.find((f) => f.key === k)?.value;
      assert.strictEqual(fact('fitMinor'), String(run.fitMinor));
      assert.strictEqual(fact('ssWagesMinor'), String(run.ssWagesMinor));
      assert.strictEqual(fact('periodEnd'), '2026-01-16');
      assert.strictEqual(unbalanced(entry.lines), 0, 'the journal entry too');
    });

    test('a reversed run no longer stands, so its paychecks leave the year to date', function (assert) {
      let month = {
        month: '2026-01',
        postings: [
          { seq: 1, kind: 'payroll', source: 'PR-A' },
          { seq: 2, kind: 'payroll', source: 'PR-B' },
          { seq: 3, kind: 'reversal', reverses: 2, source: 'PR-B' },
        ],
      };
      let sources = new Set(
        journalPostings([month], ['payroll']).map((p) => p.source),
      );
      let runs = [
        { docNo: 'PR-A', status: 'journaled' },
        { docNo: 'PR-B', status: 'journaled' },
        { docNo: 'PR-C', status: 'draft' },
      ];
      assert.deepEqual(
        standingRuns(runs, sources).map((r) => r.docNo),
        ['PR-A'],
      );
    });

    test('a run waits for the draft before it, so year to date counts every earlier run', function (assert) {
      let draft = {
        docNo: 'PR-1',
        date: '2026-01-16',
        status: 'draft',
        schedule: 'biweekly',
        periodStart: '2026-01-03',
        periodEnd: '2026-01-16',
        paychecks: [{ employeeId: 'dana-kim' }],
      };
      let next = {
        schedule: 'biweekly',
        payDate: '2026-01-30',
        start: '2026-01-17',
        end: '2026-01-30',
        employeeIds: ['dana-kim'],
      };
      assert.ok(
        runBlocker(next, [draft]).includes('PR-1 is still a draft'),
        'an unposted run blocks the next one',
      );
      assert.strictEqual(
        runBlocker(next, [{ ...draft, status: 'journaled' }]),
        '',
        'once it posts, the next run can be drafted',
      );
    });

    test('a run is refused when it would pay the same employee twice for the same days', function (assert) {
      let posted = {
        docNo: 'PR-1',
        date: '2026-01-16',
        status: 'journaled',
        schedule: 'biweekly',
        periodStart: '2026-01-03',
        periodEnd: '2026-01-16',
        paychecks: [{ employeeId: 'dana-kim' }],
      };
      let run = (
        schedule: string,
        payDate: string,
        start: string,
        end: string,
        ids: string[],
      ) =>
        runBlocker({ schedule, payDate, start, end, employeeIds: ids }, [
          posted,
        ]);
      assert.ok(
        run('biweekly', '2026-01-23', '2026-01-10', '2026-01-23', [
          'dana-kim',
        ]).includes('overlaps this period'),
        'the same schedule, shifted a week',
      );
      assert.strictEqual(
        run('biweekly', '2026-01-23', '2026-01-10', '2026-01-23', ['leo-park']),
        '',
        'the same schedule, but nobody paid twice',
      );
      let moved = run('semimonthly', '2026-01-31', '2026-01-16', '2026-01-31', [
        'dana-kim',
      ]);
      assert.ok(
        moved.includes('would pay those days again') &&
          moved.includes('first period after 2026-01-16'),
        'moving schedules says where the new schedule starts',
      );
      assert.strictEqual(
        run('biweekly', '2026-01-30', '2026-01-17', '2026-01-30', ['dana-kim']),
        '',
        'the next period',
      );
    });

    test('a run dated before a posted run for the same employee is refused', function (assert) {
      let posted = {
        docNo: 'PR-DEC31',
        date: '2026-12-31',
        status: 'journaled',
        schedule: 'biweekly',
        periodStart: '2026-12-18',
        periodEnd: '2026-12-31',
        paychecks: [{ employeeId: 'dana-kim' }],
      };
      let missed = {
        schedule: 'weekly',
        payDate: '2026-12-17',
        start: '2026-12-11',
        end: '2026-12-17',
      };
      assert.ok(
        runBlocker({ ...missed, employeeIds: ['dana-kim'] }, [posted]).includes(
          'after this pay date',
        ),
      );
      assert.strictEqual(
        runBlocker({ ...missed, employeeIds: ['leo-park'] }, [posted]),
        '',
        'another employee can still be paid then',
      );
    });

    test('a draft whose year to date has changed since it was drafted is stale', function (assert) {
      let draft = {
        date: '2026-01-30',
        paychecks: [
          calcPaycheck({ setup: DANA, payDate: '2026-01-30', tables: TABLES }),
        ],
      };
      assert.deepEqual(staleEmployees(draft, [DANA], TABLES, []), []);
      let earlier = {
        date: '2026-01-16',
        paychecks: [
          calcPaycheck({ setup: DANA, payDate: '2026-01-16', tables: TABLES }),
        ],
      };
      assert.deepEqual(
        staleEmployees(draft, [DANA], TABLES, [earlier]),
        ['dana-kim'],
        'a run posted before it since',
      );
      assert.deepEqual(
        staleEmployees(
          draft,
          [{ ...DANA, annualSalaryMinor: 17000000 }],
          TABLES,
          [],
        ),
        ['dana-kim'],
        'a changed pay setup',
      );
    });

    test('a pay period ends on the pay date', function (assert) {
      assert.deepEqual(periodFor('biweekly', '2026-01-16'), {
        start: '2026-01-03',
        end: '2026-01-16',
      });
      assert.deepEqual(periodFor('weekly', '2026-03-02'), {
        start: '2026-02-24',
        end: '2026-03-02',
      });
      assert.deepEqual(periodFor('semimonthly', '2026-02-27'), {
        start: '2026-02-16',
        end: '2026-02-28',
      });
      assert.deepEqual(periodFor('monthly', '2026-04-30'), {
        start: '2026-04-01',
        end: '2026-04-30',
      });
    });
  });

  module(
    'Acceptance | Catalog | accounting - payroll run checks',
    function (hooks) {
      setupApplicationTest(hooks);
      setupLocalIndexing(hooks);
      setupOnSave(hooks);

      let mockMatrixUtils = setupMockMatrix(hooks, {
        loggedInAs: '@testuser:localhost',
        activeRealms: [realmURL],
      });

      const probe = (attributes: Record<string, unknown>) => ({
        data: {
          type: 'card',
          attributes,
          meta: {
            adoptsFrom: { module: `${realmURL}run-probe`, name: 'CheckedRun' },
          },
        },
      });

      hooks.beforeEach(async function () {
        mockMatrixUtils.createAndJoinRoom({
          sender: '@testuser:localhost',
          name: 'room-test',
        });
        setupUserSubscription();
        setupAuthEndpoints();
        let good = runAttrs(),
          checks = runChecks();
        await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'run-probe.gts': RUN_PROBE,
            'CheckedRun/good.json': probe(good),
            'CheckedRun/short.json': probe({
              ...good,
              paychecks: [
                { ...checks[0], netMinor: checks[0].netMinor + 1 },
                checks[1],
              ],
            }),
            'CheckedRun/totals.json': probe({
              ...good,
              fitMinor: (good.fitMinor ?? 0) - 1,
            }),
            'CheckedRun/deductions.json': probe({
              ...good,
              paychecks: [
                {
                  ...checks[0],
                  deductionsMinor: checks[0].deductionsMinor + 1,
                  netMinor: checks[0].netMinor - 1,
                },
                checks[1],
              ],
              deductionsMinor: good.deductionsMinor + 1,
              netMinor: good.netMinor - 1,
            }),
            'PayrollRun/draft.json': {
              data: {
                type: 'card',
                attributes: { ...good },
                meta: {
                  adoptsFrom: {
                    module: `${accounting}ledger-cash`,
                    name: 'PayrollRun',
                  },
                },
              },
            },
            'PayrollRun/posted.json': {
              data: {
                type: 'card',
                attributes: {
                  ...good,
                  docNo: 'PR-POSTED',
                  status: 'journaled',
                },
                meta: {
                  adoptsFrom: {
                    module: `${accounting}ledger-cash`,
                    name: 'PayrollRun',
                  },
                },
              },
            },
            'CheckedRun/negative.json': probe({
              ...good,
              paychecks: [{ ...checks[0], stateMinor: -5 }, checks[1]],
            }),
          },
        });
      });

      const card = async (path: string) =>
        (await getService('store').get(`${realmURL}${path}`)) as CardDef;
      const refusedWith = (text: string) => (e: any) =>
        String(e?.detail ?? e?.message ?? e).includes(text);

      test('a run whose paychecks add up passes the checks its post makes', async function (assert) {
        await (
          operations(await card('CheckedRun/good')) as any
        ).checkPaychecks();
        assert.ok(true, 'the run is accepted');
      });

      test("a paycheck whose gross isn't its net, taxes and deductions is refused", async function (assert) {
        await assert.rejects(
          (operations(await card('CheckedRun/short')) as any).checkPaychecks(),
          refusedWith("Each paycheck's gross must equal its net"),
        );
      });

      test("a run whose totals aren't the sums of its paychecks is refused", async function (assert) {
        await assert.rejects(
          (operations(await card('CheckedRun/totals')) as any).checkPaychecks(),
          refusedWith('must be the sums of its paychecks'),
        );
      });

      test("a paycheck whose deductions total isn't its deductions is refused", async function (assert) {
        await assert.rejects(
          (
            operations(await card('CheckedRun/deductions')) as any
          ).checkPaychecks(),
          refusedWith('must add up to its deductions total'),
        );
      });

      test('a draft run can be deleted, and a posted one is refused', async function (assert) {
        await (operations(await card('PayrollRun/draft')) as any).atomic(
          (b: any) => [b.checkDraft(), b.delete()],
        );
        assert.ok(true, 'the draft is deleted');
        await assert.rejects(
          (operations(await card('PayrollRun/posted')) as any).atomic(
            (b: any) => [b.checkDraft(), b.delete()],
          ),
          refusedWith('Only a draft payroll run can be deleted'),
        );
        assert.strictEqual(
          (
            (await (
              operations(await card('PayrollRun/posted')) as any
            ).read()) as any
          ).data.attributes.status,
          'journaled',
          'the posted run is still there',
        );
      });

      test('a negative paycheck amount is refused', async function (assert) {
        await assert.rejects(
          (
            operations(await card('CheckedRun/negative')) as any
          ).checkPaychecks(),
          refusedWith("Paycheck amounts can't be negative"),
        );
      });
    },
  );

  module('Catalog | accounting - payroll filings', function () {
    // A month of journal postings: two runs in the quarter, one after it, and a 941 payment.
    const quarterMonth = () => {
      let a = journalPostingFor(runCard(), 'PayrollRun', 'a');
      let later = runCard();
      later.date = '2026-04-03';
      later.docNo = 'PR-LATER';
      let b = journalPostingFor(later, 'PayrollRun', 'b');
      let pay = {
        kind: 'bank-payment',
        date: '2026-04-10',
        source: 'PTX-1',
        lines: [
          { account: '2310', debitMinor: 100000, creditMinor: 0 },
          { account: '1000', debitMinor: 0, creditMinor: 100000 },
        ],
        facts: [
          { key: 'kind', value: PAYROLL_TAX_KIND },
          { key: 'payee', value: 'irs-941' },
          { key: 'amountMinor', value: '100000' },
        ],
        items: [],
      };
      return {
        month: '2026-01',
        postings: [
          { ...a, seq: 1 },
          { ...b, seq: 2 },
          { ...pay, seq: 3 },
        ],
      };
    };

    test("941 figures come from the quarter's runs", function (assert) {
      let posts = journalPostings([quarterMonth()], ['payroll']),
        checks = runChecks();
      let f = formFigures('irs-941', posts, [], '2026-01-01', '2026-03-31');
      let line = (k: string) => f.lines.find((l) => l.key === k)?.amountMinor;
      let sum = (g: (p: any) => number) => checks.reduce((n, p) => n + g(p), 0);
      assert.strictEqual(line('1'), 2, 'employees paid');
      assert.strictEqual(
        line('2'),
        sum((p) => p.fitWagesMinor),
        'W-2 box 1 wages: gross less the 401(k) and section 125',
      );
      assert.strictEqual(line('2'), sum((p) => p.grossMinor) - 31731 - 9500);
      assert.strictEqual(
        line('3'),
        sum((p) => p.fitMinor),
        'withholding',
      );
      assert.strictEqual(
        line('5a'),
        sum((p) => p.ssWagesMinor),
      );
      assert.strictEqual(
        line('5a-tax'),
        sum((p) => p.ssMinor + p.erSsMinor),
      );
      assert.strictEqual(
        line('5c'),
        sum((p) => p.medicareWagesMinor),
      );
      assert.strictEqual(
        line('5c-tax'),
        sum((p) => p.medicareMinor + p.erMedicareMinor),
      );
      assert.strictEqual(line('5d-tax'), 0, 'no one is over $200,000');
      assert.strictEqual(
        line('12'),
        sum(
          (p) =>
            p.fitMinor +
            p.ssMinor +
            p.erSsMinor +
            p.medicareMinor +
            p.erMedicareMinor +
            p.addlMedicareMinor,
        ),
      );
      assert.strictEqual(f.dueMinor, line('12'));
      let q2 = formFigures('irs-941', posts, [], '2026-04-01', '2026-06-30');
      assert.strictEqual(
        q2.lines.find((l) => l.key === '2')?.amountMinor,
        sum((p) => p.fitWagesMinor),
        'the later run is in its own quarter only',
      );
    });

    test("New York's quarterly report, the 940, and the W-2s and W-3", function (assert) {
      let posts = journalPostings([quarterMonth()], ['payroll']),
        checks = runChecks();
      let sum = (g: (p: any) => number) => checks.reduce((n, p) => n + g(p), 0);
      let ny = formFigures('ny-dtf', posts, [], '2026-01-01', '2026-03-31');
      assert.strictEqual(
        ny.dueMinor,
        sum((p) => p.stateMinor + p.sutaMinor),
        'withholding plus unemployment insurance',
      );
      let futa = formFigures('irs-940', posts, [], '2026-01-01', '2026-12-31');
      assert.strictEqual(futa.dueMinor, 2 * sum((p) => p.futaMinor));
      let w = w2s([...checks, ...checks]);
      let box = (k: string) => w.lines.find((l) => l.key === k)?.amountMinor;
      assert.strictEqual(box('W-2 dana-kim 1'), 2 * checks[0].fitWagesMinor);
      assert.strictEqual(box('W-2 dana-kim 12D'), 2 * 31731, 'the 401(k)');
      assert.strictEqual(box('W-2 leo-park 2'), 2 * checks[1].fitMinor);
      assert.strictEqual(
        box('W-3 3'),
        2 * sum((p) => p.ssWagesMinor),
        'the W-3 totals every W-2',
      );
      assert.strictEqual(w.dueMinor, 0, 'nothing is paid with a W-2');
    });

    test('a provider-synced run is listed apart on the 941, not as withholding', function (assert) {
      let synced = {
        kind: 'payroll',
        date: '2026-03-15',
        source: 'GUSTO-2026-03-A',
        lines: [],
        facts: [
          { key: 'withholdingMinor', value: '1624000' },
          { key: 'employerTaxMinor', value: '652500' },
        ],
        items: [{ amountMinor: 5750000 }, { amountMinor: 1500000 }],
      };
      let month = quarterMonth();
      month.postings.push({ ...synced, seq: 9 } as any);
      let posts = journalPostings([month], ['payroll']),
        checks = runChecks();
      let f = formFigures('irs-941', posts, [], '2026-01-01', '2026-03-31');
      let line = (k: string) => f.lines.find((l) => l.key === k)?.amountMinor;
      let sum = (g: (p: any) => number) => checks.reduce((n, p) => n + g(p), 0);
      assert.strictEqual(
        line('3'),
        sum((p) => p.fitMinor),
        "line 3 is only the books' own runs",
      );
      assert.strictEqual(line('synced-wages'), 7250000);
      assert.strictEqual(line('synced-withheld'), 1624000);
      assert.strictEqual(line('synced-employer'), 652500);
      assert.ok(
        f.lines
          .find((l) => l.key === 'synced-wages')
          ?.label.includes("provider's report"),
        'the form says to file them from the provider',
      );
    });

    test('the 940 stops each employee at the $7,000 FUTA wage base across runs', function (assert) {
      let runs: any[] = [],
        month = { month: '2026-01', postings: [] as any[] };
      for (let [i, date] of [
        '2026-01-02',
        '2026-01-16',
        '2026-01-30',
      ].entries()) {
        let check = calcPaycheck({
          setup: DANA,
          payDate: date,
          tables: TABLES,
          ytd: ytdOf('dana-kim', date, runs),
        });
        runs.push({ date, paychecks: [check] });
        let card = runCard([check]);
        card.date = date;
        card.docNo = `PR-${i}`;
        month.postings.push({
          ...journalPostingFor(card, 'PayrollRun', `r${i}`),
          seq: i + 1,
        });
      }
      let posts = journalPostings([month], ['payroll']);
      let f = formFigures('irs-940', posts, [], '2026-01-01', '2026-12-31');
      let line = (k: string) => f.lines.find((l) => l.key === k)?.amountMinor;
      let gross = 3 * 634615;
      assert.strictEqual(line('3'), gross);
      assert.strictEqual(line('4'), 3 * 9500, 'the section 125 plan is exempt');
      assert.strictEqual(line('7'), 700000, 'taxable wages stop at $7,000');
      assert.strictEqual(line('5'), gross - 3 * 9500 - 700000);
      assert.strictEqual(f.dueMinor, 4200, '0.6% of $7,000');
    });

    test('what the agencies are owed ties to the liability accounts, and a payment clears its share', function (assert) {
      let posts = journalPostings([quarterMonth()]);
      let owed = agencyOwed(posts);
      let held = liabilityBalance(posts);
      for (let [id, n] of owed)
        assert.strictEqual(held.get(id), n, `${id} ties to its own account`);
      let before = agencyOwed(
        journalPostings([quarterMonth()], ['payroll']),
      ).get('irs-941');
      assert.strictEqual(
        owed.get('irs-941'),
        (before ?? 0) - 100000,
        'the payment comes off what the IRS is owed',
      );
    });
  });

  module(
    'Acceptance | Catalog | accounting - payroll filings',
    function (hooks) {
      setupApplicationTest(hooks);
      setupLocalIndexing(hooks);
      setupOnSave(hooks);

      let mockMatrixUtils = setupMockMatrix(hooks, {
        loggedInAs: '@testuser:localhost',
        activeRealms: [realmURL],
      });

      const doc = (
        module: string,
        name: string,
        attributes: Record<string, unknown>,
      ) => ({
        data: {
          type: 'card',
          attributes,
          meta: { adoptsFrom: { module: `${accounting}${module}`, name } },
        },
      });
      const filing = (status: string, extra: Record<string, unknown> = {}) =>
        doc('ledger-payroll-filings', 'PayrollFiling', {
          agencyId: 'irs-941',
          form: '941',
          periodStart: '2026-01-01',
          periodEnd: '2026-03-31',
          status,
          filedDueMinor: status === 'open' ? null : 250000,
          paidMinor: 0,
          payments: [],
          ...extra,
        });

      hooks.beforeEach(async function () {
        mockMatrixUtils.createAndJoinRoom({
          sender: '@testuser:localhost',
          name: 'room-test',
        });
        setupUserSubscription();
        setupAuthEndpoints();
        await setupAcceptanceTestRealm({
          realmURL,
          mockMatrixUtils,
          contents: {
            ...SYSTEM_CARD_FIXTURE_CONTENTS,
            'PayrollAgency/irs-941.json': doc(
              'ledger-payroll',
              'PayrollAgency',
              {
                agencyId: 'irs-941',
                form: '941',
                frequency: 'quarterly',
                liabilityAccount: '2310',
                filedThrough: '2025-12-31',
              },
            ),
            'PayrollFiling/open.json': filing('open'),
            'filing-probe.gts': FILING_PROBE,
            'CheckedFiling/open.json': {
              data: {
                type: 'card',
                attributes: filing('open').data.attributes,
                meta: {
                  adoptsFrom: {
                    module: `${realmURL}filing-probe`,
                    name: 'CheckedFiling',
                  },
                },
              },
            },
            'PayrollFiling/filed.json': filing('filed'),
          },
        });
      });

      const card = async (path: string) =>
        (await getService('store').get(`${realmURL}${path}`)) as CardDef;
      const stored = async (path: string) =>
        ((await (operations(await card(path)) as any).read()) as any).data
          .attributes;
      const refusedWith = (text: string) => (e: any) =>
        String(e?.detail ?? e?.message ?? e).includes(text);

      test('filing locks the period against new runs; a correction goes in the next period', async function (assert) {
        let agency = await card('PayrollAgency/irs-941');
        await (operations(agency) as any).checkOpen({ date: '2026-02-13' });
        await (operations(agency) as any).markFiled({
          periodStart: '2026-01-01',
          periodEnd: '2026-03-31',
        });
        assert.strictEqual(
          (await stored('PayrollAgency/irs-941')).filedThrough,
          '2026-03-31',
        );
        await assert.rejects(
          (operations(await card('PayrollAgency/irs-941')) as any).checkOpen({
            date: '2026-03-31',
          }),
          refusedWith('Payroll for that date has been filed with this agency'),
        );
        await (
          operations(await card('PayrollAgency/irs-941')) as any
        ).checkOpen({
          date: '2026-04-03',
        });
        await assert.rejects(
          (operations(await card('PayrollAgency/irs-941')) as any).markFiled({
            periodStart: '2026-03-01',
            periodEnd: '2026-06-30',
          }),
          refusedWith('has already been filed'),
        );
      });

      test('a filing is filed only after its period ends', async function (assert) {
        await assert.rejects(
          (operations(await card('CheckedFiling/open')) as any).checkFile({
            dueMinor: 0,
            filedOn: '2026-03-31',
          }),
          refusedWith('filed after its period ends'),
        );
      });

      test('a liability payment clears its period', async function (assert) {
        await (operations(await card('PayrollFiling/filed')) as any).markPaid({
          paymentNo: 'PTX-1',
          amountMinor: 100000,
        });
        let part = await stored('PayrollFiling/filed');
        assert.strictEqual(part.paidMinor, 100000);
        assert.strictEqual(part.status, 'filed', 'still open for the rest');
        await (operations(await card('PayrollFiling/filed')) as any).markPaid({
          paymentNo: 'PTX-2',
          amountMinor: 150000,
        });
        let done = await stored('PayrollFiling/filed');
        assert.strictEqual(done.paidMinor, 250000);
        assert.strictEqual(done.status, 'paid', 'the period is cleared');
        assert.deepEqual(done.payments, ['PTX-1', 'PTX-2']);
      });

      test('a payment is refused on an open period, twice, or for more than is open', async function (assert) {
        await assert.rejects(
          (operations(await card('PayrollFiling/open')) as any).markPaid({
            paymentNo: 'PTX-1',
            amountMinor: 100,
          }),
          refusedWith('File this period before paying it'),
        );
        await assert.rejects(
          (operations(await card('PayrollFiling/filed')) as any).markPaid({
            paymentNo: 'PTX-1',
            amountMinor: 250001,
          }),
          refusedWith('pays more than this period has open'),
        );
        await (operations(await card('PayrollFiling/filed')) as any).markPaid({
          paymentNo: 'PTX-1',
          amountMinor: 100,
        });
        await assert.rejects(
          (operations(await card('PayrollFiling/filed')) as any).markPaid({
            paymentNo: 'PTX-1',
            amountMinor: 100,
          }),
          refusedWith('already recorded on this filing'),
        );
      });
    },
  );
}
