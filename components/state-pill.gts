import GlimmerComponent from '@glimmer/component';
import { Pill } from '@cardstack/boxel-ui/components';

export interface StateColor {
  bg: string;
  fg: string;
  ring: string;
}

// The status hues read the theme's status tokens, so a linked theme restyles
// them; orange sits between warning and destructive and follows both. The
// category hues (teal, purple, blue, pink, gold, bronze) have no contract
// token and come only from boxel's fixed palette, so a theme never moves them.
const HUE = {
  green: 'var(--success)',
  red: 'var(--destructive)',
  amber: 'var(--warning)',
  orange: 'color-mix(in oklch, var(--warning) 62%, var(--destructive))',
  teal: 'var(--boxel-dark-teal)',
  purple: 'var(--boxel-purple)',
  blue: 'color-mix(in oklch, var(--boxel-purple) 55%, var(--boxel-highlight))',
  pink: 'color-mix(in oklch, var(--boxel-danger) 60%, var(--boxel-purple))',
  slate: 'var(--muted-foreground)',
  // Metal hues for tiers and ranks (bronze / gold). They are categories, not
  // statuses, so they stay on the fixed palette like the other category hues:
  // a tier ladder must not turn into warning colours under a theme.
  gold: 'color-mix(in oklch, var(--boxel-yellow) 55%, var(--boxel-amber))',
  bronze: 'color-mix(in oklch, var(--boxel-orange) 65%, var(--boxel-dark))',
} as const;

export type Hue = keyof typeof HUE;

// Text for the solid (emphatic) fill. A status hue takes its fill's paired
// foreground from the theme; orange is mostly warning, so it takes warning's.
// The category hues have no pair and keep the inverse of the page.
const EMPHATIC_FOREGROUND: Partial<Record<Hue, string>> = {
  green: 'var(--success-foreground)',
  red: 'var(--destructive-foreground)',
  amber: 'var(--warning-foreground)',
  orange: 'var(--warning-foreground)',
  // Fixed metal fills take fixed ink: dark on gold (10.6:1), light on bronze
  // (7.0:1).
  gold: 'var(--boxel-dark)',
  bronze: 'var(--boxel-light)',
};

// One hue in, a checked pair out. Fill and text derive from the same hue and
// the card's own --card/--card-foreground pair, so a linked theme moves both
// together and no combination can drift out of contrast.
//
// 14% / 38% were computed against every hue above: 38% is the highest share
// that still clears 4.5:1 for the palest of them. Raising the hue share LOWERS
// contrast, because the card foreground in the mix supplies the darkness.
//
// `in oklab`, not `in oklch`: oklch interpolates the hue angle, so on a
// tinted card a 14% tint keeps mostly the card's hue (purple over cream turns
// orange). oklab mixes in a straight line and the tint keeps its own hue.
export function stateColor(hue: Hue): StateColor {
  let h = HUE[hue];
  return {
    bg: `color-mix(in oklab, ${h} 14%, var(--card))`,
    fg: `color-mix(in oklab, ${h} 38%, var(--card-foreground))`,
    ring: h,
  };
}

export const DEFAULT_STATE_COLOR: StateColor = stateColor('slate');

/** Look a value up in a card's own state→colour map; unknown or empty values get the neutral slate. */
export function stateColorOf(
  map: Record<string, StateColor>,
  key?: string | null,
): StateColor {
  return (key && map[key]) || DEFAULT_STATE_COLOR;
}

interface Signature {
  Args: {
    label?: string | null;
    hue?: Hue;
    /** Solid fill instead of the 14% dilution. Reserve it for one state. */
    emphatic?: boolean;
    /** Leading dot. Off in tight rows where the label alone must fit. */
    dot?: boolean;
    /**
     * Chrome, not signal: plain muted text with no fill. A status name or a
     * type is parsed once; a priority or an SLA state is scanned for. Painting
     * both costs the second group its advantage.
     */
    chrome?: boolean;
  };
  Element: HTMLElement;
}

/**
 * A small state label whose colour is derived, never stored. The chrome is
 * boxel-ui's `Pill`; only the hue derivation lives here.
 */
export class StatePill extends GlimmerComponent<Signature> {
  get colors() {
    return stateColor(this.args.hue ?? 'slate');
  }

  get colorArgs() {
    let { bg, fg, ring } = this.colors;
    if (this.args.chrome) {
      return {
        background: 'transparent',
        font: 'var(--muted-foreground)',
        border: 'transparent',
      };
    }
    if (this.args.emphatic) {
      return {
        background: ring,
        font:
          EMPHATIC_FOREGROUND[this.args.hue ?? 'slate'] ?? 'var(--background)',
        border: ring,
      };
    }
    return { background: bg, font: fg, border: bg };
  }

  <template>
    {{#if @label}}
      <Pill
        class='state-pill {{if @chrome "state-chrome"}}'
        @pillBackgroundColor={{this.colorArgs.background}}
        @pillFontColor={{this.colorArgs.font}}
        @pillBorderColor={{this.colorArgs.border}}
        ...attributes
      >
        <:default>
          {{#if @dot}}<span class='state-dot'></span>{{/if}}
          <span class='state-label'>{{@label}}</span>
        </:default>
      </Pill>
    {{/if}}

    <style scoped>
      /* Denser than Pill's default: forty of these share one queue row. */
      .state-pill {
        --boxel-pill-gap: 0.25rem;
        --boxel-pill-padding: 0.1em 0.45em;
        --boxel-pill-border-radius: var(--boxel-border-radius-xs);
        --boxel-pill-font: 600 var(--boxel-ui-label-font-size) /
          var(--boxel-ui-label-line-height) var(--boxel-ui-label-font-family);
        --boxel-lsp-xs: var(--boxel-ui-label-letter-spacing);
        max-width: 100%;
        white-space: nowrap;
      }
      .state-chrome {
        --boxel-pill-padding: 0.1em 0;
        --boxel-pill-font: var(--boxel-ui-label-font-weight)
          var(--boxel-ui-label-font-size) / var(--boxel-ui-label-line-height)
          var(--boxel-ui-label-font-family);
      }
      .state-dot {
        width: 0.3125rem;
        height: 0.3125rem;
        flex: none;
        border-radius: 50%;
        background-color: currentColor;
      }
      .state-label {
        overflow: hidden;
        text-overflow: ellipsis;
      }
    </style>
  </template>
}

export default StatePill;
