import GlimmerComponent from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { Chip } from '@cardstack/pretui/components/chip';

// The one place the fulfilment blocks decide how a lifecycle hue is allowed to
// render. A status hue arrives as data (a value on an options table, not a
// literal in a stylesheet) and is handed to Pret UI `Chip`, which derives the
// fill, the ring and the text from that single hue so they can never come
// apart. Chip mixes the hue into `--card` for the fill and mixes `--foreground`
// into the hue for the text, so the text flips with the theme in both light and
// dark. The chip runs on StatePill's checked recipe, 14% fill and 62% ink.

export type StatusStyle = {
  value: string;
  label: string;
  hue: string;
};

interface StatusChipSignature {
  Args: {
    hue?: string;
    label?: string;
    size?: 'small' | 'base';
  };
  Element: HTMLElement;
}

// A caller's `style` replaces the one Chip writes for `@hue`, so the hue
// travels in this style with the knobs. Only a hex colour or a single custom
// property reference passes; anything else falls back to the neutral.
const SAFE_HUE = /^(#[0-9a-fA-F]{3,8}|var\(--[A-Za-z0-9-]+\))$/;
const NEUTRAL = 'var(--muted-foreground)';

function statusHue(hue: string | undefined) {
  return hue && SAFE_HUE.test(hue) ? hue : NEUTRAL;
}

// Renders a lifecycle value as a Pret UI Chip, tinted by its hue. Consumers
// pass the hue; this component owns how a hue becomes colour.
export class StatusChip extends GlimmerComponent<StatusChipSignature> {
  get style() {
    let size = this.args.size === 'base' ? ' --text-ui-xs: 0.75rem;' : '';
    return htmlSafe(
      `--pretui-chip-hue: ${statusHue(this.args.hue)}; --pretui-chip-mix: 14%; --pretui-ink-mix: 62%; font-weight: 600;${size}`,
    );
  }

  <template>
    {{#if @label}}
      <Chip
        @dot={{false}}
        style={{this.style}}
        data-test-status-chip={{@label}}
        ...attributes
      >{{@label}}</Chip>
    {{/if}}
  </template>
}

export default StatusChip;
