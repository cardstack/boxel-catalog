// The interviewer: a fast vision model through the host's request proxy,
// always answering in a fixed JSON shape. It asks about the moments the face
// (or the pause button) flagged, then turns the whole response into a
// readout for whoever is selling to this person.
import SendRequestViaProxyCommand from '@cardstack/boxel-host/tools/send-request-via-proxy';
import { clock, KIND_WORDS } from './face-signals';
import type { Bin, Moment } from './face-signals';

export const MODEL = 'google/gemini-2.5-flash';

async function proxyJson(result: any): Promise<any> {
  const response = result?.response ?? result;
  const ok = response?.ok ?? (response?.status ?? 200) < 400;
  if (!ok) {
    let body = '';
    try {
      body =
        typeof response.text === 'function'
          ? await response.text()
          : String(result.body ?? '');
    } catch {
      body = '';
    }
    throw new Error(
      `the interviewer said ${response.status ?? '?'}: ${body.slice(0, 200)}`,
    );
  }
  if (typeof response.json === 'function') return response.json();
  if (typeof result.body === 'string') return JSON.parse(result.body);
  if (typeof response.body === 'string') return JSON.parse(response.body);
  return response;
}

async function ask(ctx: any, system: string, content: any[]): Promise<any> {
  const result = await new SendRequestViaProxyCommand(ctx).execute({
    url: 'https://openrouter.ai/api/v1/chat/completions',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'HTTP-Referer': 'https://boxel.ai',
      'X-Title': 'Survey lab',
    },
    requestBody: JSON.stringify({
      model: MODEL,
      response_format: { type: 'json_object' },
      temperature: 0.6,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content },
      ],
    }),
  } as any);
  const data = await proxyJson(result);
  const raw: string = data?.choices?.[0]?.message?.content ?? '';
  return JSON.parse(raw.replace(/^```(json)?|```$/g, '').trim());
}

export interface FollowUp {
  t: number;
  kind: string;
  question: string;
  answer: string;
}

const INTERVIEWER = `You are a warm, neutral market-research interviewer. Someone just watched a video. On their own device, the webcam noticed a few moments where their face or attention changed; for some moments nothing was noticed and the moment was simply picked.
For each moment you get the time, what the face did (or that it was picked), and the video frame at that moment. Write ONE short open question per moment (under 25 words) that:
- names the moment by what is on screen (look at the frame), and its time;
- mentions the face only lightly and never as a fact about feelings ("your expression changed", "you seemed to react", not "you loved it");
- is open (what, how), never leading, never yes/no.
Answer ONLY with JSON: {"questions": [{"t": <seconds>, "question": "..."}]} in the same order as the moments.`;

export async function writeFollowUps(
  ctx: any,
  brief: string,
  moments: Moment[],
  frames: string[],
): Promise<FollowUp[]> {
  const content: any[] = [
    {
      type: 'text',
      text: `What the client wants to learn: ${brief || 'how people react to this video'}.`,
    },
  ];
  moments.forEach((m, i) => {
    content.push({
      type: 'text',
      text: `Moment ${i + 1}: ${clock(m.t)} (${m.t}s), ${KIND_WORDS[m.kind]}.`,
    });
    if (frames[i])
      content.push({ type: 'image_url', image_url: { url: frames[i] } });
  });
  const json = await ask(ctx, INTERVIEWER, content);
  const qs: any[] = Array.isArray(json?.questions) ? json.questions : [];
  return moments.map((m, i) => ({
    t: m.t,
    kind: m.kind,
    question: String(
      qs[i]?.question ??
        `What was going through your mind around ${clock(m.t)}?`,
    )
      .trim()
      .slice(0, 220),
    answer: '',
  }));
}

export interface Readout {
  headline: string;
  landed: string[];
  lost: string[];
  leadWith: string;
  avoid: string;
  pitch: string;
  label: string;
}

const ANALYST = `You are a commercial research analyst writing for a marketer who wants to sell to ONE specific person. You get: what the client wants to learn, a per-second summary of that person's reaction while watching a video (attention, smiles, raised brows, frowns, all measured against their own resting face), the moments that stood out with frames, and the person's own answers.
Rules: their own words outrank the face; a face signal is a hint, never proof of a feeling. Be concrete and short. Never invent facts about the person beyond this data.
Answer ONLY with JSON:
{"headline": "<one sentence: how this person took the video>",
 "landed": ["<moment or element that worked for them, with time>", ...max 3],
 "lost": ["<where attention or interest dropped, with time>", ...max 3],
 "leadWith": "<what to open a pitch to this person with>",
 "avoid": "<what not to do with them>",
 "pitch": "<a one or two sentence pitch written for this person>",
 "label": "<a friendly 2-4 word name for how they watch, e.g. 'Detail Spotter', for them to keep>"}`;

export function summarise(bins: Bin[], duration: number): string {
  // one line per second: t, face %, on-video %, smile, surprise, frown
  const lines: string[] = [];
  for (let s = 0; s < Math.ceil(duration); s++) {
    const bs = bins.filter((b) => b.t >= s && b.t < s + 1);
    if (!bs.length) continue;
    const avg = (f: (b: Bin) => number) =>
      bs.reduce((a, b) => a + f(b), 0) / bs.length;
    const on =
      bs[0].on === null ? '–' : Math.round(avg((b) => b.on ?? 0) * 100);
    lines.push(
      `${s}s face ${Math.round(avg((b) => b.face) * 100)} on ${on} smile ${avg((b) => b.smile).toFixed(2)} surprise ${avg((b) => b.surprise).toFixed(2)} frown ${avg((b) => b.frown).toFixed(2)}`,
    );
  }
  return lines.join('\n');
}

export async function writeReadout(
  ctx: any,
  brief: string,
  bins: Bin[],
  duration: number,
  followUps: FollowUp[],
  frames: string[],
  camera: boolean,
): Promise<Readout> {
  const content: any[] = [
    {
      type: 'text',
      text: `What the client wants to learn: ${brief || 'how people react to this video'}.`,
    },
    {
      type: 'text',
      text: camera
        ? `Reaction per second (face = share of time a face was seen, on = share looking at the video, or – without calibration):\n${summarise(bins, duration)}`
        : 'The camera was off: there is no face data, only their answers.',
    },
  ];
  followUps.forEach((f, i) => {
    content.push({
      type: 'text',
      text: `At ${clock(f.t)} (${KIND_WORDS[f.kind as keyof typeof KIND_WORDS] ?? f.kind}). Asked: ${f.question} They said: ${f.answer || '(skipped)'}`,
    });
    if (frames[i])
      content.push({ type: 'image_url', image_url: { url: frames[i] } });
  });
  const j = await ask(ctx, ANALYST, content);
  const list = (x: any) =>
    Array.isArray(x)
      ? x
          .map((s) => String(s))
          .filter(Boolean)
          .slice(0, 3)
      : [];
  return {
    headline: String(j?.headline ?? '').slice(0, 240),
    landed: list(j?.landed),
    lost: list(j?.lost),
    leadWith: String(j?.leadWith ?? '').slice(0, 300),
    avoid: String(j?.avoid ?? '').slice(0, 300),
    pitch: String(j?.pitch ?? '').slice(0, 400),
    label: String(j?.label ?? '').slice(0, 40),
  };
}
