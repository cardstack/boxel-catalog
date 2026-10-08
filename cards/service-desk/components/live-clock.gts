import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { registerDestructor } from '@ember/destroyable';

import { timerSnapshot } from '@cardstack/catalog/cards/service-desk/utils/sla';
import { slaClock } from '@cardstack/catalog/cards/service-desk/utils/sla-clock';

interface Signature {
  Args: {
    /** SlaTimerField-shaped facts; the clock recomputes every second. */
    facts?: any;
    /** 'short' → "1d 19h" / "0:22"; 'long' → "1d 19h remaining of 8h". */
    variant?: 'short' | 'long';
  };
  Element: HTMLElement;
}

/**
 * A ticking countdown over `utils/sla.timerSnapshot`. The NUMBER is the
 * accessible truth (the breach ring beside it is decoration), so it carries
 * `aria-live='off'` — a live region that changes every second would be
 * unbearable; screen readers read it on focus instead.
 *
 * Ticks on the shared `slaClock`, so every clock on a page reads the same
 * instant. The only motion is the number changing.
 */
export class LiveClock extends GlimmerComponent<Signature> {
  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    slaClock.subscribe();
    registerDestructor(this, () => slaClock.unsubscribe());
  }

  get snapshot() {
    return timerSnapshot(this.args.facts ?? {}, slaClock.now);
  }

  get label() {
    return this.args.variant === 'long'
      ? this.snapshot.label
      : this.snapshot.shortLabel;
  }

  <template>
    <span
      class='live-clock live-clock-{{this.snapshot.state}}'
      aria-live='off'
      ...attributes
    >{{this.label}}</span>
    <style scoped>
      .live-clock {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        transition: color 400ms ease-out;
      }
      .live-clock-urgent,
      .live-clock-breached {
        color: var(--boxel-danger);
        font-weight: 600;
      }
      .live-clock-warning {
        color: var(--boxel-warning);
      }
      .live-clock-met,
      .live-clock-healthy {
        color: var(--boxel-success);
      }
      .live-clock-paused {
        color: var(--muted-foreground);
      }
      @media (prefers-reduced-motion: reduce) {
        .live-clock {
          transition: none;
        }
      }
    </style>
  </template>
}

export default LiveClock;
