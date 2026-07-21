import GlimmerComponent from '@glimmer/component';
import { htmlSafe } from '@ember/template';

export interface GeneratingOverlaySignature {
  Args: {
    // Optional accent colour for the sweeping border + shimmer. Defaults to the
    // host theme's highlight token. Any CSS colour works, e.g. '#e3c27d'.
    color?: string;
    // Optional status label rendered in the centre (e.g. 'Generating…').
    label?: string;
  };
  Element: HTMLDivElement;
  Blocks: { default: [] };
}

// A reusable "working…" skeleton: a rotating conic-gradient border sweep plus a
// shimmer wash, sized to fill its host box. Drop it in as a placeholder while an
// async result (an AI image, a generated plan, …) is on its way. Give the host
// box a size (width / aspect-ratio) via ...attributes or a wrapping element.
// Accent colour is theme-neutral by default (--boxel-highlight) and overridable
// with @color or the --generating-accent custom property.
export default class GeneratingOverlay extends GlimmerComponent<GeneratingOverlaySignature> {
  private get style() {
    return this.args.color
      ? htmlSafe(`--generating-accent: ${this.args.color};`)
      : undefined;
  }

  <template>
    <div class='generating' style={{this.style}} ...attributes>
      {{#if @label}}
        <span class='generating-label'>{{@label}}</span>
      {{/if}}
      {{yield}}
    </div>

    <style scoped>
      @property --generating-angle {
        syntax: '<angle>';
        initial-value: 0deg;
        inherits: false;
      }
      .generating {
        --generating-accent: var(--boxel-highlight, #00ebac);
        position: relative;
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 100%;
        height: 100%;
        min-height: 6rem;
        border-radius: var(--boxel-border-radius, 0.5rem);
        background: var(--boxel-100, #f8f7fa);
      }
      /* rotating conic-gradient border ring */
      .generating::before {
        content: '';
        position: absolute;
        inset: 0;
        padding: 3px;
        border-radius: inherit;
        background: conic-gradient(
          from var(--generating-angle, 0deg),
          transparent 0%,
          color-mix(in srgb, var(--generating-accent) 35%, transparent) 8%,
          var(--generating-accent) 16%,
          color-mix(in srgb, var(--generating-accent) 25%, white) 20%,
          var(--generating-accent) 24%,
          color-mix(in srgb, var(--generating-accent) 35%, transparent) 30%,
          transparent 38%
        );
        -webkit-mask:
          linear-gradient(#fff 0 0) content-box,
          linear-gradient(#fff 0 0);
        -webkit-mask-composite: xor;
        mask:
          linear-gradient(#fff 0 0) content-box,
          linear-gradient(#fff 0 0);
        mask-composite: exclude;
        animation: generating-sweep 2.4s linear infinite;
        pointer-events: none;
      }
      /* diagonal shimmer wash across the surface */
      .generating::after {
        content: '';
        position: absolute;
        inset: 0;
        background: linear-gradient(
          100deg,
          transparent 30%,
          color-mix(in srgb, var(--generating-accent) 14%, transparent) 50%,
          transparent 70%
        );
        transform: translateX(-100%);
        animation: generating-shimmer 1.6s ease-in-out infinite;
        pointer-events: none;
      }
      .generating-label {
        position: relative;
        z-index: 1;
        font-size: var(--boxel-font-size-xs, 0.75rem);
        font-weight: 600;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--boxel-450, #919191);
      }
      @keyframes generating-sweep {
        to {
          --generating-angle: 360deg;
        }
      }
      @keyframes generating-shimmer {
        to {
          transform: translateX(100%);
        }
      }
      @media (prefers-reduced-motion: reduce) {
        .generating::before,
        .generating::after {
          animation-duration: 6s;
        }
      }
    </style>
  </template>
}
