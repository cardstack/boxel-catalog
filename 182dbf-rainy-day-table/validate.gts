// Validate Game: plain-sentence problems an agent (or person) can act on,
// then a quick smoke test that plays bot-vs-bot matches headless.

import { compile, namesIn } from './expr';
import type { Effect, GameData, Seat } from './engine';
import { EFFECT_KEYS, knownModules } from './engine';
import type { BotSpec, SimResult } from './bots';
import { simulate, summarise } from './bots';

export interface Finding {
  level: 'error' | 'warning';
  text: string;
}

const KINDS = [
  'card',
  'die',
  'coin',
  'chip',
  'tile',
  'board',
  'token',
  'piece',
];
const ZONE_KINDS = ['stack', 'spread', 'fan', 'grid', 'track', 'pot'];
const BUILTINS = [
  'count',
  'total',
  'best',
  'soft',
  'top',
  'faceUp',
  'res',
  'pos',
  'other',
  'concat',
  'min',
  'max',
  'floor',
  'abs',
  'label',
];

export function validateGame(game: GameData, seats: Seat[] = []): Finding[] {
  let out: Finding[] = [];
  const err = (text: string) => out.push({ level: 'error', text });
  const warn = (text: string) => out.push({ level: 'warning', text });

  let rs = game.ruleset ?? {};
  let defines = new Set(Object.keys(rs.defines ?? {}));
  let phases = new Set((rs.phases ?? []).map((p) => p.id));
  if (!game.components?.length)
    err('The game has no components, so there is nothing to put on the table.');
  let ids = new Set<string>();
  for (let d of game.components ?? []) {
    if (!d.id) err(`A component called "${d.name ?? '?'}" has no id.`);
    else if (ids.has(d.id))
      err(
        `Two components share the id "${d.id}"; every definition needs its own.`,
      );
    ids.add(d.id);
    if (!KINDS.includes(d.kind))
      err(`"${d.id}" has kind "${d.kind}"; use one of ${KINDS.join(', ')}.`);
    if (
      d.quantity !== undefined &&
      (d.quantity < 1 || !Number.isInteger(d.quantity))
    )
      err(
        `"${d.id}" has quantity ${d.quantity}; it must be a whole number of 1 or more.`,
      );
    if (d.kind === 'die' && d.faces && d.faces.length < 2)
      err(`The die "${d.id}" needs at least two faces.`);
  }

  let zones = new Set<string>();
  for (let z of game.layout?.zones ?? []) {
    if (zones.has(z.id)) err(`Two zones share the id "${z.id}".`);
    zones.add(z.id);
    if (!ZONE_KINDS.includes(z.kind))
      err(
        `Zone "${z.id}" has kind "${z.kind}"; use one of ${ZONE_KINDS.join(', ')}.`,
      );
    if (
      !z.hidden &&
      (z.x === undefined ||
        z.y === undefined ||
        z.w === undefined ||
        z.h === undefined)
    ) {
      err(
        `Zone "${z.id}" is drawn but has no position; give it x, y, w and h in table units.`,
      );
    }
    if (z.board && !ids.has(z.board))
      err(
        `Zone "${z.id}" draws board "${z.board}", but no component has that id.`,
      );
    if (z.badge) tryParse(z.badge, `The badge on zone "${z.id}"`);
  }
  for (let d of game.components ?? []) {
    if (d.startZone && !zones.has(d.startZone))
      err(
        `"${d.id}" starts in zone "${d.startZone}", which the layout doesn't define.`,
      );
  }
  // copies without a startZone wait in "supply"; boards sit in "table"
  let needsSupply = game.components?.some(
    (d) => !d.startZone && d.kind !== 'board',
  );
  if (needsSupply && !zones.has('supply'))
    warn(
      'Some components have no startZone and will wait in "supply", but the layout has no "supply" zone. Add one (hidden: true) or give each a startZone.',
    );

  let mod = game.ruleModule;
  if (mod && !knownModules().includes(mod))
    err(
      `The game names rule module "${mod}", but only ${knownModules().join(', ') || 'none'} are installed.`,
    );

  function isCopyOf(ref: string) {
    let [def, n] = String(ref).split('#');
    let d = game.components?.find((x) => x.id === def);
    return !!d && Number(n) >= 1 && Number(n) <= (d.quantity ?? 1);
  }
  function tryParse(src: any, where: string) {
    if (typeof src !== 'string') return;
    try {
      let n = compile(src);
      let { calls } = namesIn(n);
      for (let c of calls) {
        if (!BUILTINS.includes(c) && !defines.has(c))
          err(
            `${where} calls "${c}()", which is neither built in nor in ruleset.defines.`,
          );
      }
    } catch (e: any) {
      err(`${where} can't be read: ${e.message}.`);
    }
  }
  function checkZone(z: any, where: string) {
    if (typeof z !== 'string' || z.includes('{')) return;
    if (!zones.has(z))
      err(`${where} uses zone "${z}", which the layout doesn't define.`);
  }
  function walk(effs: Effect[] | undefined, where: string) {
    for (let e of effs ?? []) {
      let key = EFFECT_KEYS.find((k) => k in e);
      if (!key) {
        err(
          `${where} has an effect I don't recognise: ${JSON.stringify(e).slice(0, 80)}.`,
        );
        continue;
      }
      if (key === 'shuffle') checkZone(e.shuffle, where);
      if (key === 'move') {
        checkZone(e.move.from, where);
        checkZone(e.move.to, where);
        tryParse(
          typeof e.move.count === 'string' ? e.move.count : undefined,
          where,
        );
      }
      if (key === 'collect') {
        (e.collect.from ?? []).forEach((z: string) => checkZone(z, where));
        checkZone(e.collect.to, where);
      }
      if (key === 'flip')
        checkZone(typeof e.flip === 'string' ? e.flip : e.flip.zone, where);
      if (key === 'roll' && !ids.has(e.roll) && !isCopyOf(e.roll))
        err(
          `${where} rolls "${e.roll}", but no component (or copy like "d6#1") has that id.`,
        );
      if (key === 'phase' && !phases.has(e.phase))
        err(`${where} moves to phase "${e.phase}", which isn't defined.`);
      if (key === 'if') {
        tryParse(e.if, where);
        walk(e.then, where);
        walk(e.else, where);
      }
      if (key === 'repeat') walk(e.do, where);
      if (key === 'set') tryParse(e.to, where);
      if (key === 'place' && typeof e.place === 'string' && !ids.has(e.place))
        err(`${where} places "${e.place}", but no component has that id.`);
      if (key === 'place' && typeof e.place === 'object') {
        checkZone(e.place.zone, where);
        for (let d of Object.values(e.place.at ?? {}))
          if (!ids.has(d as string))
            err(`${where} places "${d}", but no component has that id.`);
      }
    }
  }

  for (let [name, d] of Object.entries(rs.defines ?? {}))
    tryParse(typeof d === 'string' ? d : d.expr, `The definition "${name}"`);
  walk(rs.setup, 'Setup');
  for (let p of rs.phases ?? []) walk(p.onEnter, `Phase "${p.id}"`);
  for (let a of rs.actions ?? []) {
    let where = `Action "${a.id}"`;
    if (a.when) tryParse(a.when, `${where}'s condition`);
    for (let ph of a.phase === undefined
      ? []
      : Array.isArray(a.phase)
        ? a.phase
        : [a.phase]) {
      if (!phases.has(ph) && phases.size)
        err(`${where} belongs to phase "${ph}", which isn't defined.`);
    }
    if (a.clickZone) checkZone(a.clickZone, where);
    if (a.gesture?.click)
      checkZone(a.gesture.click, `${where}'s click gesture`);
    if (a.gesture?.drag) {
      checkZone(a.gesture.drag.to, `${where}'s drag gesture`);
      if (a.gesture.drag.from)
        checkZone(a.gesture.drag.from, `${where}'s drag gesture`);
      if (!a.gesture.drag.from && !a.gesture.drag.chips)
        err(
          `${where}'s drag gesture needs "from" (an area) or "chips" (a resource).`,
        );
    }
    walk(a.effect, where);
  }
  if (!mod) {
    for (let p of rs.phases ?? []) {
      let has = (rs.actions ?? []).some(
        (a) =>
          a.phase === undefined ||
          (Array.isArray(a.phase) ? a.phase : [a.phase]).includes(p.id),
      );
      if (!has)
        warn(
          `Phase "${p.id}" has no actions, so play would stop there unless its onEnter moves on.`,
        );
    }
    if (!(rs.actions ?? []).length)
      err(
        'The ruleset has no actions and no rule module, so nobody can do anything.',
      );
    let canEnd =
      JSON.stringify(rs).includes('"end"') ||
      (rs.winConditions ?? []).length > 0;
    if (!canEnd)
      err('Nothing can end the game: add a winCondition or an "end" effect.');
    // turns never pass on their own
    let json = JSON.stringify(rs);
    let seatCount = Array.isArray(rs.turnOrder)
      ? rs.turnOrder.length
      : seats.length;
    let phaseSeats = new Set(
      (rs.phases ?? []).map((p) => p.seat).filter(Boolean),
    );
    let passes =
      json.includes('"nextTurn"') ||
      /"turn"\s*:/.test(json) ||
      phaseSeats.size > 1;
    if (seatCount > 1 && !passes) {
      err(
        'No action ever passes the turn, so the first seat would play every move. End each turn\'s action with {"nextTurn": true}.',
      );
    }
  }
  if (seats.length && rs.turnOrder && Array.isArray(rs.turnOrder)) {
    for (let s of rs.turnOrder)
      if (!seats.some((x) => x.id === s))
        err(
          `turnOrder names seat "${s}", but the game's seats don't include it.`,
        );
  }
  return out;
}

export function smokeTest(
  game: GameData,
  seats: Seat[],
  bots: Record<string, BotSpec>,
  runs = 20,
) {
  let botSeats = seats.map((s) => ({ ...s, occupant: 'bot' as const }));
  let t0 = Date.now();
  let res: SimResult[] = simulate(game, botSeats, bots, runs, 11, 800);
  let sum = summarise(
    res,
    seats.map((s) => s.id),
  );
  return {
    ...sum,
    ms: Date.now() - t0,
    firstStall: res.find((r) => r.stalled)?.stalled,
  };
}
