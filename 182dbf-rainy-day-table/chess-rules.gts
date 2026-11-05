// Chess rule module: the part of chess JSON can't comfortably say.
// Full move legality: check, castling (through-check forbidden), en passant
// and promotion. Draws by stalemate and bare kings; repetition and the
// 50-move rule are Phase 2. Pieces are ordinary copies on the "board" grid
// zone (position = square index, a1 = 0). Castling rights live on the copies
// themselves as a "moved" counter; promotion sets a "becomes" counter, so a
// promoted pawn keeps its identity (wP#5 is still wP#5, now reading as a queen).

import type {
  Action,
  Copy,
  GameData,
  LegalAction,
  ModuleCtx,
  RuleModule,
  State,
} from './engine';
import { effectiveDef, registerModule } from './engine';

type Col = 'w' | 'b';
interface P {
  c: Copy;
  col: Col;
  t: string; // K Q R B N P
}

const SEAT: Record<Col, string> = { w: 'white', b: 'black' };
const COL = (seat: string): Col => (seat === 'black' ? 'b' : 'w');
const sqName = (i: number) =>
  String.fromCharCode(97 + (i & 7)) + ((i >> 3) + 1);
const fileOf = (i: number) => i & 7;
const rankOf = (i: number) => i >> 3;

function board(state: State): (P | null)[] {
  let b: (P | null)[] = new Array(64).fill(null);
  for (let c of state.copies) {
    if (c.zone !== 'board') continue;
    let d = effectiveDef(c);
    b[c.position] = { c, col: d[0] as Col, t: d[1] };
  }
  return b;
}

const N_OFF = [
  [1, 2],
  [2, 1],
  [2, -1],
  [1, -2],
  [-1, -2],
  [-2, -1],
  [-2, 1],
  [-1, 2],
];
const K_OFF = [
  [1, 0],
  [1, 1],
  [0, 1],
  [-1, 1],
  [-1, 0],
  [-1, -1],
  [0, -1],
  [1, -1],
];
const ROOK = [
  [1, 0],
  [-1, 0],
  [0, 1],
  [0, -1],
];
const BISH = [
  [1, 1],
  [1, -1],
  [-1, 1],
  [-1, -1],
];

function at(f: number, r: number) {
  return f >= 0 && f < 8 && r >= 0 && r < 8 ? r * 8 + f : -1;
}

// Is square `sq` attacked by colour `by`?
function attacked(b: (P | null)[], sq: number, by: Col): boolean {
  let f = fileOf(sq);
  let r = rankOf(sq);
  let dir = by === 'w' ? -1 : 1; // pawns of `by` attack from behind sq
  for (let df of [-1, 1]) {
    let s = at(f + df, r + dir);
    if (s >= 0 && b[s]?.col === by && b[s]?.t === 'P') return true;
  }
  for (let [df, dr] of N_OFF) {
    let s = at(f + df, r + dr);
    if (s >= 0 && b[s]?.col === by && b[s]?.t === 'N') return true;
  }
  for (let [df, dr] of K_OFF) {
    let s = at(f + df, r + dr);
    if (s >= 0 && b[s]?.col === by && b[s]?.t === 'K') return true;
  }
  for (let [dirs, kinds] of [
    [ROOK, 'RQ'],
    [BISH, 'BQ'],
  ] as const) {
    for (let [df, dr] of dirs) {
      let ff = f + df;
      let rr = r + dr;
      for (;;) {
        let s = at(ff, rr);
        if (s < 0) break;
        let p = b[s];
        if (p) {
          if (p.col === by && kinds.includes(p.t)) return true;
          break;
        }
        ff += df;
        rr += dr;
      }
    }
  }
  return false;
}

interface Mv {
  from: number;
  to: number;
  promo?: string;
  castle?: 'K' | 'Q';
  ep?: boolean;
  capture?: boolean;
}

function pseudo(b: (P | null)[], col: Col, ep: number): Mv[] {
  let out: Mv[] = [];
  for (let sq = 0; sq < 64; sq++) {
    let p = b[sq];
    if (!p || p.col !== col) continue;
    let f = fileOf(sq);
    let r = rankOf(sq);
    const add = (to: number) => {
      let cap = !!b[to];
      out.push({ from: sq, to, capture: cap });
    };
    if (p.t === 'P') {
      let dir = col === 'w' ? 1 : -1;
      let start = col === 'w' ? 1 : 6;
      let last = col === 'w' ? 7 : 0;
      let one = at(f, r + dir);
      const push = (to: number, cap: boolean, isEp = false) => {
        if (rankOf(to) === last) {
          for (let pr of ['Q', 'R', 'B', 'N'])
            out.push({ from: sq, to, promo: pr, capture: cap });
        } else out.push({ from: sq, to, capture: cap, ep: isEp });
      };
      if (one >= 0 && !b[one]) {
        push(one, false);
        let two = at(f, r + 2 * dir);
        if (r === start && !b[two]) out.push({ from: sq, to: two });
      }
      for (let df of [-1, 1]) {
        let s = at(f + df, r + dir);
        if (s < 0) continue;
        if (b[s] && b[s]!.col !== col) push(s, true);
        else if (s === ep) push(s, true, true);
      }
    } else if (p.t === 'N' || p.t === 'K') {
      for (let [df, dr] of p.t === 'N' ? N_OFF : K_OFF) {
        let s = at(f + df, r + dr);
        if (s >= 0 && b[s]?.col !== col) add(s);
      }
      if (p.t === 'K' && !p.c.counters.moved) {
        let other: Col = col === 'w' ? 'b' : 'w';
        let home = col === 'w' ? 0 : 56;
        if (sq === home + 4 && !attacked(b, sq, other)) {
          let rk = b[home + 7];
          if (
            rk &&
            rk.t === 'R' &&
            rk.col === col &&
            !rk.c.counters.moved &&
            !b[home + 5] &&
            !b[home + 6] &&
            !attacked(b, home + 5, other) &&
            !attacked(b, home + 6, other)
          ) {
            out.push({ from: sq, to: home + 6, castle: 'K' });
          }
          let rq = b[home];
          if (
            rq &&
            rq.t === 'R' &&
            rq.col === col &&
            !rq.c.counters.moved &&
            !b[home + 1] &&
            !b[home + 2] &&
            !b[home + 3] &&
            !attacked(b, home + 3, other) &&
            !attacked(b, home + 2, other)
          ) {
            out.push({ from: sq, to: home + 2, castle: 'Q' });
          }
        }
      }
    } else {
      let dirs = p.t === 'R' ? ROOK : p.t === 'B' ? BISH : [...ROOK, ...BISH];
      for (let [df, dr] of dirs) {
        let ff = f + df;
        let rr = r + dr;
        for (;;) {
          let s = at(ff, rr);
          if (s < 0) break;
          if (b[s]) {
            if (b[s]!.col !== col) add(s);
            break;
          }
          add(s);
          ff += df;
          rr += dr;
        }
      }
    }
  }
  return out;
}

function makeOnBoard(b: (P | null)[], m: Mv): (P | null)[] {
  let nb = b.slice();
  let p = nb[m.from]!;
  nb[m.from] = null;
  if (m.ep) nb[m.to + (p.col === 'w' ? -8 : 8)] = null;
  nb[m.to] = m.promo ? { ...p, t: m.promo } : p;
  if (m.castle) {
    let home = p.col === 'w' ? 0 : 56;
    if (m.castle === 'K') {
      nb[home + 5] = nb[home + 7];
      nb[home + 7] = null;
    } else {
      nb[home + 3] = nb[home];
      nb[home] = null;
    }
  }
  return nb;
}

function kingSq(b: (P | null)[], col: Col) {
  return b.findIndex((p) => p?.col === col && p.t === 'K');
}

export function legalMoves(state: State, col: Col): Mv[] {
  let b = board(state);
  let ep = state.vars.ep ?? -1;
  let other: Col = col === 'w' ? 'b' : 'w';
  return pseudo(b, col, ep).filter((m) => {
    let nb = makeOnBoard(b, m);
    let k = kingSq(nb, col);
    return k >= 0 && !attacked(nb, k, other);
  });
}

function san(b: (P | null)[], m: Mv) {
  if (m.castle) return m.castle === 'K' ? 'O-O' : 'O-O-O';
  let p = b[m.from]!;
  let piece = p.t === 'P' ? (m.capture ? sqName(m.from)[0] : '') : p.t;
  return `${piece}${m.capture ? '×' : ''}${sqName(m.to)}${m.promo ? '=' + m.promo : ''}`;
}

const chess: RuleModule = {
  legalActions(state, seat) {
    if (seat !== state.turn.seat) return [];
    let col = COL(seat);
    let b = board(state);
    let out: LegalAction[] = legalMoves(state, col).map((m) => ({
      id: 'move',
      seat,
      args: {
        from: sqName(m.from),
        to: sqName(m.to),
        ...(m.promo ? { promo: m.promo } : {}),
      },
      label: san(b, m),
      from: b[m.from]!.c.copyId,
      to: { zone: 'board', position: m.to },
    }));
    out.push({ id: 'resign', seat, args: {}, label: 'Resign', bot: false });
    return out;
  },

  apply(state: State, action: Action, ctx: ModuleCtx) {
    let col = COL(action.seat);
    let other: Col = col === 'w' ? 'b' : 'w';
    if (action.id === 'resign') {
      state.status = 'finished';
      state.result = {
        winner: SEAT[other],
        text: `${label(state, action.seat)} resigns`,
      };
      return;
    }
    let from = sqIndex(action.args!.from);
    let to = sqIndex(action.args!.to);
    let promo = action.args!.promo as string | undefined;
    let b = board(state);
    let m = legalMoves(state, col).find(
      (x) => x.from === from && x.to === to && (x.promo ?? undefined) === promo,
    );
    if (!m)
      throw new Error(`illegal move ${action.args!.from}-${action.args!.to}`);
    let note = san(b, m);
    let victimSq = m.ep ? to + (col === 'w' ? -8 : 8) : to;
    let victim = b[victimSq];
    if (victim && victim.col !== col) {
      let zone = `taken:${SEAT[col]}`;
      let n = state.copies.filter((c) => c.zone === zone).length;
      ctx.move(victim.c, zone, n, { capture: true });
    }
    let mover = b[from]!.c;
    ctx.move(mover, 'board', to);
    mover.counters = { ...mover.counters, moved: true };
    if (promo) mover.counters = { ...mover.counters, becomes: col + promo };
    if (m.castle) {
      let home = col === 'w' ? 0 : 56;
      let rk = b[m.castle === 'K' ? home + 7 : home]!.c;
      ctx.move(rk, 'board', m.castle === 'K' ? home + 5 : home + 3);
      rk.counters = { ...rk.counters, moved: true };
    }
    state.vars.ep =
      b[from]!.t === 'P' && Math.abs(to - from) === 16 ? (from + to) / 2 : -1;
    state.vars.lastMove = { from: action.args!.from, to: action.args!.to };
    // pass the turn
    state.turn.seat = SEAT[other];
    state.turn.number++;
    let replies = legalMoves(state, other);
    let nb = board(state);
    let inCheck = attacked(nb, kingSq(nb, other), col);
    if (!replies.length) note += inCheck ? '#' : '';
    else if (inCheck) note += '+';
    state.vars.check = inCheck && replies.length > 0 ? SEAT[other] : null;
    ctx.say(note);
  },

  result(state) {
    let col = COL(state.turn.seat);
    let other: Col = col === 'w' ? 'b' : 'w';
    let b = board(state);
    let pieces = b.filter(Boolean) as P[];
    if (pieces.length === 2)
      return { winner: null, text: 'Draw: only the kings are left' };
    if (legalMoves(state, col).length) return null;
    if (attacked(b, kingSq(b, col), other)) {
      return {
        winner: SEAT[other],
        text: `Checkmate. ${label(state, SEAT[other])} wins`,
      };
    }
    return { winner: null, text: 'Stalemate: a draw' };
  },

  // Material from the scorer's side, plus a little positional sense so a
  // shallow search still makes progress: pawns want to advance, and once the
  // opponent is thin, drive their king to the edge and bring your own close.
  evaluate(state, seat, _game, scoring) {
    let col = COL(seat);
    let vals: Record<string, number> = {
      P: 1,
      N: 3,
      B: 3,
      R: 5,
      Q: 9,
      K: 0,
      ...(scoring?.pieceValues ?? {}),
    };
    let b = board(state);
    let score = 0;
    let theirMat = 0;
    let myMat = 0;
    for (let sq = 0; sq < 64; sq++) {
      let p = b[sq];
      if (!p) continue;
      let v = vals[p.t] ?? 0;
      let adv =
        p.t === 'P'
          ? (p.col === 'w' ? rankOf(sq) - 1 : 6 - rankOf(sq)) * 0.06
          : 0;
      let centre =
        p.t === 'N' || p.t === 'B'
          ? (3.5 -
              Math.abs(3.5 - fileOf(sq)) +
              3.5 -
              Math.abs(3.5 - rankOf(sq))) *
            0.02
          : 0;
      if (p.col === col) {
        score += v + adv + centre;
        myMat += v;
      } else {
        score -= v + adv + centre;
        theirMat += v;
      }
    }
    if (theirMat <= 5 && myMat > theirMat) {
      let other: Col = col === 'w' ? 'b' : 'w';
      let ek = kingSq(b, other);
      let mk = kingSq(b, col);
      let edge = Math.max(
        Math.abs(3.5 - fileOf(ek)),
        Math.abs(3.5 - rankOf(ek)),
      );
      let dist =
        Math.abs(fileOf(ek) - fileOf(mk)) + Math.abs(rankOf(ek) - rankOf(mk));
      score +=
        edge * 0.3 - dist * 0.08 - legalMoves(state, other).length * 0.02;
    }
    return score;
  },
};

function sqIndex(s: string) {
  return (Number(s.slice(1)) - 1) * 8 + (s.charCodeAt(0) - 97);
}
function label(state: State, seat: string) {
  return state.seats.find((s) => s.id === seat)?.label ?? seat;
}

registerModule('chess', chess);
export default chess;
export type { GameData };
