import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import { Opportunity } from '@cardstack/catalog/cards/crm/opportunity';
import { Subscription } from '@cardstack/catalog/cards/commerce/subscription';
import { Invoice } from '@cardstack/catalog/cards/commerce/invoice';
import { Contract } from '@cardstack/catalog/cards/legal/contract';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { User } from '@cardstack/catalog/cards/crm/user';
import { LineItem } from '@cardstack/catalog/cards/commerce/line-item';
import { nextInvoiceNumber } from '@cardstack/catalog/cards/commerce/invoice-number-field';
import { linkedId } from '@cardstack/catalog/utils/linked-id';

export class CloseWonInput extends CardDef {
  @field deal = linksTo(Opportunity, { searchable: true });
  @field realm = contains(StringField);
}

export class CloseWonResult extends CardDef {
  @field contract = linksTo(Contract);
  @field subscription = linksTo(Subscription);
  @field invoice = linksTo(Invoice);
  @field message = contains(StringField);
}

export default class CloseWonCommand extends Command<
  typeof CloseWonInput,
  typeof CloseWonResult
> {
  static actionVerb = 'Close Won';

  async getInputType() {
    return CloseWonInput;
  }

  protected async run(input: CloseWonInput): Promise<CloseWonResult> {
    let { deal } = input;
    if (!deal) throw new Error('A deal or opportunity is required');
    let get = async <T extends CardDef>(id: string) =>
      (await new GetCardCommand(this.commandContext).execute({
        cardId: id,
      })) as T;
    if (deal.id) {
      deal = await get<Opportunity>(deal.id);
    }
    if (deal.stage === 'closed lost') {
      throw new Error('A lost deal cannot be closed won');
    }
    if (deal.stage === 'closed won') {
      throw new Error('This deal is already closed won');
    }
    let realm = input.realm?.trim() || (deal as any)[realmURL]?.href;
    if (!realm) throw new Error('A realm is required');

    // Links are read by id and fetched: a fetched card's links may not have
    // loaded here.
    let accountId = linkedId(deal, 'account');
    if (!accountId) {
      throw new Error(
        'The deal needs an account before it can be closed won — the subscription and invoice must belong to someone',
      );
    }
    let account = await get<Account>(accountId);
    let ownerId = linkedId(deal, 'owner');
    let owner = ownerId ? await get<User>(ownerId) : undefined;

    let save = async <T extends CardDef>(card: T): Promise<T> =>
      (await new SaveCardCommand(this.commandContext).execute({
        card,
        realm,
      } as any)) as T;
    let money = (amount: number, code: string) =>
      new AmountWithCurrency({ amount, currency: new CurrencyField({ code }) });

    let amount = deal.value?.amount;
    let currencyCode = deal.value?.currency?.code ?? 'USD';
    // Each card gets its own field instance; one can't be shared.
    let price = () =>
      typeof amount === 'number' ? money(amount, currencyCode) : undefined;
    let today = new Date();

    deal.stage = 'closed won';
    deal.lastStageChangedAt = today;
    await save(deal);

    // A one-year term starting today, matching the subscription it governs.
    let termEnd = new Date(today);
    termEnd.setFullYear(termEnd.getFullYear() + 1);
    let contract = await save(
      new Contract({
        title: `${deal.name} — agreement`,
        status: 'draft',
        startDate: today,
        endDate: termEnd,
        account,
        deal,
        value: price(),
      }),
    );

    let subscription = await save(
      new Subscription({
        planName: deal.name,
        billingCycle: 'yearly',
        startDate: today,
        status: 'active',
        account,
        contract,
        price: price(),
      }),
    );

    let dueDate = new Date(today);
    dueDate.setDate(dueDate.getDate() + 30);
    let invoiceNumber = nextInvoiceNumber(today);
    let invoice = await save(
      new Invoice({
        invoiceNumber,
        issueDate: today,
        dueDate,
        status: 'draft',
        account,
        owner,
        subscription,
        lineItems:
          typeof amount === 'number'
            ? [
                new LineItem({
                  description: `${deal.name} — year 1`,
                  quantity: 1,
                  unitPrice: price(),
                }),
              ]
            : [],
      }),
    );

    return new CloseWonResult({
      contract,
      subscription,
      invoice,
      message: `${deal.name} closed won: draft agreement prepared, subscription activated under it, and draft ${invoiceNumber} created.`,
    });
  }
}
