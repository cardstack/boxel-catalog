import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Quote } from '../quote';
import { Invoice } from '../invoice';
import type { Deal } from '../deal';
import { LineItem } from '../line-item';
import { TaxBreakdownField } from '../tax-breakdown-field';
import { TaxJurisdiction } from '../tax-jurisdiction';
import { nextInvoiceNumber } from '../invoice-number-field';
import { sumLineItems } from '../line-item-totals';
import type { Account } from '../../crm/account';
import type { User } from '../../crm/user';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import {
  findCard,
  getCard,
  inputCard,
} from '@cardstack/catalog/utils/find-card';
import { isCardOfType } from '@cardstack/catalog/utils/card-type';
import CalculateTaxCommand from './calculate-tax-command';

export class ConvertQuoteToInvoiceInput extends CardDef {
  @field quote = linksTo(Quote, { searchable: true });
  @field jurisdiction = linksTo(TaxJurisdiction);
  @field realm = contains(StringField);
}

export class ConvertQuoteToInvoiceResult extends CardDef {
  @field invoice = linksTo(Invoice);
  @field message = contains(StringField);
}

/**
 * Turns a won Quote into a draft Invoice for the quote's deal account,
 * copying its line items and, when a jurisdiction is supplied, attaching a
 * Tax Breakdown. The invoice links back to its quote, and a quote that
 * already has one gets that invoice back rather than a second.
 */
export default class ConvertQuoteToInvoiceCommand extends Command<
  typeof ConvertQuoteToInvoiceInput,
  typeof ConvertQuoteToInvoiceResult
> {
  static actionVerb = 'Convert Quote to Invoice';

  async getInputType() {
    return ConvertQuoteToInvoiceInput;
  }

  protected async run(
    input: ConvertQuoteToInvoiceInput,
  ): Promise<ConvertQuoteToInvoiceResult> {
    let ctx = this.commandContext;
    let quote = await inputCard<Quote>(ctx, input, 'quote');
    if (!quote) throw new Error('A quote is required');
    if (!isCardOfType(quote, Quote)) {
      throw new Error(`${(quote as CardDef).id ?? 'The card'} is not a quote`);
    }
    if (quote.status !== 'won') {
      throw new Error(
        `Only a won quote can be converted to an invoice (this one is "${quote.status ?? 'unset'}")`,
      );
    }
    let realm = input.realm?.trim() || (quote as any)[realmURL]?.href;
    if (!realm) throw new Error('A realm is required');

    let existing =
      quote.id &&
      (await findCard<Invoice>(ctx, Invoice, { 'quote.id': quote.id }, realm));
    if (existing) {
      return new ConvertQuoteToInvoiceResult({
        invoice: existing,
        message: `${quote.cardTitle} already has invoice ${existing.invoiceNumber}.`,
      });
    }

    let lines = quote.lineItems ?? [];
    let codes = new Set(
      lines.map((line) => line?.unitPrice?.currency?.code ?? 'USD'),
    );
    if (codes.size > 1) {
      throw new Error(
        `The quote's line items are in more than one currency (${[...codes].join(', ')}), so they can't be totalled for one invoice`,
      );
    }

    // Links are read by id and fetched: a fetched card's links may not have
    // loaded here.
    let dealId = linkedId(quote, 'deal');
    let deal = dealId ? await getCard<Deal>(ctx, dealId) : undefined;
    let accountId = deal ? linkedId(deal, 'account') : null;
    if (!accountId) {
      throw new Error(
        "The quote's deal needs an account before an invoice can be created",
      );
    }
    let account = await getCard<Account>(ctx, accountId);
    let ownerId = deal ? linkedId(deal, 'owner') : null;
    let owner = ownerId ? await getCard<User>(ctx, ownerId) : undefined;

    let jurisdiction = await inputCard<TaxJurisdiction>(
      ctx,
      input,
      'jurisdiction',
    );
    let taxBreakdown: TaxBreakdownField | undefined;
    let taxNote = '';
    if (jurisdiction) {
      let tax = await new CalculateTaxCommand(ctx).execute({
        taxableAmount: sumLineItems(lines).total,
        jurisdiction,
      } as any);
      taxBreakdown = new TaxBreakdownField({
        jurisdiction,
        taxableAmount: tax.taxableAmount,
        taxAmount: tax.taxAmount,
        rateApplied: tax.rateApplied,
      });
      taxNote = ` Tax calculated at ${tax.rateApplied}%.`;
    }

    let today = new Date();
    let invoiceNumber = nextInvoiceNumber(today);
    let invoice = (await new SaveCardCommand(ctx).execute({
      card: new Invoice({
        invoiceNumber,
        issueDate: today,
        status: 'draft',
        account,
        owner,
        quote,
        // Each line gets its own field instances; a contained field belongs
        // to one parent.
        lineItems: lines.map(
          (line) =>
            new LineItem({
              description: line?.description,
              quantity: line?.quantity,
              unitPrice: new AmountWithCurrency({
                amount: line?.unitPrice?.amount,
                currency: new CurrencyField({
                  code: line?.unitPrice?.currency?.code ?? 'USD',
                }),
              }),
            }),
        ),
        taxBreakdown,
      }),
      realm,
    } as any)) as Invoice;

    return new ConvertQuoteToInvoiceResult({
      invoice,
      message: `${invoiceNumber} created from ${quote.cardTitle}.${taxNote}`,
    });
  }
}
