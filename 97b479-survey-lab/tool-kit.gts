// What every question UI shares, because each one is a tool the interviewer
// (the agent running the survey) can pull up mid-conversation:
//   in:  `context`, what the interviewer already knows about this person, so
//        the tool can fit itself to them (optional; a tool also runs alone);
//   out: a response card holding the classic number(s) for totals, the extra
//        signal the old UI threw away, and `summary`, a few plain sentences
//        the interviewer reads to decide what to ask next.
import SendRequestViaProxyCommand from '@cardstack/boxel-host/tools/send-request-via-proxy';
import { realmURL } from '@cardstack/base/card-api';
import { MODEL } from './survey-ai';

export const SESSION_EXPIRED =
  'Your Boxel sign-in has expired. Reload the page: everything so far is saved, and it picks up from here.';

// one answer from the model, through the host's request proxy, as text
export async function askText(
  ctx: any,
  system: string,
  user: string | any[],
  temperature = 0.4,
  model = MODEL,
  json = false,
): Promise<string> {
  // a request that never comes back would leave the chat hanging silently
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, fail) => {
    timer = setTimeout(
      () =>
        fail(
          new Error(
            'the interviewer took too long to answer; trying again usually works',
          ),
        ),
      90000,
    );
  });
  const result = await Promise.race([
    new SendRequestViaProxyCommand(ctx).execute({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://boxel.ai',
        'X-Title': 'Survey lab',
      },
      requestBody: JSON.stringify({
        model,
        ...(json ? { response_format: { type: 'json_object' } } : {}),
        temperature,
        max_tokens: 4000,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
      }),
    } as any),
    timeout,
  ]).finally(() => clearTimeout(timer));
  const response = (result as any)?.response ?? result;
  if (response?.ok === false) {
    let body = '';
    try {
      body = await response.text();
    } catch {
      body = '';
    }
    // the host's sign-in can lapse in a long-open tab; only a reload renews it
    if (/token expired/i.test(body)) throw new Error(SESSION_EXPIRED);
    throw new Error(
      `the interviewer said ${response.status}: ${body.slice(0, 160)}`,
    );
  }
  const data =
    typeof response.json === 'function'
      ? await response.json()
      : JSON.parse((result as any).body ?? '{}');
  const choice = data?.choices?.[0];
  const raw: string = choice?.message?.content ?? '';
  if (!raw && choice?.finish_reason)
    throw new Error(`the model sent nothing back (${choice.finish_reason})`);
  return raw;
}

// one JSON answer
export async function askJson(
  ctx: any,
  system: string,
  user: string | any[],
  temperature = 0.4,
  model = MODEL,
): Promise<any> {
  const raw = await askText(ctx, system, user, temperature, model, true);
  return parseLoose(raw);
}

// one JSON answer about a picture; the image is sent inline, since the
// model's servers may not be able to fetch a workspace file themselves
export async function askVision(
  ctx: any,
  system: string,
  text: string,
  imageUrl: string,
  model = 'google/gemini-2.5-flash',
): Promise<any> {
  const r = await fetch(imageUrl);
  if (!r.ok) throw new Error(`couldn't load the picture (${r.status})`);
  const blob = await r.blob();
  const buf = new Uint8Array(await blob.arrayBuffer());
  let bin = '';
  for (let i = 0; i < buf.length; i += 0x8000)
    bin += String.fromCharCode(...buf.subarray(i, i + 0x8000));
  const ext = imageUrl.split('?')[0].split('.').pop()?.toLowerCase();
  const mime = blob.type?.startsWith('image/')
    ? blob.type
    : ext === 'png'
      ? 'image/png'
      : ext === 'webp'
        ? 'image/webp'
        : 'image/jpeg';
  const content = [
    { type: 'text', text },
    {
      type: 'image_url',
      image_url: { url: `data:${mime};base64,${btoa(bin)}` },
    },
  ];
  return parseLoose(await askText(ctx, system, content, 0.2, model, true));
}

// a picture from words (and, to edit, the picture before), through the
// host's proxy: Gemini's image model, as for the Living Portraits
export async function makeImage(
  ctx: any,
  prompt: string,
  base: string | null,
  aspect = '4:3',
): Promise<{ blob: Blob; dataUrl: string }> {
  const content: any[] = [{ type: 'text', text: prompt }];
  if (base) content.push({ type: 'image_url', image_url: { url: base } });
  const result = await new SendRequestViaProxyCommand(ctx).execute({
    url: 'https://openrouter.ai/api/v1/chat/completions',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://boxel.ai',
      'X-Title': 'Survey lab',
    },
    requestBody: JSON.stringify({
      model: 'google/gemini-2.5-flash-image',
      modalities: ['image', 'text'],
      messages: [{ role: 'user', content }],
      ...(base ? {} : { image_config: { aspect_ratio: aspect } }),
    }),
  } as any);
  const response = (result as any)?.response ?? result;
  if (response?.ok === false) {
    let body = '';
    try {
      body = await response.text();
    } catch {
      body = '';
    }
    if (/token expired/i.test(body)) throw new Error(SESSION_EXPIRED);
    throw new Error(
      `the image model said ${response.status}: ${body.slice(0, 160)}`,
    );
  }
  const data =
    typeof response.json === 'function'
      ? await response.json()
      : JSON.parse((result as any).body ?? '{}');
  const img = data?.choices?.[0]?.message?.images?.[0];
  const url: string | undefined =
    img?.image_url?.url ?? img?.imageUrl?.url ?? img?.url;
  const m = url?.match(
    /^data:(image\/[a-zA-Z0-9.+-]+);base64,([A-Za-z0-9+/=]+)$/,
  );
  if (!m)
    throw new Error(
      data?.choices?.[0]?.message?.content
        ? 'the model answered in words instead of a picture'
        : 'no picture came back',
    );
  const bytes = Uint8Array.from(atob(m[2]), (c) => c.charCodeAt(0));
  return { blob: new Blob([bytes], { type: m[1] }), dataUrl: url! };
}

// JSON as models write it: maybe fenced, maybe wrapped in prose, maybe with
// raw newlines inside strings
export function parseLoose(raw: string): any {
  const text = raw
    .replace(/^\s*```(json)?/, '')
    .replace(/```\s*$/, '')
    .trim();
  const a = text.indexOf('{');
  const b = text.lastIndexOf('}');
  const tries = [text, a >= 0 && b > a ? text.slice(a, b + 1) : ''].filter(
    Boolean,
  );
  for (const t of tries) {
    for (const u of [t, escapeControlInStrings(t)]) {
      try {
        return JSON.parse(u);
      } catch {
        // next
      }
    }
  }
  console.warn('[survey-lab] not JSON:', raw.slice(0, 600));
  throw new Error('the answer was not JSON');
}

function escapeControlInStrings(t: string) {
  let out = '';
  let inStr = false;
  let esc = false;
  for (const ch of t) {
    if (inStr) {
      if (esc) esc = false;
      else if (ch === '\\') esc = true;
      else if (ch === '"') inStr = false;
      else if (ch === '\n') {
        out += '\\n';
        continue;
      } else if (ch === '\r') continue;
      else if (ch === '\t') {
        out += '\\t';
        continue;
      }
    } else if (ch === '"') inStr = true;
    out += ch;
  }
  return out;
}

// a path stored relative to a card ("../Stimuli/s1.png"), made absolute, so
// a copied or installed workspace keeps working
export const resolveUrl = (
  u: string | null | undefined,
  base: string | null | undefined,
): string => {
  if (!u) return '';
  try {
    return new URL(u, base || undefined).href;
  } catch {
    return u;
  }
};

export const toolCtx = (context: any) =>
  context?.toolContext ?? context?.commandContext;

// save one person's answers as a response card next to the question
export async function saveResponse(
  args: any,
  moduleHref: string,
  name: string,
  attributes: Record<string, any>,
): Promise<string> {
  const doc = {
    data: {
      type: 'card',
      attributes: { takenAt: new Date().toISOString(), ...attributes },
      relationships: { question: { links: { self: args.model.id } } },
      meta: { adoptsFrom: { module: moduleHref, name } },
    },
  };
  const store = args.context?.store;
  if (!store?.create)
    throw new Error(
      'this view cannot save cards; open the question from its workspace',
    );
  const id = await store.create(doc as any, {
    realm: args.model[realmURL]?.href,
  });
  if (typeof id !== 'string')
    throw new Error((id as any)?.message ?? 'the response could not be saved');
  return id;
}

export const lines = (raw: string | null | undefined) =>
  (raw ?? '')
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean);

export function parseJson<T>(raw: string | null | undefined, fallback: T): T {
  try {
    return raw ? (JSON.parse(raw) as T) : fallback;
  } catch {
    return fallback;
  }
}

export const secs = (ms: number) => `${(ms / 1000).toFixed(1)} s`;

// When the interview shows a tool inside its chat, it passes a host: the tool
// skips its own intro and tabs, uses the participant's name, and hands its
// summary back when it is done.
export interface ToolResult {
  summary: string;
  responseId: string;
  image?: string; // a picture the tool produced (Picture it), shown with its result
}
export interface ToolHost {
  respondent: string;
  done(result: ToolResult): void;
}
export const hostOf = (args: any): ToolHost | undefined =>
  args?.host ?? undefined;
