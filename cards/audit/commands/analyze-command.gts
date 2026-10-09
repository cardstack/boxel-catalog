import {
  CardDef,
  contains,
  field,
  linksTo,
  StringField,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import BooleanField from '@cardstack/base/boolean';
import { Command } from '@cardstack/runtime-common';
import GetCardCommand from '@cardstack/boxel-host/commands/get-card';
import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';

import { AuditResult } from '@cardstack/catalog/cards/audit/audit-result';
import { SEVERITY_LEVELS } from '@cardstack/catalog/cards/audit/severity-vocabulary';

/**
 * Analyze — read a result and its evidence, and propose wording.
 *
 * **It writes nothing and it is not an authority.** It returns a draft
 * statement and a proposed severity for a human to accept, edit or throw
 * away, and the acceptance is a separate, attributed save. A compliance
 * finding is somebody's professional judgement with their name on it; a model
 * that quietly wrote findings would be putting words in an auditor's mouth,
 * which is the one thing an audit trail exists to prevent.
 *
 * The proposal is deliberately conservative: when the model returns a
 * severity outside the vocabulary, the rule's own default is kept rather than
 * guessed at, and `accepted` stays false until a person says otherwise.
 */
export class AnalyzeInput extends CardDef {
  @field result = linksTo(() => AuditResult, { searchable: true });
  /** Extra context the auditor wants weighed — a site note, a vendor reply. */
  @field context = contains(TextAreaField);
}

export class AnalyzeResult extends CardDef {
  /** A statement the auditor may accept as the finding's wording. */
  @field draftStatement = contains(TextAreaField);
  @field proposedSeverity = contains(StringField);
  /** Why the model proposed that severity, in its own words. */
  @field rationale = contains(TextAreaField);
  /** Always false. Acceptance is a person's act, recorded separately. */
  @field accepted = contains(BooleanField);
  @field message = contains(StringField);
}

const SYSTEM_PROMPT = [
  'You are assisting an auditor. Draft the wording for one audit finding from the facts given.',
  'Reply as JSON only, no prose around it:',
  '{"statement": "one or two sentences stating what was required and what was observed, in an auditor\'s register", "severity": "minor|major|critical", "rationale": "one sentence on why that severity"}',
  'Do not recommend closing the finding. Do not invent evidence that is not listed.',
].join('\n');

export default class AnalyzeCommand extends Command<
  typeof AnalyzeInput,
  typeof AnalyzeResult
> {
  static actionVerb = 'Analyze';
  static displayName = 'Analyze';

  async getInputType() {
    return AnalyzeInput;
  }

  protected async run(input: AnalyzeInput): Promise<AnalyzeResult> {
    let result = input.result;
    if (!result) {
      throw new Error('An audit result is required');
    }
    if (result.id) {
      result = (await new GetCardCommand(this.commandContext).execute({
        cardId: result.id,
      })) as AuditResult;
    }

    // A finding exists only for a fail or partial verdict.
    let verdict = result.status?.status ?? '';
    if (!['fail', 'partial'].includes(verdict)) {
      throw new Error(
        `Analyze drafts findings for failing results; this one is "${verdict || 'unset'}"`,
      );
    }

    let rule = result.rule;
    let evidence = (result.evidence ?? []).filter(Boolean);
    let evidenceLines = evidence
      .map(
        (e, i) =>
          `${i + 1}. ${e.kind ?? 'evidence'} — trust ${e.trust?.level ?? 'unstated'}, integrity ${e.integrity ?? 'unverified'}${e.statement ? `: ${e.statement}` : ''}`,
      )
      .join('\n');

    let facts = [
      `Rule (${rule?.ruleId ?? 'unnamed'}): ${rule?.statement ?? '(no statement)'}`,
      `Clause: ${rule?.regime?.reference ?? 'unstated'}`,
      `Verdict: ${result.status?.status ?? 'unknown'}`,
      `Observed: ${result.observedValue ?? '—'}`,
      `Rule default severity if failed: ${rule?.severityIfFailed?.level ?? 'major'}`,
      '',
      evidenceLines
        ? `Evidence attached:\n${evidenceLines}`
        : 'No evidence attached.',
      input.context?.trim() ? `\nAuditor context:\n${input.context}` : '',
    ]
      .filter(Boolean)
      .join('\n');

    let llm = await new OneShotLlmRequestCommand(this.commandContext).execute({
      systemPrompt: SYSTEM_PROMPT,
      userPrompt: facts,
      skillCardIds: [],
      llmModel: 'anthropic/claude-sonnet-4.6',
    });
    let raw = String(llm?.output ?? '').trim();

    let draft = '';
    let severity = '';
    let rationale = '';
    try {
      let match = raw.match(/\{[\s\S]*\}/);
      let parsed = match ? JSON.parse(match[0]) : {};
      draft = String(parsed.statement ?? '').trim();
      severity = String(parsed.severity ?? '').trim();
      rationale = String(parsed.rationale ?? '').trim();
    } catch {
      // A model that did not return JSON still said something worth showing.
      draft = raw;
    }

    // Never accept a severity the vocabulary does not have — fall back to the
    // rule's own default rather than guessing.
    if (!(SEVERITY_LEVELS as readonly string[]).includes(severity)) {
      severity = rule?.severityIfFailed?.level ?? 'major';
      rationale = rationale
        ? `${rationale} (severity outside the vocabulary; the rule's default was kept)`
        : "The model proposed no usable severity; the rule's default was kept.";
    }

    return new AnalyzeResult({
      draftStatement: draft || 'The model returned nothing usable.',
      proposedSeverity: severity,
      rationale,
      accepted: false,
      message: `Draft only — proposed ${severity}. Accept it on the finding to make it the wording of record.`,
    } as any);
  }
}
