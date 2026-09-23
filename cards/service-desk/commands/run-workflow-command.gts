import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import { Command } from '@cardstack/runtime-common';
import { loaded } from '../record-helpers';
import { displayTitle } from '../record-helpers';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';

import { Workflow } from '../workflow';
import { Sla, PauseIntervalField } from '../sla';
import { WorkflowStateField } from '@cardstack/catalog/fields/workflow-state/workflow-state-field';

export class RunWorkflowInput extends CardDef {
  @field card = linksTo(CardDef, {
    searchable: true,
    description:
      'Any card carrying `@field workflowState = contains(WorkflowStateField)`.',
  });
  @field workflow = linksTo(() => Workflow);
  @field toStateKey = contains(StringField);
  @field note = contains(TextAreaField, {
    description: 'Required when the transition guard is requires-note.',
  });
  @field actorName = contains(StringField);
  @field actorRoleNames = contains(StringField, {
    description:
      'Comma-separated role names the actor holds — checked against a requires-role guard. Caller-supplied: the platform has no current-user concept.',
  });
  @field sla = linksTo(() => Sla, {
    description:
      "The record's applied SLA, if any: entering a pausing state stops its clocks; leaving one resumes them with the deadline pushed out by the pause.",
  });
}

export class RunWorkflowResult extends CardDef {
  @field message = contains(StringField);
}

/**
 * THE single writer of workflow state.
 *
 * Validates the move against the Workflow card (states + transitions are
 * DATA an ops lead edits), enforces the guard, writes the new
 * `workflowState`, and keeps the SLA honest: a `waiting` state
 * (`pausesSlaClock`) stamps `pausedSince` + opens a pause interval on the
 * linked SLA's clocks; leaving it closes the interval and pushes every
 * running `deadlineAt` out by the pause length (the ServiceDesk convention —
 * pausing stops the number getting worse, it never un-breaches).
 *
 * A refusal names the rule AND the fixing action — never a bare "can't".
 */
export default class RunWorkflowCommand extends Command<
  typeof RunWorkflowInput,
  typeof RunWorkflowResult
> {
  static actionVerb = 'Move';
  static displayName = 'Run Workflow';

  async getInputType() {
    return RunWorkflowInput;
  }

  protected async run(input: RunWorkflowInput): Promise<RunWorkflowResult> {
    let card = await loaded(this.commandContext, input.card);
    if (!card) {
      throw new Error('card is required');
    }
    let workflow = await loaded(this.commandContext, input.workflow);
    if (!workflow) {
      throw new Error('workflow is required');
    }
    let current = (card as any).workflowState;
    if (current === undefined) {
      throw new Error(
        `${displayTitle(card, 'This card')} has no workflowState field — add "@field workflowState = contains(WorkflowStateField)" before running a workflow on it.`,
      );
    }
    let fromKey = current?.key as string | undefined;
    let toKey = input.toStateKey;
    // Plain lookups over the fields, not prototype methods — a card that
    // crossed a command boundary may not carry its class methods.
    let states = ((workflow as any).states ?? []) as any[];
    let transitions = ((workflow as any).transitions ?? []) as any[];
    let toState = states.find((st) => st?.key === toKey);
    if (!toState) {
      throw new Error(
        `"${toKey}" is not a state of ${workflow.title}. States: ${states
          .map((st) => st?.key)
          .join(', ')}`,
      );
    }
    if (fromKey === toKey) {
      return new RunWorkflowResult({
        message: `${displayTitle(card, 'Record')} is already in ${toKey}.`,
      });
    }
    let transition = fromKey
      ? transitions.find((t) => t?.from === fromKey && t?.to === toKey)
      : undefined;
    if (fromKey && !transition) {
      throw new Error(
        `${workflow.title} does not allow ${fromKey} → ${toKey}. Allowed from ${fromKey}: ${
          transitions
            .filter((t) => t?.from === fromKey)
            .map((t) => t?.to)
            .join(', ') || '(none)'
        }`,
      );
    }
    let guard = transition?.guard;
    if (guard === 'requires-note' && !input.note?.trim()) {
      throw new Error(
        `${fromKey} → ${toKey} needs a note — add one saying why this record is ready.`,
      );
    }
    if (guard === 'requires-role') {
      let need = transition?.guardRoleName;
      let held = (input.actorRoleNames ?? '')
        .split(',')
        .map((r) => r.trim())
        .filter(Boolean);
      if (need && !held.includes(need)) {
        throw new Error(
          `${fromKey} → ${toKey} requires the ${need} role; the actor holds: ${held.join(', ') || '(none stated)'}.`,
        );
      }
    }

    let wasPausing = Boolean(current?.pausesSlaClock);
    let willPause = Boolean(toState.pausesSlaClock);

    // Write the state (copy the workflow's own definition of it).
    (card as any).workflowState = new WorkflowStateField({
      key: toState.key,
      label: toState.label,
      kind: toState.kind,
      pausesSlaClock: toState.pausesSlaClock,
    } as any);
    await new SaveCardCommand(this.commandContext).execute({ card } as any);

    // Keep the linked SLA honest across the pause boundary.
    let clockNote = '';
    if (input.sla?.id && wasPausing !== willPause) {
      let sla = await loaded(this.commandContext, input.sla);
      let now = new Date();
      if (willPause) {
        for (let timer of (sla as any).timers ?? []) {
          if (!timer.satisfiedAt && !timer.pausedSince) {
            timer.pausedSince = now;
          }
        }
        let pauses = [...((sla as any).pauses ?? [])];
        pauses.push(
          new PauseIntervalField({ pausedAt: now, reason: toState.key } as any),
        );
        (sla as any).pauses = pauses;
        clockNote = '; clocks paused';
      } else {
        let pauses = [...((sla as any).pauses ?? [])];
        let open = pauses.find((p: any) => p.pausedAt && !p.resumedAt);
        let pausedMs = 0;
        if (open) {
          open.resumedAt = now;
          pausedMs =
            now.getTime() -
            new Date(open.pausedAt as unknown as string).getTime();
        }
        (sla as any).pauses = pauses;
        for (let timer of (sla as any).timers ?? []) {
          if (!timer.satisfiedAt && timer.pausedSince) {
            if (timer.deadlineAt && pausedMs > 0) {
              timer.deadlineAt = new Date(
                new Date(timer.deadlineAt as unknown as string).getTime() +
                  pausedMs,
              );
            }
            timer.pausedSince = undefined;
          }
        }
        clockNote = '; clocks resumed';
      }
      await new SaveCardCommand(this.commandContext).execute({
        card: sla,
      } as any);
    }

    return new RunWorkflowResult({
      message: `${displayTitle(card, 'Record')}: ${fromKey ?? '(none)'} → ${toKey}${
        input.actorName ? ` by ${input.actorName}` : ''
      }${clockNote}.`,
    });
  }
}
