import GlimmerComponent from '@glimmer/component';
import { Pill } from '@cardstack/boxel-ui/components';

import { stateColor } from '@cardstack/catalog/components/state-pill';
import {
  SEVERITY_HUE,
  SEVERITY_LABELS,
  SEVERITY_RANK,
} from '../fields/severity/severity-vocabulary';

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

// Severity is read from across a room, so it is the one place this app
// spends saturated colour — and the three-segment meter carries the rank
// on its own, so the badge still reads when colour does not.
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
  get colors() {
    return stateColor(SEVERITY_HUE[this.level] ?? 'slate');
  }
  get pillArgs() {
    let { bg, fg, ring } = this.colors;
    if (this.level === 'critical') {
      return {
        background: ring,
        font: 'var(--background, var(--boxel-light))',
        border: ring,
      };
    }
    return { background: bg, font: fg, border: bg };
  }
  get title() {
    let base = `Severity: ${this.label}`;
    return this.args.count != null ? `${base} (${this.args.count})` : base;
  }

  <template>
    {{#if this.known}}
      <Pill
        class='severity-badge {{if @compact "compact"}}'
        @pillBackgroundColor={{this.pillArgs.background}}
        @pillFontColor={{this.pillArgs.font}}
        @pillBorderColor={{this.pillArgs.border}}
        title={{this.title}}
        ...attributes
      >
        <:default>
          <span class='meter' aria-hidden='true'>
            {{#each this.segments as |on|}}
              <i class='seg {{if on "on"}}'></i>
            {{/each}}
          </span>
          {{#unless @compact}}
            <span class='label'>{{this.label}}</span>
          {{/unless}}
          {{#if @count}}
            <span class='count'>{{@count}}</span>
          {{/if}}
        </:default>
      </Pill>
    {{/if}}

    <style scoped>
      .severity-badge {
        --boxel-pill-gap: 0.35rem;
        --boxel-pill-padding: 0.1em 0.5em;
        --boxel-pill-border-radius: 3px;
        --boxel-pill-font: 700 var(--boxel-font-size-xs) / 1.45
          var(--font-sans, var(--boxel-font-family));
        --boxel-lsp-xs: 0.02em;
        text-transform: uppercase;
        white-space: nowrap;
      }
      .compact {
        --boxel-pill-padding: 0.1em 0.4em;
      }
      .meter {
        display: inline-flex;
        gap: 2px;
        align-items: center;
      }
      .seg {
        display: inline-block;
        width: 4px;
        height: 9px;
        border-radius: 1px;
        background: currentColor;
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
