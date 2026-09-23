import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import TextAreaField from '@cardstack/base/text-area';
import { Command } from '@cardstack/runtime-common';
import { loaded } from '../record-helpers';
import { displayTitle } from '../record-helpers';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { Escalation, ESCALATION_REASONS } from '../escalation';
import {
  ESCALATION_LEVELS,
  EscalationLevelField,
  levelRank,
} from '@cardstack/catalog/fields/escalation-level/escalation-level-field';
import { Role } from '../role';
import AssignOwnerCommand from './assign-owner-command';

export class EscalateCaseInput extends CardDef {
  @field subject = linksTo(CardDef, { searchable: true });
  /** The subject's latest Escalation; the current rung is read from it. */
  @field current = linksTo(() => Escalation);
  @field fromLevelKey = contains(StringField, {
    description:
      'Current rung when there is no earlier Escalation: L1 | L2 | L3 | exec.',
  });
  @field toLevelKey = contains(StringField);
  @field reason = contains(StringField, {
    description:
      'sla-risk | customer-request | agent-request | breach | policy',
  });
  @field note = contains(TextAreaField);
  @field raisedBy = linksTo(() => Employee, {
    description: 'The accountable human. A policy firing still names one.',
  });
  @field raisedByPolicy = contains(StringField, {
    description: 'Policy name when automation raised it — always attributed.',
  });
  @field targetRole = linksTo(() => Role, {
    description:
      "The receiving level's role; its onDuty member takes ownership.",
  });
  @field ackTargetMinutes = contains(StringField, {
    description:
      'Ack clock for the receiving level, minutes (string-typed for patch friendliness).',
  });
  @field override = contains(BooleanField, {
    description: 'Required to skip more than one rung; must come with a note.',
  });
  @field realm = contains(StringField, {
    description: 'Realm URL to create the Escalation in.',
  });
}

export class EscalateCaseResult extends CardDef {
  @field message = contains(StringField);
  @field escalation = linksTo(() => Escalation);
}

/**
 * Climb the ladder, as a record. Creates an `Escalation` with its ack clock,
 * moves ownership toward the receiving role's on-duty member (through Assign
 * Owner — the single writer of ownership), and refuses a jump of more than
 * one rung without `override: true` + a note.
 *
 * DIVISION OF LABOUR with the ServiceDesk's `escalate-ticket`: that command
 * moves a TICKET's priority/assignee inside the agent kit; this one owns the
 * LADDER — the escalation record, ack clocks, level ranks. Both readMes
 * cross-reference this split so nobody builds a third.
 */
export default class EscalateCaseCommand extends Command<
  typeof EscalateCaseInput,
  typeof EscalateCaseResult
> {
  static actionVerb = 'Escalate';
  static displayName = 'Escalate Case';

  async getInputType() {
    return EscalateCaseInput;
  }

  protected async run(input: EscalateCaseInput): Promise<EscalateCaseResult> {
    let subject = await loaded(this.commandContext, input.subject);
    if (!subject) {
      throw new Error('subject is required');
    }
    // The rung comes from the record, not the caller: with an earlier
    // Escalation, its `toLevel` is where the subject is now, so a caller cannot
    // claim a higher starting rung to skip one.
    let current = input.current
      ? await loaded(this.commandContext, input.current)
      : undefined;
    let from = current?.toLevel?.key || input.fromLevelKey || 'L1';
    if (current && input.fromLevelKey && input.fromLevelKey !== from) {
      throw new Error(
        `The subject is at ${from} (its latest escalation), not ${input.fromLevelKey}.`,
      );
    }
    let to = input.toLevelKey;
    if (!to || !ESCALATION_LEVELS.includes(to as any)) {
      throw new Error(
        `toLevelKey must be one of: ${ESCALATION_LEVELS.join(', ')}`,
      );
    }
    if (levelRank(to) <= levelRank(from)) {
      throw new Error(
        `Cannot escalate downward or sideways (${from} → ${to}).`,
      );
    }
    if (levelRank(to) - levelRank(from) > 1 && !input.override) {
      throw new Error(
        `Skipping a rung (${from} → ${to}) needs override: true and a note saying why.`,
      );
    }
    if (input.override && !input.note?.trim()) {
      throw new Error('An override must carry a note saying why.');
    }
    let reason = input.reason || 'agent-request';
    if (!ESCALATION_REASONS.includes(reason as any)) {
      throw new Error(
        `reason must be one of: ${ESCALATION_REASONS.join(', ')}`,
      );
    }
    if (!input.realm) {
      throw new Error('realm is required to create the Escalation record');
    }

    let role = input.targetRole
      ? await loaded(this.commandContext, input.targetRole)
      : undefined;
    let raisedByName = input.raisedByPolicy
      ? `policy “${input.raisedByPolicy}”`
      : ((input.raisedBy?.title as string) ?? 'unknown');

    let ackTarget = input.ackTargetMinutes
      ? Number(input.ackTargetMinutes)
      : undefined;

    let escalation = new Escalation({
      subject,
      fromLevel: new EscalationLevelField({ key: from } as any),
      toLevel: new EscalationLevelField({
        key: to,
        targetRoleName: (role?.name as string) ?? undefined,
        ackTargetMinutes: Number.isFinite(ackTarget) ? ackTarget : undefined,
      } as any),
      reason,
      note: input.note ?? undefined,
      raisedByName,
      raisedAt: new Date(),
      status: 'open',
    } as any);
    await new SaveCardCommand(this.commandContext).execute({
      card: escalation,
      realm: input.realm,
    } as any);

    // Ownership follows the ladder: the receiving role's on-duty member.
    let newOwner = role?.onDuty;
    if (newOwner?.id && (subject as any).ownership) {
      await new AssignOwnerCommand(this.commandContext).execute({
        card: subject,
        owner: newOwner,
        strategy: 'escalation',
      } as any);
    }

    return new EscalateCaseResult({
      escalation,
      message: `${displayTitle(subject, 'Record')} escalated ${from} → ${to} (${reason})${
        newOwner ? `; owner now ${newOwner.title}` : ''
      }${ackTarget ? `; ack due in ${ackTarget}m` : ''}.`,
    });
  }
}
