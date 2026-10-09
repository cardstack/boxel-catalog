import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import NumberField from '@cardstack/base/number';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';

import { ValidationRuleField } from '@cardstack/catalog/cards/audit/validation-rule-field';
import { AuditorBot } from '@cardstack/catalog/cards/audit/auditor-bot';
import {
  evaluateRule,
  tally,
  rollup,
  coverage,
  type RuleOutcome,
} from '@cardstack/catalog/cards/audit/utils/rule-evaluation';

/**
 * Policy — run a whole rule-set against one subject and roll the answers up.
 *
 * Pure, like Condition: nothing is written. A report persists results; this
 * only computes them, which is what lets a workspace preview a subject's
 * standing without dirtying an audit.
 *
 * Rules come either from an Auditor Bot (the configured set) or inline. The
 * roll-up is deliberately pessimistic — any failure is non-compliant, and an
 * unproven or unfireable rule makes the whole subject `partial` rather than
 * `pass`. A verdict must never be more confident than the parts it is made of.
 */
export class PolicyInput extends CardDef {
  @field subject = linksTo(CardDef, { searchable: true });
  /** Preferred: the configured rule-set. */
  @field bot = linksTo(() => AuditorBot, { searchable: true });
  /** Used when no bot is given. */
  @field rules = containsMany(ValidationRuleField);
}

export class PolicyResult extends CardDef {
  /** The roll-up status VALUE — see ConditionResult on why this is a string. */
  @field rollup = contains(StringField);
  @field ruleCount = contains(NumberField);
  @field passed = contains(NumberField);
  @field failed = contains(NumberField);
  @field unproven = contains(NumberField);
  @field notApplicable = contains(NumberField);
  @field pending = contains(NumberField);
  /** Conclusive verdicts over rules that applied, as a percentage. */
  @field coverage = contains(NumberField);
  /** One line per rule, in rule order. */
  @field results = containsMany(StringField);
  @field message = contains(StringField);
}

export default class PolicyCommand extends Command<
  typeof PolicyInput,
  typeof PolicyResult
> {
  static actionVerb = 'Evaluate policy';
  static displayName = 'Policy';

  async getInputType() {
    return PolicyInput;
  }

  protected async run(input: PolicyInput): Promise<PolicyResult> {
    let { subject, bot } = input;
    if (!subject) {
      throw new Error('A subject is required');
    }
    if (subject.id) {
      subject = (await new GetCardCommand(this.commandContext).execute({
        cardId: subject.id,
      })) as CardDef;
    }
    if (bot?.id) {
      bot = (await new GetCardCommand(this.commandContext).execute({
        cardId: bot.id,
      })) as AuditorBot;
    }

    let rules = (bot?.rules?.length ? bot.rules : input.rules) ?? [];
    if (!rules.length) {
      throw new Error(
        'No rules to evaluate — pass an Auditor Bot with rules, or rules inline',
      );
    }

    let outcomes: RuleOutcome[] = [];
    let lines: string[] = [];
    for (let rule of rules) {
      let outcome = evaluateRule(rule, subject);
      outcomes.push(outcome);
      lines.push(
        `${rule.ruleId ?? '—'} · ${outcome.status} · ${outcome.observed} · ${outcome.reason}`,
      );
    }

    let counts = tally(outcomes);
    let verdict = rollup(counts);

    return new PolicyResult({
      rollup: verdict,
      ruleCount: rules.length,
      passed: counts.pass,
      failed: counts.fail,
      unproven: counts.unproven,
      notApplicable: counts.notApplicable,
      pending: counts.pending,
      coverage: coverage(counts),
      results: lines,
      message: `${verdict} — ${counts.pass} passed, ${counts.fail} failed, ${counts.unproven} unproven of ${rules.length} rule(s)`,
    } as any);
  }
}
