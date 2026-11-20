import { CardDef, contains, field } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Command } from '@cardstack/runtime-common';
import OneShotLlmRequestCommand from '@cardstack/boxel-host/commands/one-shot-llm-request';

const SYSTEM_PROMPT = `You help a small digital agency turn a client chat into a quote. The user message is a JSON object with three keys:
- "catalog": numbered lines, one service per line, e.g. "1. Logo design (per project)". This is the ONLY list of services you may choose from.
- "transcript": the chat between the agency and the client.
- "language": the language every text field in your answer MUST be written in.

Rules:
- Choose only item numbers that exist in the catalog. Never invent items.
- Never output prices, totals or discounts. Prices are handled elsewhere.
- If the client's main objective, scope or quantities are unclear, list what is missing in "missingInfo" and write "clarifyingQuestions" addressed to the client.
- Language: write "reason", "missingInfo" and "clarifyingQuestions" ONLY in the language given in "language". Names of people or companies are not a hint about language. Never switch to any other language.
- "clarifyingQuestions" are only for things the client can answer (scope, quantity, timeline, budget). Never ask the client about our catalog or availability; put catalog gaps in "missingInfo" only.
- "isComplete" is true only when an honest quote can be made from this chat.

OUTPUT: ONE JSON object only. No prose, no markdown fences. Shape:
{"items":[{"itemNumber":1,"qty":2,"reason":"max 12 words"}],"missingInfo":["..."],"clarifyingQuestions":["..."],"isComplete":true}`;

// Bahasa ditentukan di kode, bukan ditebak AI (AI sempat menjawab Spanyol/Belanda
// untuk chat berbahasa Inggris). ponytail: hanya Indonesia vs Inggris.
const INDONESIAN_WORDS = new Set(
  'yang dan untuk dengan tidak saya kami kak mau bisa ada ini itu sudah belum berapa juga aja gimana tolong terima kasih buat sama nanti'.split(
    ' ',
  ),
);

export function chatLanguage(transcript: string) {
  let words = transcript.toLowerCase().match(/[a-z]+/g) ?? [];
  let hits = words.filter((w) => INDONESIAN_WORDS.has(w)).length;
  return hits >= 3 && hits / Math.max(words.length, 1) > 0.03
    ? 'Indonesian'
    : 'English';
}

export class AnalyzeBriefInput extends CardDef {
  @field transcript = contains(StringField, {
    description: 'Chat transcript, one "Sender: message" per line.',
  });
  @field catalogText = contains(StringField, {
    description: 'Numbered service lines, e.g. "1. Logo design (per project)".',
  });
}

export class AnalyzeBriefResult extends CardDef {
  @field resultJson = contains(StringField);
  @field error = contains(StringField);
}

const isPositiveInt = (n: unknown) => Number.isInteger(n) && (n as number) >= 1;
const strings = (v: unknown) =>
  Array.isArray(v) ? v.filter((s) => typeof s === 'string' && s.trim()) : [];

// Bersihkan balasan AI; tidak pernah throw
export function cleanAnalysis(raw: string): {
  resultJson: string;
  error: string;
} {
  let text = raw.replace(/```(?:json)?/gi, '');
  let start = text.indexOf('{');
  let end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return { resultJson: '', error: 'AI returned no JSON.' };
  }
  let parsed: any;
  try {
    parsed = JSON.parse(text.slice(start, end + 1));
  } catch {
    return { resultJson: '', error: 'AI returned invalid JSON.' };
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { resultJson: '', error: 'AI returned an unexpected shape.' };
  }
  let items = (Array.isArray(parsed.items) ? parsed.items : [])
    .filter(
      (i: any) => i && isPositiveInt(i.itemNumber) && isPositiveInt(i.qty),
    )
    .map((i: any) => ({
      itemNumber: i.itemNumber,
      qty: i.qty,
      reason: typeof i.reason === 'string' ? i.reason : '',
    }));
  let cleaned = {
    items,
    missingInfo: strings(parsed.missingInfo),
    clarifyingQuestions: strings(parsed.clarifyingQuestions),
    // Bukan boolean → anggap belum lengkap
    isComplete: parsed.isComplete === true,
  };
  return { resultJson: JSON.stringify(cleaned), error: '' };
}

export default class AnalyzeBriefCommand extends Command<
  typeof AnalyzeBriefInput,
  typeof AnalyzeBriefResult
> {
  static actionVerb = 'Analyze';
  static displayName = 'Analyze brief with AI';

  async getInputType() {
    return AnalyzeBriefInput;
  }

  protected async run(input: AnalyzeBriefInput): Promise<AnalyzeBriefResult> {
    if (!input.transcript?.trim()) {
      return new AnalyzeBriefResult({
        resultJson: '',
        error: 'Transcript is empty.',
      });
    }
    if (!input.catalogText?.trim()) {
      return new AnalyzeBriefResult({
        resultJson: '',
        error: 'Service catalog is empty.',
      });
    }
    try {
      let oneShot = new OneShotLlmRequestCommand(this.commandContext);
      let result = await oneShot.execute({
        systemPrompt: SYSTEM_PROMPT,
        userPrompt: JSON.stringify({
          catalog: input.catalogText,
          transcript: input.transcript,
          language: chatLanguage(input.transcript),
        }),
        skillCardIds: [],
        llmModel: 'anthropic/claude-sonnet-4.6',
      });
      let raw = ((result as any)?.output ?? '') as string;
      return new AnalyzeBriefResult(cleanAnalysis(raw));
    } catch (e: any) {
      return new AnalyzeBriefResult({
        resultJson: '',
        error: `AI request failed: ${String(e?.message ?? e).slice(0, 200)}`,
      });
    }
  }
}
