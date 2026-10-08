import {
  CardDef,
  contains,
  field,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import { Command } from '@cardstack/runtime-common';

import { SlaWindowField } from '@cardstack/catalog/fields/sla-window/sla-window-field';
import {
  addBusinessMinutes,
  ALWAYS_ON,
  formatMinutes,
} from '@cardstack/catalog/cards/service-desk/utils/sla';

export class ComputeSlaDeadlineInput extends CardDef {
  @field startedAt = contains(DateTimeField, {
    description: 'The instant the clock starts.',
  });
  @field targetMinutes = contains(NumberField, {
    description: 'The promised target, in business minutes.',
  });
  @field window = contains(SlaWindowField, {
    description:
      'Business hours the clock runs in. Omit (or leave windows empty) for an always-on 24/7 clock.',
  });
  @field alreadyPausedMinutes = contains(NumberField, {
    description:
      'Wall-clock minutes already spent paused — the deadline is pushed out by exactly this much.',
  });
}

export class ComputeSlaDeadlineResult extends CardDef {
  @field deadlineAt = contains(DateTimeField);
  @field explanation = contains(StringField);
}

/**
 * THE single source of SLA clock math for the desk. PURE — reads its input,
 * writes nothing, so the SLA card's computeds, the queue's sort and the
 * command center can call the same arithmetic and never disagree.
 *
 * All the calendar work is `utils/sla.ts` (`addBusinessMinutes`): DST-safe
 * (wall-clock parts are read back out of Intl in the window's own zone),
 * weekend/holiday-aware, and shared verbatim with the ServiceDesk's
 * apply-sla-policy command — one implementation, two consumers.
 *
 * The rule this command carries beyond the util: PAUSES are wall-clock, not
 * business-time. A clock paused for 17 hours resumes with its deadline pushed
 * out 17 wall hours (the ServiceDesk convention — the resume command pushes
 * `deadlineAt` out by however long the pause lasted), so `alreadyPausedMinutes`
 * is applied after the business-hours deadline is found.
 */
export default class ComputeSlaDeadlineCommand extends Command<
  typeof ComputeSlaDeadlineInput,
  typeof ComputeSlaDeadlineResult
> {
  static actionVerb = 'Compute';
  static displayName = 'Compute SLA Deadline';

  async getInputType() {
    return ComputeSlaDeadlineInput;
  }

  protected async run(
    input: ComputeSlaDeadlineInput,
  ): Promise<ComputeSlaDeadlineResult> {
    if (!input.startedAt) {
      throw new Error('startedAt is required');
    }
    let target = input.targetMinutes;
    if (typeof target !== 'number' || !Number.isFinite(target) || target <= 0) {
      throw new Error('targetMinutes must be a positive number');
    }
    let start = new Date(input.startedAt as unknown as string);
    let schedule = input.window?.businessSchedule ?? ALWAYS_ON;
    let deadline = addBusinessMinutes(start, target, schedule);
    let paused = input.alreadyPausedMinutes ?? 0;
    if (paused > 0) {
      deadline = new Date(deadline.getTime() + paused * 60000);
    }
    let windowLabel =
      schedule === ALWAYS_ON
        ? 'always-on (24/7)'
        : `${schedule.windows.length} windows in ${schedule.timeZone}`;
    return new ComputeSlaDeadlineResult({
      deadlineAt: deadline,
      explanation: `${formatMinutes(target)} of business time from ${start.toISOString()} under ${windowLabel}${
        paused > 0 ? `, plus ${formatMinutes(paused)} of pause` : ''
      } → ${deadline.toISOString()}`,
    });
  }
}
