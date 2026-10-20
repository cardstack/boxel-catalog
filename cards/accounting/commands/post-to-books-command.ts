import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { operations } from '@cardstack/base/operations';
import { Command, realmURL } from '@cardstack/runtime-common';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import {
  findCard,
  getCard,
  inputCard,
} from '@cardstack/catalog/utils/find-card';
import { isCardOfType } from '@cardstack/catalog/utils/card-type';
import { Quote } from '@cardstack/catalog/cards/commerce/quote';
import { Invoice as CommerceInvoice } from '@cardstack/catalog/cards/commerce/invoice';
import { Payment as CommercePayment } from '@cardstack/catalog/cards/commerce/payment';
import { PurchaseOrder } from '@cardstack/catalog/cards/procurement/purchase-order';
import { Invoice, CustomerPayment, Customer } from '../ledger-sales';
import { Bill, Ledger, Vendor } from '../ledger-cards';
import { BillPayment } from '../ledger-payments';
import { settingsOf } from '../ledger-settings';
import { dueDateFor } from '../ledger-terms';
import {
  BridgeRefusal,
  billLinesFrom,
  currencyOf,
  isPayable,
  isoDay,
  saleLinesFrom,
  tail,
  toMinor,
} from '../ledger-bridge';

export class PostToBooksInput extends CardDef {
  // A won commerce Quote, a commerce Invoice or Payment, or a procurement PurchaseOrder.
  @field source = linksTo(CardDef);
  @field ledger = linksTo(() => Ledger);
  @field incomeAccount = contains(StringField); // default 4000
  @field expenseAccount = contains(StringField); // default 6950
  @field depositAccount = contains(StringField); // where a customer payment waits; default 1010
  @field payFromAccount = contains(StringField); // what a bill payment is paid from; default 1000
}

export class PostToBooksResult extends CardDef {
  @field draft = linksTo(CardDef);
  @field message = contains(StringField);
}

const today = () => isoDay(new Date());
const idOf = (result: any) =>
  result?.id ?? result?.card?.id ?? result?.data?.id ?? undefined;

/**
 * Brings an operational document into the books as a draft that links back to it: a won quote or
 * a customer's commerce invoice becomes an Invoice, a vendor's commerce invoice or a purchase
 * order's received goods a Bill, and a commerce payment a customer or bill payment. Running it again
 * for the same source returns the draft already made. The draft posts like any other, so the
 * books' checks still apply, and it can be corrected before it does.
 */
export default class PostToBooksCommand extends Command<
  typeof PostToBooksInput,
  typeof PostToBooksResult
> {
  static actionVerb = 'Post to the books';

  async getInputType() {
    return PostToBooksInput;
  }

  protected async run(input: PostToBooksInput): Promise<PostToBooksResult> {
    let ctx = this.commandContext;
    let source = await inputCard<CardDef>(ctx, input, 'source');
    if (!source?.id)
      throw new BridgeRefusal('Choose a saved document to post.');
    let ledger = await inputCard<Ledger>(ctx, input, 'ledger');
    let home = ledger ? settingsOf(ledger as any).currency : 'USD';
    let realm = (source as any)[realmURL]?.href as string;
    let income = input.incomeAccount || '4000',
      expense = input.expenseAccount || '6950';
    let made = (draft: CardDef | undefined, message: string) =>
      new PostToBooksResult({ draft, message });
    let existing = async (type: typeof CardDef, key: string) =>
      findCard<CardDef>(ctx, type, { [`${key}.id`]: source!.id }, realm);
    let books = () => {
      if (!ledger)
        throw new BridgeRefusal('Choose the Ledger the bill goes into.');
      return ledger as any;
    };
    let customerOf = async (accountId: string | null) => {
      let c = accountId ? await getCard<CardDef>(ctx, accountId) : undefined;
      if (!c || !isCardOfType(c, Customer))
        throw new BridgeRefusal(
          'Its account isn’t a customer in the books. Make the account a Customer card first.',
        );
      return c as unknown as Customer;
    };
    let vendorOf = async (po: PurchaseOrder | undefined) => {
      let id = po ? linkedId(po, 'vendor') : null;
      let v = id ? await getCard<CardDef>(ctx, id) : undefined;
      if (!v || !isCardOfType(v, Vendor))
        throw new BridgeRefusal(
          'Its vendor isn’t a vendor in the books. Make the vendor a Vendor card first.',
        );
      return v as unknown as Vendor;
    };

    if (isCardOfType(source, Quote)) {
      let quote = source as unknown as Quote;
      let found = await existing(Invoice, 'quote');
      if (found) return made(found, 'This quote is already in the books.');
      if (quote.status !== 'won')
        throw new BridgeRefusal(
          `Only a won quote becomes an invoice (this one is ${quote.status ?? 'unset'}).`,
        );
      currencyOf(quote.lineItems ?? [], home);
      let dealId = linkedId(quote, 'deal');
      let deal = dealId ? await getCard<CardDef>(ctx, dealId) : undefined;
      let customer = await customerOf(deal ? linkedId(deal, 'account') : null);
      let date = today();
      let result = await (operations(customer as any) as any).invoiceFromQuote({
        docNo: `INV-${tail(quote.id)}`,
        date,
        due: dueDateFor(date, (customer as any).defaultTerms) || date,
        memo: `From quote ${quote.cardTitle ?? tail(quote.id)}`,
        lines: saleLinesFrom(quote.lineItems ?? [], income),
        quote: quote.id,
      });
      return made(
        await getCard(ctx, idOf(result)),
        'Drafted the invoice for this quote.',
      );
    }

    if (isCardOfType(source, CommerceInvoice)) {
      let inv = source as unknown as CommerceInvoice;
      currencyOf(inv.lineItems ?? [], home);
      let date = isoDay(inv.issueDate) || today();
      let due = isoDay(inv.dueDate) || date;
      if (isPayable(inv as any)) {
        let found = await existing(Bill, 'sourceInvoice');
        if (found)
          return made(found, 'This vendor invoice is already in the books.');
        let poId = linkedId(inv, 'purchaseOrder');
        let po = poId ? await getCard<PurchaseOrder>(ctx, poId) : undefined;
        let vendor = await vendorOf(po);
        let result = await (operations(books()) as any).billFromCommerce({
          billNo: inv.invoiceNumber || `B-${tail(inv.id)}`,
          vendorId: (vendor as any).vendorId,
          date,
          due,
          memo: `Vendor invoice ${inv.invoiceNumber ?? tail(inv.id)}`,
          lines: billLinesFrom(inv.lineItems ?? [], expense),
          vendor: vendor.id,
          sourceInvoice: inv.id,
        });
        return made(
          await getCard(ctx, idOf(result)),
          'Drafted the bill for this vendor invoice.',
        );
      }
      let found = await existing(Invoice, 'sourceInvoice');
      if (found) return made(found, 'This invoice is already in the books.');
      let customer = await customerOf(linkedId(inv, 'account'));
      let result = await (
        operations(customer as any) as any
      ).invoiceFromCommerce({
        docNo: inv.invoiceNumber || `INV-${tail(inv.id)}`,
        date,
        due,
        memo: `From invoice ${inv.invoiceNumber ?? tail(inv.id)}`,
        lines: saleLinesFrom(inv.lineItems ?? [], income),
        sourceInvoice: inv.id,
      });
      return made(
        await getCard(ctx, idOf(result)),
        'Drafted the invoice in the books.',
      );
    }

    if (isCardOfType(source, CommercePayment)) {
      let pay = source as unknown as CommercePayment;
      let invId = linkedId(pay, 'invoice');
      let inv = invId ? await getCard<CommerceInvoice>(ctx, invId) : undefined;
      if (!inv)
        throw new BridgeRefusal('The payment isn’t against an invoice.');
      let code = pay.amount?.currency?.code;
      if (code && code !== home)
        throw new BridgeRefusal(
          `It's in ${code} and the books are kept in ${home}.`,
        );
      let date = isoDay(pay.paidAt) || today();
      let amountMinor = toMinor(pay.amount?.amount);
      let docNo = `RP-${pay.reference || tail(pay.id)}`;
      if (isPayable(inv as any)) {
        let found = await existing(BillPayment, 'sourcePayment');
        if (found) return made(found, 'This payment is already in the books.');
        let bill = await findCard<Bill>(
          ctx,
          Bill,
          { 'sourceInvoice.id': inv.id },
          realm,
        );
        if (!bill)
          throw new BridgeRefusal(
            'Post its vendor invoice to the books first.',
          );
        let vendor = bill.vendor;
        let result = await (operations(books()) as any).billPaymentFromCommerce(
          {
            paymentNo: docNo,
            vendorId: bill.vendorId,
            date,
            fromAccount: input.payFromAccount || '1000',
            memo: `Payment ${pay.reference ?? tail(pay.id)}`,
            applications: [{ billNo: bill.billNo, amountMinor }],
            vendor: (vendor as any)?.id ?? linkedId(bill, 'vendor'),
            sourcePayment: pay.id,
          },
        );
        return made(
          await getCard(ctx, idOf(result)),
          'Drafted the bill payment.',
        );
      }
      let found = await existing(CustomerPayment, 'sourcePayment');
      if (found) return made(found, 'This payment is already in the books.');
      let booked = await findCard<Invoice>(
        ctx,
        Invoice,
        { 'sourceInvoice.id': inv.id },
        realm,
      );
      if (!booked)
        throw new BridgeRefusal('Post its invoice to the books first.');
      let customer = await customerOf(linkedId(inv, 'account'));
      let result = await (
        operations(customer as any) as any
      ).paymentFromCommerce({
        docNo,
        date,
        memo: `Payment ${pay.reference ?? tail(pay.id)}`,
        depositTo: input.depositAccount || '1010',
        applications: [{ invoiceNo: booked.docNo, amountMinor }],
        sourcePayment: pay.id,
      });
      return made(
        await getCard(ctx, idOf(result)),
        'Drafted the customer payment.',
      );
    }

    if (isCardOfType(source, PurchaseOrder)) {
      let po = source as unknown as PurchaseOrder;
      let found = await existing(Bill, 'purchaseOrder');
      if (found)
        return made(found, 'This purchase order is already in the books.');
      currencyOf(po.lineItems ?? [], home);
      let lines = billLinesFrom(
        po.lineItems ?? [],
        expense,
        po.receivedQuantities ?? [],
      );
      if (!lines.length)
        throw new BridgeRefusal(
          'Nothing on this purchase order has been received yet.',
        );
      let vendor = await vendorOf(po);
      let date = today();
      let result = await (operations(books()) as any).billFromPurchaseOrder({
        billNo: `B-${po.poNumber || tail(po.id)}`,
        vendorId: (vendor as any).vendorId,
        date,
        due: dueDateFor(date, (vendor as any).defaultTerms) || date,
        memo: `Received on ${po.poNumber ?? tail(po.id)}`,
        lines,
        vendor: vendor.id,
        purchaseOrder: po.id,
      });
      return made(
        await getCard(ctx, idOf(result)),
        'Drafted the bill for what was received.',
      );
    }

    throw new BridgeRefusal(
      'The books take a won quote, a commerce invoice or payment, or a purchase order.',
    );
  }
}
