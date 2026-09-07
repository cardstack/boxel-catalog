import GlimmerComponent from '@glimmer/component';
import { Pill } from '@cardstack/boxel-ui/components';

export interface StateColor {
  bg: string;
  fg: string;
  ring: string;
}

// A status hue has no semantic theme token (the shadcn set ships only
// --destructive), so hues come from boxel's design tokens. Boxel ships no
// orange and no plain blue; those two are mixed from tokens it does ship so a
// single token definition can still correct every hue globally.
const HUE = {
  green: 'var(--boxel-success)',
  red: 'var(--boxel-danger)',
  amber: 'var(--boxel-warning)',
  orange: 'color-mix(in oklch, var(--boxel-warning) 62%, var(--boxel-danger))',
  teal: 'var(--boxel-dark-teal)',
  purple: 'var(--boxel-purple)',
  blue: 'color-mix(in oklch, var(--boxel-purple) 55%, var(--boxel-highlight))',
  pink: 'color-mix(in oklch, var(--boxel-danger) 60%, var(--boxel-purple))',
  slate: 'var(--muted-foreground, var(--boxel-450))',
} as const;

export type Hue = keyof typeof HUE;

// One hue in, a checked pair out. Fill and text derive from the same hue and
// the card's own --card/--card-foreground pair, so a linked theme moves both
// together and no combination can drift out of contrast.
//
// 14% / 38% were computed against every hue above: 38% is the highest share
// that still clears 4.5:1 for the palest of them. Raising the hue share LOWERS
// contrast, because the card foreground in the mix supplies the darkness.
//
// `in oklab`, not `in oklch`: oklch interpolates the hue angle, and Chrome
// resolves an achromatic endpoint's hue as 0 (red), so on a white card
// `green 14% + white 86%` renders pink. oklab has no hue coordinate to rotate.
export function stateColor(hue: Hue): StateColor {
  let h = HUE[hue];
  return {
    bg: `color-mix(in oklab, ${h} 14%, var(--card, var(--boxel-light)))`,
    fg: `color-mix(in oklab, ${h} 38%, var(--card-foreground, var(--boxel-dark)))`,
    ring: h,
  };
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
        font: 'var(--muted-foreground, var(--boxel-450))',
        border: 'transparent',
      };
    }
    if (this.args.emphatic) {
      return {
        background: ring,
        font: 'var(--background, var(--boxel-light))',
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
        --boxel-pill-border-radius: 3px;
        --boxel-pill-font: 600 var(--boxel-font-size-xs) / 1.45
          var(--font-sans, var(--boxel-font-family));
        --boxel-lsp-xs: 0;
        max-width: 100%;
        white-space: nowrap;
      }
      .state-chrome {
        --boxel-pill-padding: 0.1em 0;
        --boxel-pill-font: 500 var(--boxel-font-size-xs) / 1.45
          var(--font-sans, var(--boxel-font-family));
      }
      .state-dot {
        width: 5px;
        height: 5px;
        flex: none;
        border-radius: 50%;
        background: currentColor;
      }
      .state-label {
        overflow: hidden;
        text-overflow: ellipsis;
      }
    </style>
  </template>
}

export default StatePill;
