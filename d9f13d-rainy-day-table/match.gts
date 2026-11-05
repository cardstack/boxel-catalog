// A Match is one game being played: the hero. It holds the exact state of
// every copy on the table (snapshot), every action taken (log) and the seed,
// so it saves, resumes and replays exactly. The isolated view is the table.

import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  realmURL,
} from '@cardstack/base/card-api';

import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import DatetimeField from '@cardstack/base/datetime';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import { registerDestructor } from '@ember/destroyable';
import type Owner from '@ember/owner';
import { eq, or } from '@cardstack/boxel-ui/helpers';
import DicesIcon from '@cardstack/boxel-icons/dices';
import {
  ActionLogEntryField,
  CopyStateField,
  GameJsonField,
  TurnField,
  copyToPlain,
  logToPlain,
  seatToPlain,
  writeCopies,
  writeLog,
} from './fields';
import { Game, startMatch } from './game';
import { Opponent } from './opponent';
import type { GameData, LegalAction, State } from './engine';
import {
  apply,
  copyTrails,
  defMap,
  fingerprint,
  legalActions,
  makeRng,
  newMatch,
  phaseLabel,
  replay,
  squareName,
  undo,
} from './engine';
import { chooseAction } from './bots';
import type { BotSpec } from './bots';
import { Table } from './table';
import type { AnimBatch } from './table';
import { Token } from './parts';
import './chess-rules';

const here: string = import.meta.url;

export class SeatField extends FieldDef {
  static displayName = 'Seat';
  @field seatId = contains(StringField);
  @field label = contains(StringField);
  @field occupant = contains(StringField); // human | bot | empty
  @field opponent = linksTo(() => Opponent);
  @field colour = contains(StringField);
  @field image = contains(StringField); // the seat's portrait
  @field score = contains(NumberField);
  @field resources = contains(GameJsonField);
  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span>{{@model.label}}
        ·
        {{@model.occupant}}{{#if @model.opponent}}
          ({{@model.opponent.name}}){{/if}}</span>
    </template>
  };
}

class MatchIsolated extends Component<typeof Match> {
  @tracked state: State | null = null;
  @tracked anim: AnimBatch = { version: 0, events: [] };
  @tracked thinking: string | null = null;
  @tracked showLog = false;
  @tracked showShelf = false;
  @tracked error = '';
  @tracked rematching = false;
  timer: ReturnType<typeof setTimeout> | null = null;
  trailCache: {
    len: number;
    trails: ReturnType<typeof copyTrails>;
    startCounts: Map<string, number>;
  } | null = null;
  rng = makeRng(Date.now() & 0xffff);

  constructor(owner: Owner, args: any) {
    super(owner, args);
    registerDestructor(this, () => this.timer && clearTimeout(this.timer));
  }

  get model() {
    return this.args.model as unknown as Match;
  }
  get gameCard() {
    return this.model.game as Game | undefined;
  }
  _game: { card: Game; data: GameData } | null = null;
  get gameData(): GameData {
    return this.game!;
  }
  get game(): GameData | null {
    let card = this.gameCard;
    if (!card) return null;
    if (this._game?.card !== card) this._game = { card, data: card.toData() };
    return this._game.data;
  }

  // Load or set out the table once the game has arrived.
  boot = modifier((_el: HTMLElement, [game]: [GameData | null]) => {
    if (this.state || !game || this.booting) return;
    this.booting = true;
    // after render settles: never mutate tracked state mid-render
    Promise.resolve().then(() => {
      let s = this.model.readState();
      if (!s) {
        let seats = (this.model.seats ?? []).map(seatToPlain);
        if (!seats.length) {
          this.error = 'This match has no seats yet.';
          return;
        }
        try {
          s = newMatch(game, seats, this.model.seed ?? 1).state;
          // the indexer's prerender only looks; a real visit sets the table out for good
          if (!inPrerender()) this.model.writeState(s);
        } catch (e: any) {
          this.error = `The table couldn't be set out: ${e.message}`;
          return;
        }
      }
      this.state = s;
      if (!inPrerender()) this.scheduleBot(600);
    });
  });
  booting = false;

  get viewer() {
    return this.model.humanSeat;
  }
  get myTurn() {
    return (
      this.state?.status === 'playing' && this.state.turn.seat === this.viewer
    );
  }
  get legal(): LegalAction[] {
    if (!this.state || !this.game || !this.myTurn || this.thinking) return [];
    return legalActions(this.game, this.state, this.viewer ?? undefined);
  }
  get buttons() {
    let seenLabels = new Set<string>();
    return this.legal
      .filter((a) => !a.from)
      .filter((a) =>
        seenLabels.has(a.label) ? false : (seenLabels.add(a.label), true),
      )
      .filter((a) => a.button !== false)
      .map((a, i) => ({
        a,
        n: i + 1,
        quiet: a.bot === false || a.id === 'resign' || a.id === 'leave',
        // the table gesture is the main way; the button is the fallback
        gesture: !!(a.clickZone || a.chipDrag),
        small: !!a.chipDrag,
      }));
  }
  // "Click the shoe to deal · drag a chip onto the bet"
  get hints() {
    let g = this.game;
    if (!g) return '';
    let name = (id: string) => {
      let z = g!.layout.zones.find((x) => x.id === id);
      return (
        z?.name ?? (z?.label ? `the ${z.label.toLowerCase()}` : id)
      ).replace(/^your/, 'your');
    };
    let out = new Set<string>();
    for (let a of this.legal) {
      if (a.chipDrag) out.add(`Bet: drag a chip onto ${name(a.chipDrag.to)}`);
      else if (a.clickZone) out.add(`${a.label}: click ${name(a.clickZone)}`);
      else if (a.from && a.to?.position === -1)
        out.add(
          `${a.label}: drag from ${name(this.state!.copies.find((c) => c.copyId === a.from)?.zone ?? '')} to ${name(a.to.zone)}`,
        );
    }
    let s = [...out].join(' · ');
    return s ? s[0].toUpperCase() + s.slice(1) : '';
  }
  get seatStrip() {
    let s = this.state;
    return (this.model.seats ?? []).map((f) => {
      let id = f.seatId!;
      let plain = s?.seats.find((x) => x.id === id);
      let chips = plain?.resources?.chips;
      return {
        id,
        label: f.label,
        who:
          f.occupant === 'human'
            ? 'you'
            : f.opponent?.name && f.opponent.name !== f.label
              ? f.opponent.name
              : f.opponent
                ? ''
                : 'bot',
        style: f.opponent?.style,
        colour: f.colour ?? f.opponent?.colour ?? '#b9a685',
        // a match started before the game had portraits still shows them
        image:
          f.image ||
          this.gameCard?.seatTemplates?.().find((t: any) => t.id === id)
            ?.image ||
          '',
        chips,
        turn: s?.status === 'playing' && s.turn.seat === id,
        thinking: this.thinking === id,
        won: s?.status === 'finished' && s.result?.winner === id,
      };
    });
  }
  get statusLine() {
    let s = this.state;
    if (!s || !this.game) return '';
    if (s.status === 'finished') return s.result?.text ?? 'Finished';
    if (this.thinking) {
      let seat = s.seats.find((x) => x.id === this.thinking);
      return `${seat?.label ?? 'Opponent'} is thinking…`;
    }
    return phaseLabel(this.game, s) || (this.myTurn ? 'Your turn' : '');
  }
  get lastLine() {
    let live = (this.state?.log ?? []).filter((e) => !e.undone && e.index > 0);
    let e = live[live.length - 1];
    if (!e) return '';
    let who = this.state!.seats.find((x) => x.id === e.seat)?.label ?? e.seat;
    return `${who}: ${e.resultSummary || e.action}`;
  }
  get canUndo() {
    return (
      !!this.state &&
      this.state.log.some((e) => !e.undone && e.seat === this.viewer)
    );
  }
  get logRows() {
    return [...(this.state?.log ?? [])].reverse().map((e) => ({
      ...e,
      who:
        e.index === 0
          ? 'Table'
          : (this.state!.seats.find((x) => x.id === e.seat)?.label ?? e.seat),
    }));
  }
  get replayCheck() {
    if (!this.showLog || !this.state || !this.game) return null;
    try {
      let r = replay(this.game, this.state.log, this.state.seed);
      return {
        ok: fingerprint(r) === fingerprint(this.state),
        n: this.state.log.filter((e) => !e.undone).length - 1,
      };
    } catch (e: any) {
      return { ok: false, n: 0, error: e.message };
    }
  }
  get tableStyle() {
    return htmlSafe(`--table:${this.gameCard?.tableColour ?? '#2f6b4f'}`);
  }

  // ─── acting ────────────────────────────────────────────────────────────
  commit(next: State, events: any[]) {
    this.state = next;
    this.anim = { version: this.anim.version + 1, events };
    this.model.writeState(next);
  }

  act = (a: LegalAction) => {
    if (!this.state || !this.game) return;
    try {
      let r = apply(this.game, this.state, a, { at: new Date().toISOString() });
      this.commit(r.state, r.events);
      this.scheduleBot(this.animTime(r.events));
    } catch (e: any) {
      this.error = e.message;
    }
  };

  animTime(events: any[]) {
    let moves = events.filter((e) => e.type === 'move');
    let walk = Math.max(0, ...moves.map((e) => (e.path?.length ?? 0) * 150));
    let roll = events.some((e) => e.type === 'roll') ? 820 : 0;
    return Math.max(walk + roll, moves.length * 70 + 320, roll);
  }

  botFor(seat: string): BotSpec {
    let f = (this.model.seats ?? []).find((s) => s.seatId === seat);
    let o = f?.opponent as any;
    return o?.botSpec ? o.botSpec() : { kind: 'random', thinkingDelay: 450 };
  }

  scheduleBot(after = 0) {
    if (this.timer) clearTimeout(this.timer);
    let s = this.state;
    if (!s || !this.game || s.status !== 'playing') return;
    let seat = s.turn.seat;
    let f = s.seats.find((x) => x.id === seat);
    if (!f || f.occupant !== 'bot') {
      this.thinking = null;
      return;
    }
    let bot = this.botFor(seat);
    let think = Math.max(300, Math.min(900, bot.thinkingDelay ?? 500));
    this.timer = setTimeout(() => {
      this.thinking = seat;
      this.timer = setTimeout(() => {
        this.timer = null;
        let cur = this.state;
        if (
          !cur ||
          !this.game ||
          cur.turn.seat !== seat ||
          cur.status !== 'playing'
        ) {
          this.thinking = null;
          return;
        }
        let a = chooseAction(this.game, cur, seat, bot, this.rng);
        this.thinking = null;
        if (!a) {
          this.error = `${f!.label} has no legal move in phase "${cur.turn.phase}".`;
          return;
        }
        this.act(a);
      }, think);
    }, after);
  }

  undoLast = () => {
    if (!this.state || !this.game || !this.viewer) return;
    if (this.timer) clearTimeout(this.timer);
    this.thinking = null;
    let u = undo(this.game, this.state, this.viewer);
    if (!u) return;
    this.commit(u, []);
    this.scheduleBot(400);
  };

  keys = modifier((el: HTMLElement) => {
    let h = (e: KeyboardEvent) => {
      if (
        (e.target as HTMLElement)?.closest('input, textarea, [contenteditable]')
      )
        return;
      if (e.key === 'z' || e.key === 'Z') {
        e.preventDefault();
        this.undoLast();
        return;
      }
      let btns = this.buttons;
      let byKey = btns.find((b) => b.a.key === e.code);
      if (byKey) {
        e.preventDefault();
        this.act(byKey.a);
        return;
      }
      if (/^[1-9]$/.test(e.key)) {
        let b = btns[Number(e.key) - 1];
        if (b) {
          e.preventDefault();
          this.act(b.a);
        }
      }
    };
    // focus falls to <body> when the button just pressed disappears; keep
    // listening then, but leave keys alone when another card has focus
    let doc = (e: KeyboardEvent) => {
      let a = document.activeElement;
      if (a === el || el.contains(a) || !a || a === document.body) h(e);
    };
    document.addEventListener('keydown', doc);
    return () => document.removeEventListener('keydown', doc);
  });

  // ─── copy history (one replay, cached per log length) ──────────────────
  describeCopy = (copyId: string) => {
    let s = this.state;
    let g = this.game;
    if (!s || !g) return copyId;
    if (!this.trailCache || this.trailCache.len !== s.log.length) {
      try {
        let trails = copyTrails(g, s);
        let startCounts = new Map<string, number>();
        for (let t of trails.values())
          startCounts.set(t[0].zone, (startCounts.get(t[0].zone) ?? 0) + 1);
        this.trailCache = { len: s.log.length, trails, startCounts };
      } catch {
        return copyId;
      }
    }
    let copy = s.copies.find((c) => c.copyId === copyId);
    let def = defMap(g).get(copy?.counters?.becomes ?? copy?.defId ?? '');
    let zones = new Map(g.layout.zones.map((z) => [z.id, z]));
    let trail = this.trailCache.trails.get(copyId) ?? [];
    let steps = trail.map((t) => {
      let z = zones.get(t.zone);
      let where =
        z?.kind === 'grid'
          ? squareName(z, t.position)
          : z?.kind === 'track'
            ? `square ${t.position}`
            : ((z as any)?.name ?? z?.label ?? t.zone).toLowerCase();
      let n = this.trailCache!.startCounts.get(t.zone) ?? 0;
      let pos =
        t.index === 0 && z?.kind === 'stack' && n
          ? `, ${ordinal(n - t.position)} from the top`
          : '';
      return t.index === 0 ? `${where}${pos}` : `${where} (move ${t.index})`;
    });
    let promoted = copy?.counters?.becomes
      ? `, promoted to ${def?.name?.toLowerCase()}`
      : '';
    return `${def?.name ?? 'Part'}${promoted} · ${copyId}: ${steps.join(' → ')}`;
  };

  // ─── shelf, rematch ─────────────────────────────────────────────────────
  get realms() {
    let r = this.model[realmURL];
    return r ? [r.href] : [];
  }
  gamesQuery = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: { module: new URL('./game', here).href, name: 'Game' },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  matchesQuery = this.args.context?.getCards(
    this,
    () =>
      ({
        filter: {
          type: { module: new URL('./match', here).href, name: 'Match' },
        },
      }) as any,
    () => this.realms,
    { isLive: true },
  );
  get shelfGames() {
    return (this.gamesQuery?.instances ?? []) as CardDefType[];
  }
  get shelfMatches() {
    return ((this.matchesQuery?.instances ?? []) as any[])
      .filter((m) => m.id !== this.model.id && m.status !== 'finished')
      .slice(0, 6) as CardDefType[];
  }
  toggleShelf = () => (this.showShelf = !this.showShelf);
  toggleLog = () => (this.showLog = !this.showLog);
  open = (card: CardDefType) => this.args.viewCard?.(card, 'isolated');
  openGame = () =>
    this.gameCard && this.args.viewCard?.(this.gameCard, 'isolated');

  rematch = async () => {
    if (!this.gameCard || this.rematching) return;
    this.rematching = true;
    try {
      let templates = (this.model.seats ?? []).map((f) => {
        let first = (this.model.log?.[0]?.args as any)?.seats?.find(
          (x: any) => x.id === f.seatId,
        );
        return {
          id: f.seatId!,
          label: f.label ?? f.seatId!,
          occupant: (f.occupant ?? 'human') as any,
          colour: f.colour ?? undefined,
          resources: first?.resources ?? f.resources ?? {},
          opponent: f.opponent?.id,
        };
      });
      await startMatch(
        this.gameCard,
        {
          createCard: this.args.createCard as any,
          viewCard: this.args.viewCard as any,
          context: this.args.context,
        },
        templates,
      );
    } catch (e: any) {
      this.error = `Couldn't set up a rematch: ${e.message}`;
    } finally {
      this.rematching = false;
    }
  };

  <template>
    <div class='match' style={{this.tableStyle}} tabindex='0' {{this.keys}}>
      <header class='bar'>
        <button
          type='button'
          class='chrome'
          aria-expanded={{if this.showShelf 'true' 'false'}}
          {{on 'click' this.toggleShelf}}
        >☰ Shelf</button>
        <div class='title'>
          <h1><button
              type='button'
              class='link'
              {{on 'click' this.openGame}}
            >{{this.gameCard.title}}</button></h1>
          <p>{{this.statusLine}}</p>
        </div>
        <button
          type='button'
          class='chrome'
          aria-expanded={{if this.showLog 'true' 'false'}}
          {{on 'click' this.toggleLog}}
        >⟲ Log</button>
      </header>

      <ul class='seats'>
        {{#each this.seatStrip as |s|}}
          <li class='seat {{if s.turn "turn"}} {{if s.won "won"}}'>
            {{#if s.image}}
              <img class='portrait' src={{s.image}} alt='' />
            {{else}}
              <span class='meeple'><Token @colour={{s.colour}} /></span>
            {{/if}}
            <span class='who'><b>{{s.label}}</b>
              <small>{{s.who}}{{#if s.style}}{{if
                    s.who
                    ' · '
                  }}{{s.style}}{{/if}}</small></span>
            {{#if s.chips}}<span class='chips'>{{s.chips}}</span>{{/if}}
            {{#if s.thinking}}<span class='dots' aria-label='thinking'><i></i><i
                ></i><i></i></span>{{/if}}
          </li>
        {{/each}}
      </ul>

      <div class='stage' {{this.boot this.game}}>
        {{#if this.error}}<p class='err' role='alert'>{{this.error}}</p>{{/if}}
        {{#if this.state}}
          <Table
            @game={{this.gameData}}
            @state={{this.state}}
            @viewer={{this.viewer}}
            @interactive={{this.myTurn}}
            @legal={{this.legal}}
            @onAct={{this.act}}
            @anim={{this.anim}}
            @seatColours={{this.model.seatColours}}
            @tableColour={{this.gameCard.tableColour}}
            @surface={{this.gameCard.surface}}
            @describeCopy={{this.describeCopy}}
          />
          {{#if (eq this.state.status 'finished')}}
            <div class='result' role='status'>
              <p class='rk'>{{if
                  (eq this.state.result.winner this.viewer)
                  'You win'
                  (if this.state.result.winner 'Good game' 'A draw')
                }}</p>
              <p class='rt'>{{this.state.result.text}}</p>
              <div class='rb'>
                <button
                  type='button'
                  class='primary'
                  {{on 'click' this.rematch}}
                  disabled={{this.rematching}}
                >{{if this.rematching 'Setting up…' 'Rematch'}}</button>
                <button
                  type='button'
                  class='ghost'
                  {{on 'click' this.openGame}}
                >Back to the box</button>
              </div>
            </div>
          {{/if}}
        {{else if this.error}}{{else}}
          <p class='loading'>Setting out the pieces…</p>
        {{/if}}
      </div>

      <footer class='actions'>
        <div class='last'>
          <p>{{this.lastLine}}</p>
          {{#if this.hints}}<p class='hint-line'>{{this.hints}}</p>{{/if}}
        </div>
        <div class='btns'>
          {{#each this.buttons as |b|}}
            <button
              type='button'
              class='{{if (or b.quiet b.gesture) "ghost" "primary"}}
                {{if b.small "small"}}'
              {{on 'click' (fn this.act b.a)}}
            >{{b.a.label}}</button>
          {{/each}}
          <button
            type='button'
            class='ghost undo'
            disabled={{if this.canUndo false true}}
            {{on 'click' this.undoLast}}
            title='Undo (Z)'
          >↶ Undo</button>
        </div>
      </footer>

      {{#if this.showShelf}}
        <aside class='drawer left' aria-label='Shelf'>
          <button
            type='button'
            class='close'
            aria-label='Close the shelf'
            {{on 'click' this.toggleShelf}}
          >×</button>
          <h2>The shelf</h2>
          <div class='boxes'>
            {{#each this.shelfGames as |g|}}
              <button
                type='button'
                class='box-btn'
                {{on 'click' (fn this.open g)}}
              >
                {{#let (getComponent g) as |C|}}<C @format='fitted' />{{/let}}
              </button>
            {{/each}}
          </div>
          {{#if this.shelfMatches.length}}
            <h2>Unfinished matches</h2>
            <div class='boxes'>
              {{#each this.shelfMatches as |m|}}
                <button
                  type='button'
                  class='box-btn match-btn'
                  {{on 'click' (fn this.open m)}}
                >
                  {{#let (getComponent m) as |C|}}<C @format='fitted' />{{/let}}
                </button>
              {{/each}}
            </div>
          {{/if}}
          <p class='hint'>Want a new game? Open the AI assistant with the
            <b>Rainy Day Table: game authoring</b>
            skill and describe it in a sentence or two.</p>
        </aside>
      {{/if}}

      {{#if this.showLog}}
        <aside class='drawer right' aria-label='Log'>
          <button
            type='button'
            class='close'
            aria-label='Close the log'
            {{on 'click' this.toggleLog}}
          >×</button>
          <h2>Log</h2>
          {{#if this.replayCheck}}
            <p class='proof {{if this.replayCheck.ok "ok" "bad"}}'>
              {{#if this.replayCheck.ok}}
                ✓ Seed
                {{this.state.seed}}
                plus
                {{this.replayCheck.n}}
                actions replays to exactly this table.
              {{else}}
                ✗ Replay doesn't match the saved table{{#if
                  this.replayCheck.error
                }}: {{this.replayCheck.error}}{{/if}}.
              {{/if}}
            </p>
          {{/if}}
          <ol class='log'>
            {{#each this.logRows as |e|}}
              <li class={{if e.undone 'undone'}}>
                <span class='n'>{{e.index}}</span>
                <span><b>{{e.who}}</b>
                  {{e.action}}{{#if e.resultSummary}}
                    ·
                    {{e.resultSummary}}{{/if}}</span>
              </li>
            {{/each}}
          </ol>
          <p class='hint'>Hover any face-up part on the table to see where that
            exact copy has been.</p>
        </aside>
      {{/if}}
    </div>
    <style scoped>
      .match {
        position: relative;
        min-height: 100%;
        display: flex;
        flex-direction: column;
        gap: 0.75rem;
        padding: 1rem clamp(0.75rem, 2.5cqw, 1.75rem) 1.25rem;
        background: #f4ecdd;
        color: #2b231b;
        font-family:
          ui-rounded, 'SF Pro Rounded', 'Nunito', system-ui, sans-serif;
        container-type: inline-size;
        outline: none;
        overflow: hidden;
      }
      .bar {
        display: flex;
        align-items: center;
        gap: 0.75rem;
      }
      .title {
        flex: 1;
        min-width: 0;
        text-align: center;
      }
      h1 {
        margin: 0;
        font:
          700 1.5rem/1.1 'Iowan Old Style',
          Palatino,
          Georgia,
          serif;
      }
      .link {
        font: inherit;
        background: none;
        border: 0;
        padding: 0;
        color: inherit;
        cursor: pointer;
      }
      .link:hover {
        text-decoration: underline;
        text-decoration-thickness: 1px;
        text-underline-offset: 3px;
      }
      .title p {
        margin: 0.2rem 0 0;
        color: #6b5a45;
        font-size: 0.95rem;
        min-height: 1.3em;
      }
      .chrome {
        font: inherit;
        font-size: 0.85rem;
        font-weight: 650;
        color: #6b5a45;
        background: transparent;
        border: 1px solid #d9c9a8;
        border-radius: 99px;
        padding: 0.35rem 0.8rem;
        cursor: pointer;
      }
      .chrome:hover {
        background: #ece0c8;
      }
      .seats {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: 0.5rem;
      }
      .seat {
        display: flex;
        align-items: center;
        gap: 0.45rem;
        padding: 0.3rem 0.75rem 0.3rem 0.4rem;
        border-radius: 99px;
        background: #ebe0ca;
        transition:
          background 200ms,
          box-shadow 200ms;
      }
      .seat.turn {
        background: #fff7e4;
        box-shadow: 0 0 0 2px #e7b955;
      }
      .seat.won {
        background: #fdf0c8;
        box-shadow:
          0 0 0 2px #e7b955,
          0 0 14px rgba(231, 185, 85, 0.6);
      }
      .meeple {
        width: 1.4rem;
      }
      .portrait {
        width: 2rem;
        height: 2rem;
        margin: -0.15rem 0;
        border-radius: 50%;
        object-fit: cover;
        object-position: 50% 15%;
        background: #d8c9aa;
        box-shadow: 0 0 0 2px #fff7e4;
      }
      .who small {
        color: #7a6a55;
      }
      .chips {
        font-variant-numeric: tabular-nums;
        font-weight: 700;
        color: #2f5d8a;
      }
      .dots {
        display: inline-flex;
        gap: 3px;
      }
      .dots i {
        width: 5px;
        height: 5px;
        border-radius: 50%;
        background: #8a7355;
        animation: blink 1s infinite ease-in-out;
      }
      .dots i:nth-child(2) {
        animation-delay: 0.15s;
      }
      .dots i:nth-child(3) {
        animation-delay: 0.3s;
      }
      @keyframes blink {
        50% {
          opacity: 0.2;
        }
      }
      .stage {
        position: relative;
        flex: 1;
        display: grid;
        place-items: start center;
        align-content: start;
      }
      .stage > :deep(.table-wrap) {
        max-width: min(100%, 1100px);
      }
      .loading {
        color: #8a7355;
        padding: 4rem 0;
      }
      .err {
        color: #8a2a20;
        background: #f7e0da;
        border-radius: 0.5rem;
        padding: 0.5rem 0.8rem;
        margin: 0 0 0.5rem;
      }
      .result {
        position: absolute;
        left: 50%;
        top: 50%;
        translate: -50% -50%;
        background: #fbf6ec;
        border-radius: 1rem;
        padding: 1.4rem 1.8rem;
        text-align: center;
        box-shadow: 0 18px 40px rgba(30, 20, 10, 0.35);
        animation: slidein 600ms cubic-bezier(0.2, 0.8, 0.2, 1) 500ms both;
        z-index: 400;
        max-width: 90%;
      }
      @keyframes slidein {
        from {
          translate: -50% 40%;
          opacity: 0;
        }
      }
      .rk {
        margin: 0;
        font:
          700 1.7rem 'Iowan Old Style',
          Georgia,
          serif;
      }
      .rt {
        margin: 0.4rem 0 1rem;
        color: #6b5a45;
      }
      .rb {
        display: flex;
        gap: 0.6rem;
        justify-content: center;
        flex-wrap: wrap;
      }
      .actions {
        display: flex;
        align-items: center;
        gap: 1rem;
        justify-content: space-between;
        flex-wrap: wrap;
        min-height: 2.75rem;
      }
      .last {
        margin: 0;
        color: #6b5a45;
        font-size: 0.9rem;
        flex: 1 1 14rem;
      }
      .last p {
        margin: 0;
      }
      .hint-line {
        margin-top: 0.2rem !important;
        color: #9a7a3c;
        font-size: 0.82rem;
      }
      .ghost.small {
        padding: 0.35rem 0.7rem;
        font-size: 0.85rem;
      }
      .btns {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
        justify-content: flex-end;
      }
      .primary,
      .ghost {
        font: inherit;
        font-weight: 700;
        border-radius: 99px;
        padding: 0.55rem 1.2rem;
        cursor: pointer;
      }
      .primary {
        border: 0;
        background: #f4c35a;
        color: #2b1d0c;
        box-shadow: 0 3px 0 #b88a2c;
      }
      .primary:hover {
        background: #f7cd6f;
      }
      .primary:active {
        translate: 0 2px;
        box-shadow: 0 1px 0 #b88a2c;
      }
      .ghost {
        border: 1.5px solid #cdb995;
        background: transparent;
        color: #4b3a26;
      }
      .ghost:hover {
        background: #ece0c8;
      }
      button:disabled {
        opacity: 0.45;
        cursor: default;
      }
      button:focus-visible {
        outline: 2px solid #c58b2a;
        outline-offset: 2px;
      }
      .drawer {
        position: absolute;
        top: 0;
        bottom: 0;
        width: min(22rem, 86%);
        background: #fbf6ec;
        box-shadow: 0 0 30px rgba(30, 20, 10, 0.25);
        padding: 1.1rem 1.1rem 1.5rem;
        overflow: auto;
        z-index: 500;
        animation: drawer 260ms cubic-bezier(0.2, 0.8, 0.2, 1);
      }
      .drawer.left {
        left: 0;
      }
      .drawer.right {
        right: 0;
      }
      @keyframes drawer {
        from {
          opacity: 0;
          translate: var(--from, 0) 0;
        }
      }
      .drawer.left {
        --from: -2rem;
      }
      .drawer.right {
        --from: 2rem;
      }
      .close {
        position: absolute;
        top: 0.6rem;
        right: 0.7rem;
        width: 2rem;
        height: 2rem;
        border-radius: 50%;
        border: 0;
        background: #efe3cc;
        color: #4b3a26;
        font-size: 1.2rem;
        line-height: 1;
        cursor: pointer;
      }
      .close:hover {
        background: #e4d4b6;
      }
      .drawer h2 {
        font-size: 0.78rem;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: #8a7355;
        margin: 0.25rem 0 0.6rem;
      }
      .boxes {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 0.6rem;
        margin-bottom: 1.2rem;
      }
      .box-btn {
        height: 7.5rem;
        padding: 0;
        border: 0;
        border-radius: 0.6rem;
        overflow: hidden;
        cursor: pointer;
        background: none;
        box-shadow: 0 3px 8px rgba(30, 20, 10, 0.2);
        text-align: left;
      }
      .match-btn {
        height: 8.5rem;
      }
      .box-btn:hover {
        translate: 0 -2px;
      }
      .box-btn > :deep(*) {
        height: 100%;
      }
      .hint {
        color: #7a6a55;
        font-size: 0.85rem;
        line-height: 1.5;
      }
      .proof {
        font-size: 0.85rem;
        border-radius: 0.5rem;
        padding: 0.5rem 0.7rem;
        line-height: 1.45;
      }
      .proof.ok {
        background: #e4eedb;
        color: #2f5a30;
      }
      .proof.bad {
        background: #f7e0da;
        color: #8a2a20;
      }
      .log {
        list-style: none;
        margin: 0;
        padding: 0;
        font-size: 0.88rem;
      }
      .log li {
        display: flex;
        gap: 0.55rem;
        padding: 0.35rem 0;
        border-bottom: 1px solid #ece0c8;
        line-height: 1.4;
      }
      .log li.undone {
        text-decoration: line-through;
        opacity: 0.5;
      }
      .n {
        flex: none;
        width: 2rem;
        text-align: right;
        color: #a8957a;
        font-variant-numeric: tabular-nums;
      }
      @container (width < 560px) {
        .actions {
          flex-direction: column;
          align-items: stretch;
        }
        .btns {
          justify-content: center;
        }
        .seat small {
          display: none;
        }
      }
    </style>
  </template>
}

export class Match extends CardDef {
  static displayName = 'Match';
  static icon = DicesIcon;
  @field game = linksTo(() => Game);
  @field seed = contains(NumberField);
  @field status = contains(StringField); // setup | playing | finished
  @field rngCalls = contains(NumberField);
  @field seats = containsMany(SeatField);
  @field copies = containsMany(CopyStateField);
  @field turn = contains(TurnField);
  @field vars = contains(GameJsonField);
  @field log = containsMany(ActionLogEntryField);
  @field winner = contains(StringField);
  @field resultText = contains(StringField);
  @field startedAt = contains(DatetimeField);
  @field updatedAt = contains(DatetimeField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Match) {
      let names = (this.seats ?? [])
        .map((s) =>
          s.occupant === 'human' ? 'You' : (s.opponent?.name ?? s.label),
        )
        .filter(Boolean);
      return `${this.game?.title ?? 'Match'} · ${names.join(' vs ')}`;
    },
  });

  readState(): State | null {
    if (!this.copies?.length || !this.log?.length) return null;
    return {
      seed: this.seed ?? 1,
      rngCalls: this.rngCalls ?? 0,
      status: (this.status as State['status']) ?? 'playing',
      seats: (this.seats ?? []).map(seatToPlain),
      copies: this.copies.map(copyToPlain),
      turn: {
        seat: this.turn?.seat ?? '',
        phase: this.turn?.phase ?? 'main',
        number: this.turn?.number ?? 1,
      },
      vars: { ...((this.vars as any) ?? {}) },
      log: this.log.map(logToPlain),
      ...(this.resultText
        ? { result: { winner: this.winner ?? null, text: this.resultText } }
        : {}),
    };
  }

  writeState(s: State) {
    this.seed = s.seed;
    this.rngCalls = s.rngCalls;
    this.status = s.status;
    (this.seats ?? []).forEach((f, i) => {
      let p = s.seats[i];
      if (
        p &&
        JSON.stringify(f.resources ?? {}) !== JSON.stringify(p.resources)
      )
        f.resources = { ...p.resources };
    });
    let copies = writeCopies((this.copies ?? []) as CopyStateField[], s.copies);
    if (copies) this.copies = copies;
    if (!this.turn) this.turn = new TurnField({ ...s.turn });
    else {
      if (this.turn.seat !== s.turn.seat) this.turn.seat = s.turn.seat;
      if (this.turn.phase !== s.turn.phase) this.turn.phase = s.turn.phase;
      if (this.turn.number !== s.turn.number) this.turn.number = s.turn.number;
    }
    this.vars = { ...s.vars };
    let log = writeLog((this.log ?? []) as ActionLogEntryField[], s.log);
    if (log) this.log = log;
    this.winner = (s.result?.winner ?? null) as any;
    this.resultText = (s.result?.text ?? null) as any;
    if (!this.startedAt) this.startedAt = new Date();
    this.updatedAt = new Date();
  }

  get humanSeat() {
    return (
      (this.seats ?? []).find((s) => s.occupant === 'human')?.seatId ?? null
    );
  }
  get seatColours() {
    return Object.fromEntries(
      (this.seats ?? []).map((s) => [s.seatId, s.colour ?? '#b9a685']),
    );
  }

  static isolated = MatchIsolated;

  static fitted = class Fitted extends Component<typeof this> {
    get model() {
      return this.args.model as unknown as Match;
    }
    get state() {
      return this.model.readState();
    }
    _g: { card: Game; data: GameData } | null = null;
    get gameData(): GameData {
      return this.game!;
    }
    get game() {
      let card = this.model.game as Game | undefined;
      if (!card) return null;
      if (this._g?.card !== card) this._g = { card, data: card.toData() };
      return this._g.data;
    }
    get thumbStyle() {
      let a = this.game?.layout.aspect ?? 1.5;
      return htmlSafe(`--aspect:${a}`);
    }
    get line() {
      let s = this.state;
      if (!s) return 'Not started';
      if (s.status === 'finished') return s.result?.text ?? 'Finished';
      let human = this.model.humanSeat;
      let who =
        s.turn.seat === human
          ? 'Your turn'
          : `${s.seats.find((x) => x.id === s!.turn.seat)?.label ?? ''} to play`;
      return `${who} · move ${s.log.filter((e) => !e.undone).length - 1}`;
    }
    get swatch() {
      return htmlSafe(
        `--table:${(this.model.game as Game | undefined)?.tableColour ?? '#2f6b4f'}`,
      );
    }
    <template>
      <div class='mf' style={{this.swatch}}>
        {{#if this.state}}
          {{#if this.game}}
            <div class='thumb' style={{this.thumbStyle}}>
              <Table
                @game={{this.gameData}}
                @state={{this.state}}
                @viewer={{this.model.humanSeat}}
                @staticView={{true}}
                @seatColours={{this.model.seatColours}}
                @tableColour={{this.model.game.tableColour}}
                @surface={{this.model.game.surface}}
              />
            </div>
          {{/if}}
        {{else}}
          <div class='thumb empty'></div>
        {{/if}}
        <div class='cap'>
          <b>{{this.model.game.title}}</b>
          <span>{{this.line}}</span>
        </div>
      </div>
      <style scoped>
        .mf {
          height: 100%;
          display: flex;
          flex-direction: column;
          background: #f4ecdd;
          font-family: ui-rounded, 'SF Pro Rounded', system-ui, sans-serif;
          container-type: size;
          overflow: hidden;
        }
        .thumb {
          flex: 1;
          min-height: 0;
          display: flex;
          justify-content: center;
          align-items: flex-start;
          padding: 4cqmin 4cqmin 0;
          overflow: hidden;
          pointer-events: none;
        }
        .thumb > :deep(.table-wrap) {
          width: min(100%, calc((100cqh - 3.2rem) * var(--aspect)));
        }
        .thumb.empty {
          background: var(--table);
          margin: 4cqmin 4cqmin 0;
          border-radius: 6px;
        }
        .cap {
          display: flex;
          flex-direction: column;
          padding: 2.5cqmin 4cqmin 3.5cqmin;
          line-height: 1.25;
          min-width: 0;
        }
        b {
          font:
            700 clamp(0.8rem, 8cqmin, 1.05rem) 'Iowan Old Style',
            Georgia,
            serif;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        span {
          color: #6b5a45;
          font-size: clamp(0.65rem, 6cqmin, 0.85rem);
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        @container (height < 110px) {
          .thumb {
            display: none;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get model() {
      return this.args.model as unknown as Match;
    }
    get text() {
      let m = this.model;
      let names = (m.seats ?? []).map((s) =>
        s.occupant === 'human' ? 'You' : (s.opponent?.name ?? s.label),
      );
      let st =
        m.status === 'finished'
          ? (m.resultText ?? 'finished')
          : m.turn?.seat === m.humanSeat
            ? 'your turn'
            : `${m.turn?.seat ?? ''} to play`;
      let moves = Math.max(
        0,
        (m.log ?? []).filter((e) => !e.undone).length - 1,
      );
      return `${m.game?.title ?? 'Match'} · ${names.join(' vs ')} · move ${moves} · ${st}`;
    }
    <template>
      <span class='me'>{{this.text}}</span>
      <style scoped>
        .me {
          font-family: ui-rounded, system-ui, sans-serif;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get model() {
      return this.args.model as unknown as Match;
    }
    get swatch() {
      return htmlSafe(
        `background:${(this.model.game as Game | undefined)?.tableColour ?? '#2f6b4f'}`,
      );
    }
    get dot() {
      let m = this.model;
      let mine = m.status !== 'finished' && m.turn?.seat === m.humanSeat;
      return htmlSafe(
        `background:${mine ? '#e7a93a' : m.status === 'finished' ? '#9a8b75' : '#5c8a5a'}`,
      );
    }
    <template>
      <span class='ma'><span
          class='sw'
          style={{this.swatch}}
        ></span>{{this.model.game.title}}<span
          class='dot'
          style={{this.dot}}
        ></span></span>
      <style scoped>
        .ma {
          display: inline-flex;
          gap: 0.3rem;
          align-items: center;
        }
        .sw {
          width: 0.85em;
          height: 0.65em;
          border-radius: 0.15em;
        }
        .dot {
          width: 0.45em;
          height: 0.45em;
          border-radius: 50%;
        }
      </style>
    </template>
  };
}

function ordinal(n: number) {
  let s = ['th', 'st', 'nd', 'rd'];
  let v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

function inPrerender() {
  return Boolean((globalThis as any).__boxelRenderContext);
}

function getComponent(card: CardDefType) {
  return (card.constructor as typeof CardDefType).getComponent(card);
}
