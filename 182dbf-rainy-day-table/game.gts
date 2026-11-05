// The Game card is the box: which parts are inside, how the table is laid
// out, and the rules, all as data. "Play" opens a new Match on it.

import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksToMany,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import MarkdownField from '@cardstack/base/markdown';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { on } from '@ember/modifier';
import { eq } from '@cardstack/boxel-ui/helpers';
import BoxIcon from '@cardstack/boxel-icons/box';
import {
  ComponentDefinitionField,
  GameJsonField,
  LookField,
  defToPlain,
  lookToPlain,
} from './fields';
import { Opponent } from './opponent';
import type { GameData, Seat } from './engine';
import { validateGame, smokeTest } from './validate';
import type { BotSpec } from './bots';
import { Part } from './parts';
import './chess-rules';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

export interface SeatTemplate extends Seat {
  opponent?: string; // relative URL of an Opponent card
  image?: string; // the seat's portrait: who sits there (a hero, a monster)
}

const KIND_LABEL: Record<string, string> = {
  card: 'Cards',
  die: 'Dice',
  coin: 'Coins',
  chip: 'Chips',
  tile: 'Tiles',
  board: 'Boards',
  token: 'Tokens',
  piece: 'Pieces',
};

class GameIsolated extends Component<typeof Game> {
  get game() {
    return this.args.model as unknown as Game;
  }
  @tracked testRun: ReturnType<typeof smokeTest> | null = null;
  @tracked starting = false;
  @tracked startError = '';

  get data() {
    return this.game.toData();
  }
  get lidStyle() {
    return htmlSafe(`--table:${this.args.model.tableColour ?? '#2f6b4f'}`);
  }
  get players() {
    let a = this.args.model.minPlayers;
    let b = this.args.model.maxPlayers;
    if (!a && !b) return '';
    return a === b || !b
      ? `${a} player${a === 1 ? '' : 's'}`
      : `${a}–${b} players`;
  }
  get inventory() {
    let groups = new Map<string, { defs: any[]; copies: number }>();
    for (let d of this.data.components) {
      let g = groups.get(d.kind) ?? { defs: [], copies: 0 };
      g.defs.push(d);
      g.copies += d.quantity ?? 1;
      groups.set(d.kind, g);
    }
    return [...groups.entries()].map(([kind, g]) => {
      let n = g.defs.length;
      let step = n > 6 ? Math.floor(n / 6) : 1;
      let sample = g.defs.filter((_, i) => i % step === 0).slice(0, 6);
      let dupes = g.copies > n;
      return {
        kind,
        label: KIND_LABEL[kind] ?? kind,
        sample,
        line: dupes
          ? `${n} kinds × ${Math.round(g.copies / n)} = ${g.copies} copies, each tracked on its own`
          : `${g.copies} ${g.copies === 1 ? 'part' : 'parts'}`,
        wide: kind === 'card',
      };
    });
  }
  get seats() {
    return this.game.seatTemplates().map((s) => ({
      ...s,
      opp: s.opponent
        ? (this.args.model.opponents ?? []).find(
            (o) =>
              o.id &&
              this.args.model.id &&
              o.id === new URL(s.opponent!, this.args.model.id).href,
          )
        : undefined,
    }));
  }
  get findings() {
    return validateGame(this.data, this.game.seatTemplates());
  }
  get errors() {
    return this.findings.filter((f) => f.level === 'error');
  }
  get warnings() {
    return this.findings.filter((f) => f.level === 'warning');
  }
  get testWins() {
    if (!this.testRun) return [];
    return Object.entries(this.testRun.wins).map(([seat, n]) => ({
      seat: this.seats.find((s) => s.id === seat)?.label ?? seat,
      n,
      pct: Math.round((n / Math.max(1, this.testRun!.runs)) * 100),
    }));
  }
  runTest = () => {
    let bots: Record<string, BotSpec> = {};
    for (let s of this.seats)
      bots[s.id] = s.opp ? (s.opp.botSpec() as BotSpec) : { kind: 'random' };
    this.testRun = smokeTest(
      this.data,
      this.seats,
      bots,
      this.args.model.ruleModule ? 6 : 40,
    );
  };
  play = async () => {
    if (this.starting) return;
    this.starting = true;
    this.startError = '';
    try {
      await startMatch(this.game, {
        createCard: this.args.createCard as any,
        viewCard: this.args.viewCard as any,
        context: this.args.context,
      });
    } catch (e: any) {
      this.startError = String(e?.message ?? e);
    } finally {
      this.starting = false;
    }
  };
  <template>
    <article class='box'>
      <header
        class='lid s-{{if @model.surface @model.surface "felt"}}'
        style={{this.lidStyle}}
      >
        {{#if @model.lidArt}}<img
            class='art'
            src={{@model.lidArt}}
            alt=''
          />{{/if}}
        <div class='lid-text'>
          <p class='eyebrow'>Rainy Day Table</p>
          <h1>{{@model.title}}</h1>
          {{#if @model.summary}}<p class='sum'>{{@model.summary}}</p>{{/if}}
          <p class='meta'>{{this.players}}{{#if @model.playTime}}
              ·
              {{@model.playTime}}{{/if}}</p>
        </div>
        <button
          type='button'
          class='play'
          {{on 'click' this.play}}
          disabled={{this.starting}}
        >{{if this.starting 'Setting out the pieces…' 'Play'}}</button>
      </header>
      {{#if this.startError}}<p class='err' role='alert'>Couldn't start a match:
          {{this.startError}}</p>{{/if}}

      <section class='insert' aria-label="What's in the box">
        <h2>In the box</h2>
        <div class='trays'>
          {{#each this.inventory as |g|}}
            <div class='tray {{if g.wide "wide"}}'>
              <div class='parts k-{{g.kind}}'>
                {{#each g.sample as |d|}}
                  <div class='slot'><Part
                      @def={{d}}
                      @cardLook={{this.data.cardLook}}
                    /></div>
                {{/each}}
              </div>
              <p><b>{{g.label}}</b> {{g.line}}</p>
            </div>
          {{/each}}
        </div>
      </section>

      <div class='cols'>
        <section class='rules'>
          <h2>How to play</h2>
          {{#if @model.rulesText}}<@fields.rulesText />{{else}}<p
              class='muted'
            >No rules summary yet.</p>{{/if}}
        </section>
        <section class='seats'>
          <h2>At the table</h2>
          <ul>
            {{#each this.seats as |s|}}
              <li>
                <span class='dot' style={{htmlSafe (dotStyle s.colour)}}></span>
                <b>{{s.label}}</b>
                <span class='who'>{{#if s.opp}}{{s.opp.name}}{{#if
                      s.opp.style
                    }}, {{s.opp.style}}{{/if}}{{else if
                    (eq s.occupant 'human')
                  }}you{{else}}a bot that rolls{{/if}}</span>
              </li>
            {{/each}}
          </ul>
          {{#if @model.opponents.length}}
            <div class='opps'>
              <@fields.opponents @format='fitted' />
            </div>
          {{/if}}
        </section>
      </div>

      <section class='health'>
        <h2>Health check</h2>
        {{#if this.errors.length}}
          <ul class='finds'>{{#each this.errors as |f|}}<li
                class='e'
              >{{f.text}}</li>{{/each}}</ul>
        {{else}}
          <p class='ok'>✓ The rules read cleanly: every zone, part, phase and
            expression they mention exists.</p>
        {{/if}}
        {{#if this.warnings.length}}
          <ul class='finds'>{{#each this.warnings as |f|}}<li
                class='w'
              >{{f.text}}</li>{{/each}}</ul>
        {{/if}}
        <div class='test'>
          <button
            type='button'
            class='ghost'
            {{on 'click' this.runTest}}
          >Test-play with bots</button>
          {{#if this.testRun}}
            <p>
              {{this.testRun.runs}}
              bot-vs-bot matches in
              {{this.testRun.ms}}
              ms, about
              {{this.testRun.avgLength}}
              actions each.
              {{#each this.testWins as |w|}}<span class='pill'>{{w.seat}}
                  {{w.pct}}%</span>{{/each}}
              {{#if this.testRun.draws}}<span class='pill'>draws
                  {{this.testRun.draws}}</span>{{/if}}
              {{#if this.testRun.stalls}}<span
                  class='pill bad'
                >{{this.testRun.stalls}}
                  stalled:
                  {{this.testRun.firstStall}}</span>{{/if}}
              {{#if this.testRun.soloRuns}}<span class='pill bad'>in
                  {{this.testRun.soloRuns}}
                  matches only one seat ever moved: does the turn pass?</span>{{/if}}
              {{#each this.testRun.errors as |e|}}<span
                  class='pill bad'
                >{{e}}</span>{{/each}}
            </p>
          {{/if}}
        </div>
      </section>
    </article>
    <style scoped>
      .box {
        --ink: #2b231b;
        --muted: #8a7355;
        --paper: #fbf6ec;
        min-height: 100%;
        background: var(--paper);
        color: var(--ink);
        font-family:
          ui-rounded, 'SF Pro Rounded', 'Nunito', system-ui, sans-serif;
        container-type: inline-size;
        padding-bottom: 3rem;
      }
      .lid {
        position: relative;
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        gap: 1rem;
        padding: 2.5rem clamp(1rem, 4cqw, 3rem) 1.75rem;
        min-height: 13rem;
        background-color: var(--table);
        color: #fff8ea;
        overflow: hidden;
        box-shadow: inset 0 -10px 24px rgba(0, 0, 0, 0.22);
      }
      .lid.s-paper {
        color: #2b231b;
      }
      .s-felt {
        background-image: radial-gradient(
          ellipse at 30% 10%,
          rgba(255, 255, 255, 0.14),
          transparent 60%
        );
      }
      .s-wood {
        background-image:
          radial-gradient(
            ellipse at 30% 10%,
            rgba(255, 230, 190, 0.18),
            transparent 60%
          ),
          repeating-linear-gradient(
            96deg,
            rgba(0, 0, 0, 0.06) 0 3px,
            transparent 3px 11px
          );
      }
      .s-paper {
        background-image: radial-gradient(
          ellipse at 30% 10%,
          rgba(255, 255, 255, 0.6),
          transparent 60%
        );
        box-shadow: inset 0 -1px 0 #d9c9a8;
      }
      .art {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        opacity: 0.35;
      }
      .lid-text {
        position: relative;
        max-width: 36rem;
      }
      .eyebrow {
        margin: 0;
        font-size: 0.75rem;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        opacity: 0.75;
      }
      h1 {
        margin: 0.2rem 0 0;
        font:
          700 clamp(2rem, 6cqw, 3.4rem) / 1.02 'Iowan Old Style',
          'Palatino Linotype',
          Palatino,
          Georgia,
          serif;
        letter-spacing: -0.01em;
      }
      .sum {
        margin: 0.5rem 0 0;
        font-size: 1.05rem;
        line-height: 1.45;
        opacity: 0.92;
      }
      .meta {
        margin: 0.6rem 0 0;
        font-size: 0.9rem;
        opacity: 0.8;
      }
      .play {
        position: relative;
        flex: none;
        font: inherit;
        font-weight: 750;
        font-size: 1.05rem;
        padding: 0.75rem 1.6rem;
        border-radius: 99px;
        border: 0;
        background: #f4c35a;
        color: #2b1d0c;
        cursor: pointer;
        box-shadow:
          0 3px 0 #b88a2c,
          0 6px 14px rgba(0, 0, 0, 0.25);
      }
      .play:hover {
        background: #f7cd6f;
      }
      .play:active {
        translate: 0 2px;
        box-shadow: 0 1px 0 #b88a2c;
      }
      .play:disabled {
        opacity: 0.7;
        cursor: progress;
      }
      .err {
        margin: 1rem clamp(1rem, 4cqw, 3rem) 0;
        color: #9b2f25;
      }
      section {
        padding: 0 clamp(1rem, 4cqw, 3rem);
        margin-top: 2rem;
      }
      h2 {
        font-size: 0.8rem;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted);
        margin: 0 0 0.75rem;
      }
      .trays {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(11rem, 1fr));
        gap: 0.9rem;
      }
      .tray {
        background: #efe3cc;
        border-radius: 0.9rem;
        padding: 1rem 1rem 0.8rem;
        box-shadow:
          inset 0 2px 6px rgba(80, 55, 25, 0.25),
          inset 0 -1px 0 rgba(255, 255, 255, 0.6);
      }
      .tray.wide {
        grid-column: span 2;
      }
      .parts {
        display: flex;
        align-items: flex-end;
        justify-content: center;
        min-height: 5.5rem;
      }
      .slot {
        width: 3.4rem;
        margin: 0 -0.1rem;
      }
      .k-card .slot {
        width: 3.6rem;
        margin: 0 -0.55rem;
      }
      .k-card .slot:nth-child(odd) {
        rotate: -4deg;
      }
      .k-card .slot:nth-child(even) {
        rotate: 3deg;
        translate: 0 -3px;
      }
      .k-piece .slot {
        width: 2.6rem;
        margin: 0 -0.25rem;
      }
      .k-board .slot {
        width: 4.5rem;
      }
      .k-chip .slot,
      .k-coin .slot {
        width: 3rem;
      }
      .tray p {
        margin: 0.6rem 0 0;
        font-size: 0.85rem;
        color: #5e4c37;
        line-height: 1.35;
      }
      .cols {
        display: grid;
        grid-template-columns: 1.4fr 1fr;
        gap: 0 2rem;
      }
      @container (width < 640px) {
        .cols {
          grid-template-columns: 1fr;
        }
        .tray.wide {
          grid-column: auto;
        }
        .lid {
          flex-direction: column;
          align-items: flex-start;
        }
      }
      .rules :deep(p),
      .rules :deep(li) {
        line-height: 1.6;
      }
      .seats ul {
        list-style: none;
        padding: 0;
        margin: 0 0 1rem;
      }
      .seats li {
        display: flex;
        gap: 0.5rem;
        align-items: center;
        padding: 0.35rem 0;
        border-bottom: 1px solid #eadcc2;
      }
      .dot {
        width: 0.8rem;
        height: 0.8rem;
        border-radius: 50%;
        flex: none;
      }
      .who {
        color: #6b5a45;
      }
      .opps :deep(.containsMany-field) {
        display: grid;
        gap: 0.5rem;
      }
      .opps :deep(.field-component-card.fitted-format) {
        height: 4.5rem;
      }
      .ok {
        color: #3d6b3f;
      }
      .finds {
        padding-left: 1.2rem;
        line-height: 1.5;
      }
      .finds .e {
        color: #9b2f25;
      }
      .finds .w {
        color: #8a5a12;
      }
      .test p {
        line-height: 2;
        color: #5e4c37;
      }
      .ghost {
        font: inherit;
        font-weight: 650;
        padding: 0.5rem 1rem;
        border-radius: 99px;
        border: 1.5px solid #c9b48d;
        background: transparent;
        color: #4b3a26;
        cursor: pointer;
      }
      .ghost:hover {
        background: #f1e6d1;
      }
      .pill {
        display: inline-block;
        margin-left: 0.4rem;
        padding: 0 0.6rem;
        border-radius: 99px;
        background: #efe3cc;
        font-size: 0.85rem;
        line-height: 1.7;
      }
      .pill.bad {
        background: #f5d9d3;
        color: #8a2a20;
      }
      .muted {
        color: #8a7a66;
      }
    </style>
  </template>
}

export class Game extends CardDef {
  static displayName = 'Game';
  static icon = BoxIcon;
  @field title = contains(StringField);
  @field summary = contains(StringField);
  @field minPlayers = contains(NumberField);
  @field maxPlayers = contains(NumberField);
  @field playTime = contains(StringField);
  @field tableColour = contains(StringField);
  @field surface = contains(StringField); // felt | wood | paper
  @field lidArt = contains(StringField);
  @field components = containsMany(ComponentDefinitionField);
  @field cardLook = contains(LookField);
  @field layout = contains(GameJsonField);
  @field ruleset = contains(GameJsonField);
  @field ruleModule = contains(StringField);
  @field defaultSeats = contains(GameJsonField);
  @field rulesText = contains(MarkdownField);
  @field version = contains(NumberField);
  @field opponents = linksToMany(() => Opponent);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Game) {
      return this.title ?? 'Untitled game';
    },
  });

  toData(): GameData {
    return {
      title: this.title ?? 'Untitled',
      components: (this.components ?? []).map(defToPlain),
      layout: (this.layout as any) ?? { zones: [] },
      ruleset: (this.ruleset as any) ?? {},
      ...(this.ruleModule ? { ruleModule: this.ruleModule } : {}),
      ...(lookToPlain(this.cardLook)
        ? { cardLook: lookToPlain(this.cardLook) }
        : {}),
    };
  }
  seatTemplates(): SeatTemplate[] {
    let s = (this.defaultSeats as any) ?? [];
    return Array.isArray(s) ? s : [];
  }

  static isolated = GameIsolated;

  static fitted = class Fitted extends Component<typeof this> {
    get style() {
      return htmlSafe(`--table:${this.args.model.tableColour ?? '#2f6b4f'}`);
    }
    get kinds() {
      let seen = new Map<string, any>();
      for (let d of this.args.model.components ?? []) {
        let p = defToPlain(d);
        if (!seen.has(p.kind) && p.kind !== 'board') seen.set(p.kind, p);
      }
      return [...seen.values()].slice(0, 4);
    }
    get players() {
      let a = this.args.model.minPlayers;
      let b = this.args.model.maxPlayers;
      return a === b || !b ? `${a ?? '?'}p` : `${a}–${b}p`;
    }
    get cardLook() {
      return lookToPlain(this.args.model.cardLook);
    }
    <template>
      <div
        class='shelf-box s-{{if @model.surface @model.surface "felt"}}'
        style={{this.style}}
      >
        <div class='spine'></div>
        <div class='face'>
          <h3>{{@model.title}}</h3>
          <p>{{this.players}}{{#if @model.playTime}}
              ·
              {{@model.playTime}}{{/if}}</p>
          <div class='icons'>
            {{#each this.kinds as |d|}}
              <div class='ic'><Part
                  @def={{d}}
                  @cardLook={{this.cardLook}}
                /></div>
            {{/each}}
          </div>
        </div>
      </div>
      <style scoped>
        .shelf-box {
          position: relative;
          height: 100%;
          display: flex;
          background-color: var(--table);
          color: #fff8ea;
          font-family: ui-rounded, 'SF Pro Rounded', system-ui, sans-serif;
          container-type: size;
          overflow: hidden;
          box-shadow: inset 0 -6px 14px rgba(0, 0, 0, 0.25);
        }
        .shelf-box.s-paper {
          color: #2b231b;
          box-shadow: inset 0 -2px 0 #d7c6a3;
        }
        .s-felt {
          background-image: radial-gradient(
            ellipse at 30% 10%,
            rgba(255, 255, 255, 0.16),
            transparent 60%
          );
        }
        .s-wood {
          background-image: repeating-linear-gradient(
            96deg,
            rgba(0, 0, 0, 0.07) 0 2px,
            transparent 2px 9px
          );
        }
        .spine {
          width: 6px;
          flex: none;
          background: rgba(0, 0, 0, 0.18);
        }
        .face {
          flex: 1;
          min-width: 0;
          padding: 8cqmin 9cqmin;
          display: flex;
          flex-direction: column;
        }
        h3 {
          margin: 0;
          font:
            700 clamp(0.9rem, 12cqmin, 1.9rem) / 1.05 'Iowan Old Style',
            Palatino,
            Georgia,
            serif;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        p {
          margin: 0.25rem 0 0;
          font-size: clamp(0.65rem, 6cqmin, 0.9rem);
          opacity: 0.85;
        }
        .icons {
          margin-top: auto;
          display: flex;
          gap: 4cqmin;
          align-items: flex-end;
        }
        .ic {
          width: clamp(1rem, 16cqmin, 3.2rem);
        }
        @container (height < 90px) {
          .icons {
            display: none;
          }
        }
        @container (width < 110px) {
          .icons,
          p {
            display: none;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    get players() {
      let a = this.args.model.minPlayers;
      let b = this.args.model.maxPlayers;
      return a === b || !b
        ? `${a ?? '?'} player${a === 1 ? '' : 's'}`
        : `${a}–${b} players`;
    }
    get swatch() {
      return htmlSafe(`background:${this.args.model.tableColour ?? '#2f6b4f'}`);
    }
    <template>
      <span class='g'><span class='sw' style={{this.swatch}}></span><b
        >{{@model.title}}</b>
        <span class='m'>{{this.players}}{{#if @model.playTime}}
            ·
            {{@model.playTime}}{{/if}}</span></span>
      <style scoped>
        .g {
          display: inline-flex;
          gap: 0.45rem;
          align-items: center;
          font-family: ui-rounded, system-ui, sans-serif;
        }
        .sw {
          width: 0.9rem;
          height: 0.9rem;
          border-radius: 0.2rem;
          box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.2);
        }
        .m {
          color: #7a6a55;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get swatch() {
      return htmlSafe(`background:${this.args.model.tableColour ?? '#2f6b4f'}`);
    }
    <template>
      <span class='a'><span
          class='sw'
          style={{this.swatch}}
        ></span>{{@model.title}}</span>
      <style scoped>
        .a {
          display: inline-flex;
          gap: 0.3rem;
          align-items: center;
        }
        .sw {
          width: 0.85em;
          height: 0.65em;
          border-radius: 0.15em;
          box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.25);
        }
      </style>
    </template>
  };
}

function dotStyle(c?: string) {
  return `background:${c ?? '#b9a685'}`;
}

// Create a Match for this game: seats from the box, a fresh seed. The table
// sets itself out the first time the match opens.
export interface CardEnv {
  createCard?: (...args: any[]) => Promise<string | undefined>;
  viewCard?: (...args: any[]) => void;
  context?: any;
}

// Create a Match for this game: seats from the box, a fresh seed. The table
// sets itself out the first time the match opens. Some views (a card opened
// from the AI panel, a card inside another card) get no createCard; then the
// store creates it and we open it ourselves.
export async function startMatch(
  game: Game,
  env: CardEnv,
  seats?: SeatTemplate[],
  localDir = 'Match/',
) {
  let templates = seats ?? game.seatTemplates();
  let relationships: Record<string, any> = {
    game: { links: { self: game.id } },
  };
  templates.forEach((s, i) => {
    if (s.opponent)
      relationships[`seats.${i}.opponent`] = {
        links: { self: new URL(s.opponent, game.id).href },
      };
  });
  let ref = { module: new URL('./match', here).href, name: 'Match' };
  let doc = {
    data: {
      type: 'card',
      attributes: {
        seed: Math.floor(Math.random() * 2 ** 31),
        status: 'setup',
        seats: templates.map((s) => ({
          seatId: s.id,
          label: s.label,
          occupant: s.occupant,
          colour: s.colour ?? null,
          image: s.image ?? null,
          resources: s.resources ?? {},
        })),
      },
      relationships,
      meta: { adoptsFrom: ref },
    },
  };
  let realm = game[realmURL];
  if (env.createCard) {
    return env.createCard(ref, new URL(here), {
      realmURL: realm,
      localDir,
      doc,
      cardModeAfterCreation: 'isolated',
    });
  }
  let store = env.context?.store;
  if (!store?.create)
    throw new Error(
      'this view cannot create cards; open the game from the workspace and try again',
    );
  let id = await store.create(doc as any, { realm: realm?.href, localDir });
  if (typeof id !== 'string')
    throw new Error((id as any)?.message ?? 'the match could not be saved');
  if (env.viewCard) env.viewCard(new URL(id), 'isolated');
  return id;
}
