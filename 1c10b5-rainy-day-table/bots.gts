// Opponents without an LLM. A bot only ever reads its seat's view and picks
// from legalActions, so it cannot cheat or make an illegal move.
//   random — the baseline every other bot must beat
//   policy — an ordered list of { when, do } rules, written as data
//   search — looks N moves ahead (perfect-information games only)

import type { GameData, LegalAction, Rng, State } from './engine';
import {
  apply,
  evalFor,
  legalActions,
  makeRng,
  moduleFor,
  newMatch,
  seatView,
} from './engine';

export interface PolicyRule {
  when: string;
  do: string; // action id, or "id:value" to match the first option arg
  weight?: number;
}

export interface BotSpec {
  name?: string;
  kind: 'random' | 'policy' | 'search' | 'llm';
  policy?: PolicyRule[];
  searchDepth?: number;
  scoring?: any;
  thinkingDelay?: number;
}

function matches(a: LegalAction, pattern: string) {
  let [id, val] = pattern.split(':');
  if (a.id !== id) return false;
  if (val === undefined) return true;
  let first = Object.values(a.args ?? {})[0];
  return String(first) === val;
}

export function chooseAction(
  game: GameData,
  state: State,
  seat: string,
  bot: BotSpec,
  rng: Rng,
): LegalAction | null {
  let legal = legalActions(game, state, seat).filter((a) => a.bot !== false);
  if (!legal.length) return null;
  let view = seatView(state, seat);
  if (bot.kind === 'policy' && bot.policy?.length) {
    for (let rule of bot.policy) {
      let ok = false;
      try {
        ok = !!evalFor(game, view, seat, rule.when);
      } catch {
        ok = false;
      }
      if (!ok) continue;
      let hits = legal.filter((a) => matches(a, rule.do));
      if (hits.length) return hits[rng.int(hits.length)];
    }
  }
  if (bot.kind === 'search' && moduleFor(game)) {
    return search(game, view, seat, legal, bot, rng);
  }
  return legal[rng.int(legal.length)];
}

function score(game: GameData, s: State, seat: string, bot: BotSpec): number {
  if (s.status === 'finished') {
    if (!s.result?.winner) return 0;
    return s.result.winner === seat ? 1000 : -1000;
  }
  return moduleFor(game)?.evaluate?.(s, seat, game, bot.scoring) ?? 0;
}

function search(
  game: GameData,
  view: State,
  seat: string,
  legal: LegalAction[],
  bot: BotSpec,
  rng: Rng,
) {
  let depth = Math.max(1, bot.searchDepth ?? 2);
  // Negamax: the value of a state from the side to move's point of view.
  const negamax = (
    s: State,
    d: number,
    alpha: number,
    beta: number,
  ): number => {
    let me = s.turn.seat;
    if (d === 0 || s.status === 'finished') return score(game, s, me, bot);
    let moves = legalActions(game, s, me).filter((a) => a.bot !== false);
    if (!moves.length) return score(game, s, me, bot);
    let best = -Infinity;
    for (let m of moves) {
      let next = apply(game, s, m, { sim: true, skipLegalCheck: true }).state;
      let v =
        next.turn.seat === me
          ? negamax(next, d - 1, alpha, beta)
          : -negamax(next, d - 1, -beta, -alpha);
      if (v > best) best = v;
      if (best > alpha) alpha = best;
      if (alpha >= beta) break;
    }
    return best;
  };
  let scored = legal.map((m) => {
    let next = apply(game, view, m, { sim: true, skipLegalCheck: true }).state;
    let v =
      next.status === 'finished'
        ? score(game, next, seat, bot) * 2 // a win now beats a win later
        : next.turn.seat === seat
          ? negamax(next, depth - 1, -Infinity, Infinity)
          : -negamax(next, depth - 1, -Infinity, Infinity);
    return { m, v: v + rng.next() * 0.01 }; // tiny jitter breaks ties
  });
  scored.sort((a, b) => b.v - a.v);
  return scored[0].m;
}

// ─── Headless simulation (balance checks, smoke tests) ────────────────────
export interface SimResult {
  winner: string | null;
  actions: number;
  actors?: number; // how many different seats took an action
  stalled?: string;
  error?: string;
}

export function simulate(
  game: GameData,
  seats: State['seats'],
  bots: Record<string, BotSpec>,
  runs: number,
  seed0 = 1,
  maxActions = 600,
): SimResult[] {
  let out: SimResult[] = [];
  for (let r = 0; r < runs; r++) {
    let rng = makeRng(seed0 * 7919 + r);
    try {
      let { state } = newMatch(game, seats, seed0 + r);
      let n = 0;
      let actors = new Set<string>();
      while (state.status === 'playing' && n < maxActions) {
        let seat = state.turn.seat;
        let a = chooseAction(
          game,
          state,
          seat,
          bots[seat] ?? { kind: 'random' },
          rng,
        );
        if (!a) {
          out.push({
            winner: null,
            actions: n,
            stalled: `no legal action for ${seat} in phase "${state.turn.phase}"`,
          });
          break;
        }
        actors.add(seat);
        state = apply(game, state, a, {
          sim: true,
          skipLegalCheck: true,
        }).state;
        n++;
      }
      if (state.status === 'finished')
        out.push({
          winner: state.result?.winner ?? null,
          actions: n,
          actors: actors.size,
        });
      else if (n >= maxActions)
        out.push({
          winner: null,
          actions: n,
          stalled: `still going after ${maxActions} actions`,
        });
    } catch (e: any) {
      out.push({ winner: null, actions: 0, error: String(e?.message ?? e) });
    }
  }
  return out;
}

export function summarise(results: SimResult[], seatIds: string[]) {
  let wins: Record<string, number> = Object.fromEntries(
    seatIds.map((s) => [s, 0]),
  );
  let draws = 0;
  let stalls = results.filter((r) => r.stalled).length;
  let errors = results.filter((r) => r.error);
  for (let r of results) {
    if (r.winner) wins[r.winner] = (wins[r.winner] ?? 0) + 1;
    else if (!r.stalled && !r.error) draws++;
  }
  let lens = results.filter((r) => !r.error).map((r) => r.actions);
  let avg = lens.length ? lens.reduce((a, b) => a + b, 0) / lens.length : 0;
  let soloRuns =
    seatIds.length > 1 ? results.filter((r) => r.actors === 1).length : 0;
  return {
    runs: results.length,
    wins,
    draws,
    stalls,
    soloRuns,
    errors: errors.map((e) => e.error!),
    avgLength: Math.round(avg),
  };
}
