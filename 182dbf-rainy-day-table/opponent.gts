// An opponent that sits in a seat. Written as data: a priority list
// (policy), a look-ahead (search), or the random baseline. An LLM kind is
// reserved for Phase 2.

import {
  CardDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  realmURL,
} from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import NumberField from '@cardstack/base/number';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import BotIcon from '@cardstack/boxel-icons/bot';
import { GameJsonField, PolicyRuleField } from './fields';
import { Game } from './game';
import { describe } from './expr';
import { Token } from './parts';

// @ts-expect-error import.meta is valid ESM but TS detects .gts as CJS
const here: string = import.meta.url;

const KIND_WORDS: Record<string, string> = {
  random: 'Plays any legal move at random. The baseline every bot must beat.',
  policy:
    'Follows a written priority list, top to bottom, and takes the first rule that applies.',
  search: 'Looks ahead a few moves and picks the line that leaves it best off.',
  llm: 'Asks a language model to choose among the legal moves (Phase 2).',
};

export class Opponent extends CardDef {
  static displayName = 'Opponent';
  static icon = BotIcon;
  @field name = contains(StringField);
  @field style = contains(StringField);
  @field kind = contains(StringField); // random | policy | search | llm
  @field game = linksTo(() => Game);
  @field policy = containsMany(PolicyRuleField);
  @field searchDepth = contains(NumberField);
  @field scoring = contains(GameJsonField);
  @field thinkingDelay = contains(NumberField);
  @field persona = contains(StringField);
  @field colour = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Opponent) {
      return this.name ?? 'Opponent';
    },
  });

  botSpec() {
    return {
      name: this.name,
      kind: (this.kind ?? 'random') as any,
      policy: (this.policy ?? []).map((r) => ({
        when: r.when ?? 'true',
        do: r.do ?? '',
        weight: r.weight ?? undefined,
      })),
      searchDepth: this.searchDepth ?? 2,
      scoring: this.scoring ?? undefined,
      thinkingDelay: this.thinkingDelay ?? 500,
    };
  }

  static isolated = class Isolated extends Component<typeof this> {
    get colourStyle() {
      return htmlSafe(`--bot:${this.args.model.colour ?? '#b5533c'}`);
    }
    get kindText() {
      return KIND_WORDS[this.args.model.kind ?? 'random'] ?? '';
    }
    get rules() {
      return (this.args.model.policy ?? []).map((r, i) => ({
        n: i + 1,
        when: describe(r.when ?? 'true'),
        do: (r.do ?? '').replace(':', ' '),
      }));
    }
    get values() {
      let pv = (this.args.model.scoring as any)?.pieceValues ?? {};
      return Object.entries(pv)
        .map(([k, v]) => `${k} ${v}`)
        .join(' · ');
    }
    // Win record from every Match in this realm where this bot sat.
    matchQuery = this.args.context?.getCards(
      this,
      () =>
        ({
          filter: {
            type: { module: new URL('./match', here).href, name: 'Match' },
          },
        }) as any,
      () => {
        let r = this.args.model[realmURL];
        return r ? [r.href] : undefined;
      },
      { isLive: true },
    );
    get record() {
      let id = this.args.model.id;
      let wins = 0;
      let losses = 0;
      let draws = 0;
      for (let m of (this.matchQuery?.instances ?? []) as any[]) {
        if (m.status !== 'finished') continue;
        let seat = (m.seats ?? []).find((s: any) => s.opponent?.id === id);
        if (!seat) continue;
        if (!m.winner) draws++;
        else if (m.winner === seat.seatId) wins++;
        else losses++;
      }
      return { wins, losses, draws, played: wins + losses + draws };
    }
    <template>
      <div class='opp-page'>
        <article class='opp' style={{this.colourStyle}}>
          <header>
            <div class='meeple'><Token
                @colour={{if @model.colour @model.colour '#b5533c'}}
              /></div>
            <div>
              <p class='eyebrow'>Opponent{{#if @model.game}}
                  ·
                  {{@model.game.title}}{{/if}}</p>
              <h1>{{@model.name}}</h1>
              {{#if @model.style}}<p class='style'>{{@model.style}}</p>{{/if}}
            </div>
          </header>
          <section class='kind'>
            <span class='tag'>{{if @model.kind @model.kind 'random'}}</span>
            <p>{{this.kindText}}</p>
          </section>
          {{#if (eq @model.kind 'policy')}}
            <section>
              <h2>How it decides</h2>
              <ol class='rules'>
                {{#each this.rules as |r|}}
                  <li><span class='when'>{{r.when}}</span>
                    <span class='arrow'>→</span>
                    <b>{{r.do}}</b></li>
                {{/each}}
              </ol>
            </section>
          {{/if}}
          {{#if (eq @model.kind 'search')}}
            <section>
              <h2>How it decides</h2>
              <p>Looks
                {{if @model.searchDepth @model.searchDepth 2}}
                moves ahead (its move and your reply) and scores what's left on
                the board.</p>
              {{#if this.values}}<p class='values'>Piece values:
                  {{this.values}}</p>{{/if}}
            </section>
          {{/if}}
          <section class='record'>
            <h2>Record here</h2>
            {{#if this.record.played}}
              <p><b>{{this.record.wins}}</b>
                won ·
                <b>{{this.record.losses}}</b>
                lost ·
                <b>{{this.record.draws}}</b>
                drawn</p>
            {{else}}
              <p class='muted'>No finished matches yet.</p>
            {{/if}}
            <p class='muted'>Thinks for about
              {{if @model.thinkingDelay @model.thinkingDelay 500}}
              ms before each move.</p>
          </section>
        </article>
      </div>
      <style scoped>
        .opp-page {
          min-height: 100%;
          background: #fbf6ec;
        }
        .opp {
          max-width: 46rem;
          margin: 0 auto;
          padding: 2rem 1.5rem 3rem;
          font-family: ui-rounded, 'SF Pro Rounded', system-ui, sans-serif;
          color: #2b231b;
          background: #fbf6ec;
          min-height: 100%;
        }
        header {
          display: flex;
          gap: 1.25rem;
          align-items: center;
        }
        .meeple {
          width: 5.5rem;
          flex: none;
        }
        .eyebrow {
          margin: 0;
          font-size: 0.78rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: #8a7355;
        }
        h1 {
          margin: 0.15rem 0 0;
          font:
            700 2.2rem/1.1 'Iowan Old Style',
            Palatino,
            Georgia,
            serif;
        }
        .style {
          margin: 0.25rem 0 0;
          color: #6b5a45;
          font-size: 1.05rem;
        }
        section {
          margin-top: 1.75rem;
        }
        h2 {
          font-size: 0.85rem;
          letter-spacing: 0.06em;
          text-transform: uppercase;
          color: #8a7355;
          margin: 0 0 0.5rem;
        }
        .kind {
          display: flex;
          gap: 0.75rem;
          align-items: baseline;
        }
        .kind p {
          margin: 0;
          line-height: 1.5;
        }
        .tag {
          flex: none;
          background: var(--bot);
          color: #fff;
          border-radius: 99px;
          padding: 0.15rem 0.6rem;
          font-size: 0.78rem;
          font-weight: 700;
        }
        .rules {
          margin: 0;
          padding-left: 1.4rem;
          line-height: 1.7;
        }
        .when {
          color: #4b3d2e;
        }
        .arrow {
          color: #b09670;
        }
        .values {
          font-variant-numeric: tabular-nums;
          color: #6b5a45;
        }
        .muted {
          color: #8a7a66;
          font-size: 0.9rem;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='f'>
        <div class='m'><Token
            @colour={{if @model.colour @model.colour '#b5533c'}}
          /></div>
        <div class='t'>
          <b>{{@model.name}}</b>
          {{#if @model.style}}<span>{{@model.style}}</span>{{/if}}
          <small>{{if @model.kind @model.kind 'random'}}{{#if @model.game}}
              ·
              {{@model.game.title}}{{/if}}</small>
        </div>
      </div>
      <style scoped>
        .f {
          display: flex;
          gap: 0.6rem;
          align-items: center;
          height: 100%;
          padding: 0.6rem 0.75rem;
          background: #fbf6ec;
          font-family: ui-rounded, 'SF Pro Rounded', system-ui, sans-serif;
          container-type: inline-size;
          box-sizing: border-box;
        }
        .m {
          width: min(30%, 4rem);
          flex: none;
        }
        .t {
          display: flex;
          flex-direction: column;
          min-width: 0;
          line-height: 1.25;
        }
        b {
          font:
            700 1rem 'Iowan Old Style',
            Georgia,
            serif;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        span {
          color: #6b5a45;
          font-size: 0.85rem;
        }
        small {
          color: #8a7a66;
          font-size: 0.72rem;
        }
        @container (height < 70px) {
          span,
          small {
            display: none;
          }
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <span class='e'><span class='m'><Token
            @colour={{if @model.colour @model.colour '#b5533c'}}
          /></span>{{@model.name}}</span>
      <style scoped>
        .e {
          display: inline-flex;
          gap: 0.4rem;
          align-items: center;
          font-weight: 600;
        }
        .m {
          width: 1.3rem;
          display: inline-block;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    <template>
      <span class='a'><span class='m'><Token
            @colour={{if @model.colour @model.colour '#b5533c'}}
          /></span>{{@model.name}}</span>
      <style scoped>
        .a {
          display: inline-flex;
          gap: 0.25rem;
          align-items: center;
        }
        .m {
          width: 1em;
          display: inline-block;
        }
      </style>
    </template>
  };
}
