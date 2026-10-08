import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import BooleanField from '@cardstack/base/boolean';
import { Command, realmURL } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { AuditResult } from '@cardstack/catalog/cards/audit/audit-result';
import { AuditEntry } from '../audit-entry';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { checkDuty } from '../utils/duty-separation';

/**
 * Accept Risk — record the decision that a finding will be lived with.
 *
 * **Deliberately not part of closing.** Accepting a risk is somebody putting
 * their name to a gap that stays open; if the same call both recorded the
 * approval and closed the finding, one caller would be fabricating both halves
 * and the separation of duties would be theatre. So this command records a
 * decision, and Close Finding refuses `risk-accepted` until it finds one.
 *
 * The decision is stored as an Approval Step — one approver, one decision,
 * which is exactly the shape the Approve Request row implements. Note for the
 * record: that command could **not** be reused as code, because its input is
 * typed to `ServiceRequest`/`SupportAgent`. What is reused is the
 * `ApprovalStepField` block, not the command.
 */
export class AcceptRiskInput extends CardDef {
  @field result = linksTo(() => AuditResult, { searchable: true });
  @field approver = linksTo(() => Employee, { searchable: true });
  /** `approved` or `rejected`. Defaults to `approved`. */
  @field decision = contains(StringField);
  /** Why the risk is acceptable — or why it is not. Required either way. */
  @field comment = contains(TextAreaField);
}

export class AcceptRiskResult extends CardDef {
  @field recorded = contains(BooleanField);
  @field decision = contains(StringField);
  @field findingId = contains(StringField);
  @field message = contains(StringField);
}

export default class AcceptRiskCommand extends Command<
  typeof AcceptRiskInput,
  typeof AcceptRiskResult
> {
  static actionVerb = 'Record decision';
  static displayName = 'Accept Risk';

  async getInputType() {
    return AcceptRiskInput;
  }

  protected async run(input: AcceptRiskInput): Promise<AcceptRiskResult> {
    let result = input.result;
    if (!result) {
      throw new Error('An audit result is required');
    }
    if (result.id) {
      result = (await new GetCardCommand(this.commandContext).execute({
        cardId: result.id,
      })) as AuditResult;
    }
    let finding = result.finding;
    if (!finding?.findingId) {
      throw new Error(
        'That result carries no finding, so there is no risk to accept',
      );
    }
    if (finding.state === 'closed') {
      throw new Error(
        `${finding.findingId} is already closed. Reopen it before recording a new decision.`,
      );
    }

    let approver = input.approver;
    if (!approver?.id) {
      throw new Error(
        'An approver is required — an unattributed acceptance is not a decision',
      );
    }
    let decision = (input.decision ?? 'approved').trim() || 'approved';
    if (decision !== 'approved' && decision !== 'rejected') {
      throw new Error(
        `"${decision}" is not a decision. Use approved or rejected.`,
      );
    }
    let comment = (input.comment ?? '').trim();
    if (!comment) {
      throw new Error(
        decision === 'approved'
          ? 'State why the risk is acceptable — an acceptance with no reasoning cannot be defended to an auditor'
          : 'State why the risk is not acceptable',
      );
    }

    // The same engine Permission runs. Called directly rather than through the
    // command so the refusal cannot depend on a second module resolving.
    let duty = checkDuty('accept-risk', {
      actorId: approver.id,
      raisedById: finding.raisedBy?.id ?? null,
    });
    if (!duty.allowed) {
      throw new Error(`${duty.ruleId}: ${duty.reason}`);
    }

    let now = new Date();
    // Attributes deep-merge, so only the keys named here change; the nested
    // approver is a link and travels as a relationship path.
    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: AuditResult,
    }).execute({
      cardId: result.id,
      patch: {
        attributes: {
          finding: {
            riskAcceptance: {
              decision,
              decidedAt: now.toISOString(),
              comment,
              openedAt: finding.riskAcceptance?.openedAt
                ? undefined
                : now.toISOString(),
            },
          },
        },
        relationships: {
          'finding.riskAcceptance.approver': {
            links: { self: approver.id },
          },
        },
      },
    } as any);

    let realm = (result as any)[realmURL]?.href;
    if (!realm) {
      throw new Error('Could not tell which realm the audit result is in');
    }
    await new SaveCardCommand(this.commandContext).execute({
      card: new AuditEntry({
        action: decision === 'approved' ? 'approved' : 'rejected',
        occurredAt: now,
        doneBy: approver,
        subject: result,
        subjectTitle: result.cardTitle,
        note: `Risk on ${finding.findingId} ${decision} by ${approver.name ?? 'an approver'}: ${comment}`,
      }),
      realm,
    } as any);

    return new AcceptRiskResult({
      recorded: true,
      decision,
      findingId: finding.findingId,
      message:
        decision === 'approved'
          ? `${finding.findingId} may now close as risk-accepted — ${approver.name ?? 'the approver'} accepted it.`
          : `${finding.findingId} cannot close as risk-accepted — the acceptance was rejected.`,
    } as any);
  }
}
