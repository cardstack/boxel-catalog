import { waitUntil } from '@ember/test-helpers';
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
  realmConfigCardJSON,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

import {
  Invoice,
  SaleLine,
  CustomerPayment,
  InvoiceApplication,
} from '../../../cards/accounting/ledger-sales';
import { Bill, BillLine } from '../../../cards/accounting/ledger-cards';
import {
  BillPayment,
  PaymentApplication,
} from '../../../cards/accounting/ledger-payments';
import { toHome } from '../../../cards/accounting/ledger-document';
import { booksSettings } from '../../../cards/accounting/ledger-settings';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/multicurrency/';
const salesModule = `${catalogRealmURL}cards/accounting/ledger-sales`;
const billsModule = `${catalogRealmURL}cards/accounting/ledger-cards`;
// `post` also stamps `actor()`, which this realm's in-browser dispatch can't supply, so the currency
// checks `post` runs are run here on their own, as an operation of an Invoice subclass.
const FX_PROBE = `
  import { operation } from '@cardstack/base/operations';
  import { Invoice } from '${salesModule}';
  import { FX_CHECKS } from '${catalogRealmURL}cards/accounting/ledger-document';
  export class FxInvoice extends Invoice {
    @operation static checkCurrency = {
      base: 'transform',
      transformations: { $bxl: FX_CHECKS },
    };
  }
`;

const BOOKED = 1_083_333; // 1.083333 home units per euro
const HIGHER = 1_100_000;
const LOWER = 1_050_000;

type Row = { account?: string; debitMinor?: number; creditMinor?: number };
const rows = (card: { ledgerLines?: Row[] }) =>
  (card.ledgerLines ?? []).map((l) => ({
    account: l.account ?? '',
    debitMinor: l.debitMinor ?? 0,
    creditMinor: l.creditMinor ?? 0,
  }));
const net = (lines: Row[], account: string) =>
  lines
    .filter((l) => l.account === account)
    .reduce((n, l) => n + (l.debitMinor ?? 0) - (l.creditMinor ?? 0), 0);
const unbalanced = (lines: Row[]) =>
  lines.reduce((n, l) => n + (l.debitMinor ?? 0) - (l.creditMinor ?? 0), 0);

const invoice = (amounts: number[]) =>
  new Invoice({
    docNo: 'INV-EUR-1',
    date: '2026-03-02',
    customerId: 'harbor',
    currency: 'EUR',
    rateMicros: BOOKED,
    status: 'posted',
    lines: amounts.map(
      (amountMinor) => new SaleLine({ account: '4000', amountMinor }),
    ),
  });
const receipt = (amountMinor: number, rateMicros: number) =>
  new CustomerPayment({
    docNo: 'PMT-EUR-1',
    date: '2026-04-02',
    customerId: 'harbor',
    depositTo: '1000',
    currency: 'EUR',
    rateMicros,
    applications: [
      new InvoiceApplication({
        invoiceNo: 'INV-EUR-1',
        amountMinor,
        rateMicros: BOOKED,
      }),
    ],
  });
const bill = (amounts: number[]) =>
  new Bill({
    billNo: 'B-EUR-1',
    date: '2026-03-02',
    vendorId: 'roastery',
    currency: 'EUR',
    rateMicros: BOOKED,
    status: 'posted',
    lines: amounts.map(
      (amountMinor) => new BillLine({ account: '6100', amountMinor }),
    ),
  });
const billPayment = (amountMinor: number, rateMicros: number) =>
  new BillPayment({
    paymentNo: 'BP-EUR-1',
    date: '2026-04-02',
    vendorId: 'roastery',
    fromAccount: '1000',
    currency: 'EUR',
    rateMicros,
    applications: [
      new PaymentApplication({
        billNo: 'B-EUR-1',
        amountMinor,
        rateMicros: BOOKED,
      }),
    ],
  });

export function runTests() {
  module('Catalog | accounting - multicurrency postings', function () {
    test('an invoice in euros posts in the home currency, the receivable at its total rounded once', function (assert) {
      let lines = rows(invoice([50000, 50001]));
      assert.strictEqual(net(lines, '1100'), toHome(100001, BOOKED));
      assert.strictEqual(net(lines, '1100'), 108334);
      assert.strictEqual(unbalanced(lines), 0, 'the entry balances');
    });

    test('a full payment at the booked rate clears the receivable to exactly zero', function (assert) {
      let booked = net(rows(invoice([50000, 50001])), '1100');
      let lines = rows(receipt(100001, BOOKED));
      assert.strictEqual(booked + net(lines, '1100'), 0);
      assert.strictEqual(net(lines, '7800'), 0, 'nothing is gained or lost');
      assert.strictEqual(unbalanced(lines), 0);
    });

    test('a payment received at a higher rate credits the gain to 7800, at a lower rate debits the loss', function (assert) {
      let higher = rows(receipt(100001, HIGHER));
      assert.strictEqual(net(higher, '1000'), 110001);
      assert.strictEqual(net(higher, '7800'), -(110001 - 108334), 'a gain');
      assert.strictEqual(unbalanced(higher), 0);

      let lower = rows(receipt(100001, LOWER));
      assert.strictEqual(net(lower, '1000'), 105001);
      assert.strictEqual(net(lower, '7800'), 108334 - 105001, 'a loss');
      assert.strictEqual(unbalanced(lower), 0);
    });

    test('a full payment of a euro bill at the booked rate clears the payable to exactly zero', function (assert) {
      let booked = net(rows(bill([50000, 50001])), '2000');
      assert.strictEqual(booked, -108334);
      let lines = rows(billPayment(100001, BOOKED));
      assert.strictEqual(booked + net(lines, '2000'), 0);
      assert.strictEqual(net(lines, '7800'), 0);
      assert.strictEqual(unbalanced(lines), 0);
    });

    test('a bill paid at a higher rate debits the loss to 7800, at a lower rate credits the gain', function (assert) {
      let higher = rows(billPayment(100001, HIGHER));
      assert.strictEqual(net(higher, '1000'), -110001);
      assert.strictEqual(net(higher, '7800'), 110001 - 108334, 'a loss');
      assert.strictEqual(unbalanced(higher), 0);

      let lower = rows(billPayment(100001, LOWER));
      assert.strictEqual(net(lower, '1000'), -105001);
      assert.strictEqual(net(lower, '7800'), -(108334 - 105001), 'a gain');
      assert.strictEqual(unbalanced(lower), 0);
    });

    test('two partial payments at the booked rate can clear a cent more than was booked', function (assert) {
      let booked = net(rows(invoice([50000, 50001])), '1100');
      let cleared =
        net(rows(receipt(50000, BOOKED)), '1100') +
        net(rows(receipt(50001, BOOKED)), '1100');
      assert.strictEqual(
        booked + cleared,
        -1,
        'each part rounds on its own, so the receivable is left a cent over',
      );
    });

    test('a document view formats its own amounts in its currency', function (assert) {
      let i = invoice([50000, 50001]);
      assert.strictEqual(i.currencyCode(), 'EUR');
      let open = i.facts().find((f) => f.key === 'Open');
      assert.strictEqual(open?.value, '€1,000.01');
      assert.strictEqual(receipt(100001, HIGHER).totalMinor, 100001);
    });

    test('the settings accept only currencies with cents', function (assert) {
      let ok = booksSettings({
        multicurrency: true,
        currencies: ['EUR', 'CAD'],
      });
      assert.deepEqual(ok.currencies, ['EUR', 'CAD']);
      assert.strictEqual(ok.invalid.currencies, undefined);
      let bad = booksSettings({
        multicurrency: true,
        currencies: ['EUR', 'JPY'],
      });
      assert.deepEqual(bad.currencies, []);
      assert.ok(bad.invalid.currencies?.includes('JPY'));
    });
  });

  module(
    'Acceptance | Catalog | accounting - multicurrency operations',
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
          meta: { adoptsFrom: { module, name } },
        },
      });
      const invoiceAttrs = (docNo: string, extra: Record<string, unknown>) => ({
        docNo,
        date: '2026-03-02',
        customerId: 'harbor',
        status: 'posted',
        paidMinor: 0,
        creditedMinor: 0,
        writtenOffMinor: 0,
        taxMinor: 0,
        lines: [{ account: '4000', amountMinor: 10000 }],
        ...extra,
      });
      const billAttrs = (billNo: string, extra: Record<string, unknown>) => ({
        billNo,
        date: '2026-03-02',
        vendorId: 'roastery',
        status: 'posted',
        paidMinor: 0,
        lines: [{ account: '6100', amountMinor: 10000 }],
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
            'realm.json': realmConfigCardJSON({
              name: 'Multicurrency books',
              config: {
                currency: 'USD',
                multicurrency: true,
                currencies: ['EUR'],
              },
            }),
            'Invoice/home.json': doc(
              salesModule,
              'Invoice',
              invoiceAttrs('INV-HOME', {}),
            ),
            'Invoice/eur.json': doc(
              salesModule,
              'Invoice',
              invoiceAttrs('INV-EUR', { currency: 'EUR', rateMicros: BOOKED }),
            ),
            'fx-probe.gts': FX_PROBE,
            'FxInvoice/gbp.json': doc(
              `${realmURL}fx-probe`,
              'FxInvoice',
              invoiceAttrs('INV-GBP', {
                status: 'draft',
                currency: 'GBP',
                rateMicros: 1_270_000,
              }),
            ),
            'FxInvoice/eur.json': doc(
              `${realmURL}fx-probe`,
              'FxInvoice',
              invoiceAttrs('INV-EUR-D', {
                status: 'draft',
                currency: 'EUR',
                rateMicros: BOOKED,
              }),
            ),
            'Bill/home.json': doc(billsModule, 'Bill', billAttrs('B-HOME', {})),
            'Bill/eur.json': doc(
              billsModule,
              'Bill',
              billAttrs('B-EUR', { currency: 'EUR', rateMicros: BOOKED }),
            ),
          },
        });
      });

      const card = async (path: string) =>
        (await getService('store').get(`${realmURL}${path}`)) as CardDef;
      const refusedWith = (text: string) => (e: any) =>
        String(e?.detail ?? e?.message ?? e).includes(text);

      test('a payment in euros is refused on a home-currency invoice, and a home payment on a euro invoice', async function (assert) {
        await assert.rejects(
          (operations(await card('Invoice/home')) as any).applyPayment({
            amountMinor: 10000,
            paymentNo: 'PMT-1',
            customerId: 'harbor',
            currency: 'EUR',
            rateMicros: null,
          }),
          refusedWith('only invoices in its own currency'),
        );
        await assert.rejects(
          (operations(await card('Invoice/eur')) as any).applyPayment({
            amountMinor: 10000,
            paymentNo: 'PMT-2',
            customerId: 'harbor',
            currency: null,
            rateMicros: null,
          }),
          refusedWith('only invoices in its own currency'),
        );
      });

      test('a payment clearing a euro invoice or bill at another rate than it was booked at is refused', async function (assert) {
        await assert.rejects(
          (operations(await card('Invoice/eur')) as any).applyPayment({
            amountMinor: 10000,
            paymentNo: 'PMT-3',
            customerId: 'harbor',
            currency: 'EUR',
            rateMicros: HIGHER,
          }),
          refusedWith('at the rate it was booked at'),
        );
        await assert.rejects(
          (operations(await card('Bill/eur')) as any).applyPayment({
            amountMinor: 10000,
            paymentNo: 'BP-1',
            vendorId: 'roastery',
            currency: 'EUR',
            rateMicros: LOWER,
          }),
          refusedWith('at the rate it was booked at'),
        );
      });

      test('a bill payment in another currency than the bill is refused', async function (assert) {
        await assert.rejects(
          (operations(await card('Bill/home')) as any).applyPayment({
            amountMinor: 10000,
            paymentNo: 'BP-2',
            vendorId: 'roastery',
            currency: 'EUR',
            rateMicros: BOOKED,
          }),
          refusedWith('only to bills in its own currency'),
        );
      });

      test('a euro invoice at the booked rate is applied', async function (assert) {
        await (operations(await card('Invoice/eur')) as any).applyPayment({
          amountMinor: 4000,
          paymentNo: 'PMT-4',
          customerId: 'harbor',
          currency: 'EUR',
          rateMicros: BOOKED,
        });
        let after = (await card('Invoice/eur')) as any;
        await waitUntil(() => after.paidMinor === 4000, { timeout: 10000 });
        assert.strictEqual(after.paidMinor, 4000);
      });

      test("post's currency checks refuse a currency the settings don't list", async function (assert) {
        await (operations(await card('FxInvoice/eur')) as any).checkCurrency();
        assert.ok(true, 'a listed currency passes');
        await assert.rejects(
          (operations(await card('FxInvoice/gbp')) as any).checkCurrency(),
          refusedWith(
            "The books' settings don't list this document's currency",
          ),
        );
      });
    },
  );
}
