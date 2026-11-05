// The toolbox: every traditional tabletop part, drawn from a definition plus
// a copy's state. One light source (top-left) for everything: a darker side
// offset down-right gives thickness, a thin light edge up-left catches the
// light, and a soft drop shadow grounds it. Look.depth 0–3 scales all three;
// depth 0 is flat print.

import GlimmerComponent from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { CompDef, Face, Look } from './engine';

// ─── colour helpers ───────────────────────────────────────────────────────
function hexToRgb(h: string) {
  let s = h.replace('#', '');
  if (s.length === 3)
    s = s
      .split('')
      .map((c) => c + c)
      .join('');
  let n = parseInt(s, 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
export function shade(h: string | undefined, amt: number) {
  if (!h || !h.startsWith('#')) return h ?? '#888';
  let [r, g, b] = hexToRgb(h);
  let f = (c: number) =>
    Math.max(
      0,
      Math.min(255, Math.round(amt < 0 ? c * (1 + amt) : c + (255 - c) * amt)),
    );
  return `rgb(${f(r)}, ${f(g)}, ${f(b)})`;
}
const depthOf = (look?: Look, fallback = 2) =>
  Math.max(0, Math.min(3, look?.depth ?? fallback));
const circlePath = (cx: number, cy: number, r: number) =>
  `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0z`;
const shadowCss = (d: number) =>
  d === 0
    ? 'none'
    : `drop-shadow(${d * 0.6}px ${d * 1.1}px ${d * 1.4}px rgba(20, 12, 6, ${0.18 + d * 0.07}))`;

// ─── Playing card ─────────────────────────────────────────────────────────
const SUIT: Record<string, { sym: string; red: boolean }> = {
  S: { sym: '♠︎', red: false },
  H: { sym: '♥︎', red: true },
  D: { sym: '♦︎', red: true },
  C: { sym: '♣︎', red: false },
};
const L = 17;
const M = 30;
const R = 43;
const PIPS: Record<string, [number, number][]> = {
  '2': [
    [M, 16],
    [M, 68],
  ],
  '3': [
    [M, 16],
    [M, 42],
    [M, 68],
  ],
  '4': [
    [L, 16],
    [R, 16],
    [L, 68],
    [R, 68],
  ],
  '5': [
    [L, 16],
    [R, 16],
    [M, 42],
    [L, 68],
    [R, 68],
  ],
  '6': [
    [L, 16],
    [R, 16],
    [L, 42],
    [R, 42],
    [L, 68],
    [R, 68],
  ],
  '7': [
    [L, 16],
    [R, 16],
    [M, 29],
    [L, 42],
    [R, 42],
    [L, 68],
    [R, 68],
  ],
  '8': [
    [L, 16],
    [R, 16],
    [M, 29],
    [L, 42],
    [R, 42],
    [M, 55],
    [L, 68],
    [R, 68],
  ],
  '9': [
    [L, 16],
    [R, 16],
    [L, 33],
    [R, 33],
    [M, 42],
    [L, 51],
    [R, 51],
    [L, 68],
    [R, 68],
  ],
  '10': [
    [L, 16],
    [R, 16],
    [M, 25],
    [L, 33],
    [R, 33],
    [L, 51],
    [R, 51],
    [M, 59],
    [L, 68],
    [R, 68],
  ],
};

interface CardSig {
  Args: { def?: CompDef; faceUp: boolean; back?: Look; look?: Look };
}
export class PlayingCard extends GlimmerComponent<CardSig> {
  get suit() {
    return (
      SUIT[this.args.def?.suit ?? ''] ?? {
        sym: this.args.def?.suit ?? '',
        red: false,
      }
    );
  }
  get rank() {
    return this.args.def?.rank ?? this.args.def?.name ?? '';
  }
  get pips() {
    return (PIPS[this.rank] ?? []).map(([x, y]) => ({ x, y, flip: y > 42 }));
  }
  get isAce() {
    return this.rank === 'A';
  }
  get isCourt() {
    return ['J', 'Q', 'K'].includes(this.rank);
  }
  get image() {
    return this.args.look?.imageUrl ?? this.args.def?.look?.imageUrl;
  }
  get depth() {
    return depthOf(this.args.back ?? this.args.look, 2);
  }
  get style() {
    let back = this.args.back ?? {};
    let bc = back.backColour ?? '#8c2f39';
    let pattern = back.backPattern ?? 'lattice';
    let bg =
      pattern === 'plain'
        ? bc
        : pattern === 'stripes'
          ? `repeating-linear-gradient(45deg, ${bc} 0 6%, ${shade(bc, 0.14)} 6% 9%)`
          : pattern === 'dots'
            ? `radial-gradient(circle at 50% 50%, ${shade(bc, 0.22)} 18%, transparent 20%) 0 0 / 14% 10%, ${bc}`
            : `repeating-linear-gradient(45deg, transparent 0 7%, ${shade(bc, 0.2)} 7% 8.5%), repeating-linear-gradient(-45deg, transparent 0 7%, ${shade(bc, 0.2)} 7% 8.5%), ${bc}`;
    return htmlSafe(
      `--back:${bg}; --face:${this.args.look?.fill ?? this.args.def?.look?.fill ?? '#fbf7ee'}; filter:${shadowCss(this.depth)}`,
    );
  }
  <template>
    <div class='pc {{if @faceUp "is-up"}}' style={{this.style}}>
      <div class='pc-inner'>
        <div class='pc-face pc-front {{if this.suit.red "red"}}'>
          {{#if @def}}
            {{#if this.image}}
              <img class='art' src={{this.image}} alt='' />
            {{/if}}
            <span class='idx tl'><b>{{this.rank}}</b><i>{{this.suit.sym}}</i></span>
            <span class='idx br'><b>{{this.rank}}</b><i>{{this.suit.sym}}</i></span>
            <svg class='pips' viewBox='0 0 60 84' aria-hidden='true'>
              {{#if this.isAce}}
                <text x='30' y='42' class='ace'>{{this.suit.sym}}</text>
              {{else if this.isCourt}}
                <rect
                  x='11'
                  y='11'
                  width='38'
                  height='62'
                  rx='3'
                  class='frame'
                />
                <text x='30' y='40' class='court'>{{this.rank}}</text>
                <text x='30' y='58' class='court-suit'>{{this.suit.sym}}</text>
              {{else}}
                {{#each this.pips as |p|}}
                  <text
                    x={{p.x}}
                    y={{p.y}}
                    class='pip {{if p.flip "flip"}}'
                  >{{this.suit.sym}}</text>
                {{/each}}
              {{/if}}
            </svg>
          {{/if}}
        </div>
        <div class='pc-face pc-back'><span class='back-inset'></span></div>
      </div>
    </div>
    <style scoped>
      .pc {
        width: 100%;
        aspect-ratio: 5 / 7;
        perspective: 600px;
        container-type: inline-size;
      }
      .pc-inner {
        position: relative;
        width: 100%;
        height: 100%;
        transform-style: preserve-3d;
        transition: transform 300ms ease-in-out;
        transform: rotateY(180deg);
      }
      .pc.is-up .pc-inner {
        transform: rotateY(0deg);
      }
      .pc-face {
        position: absolute;
        inset: 0;
        border-radius: 7cqw;
        backface-visibility: hidden;
        overflow: hidden;
        box-shadow:
          inset 0 0 0 0.8cqw rgba(0, 0, 0, 0.1),
          inset 1cqw 1cqw 0 rgba(255, 255, 255, 0.5);
      }
      .pc-front {
        background: var(--face);
        color: #1d1a17;
      }
      .pc-front.red {
        color: #b3262e;
      }
      .pc-back {
        transform: rotateY(180deg);
        background: var(--back);
        border: 4cqw solid #fbf7ee;
      }
      .back-inset {
        position: absolute;
        inset: 3cqw;
        border: 1.2cqw solid rgba(255, 255, 255, 0.35);
        border-radius: 3cqw;
      }
      .art {
        position: absolute;
        inset: 12% 10%;
        width: 80%;
        height: 76%;
        object-fit: cover;
        border-radius: 3cqw;
      }
      .idx {
        position: absolute;
        display: flex;
        flex-direction: column;
        align-items: center;
        line-height: 0.9;
        font-family:
          'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif;
      }
      .idx b {
        font-size: 19cqw;
        font-weight: 700;
        letter-spacing: -0.06em;
      }
      .idx i {
        font-style: normal;
        font-size: 15cqw;
      }
      .tl {
        top: 4cqw;
        left: 5cqw;
      }
      .br {
        bottom: 4cqw;
        right: 5cqw;
        transform: rotate(180deg);
      }
      .pips {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        fill: currentColor;
        font-family: 'Iowan Old Style', Georgia, serif;
      }
      .pip {
        font-size: 13px;
        text-anchor: middle;
        dominant-baseline: central;
      }
      .pip.flip {
        transform-box: fill-box;
        transform-origin: center;
        transform: rotate(180deg);
      }
      .ace {
        font-size: 30px;
        text-anchor: middle;
        dominant-baseline: central;
      }
      .frame {
        fill: none;
        stroke: currentColor;
        stroke-opacity: 0.35;
        stroke-width: 0.8;
      }
      .court {
        font-size: 24px;
        font-weight: 700;
        text-anchor: middle;
        dominant-baseline: central;
      }
      .court-suit {
        font-size: 13px;
        text-anchor: middle;
        dominant-baseline: central;
      }
    </style>
  </template>
}

// ─── Die ──────────────────────────────────────────────────────────────────
const DIE_PIPS: Record<number, [number, number][]> = {
  1: [[46, 44]],
  2: [
    [30, 28],
    [62, 60],
  ],
  3: [
    [30, 28],
    [46, 44],
    [62, 60],
  ],
  4: [
    [30, 28],
    [62, 28],
    [30, 60],
    [62, 60],
  ],
  5: [
    [30, 28],
    [62, 28],
    [46, 44],
    [30, 60],
    [62, 60],
  ],
  6: [
    [30, 26],
    [62, 26],
    [30, 44],
    [62, 44],
    [30, 62],
    [62, 62],
  ],
};
interface DieSig {
  Args: { def?: CompDef; face?: number };
}
export class Die extends GlimmerComponent<DieSig> {
  get look() {
    return this.args.def?.look ?? {};
  }
  get d() {
    return depthOf(this.look, 3);
  }
  get faces() {
    let fs: Face[] = this.args.def?.faces?.length
      ? this.args.def.faces
      : [1, 2, 3, 4, 5, 6].map((v) => ({ value: v }));
    return fs.map((f, i) => {
      let pips =
        !f.label && f.value && f.value >= 1 && f.value <= 6
          ? DIE_PIPS[f.value]
          : null;
      return {
        i,
        pips,
        label: f.label ?? (pips ? '' : String(f.value ?? i + 1)),
      };
    });
  }
  get fill() {
    return this.look.fill ?? '#fffdf7';
  }
  get side() {
    return shade(this.fill, -0.24);
  }
  get ink() {
    return this.look.ink ?? '#2a2420';
  }
  get off() {
    return this.d * 2.6;
  }
  get style() {
    return htmlSafe(`filter:${shadowCss(this.d)}`);
  }
  <template>
    <svg
      class='die'
      viewBox='0 0 100 100'
      data-show={{if @face @face 0}}
      style={{this.style}}
      aria-label='die'
    >
      <rect
        x={{this.off}}
        y={{this.off}}
        width='84'
        height='84'
        rx='17'
        fill={{this.side}}
        transform='translate(4 4)'
      />
      <rect x='4' y='4' width='84' height='84' rx='17' fill={{this.fill}} />
      <path
        d='M14 8 h62 a14 14 0 0 1 10 4'
        fill='none'
        stroke='white'
        stroke-opacity='.8'
        stroke-width='3'
        stroke-linecap='round'
      />
      {{#each this.faces as |f|}}
        <g class='f f{{f.i}}' fill={{this.ink}}>
          {{#if f.pips}}
            {{#each f.pips as |p|}}
              <circle cx={{get p "0"}} cy={{get p "1"}} r='7.5' />
            {{/each}}
          {{else}}
            <text x='46' y='47' class='lbl'>{{f.label}}</text>
          {{/if}}
        </g>
      {{/each}}
    </svg>
    <style scoped>
      .die {
        width: 100%;
        display: block;
        overflow: visible;
      }
      .f {
        display: none;
      }
      .die[data-show='0'] .f0,
      .die[data-show='1'] .f1,
      .die[data-show='2'] .f2,
      .die[data-show='3'] .f3,
      .die[data-show='4'] .f4,
      .die[data-show='5'] .f5,
      .die[data-show='6'] .f6,
      .die[data-show='7'] .f7,
      .die[data-show='8'] .f8,
      .die[data-show='9'] .f9,
      .die[data-show='10'] .f10,
      .die[data-show='11'] .f11 {
        display: inline;
      }
      .lbl {
        font:
          700 34px ui-rounded,
          'SF Pro Rounded',
          system-ui,
          sans-serif;
        text-anchor: middle;
        dominant-baseline: central;
      }
    </style>
  </template>
}

// ─── Chip and coin ────────────────────────────────────────────────────────
interface ChipSig {
  Args: {
    colour?: string;
    value?: number | string;
    depth?: number;
    coin?: boolean;
    face?: string;
  };
}
export class Chip extends GlimmerComponent<ChipSig> {
  get c() {
    return this.args.colour ?? (this.args.coin ? '#c9a24a' : '#2f5d8a');
  }
  get side() {
    return shade(this.c, -0.35);
  }
  get rim() {
    return this.args.coin ? shade(this.c, 0.35) : '#f4efe4';
  }
  get thick() {
    return (this.args.depth ?? 2) * 3 + 2;
  }
  get bottomY() {
    return 34 + this.thick;
  }
  get sidePath() {
    return `M6 34 v${this.thick} a44 20 0 0 0 88 0 v${-this.thick}z`;
  }
  get inkColour() {
    return this.args.coin
      ? shade(this.c, -0.45)
      : this.c === '#ece4d4'
        ? '#5a4c3a'
        : '#fff';
  }
  <template>
    <svg class='chip' viewBox='0 0 100 {{this.svgH}}' aria-hidden='true'>
      <path d={{this.sidePath}} fill={{this.side}} />
      {{#unless @coin}}
        <path
          d={{this.sidePath}}
          fill='none'
          stroke={{this.rim}}
          stroke-width='3'
          stroke-dasharray='5 9'
          opacity='.8'
        />
      {{/unless}}
      <ellipse cx='50' cy='34' rx='44' ry='20' fill={{this.c}} />
      <ellipse
        cx='50'
        cy='34'
        rx='38'
        ry='16.5'
        fill='none'
        stroke={{this.rim}}
        stroke-width={{if @coin '1.5' '5'}}
        stroke-dasharray={{if @coin '' '7 7'}}
      />
      <ellipse
        cx='50'
        cy='34'
        rx='26'
        ry='11'
        fill={{if @coin (shade this.c 0.12) this.rim}}
        opacity={{if @coin '1' '.9'}}
      />
      {{#if @value}}
        <text
          x='50'
          y='35'
          class='v'
          fill={{if
            @coin
            this.inkColour
            (if (eq this.c '#ece4d4') '#5a4c3a' this.c)
          }}
        >{{@value}}</text>
      {{/if}}
      {{#if @face}}
        <text x='50' y='35' class='v' fill={{this.inkColour}}>{{@face}}</text>
      {{/if}}
      <path
        d='M14 27 a40 17 0 0 1 30 -11'
        fill='none'
        stroke='white'
        stroke-opacity='.55'
        stroke-width='2.5'
        stroke-linecap='round'
      />
    </svg>
    <style scoped>
      .chip {
        width: 100%;
        display: block;
        overflow: visible;
        filter: drop-shadow(1px 2px 1.5px rgba(20, 12, 6, 0.35));
      }
      .v {
        font:
          800 15px ui-rounded,
          'SF Pro Rounded',
          system-ui,
          sans-serif;
        text-anchor: middle;
        dominant-baseline: central;
      }
    </style>
  </template>
  get svgH() {
    return 34 + this.thick + 22;
  }
}

// ─── Token (meeple, pawn, disc) ───────────────────────────────────────────
const MEEPLE =
  'M50 8c10 0 17 7 17 16c0 6-3 10-6 13l22 9c6 3 8 8 4 13c-3 3-8 3-13 1l-6-2l12 26c2 5 0 9-6 9h-14l-10-18l-10 18h-14c-6 0-8-4-6-9l12-26l-6 2c-5 2-10 2-13-1c-4-5-2-10 4-13l22-9c-3-3-6-7-6-13c0-9 7-16 17-16z';
const PAWN_TOKEN = `${circlePath(50, 24, 14)}M36 42h28c0 10 6 22 14 40c2 6-1 10-8 10h-40c-7 0-10-4-8-10c8-18 14-30 14-40z`;
const DISC = circlePath(50, 52, 38);

interface ShapeSig {
  Args: {
    paths: string[];
    fill: string;
    edge?: string;
    depth?: number;
    marks?: string[];
    markFill?: string;
  };
}
// Three layers of the same geometry: side (thickness), light edge, top.
export class Extruded extends GlimmerComponent<ShapeSig> {
  get d() {
    return Math.max(0, Math.min(3, this.args.depth ?? 2));
  }
  get sideT() {
    return `translate(${this.d * 1.6} ${this.d * 2.2})`;
  }
  get side() {
    return shade(this.args.fill, -0.42);
  }
  get hi() {
    return shade(this.args.fill, 0.55);
  }
  get edge() {
    return this.args.edge ?? shade(this.args.fill, -0.5);
  }
  get style() {
    return htmlSafe(`filter:${shadowCss(this.d)}`);
  }
  <template>
    <svg
      class='ex'
      viewBox='0 0 100 100'
      style={{this.style}}
      aria-hidden='true'
    >
      {{#if this.d}}
        <g transform={{this.sideT}} fill={{this.side}}>
          {{#each @paths as |p|}}<path d={{p}} />{{/each}}
        </g>
        <g transform='translate(-1.3 -1.3)' fill={{this.hi}}>
          {{#each @paths as |p|}}<path d={{p}} />{{/each}}
        </g>
      {{/if}}
      <g
        fill={{@fill}}
        stroke={{this.edge}}
        stroke-width='1.6'
        stroke-linejoin='round'
      >
        {{#each @paths as |p|}}<path d={{p}} />{{/each}}
      </g>
      {{#if @marks}}
        <g
          fill='none'
          stroke={{if @markFill @markFill this.edge}}
          stroke-width='2.4'
          stroke-linecap='round'
        >
          {{#each @marks as |m|}}<path d={{m}} />{{/each}}
        </g>
      {{/if}}
    </svg>
    <style scoped>
      .ex {
        width: 100%;
        display: block;
        overflow: visible;
      }
    </style>
  </template>
}

interface TokenSig {
  Args: { def?: CompDef; colour?: string };
}
export class Token extends GlimmerComponent<TokenSig> {
  get paths() {
    let s = this.args.def?.look?.shape ?? 'meeple';
    if (s === 'custom' && this.args.def?.look?.path)
      return [this.args.def.look.path];
    return [
      s === 'pawn'
        ? PAWN_TOKEN
        : s === 'circle' || s === 'disc'
          ? DISC
          : MEEPLE,
    ];
  }
  get fill() {
    return this.args.colour ?? this.args.def?.look?.fill ?? '#c8553d';
  }
  <template>
    <Extruded
      @paths={{this.paths}}
      @fill={{this.fill}}
      @edge={{@def.look.edge}}
      @depth={{@def.look.depth}}
    />
  </template>
}

// ─── Chess pieces (Staunton-ish silhouettes) ──────────────────────────────
const BASE = 'M20 92h60c0-6-4-10-10-11h-40c-6 1-10 5-10 11z';
const PIECE_PATHS: Record<string, { paths: string[]; marks?: string[] }> = {
  P: {
    paths: [
      BASE,
      'M40 50c-1 12-5 21-11 31h42c-6-10-10-19-11-31z',
      'M37 50h26c0-4-4-6-8-6h-10c-4 0-8 2-8 6z',
      circlePath(50, 32, 12),
    ],
  },
  R: {
    paths: [
      BASE,
      'M33 81l4-31h26l4 31z',
      'M30 50h40v-6h-40z',
      'M31 44v-20h8v7h7v-7h8v7h7v-7h8v20z',
    ],
  },
  N: {
    paths: [
      BASE,
      'M30 81c0-15 5-23 13-31c-6 2-12 4-16 1c-3-3-1-8 4-12c6-5 10-12 13-18l3-7l4 6c11 2 19 10 21 24c2 13-1 25-3 37z',
    ],
    marks: ['M60 22c3 6 5 13 5 20', 'M66 27c2 5 3 11 3 17'],
  },
  B: {
    paths: [
      BASE,
      'M38 81c2-12 4-22 4-29h16c0 7 2 17 4 29z',
      'M35 52h30c0-4-3-6-7-6h-16c-4 0-7 2-7 6z',
      'M50 13c10 8 15 17 15 25c0 6-6 10-15 10c-9 0-15-4-15-10c0-8 5-17 15-25z',
      circlePath(50, 11, 4.5),
    ],
    marks: ['M55 25l-9 12'],
  },
  Q: {
    paths: [
      BASE,
      'M35 81c3-13 6-24 6-31h18c0 7 3 18 6 31z',
      'M32 50h36c0-4-3-6-7-6h-22c-4 0-7 2-7 6z',
      'M30 46l-5-22l12 11l6-17l7 15l7-15l6 17l12-11l-5 22z',
      circlePath(25, 21, 4),
      circlePath(43, 15, 4),
      circlePath(57, 15, 4),
      circlePath(75, 21, 4),
    ],
  },
  K: {
    paths: [
      BASE,
      'M35 81c3-13 6-24 6-31h18c0 7 3 18 6 31z',
      'M32 50h36c0-4-3-6-7-6h-22c-4 0-7 2-7 6z',
      'M31 46c-5-11 1-20 19-20c18 0 24 9 19 20z',
      'M47 6h6v6h6v6h-6v9h-6v-9h-6v-6h6z',
    ],
  },
};
interface PieceSig {
  Args: { def?: CompDef };
}
export class Piece extends GlimmerComponent<PieceSig> {
  get shape() {
    let t = this.args.def?.rank ?? 'P';
    if (this.args.def?.look?.shape === 'custom' && this.args.def.look.path)
      return { paths: [this.args.def.look.path] };
    return PIECE_PATHS[t] ?? PIECE_PATHS.P;
  }
  get fill() {
    return this.args.def?.look?.fill ?? '#e8dcc4';
  }
  get markFill() {
    return shade(this.fill, -0.35);
  }
  <template>
    <Extruded
      @paths={{this.shape.paths}}
      @marks={{this.shape.marks}}
      @markFill={{this.markFill}}
      @fill={{this.fill}}
      @edge={{@def.look.edge}}
      @depth={{@def.look.depth}}
    />
  </template>
}

// ─── Tile (square or hex, with a label or image) ──────────────────────────
const HEX = 'M50 4l40 23v46l-40 23l-40-23v-46z';
const SQUARE = 'M10 10h80v80h-80z';
interface TileSig {
  Args: { def?: CompDef; face?: number };
}
export class Tile extends GlimmerComponent<TileSig> {
  get paths() {
    return [this.args.def?.look?.shape === 'hex' ? HEX : SQUARE];
  }
  get label() {
    let f = this.args.def?.faces?.[this.args.face ?? 0];
    return (
      f?.label ??
      (f?.value !== undefined
        ? String(f.value)
        : (this.args.def?.name ?? '').slice(0, 2))
    );
  }
  <template>
    <div class='tile'>
      <Extruded
        @paths={{this.paths}}
        @fill={{if @def.look.fill @def.look.fill '#e9dcc0'}}
        @edge={{@def.look.edge}}
        @depth={{@def.look.depth}}
      />
      <span
        class='tl'
        style={{htmlSafe (concatInk @def.look.ink)}}
      >{{this.label}}</span>
    </div>
    <style scoped>
      .tile {
        position: relative;
        width: 100%;
        container-type: inline-size;
      }
      .tl {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        font:
          700 30cqw 'Iowan Old Style',
          Georgia,
          serif;
      }
    </style>
  </template>
}
const concatInk = (ink?: string) => `color:${ink ?? '#4a3b2a'}`;

// ─── Boards: a chequered grid or a numbered track with snakes and ladders ─
interface BoardSig {
  Args: {
    def?: CompDef;
    kind: 'grid' | 'track';
    w: number;
    h: number;
    cols?: number;
    rows?: number;
    length?: number;
    path?: string;
    jumps?: Record<string, number>;
    flip?: boolean;
  };
}
export class Board extends GlimmerComponent<BoardSig> {
  get light() {
    return this.args.def?.look?.fill ?? '#e9d3ad';
  }
  get dark() {
    return this.args.def?.look?.ink ?? '#7a5236';
  }
  get viewBox() {
    return `0 0 ${this.args.w} ${this.args.h}`;
  }
  get squares() {
    let cols = this.args.cols ?? (this.args.kind === 'track' ? 10 : 8);
    let rows =
      this.args.rows ??
      (this.args.kind === 'track'
        ? Math.ceil((this.args.length ?? 100) / cols)
        : 8);
    let cw = this.args.w / cols;
    let ch = this.args.h / rows;
    let out: {
      x: number;
      y: number;
      w: number;
      h: number;
      fill: string;
      n: string;
      nx: number;
      ny: number;
    }[] = [];
    let palette = ['#f6e7c8', '#efd9b4', '#e8eed9', '#f3dcc9', '#dfe7ec'];
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        let x = c * cw;
        let y = (rows - 1 - r) * ch;
        if (this.args.kind === 'grid') {
          let darkSq = (r + c) % 2 === 0;
          out.push({
            x,
            y,
            w: cw,
            h: ch,
            fill: darkSq ? this.dark : this.light,
            n: '',
            nx: 0,
            ny: 0,
          });
        } else {
          let col = this.args.path === 'row' || r % 2 === 0 ? c : cols - 1 - c;
          let sq = r * cols + col + 1;
          out.push({
            x,
            y,
            w: cw,
            h: ch,
            fill: palette[(r * 3 + c) % palette.length],
            n: String(sq),
            nx: x + cw * 0.12,
            ny: y + ch * 0.26,
          });
        }
      }
    }
    return out;
  }
  get files() {
    if (this.args.kind !== 'grid') return [];
    let cw = this.args.w / 8;
    return 'abcdefgh'
      .split('')
      .map((f, i) => ({ f, x: (i + 0.5) * cw, y: this.args.h + 2.2 }));
  }
  get ranks() {
    if (this.args.kind !== 'grid') return [];
    let ch = this.args.h / 8;
    return [1, 2, 3, 4, 5, 6, 7, 8].map((r) => ({
      r,
      x: -2,
      y: this.args.h - (r - 0.5) * ch,
    }));
  }
  centre(sq: number) {
    let cols = this.args.cols ?? 10;
    let rows = Math.ceil((this.args.length ?? 100) / cols);
    let i = sq - 1;
    let row = Math.floor(i / cols);
    let col =
      this.args.path === 'row' || row % 2 === 0
        ? i % cols
        : cols - 1 - (i % cols);
    return {
      x: (col + 0.5) * (this.args.w / cols),
      y: this.args.h - (row + 0.5) * (this.args.h / rows),
    };
  }
  get ladders() {
    let cw = this.args.w / (this.args.cols ?? 10);
    return Object.entries(this.args.jumps ?? {})
      .filter(([a, b]) => Number(b) > Number(a))
      .map(([a, b]) => {
        let p = this.centre(Number(a));
        let q = this.centre(Number(b));
        let dx = q.x - p.x;
        let dy = q.y - p.y;
        let len = Math.hypot(dx, dy);
        let nx = (-dy / len) * cw * 0.17;
        let ny = (dx / len) * cw * 0.17;
        let rungs = [];
        let n = Math.max(2, Math.round(len / (cw * 0.38)));
        for (let i = 1; i < n; i++) {
          let t = i / n;
          let x = p.x + dx * t;
          let y = p.y + dy * t;
          rungs.push(`M${x - nx} ${y - ny}L${x + nx} ${y + ny}`);
        }
        return {
          rails: `M${p.x - nx} ${p.y - ny}L${q.x - nx} ${q.y - ny}M${p.x + nx} ${p.y + ny}L${q.x + nx} ${q.y + ny}`,
          rungs: rungs.join(''),
          w: cw * 0.06,
        };
      });
  }
  get snakes() {
    let cw = this.args.w / (this.args.cols ?? 10);
    let colours = ['#5f8f4e', '#b5533c', '#7a5aa0', '#c58b2a', '#3f7f8f'];
    return Object.entries(this.args.jumps ?? {})
      .filter(([a, b]) => Number(b) < Number(a))
      .map(([a, b], i) => {
        let head = this.centre(Number(a));
        let tail = this.centre(Number(b));
        let dx = tail.x - head.x;
        let dy = tail.y - head.y;
        let len = Math.hypot(dx, dy);
        let wig = Math.min(cw * 0.9, len * 0.28) * (i % 2 ? 1 : -1);
        let nx = -dy / len;
        let ny = dx / len;
        let c1 = {
          x: head.x + dx * 0.33 + nx * wig,
          y: head.y + dy * 0.33 + ny * wig,
        };
        let c2 = {
          x: head.x + dx * 0.66 - nx * wig,
          y: head.y + dy * 0.66 - ny * wig,
        };
        return {
          d: `M${head.x} ${head.y}C${c1.x} ${c1.y} ${c2.x} ${c2.y} ${tail.x} ${tail.y}`,
          colour: colours[i % colours.length],
          belly: shade(colours[i % colours.length], 0.35),
          w: cw * 0.2,
          head,
          r: cw * 0.17,
          eye: cw * 0.035,
        };
      });
  }
  <template>
    <svg
      class='board {{@kind}}'
      viewBox={{this.viewBox}}
      preserveAspectRatio='none'
      aria-hidden='true'
    >
      {{#each this.squares as |s|}}
        <rect
          x={{s.x}}
          y={{s.y}}
          width={{s.w}}
          height={{s.h}}
          fill={{s.fill}}
        />
        {{#if s.n}}
          <text x={{s.nx}} y={{s.ny}} class='num'>{{s.n}}</text>
        {{/if}}
      {{/each}}
      {{#each this.ladders as |l|}}
        <g class='ladder'>
          <path
            d={{l.rails}}
            stroke='#6b4a2b'
            stroke-width={{l.w}}
            stroke-linecap='round'
            transform='translate(.35 .5)'
            opacity='.35'
          />
          <path
            d={{l.rungs}}
            stroke='#a9824f'
            stroke-width={{l.w}}
            stroke-linecap='round'
          />
          <path
            d={{l.rails}}
            stroke='#8b6239'
            stroke-width={{l.w}}
            stroke-linecap='round'
          />
        </g>
      {{/each}}
      {{#each this.snakes as |s|}}
        <g class='snake'>
          <path
            d={{s.d}}
            stroke='rgba(40,20,10,.25)'
            stroke-width={{s.w}}
            stroke-linecap='round'
            fill='none'
            transform='translate(.4 .6)'
          />
          <path
            d={{s.d}}
            stroke={{s.colour}}
            stroke-width={{s.w}}
            stroke-linecap='round'
            fill='none'
          />
          <path
            d={{s.d}}
            stroke={{s.belly}}
            stroke-width={{s.eye}}
            stroke-dasharray='1 1.4'
            stroke-linecap='round'
            fill='none'
          />
          <circle cx={{s.head.x}} cy={{s.head.y}} r={{s.r}} fill={{s.colour}} />
          <circle cx={{s.head.x}} cy={{s.head.y}} r={{s.eye}} fill='#fff8e8' />
        </g>
      {{/each}}
      {{#each this.files as |f|}}
        <text x={{f.x}} y={{f.y}} class='coord'>{{f.f}}</text>
      {{/each}}
      {{#each this.ranks as |r|}}
        <text x={{r.x}} y={{r.y}} class='coord'>{{r.r}}</text>
      {{/each}}
    </svg>
    <style scoped>
      .board {
        width: 100%;
        height: 100%;
        display: block;
        overflow: visible;
      }
      .board.grid {
        outline: 1.6cqw solid #4a2e1c;
        box-shadow:
          0 0 0 2.4cqw #6a4429,
          0 1.2cqw 2.4cqw 1.6cqw rgba(0, 0, 0, 0.35);
        border-radius: 0.3cqw;
      }
      .board.track {
        box-shadow:
          0 0 0 0.8cqw #fbf3e2,
          0 0 0 1.2cqw #b49a74,
          0 1cqw 2cqw rgba(60, 40, 20, 0.3);
        border-radius: 0.4cqw;
      }
      .num {
        font:
          650 1.6px ui-rounded,
          'SF Pro Rounded',
          system-ui,
          sans-serif;
        fill: #6a573f;
        opacity: 0.6;
      }
      .coord {
        font:
          600 1.7px ui-rounded,
          system-ui,
          sans-serif;
        fill: #e9d3ad;
        text-anchor: middle;
        dominant-baseline: central;
      }
    </style>
  </template>
}

// ─── Any part, from a definition (the specimen / inventory renderer) ──────
interface PartSig {
  Args: {
    def: CompDef;
    cardLook?: Look;
    faceUp?: boolean;
    face?: number;
    colour?: string;
  };
}
export class Part extends GlimmerComponent<PartSig> {
  get kind() {
    return this.args.def.kind;
  }
  get dieFace() {
    return this.args.face ?? 4;
  }
  get chipColour() {
    return this.args.colour ?? this.args.def.look?.fill;
  }
  <template>
    {{#if (eq this.kind 'card')}}
      <PlayingCard
        @def={{@def}}
        @faceUp={{if (eq @faceUp false) false true}}
        @back={{@cardLook}}
        @look={{@def.look}}
      />
    {{else if (eq this.kind 'die')}}
      <Die @def={{@def}} @face={{this.dieFace}} />
    {{else if (eq this.kind 'chip')}}
      <Chip
        @colour={{this.chipColour}}
        @value={{@def.value}}
        @depth={{@def.look.depth}}
      />
    {{else if (eq this.kind 'coin')}}
      <Chip
        @coin={{true}}
        @colour={{@def.look.fill}}
        @face={{if (eq @face 1) 'T' 'H'}}
        @depth={{@def.look.depth}}
      />
    {{else if (eq this.kind 'token')}}
      <Token @def={{@def}} @colour={{@colour}} />
    {{else if (eq this.kind 'piece')}}
      <Piece @def={{@def}} />
    {{else if (eq this.kind 'tile')}}
      <Tile @def={{@def}} @face={{@face}} />
    {{else}}
      <div
        class='mini-board'
        style={{htmlSafe (concatFill @def.look.fill)}}
      ></div>
    {{/if}}
    <style scoped>
      .mini-board {
        width: 100%;
        aspect-ratio: 1;
        border-radius: 6%;
        box-shadow:
          inset 0 0 0 3px rgba(0, 0, 0, 0.12),
          0 3px 8px rgba(0, 0, 0, 0.2);
        background-image:
          linear-gradient(
            45deg,
            rgba(0, 0, 0, 0.18) 25%,
            transparent 25%,
            transparent 75%,
            rgba(0, 0, 0, 0.18) 75%
          ),
          linear-gradient(
            45deg,
            rgba(0, 0, 0, 0.18) 25%,
            transparent 25%,
            transparent 75%,
            rgba(0, 0, 0, 0.18) 75%
          );
        background-size: 25% 25%;
        background-position:
          0 0,
          12.5% 12.5%;
      }
    </style>
  </template>
}
const concatFill = (f?: string) => `background-color:${f ?? '#e9d3ad'}`;

export { shade as shadeColour };
