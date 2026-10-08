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
import DateField from '@cardstack/base/date';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import SaveCardCommand from '@cardstack/boxel-host/commands/save-card';
import PatchCardInstanceCommand from '@cardstack/boxel-host/commands/patch-card-instance';
import { SearchCardsByQueryCommand } from '@cardstack/boxel-host/commands/search-cards';

import { AuditorBot } from '@cardstack/catalog/cards/audit/auditor-bot';
import { AuditResult } from '@cardstack/catalog/cards/audit/audit-result';
import { StandardEvaluationReport } from '../standard-evaluation-report';
import { AuditEntry } from '../audit-entry';
import { Employee } from '@cardstack/catalog/cards/hr/employee';
import {
  evaluateRule,
  tally,
  rollup,
  coverage,
  type RuleOutcome,
} from '@cardstack/catalog/cards/audit/utils/rule-evaluation';

/**
 * Audit — run a bot's rules over its subjects and write the record.
 *
 * **The single writer.** Every Audit Result and every Finding in the realm is
 * created here, which is what makes the rest of the model safe: a result can
 * never disagree with the rule that produced it, because nothing else is
 * allowed to write one. Condition and Policy compute the same verdicts and
 * deliberately write nothing.
 *
 * Recurrence is the reason this command searches before it writes. The same
 * rule failing the same subject two periods running is a systemic gap rather
 * than an incident, and it is invisible unless someone looks for the earlier
 * finding at the moment the new one is raised.
 *
 * Compound values are patched after save, never constructed into the card —
 * the host's field validator rejects a hand-built field instance, so a bare
 * card is saved first and its rule, status, finding and metadata go on as
 * JSON.
 */
export class AuditInput extends CardDef {
  @field bot = linksTo(() => AuditorBot, { searchable: true });
  /**
   * The period as two plain dates rather than a Date Range field.
   *
   * A command input cannot hold a compound field: the host's validator
   * rejects the plain JSON an assistant or the CLI passes, so an input built
   * from compound fields is callable only from other code. Scalars in, the
   * range assembled onto the report as JSON.
   */
  @field periodStart = contains(DateField);
  @field periodEnd = contains(DateField);
  @field reportTitle = contains(StringField);
  /** Realm to write into. Defaults to the bot's own realm. */
  @field realm = contains(StringField);
  /**
   * The subjects to evaluate. Supply them when the caller already has them;
   * otherwise the bot's `subjectQuery` is run.
   */
  @field subjects = linksToMany(CardDef);
  /** Who ran it. A bot never signs off, so a name is recorded against the run. */
  @field ranBy = linksTo(() => Employee);
}

export class AuditResultSummary extends CardDef {
  @field line = contains(StringField);
}

export class AuditRunResult extends CardDef {
  @field report = linksTo(() => StandardEvaluationReport);
  @field subjectsEvaluated = contains(NumberField);
  @field resultsWritten = contains(NumberField);
  @field findingsRaised = contains(NumberField);
  @field recurrences = contains(NumberField);
  @field rollup = contains(StringField);
  @field coverage = contains(NumberField);
  @field lines = containsMany(StringField);
  @field message = contains(StringField);
}

// A field instance is not JSON-serialisable: `JSON.stringify` on one walks
// the declared shape and yields every key with a null value — the patch
// applies, the card looks populated, and every value is gone. Read the
// properties explicitly instead.
function severityToJSON(s: any) {
  return s?.level ? { level: s.level } : null;
}

function ruleToJSON(r: any) {
  return {
    ruleId: r?.ruleId ?? null,
    statement: r?.statement ?? null,
    regime: {
      regime: r?.regime?.regime ?? null,
      version: r?.regime?.version ?? null,
      clause: r?.regime?.clause ?? null,
      clauseTitle: r?.regime?.clauseTitle ?? null,
      url: r?.regime?.url ?? null,
    },
    kind: r?.kind ?? null,
    fieldPath: r?.fieldPath ?? null,
    parameters: r?.parameters ?? null,
    severityIfFailed: severityToJSON(r?.severityIfFailed),
    evidenceRequired: r?.evidenceRequired ?? null,
  };
}

function findingIdFor(year: number, n: number): string {
  return `F-${year}-${String(n).padStart(3, '0')}`;
}

export default class AuditCommand extends Command<
  typeof AuditInput,
  typeof AuditRunResult
> {
  static actionVerb = 'Run audit';
  static displayName = 'Audit';

  async getInputType() {
    return AuditInput;
  }

  protected async run(input: AuditInput): Promise<AuditRunResult> {
    let { periodStart, periodEnd, reportTitle, ranBy } = input;
    let bot = input.bot;
    if (!bot) {
      throw new Error('An auditor bot is required');
    }
    if (bot.id) {
      bot = (await new GetCardCommand(this.commandContext).execute({
        cardId: bot.id,
      })) as AuditorBot;
    }
    let rules = (bot.rules ?? []).filter(Boolean);
    if (!rules.length) {
      throw new Error(
        `${bot.name ?? 'That bot'} has no rules — a bot with no rules passes everything`,
      );
    }
    let realm =
      input.realm?.trim() ||
      (bot.id ? bot.id.slice(0, bot.id.lastIndexOf('/AuditorBot/') + 1) : '');
    if (!realm) {
      throw new Error('A realm is required to write results into');
    }

    // Subjects: the caller's, or the bot's own query.
    let subjects = (input.subjects ?? []).filter(Boolean) as CardDef[];
    if (!subjects.length) {
      let raw = (bot.subjectQuery ?? '').trim();
      if (!raw) {
        throw new Error(
          `${bot.name ?? 'That bot'} has no subjectQuery and no subjects were passed`,
        );
      }
      let query: any;
      try {
        query = JSON.parse(raw);
      } catch {
        throw new Error("The bot's subjectQuery is not valid JSON");
      }
      // A query has no base to resolve against, so a relative module silently
      // matches nothing. Authors write the relative form because that is what
      // every card module uses, so resolve it here rather than failing.
      let type = query?.filter?.type ?? query?.filter?.on;
      if (type?.module?.startsWith('.')) {
        type.module = new URL(type.module, realm).href;
      }
      let found = (await new SearchCardsByQueryCommand(
        this.commandContext,
      ).execute({ query } as any)) as any;
      subjects = ((found?.instances ?? []) as CardDef[]).filter(Boolean);
    }
    if (!subjects.length) {
      throw new Error(
        'The subject query matched nothing — nothing to evaluate',
      );
    }

    // Findings already on record, so a repeat can name the one it repeats.
    let priorFindings = new Map<string, string>();
    let priorCount = 0;
    let resultRef = { module: `${realm}audit-result`, name: 'AuditResult' };
    try {
      let prior = (await new SearchCardsByQueryCommand(
        this.commandContext,
      ).execute({ query: { filter: { type: resultRef } } } as any)) as any;
      for (let r of (prior?.instances ?? []) as AuditResult[]) {
        let id = r?.finding?.findingId;
        if (!id) {
          continue;
        }
        priorCount += 1;
        let key = `${r.rule?.ruleId ?? ''}::${r.subject?.id ?? ''}`;
        priorFindings.set(key, id);
      }
    } catch {
      // A realm with no results yet is the normal first run, not an error.
    }

    let now = new Date();
    let year = now.getFullYear();
    let nextFinding = priorCount + 1;

    // The report first, so every result can point at it as it is written.
    let report = (await new SaveCardCommand(this.commandContext).execute({
      card: new StandardEvaluationReport({
        title:
          reportTitle?.trim() ||
          `${bot.regime?.regime ?? 'Evaluation'} — ${bot.name ?? 'run'}`,
        subjectsEvaluated: subjects.length,
      }),
      realm,
    } as any)) as StandardEvaluationReport;

    let outcomes: RuleOutcome[] = [];
    let lines: string[] = [];
    let written: AuditResult[] = [];
    let findingsRaised = 0;
    let recurrences = 0;

    for (let subject of subjects) {
      for (let rule of rules) {
        let outcome = evaluateRule(rule, subject, { now });
        outcomes.push(outcome);

        let result = (await new SaveCardCommand(this.commandContext).execute({
          card: new AuditResult({
            audit: report,
            subject,
            evaluatedBy: ranBy,
            observedValue: outcome.observed,
          }),
          realm,
        } as any)) as AuditResult;

        let patch: Record<string, any> = {
          rule: ruleToJSON(rule),
          status: { status: outcome.status },
          evaluatedAt: now.toISOString(),
          meta: {
            createdAt: now.toISOString(),
            changeCount: 0,
            sourceVersion: `${bot.name ?? 'bot'} rules`,
          },
        };

        if (outcome.status === 'fail' || outcome.status === 'partial') {
          let key = `${rule.ruleId ?? ''}::${subject.id ?? ''}`;
          let repeats = priorFindings.get(key);
          let findingId = findingIdFor(year, nextFinding++);
          findingsRaised += 1;
          if (repeats) {
            recurrences += 1;
          }
          patch.finding = {
            findingId,
            rule: ruleToJSON(rule),
            severity: severityToJSON(rule.severityIfFailed) ?? {
              level: 'major',
            },
            statement: `Required: ${rule.statement ?? rule.ruleId ?? ''} — observed ${outcome.observed}. ${outcome.reason}`,
            state: 'open',
            raisedAt: now.toISOString(),
            recurrenceOfId: repeats ?? null,
            evidence: [],
            annotations: [],
          };
        }

        await new PatchCardInstanceCommand(this.commandContext, {
          cardType: AuditResult,
        }).execute({ cardId: result.id, patch: { attributes: patch } } as any);

        written.push(result);
        lines.push(
          `${rule.ruleId ?? '—'} · ${subject.cardTitle ?? subject.id} · ${outcome.status} · ${outcome.observed}`,
        );
      }
    }

    let counts = tally(outcomes);
    let verdict = rollup(counts);
    let cover = coverage(counts);

    // Link the results and the roll-up onto the report in one patch.
    let relationships: Record<string, any> = {};
    written.forEach((r, i) => {
      relationships[`results.${i}`] = { links: { self: r.id } };
    });
    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: StandardEvaluationReport,
    }).execute({
      cardId: report.id,
      patch: {
        attributes: {
          rollup: { status: verdict },
          coverage: cover,
          period:
            periodStart || periodEnd
              ? { start: periodStart ?? null, end: periodEnd ?? null }
              : undefined,
          lifecycle: { createdAt: now.toISOString() },
        },
        relationships,
      },
    } as any);

    // The trail. `subjectTitle` is the snapshot the entry is read by; the link
    // is what makes it navigable — both, per Audit Entry's own contract.
    await new SaveCardCommand(this.commandContext).execute({
      card: new AuditEntry({
        action: 'created',
        occurredAt: now,
        doneBy: ranBy,
        subject: report,
        subjectTitle: report.title,
        note: `${bot.name ?? 'Audit'} run over ${subjects.length} subject(s): ${verdict}, ${findingsRaised} finding(s) raised.`,
      }),
      realm,
    } as any);

    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: AuditorBot,
    }).execute({
      cardId: bot.id,
      patch: { attributes: { lastRunAt: now.toISOString() } },
    } as any);

    return new AuditRunResult({
      report,
      subjectsEvaluated: subjects.length,
      resultsWritten: written.length,
      findingsRaised,
      recurrences,
      rollup: verdict,
      coverage: cover,
      lines,
      message: `${verdict} — ${written.length} result(s) over ${subjects.length} subject(s), ${findingsRaised} finding(s) raised (${recurrences} recurring), ${cover}% coverage`,
    } as any);
  }
}
