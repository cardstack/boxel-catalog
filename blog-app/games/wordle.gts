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
import { eq } from '@cardstack/boxel-ui/helpers';

const WORDS = [
  'RIVER',
  'BREAD',
  'NIGHT',
  'LIGHT',
  'MUSIC',
  'PLANE',
  'OCEAN',
  'MOUNT',
  'FROST',
  'GRAPE',
  'BRICK',
  'CLOUD',
  'STONE',
  'FLAME',
  'EARTH',
  'FIELD',
  'HORSE',
  'MAPLE',
  'HOTEL',
  'METRO',
  'BLOCK',
  'PLAZA',
  'CRANE',
  'TOWER',
  'ALLEY',
];

type CellStatus = 'correct' | 'present' | 'absent' | 'empty';
type EvaluatedRow = { letter: string; status: CellStatus }[];

const MAX_GUESSES = 6;
const WORD_LENGTH = 5;

const pickWord = () => WORDS[Math.floor(Math.random() * WORDS.length)];

const evaluateGuess = (guess: string, target: string): EvaluatedRow => {
  const result: EvaluatedRow = Array.from(guess, (letter) => ({
    letter,
    status: 'absent' as CellStatus,
  }));
  const remaining: Record<string, number> = {};
  // First pass: mark greens, count remaining target letters.
  for (let i = 0; i < WORD_LENGTH; i++) {
    if (guess[i] === target[i]) {
      result[i].status = 'correct';
    } else {
      remaining[target[i]] = (remaining[target[i]] ?? 0) + 1;
    }
  }
  // Second pass: yellows for letters still available in target.
  for (let i = 0; i < WORD_LENGTH; i++) {
    if (result[i].status === 'correct') continue;
    const l = guess[i];
    if (remaining[l] > 0) {
      result[i].status = 'present';
      remaining[l]--;
    }
  }
  return result;
};

const emptyRow = (filled: string): EvaluatedRow => {
  const cells: EvaluatedRow = [];
  for (let i = 0; i < WORD_LENGTH; i++) {
    cells.push({
      letter: filled[i] ?? '',
      status: 'empty',
    });
  }
  return cells;
};

class WordleIsolated extends Component<typeof Wordle> {
  @tracked target: string = pickWord();
  @tracked rows: EvaluatedRow[] = [];
  @tracked currentGuess: string = '';
  @tracked status: 'playing' | 'won' | 'lost' = 'playing';
  @tracked errorMessage: string = '';

  get displayRows() {
    const out: { cells: EvaluatedRow; isCurrent: boolean }[] = [];
    for (const row of this.rows) {
      out.push({ cells: row, isCurrent: false });
    }
    if (this.status === 'playing') {
      out.push({ cells: emptyRow(this.currentGuess), isCurrent: true });
    }
    while (out.length < MAX_GUESSES) {
      out.push({ cells: emptyRow(''), isCurrent: false });
    }
    return out;
  }

  @action updateGuess(event: Event) {
    const raw = (event.target as HTMLInputElement).value;
    const cleaned = raw
      .toUpperCase()
      .replace(/[^A-Z]/g, '')
      .slice(0, WORD_LENGTH);
    this.currentGuess = cleaned;
    this.errorMessage = '';
    (event.target as HTMLInputElement).value = cleaned;
  }

  @action handleKeydown(event: Event) {
    const ev = event as KeyboardEvent;
    if (ev.key === 'Enter') {
      ev.preventDefault();
      this.submitGuess();
    }
  }

  @action submitGuess() {
    if (this.status !== 'playing') return;
    if (this.currentGuess.length !== WORD_LENGTH) {
      this.errorMessage = `Need ${WORD_LENGTH} letters`;
      return;
    }
    const evaluated = evaluateGuess(this.currentGuess, this.target);
    this.rows = [...this.rows, evaluated];
    if (this.currentGuess === this.target) {
      this.status = 'won';
    } else if (this.rows.length >= MAX_GUESSES) {
      this.status = 'lost';
    }
    this.currentGuess = '';
  }

  @action reset() {
    this.target = pickWord();
    this.rows = [];
    this.currentGuess = '';
    this.status = 'playing';
    this.errorMessage = '';
  }

  <template>
    <div class='wordle'>
      <h2 class='wordle-title'>Wordle</h2>
      <div class='wordle-status'>
        {{#if (eq this.status 'won')}}
          You got it!
        {{else if (eq this.status 'lost')}}
          The word was
          <strong>{{this.target}}</strong>.
        {{else if this.errorMessage}}
          {{this.errorMessage}}
        {{else}}
          Guess
          {{this.rows.length}}
          /
          {{MAX_GUESSES}}
        {{/if}}
      </div>
      <div class='wordle-board'>
        {{#each this.displayRows as |row|}}
          <div class='wordle-row'>
            {{#each row.cells as |cell|}}
              <div
                class='wordle-cell is-{{cell.status}}
                  {{if cell.letter "is-filled"}}'
              >
                {{cell.letter}}
              </div>
            {{/each}}
          </div>
        {{/each}}
      </div>
      {{#if (eq this.status 'playing')}}
        <div class='wordle-input-row'>
          <input
            type='text'
            class='wordle-input'
            placeholder='Type 5 letters'
            maxlength='5'
            autocomplete='off'
            spellcheck='false'
            value={{this.currentGuess}}
            {{on 'input' this.updateGuess}}
            {{on 'keydown' this.handleKeydown}}
          />
          <button
            type='button'
            class='wordle-submit'
            {{on 'click' this.submitGuess}}
          >Guess</button>
        </div>
      {{else}}
        <button type='button' class='wordle-reset' {{on 'click' this.reset}}>New
          Game</button>
      {{/if}}
    </div>
    <style scoped>
      .wordle {
        width: 100%;
        max-width: 360px;
        margin: 0 auto;
        padding: var(--boxel-sp-lg) var(--boxel-sp);
        background: #fafafa;
        border: 1px solid #ececec;
        border-radius: 16px;
        text-align: center;
        font-family: 'Inter', system-ui, sans-serif;
        box-sizing: border-box;
      }
      .wordle-title {
        font:
          800 1.5rem/1 'Inter',
          sans-serif;
        letter-spacing: -0.02em;
        margin: 0 0 6px;
        color: #121212;
      }
      .wordle-status {
        font:
          500 0.85rem/1.3 'Inter',
          sans-serif;
        color: #555;
        margin-bottom: 14px;
        min-height: 18px;
      }
      .wordle-status strong {
        font-weight: 800;
        color: #121212;
      }
      .wordle-board {
        display: grid;
        grid-template-rows: repeat(6, 1fr);
        gap: 6px;
        margin-bottom: 14px;
      }
      .wordle-row {
        display: grid;
        grid-template-columns: repeat(5, 1fr);
        gap: 6px;
      }
      .wordle-cell {
        aspect-ratio: 1;
        display: grid;
        place-items: center;
        font:
          800 1.4rem/1 'Inter',
          sans-serif;
        text-transform: uppercase;
        color: #1a1a1b;
        background: white;
        border: 2px solid #d3d6da;
        border-radius: 6px;
        transition:
          background-color 0.15s,
          border-color 0.15s,
          color 0.15s;
      }
      .wordle-cell.is-empty.is-filled {
        border-color: #878a8c;
      }
      .wordle-cell.is-correct {
        background: #6aaa64;
        border-color: #6aaa64;
        color: white;
      }
      .wordle-cell.is-present {
        background: #c9b458;
        border-color: #c9b458;
        color: white;
      }
      .wordle-cell.is-absent {
        background: #787c7e;
        border-color: #787c7e;
        color: white;
      }
      .wordle-input-row {
        display: flex;
        gap: 8px;
      }
      .wordle-input {
        flex: 1;
        padding: 8px 12px;
        border: 1px solid #d3d6da;
        border-radius: 8px;
        font:
          600 0.95rem/1 'Inter',
          sans-serif;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        outline: none;
        transition: border-color 0.15s;
      }
      .wordle-input:focus {
        border-color: #2c2c2c;
      }
      .wordle-submit,
      .wordle-reset {
        padding: 8px 18px;
        background: #2c2c2c;
        color: white;
        border: none;
        border-radius: 8px;
        cursor: pointer;
        font:
          600 12px/1 'Inter',
          sans-serif;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        transition:
          background-color 0.15s,
          transform 0.1s;
      }
      .wordle-reset {
        border-radius: 999px;
        padding: 9px 22px;
      }
      .wordle-submit:hover,
      .wordle-reset:hover {
        background: #1a1a1a;
      }
      .wordle-submit:active,
      .wordle-reset:active {
        transform: scale(0.96);
      }
    </style>
  </template>
}

class WordleFitted extends Component<typeof Wordle> {
  <template>
    <article class='wf'>
      <div class='wf-icon' aria-hidden='true'>
        <div class='wf-grid'>
          <span class='wf-tile wf-correct'>W</span>
          <span class='wf-tile wf-correct'>O</span>
          <span class='wf-tile wf-present'>R</span>
          <span class='wf-tile wf-absent'>D</span>
          <span class='wf-tile wf-present'>S</span>
          <span class='wf-tile wf-correct'>P</span>
          <span class='wf-tile wf-correct'>L</span>
          <span class='wf-tile wf-correct'>A</span>
          <span class='wf-tile wf-correct'>Y</span>
          <span class='wf-tile wf-correct'>!</span>
        </div>
      </div>
      <div class='wf-meta'>
        <h3 class='wf-title'>Wordle</h3>
        <p class='wf-sub'>5 letters, 6 tries</p>
        <span class='wf-tag'>Solo · 3 min</span>
      </div>
    </article>
    <style scoped>
      .wf {
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
      .wf-icon {
        width: 76px;
        height: 76px;
        display: grid;
        place-items: center;
        border-radius: 14px;
        background:
          radial-gradient(
            circle at 20% 10%,
            rgba(106, 170, 100, 0.08),
            transparent 60%
          ),
          #ffffff;
        box-shadow:
          inset 0 0 0 1px #e5e7eb,
          0 4px 10px rgba(0, 0, 0, 0.05);
        flex-shrink: 0;
      }
      .wf-grid {
        display: grid;
        grid-template-columns: repeat(5, 1fr);
        gap: 2px;
      }
      .wf-tile {
        width: 12px;
        height: 12px;
        display: grid;
        place-items: center;
        border-radius: 1.5px;
        font:
          800 0.45rem/1 'Inter',
          sans-serif;
        color: white;
        letter-spacing: 0.02em;
      }
      .wf-correct {
        background: #6aaa64;
      }
      .wf-present {
        background: #c9b458;
      }
      .wf-absent {
        background: #787c7e;
      }
      .wf-meta {
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 2px;
        overflow: hidden;
      }
      .wf-title {
        font:
          700 1rem/1.2 'Inter',
          sans-serif;
        letter-spacing: -0.01em;
        margin: 0;
        color: #121212;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .wf-sub {
        font:
          500 0.78rem/1.3 'Inter',
          sans-serif;
        color: #6b7280;
        margin: 2px 0 0;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .wf-tag {
        margin-top: 6px;
        align-self: flex-start;
        font:
          600 0.6rem/1 'Inter',
          sans-serif;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: #15803d;
        padding: 4px 8px;
        background: rgba(106, 170, 100, 0.14);
        border-radius: 999px;
        white-space: nowrap;
      }

      @container fitted-card ((aspect-ratio <= 1.0) and (height < 140px)) {
        .wf {
          grid-template-columns: 1fr;
          grid-template-rows: auto auto;
          justify-items: center;
          text-align: center;
          gap: 8px;
        }
        .wf-tag {
          display: none;
        }
        .wf-sub {
          display: none;
        }
      }

      @container fitted-card ((1.0 < aspect-ratio) and (height <= 60px)) {
        .wf {
          grid-template-columns: 40px 1fr;
          gap: 8px;
        }
        .wf-icon {
          width: 40px;
          height: 40px;
          border-radius: 8px;
        }
        .wf-tile {
          width: 6px;
          height: 6px;
          font-size: 0;
          border-radius: 1px;
        }
        .wf-grid {
          gap: 1px;
        }
        .wf-sub,
        .wf-tag {
          display: none;
        }
      }
    </style>
  </template>
}

export class Wordle extends Game {
  static displayName = 'Wordle';
  @field cardTitle = contains(StringField, {
    computeVia: function () {
      return 'Wordle';
    },
  });
  static isolated = WordleIsolated;
  // Embedded = the playable game (used in the BlogApp Games dock).
  // Fitted = the compact preview tile (used in admin grids etc.).
  static embedded = WordleIsolated;
  static fitted = WordleFitted;
}
