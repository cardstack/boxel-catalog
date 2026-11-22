import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import { getCard, inputCard } from '@cardstack/catalog/utils/find-card';
import { linkedId, linkedIds } from '@cardstack/catalog/utils/linked-id';
import { claimStatus, isoDayOf } from '../claim-logic';
import {
  localDate,
  planScanFill,
  scanSummary,
  scanTargets,
  type ScanOutcome,
} from '../scan-logic';
import { ReadReceiptCommand } from './read-receipt-command';
import { realmBooksSettings } from './books-settings';

export class ScanReceiptInput extends CardDef {
  static displayName = 'Scan Receipt Input';
  // CardDef, not ExpenseClaim: the claim's page imports this command (same as SubmitClaim).
  @field claim = linksTo(() => CardDef);
  /** 1-based line to read; empty = every line with a receipt photo and an empty field. */
  @field lineNo = contains(NumberField);
  /** Overrides the policy's scanModel (to compare models). */
  @field llmModel = contains(StringField);
}

export class ScanReceiptResult extends CardDef {
  static displayName = 'Scan Receipt Result';
  /** The lead and the notes as one text (for the CLI and the AI assistant). */
  @field message = contains(StringField);
  /** One line: how much was filled, and to check it. */
  @field lead = contains(StringField);
  /** One per thing left alone, disagreement or failure. */
  @field notes = containsMany(StringField);
  /** Lines that got at least one field. */
  @field filledLines = contains(NumberField);
  /** What the reads cost in USD, when OpenRouter reports it. */
  @field costUsd = contains(NumberField);
}

/**
 * Reads the receipt photos on a draft claim and fills each line's EMPTY fields (merchant,
 * date, amount, category); what it fills is marked in `aiFilled` for the person to check.
 * It never overwrites what a person typed (extract-resume's "never invent data"). The
 * model is the policy's `scanModel`, else ReadReceiptCommand's default (KB7, KB16).
 */
export class ScanReceiptCommand extends Command<
  typeof ScanReceiptInput,
  typeof ScanReceiptResult
> {
  static actionVerb = 'Read receipts';
  static displayName = 'Scan Receipts';

  async getInputType() {
    return ScanReceiptInput;
  }

  protected async run(input: ScanReceiptInput): Promise<ScanReceiptResult> {
    let ctx = this.commandContext;
    let claim = (await inputCard<CardDef>(ctx, input, 'claim')) as any;
    if (!claim?.id) {
      throw new Error('Choose a saved claim to read receipts for.');
    }
    let status = claimStatus({
      chainStepCount: claim.approvalChain?.steps?.length ?? 0,
      chainStatus: claim.approvalChain?.status,
    });
    if (status !== 'draft' && status !== 'rejected') {
      throw new Error(
        'This claim is submitted, so it is locked: receipts are read before submitting.',
      );
    }

    let policyId = linkedId(claim, 'policy');
    let policy = policyId
      ? ((await getCard<CardDef>(ctx, policyId).catch(() => undefined)) as any)
      : undefined;
    let categories = (
      await Promise.all(
        (policy ? linkedIds(policy, 'categories') : []).map((id) =>
          getCard<CardDef>(ctx, id).catch(() => undefined),
        ),
      )
    ).filter((c: any) => c?.labelEn) as any[];
    let byLabel = new Map(categories.map((c) => [c.labelEn as string, c]));
    let labelOfId = new Map(categories.map((c) => [c.id as string, c.labelEn]));

    // Line numbers count the claim's lines as the page shows them (1-based).
    let lines = (claim.lines ?? []).filter(Boolean);
    let now = lines.map((line: any) => {
      let categoryId = linkedId(claim, 'category', line);
      return {
        url: receiptUrl(claim, line),
        aiFilled: line.aiFilled,
        merchant: line.merchant,
        date: line.date,
        amount: line.amount,
        category: categoryId ? (labelOfId.get(categoryId) ?? categoryId) : '',
      };
    });
    let { targets, problem } = scanTargets(
      now.map((n: any) => ({
        ...n,
        hasReceipt: Boolean(n.url),
        receiptUrl: n.url,
      })),
      typeof input.lineNo === 'number' ? input.lineNo : null,
    );
    if (problem) {
      throw new Error(problem);
    }

    let model = input.llmModel?.trim() || policy?.scanModel?.trim() || '';
    let books = await realmBooksSettings(ctx, claim);
    let today = isoDayOf(new Date());
    let outcomes: ScanOutcome[] = [];
    let cost = 0;
    // One at a time: the proxy serialises a user's calls anyway.
    for (let lineNo of targets) {
      let line = lines[lineNo - 1];
      let before = now[lineNo - 1];
      try {
        let read = await new ReadReceiptCommand(ctx).execute({
          imageUrl: before.url,
          categories: categories.map((c) => c.labelEn),
          llmModel: model || undefined,
        } as any);
        cost += typeof read.costUsd === 'number' ? read.costUsd : 0;
        let plan = planScanFill({
          lineNo,
          now: before,
          aiFilled: line.aiFilled,
          receiptUrl: before.url,
          read: {
            isReceipt: read.isReceipt !== false,
            merchant: read.merchant ?? null,
            date: read.date ?? null,
            total: typeof read.total === 'number' ? read.total : null,
            currency: read.currency ?? null,
            category: read.category ?? null,
          },
          booksCurrency: books.currency,
          today,
        });
        let fill = plan.fill;
        if (fill.merchant !== undefined) line.merchant = fill.merchant;
        if (fill.date !== undefined) line.date = localDate(fill.date);
        if (fill.amount !== undefined) line.amount = fill.amount;
        if (fill.category !== undefined) {
          line.category = byLabel.get(fill.category);
        }
        line.aiFilled = plan.aiFilled;
        outcomes.push({ lineNo, filled: plan.filled, notes: plan.notes });
      } catch (e: any) {
        outcomes.push({
          lineNo,
          filled: [],
          notes: [],
          error: e?.message ?? String(e),
        });
      }
    }

    let { lead, notes } = scanSummary(outcomes);
    let message = [lead, ...notes].join(' ');
    if (outcomes.every((o) => o.error)) {
      throw new Error(message);
    }
    // Saved even when nothing was filled: each line now records the photo it read.
    await new SaveCardCommand(ctx).execute({ card: claim } as any);
    return new ScanReceiptResult({
      message,
      lead,
      notes,
      filledLines: outcomes.filter((o) => o.filled.length).length,
      costUsd: Math.round(cost * 1e6) / 1e6,
    });
  }
}

// The picture a line's ImageSourceField points at, read from the stored link (a command's
// fetched card has not loaded its links, so `resolvedUrl` can be empty here).
function receiptUrl(claim: CardDef, line: any): string {
  let receipt = line?.receipt;
  if (!receipt) return '';
  let mode = receipt.sourceMode || (receipt.url ? 'url' : 'file');
  if (mode === 'url') return receipt.url ?? '';
  return linkedId(claim, 'file', receipt) ?? receipt.file?.url ?? '';
}
