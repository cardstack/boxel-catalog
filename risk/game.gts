import { concat, fn } from '@ember/helper';
/*
  Risk: Game definition
  - Holds full game state and interactive UI for placement, attack, fortify, end turn.
  - Mini-map with ~12 territories across 3 continents.
*/
// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  FieldDef,
  Component,
  field,
  contains,
  containsMany,
  linksTo,
  linksToMany,
} from 'https://cardstack.com/base/card-api'; // ¹
import StringField from 'https://cardstack.com/base/string';
import NumberField from 'https://cardstack.com/base/number';
import BooleanField from 'https://cardstack.com/base/boolean';
import { tracked } from '@glimmer/tracking';
import { Button } from '@cardstack/boxel-ui/components';
import { on } from '@ember/modifier';
import { action } from '@ember/object';
import DiceIcon from '@cardstack/boxel-icons/dice-5'; // ²
import { Player } from './player';
import { Territory } from './territory';
import { Continent } from './continent';
import { formatNumber, eq, gt, or } from '@cardstack/boxel-ui/helpers';

export class Game extends CardDef {
  // ³
  static displayName = 'Risk Game';
  static icon = DiceIcon;
  static prefersWideFormat = true;

  // Core state
  @field name = contains(StringField); // ⁴ game name
  @field players = linksToMany(Player); // ⁵ participants
  @field territories = linksToMany(Territory); // ⁶ map territories
  @field continents = linksToMany(Continent); // ⁷ map continents
  @field currentPlayerIndex = contains(NumberField); // ⁸ whose turn (0-based)
  @field phase = contains(StringField); // ⁹ 'placement' | 'attack' | 'fortify'
  @field pendingFrom = linksTo(Territory); // ¹⁰ selection for attack/fortify
  @field pendingTo = linksTo(Territory); // ¹¹ selection to target
  @field lastRoll = contains(StringField); // ¹² dice result text

  // Display title
  @field cardTitle = contains(StringField, {
    computeVia: function (this: Game) {
      try {
        const n = this.name ?? 'Risk Game';
        return n;
      } catch {
        return 'Risk Game';
      }
    },
  });

  static isolated = class Isolated extends Component<typeof this> {
    @tracked selectedFrom?: Territory;
    @tracked selectedTo?: Territory;

    get playerCount() {
      return this.args?.model?.players?.length ?? 0;
    }

    get currentPlayer(): Player | undefined {
      try {
        const idx = this.args?.model?.currentPlayerIndex ?? 0;
        return this.args?.model?.players?.[idx];
      } catch {
        return undefined;
      }
    }

    get canAttack() {
      return (this.args?.model?.phase ?? 'placement') === 'attack';
    }
    get canFortify() {
      return (this.args?.model?.phase ?? 'placement') === 'fortify';
    }

    // Helpers
    private rollDice = (count: number) => {
      const rolls = Array.from(
        { length: count },
        () => Math.floor(Math.random() * 6) + 1,
      );
      return rolls.sort((a, b) => b - a);
    };

    private resolveBattle = () => {
      const from = this.args.model?.pendingFrom;
      const to = this.args.model?.pendingTo;
      const attacker = from?.owner;
      const defender = to?.owner;

      if (!from || !to || !attacker || !defender) {
        this.args.model.lastRoll = 'Select valid territories.';
        return;
      }
      const attackDice = Math.min(3, Math.max(0, (from.armies ?? 0) - 1));
      const defendDice = Math.min(2, Math.max(1, (to.armies ?? 0) > 0 ? 1 : 0));

      if (attackDice < 1 || defendDice < 1) {
        this.args.model.lastRoll = 'Not enough armies to attack or defend.';
        return;
      }
      const aRolls = this.rollDice(attackDice);
      const dRolls = this.rollDice(defendDice);

      let aLoss = 0;
      let dLoss = 0;
      const pairs = Math.min(aRolls.length, dRolls.length);
      for (let i = 0; i < pairs; i++) {
        if (aRolls[i] > dRolls[i]) {
          dLoss++;
        } else {
          aLoss++;
        }
      }
      from.armies = Math.max(0, (from.armies ?? 0) - aLoss);
      to.armies = Math.max(0, (to.armies ?? 0) - dLoss);

      // Capture if defender reduced to 0
      if ((to.armies ?? 0) === 0 && (from.armies ?? 0) > 1) {
        to.owner = attacker;
        const moveIn = Math.min((from.armies ?? 2) - 1, attackDice); // move at least 1 up to dice count
        from.armies = (from.armies ?? 0) - moveIn;
        to.armies = moveIn;
        this.args.model.lastRoll = `A:${aRolls.join(',')} vs D:${dRolls.join(
          ',',
        )} → Captured! (moved ${moveIn})`;
      } else {
        this.args.model.lastRoll = `A:${aRolls.join(',')} vs D:${dRolls.join(
          ',',
        )} → Loss A:${aLoss} D:${dLoss}`;
      }
    };

    private endTurn = () => {
      const players = this.args.model?.players ?? [];
      if (!players.length) return;
      const next =
        ((this.args.model.currentPlayerIndex ?? 0) + 1) % players.length;
      this.args.model.currentPlayerIndex = next;
      this.args.model.phase = 'placement';
      this.args.model.pendingFrom = undefined as unknown as Territory;
      this.args.model.pendingTo = undefined as unknown as Territory;
      this.args.model.lastRoll = '';
      // Basic reinforcements: max(3, floor(owned/3)) + continent bonuses
      const me = players[next];
      const owned = (this.args.model.territories ?? []).filter(
        (t) => t?.owner?.id === me?.id,
      ).length;
      let reinf = Math.max(3, Math.floor((owned || 0) / 3));
      // Continent bonus: if player owns all territories in continent
      for (const c of this.args.model.continents ?? []) {
        const allOwned = (c?.territories ?? []).every(
          (tt: Territory) => tt?.owner?.id === me?.id,
        );
        if (allOwned) reinf += c?.bonusArmies ?? 0;
      }
      me.reserves = (me.reserves ?? 0) + reinf;
    };

    private placeArmy = (territory: Territory) => {
      const p = this.currentPlayer;
      if (!p) return;
      if ((p.reserves ?? 0) <= 0) return;
      if (territory?.owner?.id !== p.id && territory?.owner != null) return; // only your territories or unowned during initial
      territory.owner = p;
      territory.armies = (territory.armies ?? 0) + 1;
      p.reserves = (p.reserves ?? 0) - 1;
    };

    private stepPhase = () => {
      const phase = this.args.model?.phase ?? 'placement';
      if (phase === 'placement') this.args.model.phase = 'attack';
      else if (phase === 'attack') this.args.model.phase = 'fortify';
      else this.endTurn();
    };

    // Template actions
    selectFrom = (t: Territory) => {
      this.args.model.pendingFrom = t;
    };
    selectTo = (t: Territory) => {
      this.args.model.pendingTo = t;
    };
    attack = () => {
      if (this.canAttack) this.resolveBattle();
    };
    fortify = () => {
      const from = this.args.model?.pendingFrom;
      const to = this.args.model?.pendingTo;
      const me = this.currentPlayer;
      if (
        !from ||
        !to ||
        !me ||
        from.owner?.id !== me.id ||
        to.owner?.id !== me.id
      ) {
        this.args.model.lastRoll = 'Select your two territories.';
        return;
      }
      if ((from.armies ?? 0) <= 1) {
        this.args.model.lastRoll = 'Need >1 army to move.';
        return;
      }
      const move = Math.max(1, Math.floor(((from.armies ?? 0) - 1) / 2));
      from.armies = (from.armies ?? 0) - move;
      to.armies = (to.armies ?? 0) + move;
      this.args.model.lastRoll = `Fortified: moved ${move}`;
    };

    placeOn = (t: Territory) => {
      this.placeArmy(t);
    };

    <template>
      <div class='stage'>
        <article class='game-mat'>
          <header class='top'>
            <div class='title'>
              <h1>{{if @model.name @model.name 'Risk Game'}}</h1>
              <div class='subtitle'>
                Players:
                {{this.playerCount}}
                • Turn:
                {{if this.currentPlayer.name this.currentPlayer.name '—'}}
                • Phase:
                {{if @model.phase @model.phase 'placement'}}
              </div>
            </div>
            <div class='controls'>
              <Button class='btn' {{on 'click' this.stepPhase}}>
                {{#if (eq @model.phase 'placement')}}Done Placement → Attack{{else if
                  (eq @model.phase 'attack')
                }}Done Attacks → Fortify{{else}}End Turn → Next{{/if}}
              </Button>
              {{#if (eq @model.phase 'attack')}}
                <Button class='btn' {{on 'click' this.attack}}>Roll Attack</Button>
              {{/if}}
              {{#if (eq @model.phase 'fortify')}}
                <Button class='btn' {{on 'click' this.fortify}}>Fortify</Button>
              {{/if}}
            </div>
          </header>

          <section class='players'>
            {{#if (gt @model.players.length 0)}}
              <div class='players-list'>
                <@fields.players @format='embedded' />
              </div>
            {{/if}}
          </section>

          <section class='map'>
            {{#if (gt @model.territories.length 0)}}
              <div class='grid'>
                {{#each @model.territories as |t|}}
                  <div
                    class='tile
                      {{if (eq t.id @model.pendingFrom.id) "from"}}
                      {{if (eq t.id @model.pendingTo.id) "to"}}'
                    style={{concat '--owner: ' (or t.owner.color '#64748b')}}
                  >
                    <div class='name'>{{if t.shortId t.shortId t.name}}</div>
                    <div class='armies'>⛬ {{if t.armies t.armies 0}}</div>
                    <div class='owner'>{{if
                        t.owner.name
                        t.owner.name
                        '—'
                      }}</div>

                    <div class='actions'>
                      {{#if (eq @model.phase 'placement')}}
                        <Button
                          class='btn-sm'
                          {{on 'click' (fn this.placeOn t)}}
                        >Place</Button>
                      {{/if}}
                      <Button
                        class='btn-sm'
                        {{on 'click' (fn this.selectFrom t)}}
                      >From</Button>
                      <Button
                        class='btn-sm'
                        {{on 'click' (fn this.selectTo t)}}
                      >To</Button>
                    </div>
                  </div>
                {{/each}}
              </div>
            {{else}}
              <div class='empty'>No territories configured yet.</div>
            {{/if}}
          </section>

          <footer class='status'>
            <div class='last-roll'>{{if
                @model.lastRoll
                @model.lastRoll
                '—'
              }}</div>
          </footer>
        </article>
      </div>

      <style scoped>
        .stage {
          width: 100%;
          height: 100%;
          display: flex;
          justify-content: center;
          padding: 0.5rem;
        }
        .game-mat {
          max-width: 1100px;
          width: 100%;
          padding: 1rem;
          overflow-y: auto;
          max-height: 100%;
          font-size: 0.875rem;
        }
        .top {
          display: flex;
          justify-content: space-between;
          align-items: flex-start;
          gap: 1rem;
        }
        .title h1 {
          font-size: 1.125rem;
          margin-bottom: 0.25rem;
        }
        .subtitle {
          font-size: 0.75rem;
          opacity: 0.85;
        }
        .controls {
          display: flex;
          gap: 0.5rem;
          flex-wrap: wrap;
        }
        .btn,
        .btn-sm {
          padding: 0.375rem 0.75rem;
          font-size: 0.8125rem;
          display: inline-flex;
          align-items: center;
          gap: 0.25rem;
        }
        .btn-sm {
          padding: 0.25rem 0.5rem;
          font-size: 0.75rem;
        }
        .players-list > .containsMany-field {
          display: flex;
          gap: 0.5rem;
          flex-wrap: wrap;
        }
        .map {
          margin-top: 0.75rem;
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
          gap: 0.5rem;
        }
        .tile {
          border-left: 3px solid var(--owner, #64748b);
          padding: 0.5rem;
          display: flex;
          flex-direction: column;
          gap: 0.25rem;
        }
        .tile.from {
          outline: 2px dashed #2563eb;
        }
        .tile.to {
          outline: 2px dashed #16a34a;
        }
        .name {
          font-weight: 600;
        }
        .armies,
        .owner {
          font-size: 0.75rem;
          opacity: 0.85;
        }
        .actions {
          display: flex;
          gap: 0.25rem;
          flex-wrap: wrap;
          margin-top: 0.25rem;
        }
        .status {
          margin-top: 0.75rem;
          font-size: 0.8125rem;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof this> {
    <template>
      <div class='summary'>
        <h3>{{if @model.name @model.name 'Risk Game'}}</h3>
        <div class='row'>
          Players:
          {{@model.players.length}}
          • Territories:
          {{@model.territories.length}}
          • Phase:
          {{if @model.phase @model.phase 'placement'}}
        </div>
      </div>
      <style scoped>
        .summary {
          font-size: 0.8125rem;
        }
        .row {
          font-size: 0.75rem;
          opacity: 0.85;
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof this> {
    <template>
      <div class='fitted'>
        <div class='badge-format'>
          <div class='primary-text'>{{if
              @model.name
              @model.name
              'Risk Game'
            }}</div>
          <div class='tertiary-text'>P{{@model.players.length}}
            • T{{@model.territories.length}}
            •
            {{if @model.phase @model.phase 'placement'}}</div>
        </div>
      </div>
      <style scoped>
        .fitted {
          width: 100%;
          height: 100%;
          container-type: size;
        }
        .badge-format {
          display: none;
          padding: clamp(0.1875rem, 2%, 0.5rem);
        }
        @container (max-width: 399px) and (max-height: 169px) {
          .badge-format {
            display: flex;
            flex-direction: column;
            justify-content: space-between;
          }
        }
        .primary-text {
          font-size: 1em;
          font-weight: 600;
        }
        .tertiary-text {
          font-size: 0.75em;
          opacity: 0.85;
        }
      </style>
    </template>
  };

  // Additional formats or components
}
