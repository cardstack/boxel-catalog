import {
  CardDef,
  contains,
  containsMany,
  field,
  linksTo,
  linksToMany,
  StringField,
} from '@cardstack/base/card-api';
import TextAreaField from '@cardstack/base/text-area';
import { Command } from '@cardstack/runtime-common';
import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';
import { GetCardCommand } from '@cardstack/boxel-host/commands/get-card';

import { Case } from '@cardstack/catalog/cards/service-desk/case';
import { CustomerReply } from '@cardstack/catalog/cards/service-desk/customer-reply';
import { KnowledgeArticle } from '@cardstack/catalog/cards/service-desk/knowledge-article';

export const COPILOT_INTENTS = [
  'draft-reply',
  'summarize-thread',
  'suggest-next-action',
] as const;

const SYSTEM_PROMPT = `You are a support copilot producing a DRAFT for a human agent. The user message is JSON:
- "intent": draft-reply | summarize-thread | suggest-next-action
- "case": subject, status, severity, problem statement
- "thread": the replies, oldest first, each {direction, who, body}
- "articles": knowledge-base articles, each {title, body} — cite by title anything you rely on

RULES:
- Facts come ONLY from the case, thread and articles. Never invent order numbers, names or promises.
- draft-reply: write the next OUTBOUND reply, professional and concrete. No signature.
- summarize-thread: a short factual summary an incoming agent reads in 20 seconds.
- suggest-next-action: 2-3 concrete next steps, each one line.
- End with a line "CITATIONS: <comma-separated article titles>" (or "CITATIONS: none").
OUTPUT: the draft only. No preamble.`;

export class AiCopilotInput extends CardDef {
  @field case = linksTo(() => Case, { searchable: true });
  @field intent = contains(StringField, {
    description: 'draft-reply | summarize-thread | suggest-next-action',
  });
  @field replies = linksToMany(() => CustomerReply, {
    description: "The case's thread, CALLER-loaded, in any order.",
  });
  @field articles = linksToMany(() => KnowledgeArticle, {
    description:
      'KB grounding, CALLER-selected (e.g. via suggest-kb-articles).',
  });
  @field llmModel = contains(StringField);
}

export class AiCopilotResult extends CardDef {
  @field draft = contains(TextAreaField);
  @field citations = containsMany(StringField);
}

/**
 * DRAFTS ONLY — this command never writes a card. Accepting a draft is a
 * separate, attributed act: the agent edits and saves it as their own
 * outbound Customer Reply, so nothing the model wrote can reach a customer
 * without a human's name on it.
 *
 * Grounding is caller-supplied (the thread, plus KB articles typically picked
 * by the ServiceDesk's suggest-kb-articles); the citations the model relied
 * on come back as data so the UI can show them beside the draft.
 */
export default class AiCopilotCommand extends Command<
  typeof AiCopilotInput,
  typeof AiCopilotResult
> {
  static actionVerb = 'Draft';
  static displayName = 'AI Copilot';

  async getInputType() {
    return AiCopilotInput;
  }

  protected async run(input: AiCopilotInput): Promise<AiCopilotResult> {
    if (!input.case?.id) {
      throw new Error('case is required');
    }
    let intent = input.intent || 'draft-reply';
    if (!COPILOT_INTENTS.includes(intent as any)) {
      throw new Error(`intent must be one of: ${COPILOT_INTENTS.join(', ')}`);
    }
    let kase = ((await new GetCardCommand(this.commandContext).execute({
      cardId: input.case.id,
    } as any)) ?? input.case) as any;

    let thread = [...(input.replies ?? [])]
      .filter(Boolean)
      .sort(
        (a, b) =>
          new Date((a.sentAt as any) ?? 0).getTime() -
          new Date((b.sentAt as any) ?? 0).getTime(),
      )
      .map((r) => ({
        direction: r.direction,
        who:
          r.direction === 'inbound'
            ? r.fromAddress
            : ((r.author?.title as string) ?? 'agent'),
        body: r.body,
      }));

    let articles = (input.articles ?? []).filter(Boolean).map((a: any) => ({
      title: a.title,
      body: a.body ?? a.content ?? '',
    }));

    let oneShot = new OneShotLlmRequestCommand(this.commandContext);
    let result = await oneShot.execute({
      systemPrompt: SYSTEM_PROMPT,
      userPrompt: JSON.stringify({
        intent,
        case: {
          subject: kase.subject,
          status: kase.status,
          severity: kase.severity,
          problem: kase.problemStatement,
        },
        thread,
        articles,
      }),
      skillCardIds: [],
      llmModel: input.llmModel || 'anthropic/claude-sonnet-4.6',
    });
    let raw = (((result as any)?.output ?? '') as string).trim();
    if (!raw) {
      throw new Error('Copilot returned nothing');
    }
    let citations: string[] = [];
    let m = /CITATIONS:\s*(.*)$/im.exec(raw);
    if (m) {
      raw = raw.slice(0, m.index).trim();
      let list = m[1]!.trim();
      if (list && list.toLowerCase() !== 'none') {
        citations = list
          .split(',')
          .map((c) => c.trim())
          .filter(Boolean);
      }
    }
    return new AiCopilotResult({ draft: raw, citations });
  }
}
