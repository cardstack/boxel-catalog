// The table engine. Everything that changes a match goes through two pure
// functions: legalActions(state) and apply(state, action). The UI, the bots,
// undo, replay and simulation all call these, so the log and the snapshot can
// never drift apart.
//
// Every physical part is a *copy* with its own id (7H#1, 7H#2) pointing at a
// shared *definition*. Shuffles and rolls come from a seeded generator whose
// position is saved, so seed + log replays to the identical snapshot.

import { compile, evaluate, type Scope } from './expr';

// ─── Data shapes (what the Game and Match cards hold) ─────────────────────
export type Kind =
  | 'card'
  | 'die'
  | 'coin'
  | 'chip'
  | 'tile'
  | 'board'
  | 'token'
  | 'piece';

export interface Look {
  shape?: string; // rect | rounded | circle | hex | meeple | pawn | custom
  path?: string; // custom SVG path (0–100 box) when shape is custom
  fill?: string;
  edge?: string;
  ink?: string;
  imageUrl?: string;
  backPattern?: string; // lattice | stripes | dots | plain
  backColour?: string;
  depth?: number; // 0–3: how "3D" the shadow and edge read
  size?: number; // relative, 1 = the zone's default
}

export interface Face {
  label?: string;
  value?: number;
  image?: string;
  pips?: number;
}

export interface CompDef {
  id: string;
  kind: Kind;
  name?: string;
  faces?: Face[];
  value?: number;
  alt?: number; // an alternative value (an ace's 11) used by best()
  rank?: string;
  suit?: string;
  tags?: string[];
  look?: Look;
  quantity?: number;
  startZone?: string;
  owner?: string; // seat that owns every copy (chess colours)
}

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface ZoneSpec extends Partial<Rect> {
  id: string;
  kind: 'stack' | 'spread' | 'fan' | 'grid' | 'track' | 'pot';
  label?: string;
  name?: string; // prose name for copy histories ("your hand")
  badge?: string; // expression shown next to the label, e.g. a hand total
  owner?: string;
  ordered?: boolean;
  visibleTo?: 'all' | 'none' | 'owner';
  partW?: number; // part width in table units
  cols?: number;
  rows?: number;
  coords?: 'algebraic' | 'index';
  length?: number; // track length
  path?: 'boustrophedon' | 'row';
  board?: string; // a board definition drawn under this zone
  image?: string; // art drawn in the zone, under its parts (a monster's portrait, a location)
  narrow?: Rect & { partW?: number }; // alternative placement for narrow containers
  hidden?: boolean; // logical zone, not drawn
}

export interface Meter {
  seat?: string;
  resource?: string;
  var?: string;
  label: string;
  look?: 'chips' | 'number';
  x: number;
  y: number;
  narrow?: { x: number; y: number };
}

export interface Layout {
  aspect?: number; // table width / height
  narrowAspect?: number;
  zones: ZoneSpec[];
  meters?: Meter[];
}

export type Effect = Record<string, any>;

export interface ActionSpec {
  id: string;
  label?: string;
  who?: string; // 'current' (default) | seat id
  phase?: string | string[];
  when?: string;
  options?: Record<string, any[]>; // expands into one legal action per value
  effect: Effect[];
  key?: string; // keyboard shortcut
  bot?: boolean; // false: bots never pick it (resign)
  clickZone?: string; // shorthand for gesture.click
  gesture?: Gesture; // how the action is performed on the table
  button?: boolean; // false: no fallback button (gesture only)
}

// Actions as things you do to the table, so a sketch can wire them up.
//   click: an area           { "click": "shoe" }
//   drag a part across       { "drag": { "from": "hand:you", "to": "discard" } }
//   drag chips onto an area  { "drag": { "chips": "chips", "to": "bet", "arg": "amount" } }
export interface Gesture {
  click?: string;
  drag?: {
    from?: string;
    to: string;
    chips?: string;
    arg?: string;
    pick?: 'top' | 'any';
  };
}

export interface PhaseSpec {
  id: string;
  label?: string;
  seat?: string;
  onEnter?: Effect[];
}

export interface Ruleset {
  options?: Record<string, any>;
  defines?: Record<string, { params?: string[]; expr: string } | string>;
  setup?: Effect[];
  turnOrder?: 'clockwise' | string[];
  phases?: PhaseSpec[];
  actions?: ActionSpec[];
  winConditions?: Effect[];
  maxActions?: number;
}

export interface GameData {
  title: string;
  components: CompDef[];
  layout: Layout;
  ruleset: Ruleset;
  ruleModule?: string;
  cardLook?: Look; // shared look for card backs
}

export interface Copy {
  copyId: string;
  defId: string;
  zone: string;
  position: number;
  facing: 'up' | 'down';
  orientation: number;
  visibleTo: string; // 'all' | 'none' | comma-separated seat ids
  counters: Record<string, any>;
  owner?: string;
  history: number[];
}

export interface Seat {
  id: string;
  label: string;
  occupant: 'human' | 'bot' | 'empty';
  opponentId?: string;
  colour?: string;
  resources: Record<string, number>;
}

export interface LogEntry {
  index: number;
  turn: number;
  seat: string;
  action: string;
  args: Record<string, any>;
  rngCalls: number;
  resultSummary: string;
  undone?: boolean;
  at?: string;
}

export interface State {
  seed: number;
  rngCalls: number;
  status: 'setup' | 'playing' | 'finished';
  seats: Seat[];
  copies: Copy[];
  turn: { seat: string; phase: string; number: number };
  vars: Record<string, any>;
  log: LogEntry[];
  result?: { winner: string | null; text: string };
}

export interface Action {
  id: string;
  seat: string;
  args?: Record<string, any>;
}

export interface LegalAction extends Action {
  label: string;
  key?: string;
  bot?: boolean;
  clickZone?: string;
  chipDrag?: { resource: string; to: string; value: number };
  button?: boolean;
  // board interaction hints for the table UI
  from?: string; // copy id that is picked up
  to?: { zone: string; position: number };
}

export type AnimEvent =
  | {
      type: 'move';
      copyId: string;
      from: { zone: string; position: number };
      to: { zone: string; position: number };
      path?: number[]; // track squares walked, in order
      jump?: boolean; // a snake or ladder
      capture?: boolean;
    }
  | { type: 'flip'; copyId: string }
  | { type: 'roll'; copyId: string; face: number }
  | { type: 'shuffle'; zone: string };

// ─── Rule modules: code for what JSON can't say (chess legality) ──────────
export interface ModuleCtx {
  game: GameData;
  defs: Map<string, CompDef>;
  rng: Rng;
  logIndex: number;
  events: AnimEvent[];
  say(text: string): void;
  move(
    c: Copy,
    zone: string,
    position: number,
    extra?: Partial<AnimEvent>,
  ): void;
  touch(c: Copy): void;
}

export interface RuleModule {
  legalActions(state: State, seat: string, game: GameData): LegalAction[];
  apply(state: State, action: Action, ctx: ModuleCtx): void;
  result?(state: State, game: GameData): State['result'] | null;
  evaluate?(state: State, seat: string, game: GameData, scoring: any): number;
  setupBoard?(state: State, game: GameData): void;
}

const modules = new Map<string, RuleModule>();
export function registerModule(id: string, m: RuleModule) {
  modules.set(id, m);
}
export function moduleFor(game: GameData) {
  return game.ruleModule ? modules.get(game.ruleModule) : undefined;
}
export function knownModules() {
  return [...modules.keys()];
}

// ─── Seeded RNG (mulberry32); its position is part of the saved state ─────
export interface Rng {
  next(): number;
  int(n: number): number;
  readonly calls: number;
}
export function makeRng(seed: number, skip = 0): Rng {
  let a = seed >>> 0;
  let calls = 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    calls++;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  for (let i = 0; i < skip; i++) next();
  return {
    next,
    int: (n: number) => Math.floor(next() * n),
    get calls() {
      return calls;
    },
  };
}

// ─── Helpers ──────────────────────────────────────────────────────────────
export function defMap(game: GameData) {
  return new Map(game.components.map((d) => [d.id, d]));
}
export function zoneMap(game: GameData) {
  return new Map(game.layout.zones.map((z) => [z.id, z]));
}
export function inZone(state: State, zone: string) {
  return state.copies
    .filter((c) => c.zone === zone)
    .sort((a, b) => a.position - b.position);
}
export function isVisible(c: Copy, seat: string | null) {
  if (c.visibleTo === 'all') return true;
  if (c.visibleTo === 'none' || !seat) return false;
  return c.visibleTo.split(',').includes(seat);
}
// The effective definition id of a copy (a promoted pawn reads as a queen).
export function effectiveDef(c: Copy) {
  return c.counters?.becomes ?? c.defId;
}
function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v));
}
function renumber(state: State, zone: string) {
  inZone(state, zone).forEach((c, i) => (c.position = i));
}

// The state as one seat may see it. Hidden copies lose their identity, so a
// bot reading this cannot peek at the human's hand.
export function seatView(state: State, seat: string | null): State {
  let v = clone(state);
  v.copies = v.copies.map((c) =>
    isVisible(c, seat) ? c : { ...c, defId: '?', counters: {} },
  );
  return v;
}

// ─── Expressions against a state ──────────────────────────────────────────
interface Ctx {
  game: GameData;
  state: State;
  defs: Map<string, CompDef>;
  seat: string; // the acting seat
  args: Record<string, any>;
  locals: Record<string, any>;
  rng?: Rng;
  logIndex: number;
  events: AnimEvent[];
  summary: string[];
  touched: Set<string>;
  depth?: number;
}

function zoneArg(ctx: Ctx, z: any) {
  if (typeof z !== 'string') throw new Error(`zone name expected, got ${z}`);
  return z;
}

function cardValues(ctx: Ctx, zone: string) {
  return inZone(ctx.state, zone).map((c) => {
    let d = ctx.defs.get(effectiveDef(c));
    return { v: d?.value ?? 0, alt: d?.alt };
  });
}

function bestTotal(ctx: Ctx, zone: string, limit: number) {
  let vals = cardValues(ctx, zone);
  let total = vals.reduce((s, x) => s + x.v, 0);
  let soft = false;
  for (let x of vals) {
    if (x.alt !== undefined && total - x.v + x.alt <= limit) {
      total = total - x.v + x.alt;
      soft = true;
    }
  }
  return { total, soft };
}

function tokenOf(ctx: Ctx, seat: string) {
  return ctx.state.copies.find((c) => {
    let d = ctx.defs.get(c.defId);
    return c.owner === seat && (d?.kind === 'token' || d?.kind === 'piece');
  });
}

function scopeFor(ctx: Ctx): Scope {
  const rules = ctx.game.ruleset.options ?? {};
  const scope: Scope = {
    name(path) {
      let [head, ...rest] = path;
      let base: any;
      if (head in ctx.locals) base = ctx.locals[head];
      else if (head === 'args') base = ctx.args;
      else if (head === 'rules') base = rules;
      else if (head === 'vars') base = ctx.state.vars;
      else if (head === 'self' || head === 'seat') base = ctx.seat;
      else if (head === 'turn') base = ctx.state.turn.seat;
      else if (head === 'phase') base = ctx.state.turn.phase;
      else if (head === 'move') base = ctx.state.turn.number;
      else if (head in ctx.state.vars) base = ctx.state.vars[head];
      else throw new Error(`unknown name "${path.join('.')}"`);
      for (let p of rest) base = base?.[p];
      return base;
    },
    call(fn, a) {
      switch (fn) {
        case 'count':
          return inZone(ctx.state, zoneArg(ctx, a[0])).length;
        case 'total':
          return cardValues(ctx, zoneArg(ctx, a[0])).reduce(
            (s, x) => s + x.v,
            0,
          );
        case 'best':
          return bestTotal(ctx, zoneArg(ctx, a[0]), Number(a[1] ?? Infinity))
            .total;
        case 'soft':
          return bestTotal(ctx, zoneArg(ctx, a[0]), Number(a[1] ?? Infinity))
            .soft;
        case 'top': {
          let z = inZone(ctx.state, zoneArg(ctx, a[0]));
          let c = z[z.length - 1];
          return c ? (ctx.defs.get(effectiveDef(c))?.value ?? 0) : 0;
        }
        case 'faceUp':
          return inZone(ctx.state, zoneArg(ctx, a[0])).filter(
            (c) => c.facing === 'up',
          ).length;
        case 'res':
          return (
            ctx.state.seats.find((s) => s.id === a[0])?.resources[
              a[1] as string
            ] ?? 0
          );
        case 'pos': {
          let t = tokenOf(ctx, String(a[0]));
          return t && t.zone !== 'start' ? t.position : 0;
        }
        case 'other': {
          let order = seatOrder(ctx.state, ctx.game);
          let i = order.indexOf(String(a[0] ?? ctx.seat));
          return order[(i + 1) % order.length];
        }
        case 'concat':
          return a.join('');
        case 'min':
          return Math.min(...(a as number[]));
        case 'max':
          return Math.max(...(a as number[]));
        case 'floor':
          return Math.floor(a[0] as number);
        case 'abs':
          return Math.abs(a[0] as number);
        case 'label':
          return (
            ctx.state.seats.find((s) => s.id === a[0])?.label ?? String(a[0])
          );
      }
      let def = ctx.game.ruleset.defines?.[fn];
      if (def !== undefined) {
        if ((ctx.depth ?? 0) > 20)
          throw new Error(`"${fn}" calls itself too deeply`);
        let d = typeof def === 'string' ? { expr: def, params: ['s'] } : def;
        let locals = { ...ctx.locals };
        (d.params ?? []).forEach((p, i) => (locals[p] = a[i]));
        let sub = { ...ctx, locals, depth: (ctx.depth ?? 0) + 1 };
        return evaluate(compile(d.expr), scopeFor(sub));
      }
      throw new Error(`unknown function "${fn}"`);
    },
  };
  return scope;
}

function ev(ctx: Ctx, src: any): any {
  if (typeof src === 'number' || typeof src === 'boolean') return src;
  if (typeof src !== 'string') return src;
  return evaluate(compile(src), scopeFor(ctx));
}

// "Dealer busts with {handTotal('dealer')}" → "Dealer busts with 23"
export function fill(ctx: Ctx, tpl: string): string {
  return tpl.replace(/\{([^{}]+)\}/g, (_m, e) => String(ev(ctx, e)));
}

// ─── Turn order ───────────────────────────────────────────────────────────
function seatOrder(state: State, game: GameData) {
  let order = Array.isArray(game.ruleset.turnOrder)
    ? game.ruleset.turnOrder
    : state.seats.map((s) => s.id);
  return order.filter((id) =>
    state.seats.find((s) => s.id === id && s.occupant !== 'empty'),
  );
}

// ─── Effects (the JSON building blocks) ───────────────────────────────────
function moveCopy(
  ctx: Ctx,
  c: Copy,
  zone: string,
  position: number,
  extra: Partial<AnimEvent> = {},
) {
  let from = { zone: c.zone, position: c.position };
  c.zone = zone;
  c.position = position;
  touch(ctx, c);
  ctx.events.push({
    type: 'move',
    copyId: c.copyId,
    from,
    to: { zone, position },
    ...extra,
  } as AnimEvent);
}
function touch(ctx: Ctx, c: Copy) {
  if (ctx.logIndex < 0) return;
  if (!ctx.touched.has(c.copyId)) {
    ctx.touched.add(c.copyId);
    if (c.history[c.history.length - 1] !== ctx.logIndex)
      c.history.push(ctx.logIndex);
  }
}

function visibilityFor(
  facing: string,
  v: string | undefined,
  zoneOwner: string | undefined,
) {
  if (v === 'owner') return zoneOwner ?? 'none';
  if (v) return v;
  return facing === 'up' ? 'all' : 'none';
}

function pick(ctx: Ctx, zone: string, take: string, n: number) {
  let list = inZone(ctx.state, zone);
  if (take === 'bottom') return list.slice(0, n);
  if (take === 'all') return list;
  if (take === 'random') {
    let out: Copy[] = [];
    for (let i = 0; i < n && list.length; i++)
      out.push(list.splice(ctx.rng!.int(list.length), 1)[0]);
    return out;
  }
  return list.slice(-n).reverse(); // top first
}

const zoneKeys = ['from', 'to', 'zone', 'along'];

function runEffects(ctx: Ctx, effs: Effect[] | undefined) {
  for (let e of effs ?? []) {
    if (ctx.state.status === 'finished') return;
    runEffect(ctx, e);
  }
}

export const EFFECT_KEYS = [
  'shuffle',
  'move',
  'flip',
  'roll',
  'moveToken',
  'jumps',
  'place',
  'set',
  'add',
  'resource',
  'if',
  'phase',
  'nextTurn',
  'turn',
  'end',
  'log',
  'collect',
  'counter',
  'tap',
  'repeat',
];

function runEffect(ctx: Ctx, e: Effect) {
  const zt = (z: string) => fill(ctx, z);
  if ('shuffle' in e) {
    let zone = zt(e.shuffle);
    let list = inZone(ctx.state, zone);
    for (let i = list.length - 1; i > 0; i--) {
      let j = ctx.rng!.int(i + 1);
      [list[i], list[j]] = [list[j], list[i]];
    }
    list.forEach((c, i) => {
      c.position = i;
      touch(ctx, c);
    });
    ctx.events.push({ type: 'shuffle', zone });
    return;
  }
  if ('move' in e) {
    let m = e.move;
    let to = zt(m.to);
    let n = m.count === undefined ? 1 : Number(ev(ctx, m.count));
    let chosen = m.copy
      ? ctx.state.copies.find((c) => c.copyId === ev(ctx, m.copy))
      : undefined;
    if (m.copy && !chosen) throw new Error(`no copy "${m.copy}" to move`);
    let from = chosen ? chosen.zone : zt(m.from);
    let picked = chosen ? [chosen] : pick(ctx, from, m.take ?? 'top', n);
    let dest = zoneMap(ctx.game).get(to);
    for (let c of picked) {
      let pos = inZone(ctx.state, to).length;
      if (m.facing && m.facing !== 'keep') {
        let wasUp = c.facing === 'up';
        c.facing = m.facing;
        if (wasUp !== (c.facing === 'up'))
          ctx.events.push({ type: 'flip', copyId: c.copyId });
      }
      c.visibleTo = visibilityFor(c.facing, m.visibleTo, dest?.owner);
      moveCopy(ctx, c, to, pos);
    }
    renumber(ctx.state, from);
    if (picked.length < n && m.ifEmpty) runEffects(ctx, m.ifEmpty);
    return;
  }
  if ('collect' in e) {
    let m = e.collect;
    let to = zt(m.to);
    for (let z of (m.from as string[]).map(zt)) {
      for (let c of inZone(ctx.state, z)) {
        let pos = inZone(ctx.state, to).length;
        if (m.facing) c.facing = m.facing;
        c.visibleTo = visibilityFor(c.facing, m.visibleTo, undefined);
        c.orientation = 0;
        moveCopy(ctx, c, to, pos);
      }
    }
    return;
  }
  if ('flip' in e) {
    let f = typeof e.flip === 'string' ? { zone: e.flip } : e.flip;
    let list = inZone(ctx.state, zt(f.zone));
    if (f.which === 'top') list = list.slice(-1);
    for (let c of list) {
      let next = f.facing ?? (c.facing === 'up' ? 'down' : 'up');
      if (c.facing !== next) {
        c.facing = next;
        c.visibleTo = next === 'up' ? 'all' : 'none';
        touch(ctx, c);
        ctx.events.push({ type: 'flip', copyId: c.copyId });
      }
    }
    return;
  }
  if ('tap' in e) {
    let list = inZone(ctx.state, zt(e.tap.zone));
    for (let c of list) {
      c.orientation = (c.orientation + (e.tap.by ?? 90)) % 360;
      touch(ctx, c);
    }
    return;
  }
  if ('roll' in e) {
    let die = ctx.state.copies.find(
      (c) => c.defId === e.roll || c.copyId === e.roll,
    );
    if (!die) throw new Error(`no die "${e.roll}" on the table`);
    let d = ctx.defs.get(die.defId)!;
    let faces = d.faces ?? [1, 2, 3, 4, 5, 6].map((v) => ({ value: v }));
    let i = ctx.rng!.int(faces.length);
    die.counters = { ...die.counters, face: i };
    touch(ctx, die);
    ctx.events.push({ type: 'roll', copyId: die.copyId, face: i });
    let value = faces[i].value ?? i + 1;
    ctx.locals[e.as ?? 'roll'] = value;
    ctx.state.vars.lastRoll = value;
    if (e.log !== false) ctx.summary.push(`rolled ${value}`);
    return;
  }
  if ('moveToken' in e) {
    let m =
      typeof e.moveToken === 'string'
        ? { token: e.moveToken, ...e }
        : e.moveToken;
    let seat = m.token === 'own' || !m.token ? ctx.seat : zt(m.token);
    let t = tokenOf(ctx, seat);
    if (!t) throw new Error(`seat "${seat}" has no token`);
    let along = zt(m.along ?? 'track');
    let len = zoneMap(ctx.game).get(along)?.length ?? 100;
    let cur = t.zone === along ? t.position : 0;
    let by = Number(ev(ctx, m.by));
    let next = cur + by;
    let path: number[] = [];
    if (next > len) {
      if ((m.overshoot ?? 'stay') === 'stay') {
        ctx.summary.push(`needs exactly ${len - cur}, stays on ${cur}`);
        ctx.locals.moved = false;
        return;
      }
      if (m.overshoot === 'bounce') {
        for (let s = cur + 1; s <= len; s++) path.push(s);
        next = len - (next - len);
        for (let s = len - 1; s >= next; s--) path.push(s);
      } else next = len;
    }
    if (!path.length) for (let s = cur + 1; s <= next; s++) path.push(s);
    moveCopy(ctx, t, along, next, { path });
    ctx.locals.moved = true;
    ctx.summary.push(`moves to ${next}`);
    return;
  }
  if ('jumps' in e) {
    let t = tokenOf(ctx, ctx.seat);
    if (!t) return;
    let to = e.jumps[String(t.position)];
    if (to !== undefined) {
      let up = to > t.position;
      ctx.summary.push(
        up ? `climbs a ladder to ${to}` : `slides down a snake to ${to}`,
      );
      moveCopy(ctx, t, t.zone, Number(to), { jump: true });
    }
    return;
  }
  if ('place' in e) {
    // { place: "token", each: "seat", to: "start" }  or
    // { place: { zone: "board", at: { "a1": "wR", ... } } }
    if (typeof e.place === 'string') {
      let free = ctx.state.copies.filter((c) => c.defId === e.place);
      let seats = seatOrder(ctx.state, ctx.game);
      seats.forEach((s, i) => {
        let c = free[i];
        if (!c) return;
        c.owner = s;
        c.facing = 'up';
        c.visibleTo = 'all';
        moveCopy(ctx, c, zt(e.to), 0);
      });
      return;
    }
    let zone = ctx.game.layout.zones.find((z) => z.id === e.place.zone)!;
    let used = new Set<string>();
    for (let [sq, defId] of Object.entries(
      e.place.at as Record<string, string>,
    )) {
      let c = ctx.state.copies.find(
        (x) => x.defId === defId && !used.has(x.copyId) && x.zone !== zone.id,
      );
      if (!c)
        throw new Error(`not enough copies of "${defId}" to place on ${sq}`);
      used.add(c.copyId);
      c.facing = 'up';
      c.visibleTo = 'all';
      moveCopy(ctx, c, zone.id, squareIndex(zone, sq));
    }
    return;
  }
  if ('set' in e) {
    ctx.state.vars[e.set] = ev(ctx, e.to);
    return;
  }
  if ('add' in e) {
    ctx.state.vars[e.add] =
      (Number(ctx.state.vars[e.add]) || 0) + Number(ev(ctx, e.by ?? 1));
    return;
  }
  if ('resource' in e) {
    let r = e.resource;
    let seat = ctx.state.seats.find((s) => s.id === zt(r.seat ?? '{seat}'));
    if (!seat) throw new Error(`no seat "${r.seat}"`);
    let cur = seat.resources[r.name] ?? 0;
    seat.resources = {
      ...seat.resources,
      [r.name]:
        r.set !== undefined
          ? Number(ev(ctx, r.set))
          : cur + Number(ev(ctx, r.add)),
    };
    return;
  }
  if ('if' in e) {
    runEffects(ctx, ev(ctx, e.if) ? e.then : e.else);
    return;
  }
  if ('repeat' in e) {
    let n = Number(ev(ctx, e.repeat));
    for (let i = 0; i < n; i++) runEffects(ctx, e.do);
    return;
  }
  if ('phase' in e) {
    enterPhase(ctx, zt(e.phase));
    return;
  }
  if ('nextTurn' in e) {
    let order = seatOrder(ctx.state, ctx.game);
    let i = order.indexOf(ctx.state.turn.seat);
    ctx.state.turn.seat = order[(i + 1) % order.length];
    ctx.state.turn.number++;
    let first = ctx.game.ruleset.phases?.[0];
    if (first && e.nextTurn !== 'samePhase') enterPhase(ctx, first.id, true);
    return;
  }
  if ('turn' in e) {
    let s = zt(e.turn);
    if (s !== ctx.state.turn.seat) {
      ctx.state.turn.seat = s;
      ctx.state.turn.number++;
    }
    return;
  }
  if ('end' in e) {
    let winner =
      e.end.winner === undefined || e.end.winner === null
        ? null
        : String(ev(ctx, e.end.winner));
    ctx.state.status = 'finished';
    ctx.state.result = {
      winner,
      text: fill(ctx, e.end.text ?? (winner ? `${winner} wins` : 'Draw')),
    };
    return;
  }
  if ('log' in e) {
    ctx.summary.push(fill(ctx, e.log));
    return;
  }
  if ('counter' in e) {
    let m = e.counter;
    let list = m.copy
      ? ctx.state.copies.filter((c) => c.copyId === zt(m.copy))
      : inZone(ctx.state, zt(m.zone)).slice(m.which === 'all' ? 0 : -1);
    for (let c of list) {
      let cur = Number(c.counters[m.name] ?? 0);
      c.counters = {
        ...c.counters,
        [m.name]:
          m.set !== undefined
            ? ev(ctx, m.set)
            : cur + Number(ev(ctx, m.add ?? 1)),
      };
      touch(ctx, c);
    }
    return;
  }
  throw new Error(`unknown effect ${JSON.stringify(Object.keys(e))}`);
}

function enterPhase(ctx: Ctx, id: string, keepSeat = false) {
  let p = ctx.game.ruleset.phases?.find((x) => x.id === id);
  if (!p) throw new Error(`no phase "${id}"`);
  ctx.state.turn.phase = id;
  if (p.seat && !keepSeat) {
    let s = fill(ctx, p.seat);
    if (s !== ctx.state.turn.seat) {
      ctx.state.turn.seat = s;
      ctx.state.turn.number++;
    }
  }
  runEffects(ctx, p.onEnter);
}

export function squareIndex(zone: ZoneSpec, sq: string | number) {
  if (typeof sq === 'number' || /^\d+$/.test(sq)) return Number(sq);
  let file = sq.charCodeAt(0) - 97;
  let rank = Number(sq.slice(1)) - 1;
  return rank * (zone.cols ?? 8) + file;
}
export function squareName(zone: ZoneSpec | undefined, i: number) {
  let cols = zone?.cols ?? 8;
  return String.fromCharCode(97 + (i % cols)) + (Math.floor(i / cols) + 1);
}

// ─── Building a match ─────────────────────────────────────────────────────
export function createCopies(game: GameData): Copy[] {
  let out: Copy[] = [];
  for (let d of game.components) {
    let q = d.quantity ?? 1;
    for (let i = 1; i <= q; i++) {
      out.push({
        copyId: `${d.id}#${i}`,
        defId: d.id,
        zone: d.startZone ?? (d.kind === 'board' ? 'table' : 'supply'),
        position: i - 1,
        facing: d.kind === 'card' ? 'down' : 'up',
        orientation: 0,
        visibleTo: d.kind === 'card' ? 'none' : 'all',
        counters: {},
        owner: d.owner,
        history: [0],
      });
    }
  }
  return out;
}

function mkCtx(
  game: GameData,
  state: State,
  seat: string,
  args: Record<string, any>,
  logIndex: number,
): Ctx {
  return {
    game,
    state,
    defs: defMap(game),
    seat,
    args,
    locals: {},
    rng: makeRng(state.seed, state.rngCalls),
    logIndex,
    events: [],
    summary: [],
    touched: new Set(),
  };
}

export function newMatch(
  game: GameData,
  seats: Seat[],
  seed: number,
): { state: State; events: AnimEvent[] } {
  let state: State = {
    seed,
    rngCalls: 0,
    status: 'playing',
    seats: clone(seats),
    copies: createCopies(game),
    turn: {
      seat: '',
      phase: game.ruleset.phases?.[0]?.id ?? 'main',
      number: 1,
    },
    vars: {},
    log: [],
  };
  let first = game.ruleset.phases?.[0]?.seat;
  state.turn.seat =
    first && !first.includes('{')
      ? first
      : (seatOrder(state, game)[0] ?? seats[0].id);
  let ctx = mkCtx(game, state, state.turn.seat, {}, 0);
  let m = moduleFor(game);
  runEffects(ctx, game.ruleset.setup);
  m?.setupBoard?.(state, game);
  state.rngCalls = ctx.rng!.calls;
  state.log.push({
    index: 0,
    turn: 0,
    seat: '',
    action: 'setup',
    args: { seats: clone(seats) },
    rngCalls: ctx.rng!.calls,
    resultSummary:
      ctx.summary.join('; ') || `${state.copies.length} parts set out`,
  });
  checkWin(game, state);
  return { state, events: ctx.events };
}

// ─── Legal actions ────────────────────────────────────────────────────────
export function legalActions(
  game: GameData,
  state: State,
  seat?: string,
): LegalAction[] {
  if (state.status !== 'playing') return [];
  let m = moduleFor(game);
  let who = seat ?? state.turn.seat;
  if (m) return m.legalActions(state, who, game);
  let out: LegalAction[] = [];
  for (let a of game.ruleset.actions ?? []) {
    let phases =
      a.phase === undefined
        ? null
        : Array.isArray(a.phase)
          ? a.phase
          : [a.phase];
    if (phases && !phases.includes(state.turn.phase)) continue;
    let actor = !a.who || a.who === 'current' ? state.turn.seat : a.who;
    if (actor !== who) continue;
    let g: Gesture | undefined =
      a.gesture ?? (a.clickZone ? { click: a.clickZone } : undefined);
    for (let args of expandOptions(a.options)) {
      let ctx = mkCtx(game, state, who, args, -1);
      let base: LegalAction = {
        id: a.id,
        seat: who,
        args,
        label: '',
        key: a.key,
        bot: a.bot,
        button: a.button,
        clickZone: g?.click ? fill(ctx, g.click) : undefined,
      };
      if (g?.drag?.from) {
        // one legal action per copy that may be picked up
        let from = fill(ctx, g.drag.from);
        let to = fill(ctx, g.drag.to);
        let copies = inZone(state, from);
        for (let c of g.drag.pick === 'any' ? copies : copies.slice(-1)) {
          let a2 = { ...args, copy: c.copyId };
          let c2 = mkCtx(game, state, who, a2, -1);
          if (a.when && !ev(c2, a.when)) continue;
          out.push({
            ...base,
            args: a2,
            label: a.label ? fill(c2, a.label) : a.id,
            from: c.copyId,
            to: { zone: to, position: -1 },
          });
        }
        continue;
      }
      if (a.when && !ev(ctx, a.when)) continue;
      base.label = a.label ? fill(ctx, a.label) : a.id;
      if (g?.drag?.chips) {
        let key = g.drag.arg ?? Object.keys(args)[0];
        base.chipDrag = {
          resource: g.drag.chips,
          to: fill(ctx, g.drag.to),
          value: Number(args[key]),
        };
      }
      out.push(base);
    }
  }
  return out;
}

function expandOptions(opts?: Record<string, any[]>) {
  let combos: Record<string, any>[] = [{}];
  for (let [k, vals] of Object.entries(opts ?? {})) {
    combos = combos.flatMap((c) => vals.map((v) => ({ ...c, [k]: v })));
  }
  return combos;
}

export function sameAction(a: Action, b: Action) {
  return (
    a.id === b.id &&
    a.seat === b.seat &&
    JSON.stringify(a.args ?? {}) === JSON.stringify(b.args ?? {})
  );
}

// ─── Apply ────────────────────────────────────────────────────────────────
export interface ApplyOpts {
  sim?: boolean; // skip log and history (search, simulation)
  at?: string;
  skipLegalCheck?: boolean;
}

export function apply(
  game: GameData,
  prev: State,
  action: Action,
  opts: ApplyOpts = {},
): { state: State; events: AnimEvent[] } {
  let legal = opts.skipLegalCheck
    ? null
    : legalActions(game, prev, action.seat);
  if (legal && !legal.some((l) => sameAction(l, action))) {
    throw new Error(`"${action.id}" is not legal for ${action.seat} right now`);
  }
  let state = clone(prev);
  let index = state.log.length;
  let ctx = mkCtx(
    game,
    state,
    action.seat,
    action.args ?? {},
    opts.sim ? -1 : index,
  );
  let m = moduleFor(game);
  let turnBefore = state.turn.number;
  if (m) {
    m.apply(state, action, {
      game,
      defs: ctx.defs,
      rng: ctx.rng!,
      logIndex: ctx.logIndex,
      events: ctx.events,
      say: (t) => ctx.summary.push(t),
      move: (c, zone, pos, extra) => moveCopy(ctx, c, zone, pos, extra),
      touch: (c) => touch(ctx, c),
    });
  } else {
    let spec = game.ruleset.actions?.find(
      (a) =>
        a.id === action.id &&
        (a.phase === undefined ||
          (Array.isArray(a.phase) ? a.phase : [a.phase]).includes(
            prev.turn.phase,
          )),
    );
    if (!spec) throw new Error(`no action "${action.id}"`);
    runEffects(ctx, spec.effect);
  }
  checkWin(game, state);
  let max = game.ruleset.maxActions;
  if (max && state.status === 'playing' && index >= max) {
    state.status = 'finished';
    state.result = { winner: null, text: `Stopped after ${max} actions` };
  }
  state.rngCalls = ctx.rng!.calls;
  if (opts.sim) return { state, events: ctx.events };
  state.log.push({
    index,
    turn: turnBefore,
    seat: action.seat,
    action: action.id,
    args: action.args ?? {},
    rngCalls: ctx.rng!.calls - prev.rngCalls,
    resultSummary: ctx.summary.join('; '),
    ...(opts.at ? { at: opts.at } : {}),
  });
  return { state, events: ctx.events };
}

function checkWin(game: GameData, state: State) {
  if (state.status !== 'playing') return;
  let m = moduleFor(game);
  if (m?.result) {
    let r = m.result(state, game);
    if (r) {
      state.status = 'finished';
      state.result = r;
    }
    return;
  }
  for (let w of game.ruleset.winConditions ?? []) {
    if ('tokenOn' in w) {
      let [zone, pos] = String(w.tokenOn).split(':');
      let c = state.copies.find(
        (x) => x.zone === zone && x.position === Number(pos) && x.owner,
      );
      if (c) {
        let seat = state.seats.find((s) => s.id === c!.owner);
        state.status = 'finished';
        state.result = {
          winner: c.owner!,
          text: `${seat?.label ?? c.owner} reaches ${pos}`,
        };
        return;
      }
    } else if ('when' in w) {
      let ctx = mkCtx(game, state, state.turn.seat, {}, -1);
      if (ev(ctx, w.when)) {
        let winner =
          w.winner === undefined || w.winner === null
            ? null
            : String(ev(ctx, w.winner));
        state.status = 'finished';
        state.result = {
          winner,
          text: w.text ? fill(ctx, w.text) : winner ? `${winner} wins` : 'Draw',
        };
        return;
      }
    }
  }
}

// ─── Undo, replay ─────────────────────────────────────────────────────────
// Rebuild a state by replaying the log from the seed. Undone entries are kept
// in the log (struck through in the UI) but skipped, so indices stay stable.
export function replay(
  game: GameData,
  log: LogEntry[],
  seed: number,
  upto = log.length,
): State {
  let setup = log[0];
  let { state } = newMatch(game, setup.args.seats, seed);
  for (let i = 1; i < upto; i++) {
    let e = log[i];
    if (e.undone) {
      state.log.push(clone(e));
      continue;
    }
    let r = apply(
      game,
      state,
      { id: e.action, seat: e.seat, args: e.args },
      { at: e.at, skipLegalCheck: true },
    );
    state = r.state;
  }
  return state;
}

// Undo the last human action and every bot reply after it.
export function undo(
  game: GameData,
  state: State,
  human: string,
): State | null {
  let log = clone(state.log);
  let i = log.length - 1;
  while (i > 0 && (log[i].undone || log[i].seat !== human)) i--;
  if (i <= 0) return null;
  for (let j = i; j < log.length; j++) log[j].undone = true;
  let rebuilt = replay(game, log, state.seed, i);
  for (let j = i; j < log.length; j++) rebuilt.log.push(log[j]);
  return rebuilt;
}

// Snapshot comparison for the "replay matches" proof (timestamps excluded).
export function fingerprint(state: State) {
  let s = clone(state);
  s.log.forEach((e) => delete e.at);
  s.copies.sort((a, b) => (a.copyId < b.copyId ? -1 : 1));
  return JSON.stringify({
    c: s.copies,
    s: s.seats,
    t: s.turn,
    v: s.vars,
    r: s.rngCalls,
    st: s.status,
    res: s.result ?? null,
  });
}

// Where every copy has been, from one replay: "shoe → hand:you (move 12) → discard (move 15)".
export function copyTrails(
  game: GameData,
  state: State,
): Map<string, { index: number; zone: string; position: number }[]> {
  let trails = new Map<
    string,
    { index: number; zone: string; position: number }[]
  >();
  let setup = state.log[0];
  let { state: s } = newMatch(game, setup.args.seats, state.seed);
  for (let c of s.copies)
    trails.set(c.copyId, [{ index: 0, zone: c.zone, position: c.position }]);
  for (let i = 1; i < state.log.length; i++) {
    let e = state.log[i];
    if (e.undone) {
      s.log.push(clone(e));
      continue;
    }
    let r = apply(
      game,
      s,
      { id: e.action, seat: e.seat, args: e.args },
      { skipLegalCheck: true },
    );
    s = r.state;
    for (let ev of r.events) {
      if (ev.type === 'move')
        trails
          .get(ev.copyId)
          ?.push({ index: i, zone: ev.to.zone, position: ev.to.position });
    }
  }
  return trails;
}

// ─── Expressions for the UI (zone badges, labels) ─────────────────────────
export function evalFor(
  game: GameData,
  state: State,
  seat: string,
  src: string,
) {
  try {
    return ev(mkCtx(game, state, seat, {}, -1), src);
  } catch {
    return '';
  }
}
export function fillFor(
  game: GameData,
  state: State,
  seat: string,
  tpl: string,
) {
  try {
    return fill(mkCtx(game, state, seat, {}, -1), tpl);
  } catch {
    return tpl;
  }
}
export function phaseLabel(game: GameData, state: State) {
  let p = game.ruleset.phases?.find((x) => x.id === state.turn.phase);
  return p?.label ? fillFor(game, state, state.turn.seat, p.label) : '';
}

export { zoneKeys };
