import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

import { stateColor, type Hue } from '@cardstack/catalog/components/state-pill';

export interface DashboardTile {
  label: string;
  value: string | number;
  /** 'neutral' | a Hue name — semantic state, separate from the accent. */
  intent?: Hue | 'neutral';
  /** Small print under the value. */
  detail?: string;
  /** Every tile that reports a set is a DOOR into that set. */
  onOpen?: () => void;
}

interface Signature {
  Args: {
    tiles: DashboardTile[];
    /** Minimum tile width; the grid auto-fits. Default '9rem'. */
    tileMin?: string;
  };
  Element: HTMLElement;
}

/**
 * The generic metric-grid primitive. It renders tiles and knows no domain:
 * the host decides what each tile counts and what opening it does.
 *
 * The rule it enforces: a tile with an `onOpen` renders as a real BUTTON with
 * a static open cue and hover/focus states — a wall where every number is a
 * door, not a brochure. Tiles without `onOpen` render as plain facts.
 */
export class Dashboard extends GlimmerComponent<Signature> {
  get tiles() {
    return this.args.tiles ?? [];
  }

  intentStyle = (tile: DashboardTile) => {
    if (!tile.intent || tile.intent === 'neutral') return '';
    let c = stateColor(tile.intent);
    return `--tile-accent: ${c.ring};`;
  };

  tileStyle = (tile: DashboardTile, i: number) =>
    `${this.intentStyle(tile)} --i: ${i};`;

  get minWidth() {
    return this.args.tileMin ?? '9rem';
  }

  <template>
    <div
      class='dash'
      style='grid-template-columns: repeat(auto-fit, minmax({{this.minWidth}}, 1fr));'
      ...attributes
    >
      {{#each this.tiles as |tile idx|}}
        {{#if tile.onOpen}}
          <button
            type='button'
            class='tile tile-door'
            style={{this.tileStyle tile idx}}
            {{on 'click' (fn this.openTile tile)}}
          >
            <b class='tile-value'>{{tile.value}}</b>
            <span class='tile-label'>{{tile.label}}</span>
            {{#if tile.detail}}<span
                class='tile-detail'
              >{{tile.detail}}</span>{{/if}}
            <span class='tile-cue' aria-hidden='true'>›</span>
          </button>
        {{else}}
          <div class='tile' style={{this.tileStyle tile idx}}>
            <b class='tile-value'>{{tile.value}}</b>
            <span class='tile-label'>{{tile.label}}</span>
            {{#if tile.detail}}<span
                class='tile-detail'
              >{{tile.detail}}</span>{{/if}}
          </div>
        {{/if}}
      {{/each}}
    </div>
    <style scoped>
      .dash {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .tile {
        position: relative;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
        text-align: left;
        border: 1px solid transparent;
        border-radius: var(--boxel-border-radius);
        background: var(--card, var(--boxel-light));
        color: var(--card-foreground, var(--boxel-dark));
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        min-width: 0;
        box-shadow: 0 1px 0
          color-mix(
            in oklab,
            var(--foreground, var(--boxel-dark)) 5%,
            transparent
          );
        animation: tile-in 420ms cubic-bezier(0.22, 1, 0.36, 1) both;
        animation-delay: calc(var(--i, 0) * 50ms);
      }
      .tile-door {
        cursor: pointer;
        transition:
          transform 160ms cubic-bezier(0.22, 1, 0.36, 1),
          border-color 160ms ease-out,
          box-shadow 160ms ease-out;
      }
      .tile-door:hover,
      .tile-door:focus-visible {
        transform: translateY(-1px);
        border-color: color-mix(
          in oklab,
          var(--tile-accent, var(--primary, var(--boxel-highlight))) 45%,
          transparent
        );
        box-shadow: 0 8px 20px -12px
          color-mix(
            in oklab,
            var(--foreground, var(--boxel-dark)) 45%,
            transparent
          );
      }
      @keyframes tile-in {
        from {
          opacity: 0;
          transform: translateY(8px);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      .tile-door:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: 2px;
      }
      .tile-value {
        font-size: var(--boxel-font-size-xl);
        font-weight: 600;
        font-variant-numeric: tabular-nums;
        line-height: 1.1;
        color: var(--tile-accent, var(--card-foreground, var(--boxel-dark)));
      }
      .tile-label {
        font-size: var(--boxel-font-size-xs);
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--muted-foreground, var(--boxel-450));
      }
      .tile-detail {
        font-size: var(--boxel-font-size-xs);
        color: var(--muted-foreground, var(--boxel-450));
      }
      .tile-cue {
        position: absolute;
        top: var(--boxel-sp-xs);
        right: var(--boxel-sp-xs);
        color: var(--muted-foreground, var(--boxel-450));
        font-size: var(--boxel-font-size);
        transition: transform 120ms ease-out;
      }
      .tile-door:hover .tile-cue,
      .tile-door:focus-visible .tile-cue {
        transform: translateX(2px);
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          animation: none;
        }
        .tile-door,
        .tile-cue {
          transition: none;
        }
        .tile-door:hover .tile-cue {
          transform: none;
        }
      }
    </style>
  </template>

  openTile = (tile: DashboardTile) => {
    tile.onOpen?.();
  };
}

export default Dashboard;
