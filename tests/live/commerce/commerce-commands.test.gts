import { getService } from '@universal-ember/test-support';
import { module, test } from 'qunit';

import {
  setupLocalIndexing,
  setupOnSave,
  setupAuthEndpoints,
  setupUserSubscription,
  setupAcceptanceTestRealm,
  SYSTEM_CARD_FIXTURE_CONTENTS,
  visitOperatorMode,
} from '@cardstack/host/tests/helpers';
import { setupMockMatrix } from '@cardstack/host/tests/helpers/mock-matrix';
import { setupApplicationTest } from '@cardstack/host/tests/helpers/setup';

import type CalculateTaxCommand from '../../../cards/commerce/commands/calculate-tax-command';
import type ConvertQuoteToInvoiceCommand from '../../../cards/commerce/commands/convert-quote-to-invoice-command';
import type { Invoice } from '../../../cards/commerce/invoice';
import type { Quote } from '../../../cards/commerce/quote';
import type { TaxJurisdiction } from '../../../cards/commerce/tax-jurisdiction';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const catalogRealmURL: string = new URL('../../../', import.meta.url).href;
const realmURL = 'http://test-realm/commerce/';
const cards = `${catalogRealmURL}cards/`;

function instance(
  module: string,
  name: string,
  attributes: Record<string, unknown> = {},
  relationships: Record<string, unknown> = {},
) {
  return {
    data: {
      type: 'card',
      attributes,
      relationships,
      meta: { adoptsFrom: { module: `${cards}${module}`, name } },
    },
  };
}

function link(id: string) {
  return { links: { self: `${realmURL}${id}` } };
}

function line(description: string, amount: number, code = 'USD') {
  return {
    description,
    quantity: 1,
    unitPrice: { amount, currency: { code } },
  };
}

function quote(
  status: string,
  dealId: string,
  lineItems = [line('Annual plan', 1000), line('Onboarding', 200)],
) {
  return instance(
    'commerce/quote',
    'Quote',
    { version: 1, status, lineItems },
    { deal: link(dealId) },
  );
}

export function runTests() {
  module(
    'Acceptance | Catalog | commerce - tax and quote commands',
    function (hooks) {
      setupApplicationTest(hooks);
      setupLocalIndexing(hooks);
      setupOnSave(hooks);

      let mockMatrixUtils = setupMockMatrix(hooks, {
        loggedInAs: '@testuser:localhost',
        activeRealms: [realmURL],
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
            'acme.json': instance('crm/account', 'Account', { name: 'Acme' }),
            'dana.json': instance('crm/user', 'User', { name: 'Dana' }),
            'deal.json': instance(
              'commerce/deal',
              'Deal',
              { name: 'Acme Renewal', stage: 'closed won' },
              { account: link('acme'), owner: link('dana') },
            ),
            'no-account-deal.json': instance('commerce/deal', 'Deal', {
              name: 'Orphan Deal',
              stage: 'closed won',
            }),
            'won.json': quote('won', 'deal'),
            'sent.json': quote('sent', 'deal'),
            'orphan.json': quote('won', 'no-account-deal'),
            'mixed.json': quote('won', 'deal', [
              line('Annual plan', 1000, 'USD'),
              line('Local support', 200, 'EUR'),
            ]),
            // An invoice already at the path a converted quote's invoice
            // takes, and one at a path that belongs to another quote.
            'converted.json': quote('lost', 'deal'),
            'Invoice/converted.json': instance(
              'commerce/invoice',
              'Invoice',
              { invoiceNumber: 'INV-2026-EARLIER', status: 'draft' },
              { quote: link('converted') },
            ),
            'taken.json': quote('won', 'deal'),
            'Invoice/taken.json': instance(
              'commerce/invoice',
              'Invoice',
              { invoiceNumber: 'INV-2026-OTHER', status: 'draft' },
              { quote: link('elsewhere') },
            ),
            'california.json': instance(
              'commerce/tax-jurisdiction',
              'TaxJurisdiction',
              { country: 'United States', region: 'California', rate: 7.25 },
            ),
            'unrated.json': instance(
              'commerce/tax-jurisdiction',
              'TaxJurisdiction',
              { country: 'Nowhere', region: 'Unset' },
            ),
          },
        });
        await visitOperatorMode({ stacks: [[]] });
      });

      // The inputs link cards, so each command has to come from the loader the
      // store builds those cards with.
      async function load<T>(path: string): Promise<T> {
        let { default: Command } = (await getService(
          'loader-service',
        ).loader.import(`${cards}commerce/commands/${path}`)) as {
          default: T;
        };
        return Command;
      }

      function get<T>(id: string): Promise<T> {
        return getService('store').get(`${realmURL}${id}`) as Promise<T>;
      }

      async function calculate(taxableAmount: number, jurisdictionId: string) {
        let Command = await load<typeof CalculateTaxCommand>(
          'calculate-tax-command',
        );
        return new Command(getService('tool-service').commandContext).execute({
          taxableAmount,
          jurisdiction: await get<TaxJurisdiction>(jurisdictionId),
        });
      }

      async function convert(quoteId: string, jurisdictionId?: string) {
        let Command = await load<typeof ConvertQuoteToInvoiceCommand>(
          'convert-quote-to-invoice-command',
        );
        return new Command(getService('tool-service').commandContext).execute({
          quote: await get<Quote>(quoteId),
          jurisdiction: jurisdictionId
            ? await get<TaxJurisdiction>(jurisdictionId)
            : undefined,
        });
      }

      test('calculate-tax applies the rate, rounded to the cent', async function (assert) {
        let result = await calculate(1234.56, 'california');
        assert.strictEqual(result?.rateApplied, 7.25);
        assert.strictEqual(result?.taxAmount, 89.51);
      });

      test('calculate-tax refuses a negative amount', async function (assert) {
        await assert.rejects(
          calculate(-5, 'california'),
          /taxable amount of zero or more/,
        );
      });

      test('calculate-tax refuses a jurisdiction with no rate', async function (assert) {
        await assert.rejects(calculate(100, 'unrated'), /has no tax rate/);
      });

      test('convert-quote-to-invoice refuses a quote that is not won', async function (assert) {
        await assert.rejects(
          convert('sent'),
          /Only a won quote can be converted to an invoice \(this one is "sent"\)/,
        );
      });

      test('convert-quote-to-invoice returns the invoice of a quote converted earlier, whatever its status now', async function (assert) {
        let result = await convert('converted');
        assert.strictEqual(
          (result?.invoice as Invoice | undefined)?.id,
          `${realmURL}Invoice/converted`,
        );
        assert.ok(
          /already has invoice INV-2026-EARLIER/.test(result?.message ?? ''),
          result?.message,
        );
      });

      test("convert-quote-to-invoice refuses when the quote's invoice path holds another quote's invoice", async function (assert) {
        await assert.rejects(
          convert('taken'),
          /already exists and isn't this quote's invoice/,
        );
      });

      test('convert-quote-to-invoice refuses a quote whose deal has no account', async function (assert) {
        await assert.rejects(convert('orphan'), /needs an account/);
      });

      test('convert-quote-to-invoice refuses line items in more than one currency', async function (assert) {
        await assert.rejects(convert('mixed'), /more than one currency/);
      });

      test('convert-quote-to-invoice makes one draft invoice with tax, and a second run returns it', async function (assert) {
        let first = await convert('won', 'california');
        let invoice = first?.invoice as Invoice | undefined;
        assert.strictEqual(
          invoice?.id,
          `${realmURL}Invoice/won`,
          "the invoice is created at the quote's own path",
        );
        let saved = await getService('store').get(invoice!.id!);
        let fresh = saved as Invoice;
        assert.strictEqual(fresh.status, 'draft');
        assert.ok(
          /^INV-\d{4}-/.test(fresh.invoiceNumber ?? ''),
          fresh.invoiceNumber,
        );
        assert.strictEqual(
          fresh.lineItems?.length,
          2,
          'the line items are copied',
        );
        assert.strictEqual(fresh.taxBreakdown?.taxableAmount, 1200);
        assert.strictEqual(fresh.taxBreakdown?.taxAmount, 87);
        assert.strictEqual(
          fresh.quote?.id,
          `${realmURL}won`,
          'it links back to its quote',
        );
        assert.strictEqual(fresh.account?.id, `${realmURL}acme`);

        let second = await convert('won', 'california');
        assert.strictEqual(
          (second?.invoice as Invoice | undefined)?.id,
          invoice!.id,
          'a second run returns the same invoice',
        );
        assert.ok(
          /already has invoice/.test(second?.message ?? ''),
          second?.message,
        );
      });
    },
  );
}
