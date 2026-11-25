import { CardDef, contains, field, linksTo } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Command, realmURL } from '@cardstack/runtime-common';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import {
  findCards,
  getCard,
  inputCard,
} from '@cardstack/catalog/utils/find-card';
import { linkedId, linkedIds } from '@cardstack/catalog/utils/linked-id';
import { evaluateRules } from '@cardstack/catalog/cards/legal/approval-rule';
import { ApprovalChainField } from '@cardstack/catalog/cards/hr/approval-chain-field';
import { ApprovalStepField } from '@cardstack/catalog/cards/hr/approval-step-field';
import { toMinor } from '@cardstack/catalog/cards/accounting/ledger-bridge';
import {
  CLAIM_STATUS_LABELS,
  claimStatus,
  flagCountText,
  isoDayOf,
  planApprovalChain,
  policyFlags,
  submitProblems,
  type FlagLine,
  type OtherClaim,
  type PolicyFlag,
} from '../claim-logic';
import { ClaimFlagField } from '../claim-flag';
import { realmBooksSettings } from './books-settings';

export class SubmitClaimInput extends CardDef {
  static displayName = 'Submit Claim Input';
  // Typed as CardDef, not ExpenseClaim: the claim module imports this command for
  // its button, so importing the claim here would make a cycle (same reason as
  // the HR ApproveChainStepCommand's `target`).
  @field claim = linksTo(() => CardDef);
}

export class SubmitClaimResult extends CardDef {
  static displayName = 'Submit Claim Result';
  @field message = contains(StringField);
}

/**
 * Checks a draft (or rejected) claim against its policy, then starts the approval
 * chain: the employee's manager, then the roles the policy's ApprovalRules require
 * for this total. Refuses with every problem at once, in words for the employee.
 */
export class SubmitClaimCommand extends Command<
  typeof SubmitClaimInput,
  typeof SubmitClaimResult
> {
  static actionVerb = 'Submit';
  static displayName = 'Submit Expense Claim';

  async getInputType() {
    return SubmitClaimInput;
  }

  protected async run(input: SubmitClaimInput): Promise<SubmitClaimResult> {
    let ctx = this.commandContext;
    let claim = (await inputCard<CardDef>(ctx, input, 'claim')) as any;
    if (!claim?.id) {
      throw new Error('Choose a saved claim to submit.');
    }

    let employeeId = linkedId(claim, 'employee');
    let employee = employeeId
      ? await getCard<CardDef>(ctx, employeeId)
      : undefined;
    let policyId = linkedId(claim, 'policy');
    let policy = policyId
      ? ((await getCard<CardDef>(ctx, policyId)) as any)
      : undefined;

    let books = await realmBooksSettings(ctx, claim);
    let receiptFrom = policy?.receiptRequiredAbove;
    let problems = submitProblems({
      lines: (claim.lines ?? []).map((line: any) => ({
        merchant: line?.merchant,
        amountMinor: line?.amountMinor,
        hasCategory: Boolean(line && linkedId(claim, 'category', line)),
        hasReceipt: Boolean(
          line?.receipt?.url ||
          (line?.receipt && linkedId(claim, 'file', line.receipt)),
        ),
      })),
      receiptRequiredFromMinor:
        typeof receiptFrom === 'number' ? toMinor(receiptFrom) : null,
      chainStatus: claim.approvalChain?.status,
      chainStepCount: claim.approvalChain?.steps?.length ?? 0,
      currency: books.currency,
    });
    if (!employee) problems.unshift('Choose the employee this claim is for.');
    if (!policy) problems.unshift('Link an expense policy before submitting.');
    if (problems.length) {
      throw new Error(problems.join(' '));
    }

    let rules = await Promise.all(
      linkedIds(policy, 'approvalRules').map((id) => getCard(ctx, id)),
    );
    let fired = evaluateRules(rules, {
      value: { amount: (claim.totalMinor ?? 0) / 100 },
    } as any).map((f) => ({
      name: f.name,
      because: f.because,
      roles: f.roles,
    }));

    let plan = planApprovalChain({
      employeeId,
      employeeName: (employee as any).name,
      managerId: linkedId(employee as CardDef, 'manager'),
      firedRules: fired,
      roleApprovers: (policy.roleApprovers ?? []).map((r: any) => ({
        role: r?.role,
        approverId: r ? linkedId(policy, 'approver', r) : null,
      })),
    });
    if (plan.problems.length) {
      throw new Error(plan.problems.join(' '));
    }

    let now = new Date();
    let flags = await this.policyFlagsFor(
      claim,
      employee as CardDef,
      policy,
      now,
      books.currency,
    );
    let approvers: any[] = [];
    let steps: ApprovalStepField[] = [];
    let notes: string[] = [];
    for (let [i, s] of plan.steps.entries()) {
      let approver = await getCard<CardDef>(ctx, s.approverId);
      approvers.push(approver);
      // openedAt = when the step became the current one, so only the first step
      // has it now. `conditions` stays empty: on the HR step it means "approved
      // with conditions", which is the approver's to write, not ours.
      steps.push(
        new ApprovalStepField({
          approver,
          decision: 'pending',
          openedAt: i === 0 ? now : null,
        }),
      );
      if (s.reason) {
        notes.push(`${(approver as any)?.name ?? 'Approver'}: ${s.reason}`);
      }
    }
    claim.approvalChain = new ApprovalChainField({ startedAt: now, steps });
    claim.approvalNotes = notes;
    claim.policyFlags = flags.map((f) => new ClaimFlagField(f));
    claim.submittedDate = now;
    await new SaveCardCommand(ctx).execute({ card: claim } as any);

    let names = approvers.map((a) => a?.name).filter(Boolean);
    let flagged = flags.length
      ? ` ${flagCountText(flags.length)} for the approvers to check.`
      : '';
    return new SubmitClaimResult({
      message: `Submitted. Waiting on ${names.join(', then ')}.${flagged}`,
    });
  }

  // P1, P3 and P4 (claim-logic.ts). Links aren't loaded in a command, so each
  // category is read by id, and the employee's other claims are searched for.
  private async policyFlagsFor(
    claim: any,
    employee: CardDef,
    policy: any,
    now: Date,
    currency: string,
  ): Promise<PolicyFlag[]> {
    let ctx = this.commandContext;
    let categories = new Map<string, any>();
    let lines: FlagLine[] = [];
    for (let line of (claim.lines ?? []).filter(Boolean)) {
      let id = linkedId(claim, 'category', line);
      if (id && !categories.has(id)) {
        categories.set(id, await getCard(ctx, id).catch(() => undefined));
      }
      let category = id ? categories.get(id) : undefined;
      let cap = category?.capAmount;
      lines.push({
        merchant: line.merchant,
        date: line.date,
        amountMinor: line.amountMinor,
        categoryLabel: category?.labelEn,
        capMinor: typeof cap === 'number' ? toMinor(cap) : null,
      });
    }
    let otherClaims: OtherClaim[] = [];
    let searchFailed = false;
    try {
      let found = await findCards<CardDef>(
        ctx,
        claim.constructor as typeof CardDef,
        { 'employee.id': employee.id },
        claim[realmURL]?.href ?? '',
      );
      for (let other of found as any[]) {
        let steps = other?.approvalChain?.steps?.length ?? 0;
        if (!other || other.id === claim.id || !steps) continue;
        let status = claimStatus({
          chainStepCount: steps,
          chainStatus: other.approvalChain?.status,
        });
        otherClaims.push({
          claimNo: other.claimNo,
          status: CLAIM_STATUS_LABELS[status].toLowerCase(),
          lines: (other.lines ?? []).filter(Boolean),
        });
      }
    } catch {
      searchFailed = true;
    }
    let flags = policyFlags({
      lines,
      submitWithinDays: policy?.submitWithinDays,
      submittedOn: isoDayOf(now),
      otherClaims,
      currency,
    });
    if (searchFailed) {
      flags.push({
        rule: 'P4',
        lineNo: 0,
        message:
          "The employee's other claims couldn't be searched, so receipts weren't checked against them.",
      });
    }
    return flags;
  }
}
