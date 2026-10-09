import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import {
  DUTY_ACTIONS,
  DUTY_ACTION_LABELS,
  DUTY_RULES,
  checkDuty,
  isDutyAction,
  type DutyContext,
} from '../utils/duty-separation';

/**
 * Permission — may this actor perform this act on this record?
 *
 * **A pure check. It writes nothing and it is not access control.** Realm
 * write permission is the security boundary; this answers the separation-of-
 * duties question that sits on top of it, and it is enforced inside the
 * commands that write, where nothing can route around it.
 *
 * **The actor is an argument, and that is the design.** The check tests the
 * actor recorded on the record — `raisedBy`, `evaluatedBy`, an approver on the
 * chain — so it reproduces months later from the record alone. Reading an
 * ambient current user would make the same finding answer differently
 * depending on who had the app open, which is the opposite of what an audit
 * trail is for. The consequence to state plainly: the actor is asserted by the
 * caller, not authenticated.
 *
 * `action` is a plain string rather than an enum field because a command input
 * cannot hold a compound field — the host's validator rejects the JSON an
 * assistant or the CLI passes. It is validated against the vocabulary here.
 */
export class PermissionInput extends CardDef {
  @field actor = linksTo(() => Employee, { searchable: true });
  /** One of `close-finding`, `accept-risk`, `sign-off`. */
  @field action = contains(StringField);
  /** The Audit Result carrying the finding, or the Report being signed. */
  @field target = linksTo(CardDef, { searchable: true });
}

export class PermissionResult extends CardDef {
  @field allowed = contains(BooleanField);
  /** The rule that decided it — "SOD-01" — or empty when nothing barred it. */
  @field ruleId = contains(StringField);
  /** That rule in a sentence, so a refusal can be shown without a lookup. */
  @field rule = contains(StringField);
  @field reason = contains(StringField);
  @field message = contains(StringField);
}

/**
 * Read the duty context off whichever record was passed.
 *
 * Structural rather than type-switched: a result, a report and a card that
 * merely carries a finding all answer the same question, and the standards
 * evaluator will pass a fourth shape. What matters is which ids are on it.
 */
function contextOf(target: any, actorId?: string | null): DutyContext {
  let steps = (target?.signOff?.steps ?? []).filter(Boolean);
  let results = (target?.results ?? []).filter(Boolean);
  return {
    actorId,
    raisedById: target?.finding?.raisedBy?.id ?? null,
    ranById: target?.evaluatedBy?.id ?? results[0]?.evaluatedBy?.id ?? null,
    approverIds: steps.map((s: any) => s?.approver?.id ?? null),
  };
}

export default class PermissionCommand extends Command<
  typeof PermissionInput,
  typeof PermissionResult
> {
  static actionVerb = 'Check';
  static displayName = 'Permission';

  async getInputType() {
    return PermissionInput;
  }

  protected async run(input: PermissionInput): Promise<PermissionResult> {
    let action = (input.action ?? '').trim();
    if (!isDutyAction(action)) {
      throw new Error(
        `"${action || '(none)'}" is not a duty-separated action. Use one of: ${DUTY_ACTIONS.join(', ')}`,
      );
    }
    let target = input.target;
    if (!target) {
      throw new Error(
        'A target record is required — a duty is always about something',
      );
    }
    if (target.id) {
      target = (await new GetCardCommand(this.commandContext).execute({
        cardId: target.id,
      })) as CardDef;
    }

    let verdict = checkDuty(action, contextOf(target, input.actor?.id));
    let actorName = input.actor?.name ?? 'An unnamed actor';
    let act = DUTY_ACTION_LABELS[action] ?? action;

    return new PermissionResult({
      allowed: verdict.allowed,
      ruleId: verdict.ruleId ?? '',
      rule: verdict.ruleId ? (DUTY_RULES[verdict.ruleId] ?? '') : '',
      reason: verdict.reason,
      message: verdict.allowed
        ? `Allowed — ${actorName} may ${act.toLowerCase()}. ${verdict.reason}`
        : `Denied by ${verdict.ruleId} — ${verdict.reason}`,
    } as any);
  }
}
