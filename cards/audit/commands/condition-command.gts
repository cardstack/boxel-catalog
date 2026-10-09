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

import { ValidationRuleField } from '@cardstack/catalog/cards/audit/validation-rule-field';
import { AuditorBot } from '@cardstack/catalog/cards/audit/auditor-bot';
import { evaluateRule } from '@cardstack/catalog/cards/audit/utils/rule-evaluation';

/**
 * Condition — evaluate ONE rule against ONE subject and say what was seen.
 *
 * Pure: it writes nothing, anywhere. That is what makes it safe to call from
 * a preview, a report, a badge and the Audit command without any of them
 * having to worry about side effects, and it is why a result is always
 * recomputed rather than cached — a rule's verdict is only true as of the
 * data it just read.
 *
 * The verdict logic lives in `utils/rule-evaluation`, shared with Policy and
 * with the future Audit command, so no two surfaces can disagree about what
 * "pass" means.
 */
export class ConditionInput extends CardDef {
  /** The rule itself, when the caller already holds one. */
  @field rule = contains(ValidationRuleField);
  /**
   * Or name a rule that already exists: a bot plus a ruleId.
   *
   * A compound field cannot be expressed in the JSON an assistant or the CLI
   * passes, so a command reachable only through an inline field is a command
   * only other code can call. By-reference keeps it usable as a tool.
   */
  @field bot = linksTo(() => AuditorBot, { searchable: true });
  @field ruleId = contains(StringField);
  @field subject = linksTo(CardDef, { searchable: true });
  /**
   * Whether the caller has proof to show. The engine cannot see attachments,
   * so a rule marked `evidenceRequired` returns `unproven` unless told.
   */
  @field hasEvidence = contains(BooleanField);
}

export class ConditionResult extends CardDef {
  /**
   * The status VALUE, not an Evaluation Status field.
   *
   * A command result is a readout the caller renders, not a record it saves,
   * and a compound field cannot be constructed into one — the host's field
   * validator rejects both a plain object and a hand-built field instance.
   * Consumers that want the pill wrap this string in the field themselves.
   */
  @field status = contains(StringField);
  /** What the engine actually read, rendered for a human. */
  @field observed = contains(StringField);
  /** One sentence: why this verdict. */
  @field reason = contains(StringField);
  @field conclusive = contains(BooleanField);
  @field message = contains(StringField);
}

export default class ConditionCommand extends Command<
  typeof ConditionInput,
  typeof ConditionResult
> {
  static actionVerb = 'Evaluate';
  static displayName = 'Condition';

  async getInputType() {
    return ConditionInput;
  }

  protected async run(input: ConditionInput): Promise<ConditionResult> {
    let { subject, hasEvidence, ruleId } = input;
    let rule: ValidationRuleField | undefined = input.rule;
    let bot = input.bot;
    if (!subject) {
      throw new Error('A subject is required');
    }
    if (!rule?.fieldPath && bot) {
      if (bot.id) {
        bot = (await new GetCardCommand(this.commandContext).execute({
          cardId: bot.id,
        })) as AuditorBot;
      }
      let wanted = (ruleId ?? '').trim();
      rule = (bot?.rules ?? []).find((r) =>
        wanted ? r?.ruleId === wanted : true,
      );
      if (!rule) {
        throw new Error(
          wanted
            ? `No rule "${wanted}" on ${bot?.name ?? 'that bot'}`
            : 'That bot has no rules',
        );
      }
    }
    if (!rule) {
      throw new Error(
        'A validation rule is required (inline, or bot + ruleId)',
      );
    }
    // Never trust the caller's load state: a rule may point through a link
    // the caller never loaded, and an unloaded link reads exactly like an
    // empty one.
    if (subject.id) {
      subject = (await new GetCardCommand(this.commandContext).execute({
        cardId: subject.id,
      })) as CardDef;
    }

    let outcome = evaluateRule(rule, subject, {
      hasEvidence: Boolean(hasEvidence),
    });
    let conclusive = ['pass', 'fail', 'partial', 'not-applicable'].includes(
      outcome.status,
    );

    return new ConditionResult({
      status: outcome.status,
      observed: outcome.observed,
      reason: outcome.reason,
      conclusive,
      message: `${rule.ruleId ?? 'Rule'}: ${outcome.status} — ${outcome.reason}`,
    } as any);
  }
}
