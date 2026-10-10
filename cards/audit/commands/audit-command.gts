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
import { Command, identifyCard, realmURL } from '@cardstack/runtime-common';
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
import { linkedId } from '@cardstack/catalog/utils/linked-id';

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

function regimeToJSON(r: any) {
  return {
    regime: r?.regime ?? null,
    version: r?.version ?? null,
    clause: r?.clause ?? null,
    clauseTitle: r?.clauseTitle ?? null,
    url: r?.url ?? null,
  };
}

function ruleToJSON(r: any) {
  return {
    ruleId: r?.ruleId ?? null,
    statement: r?.statement ?? null,
    regime: regimeToJSON(r?.regime),
    kind: r?.kind ?? null,
    fieldPath: r?.fieldPath ?? null,
    parameters: r?.parameters ?? null,
    severityIfFailed: severityToJSON(r?.severityIfFailed),
    evidenceRequired: r?.evidenceRequired ?? null,
  };
}

// A finding id carries the year and the first characters of its result's
// own card id, which the realm generated: unique without a shared counter
// that two concurrent runs could both read.
function findingIdFor(year: number, resultId: string): string {
  let tail = resultId.split('/').pop() ?? resultId;
  let short = tail
    .replace(/[^a-z0-9]/gi, '')
    .slice(0, 8)
    .toUpperCase();
  return `F-${year}-${short}`;
}

// A query has no base to resolve against, so a relative module silently
// matches nothing. Every `type` and `on` ref in the filter tree resolves
// against the realm the query was written in.
function resolveQueryModules(node: any, base: string): void {
  if (!node || typeof node !== 'object') {
    return;
  }
  if (Array.isArray(node)) {
    node.forEach((n) => resolveQueryModules(n, base));
    return;
  }
  for (let key of ['type', 'on']) {
    let ref = node[key];
    if (typeof ref?.module === 'string' && ref.module.startsWith('.')) {
      ref.module = new URL(ref.module, base).href;
    }
  }
  for (let value of Object.values(node)) {
    resolveQueryModules(value, base);
  }
}

// DateRangeField stores calendar days as yyyy-MM-dd, read in local time.
function dayString(d: Date): string {
  let m = `${d.getMonth() + 1}`.padStart(2, '0');
  let day = `${d.getDate()}`.padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
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
    let { periodStart, periodEnd, reportTitle } = input;
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
    // A bot never signs off, so every run is recorded against a person: the
    // caller, or the human the bot runs as.
    let ranBy = input.ranBy ?? bot.runsAs;
    if (!ranBy?.id) {
      throw new Error(
        `Name who ran it: pass ranBy, or set ${bot.name ?? 'the bot'}'s runsAs`,
      );
    }
    let realm = input.realm?.trim() || (bot as any)[realmURL]?.href;
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
      // Relative modules resolve against the bot's realm, which the query
      // belongs to, not the realm the results are written into.
      let botRealm = (bot as any)[realmURL]?.href ?? realm;
      resolveQueryModules(query?.filter, botRealm);
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
    // A command runs outside a render, where a search result's links never
    // load, so the subjects are matched in one query and each result's subject
    // is read from its reference.
    let priorFindings = new Map<string, string>();
    let resultRef = identifyCard(AuditResult);
    let subjectIds = subjects.map((s) => s.id).filter(Boolean) as string[];
    if (resultRef && subjectIds.length) {
      let prior = (await new SearchCardsByQueryCommand(
        this.commandContext,
      ).execute({
        query: {
          filter: {
            on: resultRef,
            any: subjectIds.map((id) => ({ eq: { 'subject.id': id } })),
          },
        },
      } as any)) as any;
      for (let r of (prior?.instances ?? []) as AuditResult[]) {
        let id = r?.finding?.findingId;
        let subjectId = r ? linkedId(r, 'subject') : null;
        if (id && subjectId) {
          priorFindings.set(`${r.rule?.ruleId ?? ''}::${subjectId}`, id);
        }
      }
    }

    let now = new Date();
    let year = now.getFullYear();

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
          let findingId = findingIdFor(year, result.id);
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

        let links: Record<string, any> = {};
        if (patch.finding) {
          links['finding.subject'] = { links: { self: subject.id } };
          links['finding.raisedBy'] = { links: { self: ranBy.id } };
        }
        await new PatchCardInstanceCommand(this.commandContext, {
          cardType: AuditResult,
        }).execute({
          cardId: result.id,
          patch: { attributes: patch, relationships: links },
        } as any);

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
    let authority = bot.regime?.authority?.id;
    if (authority) {
      relationships['regime.authority'] = { links: { self: authority } };
    }
    await new PatchCardInstanceCommand(this.commandContext, {
      cardType: StandardEvaluationReport,
    }).execute({
      cardId: report.id,
      patch: {
        attributes: {
          regime: regimeToJSON(bot.regime),
          rollup: { status: verdict },
          coverage: cover,
          period:
            periodStart || periodEnd
              ? {
                  start: periodStart ? dayString(periodStart) : null,
                  end: periodEnd ? dayString(periodEnd) : null,
                }
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

    // An unsaved bot has nowhere to record its last run.
    if (bot.id) {
      await new PatchCardInstanceCommand(this.commandContext, {
        cardType: AuditorBot,
      }).execute({
        cardId: bot.id,
        patch: { attributes: { lastRunAt: now.toISOString() } },
      } as any);
    }

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
