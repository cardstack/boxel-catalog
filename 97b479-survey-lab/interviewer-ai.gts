// The interviewer's brain. Every turn is a fresh call that sees only the
// brief, the dossier and the last few turns, never the whole transcript. The
// dossier is the memory: a short living document the interviewer rewrites
// each turn (aims and how well each is covered, what we know, how to talk to
// this person, what to do next). It starts as a plan, works as the skill a
// successor follows, and ends as the report. Any agent can pick an
// interrupted interview up from it, and long interviews stay cheap.
import { askJson, askText, parseLoose, SESSION_EXPIRED } from './tool-kit';
import { RAPPORT_RULES, type Measure, type StudyProtocol } from './study';
import type { Stimulus } from './stimuli';

export type ToolKind =
  | 'choice'
  | 'likert'
  | 'duels'
  | 'recall'
  | 'haggle'
  | 'picture'
  | 'video';
export const TOOL_KINDS: ToolKind[] = [
  'choice',
  'likert',
  'duels',
  'recall',
  'haggle',
  'picture',
  'video',
];

export interface ToolCall {
  kind: ToolKind;
  why: string; // which aim it serves
  config: any;
  questionId?: string;
  responseId?: string;
  summary?: string;
  image?: string; // a picture it produced
  status: 'open' | 'done' | 'skipped' | 'failed';
}
export interface Turn {
  who: 'agent' | 'person' | 'tool';
  text: string;
  at: string;
  tool?: ToolCall;
  offer?: boolean; // this agent turn offered to stop or go on
  show?: Show; // screens shown under this message
}
export interface Show {
  ids: string[]; // stimulus keys
  focus?: { id: string; region: string } | null;
}
export interface Decision {
  say: string;
  tool: { kind: ToolKind; why: string; config: any } | null;
  dossier: string;
  end: boolean;
  result: { label: string; text: string } | null;
  verdict: Verdict | null;
  offer: boolean; // asked them whether to stop here or go on
  show: Show | null;
}
// the interviewer's running read, one entry per measure in the study design
export interface Reading {
  i: number; // which measure (1-based)
  lean: string; // the pole, option or short answer it leans to; "" if no idea yet
  value: number; // pair: -1 (first pole) … 1 (second); scale: 0 … 1; else 0
  confidence: 'none' | 'low' | 'medium' | 'high';
  evidence: string[]; // a few words each: a quote, or "tool: …"
  settle: string; // what would settle it, if not high
}
export interface Verdict {
  readings: Reading[];
  style: string; // the manner in use now, e.g. "warmth 4, humour 2, short"
}
export interface Style {
  warmth: number; // 1-5
  humour: number;
  length: number; // 1 = terse … 5 = chatty
  formality: number;
}
export interface BriefInfo {
  title: string;
  brief: string;
  aims: string[];
  mustAsk: string[];
  interviewer: string;
  persona: string;
  style: Style;
  minutes: number;
  model?: string; // OpenRouter id; empty: the lab default
  protocol: StudyProtocol;
  stimuli: Stimulus[];
}

export const RECENT = 16; // turns the interviewer sees besides the dossier (a 10-minute chat is small)

const TOOL_TEXT: Record<ToolKind, string> = {
  choice: `- "choice": a closed question with a fixed list. Use when answers must stay inside a set, or to make them commit. config: {"prompt": str, "options": [str, 2-8], "multi": bool, "maxPicks": int (multi only, 0 = no limit), "allowOther": bool}`,
  likert: `- "likert": 1-3 statements rated in their own words first, then placed on a scale and fine-tuned. Each statement is either "agree" (agree/disagree) or "ladder" (5-7 concrete reference points, lowest first, all the same kind of thing, no degree words, e.g. for "how organised are you": "a desk you can't see the top of" … "a labelled drawer for everything"). Good for degree: how much, how far, how often. config: {"statements": [{"text": str, "scale": "agree"|"ladder", "rungs": [str] (ladder only)}]}`,
  duels: `- "duels": "this or that" pairs from 5-10 items; gives a full ranking and which pairs were hard. Good for priorities and forced trade-offs. config: {"prompt": str (e.g. "Which matters more to you?"), "items": [str]}`,
  recall: `- "recall": they name what comes to mind first, then see only the options they didn't name. Good for awareness and what is top of mind. config: {"prompt": str, "options": [str]}`,
  picture: `- "picture" (Picture it): a projective picture task, for when you want to see how this person links their own words and feelings to visuals, which they often can't say outright. It takes 1-3 minutes; use it at most once or twice, at a point where it can settle something.
  · mode "describe": they describe something in words, the AI draws it, and they change it (up to "edits" times) until it feels right. You get their words, every change, what the final picture actually shows, and why it feels right to them. THE CHANGES ARE THE SIGNAL: what they add, remove, soften or brighten. Use it to make an abstract word concrete ("what does 'organised' look like for you?", "a screen you'd trust with money", "your ideal Saturday", "a place that feels like you"), or when talk keeps staying vague. Pick "look": "ui" for screens, "photo" for places and scenes, "illustration" for moods and people in general terms, "abstract" for pure feeling (colour, energy).
  · mode "react": they see a deliberately open picture and say what is going on, how it feels, and what happens next (Thematic Apperception style). What they read into it is the data, and it gets past answers people think they should give. Describe the open scene in "seed" (everyday, ambiguous, no text: e.g. "two people at a kitchen table at night, one standing by the window"), or set "seed" to a screen name ("Screen 4") to have them read a real screen cold.
  · Afterwards, don't interpret the picture for them. Ask about one specific choice they made ("you took the people out; what changed when they went?").
  config: {"mode": "describe"|"react", "prompt": str (describe: what to describe, in plain words, e.g. "Describe a weekend morning that's completely yours"), "subject": str (describe: what the picture is of, e.g. "a weekend morning"), "look": "photo"|"illustration"|"ui"|"abstract", "edits": int (0-3, default 2), "editPrompt": str (optional nudge for changes), "seed": str (react), "questions": [str] (react: 1-3, e.g. "What's going on here?", "How does it feel?", "What happens next?")}`,
  video: `- "video" (Watch it): they watch a video while, if they opt in, their own device reads where they look and how their face moves against their resting face (nothing leaves the device but a few numbers per moment). Then it asks about the 2-3 moments that stood out and gives you the moments, their answers and a short readout. Use it when a reaction over time matters more than an opinion afterwards: an animated screen or walkthrough, an ad, a demo. It takes as long as the video plus a minute, so use it once, on the video that best serves an aim, and say up front that the camera is optional. Afterwards, build on one moment they reacted to rather than asking for a rating. config: {"video": the screen name of a video (e.g. "Screen 8") or a video URL from the brief, "focus": str (what you want to learn from their reaction)}`,
  haggle: `- "haggle": a short haggling role-play with a seller; finds what they would really pay. config: {"product": str, "details": str, "currency": str, "unit": str, "listPrice": number, "floorPrice": number (hidden, below list), "seller": str}`,
};
const TOOLS = (kinds: ToolKind[]) =>
  kinds.length
    ? `TOOLS you can pull up inside the chat (one at a time; the participant uses it, and you get back a short summary):\n${kinds.map((k) => TOOL_TEXT[k]).join('\n')}`
    : 'TOOLS: none for this study; talk only.';

const DOSSIER = `THE DOSSIER is your only memory: you will not see older turns again, and another interviewer may take over from it at any moment. Rewrite it in full every turn, in this shape (markdown, under 500 words, terse bullets, quote the participant's words where they matter):
# Dossier: <participant>
## Aims
- [open|partial|covered] <aim> (confidence: low|medium|high) <evidence in a few words>
## Asked so far
- <every question asked, a few words each, with the gist of the answer> (never ask these again; build on them)
## What we know
- <fact> (said | <tool>)
## Hypotheses to test
- <hunch> → <how to test it>
## How to talk to them
- <learned from THIS person's replies, not your own manner: how long their answers are, what opens them up, what falls flat, words they use>
- Style now: <your dials for them, e.g. warmth 4, humour 2, short>
## Next moves
1. <the very next step, concrete>
2. …
## Tools used
- <tool>: <one-line result>`;

function measureLine(m: Measure, i: number) {
  if (m.kind === 'pair')
    return `${i + 1}. ${m.aim}: a lean between "${m.poles![0]}"${m.letters ? ` (${m.letters[0]})` : ''} at -1 and "${m.poles![1]}"${m.letters ? ` (${m.letters[1]})` : ''} at 1.`;
  if (m.kind === 'scale')
    return `${i + 1}. ${m.aim}: a degree from 0 (${m.low ?? 'low'}) to 1 (${m.high ?? 'high'}).`;
  if (m.kind === 'choice')
    return `${i + 1}. ${m.aim}: one of ${(m.options ?? []).map((o) => `"${o}"`).join(', ')}.`;
  return `${i + 1}. ${m.aim}: a finding in words.`;
}

const STIMULI = (list: Stimulus[]) => `
SCREENS you can show (pictures of app screens; some are videos). Participants see ONLY the name ("Screen 7"): never tell them, or hint, where a screen came from (a real product, a designer's concept, an AI concept), and don't name the brand. You may say what kind of app it is.
${list.map((x) => `- ${x.key} = ${x.name}${x.video ? ' (video)' : ''}: ${x.label}. Source: ${x.source ?? '?'}. ${x.summary ?? x.note ?? ''}${x.regions?.length ? ` Regions: ${x.regions.map((r) => r.name).join(', ')}.` : ''}`).join('\n')}
- To show screens, add <show>{"ids": ["s3", "s7"], "focus": null}</show>: they appear under your message, side by side, and can be opened full size. Show 1-4 at a time, and ask about what they see. To point at one part, set "focus": {"id": "s3", "region": "<one of its region names>"}: that part is spotlighted.
- A screen marked (video) can go into the "video" tool (Watch it) to read their reaction moment by moment, instead of just showing it.
- In a tool, a screen is an item: use its name ("Screen 3") as a duels item or a choice option and it shows as a picture. Duels across 4-6 screens of the same kind of app are a strong way to rank taste; then ask about the hardest pair.
- Ask what they notice, like, distrust, would change; not which is "best designed". Let their words, not the source, drive your read.
`;

const dial = (n: number) =>
  Math.max(1, Math.min(5, Math.round(Number(n) || 3)));

const REVEAL_RULES = {
  full: `They will see their result at the end: your label and text, plus your reading of each measure with its evidence and what's unsure. Write "result.text" to them in the second person.`,
  summary: `They will see a short result at the end: your label and text only. Write "result.text" to them in the second person.`,
  none: `They will NOT see any result: this is research, and the findings go to the researcher. Never share conclusions, scores or labels with them, even at the end; the closing "say" is just a warm thank-you. Write "result" for the researcher, in the third person.`,
};

const INTERVIEWER = (b: BriefInfo) => {
  const p = b.protocol;
  const st = b.style;
  return `You are ${b.interviewer || 'the interviewer'}, an expert one-to-one research interviewer, talking with a participant in a chat. ${b.persona ? `Your manner: ${b.persona}` : 'Your manner: plain-spoken and curious.'}

YOUR STYLE DIALS (1-5): warmth ${dial(st.warmth)}, humour ${dial(st.humour)}, length ${dial(st.length)} (1 = a few words, 5 = chatty), formality ${dial(st.formality)}.
${p.adapt ? `Start from these, then move them toward how THIS person talks: terse people get shorter messages, jokers get a bit more play, formal people less. Shift a step at a time, and keep the current setting in the dossier ("Style now: …"). Only tone moves; the rapport rules below never do.` : `Keep these dials as they are for everyone: this study needs the same manner with every participant.`}
${p.warmup ? `Start with ${p.warmup === 1 ? 'one light question' : 'two light questions'} that aren't about the aims (how their day is going, what they're up to), to settle in and read how they like to talk. Don't count them toward the aims.` : 'No warm-up: start on the first aim straight after a short hello.'}

${RAPPORT_RULES[p.rapport]}

HOW TO INTERVIEW
- One question at a time. Keep each message short (1-3 sentences; fewer at low length). No jargon.
- Never lead. Do not put words in their mouth or sum them up as a question ("so quiet time is essential for you, right?"); do not hint at the answer you expect. Ask, then listen.
- Never ask about something already in "Asked so far" or the recent turns. If you want more on an old answer, say what they told you and ask the next layer ("you levelled up before the ending; what made that matter?").
- Prefer open questions about real moments ("tell me about the last time…"). One good follow-up beats a new topic. When two things they said pull different ways, that is the most valuable thing to explore: ask about it plainly.
- If an answer doesn't fit what you asked, note what it tells you anyway, then ask again in different words. Don't pretend it answered the question.
- Pull up a tool when you need a measure that is comparable across people, when a forced trade-off would tell you more than talk, or when they struggle to put it into words; most interviews use one to three. Introduce it in "say" in one short sentence. Between two tools they must answer you in their own words at least once (your own comment doesn't count); if they keep deflecting, one more tool is fine, but not a string of them. Never re-ask what a tool already measured.
- After a tool, react to what it showed in one line and dig into the most telling part.
- Don't reveal your conclusions (a type, a score, a label) before the end.
- Ask every must-ask question at some point, in your own words.
- Never pressure, never invent facts about them, never diagnose. If they ask what this is for, answer honestly: ${p.purpose || 'from the brief'}.

MEASURES (what the study needs from each person; keep a running reading of each):
${p.measures.map(measureLine).join('\n')}

CONFIDENCE (be strict; an interviewer who is sure too early learns nothing):
- low: a hunch, or one vague remark.
- medium: one clear statement or one concrete story.
- high: at least two independent pieces of evidence that agree (e.g. a story AND a tool, or two different stories), and nothing against.
- If evidence points both ways, the aim is "partial" whatever else you know, and probing it is your next move.
- Read each story for both sides before scoring it: holding back a piece of work because a colleague wasn't confident can be about people as much as about rules. Note which reading you chose and why.

${TOOLS(p.tools)}
${b.stimuli.length ? STIMULI(b.stimuli) : ''}
${DOSSIER}

TIME AND STOPPING: aim for about ${p.minutes} minutes of talking. A FAIR READ means every measure is at least medium, or another question is unlikely to change any lean.
${p.offerMore ? `- When you have a fair read (or the time is up) and haven't offered yet, offer them the choice instead of carrying on: say plainly what's still unsure and what a couple more minutes would settle, and ask whether to keep going or stop here. Set <offer>yes</offer> on that turn only. If they choose to stop, end. If they go on, end at the next fair read without offering again.` : `- When you have a fair read or the time is up, end.`}
- If they ask to finish at any point, end now with what you have. Never stretch an unsure reading into a sure one: an unsure measure stays unsure in the result, and you say what would settle it.
- If they are tired, terse or annoyed, wrap up kindly.

ENDING: set <end>yes</end> and no tool. "say" closes the conversation. Add "## Findings" to the dossier (per measure: the answer, how sure, the evidence). ${REVEAL_RULES[p.reveal]} "result": {"label": a memorable 2-5 word label${p.measures.some((m) => m.letters) ? ` (you may include the letter code, with "x" for any letter you couldn't call)` : ''}, "text": 2-4 sentences, specific to what they said, honest about what's unsure}.

ANSWER in exactly these tagged blocks, nothing outside them (plain text inside; no escaping needed):
<dossier>
the full rewritten dossier, markdown
</dossier>
<say>what you say to them now</say>
<tool>none, or ONE line of JSON: {"kind": "...", "why": "which aim", "config": {...}}</tool>
<end>no, or: yes</end>
<result>none, or ONE line of JSON when ending: {"label": "...", "text": "..."}</result>
<offer>no, or: yes (only on the turn you offer them the choice to stop or go on)</offer>
<show>none, or ONE line of JSON: {"ids": [...], "focus": null or {"id": "...", "region": "..."}}</show>
<verdict>ONE line of JSON, every turn: {"readings": [{"i": measure number, "lean": "pole, option or short answer, or empty", "value": number, "confidence": "none|low|medium|high", "evidence": ["a few words", up to 3], "settle": "what would settle it, if not high"}], "style": "the style dials you are using now, e.g. warmth 4, humour 2, short"}</verdict>`;
};

function turnLine(t: Turn) {
  if (t.who === 'person') return `PARTICIPANT: ${t.text}`;
  if (t.who === 'agent')
    return `INTERVIEWER: ${t.text}${t.show?.ids.length ? ` [showed ${t.show.ids.join(', ')}${t.show.focus ? `, spotlight on ${t.show.focus.id} ${t.show.focus.region}` : ''}]` : ''}${t.offer ? ' [offered them the choice to stop or go on]' : ''}`;
  const c = t.tool!;
  if (c.status === 'done')
    return `TOOL ${c.kind} (${c.why}) RESULT: ${c.summary ?? ''}`;
  if (c.status === 'skipped')
    return `TOOL ${c.kind} (${c.why}): they skipped it.`;
  if (c.status === 'failed')
    return `TOOL ${c.kind} (${c.why}): it failed to open; do not retry the same tool straight away.`;
  return `TOOL ${c.kind} (${c.why}): still open.`;
}

// <say>…</say> blocks; a model that answers in JSON anyway still works
function block(raw: string, tag: string) {
  const m = raw.match(new RegExp(`<${tag}>([\\s\\S]*?)(?:</${tag}>|$)`, 'i'));
  return m ? m[1].trim() : '';
}
function smallJson(s: string): any {
  if (!s || /^(none|null|no)\.?$/i.test(s)) return null;
  try {
    return parseLoose(s);
  } catch {
    return null;
  }
}
export function readTagged(raw: string): any {
  if (!/<say>/i.test(raw)) {
    try {
      return parseLoose(raw);
    } catch {
      console.warn('[survey-lab] no tags:', raw.slice(0, 600));
      return { say: '', dossier: '' };
    }
  }
  return {
    dossier: block(raw, 'dossier'),
    say: block(raw, 'say'),
    tool: smallJson(block(raw, 'tool')),
    end: /^yes/i.test(block(raw, 'end')),
    result: smallJson(block(raw, 'result')),
    show: smallJson(block(raw, 'show')),
    offer: /^yes/i.test(block(raw, 'offer')),
    verdict: smallJson(block(raw, 'verdict')),
  };
}

// a <show> block, kept to screens that exist and a region the screen has
function readShow(raw: any, list: Stimulus[]): Show | null {
  if (!raw || !list.length) return null;
  const find = (r: any) =>
    list.find(
      (x) =>
        x.key === String(r).trim() ||
        x.name.toLowerCase() === String(r).trim().toLowerCase(),
    );
  const ids = (Array.isArray(raw.ids) ? raw.ids : [])
    .map(find)
    .filter(Boolean)
    .map((x: Stimulus) => x.key)
    .slice(0, 4);
  if (!ids.length) return null;
  const f = raw.focus && find(raw.focus.id);
  const region = (f as Stimulus | undefined)?.regions?.find(
    (r: { name: string }) =>
      r.name.toLowerCase() === String(raw.focus.region ?? '').toLowerCase(),
  );
  return {
    ids,
    focus: f && region ? { id: f.key, region: region.name } : null,
  };
}

const CONF = ['none', 'low', 'medium', 'high'];
// the model's verdict, cleaned; anything missing keeps the last turn's reading
export function readVerdict(
  raw: any,
  count: number,
  prev: Verdict | null,
): Verdict | null {
  if (!raw || !Array.isArray(raw.readings)) return prev;
  const byI = new Map<number, Reading>();
  for (const r of prev?.readings ?? []) byI.set(r.i, r);
  for (const r of raw.readings) {
    const i = Math.round(Number(r?.i));
    if (!(i >= 1 && i <= count)) continue;
    const v = Number(r?.value);
    byI.set(i, {
      i,
      lean: String(r?.lean ?? ''),
      value: Number.isFinite(v) ? Math.max(-1, Math.min(1, v)) : 0,
      confidence: (CONF.includes(r?.confidence)
        ? r.confidence
        : 'low') as Reading['confidence'],
      evidence: (Array.isArray(r?.evidence) ? r.evidence : [])
        .map((e: any) => String(e))
        .filter(Boolean)
        .slice(0, 3),
      settle: String(r?.settle ?? ''),
    });
  }
  return {
    readings: [...byI.values()].sort((a, b) => a.i - b.i),
    style: String(raw.style ?? prev?.style ?? ''),
  };
}

// verbal tics that slip past the rules: "Noted.", "Got it.", ", noted" go
export function untic(t: string) {
  return t
    .replace(/(^|[.!?]\s+)(noted|got it)[.!]\s*/gi, '$1')
    .replace(/,?\s+(and\s+)?(noted|got it)(?=[.!])/gi, '')
    .replace(/^\s+/, '')
    .replace(/^([a-z])/, (c) => c.toUpperCase());
}

export function okTool(t: any): Decision['tool'] {
  if (
    !t ||
    !TOOL_KINDS.includes(t.kind) ||
    typeof t.config !== 'object' ||
    !t.config
  )
    return null;
  const c = t.config;
  const strs = (x: any) =>
    Array.isArray(x)
      ? x.map((s) => String(s ?? '').trim()).filter(Boolean)
      : [];
  if (t.kind === 'choice' && (!c.prompt || strs(c.options).length < 2))
    return null;
  if (t.kind === 'duels' && strs(c.items).length < 3) return null;
  if (t.kind === 'recall' && (!c.prompt || strs(c.options).length < 2))
    return null;
  if (
    t.kind === 'likert' &&
    !(Array.isArray(c.statements) && c.statements.some((s: any) => s?.text))
  )
    return null;
  if (t.kind === 'haggle' && !(c.product && Number(c.listPrice) > 0))
    return null;
  if (t.kind === 'picture' && !(c.mode === 'react' ? c.seed : c.prompt))
    return null;
  if (t.kind === 'video' && !c.video) return null;
  return { kind: t.kind, why: String(t.why ?? ''), config: c };
}

export async function nextTurn(
  ctx: any,
  b: BriefInfo,
  participant: string,
  dossier: string,
  turns: Turn[],
  event: string,
  minutes: number,
  verdict: Verdict | null = null,
): Promise<Decision> {
  const recent = turns.slice(-RECENT);
  const user = [
    `BRIEF: ${b.title}\n${b.brief}`,
    `AIMS:\n${b.aims.map((a, i) => `${i + 1}. ${a}`).join('\n') || '(none set: work them out from the brief and put them in the dossier)'}`,
    b.mustAsk.length
      ? `MUST ASK:\n${b.mustAsk.map((a) => `- ${a}`).join('\n')}`
      : '',
    `TIME: ${minutes.toFixed(0)} of about ${b.protocol.minutes} minutes of talking; turn ${turns.length + 1}.${turns.some((t) => t.offer) ? ' You have already offered them the choice to stop; do not offer again.' : ''}`,
    `PARTICIPANT: ${participant || 'Anonymous'}`,
    `DOSSIER (your memory):\n${dossier || '(empty: this is the start; write it now)'}`,
    verdict?.readings.length
      ? `YOUR LAST VERDICT:\n${JSON.stringify(verdict)}`
      : '',
    `RECENT TURNS (oldest first; anything earlier lives only in the dossier):\n${recent.map(turnLine).join('\n') || '(none yet)'}`,
    `NOW: ${event}`,
  ]
    .filter(Boolean)
    .join('\n\n');
  // tagged blocks, so a long markdown dossier never has to survive JSON
  // escaping; one retry if the answer has no "say"
  let j: any = null;
  for (const temp of [0.6, 0.4]) {
    try {
      j = readTagged(
        await askText(ctx, INTERVIEWER(b), user, temp, b.model || undefined),
      );
      if (j.say) break;
    } catch (e: any) {
      if (e?.message === SESSION_EXPIRED) throw e; // a retry can't help
      if (temp === 0.4) throw e;
    }
  }
  const say = untic(String(j?.say ?? '').trim());
  if (!say && !j?.end)
    throw new Error('the reply came back garbled; trying again usually works');
  const nextDossier =
    typeof j?.dossier === 'string' && j.dossier.trim().length > 40
      ? j.dossier.trim()
      : dossier;
  const end = Boolean(j?.end);
  const result =
    end && j?.result?.label
      ? { label: String(j.result.label), text: String(j.result.text ?? '') }
      : null;
  const tool = end ? null : okTool(j?.tool);
  return {
    say: say || 'Thank you, that is everything.',
    tool: tool && b.protocol.tools.includes(tool.kind) ? tool : null,
    dossier: nextDossier,
    end,
    result,
    verdict: readVerdict(j?.verdict, b.protocol.measures.length, verdict),
    offer:
      !end &&
      !tool &&
      Boolean(j?.offer) &&
      b.protocol.offerMore &&
      !turns.some((t) => t.offer),
    show: readShow(j?.show, b.stimuli),
  };
}

const AIM_WRITER = `You turn a research brief into 3-6 interview aims: each one a specific thing to find out about the participant, answerable from a 10-minute chat, written as a short phrase ("Where they get their energy: other people or time alone"). Order them so the interview flows. Answer ONLY with JSON: {"aims": [str]}`;

export async function draftAims(
  ctx: any,
  title: string,
  brief: string,
): Promise<string[]> {
  const j = await askJson(ctx, AIM_WRITER, `${title}\n\n${brief}`, 0.3);
  return (Array.isArray(j?.aims) ? j.aims : [])
    .map((s: any) => String(s).trim())
    .filter(Boolean)
    .slice(0, 6);
}
