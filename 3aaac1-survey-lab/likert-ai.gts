// The adaptive Likert's interviewer: it places a person's own words on the
// scale, writes the in-between statements that fine-tune where they sit, and
// at the end turns the answers into a readout. Same model and proxy as the
// video question.
import { askJson } from './tool-kit';

const ask = askJson;

const clamp01 = (n: any) =>
  Math.min(1, Math.max(0, Number.isFinite(Number(n)) ? Number(n) : 0.5));

export const SCALE = [
  'Strongly disagree',
  'Disagree',
  'Somewhat disagree',
  'Neither',
  'Somewhat agree',
  'Agree',
  'Strongly agree',
];
// 0–1 on the axis to the classic 1–7
export const toPoint = (pos: number) => Math.round(clamp01(pos) * 6) + 1;
export const pointLabel = (pos: number) => SCALE[toPoint(pos) - 1];

// ─── ladders ─────────────────────────────────────────────────────────────
// A ladder is the questioner's own scale: concrete reference points, lowest
// first, evenly spaced from 0 to 1. Everyone answering that question is
// measured against the same rungs, so the numbers still add up.
export type ScaleKind = 'agree' | 'ladder';
export const rungAt = (i: number, n: number) => (n > 1 ? i / (n - 1) : 0.5);
// where a position sits, in the ladder's own words
export function ladderLabel(pos: number, rungs: string[]) {
  const n = rungs.length;
  if (n < 2) return '';
  const x = clamp01(pos) * (n - 1);
  const i = Math.round(x);
  if (Math.abs(x - i) < 0.2) return `about ${rungs[i]}`;
  const lo = Math.floor(x);
  return `between ${rungs[lo]} and ${rungs[lo + 1]}`;
}
export const labelFor = (
  pos: number,
  kind: ScaleKind | undefined,
  rungs: string[] | undefined,
) =>
  kind === 'ladder' && rungs && rungs.length > 1
    ? ladderLabel(pos, rungs)
    : pointLabel(pos);

const LADDER_WRITER = `You write a ladder for one survey question: concrete reference points, from the lowest to the highest, so a person can say where they sit by comparing with things they already know (like "bigger than a car, smaller than an elephant").
Rules: exactly N rungs; each under 8 words; every rung is the SAME kind of thing (all example apps, all animals, all prices…) so any two can be compared directly; concrete, never degree words like "somewhat", "a lot" or "not at all"; strictly increasing with clear steps, so nobody could argue two rungs are in the wrong order; roughly evenly spaced; recognisable to the audience in the context; the lowest is where almost everyone would be, the highest where almost no one would. Lowercase unless a proper noun; no full stops.
Answer ONLY with JSON: {"rungs": ["<lowest>", ..., "<highest>"]}`;

export async function writeLadder(
  ctx: any,
  question: string,
  brief: string,
  n = 7,
): Promise<string[]> {
  const j = await ask(
    ctx,
    LADDER_WRITER,
    `N: ${n}\nContext: ${brief || 'a market research survey'}\nQuestion: "${question}"`,
    0.6,
  );
  const rungs = Array.isArray(j?.rungs)
    ? j.rungs.map((r: any) => String(r).trim().slice(0, 80)).filter(Boolean)
    : [];
  if (rungs.length < 3) throw new Error('the ladder came back too short');
  return rungs;
}

const LADDER_PLACER = `You place a survey respondent on a ladder of reference points from their own words. Rungs are numbered from 0 (lowest). Answer with a rung number, using decimals for in between (e.g. 2.5 = halfway between rung 2 and rung 3). Be precise; read conditions and "but"s.
Also judge whether they sound frustrated, bored, or unwilling (e.g. "idk", "whatever", "stop asking"). Not knowing much is NOT frustration.
In "why", never mention rung numbers; name the rungs in words.
Answer ONLY with JSON: {"rung": <number>, "why": "<under 22 words, second person, quoting a few of their words and naming the rungs, e.g. You said 'only internal stuff', so past a team tracker but short of anything customers see>", "frustrated": <true|false>}`;

export async function placeOnLadder(
  ctx: any,
  question: string,
  rungs: string[],
  answer: string,
  brief: string,
): Promise<Placement> {
  const list = rungs.map((r, i) => `${i}: ${r}`).join('\n');
  const j = await ask(
    ctx,
    LADDER_PLACER,
    `Context: ${brief || 'a market research survey'}\nQuestion: "${question}"\nRungs:\n${list}\nTheir answer: "${answer}"`,
    0.2,
  );
  const r = Math.min(rungs.length - 1, Math.max(0, Number(j?.rung)));
  return {
    pos: Number.isFinite(r) ? r / (rungs.length - 1) : 0.5,
    why: String(j?.why ?? '').slice(0, 220),
    frustrated: Boolean(j?.frustrated),
  };
}

const ANCHOR_WRITER = `You write ONE new reference point for a ladder, to fine-tune where a respondent sits. You get the question, the full ladder, the two ends of the stretch they are in, and the respondent's own words.
Write a concrete example of the same kind as the rungs that sits between the two ends, at the given fraction of the way from the lower to the higher one. It must clearly be past the lower end and short of the higher end: someone comfortable with the higher end would accept it, someone only at the lower end would not. Under 10 words, same style as the rungs (lowercase, no full stop). Where it fits naturally, draw on the respondent's own world (their job, tools, situation) but do NOT restate their words. If earlier examples are listed, write a clearly different one.
Answer ONLY with JSON: {"example": "..."}`;

export async function ladderAnchor(
  ctx: any,
  question: string,
  rungs: string[],
  lower: string,
  higher: string,
  fraction: number,
  answer: string,
  brief: string,
  earlier: string[] = [],
): Promise<string> {
  const j = await ask(
    ctx,
    ANCHOR_WRITER,
    `Context: ${brief || 'a market research survey'}\nQuestion: "${question}"\nLadder (lowest first): ${rungs.join(' | ')}\nLower end: "${lower}"\nHigher end: "${higher}"\nFraction of the way up: ${fraction.toFixed(2)}\nTheir words: "${answer || '(none, they used the scale)'}"${earlier.length ? `\nEarlier examples (do not repeat): ${earlier.join(' / ')}` : ''}`,
    0.7,
  );
  return String(j?.example ?? '')
    .trim()
    .slice(0, 120);
}

// ─── 1. place their words on the scale ───────────────────────────────────
export interface Placement {
  pos: number; // 0 = strongly disagree … 1 = strongly agree
  why: string;
  frustrated: boolean;
}

const PLACER = `You place a survey respondent on an agreement scale from their own words.
The scale runs 0.0 (strongly disagree) to 1.0 (strongly agree); 0.5 is neither. Be precise: "yes but…" is not 1.0.
Also judge whether they sound frustrated, bored, or unwilling (e.g. "idk", "whatever", "stop asking", one word with irritation). Not knowing much is NOT frustration.
Answer ONLY with JSON: {"pos": <0..1>, "why": "<under 20 words, second person, quoting a few of their words, e.g. You said 'only for small things', so a little below agree>", "frustrated": <true|false>}`;

export async function place(
  ctx: any,
  statement: string,
  answer: string,
  brief: string,
): Promise<Placement> {
  const j = await ask(
    ctx,
    PLACER,
    `Context: ${brief || 'a market research survey'}\nStatement: "${statement}"\nTheir answer: "${answer}"`,
    0.2,
  );
  return {
    pos: clamp01(j?.pos),
    why: String(j?.why ?? '').slice(0, 200),
    frustrated: Boolean(j?.frustrated),
  };
}

// ─── 2. the in-between statements ────────────────────────────────────────
export interface Probe {
  low: { text: string; pos: number };
  high: { text: string; pos: number };
}

const PROBER = `You write two short first-person statements that a respondent can choose between, to fine-tune where they sit on an agreement scale about one statement.
The scale runs 0.0 (strongly disagree) to 1.0 (strongly agree). You get their current position, their own words, and the two target positions. Write one statement that someone at the LOW target would say and one at the HIGH target.
Rules: about the statement's topic, concrete and everyday (a situation or a condition, not just "I agree a bit more"); under 16 words each; neither should sound like the right answer.
Do NOT restate or paraphrase their own words in either statement: both must be new angles, equally close to what they said, so neither is the obvious pick. If earlier pairs are listed, use clearly different situations.
Answer ONLY with JSON: {"low": "...", "high": "..."}`;

export async function probe(
  ctx: any,
  statement: string,
  answer: string,
  pos: number,
  delta: number,
  brief: string,
  earlier: string[] = [],
): Promise<Probe> {
  const lo = clamp01(pos - delta);
  const hi = clamp01(pos + delta);
  const j = await ask(
    ctx,
    PROBER,
    `Context: ${brief || 'a market research survey'}\nStatement: "${statement}"\nTheir words: "${answer}"\nCurrent position: ${pos.toFixed(2)}\nLOW target: ${lo.toFixed(2)}\nHIGH target: ${hi.toFixed(2)}${earlier.length ? `\nEarlier pairs (do not repeat): ${earlier.join(' / ')}` : ''}`,
    0.7,
  );
  return {
    low: { text: String(j?.low ?? '').slice(0, 140), pos: lo },
    high: { text: String(j?.high ?? '').slice(0, 140), pos: hi },
  };
}

// ─── 3. the readout ──────────────────────────────────────────────────────
export interface LikertItem {
  statement: string;
  scale?: ScaleKind; // missing on early responses: agree
  rungs?: string[]; // the ladder, as it was when they answered
  landed?: string; // where they ended, in the ladder's words
  answer: string;
  aiPos: number | null;
  aiWhy: string;
  selfPos: number | null; // after they adjusted the AI's guess
  // agree: two statements either side. ladder: one new example, and whether
  // they are below it, about there, or above it
  probes: {
    low: string;
    high: string;
    anchor?: string;
    at?: number;
    picked: 'low' | 'high' | 'between' | 'below' | 'here' | 'above' | 'skip';
    ms: number;
  }[];
  final: number | null;
  point: number | null; // classic 1–7
  frustrated: boolean;
  skipped: boolean;
  ms: number; // time spent on this item
}

export interface LikertReadout {
  headline: string;
  for: string[];
  against: string[];
  leadWith: string;
  avoid: string;
  pitch: string;
  label: string;
}

const ANALYST = `You are a commercial research analyst writing for a marketer who wants to sell to ONE specific person. You get each statement they rated (some are ladders of concrete reference points instead of agree/disagree; where they sit on a ladder is the most sellable fact, e.g. 'trusts it up to dashboards, not customer-facing'): their own words, where an AI first placed them, where they moved themselves (the gap between those says how they see themselves), which in-between statements they picked, and their final 1–7 rating. Their words and their own adjustments outrank the AI's guess. If they were frustrated, say so briefly and lean on what they did answer.
Answer ONLY with JSON:
{"headline": "<one sentence: where this person stands>",
 "for": ["<what they are positive about, with the reason in their terms>", ...max 3],
 "against": ["<doubts or objections, in their terms>", ...max 3],
 "leadWith": "<what to open a pitch to them with>",
 "avoid": "<what not to say or do>",
 "pitch": "<a one or two sentence pitch written for this person>",
 "label": "<a friendly 2-4 word name for their stance, for them to keep>"}`;

export async function writeLikertReadout(
  ctx: any,
  brief: string,
  items: LikertItem[],
): Promise<LikertReadout> {
  const lines = items.map((it, i) => {
    if (it.scale === 'ladder' && it.rungs) {
      const r = it.rungs;
      const probes = it.probes
        .map((p) =>
          p.picked === 'skip'
            ? `skipped "${p.anchor}"`
            : `compared with "${p.anchor}" they said ${p.picked === 'here' ? 'about there' : p.picked}`,
        )
        .join('; ');
      return `${i + 1}. Question: "${it.statement}" (a ladder, lowest to highest: ${r.join(' | ')})\n  Said: "${it.answer || '(used the ladder only)'}"\n  AI placed: ${it.aiPos === null ? '–' : ladderLabel(it.aiPos, r)}; they moved it to: ${it.selfPos === null ? '–' : ladderLabel(it.selfPos, r)}${probes ? `\n  Fine-tuning: ${probes}` : ''}\n  Final: ${it.final === null ? 'skipped' : ladderLabel(it.final, r)}${it.frustrated ? ' (sounded frustrated)' : ''}`;
    }
    const probes = it.probes
      .map((p) => `between "${p.low}" and "${p.high}" they picked ${p.picked}`)
      .join('; ');
    return `${i + 1}. "${it.statement}"\n  Said: "${it.answer || '(used the slider only)'}"\n  AI placed: ${it.aiPos === null ? '–' : it.aiPos.toFixed(2)}; they moved it to: ${it.selfPos === null ? '–' : it.selfPos.toFixed(2)}${probes ? `\n  Fine-tuning: ${probes}` : ''}\n  Final: ${it.point ?? 'skipped'} of 7${it.frustrated ? ' (sounded frustrated)' : ''}`;
  });
  const j = await ask(
    ctx,
    ANALYST,
    `What the client wants to learn: ${brief || 'how this person feels'}\n\n${lines.join('\n')}`,
    0.5,
  );
  const list = (x: any) =>
    Array.isArray(x)
      ? x
          .map((s) => String(s))
          .filter(Boolean)
          .slice(0, 3)
      : [];
  return {
    headline: String(j?.headline ?? '').slice(0, 240),
    for: list(j?.for),
    against: list(j?.against),
    leadWith: String(j?.leadWith ?? '').slice(0, 300),
    avoid: String(j?.avoid ?? '').slice(0, 300),
    pitch: String(j?.pitch ?? '').slice(0, 400),
    label: String(j?.label ?? '').slice(0, 40),
  };
}

// words that mean "stop", without asking the model
export function soundsDone(answer: string) {
  const a = answer.trim().toLowerCase();
  return (
    a.length < 3 ||
    /^(idk|dunno|whatever|no idea|skip|stop|next|meh|pass)\b/.test(a)
  );
}

// a few plain sentences for the interviewer, one per statement
export function likertSummary(items: LikertItem[]) {
  const q = (s: string) => `"${s.length > 90 ? s.slice(0, 87) + '…' : s}"`;
  return items
    .map((it) => {
      if (it.skipped) return `${q(it.statement)}: skipped.`;
      const ladder = it.scale === 'ladder' && it.rungs?.length;
      const where = ladder
        ? `ended ${it.landed ?? labelFor(it.final ?? 0.5, it.scale, it.rungs)}`
        : it.point
          ? `${it.point}/7 (${SCALE[it.point - 1].toLowerCase()})`
          : 'no rating';
      const parts = [`${q(it.statement)}: ${where}.`];
      if (it.answer)
        parts.push(`In their words: "${it.answer.slice(0, 160)}".`);
      if (
        it.aiPos !== null &&
        it.selfPos !== null &&
        Math.abs(it.selfPos - it.aiPos) >= 0.12
      ) {
        parts.push(
          `They moved the AI's placement ${it.selfPos > it.aiPos ? 'up' : 'down'}${ladder ? '' : ` by ${Math.abs(toPoint(it.selfPos) - toPoint(it.aiPos))} point(s)`}.`,
        );
      }
      if (it.frustrated) parts.push('Seemed frustrated by it.');
      return parts.join(' ');
    })
    .join(' ');
}
