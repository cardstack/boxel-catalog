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
import { Task } from '@cardstack/catalog/cards/tasks/task';
import {
  RESOLUTION_CODES,
  RESOLUTION_LABELS,
} from '@cardstack/catalog/fields/resolution-code/resolution-code-field';
import { closureGap } from '@cardstack/catalog/cards/audit/utils/finding-closure';
import { checkDuty } from '../utils/duty-separation';
import { linkedId } from '../utils/linked-id';

/**
 * Close Finding — the only way a finding stops being open.
 *
 * **Closing is a coded act, never a status flip.** Six things are checked
 * before anything is written, and each refusal names what is missing rather
 * than reporting "invalid": the code exists and is in the vocabulary; somebody
 * is named; `remediated` has its corrective action actually done; and
 * `risk-accepted` has an approval already on record from Accept Risk.
 *
 * **Nothing is deleted and nothing is overwritten.** A closed finding keeps
 * its statement, its evidence and its severity; the note becomes an annotation
 * appended to what is already there, and the trail gets an entry. A compliance
 * team's first question about any tool is whether it can quietly lose a
 * finding, and the answer here has to be no.
 *
 * The gate itself lives in `utils/finding-closure` so the sentence this
 * command refuses with is the same one the finding displays as its blocker.
 */
export class CloseFindingInput extends CardDef {
  @field result = linksTo(() => AuditResult, { searchable: true });
  /** One of remediated, risk-accepted, false-positive, duplicate, superseded, out-of-scope. */
  @field code = contains(StringField);
  @field closedBy = linksTo(() => Employee, { searchable: true });
  /** Required for `remediated`: the task the fix was done under. */
  @field correctiveAction = linksTo(() => Task);
  /** Recorded as an annotation on the finding, not as a replacement statement. */
  @field note = contains(TextAreaField);
}

export class CloseFindingResult extends CardDef {
  @field closed = contains(BooleanField);
  @field findingId = contains(StringField);
  @field code = contains(StringField);
  @field message = contains(StringField);
}

function annotationToJSON(a: any) {
  return {
    anchor: a?.anchor ?? null,
    text: a?.text ?? null,
    kind: a?.kind ?? null,
    createdAt: a?.createdAt ? new Date(a.createdAt).toISOString() : null,
  };
}

export default class CloseFindingCommand extends Command<
  typeof CloseFindingInput,
  typeof CloseFindingResult
> {
  static actionVerb = 'Close';
  static displayName = 'Close Finding';

  async getInputType() {
    return CloseFindingInput;
  }

  protected async run(input: CloseFindingInput): Promise<CloseFindingResult> {
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
        'That result carries no finding, so there is nothing to close',
      );
    }
    if (finding.state === 'closed') {
      throw new Error(
        `${finding.findingId} is already closed as ${RESOLUTION_LABELS[finding.resolution?.code ?? ''] ?? 'closed'}. A closure is not re-recorded.`,
      );
    }

    let code = (input.code ?? '').trim();
    let closedBy = input.closedBy;
    // The finding's own link is read by reference: it may not have loaded on
    // a fetched card. The task is fetched either way, because a status that
    // never loaded reads undefined and would fail the done check.
    let actionId =
      input.correctiveAction?.id ??
      linkedId(result, finding, 'correctiveAction');
    let actionCard: Task | null = actionId
      ? ((await new GetCardCommand(this.commandContext).execute({
          cardId: actionId,
        })) as Task)
      : (input.correctiveAction ?? null);

    let gap = closureGap(
      {
        code,
        hasCorrectiveAction: Boolean(actionCard),
        correctiveActionDone: actionCard?.status === 'Done',
        acceptanceDecision: finding.riskAcceptance?.decision,
        closedById: closedBy?.id,
      },
      RESOLUTION_CODES,
    );
    if (gap) {
      throw new Error(gap);
    }

    let duty = checkDuty('close-finding', {
      actorId: closedBy!.id,
      raisedById: linkedId(result, finding, 'raisedBy'),
    });
    if (!duty.allowed) {
      throw new Error(`${duty.ruleId}: ${duty.reason}`);
    }
    let realm = (result as any)[realmURL]?.href;
    if (!realm) {
      throw new Error('Could not tell which realm the audit result is in');
    }

    let now = new Date();
    let note = (input.note ?? '').trim();
    // Arrays are replaced wholesale by a patch, so the existing annotations
    // are read back and rewritten with the new one appended. Read explicitly:
    // JSON.stringify on a field instance yields the shape with every value
    // null.
    let annotations = (finding.annotations ?? [])
      .filter(Boolean)
      .map(annotationToJSON);
    if (note) {
      annotations.push({
        anchor: `closure of ${finding.findingId}`,
        text: note,
        kind: 'note',
        createdAt: now.toISOString(),
      });
    }

    let relationships: Record<string, any> = {
      'finding.closedBy': { links: { self: closedBy!.id } },
      'meta.lastChangedBy': { links: { self: closedBy!.id } },
    };
    if (actionCard?.id) {
      relationships['finding.correctiveAction'] = {
        links: { self: actionCard.id },
      };
    }

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: AuditResult,
    }).execute({
      cardId: result.id,
      patch: {
        attributes: {
          finding: {
            state: 'closed',
            resolution: { code },
            closedAt: now.toISOString(),
            annotations,
          },
          meta: {
            lastChangedAt: now.toISOString(),
            changeCount: (result.meta?.changeCount ?? 0) + 1,
          },
        },
        relationships,
      },
    } as any);

    let label = RESOLUTION_LABELS[code] ?? code;
    await new SaveCardCommand(this.commandContext).execute({
      card: new AuditEntry({
        action: 'closed',
        occurredAt: now,
        doneBy: closedBy,
        subject: result,
        subjectTitle: result.cardTitle,
        note: `${finding.findingId} closed as ${label} by ${closedBy?.name ?? 'an auditor'}.${note ? ` ${note}` : ''}`,
      }),
      realm,
    } as any);

    return new CloseFindingResult({
      closed: true,
      findingId: finding.findingId,
      code,
      message: `${finding.findingId} closed as ${label}. ${duty.reason}`,
    } as any);
  }
}
