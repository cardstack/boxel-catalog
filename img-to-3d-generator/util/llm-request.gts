// The one place this pipeline talks to a model.
//
// Every stage — analyse, spec, refine, targeted edit — is the same shape of
// call: a system prompt, some images, a JSON reply that has to parse. What
// differs between them is only the prompt and the parser, so the transport,
// the retry policy and the determinism controls live here once. Keeping them
// together also keeps them honest: the retry budget and the temperature are
// the same decision seen from two sides, and splitting them is how one gets
// tuned without the other.

import SendRequestViaProxyCommand from '@cardstack/boxel-host/tools/send-request-via-proxy';

import { parseSpecJson } from './spec-io';

export const OPENROUTER_URL = 'https://openrouter.ai/api/v1/chat/completions';
export const VISION_MODEL = 'anthropic/claude-sonnet-5';
// the model for the conversational "Refine with AI" room. Deliberately
// NON-Anthropic: the ai-bot injects skill instructions as an inline system
// message, which Anthropic's tightened API rejects ("role 'system' must follow
// a 'user' message …"). Gemini Flash sidesteps that rule and is vision-strong
// for the reference-vs-render diagnosis the assistant does in the room.
// the conversational Refine room's model — shown in the chat UI. Non-Anthropic
// (sidesteps the inline-system-message API error) and vision-capable for the
// reference-vs-render diagnosis. Kept in step with REFINE_MODEL so the visible
// room model and the edit model are the same.
export const ASSISTANT_MODEL = 'google/gemini-3.5-flash';
// the model the Refine Model command uses to turn ONE agreed instruction into a
// spec change set (no image — the assistant already diagnosed visually). A fast
// Gemini Flash is plenty for that structured-JSON edit and keeps refines snappy.
export const REFINE_MODEL = 'google/gemini-3.5-flash';
// the analysis stage is the gate for the whole pipeline — it classifies the
// object, measures per-part bboxes, and decides which parts are 'revolved'
// (which drives deterministic silhouette tracing). It is almost pure PERCEPTION
// (image → bboxes/camera), where a fast Gemini Flash grounds bounding boxes at
// least as well as a much slower/pricier reasoning model — so the gate is
// pinned to Flash for speed/cost, independent of the spec model the user picks.
export const ANALYSIS_MODEL = 'google/gemini-3.6-flash';
// the vision models offered anywhere a model can be picked (studio) or
// recorded (each SculptedModel round, the analyze command) — one shared list
// so every "model" field enumerates the same options. VISION_MODEL must stay
// a member so the programmatic default is always a valid enum value.
export const VISION_MODEL_OPTIONS = [
  'anthropic/claude-sonnet-5',
  'anthropic/claude-sonnet-4.6',
  'anthropic/claude-opus-4.8',
  'google/gemini-3.5-flash',
  'google/gemini-3.6-flash',
];

// Every stage of this pipeline is a MEASUREMENT, not a creative act: the
// analysis reads bboxes off a photo, the spec derives coordinates from those
// bboxes, the refine pass corrects placement. Sampling has nothing to
// contribute to any of them — it only makes the same photo produce a
// different object type, a different part count and differently placed parts
// on every run. Left unset, the request inherits the provider's default
// (~1.0), which is why two Generates on one reference never matched. Pin it
// at 0 so a reference maps to one reconstruction.
export const SPEC_TEMPERATURE = 0;

// temperature 0 alone is not bit-reproducible — it picks the argmax token,
// and ties/batching still drift. `seed` closes the rest of the gap on
// providers that honour it (Gemini and OpenAI-family; Anthropic ignores it
// harmlessly), so both are sent. Derived from the reference URLs rather than
// random: same photos in, same seed, same model — while a new photo set gets
// its own seed instead of inheriting the previous object's sampling path.
export function seedFromStrings(parts: string[]): number {
  // FNV-1a, 32-bit — tiny, dependency-free, well distributed over short
  // strings. Kept below 2^31 because some providers reject larger seeds.
  let hash = 0x811c9dc5;
  for (let part of parts) {
    for (let i = 0; i < part.length; i++) {
      hash ^= part.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    // separator so ['ab','c'] and ['a','bc'] do not collide
    hash ^= 0x2f;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash % 0x7fffffff;
}

// one vision round-trip through the Boxel proxy, returning the parsed spec.
// Retries transient failures (rate limit / upstream error / dropped
// connection / invalid JSON / truncation) with backoff, appending a
// corrective nudge on content failures. Network drops get extra attempts:
// the browser kills every in-flight fetch when the machine's network
// changes (ERR_NETWORK_CHANGED — Wi-Fi hop, VPN reconnect), and these
// vision calls run for minutes, so a single flap mid-request is common.
// This pipeline's calls are INPUT-heavy, not output-heavy: the spec stage sends
// roughly 7k tokens of system prompt, 1.7k of analysis and up to 11k of images to
// get back about 2.3k tokens of JSON. Marking the system prompt cacheable lets
// the provider skip re-processing it — cheaper and quicker to first token.
//
// A caller may pass several blocks. Only the FIRST carries the cache marker,
// because only the first is guaranteed byte-identical across objects: the spec
// stage sends its invariant contract as block 0 and this object's selected
// build directives after it, so the expensive half still caches while the
// per-object half varies freely. Order matters — a prefix cache is only a hit
// up to the first byte that differs.
//
// Only Anthropic models are given the marker: the field is an Anthropic
// extension, and a provider that does not understand a structured system message
// is better off receiving the plain string it has always received.
function systemMessage(llmModel: string, systemPrompt: string | string[]): any {
  let blocks = Array.isArray(systemPrompt) ? systemPrompt : [systemPrompt];
  if (!/^anthropic\//.test(llmModel)) return blocks.join('\n\n');
  return blocks.map((text, i) => ({
    type: 'text',
    text,
    ...(i === 0 ? { cache_control: { type: 'ephemeral' } } : {}),
  }));
}

export async function requestSpec(
  commandContext: any,
  llmModel: string,
  systemPrompt: string | string[],
  userContent: any[],
  onLog?: (line: string) => void,
  parser: (raw: string) => any = parseSpecJson,
  // seed: pass seedFromStrings(referenceUrls) so one reference set always
  // takes the same sampling path. temperature defaults to SPEC_TEMPERATURE
  // (0) and should only be raised deliberately.
  //
  // validate: inspect a well-formed reply and return a correction to send back,
  // or null to accept it. The retry loop below already knows how to re-ask with a
  // nudge when a reply is truncated or is not JSON; a reply that PARSES but left
  // out half the object is the same kind of failure and deserves the same
  // treatment. Being told exactly which parts are missing is far more likely to
  // work than re-rolling and hoping.
  options?: {
    temperature?: number;
    seed?: number;
    validate?: (parsed: any) => string | null;
    // OpenRouter reasoning control. The analysis stage is pure perception, so
    // passing { enabled: false } stops a "thinking" model (e.g. Gemini flash)
    // from spending seconds emitting reasoning tokens before the JSON.
    reasoning?: { enabled?: boolean; max_tokens?: number; effort?: string };
  },
) {
  let temperature = options?.temperature ?? SPEC_TEMPERATURE;
  let seed = options?.seed;
  let attempt = async (extraNudge?: string) => {
    let content = extraNudge
      ? [...userContent, { type: 'text', text: extraNudge }]
      : userContent;
    let proxy = new SendRequestViaProxyCommand(commandContext);
    let result = await proxy.execute({
      url: OPENROUTER_URL,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      requestBody: JSON.stringify({
        model: llmModel,
        max_tokens: 24000,
        temperature,
        ...(typeof seed === 'number' ? { seed } : {}),
        ...(options?.reasoning ? { reasoning: options.reasoning } : {}),
        messages: [
          { role: 'system', content: systemMessage(llmModel, systemPrompt) },
          { role: 'user', content },
        ],
      }),
    });
    let response = result?.response;
    if (!response) {
      throw new Error('proxy returned no response');
    }
    if (response.status === 403) {
      throw new Error(
        'AI request rejected (403) — you may be out of AI credits.',
      );
    }
    if (response.status >= 400) {
      let body = '';
      try {
        body = (await response.text()).slice(0, 120);
      } catch {
        // body unavailable
      }
      let err: any = new Error(
        `vision request failed: ${response.status}${body ? ` — ${body}` : ''}`,
      );
      err.status = response.status;
      throw err;
    }
    let payload = await response.json();
    let choice = payload?.choices?.[0];
    if (choice?.finish_reason === 'length') {
      let err: any = new Error(
        'the spec got too long and was truncated — retrying with shorter notes',
      );
      err.truncated = true;
      throw err;
    }
    let parsed = parser(choice?.message?.content ?? '');
    let complaint = options?.validate?.(parsed) ?? null;
    if (complaint) {
      // a parseable but incomplete reply: throw so the loop retries, and carry
      // both the complaint (to send back) and the reply (so the last attempt can
      // still be used rather than failing the whole generation)
      let err: any = new Error(complaint);
      err.incomplete = true;
      err.correction = complaint;
      err.parsed = parsed;
      throw err;
    }
    return parsed;
  };

  // A dropped connection deserves more patience than a bad reply: nothing about
  // the request was wrong, it just never finished, and re-sending is free of the
  // risk that a retry makes things worse. A malformed or truncated reply is the
  // model's doing, so hammering it rarely helps — the corrective nudge does. The
  // comment here used to claim network drops already got extra attempts; they
  // did not, every failure shared one budget.
  const MAX_ATTEMPTS = 4;
  const MAX_NETWORK_ATTEMPTS = 7;
  const RETRY_DELAYS_MS = [2000, 5000, 10000];
  // longer, gentler backoff for a flapping connection — a Wi-Fi hop or a dev
  // server restart takes tens of seconds to settle, and retrying into it just
  // burns an attempt
  const NETWORK_DELAYS_MS = [2000, 5000, 10000, 20000, 30000, 30000];
  let attemptsAllowed = MAX_ATTEMPTS;
  let lastError: any;
  for (let i = 0; i < attemptsAllowed; i++) {
    let nudge: string | undefined;
    if (lastError?.truncated) {
      nudge =
        'Your previous reply was truncated. Reply with ONLY the JSON object and keep every "note" under 8 words.';
    } else if (lastError?.correction) {
      nudge = lastError.correction;
    } else if (lastError?.contentFailure) {
      nudge =
        'Your previous reply was not valid JSON. Reply with ONLY the JSON object — no prose, no markdown fences.';
    }
    try {
      return await attempt(nudge);
    } catch (e: any) {
      let transientHttp =
        e?.status === 429 || (typeof e?.status === 'number' && e.status >= 500);
      let networkDrop = /Failed to fetch|NetworkError|network changed/i.test(
        e?.message ?? '',
      );
      let contentFailure =
        e?.truncated ||
        e?.incomplete ||
        /did not return JSON|no components/i.test(e?.message ?? '');
      if (!transientHttp && !networkDrop && !contentFailure) throw e;
      e.contentFailure = contentFailure;
      lastError = e;
      if (networkDrop) attemptsAllowed = MAX_NETWORK_ATTEMPTS;
      // an incomplete reply is only worth ONE corrective re-ask: if naming the
      // missing parts did not produce them, a third identical request will not
      // either, and the reply we already hold is usable — better an object with a
      // part missing than no object at all
      if (e?.incomplete && i >= 1) {
        onLog?.(
          `> still incomplete after a correction — building anyway (${e.correction})`,
        );
        return e.parsed;
      }
      if (i === attemptsAllowed - 1) break;
      let delay = networkDrop
        ? (NETWORK_DELAYS_MS[i] ?? 30000)
        : (RETRY_DELAYS_MS[i] ?? 10000);
      onLog?.(
        `> retrying ${i + 1}/${attemptsAllowed - 1} in ${Math.round(delay / 1000)}s (${
          networkDrop ? 'connection dropped' : (e?.status ?? 'invalid response')
        })…`,
      );
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw lastError;
}
