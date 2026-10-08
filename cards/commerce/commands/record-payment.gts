import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import {
  Invoice,
  InvoiceStatusField,
  invoiceAmounts,
} from '@cardstack/catalog/cards/commerce/invoice';
import { canTransition } from '@cardstack/catalog/cards/commerce/payment-status-field';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { linkedId, linkedIds } from '@cardstack/catalog/utils/linked-id';
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
    let { invoice, amount, currencyCode, method, reference } = input;
    if (!invoice) throw new Error('An invoice is required');
    let get = async <T extends CardDef>(id: string) =>
      (await new GetCardCommand(this.commandContext).execute({
        cardId: id,
      })) as T;
    if (invoice.id) {
      invoice = await get<Invoice>(invoice.id);
    }
    if (typeof amount !== 'number' || !(amount > 0)) {
      throw new Error('A positive payment amount is required');
    }
    let realm = input.realm?.trim() || (invoice as any)[realmURL]?.href;
    if (!realm) throw new Error('A realm is required');

    // Prior payments are links, read by id and fetched: a fetched card's links
    // may not have loaded here, and saving the invoice with an unloaded list
    // would drop its payment history.
    let priorPayments = await Promise.all(
      linkedIds(invoice, 'payments').map((id) => get<Payment>(id)),
    );
    // A sell-side invoice: lines plus tax. Payments are counted below from
    // the fetched records.
    let { total, code } = invoiceAmounts({
      lineItems: invoice.lineItems,
      taxBreakdown: invoice.taxBreakdown,
    });
    let invoiceCurrency = code ?? 'USD';
    let currency = currencyCode?.trim().toUpperCase() || invoiceCurrency;
    if (currency !== invoiceCurrency) {
      throw new Error(
        `This invoice is in ${invoiceCurrency}; record the payment in ${invoiceCurrency}, converting it first if it arrived in ${currency}`,
      );
    }

    let priorPaid = priorPayments.reduce(
      (sum, p) => sum + (p?.amount?.amount ?? 0),
      0,
    );
    let paidNow = Math.round((priorPaid + amount) * 100) / 100;
    let current = invoice.status ?? '';
    let next = paidNow >= total && total > 0 ? 'paid' : 'partial';
    // A second part payment keeps the invoice at `partial`.
    if (
      !(current === 'partial' && next === 'partial') &&
      !canTransition(InvoiceStatusField, current, next)
    ) {
      throw new Error(
        `A "${current || 'unset'}" invoice can't take a payment — only a sent, viewed, part-paid or approved one`,
      );
    }

    let save = async <T extends CardDef>(card: T): Promise<T> =>
      (await new SaveCardCommand(this.commandContext).execute({
        card,
        realm,
      } as any)) as T;

    let payment = await save(
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
    );

    invoice.payments = [...priorPayments, payment];
    invoice.status = next;
    await save(invoice);

    let accountId = linkedId(invoice, 'account');
    if (accountId) {
      let account = await get<Account>(accountId);
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
