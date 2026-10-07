import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';

import { AuditorBot } from '@cardstack/catalog/cards/audit/auditor-bot';
import { Obligation } from '@cardstack/catalog/cards/legal/obligation';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import { readPath } from '@cardstack/catalog/cards/audit/utils/rule-evaluation';

/**
 * Schedule Obligations — turn the bot's expiry rules into recurring duties.
 *
 * A rule that says "reviewed within 365 days" is really a duty that falls due
 * every year, and it is the *duty* the people doing the work need to see. The
 * audit tells them they failed; the obligation is what would have stopped them
 * failing. So each expiry rule becomes an Obligation on the existing
 * obligations calendar, with the recurrence read off the rule's own window and
 * the first due date computed from when the subject was last in compliance —
 * not from today, which would quietly forgive a control that is already
 * overdue.
 *
 * **It writes obligations and nothing else.** Deliberately not folded into the
 * Audit command: an audit run must never mutate anybody's calendar as a side
 * effect, and the two records answer to different owners.
 *
 * Only `expiry` rules are eligible. A threshold or presence rule has no period
 * — it is either satisfied now or not — and inventing a review cadence for one
 * would be putting words in the regime's mouth.
 */
export class ScheduleObligationsInput extends CardDef {
  @field bot = linksTo(() => AuditorBot, { searchable: true });
  /** The subjects to schedule for. Required — an obligation needs an owner of the work. */
  @field subjects = linksToMany(CardDef);
  /** Who carries the duty. */
  @field owner = linksTo(() => Employee);
  /** Realm to write into. Defaults to the bot's own. */
  @field realm = contains(StringField);
}

export class ScheduleObligationsResult extends CardDef {
  @field created = contains(NumberField);
  @field skipped = contains(NumberField);
  @field lines = containsMany(StringField);
  @field message = contains(StringField);
}

/**
 * A review window expressed as a recurrence.
 *
 * Rounded to the nearest calendar unit the pattern field can express, because
 * "every 11.8 months" is not a thing anyone schedules. The window itself stays
 * on the obligation's description, so the rounding never hides the rule.
 */
export function recurrenceFor(maxAgeDays: number): {
  pattern: string;
  interval: number;
} {
  if (maxAgeDays >= 330) {
    return {
      pattern: 'yearly',
      interval: Math.max(1, Math.round(maxAgeDays / 365)),
    };
  }
  if (maxAgeDays >= 25) {
    return {
      pattern: 'monthly',
      interval: Math.max(1, Math.round(maxAgeDays / 30)),
    };
  }
  if (maxAgeDays >= 6) {
    return {
      pattern: 'weekly',
      interval: Math.max(1, Math.round(maxAgeDays / 7)),
    };
  }
  return { pattern: 'daily', interval: Math.max(1, maxAgeDays) };
}

function addDays(d: Date, days: number): Date {
  let out = new Date(d.getTime());
  out.setDate(out.getDate() + days);
  return out;
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function toDate(value: unknown): Date | undefined {
  if (value instanceof Date) {
    return isNaN(value.getTime()) ? undefined : value;
  }
  if (typeof value === 'string' && value.trim()) {
    let d = new Date(value);
    return isNaN(d.getTime()) ? undefined : d;
  }
  return undefined;
}

export default class ScheduleObligationsCommand extends Command<
  typeof ScheduleObligationsInput,
  typeof ScheduleObligationsResult
> {
  static actionVerb = 'Schedule';
  static displayName = 'Schedule Obligations';

  async getInputType() {
    return ScheduleObligationsInput;
  }

  protected async run(
    input: ScheduleObligationsInput,
  ): Promise<ScheduleObligationsResult> {
    let bot = input.bot;
    if (!bot) {
      throw new Error(
        'An auditor bot is required — its rules are what get scheduled',
      );
    }
    if (bot.id) {
      bot = (await new GetCardCommand(this.commandContext).execute({
        cardId: bot.id,
      })) as AuditorBot;
    }
    let subjects = (input.subjects ?? []).filter(Boolean) as CardDef[];
    if (!subjects.length) {
      throw new Error(
        'At least one subject is required — an obligation is somebody doing something about something',
      );
    }
    let realm =
      input.realm?.trim() ||
      (bot.id ? bot.id.slice(0, bot.id.lastIndexOf('/AuditorBot/') + 1) : '');
    if (!realm) {
      throw new Error('A realm is required to write into');
    }

    let expiryRules = (bot.rules ?? [])
      .filter(Boolean)
      .filter((r) => r.kind === 'expiry');
    if (!expiryRules.length) {
      throw new Error(
        `${bot.name ?? 'That bot'} has no expiry rules — only a rule with a review window becomes a recurring duty`,
      );
    }

    let now = new Date();
    let created: string[] = [];
    let skipped = 0;
    let lines: string[] = [];

    for (let rule of expiryRules) {
      let params: any = {};
      try {
        params = JSON.parse((rule.parameters ?? '{}').trim() || '{}');
      } catch {
        params = {};
      }
      let maxAgeDays = Number(params?.maxAgeDays);
      if (!Number.isFinite(maxAgeDays) || maxAgeDays <= 0) {
        // `mustBeFuture` is a deadline on a specific date, not a cadence — the
        // certificate expires when it expires and no recurrence describes it.
        skipped += 1;
        lines.push(
          `${rule.ruleId ?? '—'} · skipped · no review window (maxAgeDays) to repeat on`,
        );
        continue;
      }
      let recurrence = recurrenceFor(maxAgeDays);

      for (let subject of subjects) {
        let last = toDate(readPath(subject, rule.fieldPath));
        // From when the control was last satisfied, so an overdue duty reads
        // as overdue instead of being silently reset to a year from today.
        let due = last ? addDays(last, maxAgeDays) : addDays(now, maxAgeDays);
        let subjectName = (subject as any).cardTitle ?? subject.id ?? 'subject';

        let obligation = (await new SaveCardCommand(
          this.commandContext,
        ).execute({
          card: new Obligation({
            owner: input.owner,
            description: `${rule.statement ?? rule.ruleId ?? 'Control'} — ${subjectName}`,
          }),
          realm,
        } as any)) as Obligation;

        await new PatchCardInstanceCommand(this.commandContext, {
          cardType: Obligation,
        }).execute({
          cardId: obligation.id,
          patch: {
            attributes: {
              obligationType: 'compliance',
              firstDueDate: isoDate(due),
              recurrence: {
                pattern: recurrence.pattern,
                interval: recurrence.interval,
                startDate: isoDate(due),
              },
              consequence: rule.severityIfFailed?.level
                ? `A lapse is a ${rule.severityIfFailed.level} finding under ${rule.regime?.regime ?? 'the regime'}.`
                : null,
            },
          },
        } as any);

        created.push(obligation.id);
        lines.push(
          `${rule.ruleId ?? '—'} · ${subjectName} · due ${isoDate(due)} · every ${recurrence.interval} ${recurrence.pattern.replace('ly', '')}(s)${last ? '' : ' (no prior date on the subject; counted from today)'}`,
        );
      }
    }

    return new ScheduleObligationsResult({
      created: created.length,
      skipped,
      lines,
      message: `${created.length} obligation(s) scheduled from ${expiryRules.length - skipped} expiry rule(s) over ${subjects.length} subject(s)${skipped ? `, ${skipped} rule(s) skipped` : ''}`,
    } as any);
  }
}
