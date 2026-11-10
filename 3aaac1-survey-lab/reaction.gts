// The reaction timeline: the video's own frames along the top, then one lane
// per signal (looking at it, smile, raised brows, frown), with the moments
// that were asked about pinned on it. Used by the response and the results.
import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { clock, linePath } from './face-signals';
import type { Bin } from './face-signals';

export interface Pin {
  t: number;
  label: string;
}

interface Signature {
  Args: {
    bins: Bin[];
    duration: number;
    thumbs?: { t: number; url: string }[];
    pins?: Pin[];
    cursor?: number;
    onSeek?: (t: number) => void;
    camera?: boolean;
  };
}

const W = 600;
const H = 34;

export class ReactionTimeline extends Component<Signature> {
  get lanes() {
    const b = this.args.bins ?? [];
    const hasGaze = b.some((x) => x.on !== null);
    const lanes = [
      {
        key: 'att',
        name: hasGaze ? 'Looking at it' : 'Face in view',
        cls: 'att',
        d: linePath(
          b.map((x) => (hasGaze ? (x.on ?? 0) : x.face)),
          W,
          H,
        ),
        area: true,
      },
      {
        key: 'smile',
        name: 'Smile',
        cls: 'smile',
        d: linePath(
          b.map((x) => x.smile),
          W,
          H,
          0.35,
        ),
        area: true,
      },
      {
        key: 'surprise',
        name: 'Brows up',
        cls: 'surprise',
        d: linePath(
          b.map((x) => x.surprise),
          W,
          H,
          0.3,
        ),
        area: true,
      },
      {
        key: 'frown',
        name: 'Frown',
        cls: 'frown',
        d: linePath(
          b.map((x) => x.frown),
          W,
          H,
          0.3,
        ),
        area: true,
      },
    ];
    return lanes.map((l) => ({
      ...l,
      fill: l.d ? `${l.d} L${W},${H} L0,${H} Z` : '',
    }));
  }
  get pins() {
    const d = this.args.duration || 1;
    return (this.args.pins ?? []).map((p) => ({
      ...p,
      time: clock(p.t),
      style: htmlSafe(`left:${((p.t / d) * 100).toFixed(2)}%`),
    }));
  }
  get cursorStyle() {
    const d = this.args.duration || 1;
    return htmlSafe(
      `left:${(((this.args.cursor ?? 0) / d) * 100).toFixed(2)}%`,
    );
  }
  get hasCursor() {
    return typeof this.args.cursor === 'number';
  }
  get viewBox() {
    return `0 0 ${W} ${H}`;
  }
  get ticks() {
    const d = this.args.duration || 0;
    const step = d > 90 ? 30 : d > 40 ? 10 : 5;
    const out: { label: string; style: ReturnType<typeof htmlSafe> }[] = [];
    for (let t = 0; t <= d; t += step)
      out.push({
        label: clock(t),
        style: htmlSafe(`left:${((t / (d || 1)) * 100).toFixed(2)}%`),
      });
    return out;
  }
  seek = (ev: Event) => {
    const e = ev as MouseEvent;
    const el = e.currentTarget as HTMLElement;
    const r = el.getBoundingClientRect();
    const f = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    this.args.onSeek?.(f * (this.args.duration || 0));
  };
  seekTo = (t: number) => this.args.onSeek?.(t);

  <template>
    <div class='rt'>
      {{#if @thumbs.length}}
        <div class='thumbs' aria-hidden='true'>
          {{#each @thumbs as |th|}}<img src={{th.url}} alt='' />{{/each}}
        </div>
      {{/if}}
      <div class='plot'>
        <div class='names'>
          {{#each this.lanes as |l|}}<span
              class='name {{l.cls}}'
            >{{l.name}}</span>{{/each}}
        </div>
        {{! a mouse shortcut; the same seeking is on the pins and the player }}
        {{! template-lint-disable no-invalid-interactive }}
        <div class='lanes' {{on 'click' this.seek}}>
          {{#each this.lanes as |l|}}
            <svg
              class='lane {{l.cls}}'
              viewBox={{this.viewBox}}
              preserveAspectRatio='none'
              aria-hidden='true'
            >
              <path class='area' d={{l.fill}} />
              <path class='line' d={{l.d}} vector-effect='non-scaling-stroke' />
            </svg>
          {{/each}}
          {{#each this.pins as |p|}}<span
              class='pinline'
              style={{p.style}}
            ></span>{{/each}}
          {{#if this.hasCursor}}<span
              class='cursor'
              style={{this.cursorStyle}}
            ></span>{{/if}}
        </div>
      </div>
      <div class='axis'>
        <span class='gutter'></span>
        <div class='ticks'>
          {{#each this.ticks as |tk|}}<span
              class='tick'
              style={{tk.style}}
            >{{tk.label}}</span>{{/each}}
          {{#each this.pins as |p|}}
            <button
              type='button'
              class='pin'
              style={{p.style}}
              title={{p.label}}
              {{on 'click' (fn this.seekTo p.t)}}
            >{{p.time}}</button>
          {{/each}}
        </div>
      </div>
      {{#unless @camera}}<p class='nocam'>Camera was off for this one, so there
          is no face data. Only the answers count.</p>{{/unless}}
    </div>
    <style scoped>
      .rt {
        --gut: 92px;
        display: grid;
        gap: 6px;
        font-size: 12px;
      }
      .thumbs {
        margin-left: var(--gut);
        display: grid;
        grid-auto-flow: column;
        grid-auto-columns: 1fr;
        gap: 2px;
        border-radius: 6px;
        overflow: hidden;
        height: 44px;
      }
      .thumbs img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .plot {
        display: grid;
        grid-template-columns: var(--gut) 1fr;
      }
      .names {
        display: grid;
        grid-auto-rows: 38px;
      }
      .name {
        align-self: center;
        color: var(--sv-muted);
        font-weight: 500;
      }
      .lanes {
        position: relative;
        display: grid;
        grid-auto-rows: 38px;
        cursor: pointer;
        border-left: 1px solid var(--sv-rule);
      }
      .lane {
        width: 100%;
        height: 34px;
        align-self: center;
        display: block;
        overflow: visible;
      }
      .lane + .lane {
        border-top: 1px dashed var(--sv-rule);
      }
      .area {
        opacity: 0.16;
      }
      .line {
        fill: none;
        stroke-width: 1.6;
      }
      .att .area {
        fill: var(--sv-att);
      }
      .att .line {
        stroke: var(--sv-att);
      }
      .name.att {
        color: var(--sv-att);
      }
      .smile .area {
        fill: var(--sv-smile);
      }
      .smile .line {
        stroke: var(--sv-smile);
      }
      .name.smile {
        color: var(--sv-smile);
      }
      .surprise .area {
        fill: var(--sv-surprise);
      }
      .surprise .line {
        stroke: var(--sv-surprise);
      }
      .name.surprise {
        color: var(--sv-surprise);
      }
      .frown .area {
        fill: var(--sv-frown);
      }
      .frown .line {
        stroke: var(--sv-frown);
      }
      .name.frown {
        color: var(--sv-frown);
      }
      .pinline {
        position: absolute;
        top: 0;
        bottom: 0;
        width: 0;
        border-left: 1.5px solid var(--sv-ink);
        opacity: 0.55;
      }
      .cursor {
        position: absolute;
        top: -4px;
        bottom: -4px;
        width: 2px;
        margin-left: -1px;
        background: var(--sv-live);
        border-radius: 1px;
      }
      .axis {
        display: grid;
        grid-template-columns: var(--gut) 1fr;
      }
      .ticks {
        position: relative;
        height: 40px;
      }
      .tick {
        position: absolute;
        top: 0;
        transform: translateX(-50%);
        color: var(--sv-muted);
        font-family: var(--sv-mono);
        font-size: 11px;
      }
      .tick:first-child {
        transform: none;
      }
      .pin {
        position: absolute;
        top: 16px;
        transform: translateX(-50%);
        white-space: nowrap;
        font: 600 11px/1 var(--sv-sans);
        padding: 5px 8px;
        border-radius: 999px;
        border: 0;
        background: var(--sv-ink);
        color: var(--sv-paper);
        cursor: pointer;
      }
      .pin:hover {
        background: var(--sv-live);
      }
      .pin:focus-visible {
        outline: 2px solid var(--sv-live);
        outline-offset: 2px;
      }
      .nocam {
        margin: 0;
        color: var(--sv-muted);
      }
    </style>
  </template>
}
