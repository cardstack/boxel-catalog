import GlimmerComponent from '@glimmer/component';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { Chip } from '@cardstack/pretui/components/chip';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { nameProgress } from '@cardstack/catalog/components/pretui-helpers';

import CircleCheckIcon from '@cardstack/boxel-icons/circle-check';
import ClockIcon from '@cardstack/boxel-icons/clock';
import AlertTriangleIcon from '@cardstack/boxel-icons/alert-triangle';
import CircleXIcon from '@cardstack/boxel-icons/circle-x';
import PauseIcon from '@cardstack/boxel-icons/pause';

import { stateColor, type Hue } from '@cardstack/catalog/components/state-pill';
import {
  TIMER_HUE,
  timerSnapshot,
  type TimerFacts,
  type TimerState,
} from '../utils/sla';

// The clock moved to utils/sla-clock so the lens predicates can read the
// same instant this badge draws. Re-exported: the badge is where every
// existing importer looks for it.
export { slaClock } from '../utils/sla-clock';
import { slaClock } from '../utils/sla-clock';

const STATE_ICON = {
  met: CircleCheckIcon,
  healthy: ClockIcon,
  warning: ClockIcon,
  urgent: AlertTriangleIcon,
  breached: CircleXIcon,
  paused: PauseIcon,
};

interface TimerChipSignature {
  Args: {
    hue?: string;
    breached?: boolean;
    icon: (typeof STATE_ICON)[keyof typeof STATE_ICON];
    label?: string;
  };
}

/**
 * The badge's Pret UI `Chip`: the state icon and its name. The dilute states
 * use StatePill's checked recipe (14% fill, 62% foreground ink). A breach is
 * the one state allowed to shout: a solid fill rather than the 14% dilution
 * every other state uses, because "you have already missed this" should not
 * look like a sibling of "you have time". Chip's hairline ring is turned off
 * on every state: a fill and an outline in the same hue is the same
 * information drawn twice, around the most-read element on the page.
 */
const TimerChip: TemplateOnlyComponent<TimerChipSignature> = <template>
  <Chip
    class='sla-chip {{if @breached "breached"}}'
    @hue={{@hue}}
    @dot={{false}}
  >
    <@icon class='sla-icon' width='12' height='12' aria-hidden='true' />
    {{! The state name is carried in text as well as colour — a red chip
        and an amber chip are the same chip to a colourblind agent. }}
    <span class='sla-text'>{{@label}}</span>
  </Chip>
  <style scoped>
    /* Chip sits in a lower cascade layer, so these plain rules win. */
    .sla-chip {
      --pretui-chip-mix: 14%;
      --pretui-ink-mix: 62%;
      align-self: flex-start;
      max-width: 100%;
      font-weight: 600;
      box-shadow: none;
    }
    /* The solid fill is `--destructive` with its own
       `--destructive-foreground`, set together in one rule. */
    .breached {
      background-color: var(--destructive);
      color: var(--destructive-foreground);
    }
    .sla-icon {
      flex: none;
    }
    .sla-text {
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      font-variant-numeric: tabular-nums;
    }
  </style>
</template>;

interface Signature {
  Args: {
    /** The timer's raw fields. Accepts an SlaTimerField model directly. */
    facts?: TimerFacts;
    /** 'First response', 'Resolution' — omitted in the tightest slots. */
    caption?: string;
    /**
     * Tick once a second. Only ever true where the component is hydrated:
     * prerendered fitted views render once at index time, so a live badge
     * there would freeze at whatever second it was built, which reads as a
     * bug. Those views pass `false` and show the stored snapshot instead.
     */
    live?: boolean;
    /** Show the proportional bar under the chip. */
    showBar?: boolean;
  };
  Element: HTMLElement;
}

export class SlaTimerBadge extends GlimmerComponent<Signature> {
  constructor(owner: unknown, args: Signature['Args']) {
    super(owner as never, args as never);
    if (this.args.live) {
      slaClock.subscribe();
    }
  }

  willDestroy() {
    super.willDestroy();
    if (this.args.live) {
      slaClock.unsubscribe();
    }
  }

  get snapshot() {
    // Reading `slaClock.now` is what subscribes this component to the tick;
    // in static mode we deliberately do not touch it, so the badge never
    // re-renders.
    let now = this.args.live ? slaClock.now : new Date();
    return timerSnapshot(this.args.facts ?? {}, now);
  }

  get state(): TimerState {
    return this.snapshot.state;
  }

  get icon() {
    return STATE_ICON[this.state];
  }

  get colors() {
    return stateColor(TIMER_HUE[this.state] as Hue);
  }

  get isBreached() {
    return this.state === 'breached';
  }

  // A breach paints its own fill, so its chip takes no hue.
  get chipHue() {
    return this.isBreached ? undefined : this.colors.ring;
  }

  get percentRemaining(): number {
    return this.snapshot.percentRemaining ?? 0;
  }

  get barLabel(): string {
    return `${this.args.caption ?? 'SLA'} time remaining`;
  }

  get hasBar() {
    return this.args.showBar && this.snapshot.percentRemaining != null;
  }

  <template>
    {{! A div when the bar is drawn, because ProgressBar's root is a div and
        a span cannot hold one; a span otherwise, so the badge stays phrasing
        content inside atoms and table cells. }}
    {{#if this.hasBar}}
      <div class='sla' data-sla-state={{this.state}} ...attributes>
        {{#if @caption}}
          <span class='sla-caption'>{{@caption}}</span>
        {{/if}}
        <TimerChip
          @hue={{this.chipHue}}
          @breached={{this.isBreached}}
          @icon={{this.icon}}
          @label={{this.snapshot.shortLabel}}
        />
        <ProgressBar
          class='sla-bar'
          @hue={{this.colors.ring}}
          @value={{this.percentRemaining}}
          @max={{100}}
          @steps={{false}}
          {{nameProgress this.barLabel}}
        />
        {{#if this.isBreached}}
          <span class='boxel-sr-only'>SLA breached</span>
        {{/if}}
      </div>
    {{else}}
      <span class='sla' data-sla-state={{this.state}} ...attributes>
        {{#if @caption}}
          <span class='sla-caption'>{{@caption}}</span>
        {{/if}}
        <TimerChip
          @hue={{this.chipHue}}
          @breached={{this.isBreached}}
          @icon={{this.icon}}
          @label={{this.snapshot.shortLabel}}
        />
        {{#if this.isBreached}}
          <span class='boxel-sr-only'>SLA breached</span>
        {{/if}}
      </span>
    {{/if}}

    <style scoped>
      .sla {
        display: inline-flex;
        flex-direction: column;
        gap: var(--boxel-sp-6xs);
        min-width: 0;
      }
      .sla-caption {
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      /* Pret UI ProgressBar. Its fill is the timer state's hue through
         `@hue`, and its track reads the theme's `--inset`. Only the width
         animates, and only in the live view — the tick is once a second, so
         the ease runs that long and linear; a bar that eases on every
         re-render looks like the number changed when it did not. */
      .sla-bar {
        --pretui-dur-morph: 0.9s;
        --pretui-ease-morph: linear;
        width: 100%;
      }
      @media (prefers-reduced-motion: reduce) {
        .sla-bar {
          --pretui-dur-morph: 0s;
        }
      }
    </style>
  </template>
}

export default SlaTimerBadge;
