import { module, test } from 'qunit';

import {
  bankKey,
  bookAt,
  closedBefore,
  lastRecOf,
  monthEndOf,
  recItems,
} from '../../../cards/accounting/ledger-reconcile';

const BANK = '1000',
  CARD = '2100';

const line = (account: string, minor: number) => ({
  account,
  debitMinor: minor > 0 ? minor : 0,
  creditMinor: minor < 0 ? -minor : 0,
});
const posting = (
  key: string,
  date: string,
  account: string,
  minor: number,
) => ({
  key,
  date,
  lines: [line(account, minor), line('4000', -minor)],
});

// January is closed with its totals; February is open. Both months keep their postings.
const closes = [
  {
    month: '2027-01',
    status: 'closed',
    totals: [line(BANK, 100000 - 30000), line(CARD, -20000)],
  },
];
const journalMonths = [
  {
    month: '2027-01',
    postings: [
      posting('jan-deposit', '2027-01-10', BANK, 100000),
      posting('jan-card', '2027-01-12', CARD, -20000),
      posting('jan-check', '2027-01-25', BANK, -30000),
    ],
  },
  {
    month: '2027-02',
    postings: [
      posting('feb-deposit', '2027-02-03', BANK, 5000),
      posting('feb-fee', '2027-02-20', BANK, -700),
    ],
  },
];

export function runTests() {
  module('Catalog | accounting - reconciliation', function () {
    test('a month ends on its last calendar day', function (assert) {
      assert.strictEqual(monthEndOf('2027-02'), '2027-02-28');
      assert.strictEqual(monthEndOf('2028-02'), '2028-02-29');
      assert.strictEqual(monthEndOf('2027-12'), '2027-12-31');
      assert.strictEqual(monthEndOf(''), '');
    });

    test('a closed month counts its stored totals at its end', function (assert) {
      assert.strictEqual(
        bookAt(BANK, '2027-01-31', 'debit', closes, journalMonths),
        70000,
      );
      assert.strictEqual(
        bookAt(BANK, '2027-02-28', 'debit', closes, journalMonths),
        70000 + 5000 - 700,
        'later open months add their postings',
      );
    });

    test('a statement dated mid-month of a closed month counts the postings up to its day', function (assert) {
      assert.strictEqual(
        bookAt(BANK, '2027-01-15', 'debit', closes, journalMonths),
        100000,
        'the check on the 25th is not in a statement ending the 15th',
      );
    });

    test('the stored totals stand for a closed month even when its postings differ', function (assert) {
      let drifted = [{ ...closes[0], totals: [line(BANK, 12345)] }];
      assert.strictEqual(
        bookAt(BANK, '2027-01-31', 'debit', drifted, journalMonths),
        12345,
      );
    });

    test('a card account reads its balance on the credit side', function (assert) {
      assert.strictEqual(
        bookAt(CARD, '2027-01-31', 'credit', closes, journalMonths),
        20000,
      );
      assert.strictEqual(
        bookAt(CARD, '2027-01-31', 'debit', closes, journalMonths),
        -20000,
      );
    });

    test('a first reconciliation after a closed run lists only postings after it', function (assert) {
      assert.strictEqual(closedBefore('2027-02', closes), '2027-01-31');
      assert.strictEqual(closedBefore('2027-01', closes), '');
      let items = recItems(
        {
          id: 'feb',
          account: BANK,
          statementDate: '2027-02-28',
          side: 'debit',
        },
        [],
        closes,
        journalMonths,
      );
      assert.deepEqual(
        items.map((i) => [i.key, i.amountMinor]),
        [
          ['feb-deposit', 5000],
          ['feb-fee', -700],
        ],
      );
    });

    test('a reconciliation lists from the last one, carrying in its outstanding and skipping what it cleared', function (assert) {
      let jan = {
        id: 'jan',
        account: BANK,
        statementDate: '2027-01-31',
        status: 'reconciled',
        cleared: [{ key: 'jan-deposit' }],
        outstanding: [{ ref: 'jan-check', amountMinor: -30000 }],
      };
      let feb = {
        id: 'feb',
        account: BANK,
        statementDate: '2027-02-15',
        side: 'debit',
        outstanding: jan.outstanding,
      };
      let items = recItems(feb, [jan, feb], [], journalMonths);
      assert.deepEqual(
        items.map((i) => [i.key, i.date, i.amountMinor]),
        [
          ['jan-check', '', -30000],
          ['feb-deposit', '2027-02-03', 5000],
        ],
        'the outstanding check comes first, and the fee after the statement date is left for later',
      );
      assert.strictEqual(lastRecOf([jan, feb], BANK, '9999-12-31')?.id, 'jan');
    });

    test('a card reconciliation lists charges as positive', function (assert) {
      let items = recItems(
        { id: 'c', account: CARD, statementDate: '2027-01-31', side: 'credit' },
        [],
        [],
        journalMonths,
      );
      assert.deepEqual(
        items.map((i) => [i.key, i.amountMinor]),
        [['jan-card', 20000]],
      );
    });

    test('a bank line posted again after a reversal takes the next key', function (assert) {
      let importKey = `${BANK}|FCB-270105-01`,
        base = `bank:${importKey}`;
      let months = (keys: string[]) => [
        {
          month: '2027-01',
          postings: keys.map((key) => ({ key, date: '2027-01-05' })),
        },
      ];
      assert.strictEqual(bankKey(importKey, '2027-01-05', months([])), base);
      assert.strictEqual(
        bankKey(importKey, '2027-01-05', months([base, 'reverse:2027-01:1'])),
        `${base}#2`,
      );
      assert.strictEqual(
        bankKey(
          importKey,
          '2027-01-05',
          months([base, 'reverse:2027-01:1', `${base}#2`, 'reverse:2027-01:3']),
        ),
        `${base}#3`,
      );
      assert.strictEqual(
        bankKey(importKey, '2027-02-05', months([base])),
        base,
        'a key counts only within its month',
      );
    });
  });
}
