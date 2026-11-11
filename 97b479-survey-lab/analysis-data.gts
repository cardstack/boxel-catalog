// What the analysis canvas works from: each interview turned into a row of
// plain numbers and readings, and the tools' data pooled across people. Tiles
// draw from this, never from numbers an AI typed, so a chart can be trusted;
// the analyst only chooses which tiles to show and writes the words.
import { parseJson } from './tool-kit';
import { fit } from './duels';
import type { Turn, Verdict } from './interviewer-ai';
import type { StudyProtocol } from './study';
import type { Stimulus } from './stimuli';

export interface Row {
  id: string;
  n: number; // P1, P2… in the order they started
  who: string;
  host: string; // the interviewer they talked to
  test: boolean; // a scripted or test run
  done: boolean;
  minutes: number; // time talking (breaks count as at most 2 minutes)
  answers: number;
  words: number; // average words per typed answer
  tools: {
    kind: string;
    status: string;
    summary: string;
    responseId?: string;
    image?: string;
  }[];
  offered: boolean;
  keptGoing: boolean;
  label: string;
  code: string;
  readings: {
    i: number;
    lean: string;
    value: number;
    confidence: string;
    evidence: string[];
  }[];
  dossier: string;
}

const CANNED =
  /^(let's keep going\.|let's stop here\.|i'd like to finish here, please\.)$/i;
const words = (t: string) => t.trim().split(/\s+/).filter(Boolean).length;

function activeMinutes(startedAt: string, turns: Turn[], end: string) {
  const times = [
    Date.parse(startedAt),
    ...turns.map((t) => Date.parse(t.at)),
    Date.parse(end),
  ].filter((x) => Number.isFinite(x));
  let ms = 0;
  for (let k = 1; k < times.length; k++)
    ms += Math.min(Math.max(0, times[k] - times[k - 1]), 120000);
  return Math.round((ms / 60000) * 10) / 10;
}

export function rowsOf(interviews: any[], p: StudyProtocol): Row[] {
  return [...interviews]
    .sort((a, b) =>
      String(a.startedAt ?? '').localeCompare(String(b.startedAt ?? '')),
    )
    .map((iv, k) => {
      const turns = parseJson<Turn[]>(iv.turns, []);
      const said = turns.filter(
        (t) => t.who === 'person' && !CANNED.test(t.text.trim()),
      );
      const v = parseJson<Verdict | null>(iv.verdict, null);
      const res = parseJson<{ label: string } | null>(iv.result, null);
      const offerAt = turns.findIndex((t) => t.offer);
      const after =
        offerAt >= 0
          ? turns.slice(offerAt + 1).find((t) => t.who === 'person')
          : undefined;
      const letters = p.measures.map((m, i) => {
        if (!m.letters) return null;
        const r = v?.readings.find((x) => x.i === i + 1);
        return r && (r.confidence === 'medium' || r.confidence === 'high')
          ? r.value < 0
            ? m.letters[0]
            : m.letters[1]
          : 'x';
      });
      const ls = letters.filter((l): l is string => l !== null);
      return {
        id: iv.id,
        n: k + 1,
        who: iv.participant || 'Anonymous',
        host: iv.host?.name ?? iv.brief?.interviewer ?? '',
        test: /tester|^test\b/i.test(iv.participant ?? ''),
        done: iv.status === 'done',
        minutes: activeMinutes(
          iv.startedAt ?? '',
          turns,
          iv.updatedAt ?? iv.startedAt ?? '',
        ),
        answers: said.length,
        words: said.length
          ? Math.round(
              said.reduce((t, x) => t + words(x.text), 0) / said.length,
            )
          : 0,
        tools: turns
          .filter((t) => t.tool)
          .map((t) => ({
            kind: t.tool!.kind,
            status: t.tool!.status,
            summary: t.tool!.summary ?? '',
            responseId: t.tool!.responseId,
            image: t.tool!.image,
          })),
        offered: offerAt >= 0,
        keptGoing: /keep going/i.test(after?.text ?? ''),
        label: res?.label ?? '',
        code:
          ls.length >= 2 && (v?.readings.length ?? 0) > 0 ? ls.join('') : '', // no verdict yet (older interviews): no code
        readings: (v?.readings ?? []).map((r) => ({
          i: r.i,
          lean: r.lean,
          value: r.value,
          confidence: r.confidence,
          evidence: r.evidence,
        })),
        dossier: String(iv.dossier ?? ''),
      };
    });
}

// ─── features to compare groups by ───────────────────────────────────────
export const FEATURES: Record<
  string,
  { name: string; of: (r: Row) => number }
> = {
  words: { name: 'Words per answer', of: (r) => r.words },
  minutes: { name: 'Minutes talking', of: (r) => r.minutes },
  answers: { name: 'Answers given', of: (r) => r.answers },
  tools: {
    name: 'Tools used',
    of: (r) => r.tools.filter((t) => t.status === 'done').length,
  },
  skipped: {
    name: 'Tools skipped',
    of: (r) => r.tools.filter((t) => t.status === 'skipped').length,
  },
};

// "host", "done", or "lean:N" (which side of measure N they lean to)
export function groupOf(by: string, r: Row, p: StudyProtocol): string {
  if (by === 'host') return r.host || 'Unknown';
  if (by === 'done') return r.done ? 'Finished' : 'Not finished';
  const m = by.match(/^(lean|letter):(\d+)$/);
  if (m) {
    const i = Number(m[2]);
    const ms = p.measures[i - 1];
    const rd = r.readings.find((x) => x.i === i);
    if (!ms || !rd || rd.confidence === 'none' || rd.confidence === 'low')
      return 'Unsure';
    if (ms.kind === 'pair' && ms.poles)
      return ms.letters
        ? rd.value < 0
          ? ms.letters[0]
          : ms.letters[1]
        : rd.value < 0
          ? ms.poles[0]
          : ms.poles[1];
    return rd.lean || 'Unsure';
  }
  return 'All';
}

export function compare(
  rows: Row[],
  feature: string,
  by: string,
  p: StudyProtocol,
) {
  const f = FEATURES[feature] ?? FEATURES.words;
  const groups = new Map<string, number[]>();
  for (const r of rows) {
    const g = groupOf(by, r, p);
    groups.set(g, [...(groups.get(g) ?? []), f.of(r)]);
  }
  const out = [...groups.entries()].map(([group, xs]) => ({
    group,
    n: xs.length,
    mean: Math.round((xs.reduce((a, b) => a + b, 0) / xs.length) * 10) / 10,
  }));
  const max = Math.max(1, ...out.map((o) => o.mean));
  return {
    name: f.name,
    groups: out
      .sort((a, b) => b.mean - a.mean)
      .map((o) => ({ ...o, pct: Math.round((o.mean / max) * 100) })),
  };
}

// ─── This or that, pooled across people ──────────────────────────────────
interface Pick {
  a: string;
  b: string;
  won: 'a' | 'b' | 'tie';
  ms: number;
}
export function poolDuels(
  duels: { items: string[]; picks: Pick[] }[],
  stimuli: Stimulus[],
) {
  const items = [...new Set(duels.flatMap((d) => d.items))];
  const picks = duels.flatMap((d) => d.picks);
  if (!items.length || !picks.length) return null;
  const scores = fit(items, picks);
  const shown = (name: string) => stimuli.find((s) => s.name === name);
  const ranking = [...items]
    .sort((x, y) => scores[y] - scores[x])
    .map((name) => {
      const s = shown(name);
      const seen = picks.filter((k) => k.a === name || k.b === name).length;
      return {
        name,
        score: scores[name],
        seen,
        image: s?.image ?? null,
        source: s?.source ?? '',
        label: s?.label ?? name,
      };
    });
  // by where the screens came from: wins over head-to-heads it was in
  const bySource = new Map<string, { wins: number; games: number }>();
  for (const k of picks) {
    if (k.won === 'tie') continue;
    for (const [me, won] of [
      [k.a, k.won === 'a'],
      [k.b, k.won === 'b'],
    ] as [string, boolean][]) {
      const src = shown(me)?.source ?? 'Other';
      const e = bySource.get(src) ?? { wins: 0, games: 0 };
      e.games++;
      if (won) e.wins++;
      bySource.set(src, e);
    }
  }
  const sources = [...bySource.entries()]
    .map(([source, e]) => ({
      source,
      games: e.games,
      rate: Math.round((e.wins / e.games) * 100),
    }))
    .sort((a, b) => b.rate - a.rate);
  return { ranking, sources, people: duels.length, picks: picks.length };
}

// ─── for the analyst: everything, compactly ──────────────────────────────
function section(dossier: string, name: string, max = 500) {
  const part = dossier
    .split(/^## /m)
    .find((s) => s.toLowerCase().startsWith(name.toLowerCase()));
  return part
    ? part.slice(name.length).trim().replace(/\s+/g, ' ').slice(0, max)
    : '';
}
export function digest(rows: Row[]) {
  return rows
    .map((r) => {
      const rd = r.readings
        .map(
          (x) =>
            `${x.i}:${x.lean || '?'}(${x.confidence}${x.evidence[0] ? `; "${x.evidence[0]}"` : ''})`,
        )
        .join(' ');
      return [
        `P${r.n} ${r.who}${r.test ? ' [test run]' : ''} · with ${r.host || '?'} · ${r.done ? 'finished' : 'not finished'} · ${r.minutes} min · ${r.answers} answers, ${r.words} words avg${r.offered ? ` · offered to stop, ${r.keptGoing ? 'kept going' : 'stopped'}` : ''}${r.code ? ` · code ${r.code}` : ''}${r.label ? ` · result "${r.label}"` : ''}`,
        rd ? `  readings: ${rd}` : '',
        r.tools.length
          ? `  tools: ${r.tools.map((t) => `${t.kind}(${t.status})${t.summary ? `: ${t.summary.slice(0, 160)}` : ''}`).join(' | ')}`
          : '',
        section(r.dossier, 'How to talk to them', 220)
          ? `  how they talk: ${section(r.dossier, 'How to talk to them', 220)}`
          : '',
        section(r.dossier, 'Findings')
          ? `  findings: ${section(r.dossier, 'Findings')}`
          : '',
      ]
        .filter(Boolean)
        .join('\n');
    })
    .join('\n');
}
