// The table: a play surface drawn entirely from Game layout + Match state.
// Every copy is one element keyed by its copy id, so when a copy changes zone
// the same element travels there (lift, slide, settle) instead of popping out
// of one pile and into another. Animation is Web Animations, driven by the
// engine's events for the last action (deal stagger, token walks, ladder
// jumps, captures, die tumbles).

import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { on } from '@ember/modifier';
import { concat, fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { AnimEvent, GameData, LegalAction, Look, State } from './engine';
import { defMap, evalFor } from './engine';
import {
  DENOMS,
  aspectOf,
  chipStacks,
  placeCopies,
  rectOf,
  squareAt,
  squareCentre,
  trackPoint,
  zoneBoxes,
} from './layout';
import type { Placed } from './layout';
import { Board, Chip, Die, Piece, PlayingCard, Tile, Token } from './parts';

export interface AnimBatch {
  version: number;
  events: AnimEvent[];
}

interface Hint {
  version: number;
  delay: number;
  path?: { x: number; y: number }[];
  jump?: boolean;
  capture?: boolean;
}

const reduced = () =>
  typeof window !== 'undefined' &&
  window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;

// Glide a copy from where it was to where it is now.
const placeCopy = modifier(
  (
    el: HTMLElement,
    [x, y, rot, hint]: [number, number, number, Hint | null],
  ) => {
    let prev = (el as any).__at as
      | { x: number; y: number; rot: number }
      | undefined;
    (el as any).__at = { x, y, rot };
    if (
      !prev ||
      (prev.x === x && prev.y === y && prev.rot === rot) ||
      reduced()
    )
      return;
    let fresh = hint && (el as any).__hv !== hint.version;
    if (hint) (el as any).__hv = hint.version;
    let pts =
      fresh && hint?.path?.length
        ? [{ x: prev.x, y: prev.y }, ...hint.path]
        : [
            { x: prev.x, y: prev.y },
            { x, y },
          ];
    let dist = Math.hypot(x - prev.x, y - prev.y);
    let dur =
      fresh && hint?.path?.length
        ? Math.min(1400, 150 * (pts.length - 1))
        : fresh && hint?.jump
          ? 520
          : Math.max(220, Math.min(380, 200 + dist * 3));
    let delay = fresh ? hint!.delay : 0;
    let frames: Keyframe[] = pts.map((p, i) => ({
      left: `${p.x}%`,
      top: `${p.y}%`,
      offset: pts.length > 1 ? i / (pts.length - 1) : 1,
    }));
    el.animate(frames, {
      duration: dur,
      delay,
      easing: pts.length > 2 ? 'linear' : 'cubic-bezier(.3,.7,.2,1)',
      fill: 'backwards',
    });
    // lift: scale up and cast a longer shadow mid-flight
    let lift = fresh && hint?.jump ? 1.35 : pts.length > 2 ? 1.08 : 1.1;
    el.animate(
      [
        { scale: 1, offset: 0 },
        { scale: lift, offset: 0.45 },
        { scale: 1, offset: 1 },
      ],
      { duration: dur, delay, easing: 'ease-in-out', composite: 'add' } as any,
    );
    if (fresh && hint?.capture) {
      el.animate([{ rotate: '0deg' }, { rotate: '200deg' }], {
        duration: dur,
        delay,
        easing: 'ease-out',
        composite: 'add',
      } as any);
    }
    if (rot !== prev.rot) {
      el.style.setProperty('--rot', `${rot}deg`);
    }
  },
);

// Drag starts on press (a pointer-up binding can't begin a drag).
const grabOn = modifier((el: HTMLElement, [handler]: [(e: Event) => void]) => {
  el.addEventListener('pointerdown', handler);
  return () => el.removeEventListener('pointerdown', handler);
});

// Same, only when there is something to grab.
const grabIf = modifier(
  (el: HTMLElement, [on, handler]: [unknown, (e: Event) => void]) => {
    if (!on) return;
    el.addEventListener('pointerdown', handler);
    return () => el.removeEventListener('pointerdown', handler);
  },
);

// The die tumbles for ~800ms with its faces cycling, then settles.
const tumble = modifier(
  (el: HTMLElement, [face, version, faces]: [number, number, number]) => {
    let last = (el as any).__rv;
    (el as any).__rv = version;
    if (!version || last === version || reduced()) return;
    let svg = el.querySelector('svg');
    let n = Math.max(2, faces);
    let t = 0;
    let id = setInterval(() => {
      t++;
      svg?.setAttribute('data-show', String(Math.floor(Math.random() * n)));
      if (t > 9) {
        clearInterval(id);
        svg?.setAttribute('data-show', String(face));
      }
    }, 72);
    el.animate(
      [
        { transform: 'translate(0, 0) rotate(0deg) scale(1)' },
        {
          transform: 'translate(22%, -48%) rotate(160deg) scale(1.18)',
          offset: 0.3,
        },
        {
          transform: 'translate(-12%, 8%) rotate(300deg) scale(1.06)',
          offset: 0.62,
        },
        {
          transform: 'translate(3%, -7%) rotate(350deg) scale(1.02)',
          offset: 0.85,
        },
        { transform: 'translate(0, 0) rotate(360deg) scale(1)' },
      ],
      { duration: 820, easing: 'cubic-bezier(.2,.6,.3,1)' },
    );
    return () => clearInterval(id);
  },
);

interface TableSig {
  Element: HTMLDivElement;
  Args: {
    game: GameData;
    state: State;
    viewer: string | null;
    interactive?: boolean;
    legal?: LegalAction[];
    onAct?: (a: LegalAction) => void;
    anim?: AnimBatch;
    seatColours?: Record<string, string>;
    tableColour?: string;
    surface?: string;
    describeCopy?: (copyId: string) => string;
    staticView?: boolean;
  };
}

export class Table extends GlimmerComponent<TableSig> {
  @tracked narrow = false;
  @tracked selected: string | null = null;
  @tracked tip: { text: string; x: number; y: number } | null = null;
  surfaceEl: HTMLElement | null = null;

  watchSize = modifier((el: HTMLElement) => {
    let ro = new ResizeObserver(([e]) => {
      let n = e.contentRect.width < 560;
      if (n !== this.narrow) this.narrow = n;
    });
    ro.observe(el);
    return () => ro.disconnect();
  });
  registerSurface = modifier((el: HTMLElement) => {
    this.surfaceEl = el;
    return () => (this.surfaceEl = null);
  });

  get game() {
    return this.args.game;
  }
  get aspect() {
    return aspectOf(this.game, this.narrow);
  }
  get defs() {
    return defMap(this.game);
  }
  get surfaceStyle() {
    let c = this.args.tableColour ?? '#2f6b4f';
    return htmlSafe(`aspect-ratio:${this.aspect}; --table:${c}`);
  }
  get jumps(): Record<string, number> | undefined {
    for (let a of this.game.ruleset.actions ?? []) {
      for (let e of a.effect ?? []) if (e.jumps) return e.jumps;
    }
    return undefined;
  }
  get winner() {
    return this.args.state.status === 'finished'
      ? this.args.state.result?.winner
      : null;
  }

  get boards() {
    let a = this.aspect;
    return this.game.layout.zones
      .filter((z) => z.board && !z.hidden)
      .map((z) => {
        let r = rectOf(z, this.narrow);
        return {
          z,
          def: this.defs.get(z.board!),
          kind: (z.kind === 'track' ? 'track' : 'grid') as 'track' | 'grid',
          w: r.w,
          h: r.h,
          style: htmlSafe(
            `left:${r.x}%; top:${r.y * a}%; width:${r.w}%; height:${r.h * a}%`,
          ),
        };
      });
  }

  get zones() {
    let clickable = new Map<string, LegalAction>();
    for (let l of this.args.legal ?? [])
      if (l.clickZone && !clickable.has(l.clickZone))
        clickable.set(l.clickZone, l);
    return zoneBoxes(this.game, this.narrow).map((b) => {
      let badge =
        b.zone.badge && this.args.viewer
          ? evalFor(this.game, this.args.state, this.args.viewer, b.zone.badge)
          : '';
      let toZone = this.selected
        ? (this.args.legal ?? []).find(
            (l) =>
              l.from === this.selected &&
              l.to?.position === -1 &&
              l.to.zone === b.zone.id,
          )
        : undefined;
      let act = this.args.interactive
        ? (toZone ?? clickable.get(b.zone.id))
        : undefined;
      let drop = this.dropZones.includes(b.zone.id) || !!toZone;
      let ownerWins = this.winner && b.zone.owner === this.winner;
      return {
        id: b.zone.id,
        label: b.zone.label,
        image: b.zone.image ?? '',
        badge: badge === '' || badge === undefined ? '' : String(badge),
        act,
        style: htmlSafe(
          `left:${b.x}%; top:${b.y}%; width:${b.w}%; height:${b.h}%`,
        ),
        cls: `${b.zone.kind}${b.zone.board ? ' has-board' : ''}${act && !drop ? ' clickable' : ''}${drop ? ' drop' : ''}${ownerWins ? ' wins' : ''}`,
      };
    });
  }

  get hints(): Map<string, Hint> {
    let m = new Map<string, Hint>();
    let batch = this.args.anim;
    if (!batch || this.args.staticView) return m;
    let order = 0;
    for (let e of batch.events) {
      if (e.type !== 'move') continue;
      let h: Hint = { version: batch.version, delay: 0 };
      if (e.path?.length && e.to.zone) {
        h.path = e.path.map((sq) =>
          trackPoint(this.game, e.to.zone, this.narrow, sq),
        );
      }
      if (e.jump) {
        let prev = m.get(e.copyId);
        // a walk then a ladder: keep the walk, then add the jump as the last leg
        if (prev?.path) {
          prev.path = [
            ...prev.path,
            trackPoint(this.game, e.to.zone, this.narrow, e.to.position),
          ];
          prev.jump = true;
          continue;
        }
        h.jump = true;
      }
      if (e.capture) h.capture = true;
      h.delay = order * 70;
      order++;
      m.set(e.copyId, h);
    }
    return m;
  }

  get rollVersions() {
    let m = new Map<string, number>();
    for (let e of this.args.anim?.events ?? [])
      if (e.type === 'roll') m.set(e.copyId, this.args.anim!.version);
    return m;
  }

  get targets() {
    if (!this.selected || !this.args.interactive) return [];
    return (this.args.legal ?? [])
      .filter(
        (a) =>
          a.from === this.selected &&
          a.to &&
          (!a.args?.promo || a.args.promo === 'Q'),
      )
      .map((a) => {
        let c = squareCentre(
          this.game,
          a.to!.zone,
          this.narrow,
          a.to!.position,
        );
        let occupied = this.args.state.copies.some(
          (x) => x.zone === a.to!.zone && x.position === a.to!.position,
        );
        return {
          a,
          occupied,
          style: htmlSafe(
            `left:${c.x}%; top:${c.y}%; width:${c.w}%; height:${c.h}%`,
          ),
        };
      });
  }

  get movable() {
    let s = new Set<string>();
    if (this.args.interactive)
      for (let a of this.args.legal ?? []) if (a.from) s.add(a.from);
    return s;
  }

  get lastMove() {
    let lm = this.args.state.vars?.lastMove;
    if (!lm) return [];
    let z = this.game.layout.zones.find((x) => x.kind === 'grid');
    if (!z) return [];
    return [lm.from, lm.to].map((sq: string) => {
      let pos =
        (Number(sq.slice(1)) - 1) * (z.cols ?? 8) + (sq.charCodeAt(0) - 97);
      let c = squareCentre(this.game, z.id, this.narrow, pos);
      return htmlSafe(
        `left:${c.x}%; top:${c.y}%; width:${c.w}%; height:${c.h}%`,
      );
    });
  }

  get placed() {
    let hints = this.hints;
    let rolls = this.rollVersions;
    let movable = this.movable;
    return placeCopies(
      this.game,
      this.args.state,
      this.args.viewer,
      this.narrow,
    ).map((p: Placed) => {
      let colour = p.copy.owner
        ? this.args.seatColours?.[p.copy.owner]
        : undefined;
      let wins =
        this.winner &&
        (p.copy.owner === this.winner || p.zone.owner === this.winner);
      return {
        id: p.copy.copyId,
        p,
        def: p.def,
        kind: p.kind,
        colour,
        face: Number(p.copy.counters?.face ?? 0),
        faces: p.def?.faces?.length ?? 6,
        rollVersion: rolls.get(p.copy.copyId) ?? 0,
        x: p.x,
        y: p.y,
        rot: p.rot,
        hint: hints.get(p.copy.copyId) ?? null,
        style: htmlSafe(
          `left:${p.x}%; top:${p.y}%; width:${p.w}%; z-index:${p.z}; --rot:${p.rot}deg`,
        ),
        cls: `copy k-${p.kind}${movable.has(p.copy.copyId) ? ' movable' : ''}${this.selected === p.copy.copyId ? ' selected' : ''}${wins ? ' wins' : ''}`,
      };
    });
  }

  get meters() {
    let a = this.aspect;
    return (this.game.layout.meters ?? []).map((m) => {
      let v = m.var
        ? Number(this.args.state.vars?.[m.var] ?? 0)
        : Number(
            this.args.state.seats.find((s) => s.id === m.seat)?.resources?.[
              m.resource ?? ''
            ] ?? 0,
          );
      let narrowPos = this.narrow && m.narrow ? m.narrow : m;
      // a seat's chips become a rack you can drag from when a chip gesture is live
      let drags = m.resource
        ? (this.args.legal ?? []).filter(
            (l) => l.chipDrag?.resource === m.resource,
          )
        : [];
      let stacks = drags.length
        ? DENOMS.filter(([d]) =>
            drags.some((l) => l.chipDrag!.value === d),
          ).map(([value, colour]) => ({
            value,
            colour,
            count: Math.max(1, Math.min(8, Math.floor(v / value))),
            drag: drags.find((l) => l.chipDrag!.value === value),
          }))
        : m.look === 'chips'
          ? chipStacks(v).map((x) => ({
              ...x,
              drag: undefined as LegalAction | undefined,
            }))
          : [];
      return {
        label: m.label,
        big: m.look === 'number',
        value: v,
        rack: drags.length > 0,
        stacks,
        style: htmlSafe(`left:${narrowPos.x}%; top:${narrowPos.y * a}%`),
      };
    });
  }

  get cardBack(): Look | undefined {
    return this.game.cardLook;
  }

  // ─── pointer: click to select, drag to move ────────────────────────────
  drag: {
    id: string;
    el: HTMLElement;
    x0: number;
    y0: number;
    moved: boolean;
    pointer: number;
    chip?: LegalAction;
  } | null = null;
  @tracked dropZones: string[] = [];

  zoneAt(px: number, py: number) {
    let hit = zoneBoxes(this.game, this.narrow).filter(
      (b) => px >= b.x && px <= b.x + b.w && py >= b.y && py <= b.y + b.h,
    );
    return hit.map((b) => b.zone.id);
  }
  // drag a chip from the rack onto an area (a bet)
  chipDown = (a: LegalAction, ev: Event) => {
    if (!this.args.interactive) return;
    let e = ev as PointerEvent;
    let el = e.currentTarget as HTMLElement;
    el.setPointerCapture(e.pointerId);
    this.drag = {
      id: '',
      el,
      x0: e.clientX,
      y0: e.clientY,
      moved: false,
      pointer: e.pointerId,
      chip: a,
    };
    this.dropZones = [a.chipDrag!.to];
  };

  pointerDown = (item: { id: string; p: Placed }, ev: Event) => {
    let e = ev as PointerEvent;
    if (!this.args.interactive) return;
    // a click on an enemy piece that sits on a target square is a capture
    let target = this.targets.find(
      (t) =>
        t.a.to!.zone === item.p.copy.zone &&
        t.a.to!.position === item.p.copy.position,
    );
    if (target && item.id !== this.selected) {
      this.act(target.a);
      return;
    }
    if (!this.movable.has(item.id)) {
      this.selected = null;
      return;
    }
    let el = e.currentTarget as HTMLElement;
    el.setPointerCapture(e.pointerId);
    this.drag = {
      id: item.id,
      el,
      x0: e.clientX,
      y0: e.clientY,
      moved: false,
      pointer: e.pointerId,
    };
    this.selected = item.id;
    this.dropZones = (this.args.legal ?? [])
      .filter((a) => a.from === item.id && a.to?.position === -1)
      .map((a) => a.to!.zone);
  };
  pointerMove = (ev: Event) => {
    let e = ev as PointerEvent;
    let d = this.drag;
    if (!d) return;
    let dx = e.clientX - d.x0;
    let dy = e.clientY - d.y0;
    if (!d.moved && Math.hypot(dx, dy) < 5) return;
    d.moved = true;
    d.el.classList.add('dragging');
    d.el.style.translate = `${dx}px ${dy}px`;
  };
  pointerUp = (ev: Event) => {
    let e = ev as PointerEvent;
    let d = this.drag;
    if (!d) return;
    this.drag = null;
    d.el.classList.remove('dragging');
    let rect = this.surfaceEl?.getBoundingClientRect();
    let px = rect ? ((e.clientX - rect.left) / rect.width) * 100 : -1;
    let py = rect ? ((e.clientY - rect.top) / rect.height) * 100 : -1;
    if (d.chip) {
      this.dropZones = [];
      d.el.style.translate = '';
      if (!d.moved) return;
      if (this.zoneAt(px, py).includes(d.chip.chipDrag!.to)) this.act(d.chip);
      else
        d.el.animate(
          [
            { translate: `${e.clientX - d.x0}px ${e.clientY - d.y0}px` },
            { translate: '0 0' },
          ],
          { duration: 260, easing: 'cubic-bezier(.3,1.5,.5,1)' },
        );
      return;
    }
    if (!d.moved) return; // a click: selection stays, targets show
    this.dropZones = [];
    let legal = (this.args.legal ?? []).filter((a) => a.from === d.id && a.to);
    let hit: LegalAction | undefined;
    if (rect && legal.length) {
      let under = this.zoneAt(px, py);
      hit = legal.find(
        (a) => a.to!.position === -1 && under.includes(a.to!.zone),
      );
      if (!hit) {
        let grid = legal.find((a) => a.to!.position >= 0);
        if (grid) {
          let sq = squareAt(this.game, grid.to!.zone, this.narrow, px, py);
          let hits = legal.filter((a) => a.to!.position === sq);
          hit =
            hits.find((a) => !a.args?.promo || a.args.promo === 'Q') ?? hits[0];
        }
      }
    }
    if (hit) {
      // drop where it was released, then let the placement glide the last bit
      let r = d.el.getBoundingClientRect();
      if (rect)
        (d.el as any).__at = {
          x: ((r.left + r.width / 2 - rect.left) / rect.width) * 100,
          y: ((r.top + r.height / 2 - rect.top) / rect.height) * 100,
          rot: 0,
        };
      d.el.style.translate = '';
      this.act(hit);
    } else {
      // illegal drop: spring back, no alarm
      let from = d.el.style.translate;
      d.el.style.translate = '';
      d.el.animate([{ translate: from }, { translate: '0 0' }], {
        duration: 260,
        easing: 'cubic-bezier(.3,1.5,.5,1)',
      });
    }
  };
  act(a: LegalAction) {
    this.selected = null;
    this.dropZones = [];
    this.args.onAct?.(a);
  }
  clickTarget = (a: LegalAction) => this.act(a);
  clickZone = (a: LegalAction) => this.act(a);
  showTip = (item: { id: string; p: Placed }, ev: Event) => {
    let e = ev as PointerEvent;
    if (!this.args.describeCopy || !this.surfaceEl || this.drag) return;
    let rect = this.surfaceEl.getBoundingClientRect();
    let text =
      item.p.def || item.p.kind !== 'card'
        ? this.args.describeCopy(item.id)
        : 'A face-down card. Its identity stays hidden until it turns over.';
    this.tip = {
      text,
      x: ((e.clientX - rect.left) / rect.width) * 100,
      y: ((e.clientY - rect.top) / rect.height) * 100,
    };
  };
  hideTip = () => (this.tip = null);
  get tipStyle() {
    if (!this.tip) return htmlSafe('');
    return htmlSafe(
      `left:${Math.min(70, Math.max(2, this.tip.x))}%; top:${this.tip.y}%`,
    );
  }

  <template>
    <div
      class='table-wrap {{if this.narrow "narrow"}} {{if @staticView "static"}}'
      {{this.watchSize}}
      ...attributes
    >
      <div
        class='surface s-{{if @surface @surface "felt"}}
          {{if this.winner "finished"}}'
        style={{this.surfaceStyle}}
        {{this.registerSurface}}
        {{on 'pointermove' this.pointerMove}}
        {{on 'pointerup' this.pointerUp}}
      >
        {{#each this.boards as |b|}}
          <div class='board-slot' style={{b.style}}>
            <Board
              @def={{b.def}}
              @kind={{b.kind}}
              @w={{b.w}}
              @h={{b.h}}
              @cols={{b.z.cols}}
              @rows={{b.z.rows}}
              @length={{b.z.length}}
              @path={{b.z.path}}
              @jumps={{this.jumps}}
            />
          </div>
        {{/each}}

        {{#each this.lastMove as |s|}}
          <div class='last-move' style={{s}}></div>
        {{/each}}

        {{#each this.zones as |z|}}
          <div class='zone {{z.cls}}' style={{z.style}}>
            {{#if z.image}}<img
                class='zone-art'
                src={{z.image}}
                alt=''
              />{{/if}}
            {{#if z.label}}
              <span class='zone-label'>{{z.label}}{{#if z.badge}}
                  <b>{{z.badge}}</b>{{/if}}</span>
            {{/if}}
            {{#if z.act}}
              <button
                type='button'
                class='zone-hit'
                aria-label={{z.act.label}}
                {{on 'click' (fn this.clickZone z.act)}}
              ></button>
            {{/if}}
          </div>
        {{/each}}

        {{#each this.meters as |m|}}
          <div class='meter {{if m.big "big"}}' style={{m.style}}>
            <div class='chip-stacks'>
              {{#each m.stacks as |s|}}
                <div
                  class='chip-stack {{if s.drag "draggable"}}'
                  title={{if s.drag (concat 'Drag a ' s.value ' chip')}}
                  {{grabIf s.drag (fn this.chipDown s.drag)}}
                >
                  {{#each (rangeOf s.count) as |i|}}
                    <div class='chip-slot' style={{chipOffset i}}><Chip
                        @colour={{s.colour}}
                        @depth={{1}}
                      /></div>
                  {{/each}}
                </div>
              {{/each}}
            </div>
            <span class='meter-label'>{{m.label}} <b>{{m.value}}</b></span>
            {{#if m.rack}}<span class='rack-hint'>drag a chip to bet</span>{{/if}}
          </div>
        {{/each}}

        {{#each this.placed key='id' as |c|}}
          <div
            class={{c.cls}}
            style={{c.style}}
            data-copy={{c.id}}
            {{placeCopy c.x c.y c.rot c.hint}}
            {{grabOn (fn this.pointerDown c)}}
            {{on 'pointerenter' (fn this.showTip c)}}
            {{on 'pointerleave' this.hideTip}}
          >
            {{#if (eq c.kind 'card')}}
              <PlayingCard
                @def={{c.def}}
                @faceUp={{c.p.faceUp}}
                @back={{this.cardBack}}
                @look={{c.def.look}}
              />
            {{else if (eq c.kind 'die')}}
              <div class='die-wrap' {{tumble c.face c.rollVersion c.faces}}><Die
                  @def={{c.def}}
                  @face={{c.face}}
                /></div>
            {{else if (eq c.kind 'piece')}}
              <Piece @def={{c.def}} />
            {{else if (eq c.kind 'token')}}
              <Token @def={{c.def}} @colour={{c.colour}} />
            {{else if (eq c.kind 'chip')}}
              <Chip
                @colour={{c.def.look.fill}}
                @value={{c.def.value}}
                @depth={{c.def.look.depth}}
              />
            {{else if (eq c.kind 'coin')}}
              <Chip
                @coin={{true}}
                @colour={{c.def.look.fill}}
                @face={{if (eq c.face 1) 'T' 'H'}}
              />
            {{else if (eq c.kind 'tile')}}
              <Tile @def={{c.def}} @face={{c.face}} />
            {{/if}}
          </div>
        {{/each}}

        {{#each this.targets as |t|}}
          <button
            type='button'
            class='target {{if t.occupied "capture"}}'
            style={{t.style}}
            aria-label={{t.a.label}}
            {{on 'click' (fn this.clickTarget t.a)}}
          ><span></span></button>
        {{/each}}

        {{#if this.tip}}
          <div
            class='tip'
            style={{this.tipStyle}}
            role='tooltip'
          >{{this.tip.text}}</div>
        {{/if}}
      </div>
    </div>
    <style scoped>
      .table-wrap {
        width: 100%;
        container-type: inline-size;
        font-family:
          ui-rounded, 'SF Pro Rounded', 'Nunito', system-ui, sans-serif;
      }
      .surface {
        position: relative;
        width: 100%;
        border-radius: 1.6cqw;
        overflow: hidden;
        touch-action: none;
        user-select: none;
        background-color: var(--table);
        box-shadow:
          inset 0 0 0 0.5cqw rgba(0, 0, 0, 0.18),
          inset 0 1.2cqw 3cqw rgba(0, 0, 0, 0.25),
          0 0.6cqw 2cqw rgba(30, 20, 10, 0.22);
      }
      .s-felt {
        background-image:
          radial-gradient(
            ellipse at 32% 18%,
            rgba(255, 255, 255, 0.13),
            transparent 60%
          ),
          radial-gradient(
            ellipse at 70% 100%,
            rgba(0, 0, 0, 0.28),
            transparent 65%
          ),
          url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2'/%3E%3CfeColorMatrix values='0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 .14 0'/%3E%3C/filter%3E%3Crect width='120' height='120' filter='url(%23n)'/%3E%3C/svg%3E");
      }
      .s-wood {
        background-image:
          radial-gradient(
            ellipse at 30% 15%,
            rgba(255, 230, 190, 0.16),
            transparent 60%
          ),
          repeating-linear-gradient(
            97deg,
            rgba(0, 0, 0, 0.05) 0 0.4cqw,
            transparent 0.4cqw 1.3cqw,
            rgba(255, 255, 255, 0.03) 1.3cqw 1.6cqw,
            transparent 1.6cqw 3cqw
          ),
          repeating-linear-gradient(
            93deg,
            rgba(60, 30, 10, 0.12) 0 0.15cqw,
            transparent 0.15cqw 5cqw
          );
      }
      .s-paper {
        background-image:
          radial-gradient(
            ellipse at 30% 15%,
            rgba(255, 255, 255, 0.5),
            transparent 60%
          ),
          url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.8' numOctaves='2'/%3E%3CfeColorMatrix values='0 0 0 0 .4 0 0 0 0 .3 0 0 0 0 .2 0 0 0 .08 0'/%3E%3C/filter%3E%3Crect width='120' height='120' filter='url(%23n)'/%3E%3C/svg%3E");
      }
      .board-slot {
        position: absolute;
      }
      .zone {
        position: absolute;
        border-radius: 1cqw;
        pointer-events: none;
      }
      .zone.stack,
      .zone.spread {
        border: 0.25cqw dashed rgba(255, 255, 255, 0.16);
      }
      .s-paper .zone.stack,
      .s-paper .zone.spread,
      .s-paper .zone.pot {
        border-color: rgba(90, 70, 40, 0.18);
      }
      .zone.pot:not(.has-board) {
        border: 0.25cqw dashed rgba(255, 255, 255, 0.1);
      }
      .zone.has-board {
        border: 0;
      }
      /* a zone's own art: a portrait or a place, under whatever lies in it */
      .zone-art {
        position: absolute;
        inset: 4%;
        width: 92%;
        height: 92%;
        object-fit: contain;
        filter: drop-shadow(0 0.6cqw 0.8cqw rgba(0, 0, 0, 0.45));
      }
      .zone-label {
        position: absolute;
        left: 0.8cqw;
        top: -2.8cqw;
        font-size: max(10px, 1.55cqw);
        font-weight: 650;
        letter-spacing: 0.03em;
        color: rgba(255, 255, 255, 0.78);
        white-space: nowrap;
        text-shadow: 0 1px 1px rgba(0, 0, 0, 0.35);
      }
      .s-paper .zone-label {
        color: #6b5638;
        text-shadow: none;
      }
      .zone-label b {
        display: inline-block;
        min-width: 2.2em;
        margin-left: 0.35em;
        padding: 0.05em 0.45em;
        border-radius: 99px;
        background: rgba(0, 0, 0, 0.32);
        color: #fff6dc;
        text-align: center;
        font-variant-numeric: tabular-nums;
      }
      .zone.clickable {
        box-shadow:
          0 0 0 0.4cqw rgba(255, 210, 120, 0.55),
          0 0 2.4cqw rgba(255, 210, 120, 0.4);
        animation: breathe 1.8s ease-in-out infinite;
      }
      .zone.drop {
        box-shadow:
          0 0 0 0.5cqw rgba(255, 220, 130, 0.95),
          0 0 3cqw rgba(255, 220, 130, 0.55);
        background: rgba(255, 220, 130, 0.08);
      }
      .meter {
        z-index: 60;
      }
      .chip-stack.draggable {
        cursor: grab;
        pointer-events: auto;
        touch-action: none;
      }
      .chip-stack.draggable:hover {
        translate: 0 -0.4cqw;
      }
      .rack-hint {
        font-size: max(9px, 1.15cqw);
        color: rgba(255, 246, 220, 0.6);
      }
      .zone.wins {
        box-shadow:
          0 0 0 0.4cqw rgba(255, 214, 120, 0.9),
          0 0 3cqw rgba(255, 214, 120, 0.7);
      }
      @keyframes breathe {
        50% {
          box-shadow:
            0 0 0 0.4cqw rgba(255, 210, 120, 0.3),
            0 0 1.2cqw rgba(255, 210, 120, 0.2);
        }
      }
      .zone-hit {
        position: absolute;
        inset: 0;
        pointer-events: auto;
        background: transparent;
        border: 0;
        cursor: pointer;
        z-index: 90;
      }
      .zone-hit:focus-visible {
        outline: 0.4cqw solid #ffd27a;
        border-radius: 1cqw;
      }
      .copy {
        position: absolute;
        transform: translate(-50%, -50%) rotate(var(--rot, 0deg));
        transform-origin: center;
      }
      .copy.movable {
        cursor: grab;
      }
      .copy.movable:hover {
        filter: brightness(1.06) drop-shadow(0 0.4cqw 0.5cqw rgba(0, 0, 0, 0.3));
      }
      .copy.selected {
        filter: drop-shadow(0 0 0.6cqw rgba(255, 214, 120, 0.95));
      }
      .copy.dragging {
        cursor: grabbing;
        scale: 1.12;
        z-index: 200 !important;
        filter: drop-shadow(0.6cqw 1.4cqw 1.2cqw rgba(0, 0, 0, 0.4));
      }
      .copy.wins {
        filter: drop-shadow(0 0 0.8cqw rgba(255, 214, 120, 0.95));
      }
      .k-die {
        cursor: default;
      }
      .die-wrap {
        transform-origin: center;
      }
      .last-move {
        position: absolute;
        transform: translate(-50%, -50%);
        background: rgba(255, 214, 110, 0.32);
        pointer-events: none;
      }
      .target {
        position: absolute;
        transform: translate(-50%, -50%);
        background: transparent;
        border: 0;
        padding: 0;
        cursor: pointer;
        z-index: 150;
        display: grid;
        place-items: center;
      }
      .target span {
        width: 30%;
        aspect-ratio: 1;
        border-radius: 50%;
        background: rgba(255, 220, 130, 0.85);
        box-shadow: 0 0 0.8cqw rgba(255, 220, 130, 0.9);
      }
      .target.capture {
        z-index: 25;
      }
      .target.capture span {
        width: 92%;
        background: transparent;
        border: 0.6cqw solid rgba(255, 220, 130, 0.9);
      }
      .meter {
        position: absolute;
        transform: translate(-50%, -50%);
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.4cqw;
        pointer-events: none;
      }
      .chip-stacks {
        display: flex;
        gap: 0.6cqw;
        align-items: flex-end;
        min-height: 2cqw;
      }
      .chip-stack {
        position: relative;
        width: 5.6cqw;
        height: 8.5cqw;
      }
      .chip-slot {
        position: absolute;
        left: 0;
        width: 100%;
      }
      .meter-label {
        font-size: max(10px, 1.5cqw);
        color: rgba(255, 255, 255, 0.8);
        font-weight: 600;
        white-space: nowrap;
      }
      .meter-label b {
        color: #fff6dc;
        font-variant-numeric: tabular-nums;
      }
      .meter.big .meter-label {
        display: flex;
        flex-direction: column;
        align-items: center;
        font-size: max(11px, 1.8cqw);
      }
      .meter.big .meter-label b {
        font:
          700 max(22px, 5.4cqw) / 1 'Iowan Old Style',
          Georgia,
          serif;
      }
      .tip {
        position: absolute;
        transform: translate(0, calc(-100% - 14px));
        max-width: 46%;
        background: rgba(28, 22, 16, 0.92);
        color: #f6ecd8;
        font-size: max(11px, 1.35cqw);
        line-height: 1.4;
        padding: 0.5em 0.75em;
        border-radius: 0.6em;
        pointer-events: none;
        z-index: 300;
        box-shadow: 0 4px 14px rgba(0, 0, 0, 0.3);
      }
      .static .zone-label,
      .static .meter-label,
      .static .zone.clickable {
        animation: none;
      }
      @container (width < 300px) {
        .zone-label,
        .meter-label {
          display: none;
        }
      }
    </style>
  </template>
}

function rangeOf(n: number) {
  return Array.from({ length: n }, (_, i) => i);
}
function chipOffset(i: number) {
  return htmlSafe(`bottom:${i * 9}%`);
}
