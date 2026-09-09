import { Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import { Game } from './game';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';

type Cell = 'X' | 'O' | null;

const WINS: number[][] = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];

class TicTacToeIsolated extends Component<typeof TicTacToe> {
  @tracked board: Cell[] = Array(9).fill(null);
  @tracked currentPlayer: 'X' | 'O' = 'X';
  @tracked winner: 'X' | 'O' | 'draw' | null = null;

  @action placeMark(index: number) {
    if (this.winner || this.board[index]) return;
    const next = [...this.board];
    next[index] = this.currentPlayer;
    this.board = next;
    const w = this.computeWinner(next);
    if (w) {
      this.winner = w;
    } else {
      this.currentPlayer = this.currentPlayer === 'X' ? 'O' : 'X';
    }
  }

  @action reset() {
    this.board = Array(9).fill(null);
    this.currentPlayer = 'X';
    this.winner = null;
  }

  private computeWinner(b: Cell[]): 'X' | 'O' | 'draw' | null {
    for (const line of WINS) {
      const [a, c, d] = line;
      if (b[a] && b[a] === b[c] && b[a] === b[d]) {
        return b[a] as 'X' | 'O';
      }
    }
    return b.every((cell) => cell !== null) ? 'draw' : null;
  }

  <template>
    <section class='ttt' aria-label='Tic Tac Toe'>
      <h2 class='ttt-title'>Tic Tac Toe</h2>
      <div class='ttt-status'>
        {{#if this.winner}}
          {{#if (eq this.winner 'draw')}}
            It's a draw.
          {{else}}
            <strong>{{this.winner}}</strong>
            wins!
          {{/if}}
        {{else}}
          <strong>{{this.currentPlayer}}</strong>'s turn
        {{/if}}
      </div>
      <div class='ttt-board'>
        {{#each this.board as |cell index|}}
          <Button
            @size='auto'
            @kind='text-only'
            class='ttt-cell
              {{if cell "is-filled"}}
              {{if (eq cell "X") "is-x"}}
              {{if (eq cell "O") "is-o"}}'
            @disabled={{if (eq this.winner null) false true}}
            aria-label='Cell {{index}}'
            {{on 'click' (fn this.placeMark index)}}
          >
            {{cell}}
          </Button>
        {{/each}}
      </div>
      <Button
        @kind='text-only'
        @size='auto'
        class='ttt-reset'
        {{on 'click' this.reset}}
      >
        New Game
      </Button>
    </section>
    <style scoped>
      .ttt {
        width: 100%;
        max-width: 22.5rem;
        margin: 0 auto;
        padding: var(--boxel-sp-lg) var(--boxel-sp);
        background-color: var(--card);
        color: var(--card-foreground);
        border: 1px solid var(--border);
        border-radius: 1rem;
        text-align: center;
        font-family: 'Inter', system-ui, sans-serif;
        box-sizing: border-box;
      }
      .ttt-title {
        font:
          800 1.5rem/1 'Inter',
          sans-serif;
        letter-spacing: -0.02em;
        margin: 0 0 0.5rem;
        color: var(--foreground);
      }
      .ttt-status {
        font:
          500 0.9rem/1 'Inter',
          sans-serif;
        color: var(--muted-foreground);
        margin-bottom: 1.125rem;
        height: 1.125rem;
      }
      .ttt-status strong {
        font-weight: 800;
        color: var(--foreground);
      }
      .ttt-board {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 0.5rem;
        margin-bottom: 1.125rem;
      }
      .ttt-cell {
        aspect-ratio: 1;
        background-color: var(--card);
        border: 2px solid var(--border);
        border-radius: 0.75rem;
        font:
          800 2.2rem/1 'Inter',
          sans-serif;
        cursor: pointer;
        transition:
          background-color 0.12s,
          border-color 0.12s,
          transform 0.1s;
        color: var(--foreground);
      }
      .ttt-cell:hover:not(.is-filled):not([disabled]) {
        background-color: var(--card);
        color: var(--card-foreground);
        border-color: var(--border);
      }
      .ttt-cell:active:not(.is-filled):not([disabled]) {
        transform: scale(0.96);
      }
      .ttt-cell.is-filled {
        cursor: default;
      }
      .ttt-cell.is-x {
        color: var(--primary-ink);
      }
      .ttt-cell.is-o {
        color: var(--destructive-ink);
      }
      .ttt-reset {
        padding: 0.5625rem 1.375rem;
        background-color: var(--card);
        color: var(--card-foreground);
        border: none;
        border-radius: 62.4375rem;
        cursor: pointer;
        font:
          600 0.75rem/1 'Inter',
          sans-serif;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        transition:
          background-color 0.15s,
          transform 0.1s;
      }
      .ttt-reset:hover {
        background-color: var(--card);
        color: var(--card-foreground);
      }
      .ttt-reset:active {
        transform: scale(0.96);
      }
    </style>
  </template>
}

class TicTacToeFitted extends Component<typeof TicTacToe> {
  <template>
    <article class='ttt-fitted'>
      <div class='ttt-fitted-icon' aria-hidden='true'>
        <div class='ttt-board'>
          <span class='ttt-cell ttt-x'>X</span>
          <span class='ttt-cell'></span>
          <span class='ttt-cell ttt-o'>O</span>
          <span class='ttt-cell'></span>
          <span class='ttt-cell ttt-x'>X</span>
          <span class='ttt-cell'></span>
          <span class='ttt-cell ttt-o'>O</span>
          <span class='ttt-cell'></span>
          <span class='ttt-cell ttt-x'>X</span>
          <span class='ttt-strike' aria-hidden='true'></span>
        </div>
      </div>
      <div class='ttt-fitted-meta'>
        <h3 class='ttt-fitted-title'>Tic Tac Toe</h3>
        <p class='ttt-fitted-sub'>Quick round, 1 vs 1</p>
        <span class='ttt-fitted-tag'>2-player</span>
      </div>
    </article>
    <style scoped>
      .ttt-fitted {
        width: 100%;
        height: 100%;
        display: grid;
        grid-template-columns: 4.75rem 1fr;
        align-items: center;
        gap: 0.75rem;
        padding: 0.25rem;
        background-color: transparent;
        min-width: 0;
      }
      .ttt-fitted-icon {
        width: 4.75rem;
        height: 4.75rem;
        border-radius: 0.875rem;
        display: grid;
        place-items: center;
        background:
          radial-gradient(
            circle at 20% 10%,
            color-mix(in oklch, var(--card) 25%, transparent),
            transparent 50%
          ),
          var(--primary);
        box-shadow:
          inset 0 1px 0 color-mix(in oklch, var(--card) 30%, transparent),
          0 6px 14px color-mix(in oklch, var(--primary) 28%, transparent);
        overflow: hidden;
        flex-shrink: 0;
      }
      .ttt-board {
        position: relative;
        width: 3.5rem;
        height: 3.5rem;
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        grid-template-rows: repeat(3, 1fr);
        gap: 2px;
        background-color: color-mix(in oklch, var(--card) 32%, transparent);
        padding: 2px;
        border-radius: 0.375rem;
      }
      .ttt-cell {
        background-color: color-mix(in oklch, var(--card) 55%, transparent);
        display: grid;
        place-items: center;
        font:
          800 0.78rem/1 'Inter',
          system-ui,
          sans-serif;
        color: var(--card-foreground);
        border-radius: 2px;
      }
      .ttt-x {
        color: var(--warning-ink);
      }
      .ttt-o {
        color: var(--info-ink);
      }
      .ttt-strike {
        position: absolute;
        top: 50%;
        left: -0.25rem;
        right: -0.25rem;
        height: 2px;
        background-color: var(--card);
        color: var(--card-foreground);
        transform: rotate(-45deg);
        transform-origin: center;
        border-radius: 2px;
        box-shadow: 0 0 6px color-mix(in oklch, var(--card) 70%, transparent);
      }
      .ttt-fitted-meta {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
        overflow: hidden;
      }
      .ttt-fitted-title {
        font:
          700 1rem/1.2 'Inter',
          system-ui,
          sans-serif;
        letter-spacing: -0.01em;
        margin: 0;
        color: var(--foreground);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .ttt-fitted-sub {
        font:
          500 0.78rem/1.3 'Inter',
          system-ui,
          sans-serif;
        color: var(--muted-foreground);
        margin: 2px 0 0;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .ttt-fitted-tag {
        margin-top: 0.375rem;
        align-self: flex-start;
        font:
          600 0.6rem/1 'Inter',
          system-ui,
          sans-serif;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--primary-ink);
        padding: 0.25rem 0.5rem;
        background-color: color-mix(in oklch, var(--primary) 10%, transparent);
        border-radius: 62.4375rem;
        white-space: nowrap;
      }

      @container fitted-card ((aspect-ratio <= 1.0) and (height < 140px)) {
        .ttt-fitted {
          grid-template-columns: 1fr;
          grid-template-rows: auto auto;
          justify-items: center;
          text-align: center;
          gap: 0.5rem;
        }
        .ttt-fitted-tag {
          display: none;
        }
        .ttt-fitted-sub {
          display: none;
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (height <= 60px)) {
        .ttt-fitted {
          grid-template-columns: 2.5rem 1fr;
          gap: 0.5rem;
        }
        .ttt-fitted-icon {
          width: 2.5rem;
          height: 2.5rem;
          border-radius: 0.5rem;
        }
        .ttt-board {
          width: 1.75rem;
          height: 1.75rem;
          gap: 1px;
        }
        .ttt-cell {
          font-size: 0.55rem;
        }
        .ttt-fitted-sub,
        .ttt-fitted-tag {
          display: none;
        }
      }
    </style>
  </template>
}

export class TicTacToe extends Game {
  static displayName = 'Tic Tac Toe';
  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'Tic Tac Toe';
    },
  });
  static isolated = TicTacToeIsolated;
  // Embedded = the playable game (used in the BlogApp Games dock).
  // Fitted = the compact preview tile (used in admin grids etc.).
  static embedded = TicTacToeIsolated;
  static fitted = TicTacToeFitted;
}
