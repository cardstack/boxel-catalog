import GlimmerComponent from '@glimmer/component';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { registerDestructor } from '@ember/destroyable';

import { timerSnapshot } from '@cardstack/catalog/cards/service-desk/utils/sla';

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
 * One interval per mounted clock, torn down with the component. The only
 * motion is the number changing.
 */
export class LiveClock extends GlimmerComponent<Signature> {
  @tracked now = new Date();
  private handle: ReturnType<typeof setInterval>;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    this.handle = setInterval(() => (this.now = new Date()), 1000);
    registerDestructor(this, () => clearInterval(this.handle));
  }

  get snapshot() {
    return timerSnapshot(this.args.facts ?? {}, this.now);
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
        font-family: var(--font-mono, var(--boxel-monospace-font-family));
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
        color: var(--muted-foreground, var(--boxel-450));
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
