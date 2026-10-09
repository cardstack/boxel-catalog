import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import AmountWithCurrency from '@cardstack/base/amount-with-currency';
import CurrencyField from '@cardstack/base/currency';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { Opportunity } from '@cardstack/catalog/cards/crm/opportunity';
import {
  PipelineStageField,
  canTransition,
} from '@cardstack/catalog/cards/crm/pipeline-stage-field';
import { Subscription } from '@cardstack/catalog/cards/commerce/subscription';
import { Invoice } from '@cardstack/catalog/cards/commerce/invoice';
import { Contract } from '@cardstack/catalog/cards/legal/contract';
import { Account } from '@cardstack/catalog/cards/crm/account';
import { User } from '@cardstack/catalog/cards/crm/user';
import { LineItem } from '@cardstack/catalog/cards/commerce/line-item';
import { nextInvoiceNumber } from '@cardstack/catalog/cards/commerce/invoice-number-field';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import {
  findCard,
  getCard,
  inputCard,
} from '@cardstack/catalog/utils/find-card';

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
    let ctx = this.commandContext;
    let deal = await inputCard<Opportunity>(ctx, input, 'deal');
    if (!deal) throw new Error('A deal or opportunity is required');
    if (!canTransition(PipelineStageField, deal.stage, 'closed won')) {
      throw new Error(
        `A "${deal.stage ?? 'unset'}" deal can't be closed won — move it to negotiation first`,
      );
    }
    let amount = deal.value?.amount;
    if (typeof amount !== 'number' || !Number.isFinite(amount) || amount < 0) {
      throw new Error(
        'The deal needs a value before it can be closed won — the subscription and invoice are billed at it',
      );
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
    let account = await getCard<Account>(ctx, accountId);
    let ownerId = linkedId(deal, 'owner');
    let owner = ownerId ? await getCard<User>(ctx, ownerId) : undefined;

    let save = async <T extends CardDef>(card: T): Promise<T> =>
      (await new SaveCardCommand(ctx).execute({ card, realm } as any)) as T;
    let currencyCode = deal.value?.currency?.code ?? 'USD';
    // Each card gets its own field instance; one can't be shared.
    let price = () =>
      new AmountWithCurrency({
        amount,
        currency: new CurrencyField({ code: currencyCode }),
      });
    let today = new Date();

    // The deal is marked won last, and each record is looked up before it is
    // made, so a run interrupted part way is finished by running it again
    // rather than leaving a closed deal with missing records or duplicates.
    let contract =
      (deal.id &&
        (await findCard<Contract>(
          ctx,
          Contract,
          { 'deal.id': deal.id },
          realm,
        ))) ||
      (await save(
        new Contract({
          title: `${deal.name} — agreement`,
          status: 'draft',
          startDate: today,
          endDate: oneYearFrom(today),
          account,
          deal,
          value: price(),
        }),
      ));

    let subscription =
      (await findCard<Subscription>(
        ctx,
        Subscription,
        { 'contract.id': contract.id },
        realm,
      )) ||
      (await save(
        new Subscription({
          planName: deal.name,
          billingCycle: 'yearly',
          startDate: today,
          status: 'active',
          account,
          contract,
          price: price(),
        }),
      ));

    let invoice =
      (await findCard<Invoice>(
        ctx,
        Invoice,
        { 'subscription.id': subscription.id },
        realm,
      )) ||
      (await save(
        new Invoice({
          invoiceNumber: nextInvoiceNumber(today),
          issueDate: today,
          dueDate: daysFrom(today, 30),
          status: 'draft',
          account,
          owner,
          subscription,
          lineItems: [
            new LineItem({
              description: `${deal.name} — year 1`,
              quantity: 1,
              unitPrice: price(),
            }),
          ],
        }),
      ));

    deal.stage = 'closed won';
    deal.lastStageChangedAt = today;
    await save(deal);

    return new CloseWonResult({
      contract,
      subscription,
      invoice,
      message: `${deal.name} closed won: draft agreement prepared, subscription activated under it, and draft ${invoice.invoiceNumber} created.`,
    });
  }
}

function oneYearFrom(day: Date): Date {
  return new Date(day.getFullYear() + 1, day.getMonth(), day.getDate());
}

function daysFrom(day: Date, days: number): Date {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate() + days);
}
