import { Component } from '@cardstack/base/card-api';

import { parseInk, strokeBBox, unionBBox, type InkDoc } from '../utils/index';
import type { EchoPad } from '../echo-pad';

function inkPaths(doc: InkDoc): { d: string; w: number }[] {
  return doc.strokes.map((s) => {
    let d = `M ${s.pts[0]} ${s.pts[1]}`;
    for (let i = 2; i < s.pts.length; i += 2) {
      d += ` L ${s.pts[i]} ${s.pts[i + 1]}`;
    }
    return { d, w: s.w };
  });
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

  get themed(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
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
    <div class='ep-embedded {{if this.themed "themed"}}'>
      <div class='ink'>
        {{#if this.ink.paths.length}}
          <svg viewBox={{this.ink.viewBox}} preserveAspectRatio='xMidYMid meet'>
            {{#each this.ink.paths as |p|}}
              <path d={{p.d}} stroke-width='4' />
            {{/each}}
          </svg>
        {{else}}
          <svg viewBox='0 0 96 74' class='mark'>
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
        <div class='name'>{{if
            @model.title
            @model.title
            'Untitled board'
          }}</div>
        <div class='sum'>
          {{#if this.echoCount}}
            Handwritten board with accepted echoes — circle ink and the answer
            arrives beside it.
          {{else}}
            Handwritten board awaiting its first echo — circle ink and the
            answer arrives beside it.
          {{/if}}
        </div>
        <div class='meta'>{{this.strokeCount}}
          strokes ·
          <b>{{this.echoLabel}}</b></div>
      </div>
    </div>
    <style scoped>
      .ep-embedded {
        --paper: var(--ep-paper, #f7f4ec);
        --paper-raised: var(--ep-paper-raised, #fffdf5);
        --ink: var(--ep-ink, #2b3f8c);
        --echo: var(--ep-echo, #c33d2e);
        --chrome: var(--ep-chrome, #3a3527);
        --chrome-soft: var(--ep-chrome-soft, #6d6753);
        --edge: var(--ep-edge, #56503f);
        --grid: var(--ep-grid, rgba(90, 120, 160, 0.14));
        --font-chrome: var(--ep-font-chrome, 'IBM Plex Mono', monospace);
        --font-hand: var(--ep-font-hand, 'Caveat', cursive);
        display: flex;
        height: 100%;
        min-height: 110px;
        font-family: var(
          --ep-font-chrome,
          var(--font-mono, 'IBM Plex Mono', monospace)
        );
        color: var(--chrome);
        background-color: var(--paper);
        background-image:
          linear-gradient(
            var(--ep-grid, rgba(90, 120, 160, 0.14)) 1px,
            transparent 1px
          ),
          linear-gradient(
            90deg,
            var(--ep-grid, rgba(90, 120, 160, 0.14)) 1px,
            transparent 1px
          );
        background-size: 14px 14px;
      }
      .ink {
        position: relative;
        flex: none;
        width: 34%;
        max-width: 170px;
        min-width: 110px;
        border-right: 1px solid rgba(90, 120, 160, 0.3);
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
      .mark-lasso {
        stroke: var(--echo) !important;
        stroke-width: 2;
        stroke-dasharray: 7 6;
      }
      .slip-chip {
        position: absolute;
        right: 6px;
        bottom: 10px;
        max-width: 84%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        background: var(--paper-raised);
        border: 1px solid #eae4d2;
        box-shadow: 0 3px 8px rgba(50, 40, 20, 0.2);
        padding: 3px 8px;
        transform: rotate(1.6deg);
        font-family: var(--font-hand);
        font-size: 13px;
        color: var(--echo);
      }
      .body {
        position: relative;
        flex: 1;
        min-width: 0;
        padding: 14px 16px;
      }
      .eyebrow {
        font-size: 7.5px;
        font-weight: 600;
        letter-spacing: 0.24em;
        text-transform: uppercase;
        color: var(--echo);
      }
      .name {
        font-family: var(--font-hand);
        font-size: 28px;
        line-height: 1.05;
        color: var(--ink);
        margin-top: 6px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sum {
        font-size: 9.5px;
        line-height: 1.7;
        color: var(--chrome-soft);
        margin-top: 6px;
        display: -webkit-box;
        -webkit-box-orient: vertical;
        -webkit-line-clamp: 2;
        overflow: hidden;
      }
      .meta {
        margin-top: 8px;
        font-size: 8.5px;
        letter-spacing: 0.14em;
        text-transform: uppercase;
        color: var(--chrome-soft);
      }
      .meta b {
        color: var(--echo);
      }

      /* semantic tier only when a Theme card is linked */
      .ep-embedded.themed,
      .themed .fit {
        --paper: var(--ep-paper, var(--background, #f7f4ec));
        --paper-raised: var(--ep-paper-raised, var(--card, #fffdf5));
        --ink: var(--ep-ink, var(--primary, #2b3f8c));
        --echo: var(--ep-echo, var(--accent, #c33d2e));
        --chrome: var(--ep-chrome, var(--foreground, #3a3527));
        --chrome-soft: var(--ep-chrome-soft, var(--muted-foreground, #6d6753));
        --edge: var(--ep-edge, var(--border, #56503f));
        --font-chrome: var(
          --ep-font-chrome,
          var(--font-mono, 'IBM Plex Mono', monospace)
        );
      }
    </style>
  </template>
}

export class EchoPadFitted extends Component<typeof EchoPad> {
  get ink(): InkGlance {
    return new InkGlance(this.args.model?.inkJson);
  }

  get themed(): boolean {
    return Boolean((this.args.model as any)?.cardInfo?.theme);
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
    <div class='cq {{if this.themed "themed"}}'>
      <div class='fit'>
        <div class='r-ink'>
          {{#if this.ink.paths.length}}
            <svg
              viewBox={{this.ink.viewBox}}
              preserveAspectRatio='xMidYMid meet'
            >
              {{#each this.ink.paths as |p|}}
                <path d={{p.d}} stroke-width='4' />
              {{/each}}
            </svg>
          {{else}}
            <svg viewBox='0 0 96 74' preserveAspectRatio='xMidYMid meet'>
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
          <div class='name'>{{if @model.title @model.title 'Echo Pad'}}</div>
        </div>
        <div class='r-meta'>
          <span>{{this.strokeCount}}
            strokes ·
            <b>{{this.echoLabel}}</b></span>
        </div>
      </div>
    </div>
    <style scoped>
      .cq {
        container-type: size;
        container-name: card;
        width: 100%;
        height: 100%;
        overflow: hidden;
      }
      .fit {
        --paper: var(--ep-paper, #f7f4ec);
        --paper-raised: var(--ep-paper-raised, #fffdf5);
        --ink: var(--ep-ink, #2b3f8c);
        --echo: var(--ep-echo, #c33d2e);
        --chrome: var(--ep-chrome, #3a3527);
        --chrome-soft: var(--ep-chrome-soft, #6d6753);
        --edge: var(--ep-edge, #56503f);
        --grid: var(--ep-grid, rgba(90, 120, 160, 0.14));
        --font-chrome: var(--ep-font-chrome, 'IBM Plex Mono', monospace);
        --font-hand: var(--ep-font-hand, 'Caveat', cursive);
        width: 100%;
        height: 100%;
        display: grid;
        grid-template-rows: minmax(0, 1fr) auto auto;
        grid-template-areas: 'ink' 'head' 'meta';
        overflow: hidden;
        box-sizing: border-box;
        font-family: var(
          --ep-font-chrome,
          var(--font-mono, 'IBM Plex Mono', monospace)
        );
        color: var(--chrome);
        background-color: var(--paper);
        background-image:
          linear-gradient(
            var(--ep-grid, rgba(90, 120, 160, 0.14)) 1px,
            transparent 1px
          ),
          linear-gradient(
            90deg,
            var(--ep-grid, rgba(90, 120, 160, 0.14)) 1px,
            transparent 1px
          );
        background-size: 12px 12px;

        --type-ratio: 1.25;
        --ar: calc(max(1cqi, 1cqb) - min(1cqi, 1cqb));
        --type-base: clamp(
          10px,
          calc(3px + 2.2cqi + 1cqb - 0.6 * var(--ar)),
          18px
        );
        --fit-meta-size: max(8px, calc(var(--type-base) / var(--type-ratio)));
        --fit-headline-size: max(
          12px,
          calc(var(--type-base) * pow(var(--type-ratio), 2))
        );
        --fit-pad: clamp(5px, calc(2px + 1.8cqi), 12px);
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
      .mark-lasso {
        stroke: var(--echo) !important;
        stroke-width: 2;
        stroke-dasharray: 7 6;
      }
      .echo-badge {
        position: absolute;
        right: 0;
        top: 0;
        background: var(--echo);
        color: var(--paper-raised);
        font-size: max(7px, calc(var(--type-base) / pow(var(--type-ratio), 2)));
        font-weight: 600;
        letter-spacing: 0.16em;
        text-transform: uppercase;
        padding: 3px 6px;
      }
      .slip-chip {
        position: absolute;
        right: 6%;
        bottom: 8%;
        max-width: 70%;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        background: var(--paper-raised);
        border: 1px solid #eae4d2;
        box-shadow: 0 3px 8px rgba(50, 40, 20, 0.2);
        padding: 2px 8px;
        transform: rotate(1.6deg);
        font-family: var(--font-hand);
        font-size: max(11px, var(--type-base));
        color: var(--echo);
      }
      .r-head {
        grid-area: head;
        padding: 2px var(--fit-pad) 0;
        border-top: 1.5px solid var(--ink);
        background: var(--paper);
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
        padding: 1px var(--fit-pad) var(--fit-pad);
        font-size: var(--fit-meta-size);
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--chrome-soft);
        background: var(--paper);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .r-meta b {
        color: var(--echo);
      }

      /* badge: the mark only, no meta */
      @container card (width <= 150px) and (height <= 169px) {
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

      /* under ~66px tall the chip truncates to noise — drop it */
      @container card (height <= 66px) {
        .slip-chip {
          display: none;
        }
      }

      /* strip: short & wide — ink thumb beside text */
      @container card (width > 150px) and (height <= 169px) {
        .fit {
          grid-template-columns: minmax(56px, 30%) 1fr;
          grid-template-rows: minmax(0, 1fr) auto;
          grid-template-areas: 'ink head' 'ink meta';
        }
        .r-ink {
          border-right: 1px solid rgba(90, 120, 160, 0.3);
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
      @container card (width >= 400px) and (height >= 170px) {
        .fit {
          grid-template-columns: minmax(0, 1.5fr) minmax(200px, 1fr);
          grid-template-rows: minmax(0, 1fr) auto;
          grid-template-areas: 'ink head' 'ink meta';
        }
        .r-ink {
          border-right: 1.5px solid rgba(43, 63, 140, 0.4);
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

      /* semantic tier only when a Theme card is linked */
      .ep-embedded.themed,
      .themed .fit {
        --paper: var(--ep-paper, var(--background, #f7f4ec));
        --paper-raised: var(--ep-paper-raised, var(--card, #fffdf5));
        --ink: var(--ep-ink, var(--primary, #2b3f8c));
        --echo: var(--ep-echo, var(--accent, #c33d2e));
        --chrome: var(--ep-chrome, var(--foreground, #3a3527));
        --chrome-soft: var(--ep-chrome-soft, var(--muted-foreground, #6d6753));
        --edge: var(--ep-edge, var(--border, #56503f));
        --font-chrome: var(
          --ep-font-chrome,
          var(--font-mono, 'IBM Plex Mono', monospace)
        );
      }
    </style>
  </template>
}
