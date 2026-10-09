import GlimmerComponent from '@glimmer/component';
import { Chip } from '@cardstack/pretui/components/chip';

import { stateColor } from '@cardstack/catalog/components/state-pill';
import {
  SEVERITY_HUE,
  SEVERITY_LABELS,
  SEVERITY_RANK,
} from '../severity-vocabulary';

interface Signature {
  Args: {
    level?: string | null;
    /** How many findings carry this severity; rendered as a trailing count. */
    count?: number | null;
    /** Meter and count only — for table cells and fitted tiles. */
    compact?: boolean;
  };
  Element: HTMLElement;
}

// Severity is read from across a room, so it is the one place an audit view
// spends saturated colour — and the three-segment meter carries the rank
// on its own, so the badge still reads when colour does not.
//
// The chrome is Pret UI's `Chip`, set to StatePill's checked recipe (14% fill,
// 62% foreground ink). Critical is the solid `--destructive` fill with its own
// `--destructive-foreground`, the pair the theme guarantees to read.
export class SeverityBadge extends GlimmerComponent<Signature> {
  get level() {
    return this.args.level ?? '';
  }
  get known() {
    return this.level in SEVERITY_RANK;
  }
  get rank() {
    return SEVERITY_RANK[this.level] ?? 0;
  }
  get label() {
    return SEVERITY_LABELS[this.level] ?? this.level;
  }
  get segments() {
    return [1, 2, 3].map((n) => n <= this.rank);
  }
  get isCritical() {
    return this.level === 'critical';
  }
  // Critical paints its own fill, so it takes no hue.
  get hue() {
    return this.isCritical
      ? undefined
      : stateColor(SEVERITY_HUE[this.level] ?? 'slate').ring;
  }
  get title() {
    let base = `Severity: ${this.label}`;
    return this.args.count != null ? `${base} (${this.args.count})` : base;
  }

  <template>
    {{#if this.known}}
      <Chip
        class='severity-badge
          {{if @compact "compact"}}
          {{if this.isCritical "critical"}}'
        @hue={{this.hue}}
        @dot={{false}}
        title={{this.title}}
        ...attributes
      >
        <span class='meter' aria-hidden='true'>
          {{#each this.segments as |on|}}
            <i class='seg {{if on "on"}}'></i>
          {{/each}}
        </span>
        {{! compact hides the word, not its meaning: the meter is decorative }}
        <span class={{if @compact 'boxel-sr-only'}}>{{this.label}}</span>
        {{#if @count}}
          <span class='count'>{{@count}}</span>
        {{/if}}
      </Chip>
    {{/if}}

    <style scoped>
      /* Chip sits in a lower cascade layer, so these plain rules win. */
      .severity-badge {
        --pretui-chip-mix: 14%;
        --pretui-ink-mix: 62%;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.02em;
      }
      .critical {
        background-color: var(--destructive);
        color: var(--destructive-foreground);
        box-shadow: none;
      }
      .compact {
        padding-inline: 0.4em;
      }
      .meter {
        display: inline-flex;
        gap: var(--boxel-sp-6xs);
        align-items: center;
      }
      .seg {
        display: inline-block;
        width: 0.25rem;
        height: 0.5625rem;
        border-radius: 0.0625rem;
        background-color: currentColor;
        opacity: 0.28;
      }
      .seg.on {
        opacity: 1;
      }
      .count {
        font-variant-numeric: tabular-nums;
        opacity: 0.75;
      }
    </style>
  </template>
}

export default SeverityBadge;
