// The analyst: a researcher's assistant that works on a canvas of tiles. It
// sees a compact digest of every interview, the pooled tool data and the
// current canvas, and answers with words plus canvas moves: add a tile, bring
// one into focus, minimise one to the dock, resize, reorder, remove. Tiles
// draw their numbers from the data themselves; the analyst never types a
// statistic into a chart, only into its own sentences, which must come from
// the digest.
import { askJson } from './tool-kit';

export type Size = 's' | 'm' | 'l' | 'xl';
export type TileKind =
  | 'note'
  | 'quotes'
  | 'measure'
  | 'scatter'
  | 'compare'
  | 'duels'
  | 'gallery'
  | 'participation'
  | 'interviewers'
  | 'types'
  | 'videos';
export const TILE_KINDS: TileKind[] = [
  'note',
  'quotes',
  'measure',
  'scatter',
  'compare',
  'duels',
  'gallery',
  'participation',
  'interviewers',
  'types',
  'videos',
];

export interface Tile {
  id: string;
  kind: TileKind;
  title: string;
  size: Size;
  min?: boolean; // in the dock
  config: any;
}
export interface Op {
  op:
    | 'add'
    | 'focus'
    | 'unfocus'
    | 'minimize'
    | 'restore'
    | 'resize'
    | 'move'
    | 'remove'
    | 'clear'
    | 'chat';
  side?: 'left' | 'right' | 'hidden'; // chat: where the chat sits
  id?: string;
  tile?: Partial<Tile>;
  size?: Size;
  to?: number; // move: new position (0 = first)
}
export interface Step {
  say: string; // one short spoken line
  ops: Op[];
}
export interface ChatLine {
  who: 'analyst' | 'you';
  text: string;
  at: string;
}

const TILES = `TILES (the canvas draws the numbers itself from the data; you choose what to show):
- "participation": how many took part, finished, minutes, offers taken. config {}
- "interviewers": who people picked to talk to, and how each went. config {}
- "measure": one measure across people (pairs: a strip, one dot per person with its uncertainty; others: their leans). config {"measure": N}
- "scatter": each person on two pair/scale measures at once. config {"x": N, "y": N}
- "compare": a feature compared across groups. feature: "words" (words per answer), "minutes", "answers", "tools", "skipped". by: "host" (interviewer), "done", or "lean:N" (which side of measure N). config {"feature": str, "by": str}
- "types": the letter codes people got (studies with letter codes only). config {}
- "duels": This-or-that pooled across people: the screen ranking, and win rate by where screens came from. config {}
- "gallery": everyone's Picture it pictures. config {}
- "videos": what people said while watching videos. config {}
- "note": a finding in your words: 1-4 short sentences, every number from the digest. config {"text": str}
- "quotes": 2-5 telling quotes, word for word from the digest, each with its P number. config {"quotes": [{"text": str, "who": "P3"}]}
Sizes: "s" (small), "m" (medium), "l" (large), "xl" (full width).`;

const ANALYST = `You are a sharp, honest research analyst presenting findings to a CEO on a whiteboard, with the researcher asking questions in a small chat. You present ONE POINT AT A TIME, like a good presenter:
- Answer as 1-5 steps. Each step is one short spoken line (one or two sentences, said to the room) and usually one tile that shows it.
- A new tile first appears big, centre stage, while you speak; then it settles into its slot on the board by itself, at the size you give it (first slot is top-left, the next beside it, then the next row). So give each tile its final size: "s" for a number or a short table, "m" for a chart, "l" for something to read closely, "xl" for a full-width picture. Order the steps so the board reads left to right, top to bottom.
- Each question starts a fresh slide by default: the board is cleared (everything goes to the dock, nothing is lost) before your first step. Only if the question clearly builds on what's showing, set "board": "keep" and add to it. Bring back a docked tile with "restore" rather than making a duplicate.
- Every claim comes from the digest. Say how many people it rests on ("3 of 5"). With few people, call it a hint. Test runs are scripted: say so when they drive a result.
- Your spoken numbers must match the tiles: a measure's readings are ONLY the "readings:" lines (that's what its tile counts). Findings written in older dossiers without readings are not readings; if you use them, say they're from notes.
- Look for patterns in how people answered, not just what they concluded: answer length, stories vs abstractions, deflecting, when they stopped, which interviewer, and how these line up with their readings.
- Optional: {"op": "chat", "side": "left" | "right" | "hidden"} moves the chat if the board needs the room.

${TILES}

OPS: {"op": "add", "tile": {"id": "short-id", "kind": str, "title": str, "size": str, "config": {...}}} · {"op": "clear"} · {"op": "focus", "id": str} · {"op": "unfocus"} · {"op": "minimize", "id": str} · {"op": "restore", "id": str} · {"op": "resize", "id": str, "size": str} · {"op": "move", "id": str, "to": int} · {"op": "remove", "id": str} · {"op": "chat", "side": str}

Answer ONLY with JSON: {"board": "new" | "keep", "steps": [{"say": str, "ops": [ ... ]}]}`;

export async function ask(
  ctx: any,
  o: {
    brief: string;
    measures: string;
    digest: string;
    pooled: string;
    canvas: Tile[];
    chat: ChatLine[];
    question: string;
  },
): Promise<Step[]> {
  const user = [
    `STUDY: ${o.brief}`,
    `MEASURES:\n${o.measures}`,
    `INTERVIEWS (digest):\n${o.digest || '(none yet)'}`,
    o.pooled ? `POOLED TOOL DATA:\n${o.pooled}` : '',
    `BOARD NOW (in order; ~ = minimised in the dock): ${o.canvas.map((t, i) => `${i}. ${t.id} ${t.kind} "${t.title}" ${t.size}${t.min ? ' ~' : ''}`).join(' | ') || '(blank)'}`,
    o.chat.length
      ? `CONVERSATION SO FAR:\n${o.chat
          .slice(-10)
          .map((c) => `${c.who === 'you' ? 'RESEARCHER' : 'YOU'}: ${c.text}`)
          .join('\n')}`
      : '',
    `RESEARCHER NOW: ${o.question}`,
  ]
    .filter(Boolean)
    .join('\n\n');
  const j = await askJson(
    ctx,
    ANALYST,
    user,
    0.3,
    'anthropic/claude-sonnet-5.5',
  );
  const clean = (xs: any) =>
    (Array.isArray(xs) ? xs : []).filter(
      (x: any) => x && typeof x.op === 'string',
    ) as Op[];
  // a model that answers with a single {say, ops} still works
  const steps = Array.isArray(j?.steps)
    ? j.steps
    : [{ say: j?.say, ops: j?.ops }];
  const out: Step[] = steps
    .filter((x: any) => x && (x.say || x.ops?.length))
    .slice(0, 6)
    .map((x: any) => ({ say: String(x.say ?? ''), ops: clean(x.ops) }));
  // a new slide unless told to keep the board
  if (
    j?.board !== 'keep' &&
    out.length &&
    !out[0].ops.some((o) => o.op === 'clear')
  )
    out[0].ops.unshift({ op: 'clear' });
  return out;
}
