import {
  Component,
  field,
  contains,
} from 'https://cardstack.com/base/card-api';
import StringField from 'https://cardstack.com/base/string';
import { Game } from './game';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
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
    <div class='ttt'>
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
          <button
            type='button'
            class='ttt-cell
              {{if cell "is-filled"}}
              {{if (eq cell "X") "is-x"}}
              {{if (eq cell "O") "is-o"}}'
            disabled={{if (eq this.winner null) false true}}
            aria-label='Cell {{index}}'
            {{on 'click' (fn this.placeMark index)}}
          >
            {{cell}}
          </button>
        {{/each}}
      </div>
      <button type='button' class='ttt-reset' {{on 'click' this.reset}}>
        New Game
      </button>
    </div>
    <style scoped>
      .ttt {
        --ttt-bg: #fafafa;
        --ttt-text: #121212;
        --ttt-muted: #555;
        --ttt-cell-bg: #f0f0f0;
        --ttt-cell-border: #aaa;
        --ttt-x: #2563eb;
        --ttt-o: #dc2626;
        --ttt-key-bg: #2c2c2c;
        --ttt-key-bg-hover: #1a1a1a;
        --ttt-on-dark: #ffffff;
        --ttt-win-gold: #fde68a;
        --ttt-win-cyan: #a5f3fc;
        --ttt-muted-2: #6b7280;
        --ttt-accent: #6366f1;

        width: 100%;
        max-width: 360px;
        margin: 0 auto;
        padding: var(--boxel-sp-lg) var(--boxel-sp);
        background: var(--ttt-bg);
        border: 1px solid #ececec;
        border-radius: 16px;
        text-align: center;
        font-family: 'Inter', system-ui, sans-serif;
        box-sizing: border-box;
      }
      .ttt-title {
        font:
          800 1.5rem/1 'Inter',
          sans-serif;
        letter-spacing: -0.02em;
        margin: 0 0 8px;
        color: var(--ttt-text);
      }
      .ttt-status {
        font:
          500 0.9rem/1 'Inter',
          sans-serif;
        color: var(--ttt-muted);
        margin-bottom: 18px;
        height: 18px;
      }
      .ttt-status strong {
        font-weight: 800;
        color: var(--ttt-text);
      }
      .ttt-board {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 8px;
        margin-bottom: 18px;
      }
      .ttt-cell {
        aspect-ratio: 1;
        background: white;
        border: 2px solid #e5e7eb;
        border-radius: 12px;
        font:
          800 2.2rem/1 'Inter',
          sans-serif;
        cursor: pointer;
        transition:
          background-color 0.12s,
          border-color 0.12s,
          transform 0.1s;
        color: var(--ttt-text);
      }
      .ttt-cell:hover:not(.is-filled):not([disabled]) {
        background: var(--ttt-cell-bg);
        border-color: var(--ttt-cell-border);
      }
      .ttt-cell:active:not(.is-filled):not([disabled]) {
        transform: scale(0.96);
      }
      .ttt-cell.is-filled {
        cursor: default;
      }
      .ttt-cell.is-x {
        color: var(--ttt-x);
      }
      .ttt-cell.is-o {
        color: var(--ttt-o);
      }
      .ttt-reset {
        padding: 9px 22px;
        background: var(--ttt-key-bg);
        color: white;
        border: none;
        border-radius: 999px;
        cursor: pointer;
        font:
          600 12px/1 'Inter',
          sans-serif;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        transition:
          background-color 0.15s,
          transform 0.1s;
      }
      .ttt-reset:hover {
        background: var(--ttt-key-bg-hover);
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
        grid-template-columns: 76px 1fr;
        align-items: center;
        gap: 12px;
        padding: 4px;
        background: transparent;
        min-width: 0;
      }
      .ttt-fitted-icon {
        width: 76px;
        height: 76px;
        border-radius: 14px;
        display: grid;
        place-items: center;
        background:
          radial-gradient(
            circle at 20% 10%,
            rgba(255, 255, 255, 0.25),
            transparent 50%
          ),
          #4f46e5;
        box-shadow:
          inset 0 1px 0 rgba(255, 255, 255, 0.3),
          0 6px 14px rgba(79, 70, 229, 0.28);
        overflow: hidden;
        flex-shrink: 0;
      }
      .ttt-board {
        position: relative;
        width: 56px;
        height: 56px;
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        grid-template-rows: repeat(3, 1fr);
        gap: 2px;
        background: rgba(255, 255, 255, 0.32);
        padding: 2px;
        border-radius: 6px;
      }
      .ttt-cell {
        background: rgba(13, 13, 30, 0.55);
        display: grid;
        place-items: center;
        font:
          800 0.78rem/1 'Inter',
          system-ui,
          sans-serif;
        color: var(--ttt-on-dark);
        border-radius: 2px;
      }
      .ttt-x {
        color: var(--ttt-win-gold);
      }
      .ttt-o {
        color: var(--ttt-win-cyan);
      }
      .ttt-strike {
        position: absolute;
        top: 50%;
        left: -4px;
        right: -4px;
        height: 2px;
        background: var(--ttt-on-dark);
        transform: rotate(-45deg);
        transform-origin: center;
        border-radius: 2px;
        box-shadow: 0 0 6px rgba(255, 255, 255, 0.7);
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
        color: var(--ttt-text);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .ttt-fitted-sub {
        font:
          500 0.78rem/1.3 'Inter',
          system-ui,
          sans-serif;
        color: var(--ttt-muted-2);
        margin: 2px 0 0;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .ttt-fitted-tag {
        margin-top: 6px;
        align-self: flex-start;
        font:
          600 0.6rem/1 'Inter',
          system-ui,
          sans-serif;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--ttt-accent);
        padding: 4px 8px;
        background: rgba(99, 102, 241, 0.1);
        border-radius: 999px;
        white-space: nowrap;
      }

      @container fitted-card ((aspect-ratio <= 1.0) and (height < 140px)) {
        .ttt-fitted {
          grid-template-columns: 1fr;
          grid-template-rows: auto auto;
          justify-items: center;
          text-align: center;
          gap: 8px;
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
          grid-template-columns: 40px 1fr;
          gap: 8px;
        }
        .ttt-fitted-icon {
          width: 40px;
          height: 40px;
          border-radius: 8px;
        }
        .ttt-board {
          width: 28px;
          height: 28px;
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
