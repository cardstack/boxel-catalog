import GlimmerComponent from '@glimmer/component';
import { on } from '@ember/modifier';
import { concat, fn } from '@ember/helper';
import { htmlSafe } from '@ember/template';
import { Stat } from '@cardstack/pretui/components/stat';

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
 * The rule it enforces: a tile with an `onOpen` carries a real BUTTON over
 * the whole tile, with a static open cue and hover/focus states — a wall
 * where every number is a door, not a brochure. Tiles without `onOpen`
 * render as plain facts. Each tile's number is a Pret UI `Stat`; the button
 * sits beside it rather than around it, because a button may only hold
 * phrasing content and `Stat` is a block.
 */
export class Dashboard extends GlimmerComponent<Signature> {
  get tiles() {
    return this.args.tiles ?? [];
  }

  // The ring hue marks the hover edge; the number takes the hue's checked
  // text mix, because the raw hue is too pale to read as text on a card.
  intentStyle = (tile: DashboardTile) => {
    if (!tile.intent || tile.intent === 'neutral') return '';
    let c = stateColor(tile.intent);
    return `--tile-accent: ${c.ring}; --tile-value-color: ${c.fg};`;
  };

  tileStyle = (tile: DashboardTile, i: number) =>
    htmlSafe(`${this.intentStyle(tile)} --i: ${i};`);

  get gridStyle() {
    let min = this.args.tileMin ?? '9rem';
    return htmlSafe(
      `grid-template-columns: repeat(auto-fit, minmax(${min}, 1fr));`,
    );
  }

  <template>
    <div class='dash' style={{this.gridStyle}} ...attributes>
      {{#each this.tiles as |tile idx|}}
        <div
          class='tile {{if tile.onOpen "tile-door"}}'
          style={{this.tileStyle tile idx}}
        >
          <Stat
            class='tile-stat'
            @label={{tile.label}}
            @value={{tile.value}}
            @hint={{tile.detail}}
            @roll={{false}}
          />
          {{#if tile.onOpen}}
            <button
              type='button'
              class='tile-open'
              aria-label='{{tile.label}}: {{tile.value}}{{if
                tile.detail
                (concat ". " tile.detail)
              }}'
              {{on 'click' (fn this.openTile tile)}}
            ><span class='tile-cue' aria-hidden='true'>›</span></button>
          {{/if}}
        </div>
      {{/each}}
    </div>
    <style scoped>
      .dash {
        display: grid;
        gap: var(--boxel-sp-xs);
      }
      .tile {
        /* Stat's hint reads --ink-3, which boxel's theme leaves at a pale
           grey; this points it at the muted ink for the detail line. */
        --ink-3: var(--muted-foreground);
        position: relative;
        border: 1px solid transparent;
        border-radius: var(--boxel-border-radius);
        background-color: var(--card);
        color: var(--card-foreground);
        padding: var(--boxel-sp-sm) var(--boxel-sp);
        min-width: 0;
        box-shadow: 0 1px 0
          color-mix(in oklab, var(--foreground) 5%, transparent);
        animation: tile-in 420ms cubic-bezier(0.22, 1, 0.36, 1) both;
        animation-delay: calc(var(--i, 0) * 50ms);
      }
      /* Stat's label and hint set their own muted ink, so the colour here
         reaches the number only. */
      .tile-stat {
        color: var(--tile-value-color, var(--card-foreground));
      }
      .tile-door {
        transition:
          transform 160ms cubic-bezier(0.22, 1, 0.36, 1),
          border-color 160ms ease-out,
          box-shadow 160ms ease-out;
      }
      .tile-door:hover,
      .tile-door:has(.tile-open:focus-visible) {
        transform: translateY(-1px);
        border-color: color-mix(
          in oklab,
          var(--tile-accent, var(--primary)) 45%,
          transparent
        );
        box-shadow: 0 0.5rem 1.25rem -0.75rem
          color-mix(in oklab, var(--foreground) 45%, transparent);
      }
      @keyframes tile-in {
        from {
          opacity: 0;
          transform: translateY(0.5rem);
        }
        to {
          opacity: 1;
          transform: none;
        }
      }
      /* The open button covers the whole tile, so the tile is one target
         and its focus ring traces the tile's edge. */
      .tile-open {
        position: absolute;
        inset: 0;
        padding: 0;
        border: none;
        border-radius: inherit;
        background-color: transparent;
        color: inherit;
        cursor: pointer;
      }
      .tile-open:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.125rem;
      }
      .tile-cue {
        position: absolute;
        top: var(--boxel-sp-xs);
        right: var(--boxel-sp-xs);
        color: var(--muted-foreground);
        font-size: var(--boxel-font-size);
        transition: transform 120ms ease-out;
      }
      .tile-door:hover .tile-cue,
      .tile-open:focus-visible .tile-cue {
        transform: translateX(0.125rem);
      }
      @media (prefers-reduced-motion: reduce) {
        .tile {
          animation: none;
        }
        .tile-door,
        .tile-cue {
          transition: none;
        }
        .tile-door:hover .tile-cue,
        .tile-open:focus-visible .tile-cue {
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
