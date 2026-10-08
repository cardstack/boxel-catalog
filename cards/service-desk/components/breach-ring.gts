import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { get } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { tracked } from '@glimmer/tracking';
import { registerDestructor } from '@ember/destroyable';

import {
  timerSnapshot,
  TIMER_HUE,
} from '@cardstack/catalog/cards/service-desk/utils/sla';
import { stateColor, type Hue } from '@cardstack/catalog/components/state-pill';
import { slaClock } from '@cardstack/catalog/cards/service-desk/utils/sla-clock';

interface Signature {
  Args: {
    /** The timer facts (SlaTimerField-shaped). The ring recomputes live. */
    facts?: any;
    /** Diameter in px. Default 20. */
    size?: number;
    /** Show the remaining label inside the ring (needs size ≥ 44). */
    labelled?: boolean;
  };
  Element: HTMLElement;
}

const R = 8;
const C = 2 * Math.PI * R; // 50.27

/**
 * The desk's SIGNATURE element: a thin clock ring that depletes toward
 * breach — time-to-breach readable from across the room, without a number.
 *
 * MOTION CONTRACT: on mount the arc draws from full to its value (600ms,
 * ease-out — the one entrance flourish, because it shows the clock is a
 * clock); thereafter the arc moves only as time passes (1s ticks, eased).
 * Under `prefers-reduced-motion` the arc is a snapshot: no draw-in, no
 * eased ticks.
 *
 * ACCESSIBILITY CONTRACT: the ring is `aria-hidden`; the countdown text
 * beside it (LiveClock) is the accessible truth.
 */
export class BreachRing extends GlimmerComponent<Signature> {
  @tracked mounted = false;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    slaClock.subscribe();
    // First paint at "full", then ease to the real value: the draw-in.
    // A paint callback on purpose: the arc must first paint at full, then
    // ease to its value — a runloop hook would skip the draw-in frame.
    let raf = requestAnimationFrame(() => (this.mounted = true));
    registerDestructor(this, () => {
      slaClock.unsubscribe();
      cancelAnimationFrame(raf);
    });
  }

  get snapshot() {
    return timerSnapshot(this.args.facts ?? {}, slaClock.now);
  }

  get consumedFraction() {
    let remaining = this.snapshot.percentRemaining;
    if (remaining == null) return 0;
    return Math.max(0, Math.min(1, 1 - remaining / 100));
  }

  get ringColor() {
    let hue =
      (TIMER_HUE as Record<string, Hue>)[this.snapshot.state] ?? 'slate';
    return stateColor(hue).ring;
  }

  get dashOffset() {
    return this.mounted ? C * this.consumedFraction : 0;
  }

  get sizeStyle() {
    let px = `${this.args.size ?? 20}px`;
    return `width: ${px}; height: ${px};`;
  }

  /** "−6h 27m" → two lines so each fits the 14-unit inner disc; 'Paused'
      stays one line but shrinks. Mono glyphs are ~0.62em wide. */
  get labelLines(): string[] {
    let label = this.snapshot.shortLabel ?? '';
    let parts = label.split(' ');
    return parts.length === 2 ? parts : [label];
  }
  get labelSize() {
    let longest = Math.max(...this.labelLines.map((l) => l.length), 1);
    return Math.min(4.2, 13 / (longest * 0.62)).toFixed(2);
  }
  get labelStyle() {
    return `font-size: ${this.labelSize}px;`;
  }

  get paused() {
    return this.snapshot.state === 'paused';
  }

  <template>
    <svg
      class='breach-ring {{if this.paused "breach-ring-paused"}}'
      viewBox='0 0 20 20'
      aria-hidden='true'
      style={{this.sizeStyle}}
      ...attributes
    >
      <circle
        cx='10'
        cy='10'
        r='8'
        fill='none'
        stroke='var(--muted)'
        stroke-width='2'
      />
      <circle
        class='breach-arc'
        cx='10'
        cy='10'
        r='8'
        fill='none'
        stroke={{this.ringColor}}
        stroke-width='2.2'
        stroke-linecap='round'
        stroke-dasharray='50.27'
        stroke-dashoffset='{{this.dashOffset}}'
        transform='rotate(-90 10 10)'
      />
      {{#if @labelled}}
        {{#if (eq this.labelLines.length 2)}}
          <text
            x='10'
            y='8.4'
            text-anchor='middle'
            dominant-baseline='middle'
            class='breach-label'
            style={{this.labelStyle}}
          >{{get this.labelLines 0}}</text>
          <text
            x='10'
            y='12.9'
            text-anchor='middle'
            dominant-baseline='middle'
            class='breach-label'
            style={{this.labelStyle}}
          >{{get this.labelLines 1}}</text>
        {{else}}
          <text
            x='10'
            y='10.6'
            text-anchor='middle'
            dominant-baseline='middle'
            class='breach-label'
            style={{this.labelStyle}}
          >{{get this.labelLines 0}}</text>
        {{/if}}
      {{/if}}
    </svg>
    <style scoped>
      .breach-ring {
        flex: none;
        display: inline-block;
        vertical-align: middle;
      }
      .breach-arc {
        transition:
          stroke-dashoffset 600ms cubic-bezier(0.22, 1, 0.36, 1),
          stroke 400ms ease-out;
      }
      .breach-ring-paused .breach-arc {
        stroke-dasharray: 2 3;
      }
      .breach-label {
        font-family: var(--font-mono);
        font-weight: 600;
        fill: var(--foreground);
      }
      @media (prefers-reduced-motion: reduce) {
        .breach-arc {
          transition: none;
        }
      }
    </style>
  </template>
}

export default BreachRing;
