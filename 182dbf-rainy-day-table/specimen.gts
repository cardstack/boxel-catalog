// Every part in the toolbox at each depth (0 flat print → 3 full faux-3D),
// drawn from definitions alone with default looks.

import { CardDef, Component, field, contains } from '@cardstack/base/card-api';
import StringField from '@cardstack/base/string';
import PuzzleIcon from '@cardstack/boxel-icons/puzzle';
import type { CompDef } from './engine';
import { Part } from './parts';

const ROWS: {
  label: string;
  def: CompDef;
  faceUp?: boolean;
  face?: number;
  colour?: string;
}[] = [
  {
    label: 'Card',
    def: {
      id: 'QH',
      kind: 'card',
      name: 'Queen of hearts',
      rank: 'Q',
      suit: 'H',
    },
  },
  {
    label: 'Card (back)',
    def: {
      id: '7S',
      kind: 'card',
      name: 'Seven of spades',
      rank: '7',
      suit: 'S',
    },
    faceUp: false,
  },
  { label: 'Die', def: { id: 'd6', kind: 'die', name: 'Die' }, face: 4 },
  {
    label: 'Die (labels)',
    def: {
      id: 'dx',
      kind: 'die',
      name: 'Symbol die',
      faces: [{ label: '★' }, { label: '☾' }, { label: '☀' }],
      look: { fill: '#2f5d8a', ink: '#fff6dc' },
    },
    face: 0,
  },
  {
    label: 'Chip',
    def: {
      id: 'c25',
      kind: 'chip',
      name: 'Chip',
      value: 25,
      look: { fill: '#2f7a4f' },
    },
  },
  {
    label: 'Coin',
    def: { id: 'coin', kind: 'coin', name: 'Coin', look: { fill: '#c9a24a' } },
    face: 0,
  },
  {
    label: 'Token',
    def: {
      id: 'meeple',
      kind: 'token',
      name: 'Meeple',
      look: { shape: 'meeple' },
    },
    colour: '#c8553d',
  },
  {
    label: 'Token (pawn)',
    def: { id: 'pawn', kind: 'token', name: 'Pawn', look: { shape: 'pawn' } },
    colour: '#3f6f9f',
  },
  {
    label: 'Piece',
    def: {
      id: 'wN',
      kind: 'piece',
      name: 'White knight',
      rank: 'N',
      look: { fill: '#f4ead7', edge: '#8a7350' },
    },
  },
  {
    label: 'Piece',
    def: {
      id: 'bQ',
      kind: 'piece',
      name: 'Black queen',
      rank: 'Q',
      look: { fill: '#2b2420', edge: '#0d0a08' },
    },
  },
  {
    label: 'Tile (hex)',
    def: {
      id: 'hex',
      kind: 'tile',
      name: 'Hex tile',
      faces: [{ label: '6' }],
      look: { shape: 'hex', fill: '#d9b96a', ink: '#4a3b2a' },
    },
  },
  {
    label: 'Tile',
    def: {
      id: 'sq',
      kind: 'tile',
      name: 'Letter tile',
      faces: [{ label: 'R' }],
      look: { fill: '#efe2c6' },
    },
  },
];
const DEPTHS = [0, 1, 2, 3];

function withDepth(d: CompDef, depth: number): CompDef {
  return { ...d, look: { ...(d.look ?? {}), depth } };
}
function backFor(depth: number) {
  return { backPattern: 'lattice', backColour: '#8c2f39', depth };
}

class SpecimenIsolated extends Component<typeof PartsSpecimen> {
  get rows() {
    return ROWS.map((r) => ({
      ...r,
      cells: DEPTHS.map((depth) => ({
        depth,
        def: withDepth(r.def, depth),
        back: backFor(depth),
      })),
    }));
  }
  <template>
    <article class='spec'>
      <header>
        <p class='eyebrow'>Rainy Day Table · toolbox</p>
        <h1>{{if @model.title @model.title 'Parts specimen'}}</h1>
        <p class='sub'>Every part, drawn from its definition alone. Columns step
          <code>look.depth</code>
          from 0 (flat print) to 3 (side thickness, a lit edge and a grounded
          shadow), all lit from the top left.</p>
      </header>
      <div class='grid' role='table' aria-label='Parts by depth'>
        <div class='row head' role='row'>
          <span role='columnheader'></span>
          {{#each DEPTHS as |d|}}<span role='columnheader'>depth
              {{d}}</span>{{/each}}
        </div>
        {{#each this.rows as |r|}}
          <div class='row' role='row'>
            <span class='lbl' role='rowheader'>{{r.label}}</span>
            {{#each r.cells as |c|}}
              <span class='cell k-{{r.def.kind}}' role='cell'>
                <span class='part'><Part
                    @def={{c.def}}
                    @cardLook={{c.back}}
                    @faceUp={{r.faceUp}}
                    @face={{r.face}}
                    @colour={{r.colour}}
                  /></span>
              </span>
            {{/each}}
          </div>
        {{/each}}
      </div>
    </article>
    <style scoped>
      .spec {
        min-height: 100%;
        background: #f4ecdd;
        color: #2b231b;
        padding: 2rem clamp(1rem, 4cqw, 3rem) 3rem;
        font-family: ui-rounded, 'SF Pro Rounded', system-ui, sans-serif;
        container-type: inline-size;
      }
      .eyebrow {
        margin: 0;
        font-size: 0.75rem;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: #8a7355;
      }
      h1 {
        margin: 0.2rem 0 0;
        font:
          700 2.4rem/1.05 'Iowan Old Style',
          Palatino,
          Georgia,
          serif;
      }
      .sub {
        max-width: 40rem;
        line-height: 1.5;
        color: #5e4c37;
      }
      .grid {
        margin-top: 1.5rem;
        display: grid;
        gap: 0.4rem;
      }
      .row {
        display: grid;
        grid-template-columns: 8rem repeat(4, 1fr);
        align-items: center;
        gap: 0.5rem;
        padding: 0.5rem 0;
        border-bottom: 1px solid #e4d6bb;
      }
      .head span {
        font-size: 0.78rem;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: #8a7355;
        text-align: center;
      }
      .lbl {
        font-weight: 650;
        color: #4b3a26;
      }
      .cell {
        display: grid;
        place-items: center;
        min-height: 5rem;
        background: #2f6b4f;
        border-radius: 0.6rem;
        padding: 0.6rem;
        box-shadow: inset 0 2px 8px rgba(0, 0, 0, 0.25);
      }
      .part {
        width: 3.6rem;
      }
      .k-card .part {
        width: 3.2rem;
      }
      .k-chip .part,
      .k-coin .part {
        width: 3.4rem;
      }
      @container (width < 560px) {
        .row {
          grid-template-columns: 4.5rem repeat(4, 1fr);
        }
        .part,
        .k-card .part {
          width: 2.2rem;
        }
        .cell {
          min-height: 3.5rem;
          padding: 0.3rem;
        }
      }
    </style>
  </template>
}

export class PartsSpecimen extends CardDef {
  static displayName = 'Parts Specimen';
  static icon = PuzzleIcon;
  @field title = contains(StringField);
  @field cardTitle = contains(StringField, {
    computeVia: function (this: PartsSpecimen) {
      return this.title ?? 'Parts specimen';
    },
  });
  static isolated = SpecimenIsolated;
  static fitted = class Fitted extends Component<typeof this> {
    get sample() {
      return [ROWS[0], ROWS[2], ROWS[4], ROWS[6], ROWS[8]].map((r) => ({
        ...r,
        def: withDepth(r.def, 3),
      }));
    }
    <template>
      <div class='f'>
        <b>{{if @model.title @model.title 'Parts specimen'}}</b>
        <div class='row'>
          {{#each this.sample as |r|}}<span class='p'><Part
                @def={{r.def}}
                @cardLook={{backFor 3}}
                @face={{r.face}}
                @colour={{r.colour}}
              /></span>{{/each}}
        </div>
      </div>
      <style scoped>
        .f {
          height: 100%;
          display: flex;
          flex-direction: column;
          justify-content: space-between;
          padding: 0.7rem 0.8rem;
          background: #2f6b4f;
          color: #fff8ea;
          font-family: ui-rounded, system-ui, sans-serif;
          box-sizing: border-box;
        }
        b {
          font:
            700 1rem 'Iowan Old Style',
            Georgia,
            serif;
        }
        .row {
          display: flex;
          gap: 0.35rem;
          align-items: flex-end;
        }
        .p {
          flex: 1;
          max-width: 2.6rem;
        }
      </style>
    </template>
  };
}
