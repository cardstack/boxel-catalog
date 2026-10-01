import GlimmerComponent from '@glimmer/component';
import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { htmlSafe } from '@ember/template';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Chip } from '@cardstack/pretui/components/chip';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { nameProgress } from './service-desk-ui';

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
    chipStyle: ReturnType<typeof htmlSafe>;
    icon: (typeof STATE_ICON)[keyof typeof STATE_ICON];
    label?: string;
  };
}

/** The badge's Pret UI `Chip`: the state icon and its name. */
const TimerChip: TemplateOnlyComponent<TimerChipSignature> = <template>
  <Chip @dot={{false}} style={{@chipStyle}}>
    <@icon class='sla-icon' role='presentation' />
    {{! The state name is carried in text as well as colour — a red chip
        and an amber chip are the same chip to a colourblind agent. }}
    <span class='sla-text'>{{@label}}</span>
  </Chip>
  <style scoped>
    .sla-icon {
      width: 0.75rem;
      height: 0.75rem;
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

  /**
   * Pret UI `Chip` knobs. The dilute states use StatePill's checked recipe
   * (14% fill, 62% foreground ink). A breach is the one state allowed to
   * shout: a solid fill rather than the 14% dilution every other state uses,
   * because "you have already missed this" should not look like a sibling of
   * "you have time". Chip's hairline ring is turned off on both branches: a
   * fill and an outline in the same hue is the same information drawn twice,
   * around the most-read element on the page. Chip writes its own `@hue` as
   * an inline style that this `style` replaces, so the hue travels here too.
   */
  get chipStyle() {
    // Chip's own rules and this module's scoped rules tie on specificity, so
    // every property that differs from Chip's (weight, alignment) rides in
    // the inline style rather than a class.
    let shared =
      'align-self: flex-start; font-weight: 600; box-shadow: none; max-width: 100%';
    if (this.state === 'breached') {
      // The solid fill is `--destructive-ink` under `--background` text: the
      // ink moves away from the page colour in both schemes, where the
      // `--destructive` fill sits too close to it for 4.5:1 in light mode.
      return htmlSafe(
        `--pretui-chip-hue: var(--destructive-ink); ${shared}; --pretui-chip-mix: 100%; color: var(--background)`,
      );
    }
    return htmlSafe(
      `--pretui-chip-hue: ${this.colors.ring}; ${shared}; --pretui-chip-mix: 14%; --pretui-ink-mix: 62%`,
    );
  }

  /**
   * Pret UI `ProgressBar` draws its fill in `--primary`; this bar takes the
   * timer state's hue instead, through a local variable a scoped rule reads.
   */
  get barStyle() {
    return htmlSafe(`--sla-fill: ${this.colors.ring}`);
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
          @chipStyle={{this.chipStyle}}
          @icon={{this.icon}}
          @label={{this.snapshot.shortLabel}}
        />
        <ProgressBar
          class='sla-bar'
          style={{this.barStyle}}
          @value={{this.percentRemaining}}
          @max={{100}}
          @steps={{false}}
          {{nameProgress this.barLabel}}
        />
        {{#if (eq this.state 'breached')}}
          <span class='sr-only'>SLA breached</span>
        {{/if}}
      </div>
    {{else}}
      <span class='sla' data-sla-state={{this.state}} ...attributes>
        {{#if @caption}}
          <span class='sla-caption'>{{@caption}}</span>
        {{/if}}
        <TimerChip
          @chipStyle={{this.chipStyle}}
          @icon={{this.icon}}
          @label={{this.snapshot.shortLabel}}
        />
        {{#if (eq this.state 'breached')}}
          <span class='sr-only'>SLA breached</span>
        {{/if}}
      </span>
    {{/if}}

    <style scoped>
      .sla {
        display: inline-flex;
        flex-direction: column;
        gap: 0.125rem;
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
      /* Pret UI ProgressBar. Its fill is the timer state's hue, and its track
         keeps the muted ground it had. Only the width animates, and only in
         the live view — the tick is once a second, so the ease runs that long
         and linear; a bar that eases on every re-render looks like the number
         changed when it did not. */
      .sla-bar {
        width: 100%;
        --pretui-dur-morph: 0.9s;
        --pretui-ease-morph: linear;
      }
      .sla-bar :deep(.pretui-progress) {
        background-color: var(--muted);
      }
      .sla-bar :deep(.pretui-progress-fill) {
        background-color: var(--sla-fill);
      }
      @media (prefers-reduced-motion: reduce) {
        .sla-bar {
          --pretui-dur-morph: 0s;
        }
      }
      .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
        white-space: nowrap;
      }
    </style>
  </template>
}

export default SlaTimerBadge;
