import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { operations } from '@cardstack/base/operations';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import {
  findCard,
  getCard,
  inputCard,
} from '@cardstack/catalog/utils/find-card';
import { linkedId } from '@cardstack/catalog/utils/linked-id';
import { Bill, Ledger } from '@cardstack/catalog/cards/accounting/ledger-cards';
import {
  approvedOn,
  billNoClash,
  isoDayOf,
  moneyText,
  planBill,
  type BooksLine,
} from '../claim-logic';
import { realmBooksSettings } from './books-settings';

export class SendClaimToBooksInput extends CardDef {
  static displayName = 'Send Claim to Books Input';
  // CardDef, not ExpenseClaim: the claim's page imports this command for its
  // button, so importing the claim here would make a cycle (as in SubmitClaim).
  @field claim = linksTo(() => CardDef);
  /** The books to enter the bill in; empty = the Ledger the claim's policy names. */
  @field ledger = linksTo(() => Ledger);
}

export class SendClaimToBooksResult extends CardDef {
  static displayName = 'Send Claim to Books Result';
  @field bill = linksTo(() => CardDef);
  @field message = contains(StringField);
}

// What a create operation answers, read the way the catalog's PostToBooksCommand reads it.
const idOf = (result: any): string | undefined =>
  result?.id ?? result?.card?.id ?? result?.data?.id ?? undefined;

// A link whose card can't be read (deleted, no access) counts as no link.
async function tryCard(ctx: any, id: string | null) {
  if (!id) return undefined;
  try {
    let card = await getCard<CardDef>(ctx, id);
    return card?.id ? (card as any) : undefined;
  } catch {
    return undefined;
  }
}

/**
 * An approved claim becomes a draft Bill in the books through the Ledger's own
 * enterBill operation (the realm stamps who entered it; an accountant posts it).
 * One bill per claim: the claim's number is the bill number, and a bill already in
 * the books under it is linked instead of entering a second one, because the books
 * accept a duplicate billNo (C6). Running it again returns the bill it made.
 */
export class SendClaimToBooksCommand extends Command<
  typeof SendClaimToBooksInput,
  typeof SendClaimToBooksResult
> {
  static actionVerb = 'Send to books';
  static displayName = 'Send Expense Claim to Books';

  async getInputType() {
    return SendClaimToBooksInput;
  }

  protected async run(
    input: SendClaimToBooksInput,
  ): Promise<SendClaimToBooksResult> {
    let ctx = this.commandContext;
    let claim = (await inputCard<CardDef>(ctx, input, 'claim')) as any;
    if (!claim?.id) {
      throw new Error('Choose a saved claim to send to the books.');
    }
    let done = (bill: CardDef, message: string) =>
      new SendClaimToBooksResult({ bill, message });

    let linked = await tryCard(ctx, linkedId(claim, 'bill'));
    if (linked) {
      return done(linked, `Already in the books as bill ${linked.billNo}.`);
    }

    let policy = await tryCard(ctx, linkedId(claim, 'policy'));
    let ledger =
      (await tryCard(ctx, linkedId(input, 'ledger'))) ??
      (policy ? await tryCard(ctx, linkedId(policy, 'ledger')) : undefined);
    if (!ledger) {
      throw new Error(
        'The expense policy names no books. Link its Ledger, then send again.',
      );
    }

    // Links aren't loaded in a command, so each line's category is read by id.
    let categories = new Map<string, any>();
    let lines: BooksLine[] = [];
    for (let line of (claim.lines ?? []).filter(Boolean)) {
      let id = linkedId(claim, 'category', line);
      if (id && !categories.has(id)) categories.set(id, await tryCard(ctx, id));
      let category = id ? categories.get(id) : undefined;
      lines.push({
        merchant: line.merchant,
        date: line.date,
        categoryLabel: category?.labelEn,
        account: category?.account,
        amountMinor: line.amountMinor,
      });
    }

    let books = await realmBooksSettings(ctx, ledger);
    let claimBooks = await realmBooksSettings(ctx, claim);
    let chain = claim.approvalChain;
    let employeeId = linkedId(claim, 'employee');
    let plan = planBill({
      claimNo: claim.claimNo,
      chainStepCount: chain?.steps?.length ?? 0,
      chainStatus: chain?.status,
      employeeId,
      lines,
      claimCurrency: claimBooks.currency,
      booksCurrency: books.currency,
      chart: books.chart,
      closedThrough: books.closedThrough,
      approvedOn: approvedOn(chain?.steps),
      today: isoDayOf(new Date()),
    });
    if (plan.problems.length) {
      throw new Error(plan.problems.join(' '));
    }

    let linkBill = async (bill: CardDef) => {
      claim.bill = bill;
      await new SaveCardCommand(ctx).execute({ card: claim } as any);
    };
    let booksRealm = ledger[realmURL]?.href as string;
    let found = await findCard<Bill>(
      ctx,
      Bill,
      { billNo: plan.billNo },
      booksRealm,
    );
    if (found) {
      let clash = billNoClash(found, plan, books.currency);
      if (clash) throw new Error(clash);
      await linkBill(found);
      return done(
        found,
        `Bill ${plan.billNo} was already in the books. Linked it to this claim.`,
      );
    }

    let employee = await tryCard(ctx, employeeId);
    let count = lines.length;
    let result = await (operations(ledger) as any).enterBill({
      billNo: plan.billNo,
      vendorId: plan.vendorId,
      date: plan.date,
      // An employee is owed the money once the claim is approved.
      due: plan.date,
      memo: `Expense claim ${plan.billNo} · ${employee?.name ?? plan.vendorId} · ${count} receipt${count === 1 ? '' : 's'}`,
      lines: plan.lines,
    });
    let id = idOf(result);
    let bill =
      (await tryCard(ctx, id ?? null)) ??
      (await findCard<Bill>(ctx, Bill, { billNo: plan.billNo }, booksRealm));
    if (!bill) {
      throw new Error(
        `The books took bill ${plan.billNo}, but it can't be read back yet. Send again in a minute to link it.`,
      );
    }
    await linkBill(bill);
    let moved = plan.movedFrom
      ? ` Dated ${plan.date}: the books are closed for ${plan.movedFrom}.`
      : '';
    return done(
      bill,
      `Draft bill ${plan.billNo} for ${moneyText(plan.totalMinor, books.currency)} is in the books of ${ledger.company || 'the Ledger'}. An accountant posts it.${moved}`,
    );
  }
}
