import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Command, identifyCard, realmURL } from '@cardstack/runtime-common';
import ReadTextFileCommand from '@cardstack/boxel-host/commands/read-text-file';
import WriteTextFileCommand from '@cardstack/boxel-host/commands/write-text-file';
import { Quote } from '../quote';
import { Invoice } from '../invoice';
import type { Deal } from '../deal';
import { TaxJurisdiction } from '../tax-jurisdiction';
import { nextInvoiceNumber } from '../invoice-number-field';
import { sumLineItems } from '../line-item-totals';
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

function localDay(date: Date): string {
  let month = String(date.getMonth() + 1).padStart(2, '0');
  let day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

/**
 * Turns a won Quote into a draft Invoice for the quote's deal account,
 * copying its line items and, when a jurisdiction is supplied, attaching a
 * Tax Breakdown.
 *
 * The invoice is written at a path named after the quote, `Invoice/<quote>`
 * in the target realm. Before anything else a run reads that path; when it
 * holds this quote's invoice, that invoice is returned. The read goes to the
 * realm's files rather than its index, so a run that starts after an earlier
 * one finished gets that invoice back even before the index has caught up.
 * Runs that overlap are not covered: both can pass the read, and the later
 * write replaces the earlier invoice. Each run reports the invoice the file
 * holds when it reads it back. An invoice made some other way is found
 * through the index instead.
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
    let quoteId = quote.id;
    let quoteTitle = quote.cardTitle;
    if (!quoteId) throw new Error('The quote has to be saved first');
    let target: string | undefined =
      input.realm?.trim() || (quote as any)[realmURL]?.href;
    if (!target) throw new Error('A realm is required');
    const realm = target.endsWith('/') ? target : `${target}/`;

    let path = `Invoice/${quoteId.split('/').pop()}.json`;
    let invoiceId = new URL(path.replace(/\.json$/, ''), realm).href;
    let alreadyMade = async (): Promise<Invoice | undefined> => {
      if (await this.invoiceAt(realm, path, quoteId)) {
        return getCard<Invoice>(ctx, invoiceId);
      }
      return findCard<Invoice>(ctx, Invoice, { 'quote.id': quoteId }, realm);
    };
    let found = (invoice: Invoice) =>
      new ConvertQuoteToInvoiceResult({
        invoice,
        message: `${quoteTitle} already has invoice ${invoice.invoiceNumber}.`,
      });

    // A converted quote returns its invoice whatever its status is now.
    let existing = await alreadyMade();
    if (existing) return found(existing);

    if (quote.status !== 'won') {
      throw new Error(
        `Only a won quote can be converted to an invoice (this one is "${quote.status ?? 'unset'}")`,
      );
    }
    let lines = quote.lineItems ?? [];
    let codes = new Set(
      lines.map((line) => line?.unitPrice?.currency?.code ?? 'no currency'),
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
    let ownerId = deal ? linkedId(deal, 'owner') : null;

    let jurisdiction = await inputCard<TaxJurisdiction>(
      ctx,
      input,
      'jurisdiction',
    );
    let taxBreakdown: Record<string, number> | null = null;
    let taxNote = '';
    if (jurisdiction) {
      let tax = await new CalculateTaxCommand(ctx).execute({
        taxableAmount: sumLineItems(lines).total,
        jurisdiction,
      } as any);
      taxBreakdown = {
        taxableAmount: tax.taxableAmount,
        taxAmount: tax.taxAmount,
        rateApplied: tax.rateApplied,
      };
      taxNote = ` Tax calculated at ${tax.rateApplied}%.`;
    }

    let today = new Date();
    let self = (id: string | null | undefined) => ({
      links: { self: id ?? null },
    });
    let doc = {
      data: {
        type: 'card',
        attributes: {
          invoiceNumber: nextInvoiceNumber(today),
          issueDate: localDay(today),
          status: 'draft',
          lineItems: lines.map((line) => ({
            description: line?.description ?? null,
            quantity: line?.quantity ?? null,
            unitPrice: {
              amount: line?.unitPrice?.amount ?? null,
              currency: { code: line?.unitPrice?.currency?.code ?? null },
            },
          })),
          taxBreakdown,
        },
        relationships: {
          account: self(accountId),
          owner: self(ownerId),
          quote: self(quoteId),
          ...(jurisdiction
            ? { 'taxBreakdown.jurisdiction': self(jurisdiction.id) }
            : {}),
        },
        meta: { adoptsFrom: identifyCard(Invoice) },
      },
    };

    try {
      await new WriteTextFileCommand(ctx).execute({
        realm,
        path,
        content: JSON.stringify(doc, null, 2),
      });
    } catch (e) {
      // The write refuses a file that appeared after the read.
      let raced = await alreadyMade();
      if (raced) return found(raced);
      throw e;
    }

    let invoice = await getCard<Invoice>(ctx, invoiceId);
    return new ConvertQuoteToInvoiceResult({
      invoice,
      message: `${invoice.invoiceNumber} created from ${quote.cardTitle}.${taxNote}`,
    });
  }

  // Whether `path` in `realm` holds an invoice for `quoteId`. A file there
  // that belongs to another quote is an error, not a match.
  private async invoiceAt(
    realm: string,
    path: string,
    quoteId: string,
  ): Promise<boolean> {
    let content: string | undefined;
    try {
      ({ content } = await new ReadTextFileCommand(this.commandContext).execute(
        { realm, path },
      ));
    } catch {
      return false;
    }
    let link = JSON.parse(content ?? '{}')?.data?.relationships?.quote?.links
      ?.self;
    let fileURL = new URL(path, realm);
    let linked = link ? new URL(link, fileURL).href : undefined;
    if (linked !== quoteId) {
      throw new Error(
        `${fileURL.href} already exists and isn't this quote's invoice`,
      );
    }
    return true;
  }
}
