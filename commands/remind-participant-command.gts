import {
  CardDef,
  contains,
  containsMany,
  field,
  StringField,
} from '@cardstack/base/card-api';
import BooleanField from '@cardstack/base/boolean';
import NumberField from '@cardstack/base/number';
import DateTimeField from '@cardstack/base/datetime';
import { Command } from '@cardstack/runtime-common';

export class RemindParticipantInput extends CardDef {
  @field recipientRef = contains(StringField);
  @field about = contains(StringField, {
    description: 'What the reminder is about, in the recipient’s words.',
  });
  @field dueAt = contains(DateTimeField, {
    description: 'When the thing is due. A reminder without one is a nag.',
  });
  @field acknowledgedAt = contains(DateTimeField, {
    description: 'When the recipient acted. Set means: stop reminding.',
  });
  @field completedAt = contains(DateTimeField);

  // Hours before `dueAt` at which to remind. A schedule, not a frequency —
  // see the readMe on why an interval is the wrong model.
  @field offsetsHoursBefore = containsMany(NumberField);
  @field sentOffsets = containsMany(NumberField, {
    description: 'Offsets already sent, so a re-run does not repeat one.',
  });

  @field asOf = contains(DateTimeField);
  @field quietHoursStart = contains(NumberField, {
    description: 'Local hour, 0–23, after which not to send. Blank disables.',
  });
  @field quietHoursEnd = contains(NumberField);
  @field maxReminders = contains(NumberField, {
    description: 'Hard ceiling regardless of schedule. Defaults to 5.',
  });
}

export class RemindParticipantResult extends CardDef {
  @field shouldSend = contains(BooleanField);
  @field offset = contains(NumberField, {
    description: 'Which scheduled offset is due now.',
  });
  @field reason = contains(StringField);
  @field nextDueAt = contains(DateTimeField, {
    description: 'When the next reminder would fire, if any.',
  });
  @field isEscalation = contains(BooleanField, {
    description: 'True once the due date has passed.',
  });
}

const DEFAULT_MAX = 5;

/**
 * Decide whether to nudge someone about something, right now.
 *
 * ### It decides; it does not send
 *
 * The send is `NotifyParticipantCommand`'s job, which already owns dedupe,
 * consent and channel. Putting the schedule in a second sender would give the
 * system two places that can produce a message and two dedupe stories.
 *
 * ### A schedule of offsets, not an interval
 *
 * "Every 3 days" is the wrong model for a reminder. What people actually
 * want is *a week before, a day before, and again when it is late* — the
 * spacing tightens as the deadline approaches, which no fixed interval does.
 *
 * So `offsetsHoursBefore` is a list, negative values meaning *after* the due
 * date. `[168, 24, -24]` is: one week before, one day before, one day late.
 *
 * ### Acknowledgement stops everything, immediately
 *
 * `acknowledgedAt` is checked before the schedule. Someone who has already
 * acted and still gets reminded learns the reminders are not worth reading,
 * which breaks every future reminder too — the cost of one wrong nudge is
 * not one wrong nudge.
 *
 * ### Quiet hours shift, they do not skip
 *
 * A reminder that falls inside quiet hours is **deferred to the end of the
 * window**, not dropped. Dropping it loses the only notice the person was
 * going to get; a 3am alert they see at 8am is still the notice.
 *
 * ### `maxReminders` is a hard ceiling
 *
 * Independent of the schedule, because a schedule can be edited into
 * something abusive and a ceiling cannot be reasoned around.
 */
export class RemindParticipantCommand extends Command<
  typeof RemindParticipantInput,
  typeof RemindParticipantResult
> {
  static actionVerb = 'Remind';
  static displayName = 'Remind Participant';

  async getInputType() {
    return RemindParticipantInput;
  }

  protected async run(
    input: RemindParticipantInput,
  ): Promise<RemindParticipantResult> {
    let now = input.asOf ? new Date(input.asOf) : new Date();

    if (input.acknowledgedAt || input.completedAt) {
      return new RemindParticipantResult({
        shouldSend: false,
        reason:
          'Already acknowledged or completed. Reminding someone who has acted teaches them to ignore reminders.',
      });
    }

    if (!input.dueAt) {
      return new RemindParticipantResult({
        shouldSend: false,
        reason:
          'No due date. A reminder without one has nothing to count down to — that is a nag, not a reminder.',
      });
    }

    let due = new Date(input.dueAt).getTime();
    let sent = new Set(input.sentOffsets ?? []);
    let max = input.maxReminders ?? DEFAULT_MAX;

    if (sent.size >= max) {
      return new RemindParticipantResult({
        shouldSend: false,
        reason: `Ceiling reached — ${sent.size} of ${max} reminders already sent.`,
      });
    }

    // Largest offset first: a week before fires before a day before.
    let schedule = [...(input.offsetsHoursBefore ?? [])].sort((a, b) => b - a);
    if (!schedule.length) {
      return new RemindParticipantResult({
        shouldSend: false,
        reason: 'No reminder schedule set.',
      });
    }

    let dueOffset: number | undefined;
    let nextDueAt: Date | undefined;
    for (let off of schedule) {
      let fireAt = due - off * 3600000;
      if (sent.has(off)) {
        continue;
      }
      if (fireAt <= now.getTime()) {
        dueOffset = off;
        break;
      }
      if (!nextDueAt) {
        nextDueAt = new Date(fireAt);
      }
    }

    if (dueOffset == null) {
      return new RemindParticipantResult({
        shouldSend: false,
        nextDueAt,
        reason: nextDueAt
          ? `Nothing due yet. Next reminder at ${nextDueAt.toISOString()}.`
          : 'Every scheduled reminder has been sent.',
      });
    }

    // Quiet hours defer rather than drop.
    let qs = input.quietHoursStart;
    let qe = input.quietHoursEnd;
    if (qs != null && qe != null) {
      let h = now.getHours();
      let inQuiet = qs <= qe ? h >= qs && h < qe : h >= qs || h < qe;
      if (inQuiet) {
        let deferred = new Date(now);
        deferred.setHours(qe, 0, 0, 0);
        if (deferred <= now) {
          deferred.setDate(deferred.getDate() + 1);
        }
        return new RemindParticipantResult({
          shouldSend: false,
          offset: dueOffset,
          nextDueAt: deferred,
          reason: `Inside quiet hours. Deferred to ${deferred.toISOString()} — not dropped, because this may be the only notice they get.`,
        });
      }
    }

    let isEscalation = now.getTime() > due;
    return new RemindParticipantResult({
      shouldSend: true,
      offset: dueOffset,
      isEscalation,
      nextDueAt,
      reason: isEscalation
        ? `Overdue by ${Math.round((now.getTime() - due) / 3600000)}h — escalation reminder.`
        : `Due in ${dueOffset}h. Reminder ${sent.size + 1} of at most ${max}.`,
    });
  }
}

export default RemindParticipantCommand;
