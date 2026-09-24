import { Component } from '@cardstack/base/card-api';

import {
  flatPointsToPath,
  parseInk,
  strokeBBox,
  unionBBox,
  type InkDoc,
} from '../utils/index';
import type { EchoPad } from '../echo-pad';

function inkPaths(doc: InkDoc): { d: string; w: number }[] {
  return doc.strokes.map((s) => ({ d: flatPointsToPath(s.pts), w: s.w }));
}

function inkViewBox(doc: InkDoc): string {
  let box = unionBBox(doc.strokes.map(strokeBBox));
  if (!box) {
    return '0 0 100 100';
  }
  let pad = 24;
  return `${box.minX - pad} ${box.minY - pad} ${
    box.maxX - box.minX + pad * 2
  } ${box.maxY - box.minY + pad * 2}`;
}

class InkGlance {
  paths: { d: string; w: number }[];
  viewBox: string;
  constructor(json: string | undefined | null) {
    let doc = parseInk(json);
    this.paths = inkPaths(doc);
    this.viewBox = inkViewBox(doc);
  }
}

export class EchoPadEmbedded extends Component<typeof EchoPad> {
  get ink(): InkGlance {
    return new InkGlance(this.args.model?.inkJson);
  }

  get echoCount(): number {
    return (this.args.model?.echoes ?? []).filter(Boolean).length;
  }

  get strokeCount(): number {
    return this.ink.paths.length;
  }

  get echoLabel(): string {
    let n = this.echoCount;
    return `${n} ${n === 1 ? 'echo' : 'echoes'}`;
  }

  get firstEchoText(): string {
    let first = (this.args.model?.echoes ?? []).filter(Boolean)[0];
    let text = first?.content ?? '';
    return text.split('\n')[0] ?? '';
  }

  <template>
    <article class='ep-embedded'>
      <div class='ink'>
        {{#if this.ink.paths.length}}
          <svg
            viewBox={{this.ink.viewBox}}
            preserveAspectRatio='xMidYMid meet'
            aria-hidden='true'
          >
            {{#each this.ink.paths as |p|}}
              <path d={{p.d}} stroke-width='4' />
            {{/each}}
          </svg>
        {{else}}
          <svg viewBox='0 0 96 74' class='mark' aria-hidden='true'>
            <path d='M14 44 C 20 20, 52 14, 74 26' class='mark-ink' />
            <path
              d='M8 40 C 16 8, 74 4, 88 30 C 96 48, 60 68, 28 60 C 12 56, 4 50, 8 40 Z'
              class='mark-lasso'
            />
          </svg>
        {{/if}}
        {{#if this.firstEchoText}}
          <div class='slip-chip'>{{this.firstEchoText}}</div>
        {{/if}}
      </div>
      <div class='body'>
        <div class='eyebrow'>Echo Pad · Board</div>
        <h3 class='name'>{{if @model.title @model.title 'Untitled board'}}</h3>
        <p class='sum'>
          {{#if this.echoCount}}
            Handwritten board with accepted echoes — circle ink and the answer
            arrives beside it.
          {{else}}
            Handwritten board awaiting its first echo — circle ink and the
            answer arrives beside it.
          {{/if}}
        </p>
        <dl class='meta'>
          <dt>Strokes</dt>
          <dd>{{this.strokeCount}}</dd>
          <dt>Echoes</dt>
          <dd class='meta-echo'>{{this.echoLabel}}</dd>
        </dl>
      </div>
    </article>
    <style scoped>
      .ep-embedded {
        /* Board palette. Glimmer scopes <style> per component, so this block
           is necessarily duplicated in isolated.gts, edit.gts and BOTH
           components in formats.gts (Embedded + Fitted) — 4 copies. Change
           one, change all four, or the formats drift apart. */
        --paper: var(--background);
        --paper-raised: var(--card);
        --ink: var(--chart-4);
        --echo: var(--chart-1);
        --chrome: var(--foreground);
        --chrome-soft: var(--muted-foreground);
        --edge: var(--border);
        --grid: color-mix(in oklch, var(--border) 45%, transparent);
        --font-chrome: var(--font-mono);
        --font-hand: 'Caveat', cursive;
        display: flex;
        height: 100%;
        min-height: 6.875rem;
        font-family: var(--font-chrome);
        color: var(--chrome);
        background-color: var(--paper);
        background-image:
          linear-gradient(var(--grid) 1px, transparent 1px),
          linear-gradient(90deg, var(--grid) 1px, transparent 1px);
        background-size: 0.875rem 0.875rem;
      }
      .ink {
        position: relative;
        flex: none;
        width: 34%;
        max-width: 10.625rem;
        min-width: 6.875rem;
        border-right: 1px solid var(--grid);
        overflow: hidden;
      }
      .ink svg {
        width: 100%;
        height: 100%;
      }
      .ink path {
        fill: none;
        stroke: var(--ink);
        stroke-linecap: round;
        stroke-linejoin: round;
      }
      .mark-ink {
        stroke-width: 2.4;
      }
      /* raised to out-specify `.ink path` (0,1,1) rather than !important */
      .ink path.mark-lasso {
        stroke: var(--echo);
        stroke-width: 2;
        stroke-dasharray: 7 6;
      }
      .slip-chip {
        position: absolute;
        right: 0.375rem;
        bottom: 0.625rem;
        max-width: 84%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        background-color: var(--paper-raised);
        border: 1px solid color-mix(in oklch, var(--edge) 30%, var(--paper));
        box-shadow: 0 3px 8px
          color-mix(in oklch, var(--chrome) 20%, transparent);
        padding: 0.1875rem 0.5rem;
        transform: rotate(1.6deg);
        font-family: var(--font-hand);
        font-size: 0.8125rem;
        color: var(--echo);
      }
      .body {
        position: relative;
        flex: 1;
        min-width: 0;
        padding: 0.875rem 1rem;
      }
      .eyebrow {
        font-size: 0.46875rem;
        font-weight: 600;
        letter-spacing: 0.24em;
        text-transform: uppercase;
        color: var(--echo);
      }
      .name {
        font-family: var(--font-hand);
        font-weight: 400;
        font-size: 1.75rem;
        line-height: 1.05;
        color: var(--ink);
        margin: 0.375rem 0 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sum {
        font-size: 0.59375rem;
        line-height: 1.7;
        color: var(--chrome-soft);
        margin: 0.375rem 0 0;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
        overflow: hidden;
      }
      .meta {
        margin: 0.5rem 0 0;
        display: flex;
        gap: 0.375rem;
        font-size: 0.53125rem;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--chrome-soft);
      }
      .meta dt {
        display: inline;
      }
      .meta dt::after {
        content: ':';
      }
      .meta dd {
        display: inline;
        margin: 0;
      }
      .meta dd + dt {
        margin-left: 0.5rem;
      }
      .meta .meta-echo {
        color: var(--echo);
        font-weight: 600;
      }
    </style>
  </template>
}

export class EchoPadFitted extends Component<typeof EchoPad> {
  get ink(): InkGlance {
    return new InkGlance(this.args.model?.inkJson);
  }

  get echoCount(): number {
    return (this.args.model?.echoes ?? []).filter(Boolean).length;
  }

  get strokeCount(): number {
    return this.ink.paths.length;
  }

  get echoLabel(): string {
    let n = this.echoCount;
    return `${n} ${n === 1 ? 'echo' : 'echoes'}`;
  }

  get firstEchoText(): string {
    let first = (this.args.model?.echoes ?? []).filter(Boolean)[0];
    let text = first?.content ?? '';
    return text.split('\n')[0] ?? '';
  }

  <template>
    <article class='cq'>
      <div class='fit'>
        <div class='r-ink'>
          {{#if this.ink.paths.length}}
            <svg
              viewBox={{this.ink.viewBox}}
              preserveAspectRatio='xMidYMid meet'
              aria-hidden='true'
            >
              {{#each this.ink.paths as |p|}}
                <path d={{p.d}} stroke-width='4' />
              {{/each}}
            </svg>
          {{else}}
            <svg
              viewBox='0 0 96 74'
              preserveAspectRatio='xMidYMid meet'
              aria-hidden='true'
            >
              <path d='M14 44 C 20 20, 52 14, 74 26' class='mark-ink' />
              <path
                d='M8 40 C 16 8, 74 4, 88 30 C 96 48, 60 68, 28 60 C 12 56, 4 50, 8 40 Z'
                class='mark-lasso'
              />
            </svg>
          {{/if}}
          {{#if this.firstEchoText}}
            <div class='slip-chip'>{{this.firstEchoText}}</div>
          {{/if}}
          {{#if this.echoCount}}
            <div class='echo-badge'>{{this.echoLabel}}</div>
          {{/if}}
        </div>
        <div class='r-head'>
          <h3 class='name'>{{if @model.title @model.title 'Echo Pad'}}</h3>
        </div>
        <dl class='r-meta'>
          <dt>Strokes</dt>
          <dd>{{this.strokeCount}}</dd>
          <dt>Echoes</dt>
          <dd class='meta-echo'>{{this.echoLabel}}</dd>
        </dl>
      </div>
    </article>
    <style scoped>
      .cq {
        container-type: size;
        container-name: card;
        width: 100%;
        height: 100%;
        overflow: hidden;
      }
      .fit {
        /* Board palette. Glimmer scopes <style> per component, so this block
           is necessarily duplicated in isolated.gts, edit.gts and BOTH
           components in formats.gts (Embedded + Fitted) — 4 copies. Change
           one, change all four, or the formats drift apart. */
        --paper: var(--background);
        --paper-raised: var(--card);
        --ink: var(--chart-4);
        --echo: var(--chart-1);
        --chrome: var(--foreground);
        --chrome-soft: var(--muted-foreground);
        --edge: var(--border);
        --grid: color-mix(in oklch, var(--border) 45%, transparent);
        --font-chrome: var(--font-mono);
        --font-hand: 'Caveat', cursive;
        width: 100%;
        height: 100%;
        display: grid;
        grid-template-rows: minmax(0, 1fr) auto auto;
        grid-template-areas: 'ink' 'head' 'meta';
        overflow: hidden;
        box-sizing: border-box;
        font-family: var(--font-chrome);
        color: var(--chrome);
        background-color: var(--paper);
        background-image:
          linear-gradient(var(--grid) 1px, transparent 1px),
          linear-gradient(90deg, var(--grid) 1px, transparent 1px);
        background-size: 0.75rem 0.75rem;

        --type-ratio: 1.25;
        --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
        --type-base: clamp(
          0.625rem,
          calc(0.1875rem + 2.2cqi + 1cqb - 0.6 * var(--ar)),
          1.125rem
        );
        --fit-meta-size: max(
          0.5rem,
          calc(var(--type-base) / var(--type-ratio))
        );
        --fit-headline-size: max(
          0.75rem,
          calc(var(--type-base) * pow(var(--type-ratio), 2))
        );
        --fit-pad: clamp(0.3125rem, calc(0.125rem + 1.8cqi), 0.75rem);
      }
      .r-ink,
      .r-head,
      .r-meta {
        overflow: hidden;
        min-height: 0;
      }
      .r-ink {
        grid-area: ink;
        position: relative;
      }
      .r-ink > svg {
        width: 100%;
        height: 100%;
      }
      .r-ink path {
        fill: none;
        stroke: var(--ink);
        stroke-linecap: round;
        stroke-linejoin: round;
      }
      .mark-ink {
        stroke-width: 2.4;
      }
      /* raised to out-specify `.r-ink path` (0,1,1) rather than !important */
      .r-ink path.mark-lasso {
        stroke: var(--echo);
        stroke-width: 2;
        stroke-dasharray: 7 6;
      }
      .echo-badge {
        position: absolute;
        right: 0;
        top: 0;
        background-color: var(--echo);
        color: var(--paper-raised);
        font-size: max(
          0.4375rem,
          calc(var(--type-base) / pow(var(--type-ratio), 2))
        );
        font-weight: 600;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        padding: 0.1875rem 0.375rem;
      }
      .slip-chip {
        position: absolute;
        right: 6%;
        bottom: 8%;
        max-width: 70%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        background-color: var(--paper-raised);
        border: 1px solid color-mix(in oklch, var(--edge) 30%, var(--paper));
        box-shadow: 0 3px 8px
          color-mix(in oklch, var(--chrome) 20%, transparent);
        padding: 0.125rem 0.5rem;
        transform: rotate(1.6deg);
        font-family: var(--font-hand);
        font-size: max(0.6875rem, var(--type-base));
        color: var(--echo);
      }
      .r-head {
        grid-area: head;
        padding: 0.125rem var(--fit-pad) 0;
        border-top: 1.5px solid var(--ink);
        background-color: var(--paper);
      }
      .name {
        font-family: var(--font-hand);
        font-size: var(--fit-headline-size);
        line-height: 1.15;
        color: var(--ink);
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 1;
        overflow: hidden;
        margin: 0;
      }
      .r-meta {
        grid-area: meta;
        margin: 0;
        padding: 0.0625rem var(--fit-pad) var(--fit-pad);
        display: flex;
        gap: 0.375rem;
        font-size: var(--fit-meta-size);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--chrome-soft);
        background-color: var(--paper);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .r-meta dt {
        display: inline;
      }
      .r-meta dt::after {
        content: ':';
      }
      .r-meta dd {
        display: inline;
        margin: 0;
      }
      .r-meta dd + dt {
        margin-left: 0.5rem;
      }
      .r-meta .meta-echo {
        color: var(--echo);
        font-weight: 600;
      }

      /* badge: the mark only, no meta */
      @container card (width <= 9.375rem) and (height <= 10.5625rem) {
        .r-meta,
        .echo-badge {
          display: none;
        }
        .fit {
          grid-template-rows: minmax(0, 1fr) auto;
          grid-template-areas: 'ink' 'head';
        }
        .slip-chip {
          display: none;
        }
      }

      /* under ~4.125rem tall the chip truncates to noise — drop it */
      @container card (height <= 4.125rem) {
        .slip-chip {
          display: none;
        }
      }

      /* strip: short & wide — ink thumb beside text */
      @container card (width > 9.375rem) and (height <= 10.5625rem) {
        .fit {
          grid-template-columns: minmax(3.5rem, 30%) 1fr;
          grid-template-rows: minmax(0, 1fr) auto;
          grid-template-areas: 'ink head' 'ink meta';
        }
        .r-ink {
          border-right: 1px solid var(--grid);
        }
        .r-head {
          border-top: none;
          align-self: end;
        }
        .echo-badge {
          display: none;
        }
      }

      /* card tier: ink zone left, panel right */
      @container card (width >= 25rem) and (height >= 10.625rem) {
        .fit {
          grid-template-columns: minmax(0, 1.5fr) minmax(12.5rem, 1fr);
          grid-template-rows: minmax(0, 1fr) auto;
          grid-template-areas: 'ink head' 'ink meta';
        }
        .r-ink {
          border-right: 1.5px solid
            color-mix(in oklch, var(--ink) 40%, transparent);
        }
        .r-head {
          border-top: none;
          padding-top: var(--fit-pad);
          align-self: start;
        }
        .name {
          -webkit-line-clamp: 2;
          white-space: normal;
        }
        .r-meta {
          align-self: end;
          white-space: normal;
          line-height: 1.9;
        }
      }
    </style>
  </template>
}
