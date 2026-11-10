// The study design: how one brief's interviews behave and what each person
// sees. A fun self-reflection study (the 16 types) and a product study (the
// Taste Test) want different things: whether the participant gets a result,
// how much warmth the interviewer can afford before it skews answers, whether
// the aims and notes are visible, when to stop. A designer agent drafts it
// from the brief; the researcher adjusts it on the brief.
import { askJson } from './tool-kit';
import type { ToolKind } from './interviewer-ai';

const TOOL_KINDS: ToolKind[] = [
  'choice',
  'likert',
  'duels',
  'recall',
  'haggle',
  'picture',
  'video',
]; // kept here so the two modules don't import each other's values

export type Reveal = 'full' | 'summary' | 'none';
export type Rapport = 'strict' | 'balanced' | 'warm';
export type MeasureKind = 'pair' | 'scale' | 'choice' | 'open';

// what one aim is measured as, so the running verdict can be drawn and
// totalled across people
export interface Measure {
  aim: string;
  kind: MeasureKind;
  poles?: [string, string]; // pair: the two ends ("time alone", "other people")
  letters?: [string, string]; // pair, optional: a code letter for each end ("I", "E")
  low?: string; // scale: what 0 means
  high?: string; // scale: what 1 means
  options?: string[]; // choice: the possible answers
}

export interface StudyProtocol {
  purpose: string; // what participants are told this is for
  intro: string; // the start screen's line
  reveal: Reveal; // what the participant sees at the end
  rapport: Rapport; // how much warmth the interviewer may use
  adapt: boolean; // the interviewer shifts its style toward the participant
  warmup: number; // light questions first, not about the aims (0-2)
  showNotes: boolean; // the participant can open the interviewer's notes
  showAims: boolean; // the participant sees which aims are covered
  minutes: number; // the time to aim for
  offerMore: boolean; // with a fair read, offer to stop or go on, rather than run on
  tools: ToolKind[];
  measures: Measure[];
  rationale: string; // why the designer chose these settings
}

const asReveal = (x: any): Reveal =>
  ['full', 'summary', 'none'].includes(x) ? x : 'full';
const asRapport = (x: any): Rapport =>
  ['strict', 'balanced', 'warm'].includes(x) ? x : 'balanced';
const asKind = (x: any): MeasureKind =>
  ['pair', 'scale', 'choice', 'open'].includes(x) ? x : 'open';
const strs = (x: any) =>
  Array.isArray(x) ? x.map((s) => String(s ?? '').trim()).filter(Boolean) : [];

// whatever was stored (or nothing), made whole: missing settings fall back to
// what suits a short, friendly interview
export function readProtocol(
  raw: string | null | undefined,
  b: { aims?: string[]; minutes?: number } = {},
): StudyProtocol {
  let p: any = {};
  try {
    p = raw ? JSON.parse(raw) : {};
  } catch {
    p = {};
  }
  const measures: Measure[] = (Array.isArray(p.measures) ? p.measures : [])
    .filter((m: any) => m?.aim)
    .map((m: any) => {
      const kind = asKind(m.kind);
      const poles = strs(m.poles);
      const letters = strs(m.letters);
      return {
        aim: String(m.aim),
        kind: kind === 'pair' && poles.length < 2 ? 'open' : kind,
        ...(poles.length >= 2
          ? { poles: [poles[0], poles[1]] as [string, string] }
          : {}),
        ...(letters.length >= 2
          ? { letters: [letters[0], letters[1]] as [string, string] }
          : {}),
        ...(m.low ? { low: String(m.low) } : {}),
        ...(m.high ? { high: String(m.high) } : {}),
        ...(strs(m.options).length ? { options: strs(m.options) } : {}),
      };
    });
  return {
    purpose: String(p.purpose ?? ''),
    intro: String(p.intro ?? ''),
    reveal: asReveal(p.reveal),
    rapport: asRapport(p.rapport),
    adapt: p.adapt !== false,
    warmup: Math.max(0, Math.min(2, Math.round(Number(p.warmup ?? 1)))),
    showNotes: p.showNotes !== false,
    showAims: p.showAims !== false,
    minutes: Number(p.minutes) || b.minutes || 10,
    offerMore: p.offerMore !== false,
    tools: strs(p.tools).filter((t): t is ToolKind =>
      (TOOL_KINDS as string[]).includes(t),
    ).length
      ? (strs(p.tools).filter((t) =>
          (TOOL_KINDS as string[]).includes(t),
        ) as ToolKind[])
      : [...TOOL_KINDS],
    measures: measures.length
      ? measures
      : (b.aims ?? []).map((aim) => ({ aim, kind: 'open' as MeasureKind })),
    rationale: String(p.rationale ?? ''),
  };
}

// ─── how warm the interviewer may be ─────────────────────────────────────
// Rapport that doesn't steer: react to the telling, not the content; use
// their own feeling words, never guess feelings; curiosity about them; humour
// at the interviewer's own expense. Warmer levels add more of it.
const NEVER = `Never, at any level: lead (put an answer in their mouth, or sum them up as a question), agree or disagree with them, praise or judge what they chose or did, or guess a feeling they didn't state.`;

export const RAPPORT_RULES: Record<Rapport, string> = {
  strict: `RAPPORT: strict (research where your manner could skew answers, e.g. what people prefer or would buy). Stay neutral and plain. Allowed: their own words back; thanks for detail ("thanks, that's useful detail"); saying what's coming ("a quick one next"); "there's no right answer". No humour, no exclamation marks, no reactions to what they said. Don't reveal who is asking or which answer anyone hopes for. ${NEVER}`,
  balanced: `RAPPORT: balanced. Neutral but human. Allowed: their own words back, including their feeling words ("relieved: what was the most draining part?"); thanks for the telling, not the content ("thanks, that's a vivid one"); curiosity about them ("wait, max level before the ending, why then?"); a little humour at your own expense ("my memory, not yours"); saying what's coming; making answers safe ("people split about evenly on this"); clear changes of topic ("two very different stories, the work one first"). Never "great", "nice", "lovely", "awesome", "interesting", "sounds like", "sounds fun", "noted", "got it". ${NEVER}`,
  warm: `RAPPORT: warm (low stakes, for fun or self-reflection; the person should enjoy it). Everything in balanced, plus brief, friendly reactions to small talk that isn't evidence for an aim ("a weekend of sleep and games, fair enough"), light jokes, and the odd exclamation. Still keep your reactions off anything that IS evidence for an aim: don't cheer one side of a question you're measuring. ${NEVER}`,
};

// ─── the designer ────────────────────────────────────────────────────────
const DESIGNER = `You design how a one-to-one AI research interview should run, from the research brief. Think about who the participants are, what the researcher needs, and how the interviewer's manner and the participant's view could bias the answers. Decide:
- reveal: what the participant sees at the end. "full" = their result with the evidence for each part (self-reflection, fun, personal insight they came for); "summary" = a short result; "none" = just thanks (market or product research, where showing conclusions could change future answers or isn't what they came for).
- rapport: "warm" (fun, low stakes; warmth won't skew much), "balanced" (most studies), "strict" (preferences, prices, product opinions: any reaction from the interviewer can push answers).
- adapt: may the interviewer shift its tone toward how the person talks? (usually true; false when every participant must get exactly the same manner).
- warmup: 0-2 light questions before the aims (0 when time is tight or the setting is formal).
- showAims: may the participant see the aims being covered? (false when knowing what's measured would change answers).
- showNotes: may the participant open the interviewer's notes? (false unless the brief is about the participant's own insight; testing can switch it on).
- minutes: a realistic length that respects short attention spans.
- offerMore: once there is a fair read, offer them the choice to stop or go on (true for most studies).
- tools: which in-chat tools fit: choice (closed question), likert (scales and ladders), duels (this-or-that ranking), recall (unprompted awareness), haggle (willingness to pay), video (Watch it: reactions over time to a video, camera optional), picture (Picture it: they describe something and the AI draws it, then they change it; or they read an open picture. For how people link words and feelings to visuals: taste, moods, self-image).
- measures: one per aim, written as the aim. kind "pair" for a lean between two ends (give "poles", and "letters" if results are written as a code like a 4-letter type), "scale" for a degree (give "low" and "high"), "choice" for one answer from a set (give "options"), "open" for findings in words. Leave out aims that are really the overall result (e.g. "give them a type").
- purpose: one honest sentence participants are told about what this is for (don't name a client if that would bias them).
- intro: one friendly line for the start screen.
- rationale: 2-4 short sentences for the researcher: why these settings, especially the bias trade-offs.
Answer ONLY with JSON: {"purpose": str, "intro": str, "reveal": str, "rapport": str, "adapt": bool, "warmup": int, "showAims": bool, "showNotes": bool, "minutes": int, "offerMore": bool, "tools": [str], "measures": [{"aim": str, "kind": str, "poles": [str, str], "letters": [str, str], "low": str, "high": str, "options": [str]}], "rationale": str}`;

export async function designStudy(
  ctx: any,
  title: string,
  brief: string,
  aims: string[],
  mustAsk: string[],
): Promise<StudyProtocol> {
  const user = `TITLE: ${title}\n\nBRIEF: ${brief}\n\nAIMS:\n${aims.map((a, i) => `${i + 1}. ${a}`).join('\n') || '(none yet)'}\n\nMUST ASK:\n${mustAsk.join('\n') || '(none)'}`;
  const j = await askJson(ctx, DESIGNER, user, 0.3);
  return readProtocol(JSON.stringify(j), { aims });
}
