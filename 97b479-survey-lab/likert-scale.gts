// A read-only strip: the seven agreement points (or a ladder's rungs), where the AI first
// placed someone (ring), where they moved themselves (diamond), and where
// they ended up (dot). Other people's finals can sit behind as faint ticks.
import Component from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { SCALE } from './likert-ai';

interface Signature {
  Args: {
    aiPos?: number | null;
    selfPos?: number | null;
    final?: number | null;
    others?: number[];
    mean?: number | null;
    compact?: boolean;
    labels?: string[]; // a ladder's rungs, lowest first; default is agree/disagree
  };
}

const at = (p: number) =>
  htmlSafe(`left:${(Math.min(1, Math.max(0, p)) * 100).toFixed(2)}%`);

export class LikertStrip extends Component<Signature> {
  get ticks() {
    const labels =
      this.args.labels && this.args.labels.length > 1
        ? this.args.labels
        : SCALE;
    const last = labels.length - 1;
    const mid = Math.round(last / 2);
    if (labels === SCALE)
      return labels.map((label, i) => ({
        label,
        style: at(i / last),
        labelStyle: at(i / last),
        short: i === 0 || i === mid || i === last,
      }));
    // ladder labels are longer: each gets its share of the width, and the two
    // ends hang inwards so nothing runs off or overlaps
    const share = (100 / last) * 0.92;
    return labels.map((label, i) => {
      const left = (i / last) * 100;
      const pos =
        i === 0
          ? `left:0;width:${share / 2 + 2}%;transform:none;text-align:left`
          : i === last
            ? `left:auto;right:0;width:${share / 2 + 2}%;transform:none;text-align:right`
            : `left:${left.toFixed(2)}%;width:${share.toFixed(2)}%`;
      return {
        label,
        style: at(i / last),
        labelStyle: htmlSafe(pos),
        short: i === 0 || i === mid || i === last,
      };
    });
  }
  get ladder() {
    return Boolean(this.args.labels && this.args.labels.length > 1);
  }
  get ai() {
    return typeof this.args.aiPos === 'number' ? at(this.args.aiPos) : null;
  }
  get self() {
    const s = this.args.selfPos;
    const a = this.args.aiPos;
    // only worth a mark when they moved it
    return typeof s === 'number' &&
      (typeof a !== 'number' || Math.abs(s - a) > 0.02)
      ? at(s)
      : null;
  }
  get final() {
    return typeof this.args.final === 'number' ? at(this.args.final) : null;
  }
  get mean() {
    return typeof this.args.mean === 'number' ? at(this.args.mean) : null;
  }
  get others() {
    return (this.args.others ?? []).map((p) => at(p));
  }

  <template>
    <div class='ls {{if @compact "compact"}} {{if this.ladder "ladder"}}'>
      <div class='track'>
        {{#each this.ticks as |t|}}<span
            class='tick'
            style={{t.style}}
          ></span>{{/each}}
        {{#each this.others as |o|}}<span
            class='other'
            style={{o}}
          ></span>{{/each}}
        {{#if this.mean}}<span
            class='mean'
            style={{this.mean}}
            title='Average'
          ></span>{{/if}}
        {{#if this.ai}}<span
            class='ai'
            style={{this.ai}}
            title='Where the AI placed them'
          ></span>{{/if}}
        {{#if this.self}}<span
            class='self'
            style={{this.self}}
            title='Where they moved it'
          ></span>{{/if}}
        {{#if this.final}}<span
            class='final'
            style={{this.final}}
            title='Final'
          ></span>{{/if}}
      </div>
      <div class='labels'>
        {{#each this.ticks as |t|}}
          <span
            class='label {{if t.short "keep"}}'
            style={{t.labelStyle}}
          >{{t.label}}</span>
        {{/each}}
      </div>
    </div>
    <style scoped>
      .ls {
        --c-ink: var(--sv-ink, #1d1c1a);
        --c-muted: var(--sv-muted, #6b675f);
        --c-rule: var(--sv-rule, #e4e0d8);
        --c-live: var(--sv-live, #e2553b);
        --c-ai: var(--sv-surprise, #7a55c9);
        padding: 0 6px;
      }
      .track {
        position: relative;
        height: 26px;
      }
      .track::before {
        content: '';
        position: absolute;
        left: 0;
        right: 0;
        top: 12px;
        height: 2px;
        border-radius: 1px;
        background: linear-gradient(90deg, #c9634a, var(--c-rule) 50%, #3f8a6e);
      }
      .tick {
        position: absolute;
        top: 8px;
        width: 2px;
        height: 10px;
        margin-left: -1px;
        background: var(--c-rule);
      }
      .other {
        position: absolute;
        top: 6px;
        width: 3px;
        height: 14px;
        margin-left: -1.5px;
        border-radius: 2px;
        background: var(--c-ink);
        opacity: 0.18;
      }
      .mean {
        position: absolute;
        top: 2px;
        width: 2px;
        height: 22px;
        margin-left: -1px;
        background: var(--c-ink);
      }
      .ai {
        position: absolute;
        top: 5px;
        width: 16px;
        height: 16px;
        margin-left: -8px;
        border-radius: 50%;
        border: 2px solid var(--c-ai);
        box-sizing: border-box;
        background: transparent;
      }
      .self {
        position: absolute;
        top: 7px;
        width: 12px;
        height: 12px;
        margin-left: -6px;
        transform: rotate(45deg);
        border: 2px solid var(--c-ink);
        box-sizing: border-box;
        background: var(--sv-paper, #fff);
      }
      .final {
        position: absolute;
        top: 6px;
        width: 14px;
        height: 14px;
        margin-left: -7px;
        border-radius: 50%;
        background: var(--c-live);
        box-shadow: 0 0 0 3px rgba(226, 85, 59, 0.2);
      }
      .labels {
        position: relative;
        height: 30px;
        margin-top: 4px;
      }
      .label {
        position: absolute;
        transform: translateX(-50%);
        width: 72px;
        text-align: center;
        font-size: 11px;
        line-height: 1.2;
        color: var(--c-muted);
      }
      .label:first-child {
        transform: translateX(-12%);
      }
      .label:last-child {
        transform: translateX(-88%);
      }
      .compact .label:not(.keep) {
        display: none;
      }
      .ladder .track::before {
        background: linear-gradient(90deg, var(--c-rule), var(--c-ink));
        opacity: 0.5;
      }
      .ladder .labels {
        height: 44px;
      }
      .ladder .label {
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      @container (max-width: 560px) {
        .label:not(.keep) {
          display: none;
        }
      }
    </style>
  </template>
}

// The zoomed ladder: only the stretch someone is in, with its two ends named
// (rungs at first, then the examples fine-tuning added), their dot inside it,
// and a small overview of the whole ladder underneath.
interface ZoomSignature {
  Args: {
    rungs: string[];
    lo: number;
    hi: number;
    loLabel: string;
    hiLabel: string;
    pos: number;
    aiPos?: number | null;
    anchor?: { at: number; text: string } | null;
  };
}

export class LadderZoom extends Component<ZoomSignature> {
  inWin(p: number) {
    const { lo, hi } = this.args;
    return htmlSafe(
      `left:${(((p - lo) / Math.max(1e-6, hi - lo)) * 100).toFixed(2)}%`,
    );
  }
  get dot() {
    return this.inWin(this.args.pos);
  }
  get ai() {
    const a = this.args.aiPos;
    return typeof a === 'number' &&
      a >= this.args.lo - 1e-6 &&
      a <= this.args.hi + 1e-6
      ? this.inWin(a)
      : null;
  }
  get anchor() {
    return this.args.anchor ? this.inWin(this.args.anchor.at) : null;
  }
  get band() {
    const { lo, hi } = this.args;
    return htmlSafe(
      `left:${(lo * 100).toFixed(2)}%;width:${(Math.max(0.01, hi - lo) * 100).toFixed(2)}%`,
    );
  }
  get rungDots() {
    const n = this.args.rungs.length;
    return this.args.rungs.map((r, i) => ({
      title: r,
      style: at(n > 1 ? i / (n - 1) : 0.5),
    }));
  }

  <template>
    <div class='lz'>
      <div class='ends'>
        <span class='end lo'><small>lower</small>{{@loLabel}}</span>
        <span class='end hi'><small>higher</small>{{@hiLabel}}</span>
      </div>
      <div class='zt'>
        <span class='cap l'></span><span class='cap r'></span>
        {{#if this.anchor}}<span
            class='anch'
            style={{this.anchor}}
          ></span>{{/if}}
        {{#if this.ai}}<span
            class='ai'
            style={{this.ai}}
            title='Where the AI placed you'
          ></span>{{/if}}
        <span class='dot' style={{this.dot}}></span>
      </div>
      <div class='ov' aria-hidden='true'>
        <span class='band' style={{this.band}}></span>
        {{#each this.rungDots as |d|}}<span
            class='rd'
            style={{d.style}}
            title={{d.title}}
          ></span>{{/each}}
      </div>
    </div>
    <style scoped>
      .lz {
        --c-ink: var(--sv-ink, #1d1c1a);
        --c-muted: var(--sv-muted, #6b675f);
        --c-rule: var(--sv-rule, #e4e0d8);
        --c-live: var(--sv-live, #e2553b);
        --c-ai: var(--sv-surprise, #7a55c9);
        display: grid;
        gap: 10px;
      }
      .ends {
        display: flex;
        justify-content: space-between;
        gap: 16px;
      }
      .end {
        display: grid;
        gap: 2px;
        max-width: 45%;
        font: 600 15px/1.3 var(--sv-sans, sans-serif);
      }
      .end.hi {
        text-align: right;
      }
      .end small {
        font: 500 11px/1 var(--sv-mono, monospace);
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--c-muted);
      }
      .zt {
        position: relative;
        height: 30px;
        margin: 0 8px;
      }
      .zt::before {
        content: '';
        position: absolute;
        left: 0;
        right: 0;
        top: 14px;
        height: 2px;
        background: var(--c-ink);
        opacity: 0.35;
      }
      .cap {
        position: absolute;
        top: 6px;
        width: 2px;
        height: 18px;
        background: var(--c-ink);
      }
      .cap.l {
        left: 0;
      }
      .cap.r {
        right: 0;
      }
      .anch {
        position: absolute;
        top: 4px;
        width: 2px;
        height: 22px;
        margin-left: -1px;
        background: var(--c-ink);
      }
      .ai {
        position: absolute;
        top: 6px;
        width: 18px;
        height: 18px;
        margin-left: -9px;
        border-radius: 50%;
        border: 2px solid var(--c-ai);
        box-sizing: border-box;
      }
      .dot {
        position: absolute;
        top: 7px;
        width: 16px;
        height: 16px;
        margin-left: -8px;
        border-radius: 50%;
        background: var(--c-live);
        box-shadow: 0 0 0 4px rgba(226, 85, 59, 0.2);
        transition: left 0.35s cubic-bezier(0.22, 1, 0.36, 1);
      }
      .ov {
        position: relative;
        height: 10px;
        margin: 0 8px;
      }
      .ov::before {
        content: '';
        position: absolute;
        left: 0;
        right: 0;
        top: 4px;
        height: 2px;
        background: var(--c-rule);
      }
      .band {
        position: absolute;
        top: 1px;
        height: 8px;
        border-radius: 4px;
        background: var(--c-live);
        opacity: 0.35;
        transition:
          left 0.35s,
          width 0.35s;
      }
      .rd {
        position: absolute;
        top: 2px;
        width: 6px;
        height: 6px;
        margin-left: -3px;
        border-radius: 50%;
        background: var(--c-muted);
      }
    </style>
  </template>
}
