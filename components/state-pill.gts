import GlimmerComponent from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { Chip } from '@cardstack/pretui/components/chip';

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
  // "Needs a look": a waiting application, an ageing requisition, low stock.
  // Where `amber` reads as a status, `attention` is the theme's own hue for
  // work that wants someone's eye.
  attention: 'var(--attention)',
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

/** Every hue name, in the table's order: the one list to iterate instead of re-typing the names. */
export const STATE_HUES = Object.keys(HUE) as Hue[];

// Text for the solid (emphatic) fill. A status hue takes its fill's paired
// foreground from the theme; orange is mostly warning, so it takes warning's.
// Slate is the page's own muted ink, so it keeps the inverse of the page.
const EMPHATIC_FOREGROUND: Partial<Record<Hue, string>> = {
  green: 'var(--success-foreground)',
  red: 'var(--destructive-foreground)',
  amber: 'var(--warning-foreground)',
  attention: 'var(--attention-foreground)',
  orange: 'var(--warning-foreground)',
  // Fixed category fills take fixed ink, so the pair holds under any theme:
  // dark on teal (11.5:1), blue (8.6:1), pink (5.1:1) and gold (10.6:1); light
  // on purple (5.9:1) and bronze (7.0:1).
  teal: 'var(--boxel-dark)',
  blue: 'var(--boxel-dark)',
  pink: 'var(--boxel-dark)',
  gold: 'var(--boxel-dark)',
  purple: 'var(--boxel-light)',
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
  /**
   * Structured content for a pill of several styled parts (a key and its
   * label, a relation and its target). Rendered only when `@label` is empty,
   * with the same hue and recipe; the parts inherit the pill's ink, and the
   * pill's accessible text is the block's text.
   */
  Blocks: { default: [] };
  Element: HTMLElement;
}

/**
 * A small state label whose colour is derived, never stored. The chrome is
 * Pret UI's `Chip`; only the hue derivation lives here.
 *
 * Chip's own treatment mixes 20% hue into the fill and 34% foreground into the
 * ink, which leaves pale hues below 4.5:1 (amber 3.90 light, bronze 3.15 dark).
 * StatePill sets Chip's two knobs to its checked recipe instead, 14% fill and
 * 62% foreground ink, which clears 5.59:1 for every hue in both schemes. Chip
 * has no solid or unfilled mode, so `emphatic` and `chrome` set the fill, ink
 * and ring directly; every value comes from the hue tables above, never from
 * a caller.
 */
export class StatePill extends GlimmerComponent<Signature> {
  get hue(): string {
    return HUE[this.args.hue ?? 'slate'];
  }

  // Only the per-instance values travel inline: the hue, and for the solid
  // fill its paired ink. The treatments themselves are the scoped rules below.
  get style() {
    let hue = `--pretui-chip-hue: ${this.hue}`;
    if (this.args.emphatic && !this.args.chrome) {
      let ink =
        EMPHATIC_FOREGROUND[this.args.hue ?? 'slate'] ?? 'var(--background)';
      return htmlSafe(`${hue}; --state-pill-ink: ${ink}`);
    }
    return htmlSafe(hue);
  }

  get treatment(): string {
    if (this.args.chrome) {
      return 'chrome';
    }
    return this.args.emphatic ? 'emphatic' : 'tint';
  }

  <template>
    {{#if @label}}
      <Chip
        @dot={{if @dot true false}}
        class='state-pill {{this.treatment}}'
        style={{this.style}}
        ...attributes
      >
        <span class='state-label'>{{@label}}</span>
      </Chip>
    {{else if (has-block)}}
      <Chip
        @dot={{if @dot true false}}
        class='state-pill {{this.treatment}}'
        style={{this.style}}
        ...attributes
      >
        <span class='state-label'>{{yield}}</span>
      </Chip>
    {{/if}}

    <style scoped>
      /* Chip sits in a lower cascade layer, so these plain rules win. */
      .state-pill {
        max-width: 100%;
      }
      .tint {
        --pretui-chip-mix: 14%;
        --pretui-ink-mix: 62%;
      }
      .emphatic {
        --pretui-chip-mix: 100%;
        color: var(--state-pill-ink);
        box-shadow: none;
      }
      .chrome {
        background-color: transparent;
        color: var(--muted-foreground);
        box-shadow: none;
        padding-inline: 0;
      }
      .state-label {
        overflow: hidden;
        text-overflow: ellipsis;
      }
    </style>
  </template>
}

export default StatePill;
