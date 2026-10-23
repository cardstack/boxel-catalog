import { module, test } from 'qunit';

import {
  parseCsvStatement,
  parseOfxStatement,
  planImport,
  ruleFor,
  guessColumns,
  matchCandidates,
  readCsvHeader,
  toMinor,
} from '../../../cards/accounting/ledger-bank-statement';

const CSV = `Date,Description,Amount,Transaction ID,Check Number
04/02/2026,"COFFEE IMPORTERS, INC",-1250.00,T1,
2026-04-03,Square payout,"2,310.45",T2,
2026-04-03,Rent,(4500.00),,1042
2026-04-03,Rent,(4500.00),,1043
bad,row,1,T5,
`;

const known = (
  lines: { externalId: string; date: string; amountMinor: number }[],
) => lines.map((l) => ({ ...l, description: '' }));

export function runTests() {
  module('Catalog | accounting - bank statements', function () {
    test('a CSV statement reads signed whole cents and calendar days', function (assert) {
      let { lines, rejected } = parseCsvStatement(CSV);
      assert.deepEqual(
        lines.map((l) => [l.date, l.amountMinor, l.externalId.slice(0, 2)]),
        [
          ['2026-04-02', -125000, 'T1'],
          ['2026-04-03', 231045, 'T2'],
          ['2026-04-03', -450000, '20'],
          ['2026-04-03', -450000, '20'],
        ],
      );
      assert.deepEqual(
        rejected.map((r) => r.row),
        [6],
        'the unreadable date is refused, not guessed',
      );
    });

    test('lines with no bank ID get the same IDs every time the file is read', function (assert) {
      let first = parseCsvStatement(CSV).lines.map((l) => l.externalId);
      let again = parseCsvStatement(CSV).lines.map((l) => l.externalId);
      assert.deepEqual(first, again);
      assert.notStrictEqual(first[2], first[3], 'repeated lines stay distinct');
    });

    test('importing the same file again skips every line', function (assert) {
      let parsed = parseCsvStatement(CSV);
      let plan = planImport(parsed, known(parsed.lines));
      assert.strictEqual(plan.accepted.length, 0);
      assert.strictEqual(plan.skipped.length, 4);
    });

    test('a bank ID that comes back with a different amount is refused', function (assert) {
      let plan = planImport(
        parseCsvStatement(CSV),
        known([{ externalId: 'T1', date: '2026-04-02', amountMinor: -999 }]),
      );
      assert.true(
        plan.rejected.some((r) =>
          r.reason.includes('different date or amount'),
        ),
      );
      assert.false(plan.accepted.some((l) => l.externalId === 'T1'));
    });

    test('an OFX statement reads each transaction', function (assert) {
      let { lines } = parseOfxStatement(
        '<OFX><STMTTRN><DTPOSTED>20270105120000[-5:EST]<TRNAMT>-42.10<FITID>F1<NAME>Shell Oil<MEMO>Fuel</STMTTRN></OFX>',
      );
      assert.deepEqual(lines[0], {
        row: 1,
        date: '2027-01-05',
        description: 'Shell Oil · Fuel',
        amountMinor: -4210,
        reference: '',
        payee: 'Shell Oil',
        externalId: 'F1',
      });
    });

    test('column names banks use are recognised', function (assert) {
      assert.deepEqual(
        guessColumns(['Posted Date', 'Payee', 'Withdrawal', 'Deposit']),
        { date: 0, payee: 1, debit: 2, credit: 3 },
      );
      assert.strictEqual(toMinor('$1,234.5'), 123450);
      assert.throws(() => toMinor('12.345'));
    });

    test('each part takes the column its likeliest name labels', function (assert) {
      // Chase's checking export puts DEBIT/CREDIT under Details and the text under Description.
      assert.deepEqual(
        guessColumns([
          'Details',
          'Posting Date',
          'Description',
          'Amount',
          'Type',
        ]),
        { date: 1, description: 2, amount: 3 },
      );
    });

    test('amounts read a decimal comma, a trailing minus and thousands separators', function (assert) {
      assert.strictEqual(toMinor('-86,42'), -8642);
      assert.strictEqual(toMinor('12.00-'), -1200);
      assert.strictEqual(toMinor('1,234'), 123400);
      assert.strictEqual(toMinor('1.234,56'), 123456);
    });

    test('a CSV with no header row keeps its first transaction', function (assert) {
      let text = '01/02/2027,COFFEE,-12.50\n01/03/2027,TEA,-4.00\n';
      assert.deepEqual(readCsvHeader(text).header, [
        'Column 1',
        'Column 2',
        'Column 3',
      ]);
      let { lines } = parseCsvStatement(text, {
        columns: { date: 0, description: 1, amount: 2 },
      });
      assert.deepEqual(
        lines.map((l) => l.description),
        ['COFFEE', 'TEA'],
      );
    });

    test('day-first dates and positive charges read as the bank meant', function (assert) {
      let { lines } = parseCsvStatement(
        'Date,Description,Amount\n03/01/2027,Charge,25.00\n',
        {
          dayFirst: true,
          flipSigns: true,
        },
      );
      assert.strictEqual(lines[0].date, '2027-01-03');
      assert.strictEqual(lines[0].amountMinor, -2500);
    });

    test('an OFX file holding two accounts is refused, and a card statement says so', function (assert) {
      let two = parseOfxStatement(
        '<OFX><STMTRS><STMTTRN></STMTTRN></STMTRS><CCSTMTRS></CCSTMTRS></OFX>',
      );
      assert.strictEqual(two.lines.length, 0);
      assert.true(two.rejected[0].reason.includes('2 accounts'));
      assert.true(
        parseOfxStatement(
          '<OFX><CCSTMTRS><STMTTRN><DTPOSTED>20270103<TRNAMT>-5<FITID>A</STMTTRN></CCSTMTRS></OFX>',
        ).card,
      );
    });

    test('match candidates move the line’s account by its amount, nearest first', function (assert) {
      let postings = [
        {
          key: 'far',
          date: '2027-01-20',
          kind: 'transfer',
          lines: [
            { account: '2100', debitMinor: 320000, creditMinor: 0 },
            { account: '1000', debitMinor: 0, creditMinor: 320000 },
          ],
        },
        {
          key: 'near',
          date: '2027-01-08',
          kind: 'transfer',
          lines: [
            { account: '2100', debitMinor: 320000, creditMinor: 0 },
            { account: '1000', debitMinor: 0, creditMinor: 320000 },
          ],
        },
        {
          key: 'taken',
          date: '2027-01-08',
          kind: 'transfer',
          lines: [
            { account: '2100', debitMinor: 320000, creditMinor: 0 },
            { account: '1000', debitMinor: 0, creditMinor: 320000 },
          ],
        },
      ];
      // The card's side of the payment: money in pays the card down, a debit to 2100.
      let found = matchCandidates(
        { account: '2100', date: '2027-01-09', amountMinor: 320000 },
        postings,
        new Set(['taken']),
      );
      assert.deepEqual(
        found.map((c) => c.posting.key),
        ['near'],
        'the one 11 days away and the one already matched are left out',
      );
      assert.strictEqual(
        matchCandidates(
          { account: '1000', date: '2027-01-08', amountMinor: -320000 },
          postings,
        ).length,
        2,
      );
    });

    test('the first rule that applies suggests, lowest priority first', function (assert) {
      let rules = [
        { name: 'any', category: '6999', priority: 9 },
        {
          name: 'fuel',
          descriptionContains: 'shell',
          direction: 'out',
          category: '6100',
          priority: 1,
        },
        {
          name: 'off',
          descriptionContains: 'shell',
          category: '6200',
          active: false,
        },
      ];
      assert.strictEqual(
        ruleFor(rules, { description: 'SHELL OIL', amountMinor: -4210 })?.name,
        'fuel',
      );
      assert.strictEqual(
        ruleFor(rules, { description: 'Shell refund', amountMinor: 500 })?.name,
        'any',
        'a rule for money out leaves money in alone',
      );
    });
  });
}
