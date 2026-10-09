import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import {
  Invoice,
  InvoiceStatusField,
  invoiceAmounts,
} from '@cardstack/catalog/cards/commerce/invoice';
import { canTransition } from '@cardstack/catalog/cards/commerce/payment-status-field';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { PurchaseOrder } from '@cardstack/catalog/cards/procurement/purchase-order';
import { linkedId, linkedIds } from '@cardstack/catalog/utils/linked-id';
import {
  findCards,
  getCard,
  inputCard,
} from '@cardstack/catalog/utils/find-card';
import { Payment } from '@cardstack/catalog/cards/commerce/payment';

export class RecordPaymentInput extends CardDef {
  @field invoice = linksTo(Invoice, { searchable: true });
  @field amount = contains(NumberField);
  @field currencyCode = contains(StringField);
  @field method = contains(StringField);
  @field reference = contains(StringField);
  @field realm = contains(StringField);
}

export class RecordPaymentResult extends CardDef {
  @field payment = linksTo(Payment);
  @field message = contains(StringField);
}

export default class RecordPaymentCommand extends Command<
  typeof RecordPaymentInput,
  typeof RecordPaymentResult
> {
  static actionVerb = 'Record Payment';

  async getInputType() {
    return RecordPaymentInput;
  }

  protected async run(input: RecordPaymentInput): Promise<RecordPaymentResult> {
    let ctx = this.commandContext;
    let { amount, currencyCode, method, reference } = input;
    let invoice = await inputCard<Invoice>(ctx, input, 'invoice');
    if (!invoice) throw new Error('An invoice is required');
    if (typeof amount !== 'number' || !Number.isFinite(amount) || amount <= 0) {
      throw new Error('A positive payment amount is required');
    }
    let realm = input.realm?.trim() || (invoice as any)[realmURL]?.href;
    if (!realm) throw new Error('A realm is required');

    // What is owed, as the invoice's own view reckons it: lines plus tax, less
    // any short-pay or rejected lines a vendor invoice's match resolved.
    let poId = linkedId(invoice, 'purchaseOrder');
    let { total, code } = invoiceAmounts({
      lineItems: invoice.lineItems,
      taxBreakdown: invoice.taxBreakdown,
      varianceResolutions: invoice.varianceResolutions,
      purchaseOrder: poId ? await getCard<PurchaseOrder>(ctx, poId) : undefined,
    });
    let invoiceCurrency = code ?? 'USD';
    let currency = currencyCode?.trim().toUpperCase() || invoiceCurrency;
    if (currency !== invoiceCurrency) {
      throw new Error(
        `This invoice is in ${invoiceCurrency}; record the payment in ${invoiceCurrency}, converting it first if it arrived in ${currency}`,
      );
    }

    // Payments link their invoice, so they are found by that link rather than
    // read from `invoice.payments`: the list's links may not have loaded here,
    // and a payment an interrupted run saved is found even though the invoice
    // never listed it.
    let payments = invoice.id
      ? await findCards<Payment>(ctx, Payment, { 'invoice.id': invoice.id })
      : [];
    let listed = new Set(linkedIds(invoice, 'payments'));
    let unlisted = payments.find(
      (p) =>
        !listed.has(p.id) &&
        p.amount?.amount === amount &&
        (p.reference ?? '') === (reference ?? ''),
    );

    let save = async <T extends CardDef>(card: T): Promise<T> =>
      (await new SaveCardCommand(ctx).execute({ card, realm } as any)) as T;

    let priorPaid = payments
      .filter((p) => p !== unlisted)
      .reduce((sum, p) => sum + (p?.amount?.amount ?? 0), 0);
    let paidNow = Math.round((priorPaid + amount) * 100) / 100;
    let current = invoice.status ?? '';
    let next = paidNow >= total && total > 0 ? 'paid' : 'partial';
    // A second part payment keeps the invoice at `partial`.
    if (
      !(current === 'partial' && next === 'partial') &&
      !canTransition(InvoiceStatusField, current, next)
    ) {
      throw new Error(
        `A "${current || 'unset'}" invoice can't take a payment — only a sent, viewed, part-paid or approved-for-payment one`,
      );
    }

    let payment =
      unlisted ??
      (await save(
        new Payment({
          invoice,
          amount: new AmountWithCurrency({
            amount,
            currency: new CurrencyField({ code: currency }),
          }),
          method: method || 'bank transfer',
          paidAt: new Date(),
          reference,
        }),
      ));

    invoice.payments = [...payments.filter((p) => p !== unlisted), payment];
    invoice.status = next;
    await save(invoice);

    let accountId = linkedId(invoice, 'account');
    if (accountId) {
      let account = await getCard<Account>(ctx, accountId);
      if (!account.firstPaidAt) {
        account.firstPaidAt = new Date();
        await save(account);
      }
    }

    return new RecordPaymentResult({
      payment,
      message: `Recorded ${amount} ${currency} against ${
        invoice.invoiceNumber ?? 'invoice'
      } — status ${next} (paid ${paidNow} of ${total})`,
    });
  }
}
