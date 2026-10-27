// Pretui — Chip: a compact label, muted or outlined in a tone; @hue colors the dot.
import Component from '@glimmer/component';
import { hueStyle } from '../internal/ink';
import {
  PRETUI_TONES,
  resolveTone,
  type PretuiTone,
  type PretuiToneArg,
} from '../pretui-primitives';

export interface ChipSignature {
  Args: {
    label?: string;
    /** the dot's color */
    hue?: string;
    /** neutral (the default) is the muted pill; any other tone is outlined in
     * that tone, with its -ink as the text */
    tone?: PretuiToneArg;
    dot?: boolean;
  };
  Blocks: { default: [] };
  Element: HTMLSpanElement;
}

export class Chip extends Component<ChipSignature> {
  get showDot() {
    return this.args.dot ?? true;
  }
  get tone(): PretuiTone {
    return resolveTone(this.args.tone, PRETUI_TONES, 'neutral');
  }
  get style() {
    return hueStyle('--pretui-chip-hue', this.args.hue);
  }
  <template>
    <span
      class='pretui-chip'
      style={{this.style}}
      data-tone={{this.tone}}
      data-test-pretui-chip
      ...attributes
    >
      {{#if this.showDot}}<span class='pretui-chip-dot'></span>{{/if}}
      <span class='pretui-chip-label'>{{#if
          @label
        }}{{@label}}{{else}}{{yield}}{{/if}}</span>
    </span>
    <style scoped>
      @layer PretComponent {
        .pretui-chip {
          --pretui-chip-hue: var(--muted-foreground);
          --pretui-chip-height: auto;
          --pretui-chip-dot-size: var(--boxel-sp-3xs);

          display: inline-flex;
          align-items: center;
          gap: var(--boxel-sp-3xs);
          height: var(--pretui-chip-height);
          padding: var(--boxel-sp-6xs) var(--boxel-sp-xs);
          border-radius: var(--boxel-border-radius-xs);
          /* --text-ui-xs is the legacy size knob catalog chips still set */
          font-size: var(--pretui-chip-font-size, var(--boxel-font-size-xs));
          font-weight: 600;
          line-height: 1.5;
          letter-spacing: normal;
          white-space: nowrap;
          /* --pretui-chip-mix / --pretui-ink-mix are legacy knobs catalog chips
             still set: 0% / 100% (unset) resolve to plain --muted / --foreground */
          background-color: color-mix(
            in oklch,
            var(--pretui-chip-hue) var(--pretui-chip-mix, 0%),
            var(--muted)
          );
          color: color-mix(
            in oklch,
            var(--foreground) var(--pretui-ink-mix, 100%),
            var(--pretui-chip-hue)
          );
          /* the hue hairline legacy chips were drawn with: any
             --pretui-chip-mix above 0% shows it at full strength, and the
             default 0% leaves it transparent */
          box-shadow: 0 0 0 1px
            color-mix(
              in oklch,
              color-mix(in oklch, var(--pretui-chip-hue) 45%, var(--border))
                min(calc(var(--pretui-chip-mix, 0%) * 100), 100%),
              transparent
            );
        }
        /* a toned chip is outlined on --card: its -ink draws the text and the
           ring (the fill hue misses 3:1 as a ring), the dot takes the tone */
        .pretui-chip:not([data-tone='neutral']) {
          background-color: var(--card);
          box-shadow: inset 0 0 0 1px currentColor;
        }
        .pretui-chip[data-tone='primary'] {
          --pretui-chip-hue: var(--primary);

          color: var(--primary-ink);
        }
        .pretui-chip[data-tone='info'] {
          --pretui-chip-hue: var(--info);

          color: var(--info-ink);
        }
        .pretui-chip[data-tone='success'] {
          --pretui-chip-hue: var(--success);

          color: var(--success-ink);
        }
        .pretui-chip[data-tone='warning'] {
          --pretui-chip-hue: var(--warning);

          color: var(--warning-ink);
        }
        .pretui-chip[data-tone='danger'] {
          --pretui-chip-hue: var(--destructive);

          color: var(--destructive-ink);
        }
        .pretui-chip[data-tone='attention'] {
          --pretui-chip-hue: var(--attention);

          color: var(--attention-ink);
        }
        /* in a row too narrow for it, the chip ellipsizes instead of
           being cut: the label is its own box so it can shrink */
        .pretui-chip {
          max-inline-size: 100%;
          min-inline-size: 0;
          /* top, not baseline: inside a text line (a field atom's inline
             wrapper) baseline alignment leaves descender space under the
             chip and the line outgrows it; top keeps the line exactly
             chip-high */
          vertical-align: top;
        }
        .pretui-chip-label {
          min-inline-size: 0;
          overflow: hidden;
          text-overflow: ellipsis;
        }
        .pretui-chip-dot {
          width: var(--pretui-chip-dot-size);
          height: var(--pretui-chip-dot-size);
          border-radius: 50%;
          background-color: var(--pretui-chip-hue);
          flex: none;
        }
        /* Inside a small fitted card the chip compacts itself; no caller
           passes a density. Under 170 tall it drops its block padding, same
           12/600 text. */
        @container fitted-card (height < 170px) {
          .pretui-chip {
            padding-block: 0;
          }
        }
        /* Under 65 tall or 150 wide a pill frame costs more than it says, so
           the chip becomes dot + text. [data-tone] outranks the toned recipes. */
        @container fitted-card ((height < 65px) or (width < 150px)) {
          .pretui-chip[data-tone] {
            padding-inline: 0;
            background: none;
            box-shadow: none;
          }
        }
      }
    </style>
  </template>
}
