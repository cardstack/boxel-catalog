import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Button } from '@cardstack/boxel-ui/components';
import { eq, not } from '@cardstack/boxel-ui/helpers';
import type { ComponentLike } from '@glint/template';

/**
 * `<Stepper>` — a general multi-step flow shell: a vertical step rail on
 * the left, the active step's content on the right, and a Back / Skip /
 * Next action bar. Optionally renders as a modal (scrim + centered card)
 * for first-run wizards.
 *
 * **What the host owns.** The step definitions (labels, completion
 * state) and each step's content, supplied through the `<:step>` block,
 * which receives the active step plus a navigation API. The Stepper owns
 * the step state machine, the rail's done/active states, gating Next on
 * `isComplete`, and the shell chrome (header, action bar, modal scrim).
 *
 * **Theming.** Every visual value resolves through three scopes,
 * strongest first — so a linked Theme card / Brand Guide restyles the
 * stepper with no stepper-specific work:
 *
 *   1. `--stepper-*` knobs — set on a host class to restyle ONLY the
 *      stepper.
 *   2. Theme semantic tokens — `--primary` / `--primary-foreground`
 *      (accent fills + on-fill content, also the Next button),
 *      `--foreground`, `--muted`, `--muted-foreground`, `--card`,
 *      `--border`, `--radius`, `--font-sans`. Author a normal theme and
 *      the stepper follows automatically.
 *   3. Built-in neutral defaults (Boxel tokens), used with no theme at
 *      all.
 *
 * The `--stepper-*` knob catalog:
 *
 *   --stepper-accent        done/active fills (dots, connectors, lead circle)
 *   --stepper-accent-fg     content ON accent fills (✓ glyph, lead icon)
 *   --stepper-ink           body text color
 *   --stepper-muted         secondary text color
 *   --stepper-surface       rail background
 *   --stepper-card-bg       card background (modal card / shell)
 *   --stepper-border        rail/card hairlines
 *   --stepper-connector     pending rail connectors + dot rings
 *   --stepper-primary-bg    primary button background
 *   --stepper-primary-fg    primary button text
 *   --stepper-kicker-color  header eyebrow text (defaults to muted)
 *   --stepper-heading-font  step titles + rail labels
 *   --stepper-body-font     everything else
 *   --stepper-radius        card corner radius
 *   --stepper-scrim-bg      modal backdrop
 *   --stepper-shadow        modal card shadow
 */

export interface StepperStep {
  id: string;
  /** Rail label (e.g. 'Your event'). */
  label: string;
  /** Rail sub-line while the step is pending (e.g. 'Event details'). */
  summary?: string;
  /** Content-pane heading; defaults to `label`. */
  title?: string;
  /** Content-pane sub-line under the heading. */
  description?: string;
  /** Optional lead icon rendered in a circle above the title. */
  icon?: ComponentLike<{ Element: Element }>;
  /** Gates Next and paints the rail ✓; `undefined` = always proceedable. */
  isComplete?: boolean;
  /** Marks the step skippable — a Skip button appears beside Next
   *  (MUI-style optional step). Linear steps omit this. */
  optional?: boolean;
}

export interface StepperApi {
  index: number;
  isFirst: boolean;
  isLast: boolean;
  canProceed: boolean;
  next: () => void;
  back: () => void;
  /** Advance without gating; on the last step calls `onClose`. */
  skip: () => void;
  goTo: (index: number) => void;
}

interface StepperSignature {
  Element: HTMLDivElement;
  Args: {
    steps: StepperStep[];
    /** Wrap the shell in a scrim + centered card. Default false. */
    modal?: boolean;
    /** Header brand name; header renders when this or `onClose` is set. */
    title?: string;
    /** Header eyebrow above the brand name (e.g. 'Getting started'). */
    kicker?: string;
    /** Last-step primary button label. Default 'Done'. */
    finishLabel?: string;
    /** Starting step index. Default 0. */
    initialStep?: number;
    /** Header ✕ and last-step Skip. Close button renders only if set. */
    onClose?: () => void;
    /** Show the header ✕. Default: true whenever `onClose` is set. */
    showClose?: boolean;
    /** Last-step primary button; the button renders only if set. */
    onFinish?: () => void;
    /** Fired whenever a step is entered (Next / Skip / goTo). */
    onStepChange?: (step: StepperStep, index: number) => void;
    /** Allow clicking rail items to jump between steps. Default false. */
    allowStepJump?: boolean;
  };
  Blocks: {
    step: [StepperStep, StepperApi];
    actions?: [StepperApi];
    decoration?: [];
  };
}

export default class Stepper extends Component<StepperSignature> {
  @tracked index = this.args.initialStep ?? 0;

  get steps(): StepperStep[] {
    return this.args.steps ?? [];
  }
  get current(): StepperStep | undefined {
    return this.steps[this.index];
  }
  get isFirst(): boolean {
    return this.index === 0;
  }
  get isLast(): boolean {
    return this.index >= this.steps.length - 1;
  }
  get canProceed(): boolean {
    return this.current?.isComplete ?? true;
  }
  get finishLabel(): string {
    return this.args.finishLabel ?? 'Done';
  }
  get showHeader(): boolean {
    return Boolean(this.args.title || this.args.kicker || this.showClose);
  }
  get showClose(): boolean {
    return this.args.showClose ?? Boolean(this.args.onClose);
  }
  get currentOptional(): boolean {
    return this.current?.optional ?? false;
  }
  get api(): StepperApi {
    return {
      index: this.index,
      isFirst: this.isFirst,
      isLast: this.isLast,
      canProceed: this.canProceed,
      next: this.next,
      back: this.back,
      skip: this.skip,
      goTo: this.goTo,
    };
  }

  private enter = (index: number) => {
    if (index < 0 || index >= this.steps.length) return;
    this.index = index;
    let step = this.steps[index];
    if (step) this.args.onStepChange?.(step, index);
  };
  next = () => {
    if (!this.isLast) this.enter(this.index + 1);
  };
  back = () => {
    if (!this.isFirst) this.index -= 1;
  };
  skip = () => {
    if (!this.isLast) this.enter(this.index + 1);
    else this.args.onClose?.();
  };
  goTo = (index: number) => {
    this.enter(index);
  };
  railJump = (index: number) => {
    if (this.args.allowStepJump) this.enter(index);
  };

  stepNumber = (index: number): string => {
    return String(index + 1).padStart(2, '0');
  };

  <template>
    <div class='stepper-shell {{if @modal "stepper-scrim"}}' ...attributes>
      <div class='stepper-card {{unless @modal "stepper-inline"}}'>
        {{yield to='decoration'}}
        {{#if this.showHeader}}
          <div class='stepper-top'>
            <div class='stepper-brand'>
              {{#if @kicker}}<span
                  class='stepper-kicker'
                >{{@kicker}}</span>{{/if}}
              {{#if @title}}<span
                  class='stepper-brand-name'
                >{{@title}}</span>{{/if}}
            </div>
            {{#if this.showClose}}
              {{#if @onClose}}
                <Button
                  @kind='text-only'
                  @size='auto'
                  class='stepper-close'
                  aria-label='Close'
                  {{on 'click' @onClose}}
                >✕</Button>
              {{/if}}
            {{/if}}
          </div>
        {{/if}}
        <div class='stepper-body'>
          <ol class='stepper-rail'>
            {{#each this.steps as |step i|}}
              <li
                class='stepper-step
                  {{if step.isComplete "is-done"}}
                  {{if (eq this.index i) "is-active"}}
                  {{if @allowStepJump "is-jumpable"}}'
                {{on 'click' (fn this.railJump i)}}
              >
                <span class='stepper-dot'>{{if
                    step.isComplete
                    '✓'
                    (this.stepNumber i)
                  }}</span>
                <span class='stepper-step-txt'>
                  <span class='stepper-step-k'>Step {{this.stepNumber i}}</span>
                  <span class='stepper-step-l'>{{step.label}}</span>
                  {{#if step.summary}}
                    <span class='stepper-step-s'>{{if
                        step.isComplete
                        'Completed'
                        step.summary
                      }}</span>
                  {{/if}}
                </span>
              </li>
            {{/each}}
          </ol>
          <div class='stepper-main'>
            <div class='stepper-content'>
              {{#if this.current}}
                {{#if this.current.icon}}
                  <div class='stepper-lead'><this.current.icon
                      width='26'
                      height='26'
                    /></div>
                {{/if}}
                {{#if this.current.title}}
                  <h1 class='stepper-title'>{{this.current.title}}</h1>
                {{else}}
                  <h1 class='stepper-title'>{{this.current.label}}</h1>
                {{/if}}
                {{#if this.current.description}}
                  <p class='stepper-sub'>{{this.current.description}}</p>
                {{/if}}
                {{yield this.current this.api to='step'}}
              {{/if}}
            </div>
            {{#if (has-block 'actions')}}
              {{yield this.api to='actions'}}
            {{else}}
              <div class='stepper-actions'>
                {{#unless this.isFirst}}
                  <Button
                    @kind='text-only'
                    @size='auto'
                    class='stepper-ghost stepper-back'
                    {{on 'click' this.back}}
                  >Back</Button>
                {{/unless}}
                {{#if this.isLast}}
                  {{#if @onFinish}}
                    <Button
                      @kind='primary'
                      @size='auto'
                      class='stepper-primary'
                      {{on 'click' @onFinish}}
                    >{{this.finishLabel}}</Button>
                  {{/if}}
                {{else}}
                  {{#if this.currentOptional}}
                    <Button
                      @kind='text-only'
                      @size='auto'
                      class='stepper-ghost'
                      {{on 'click' this.skip}}
                    >Skip</Button>
                  {{/if}}
                  <Button
                    @kind='primary'
                    @size='auto'
                    @disabled={{not this.canProceed}}
                    class='stepper-primary'
                    {{on 'click' this.next}}
                  >Next</Button>
                {{/if}}
              </div>
            {{/if}}
          </div>
        </div>
      </div>
    </div>
    <style scoped>
      .stepper-shell {
        box-sizing: border-box;
        width: 100%;
        height: 100%;
        container-type: inline-size;
        container-name: stepper;
        background-color: var(--canvas);
        color: var(--foreground);
      }
      .stepper-scrim {
        position: absolute;
        inset: 0;
        z-index: 200;
        display: grid;
        place-items: center;
        padding: var(--boxel-sp);
        background-color: var(
          --stepper-scrim-bg,
          color-mix(in oklch, var(--foreground) 30%, transparent)
        );
        backdrop-filter: blur(2px);
      }
      .stepper-card {
        box-sizing: border-box;
        position: relative;
        display: flex;
        flex-direction: column;
        width: 100%;
        height: 100%;
        padding: 1.625rem 1.875rem;
        overflow: hidden;
        background-color: var(--card);
        border-radius: var(--radius);
        box-shadow: var(
          --stepper-shadow,
          0 20px 60px color-mix(in oklch, var(--foreground) 25%, transparent)
        );
        font-family: var(--font-sans);
        color: var(--foreground);
      }
      .stepper-inline {
        box-shadow: none;
        border: 1px solid var(--border);
      }
      .stepper-top {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
      }
      .stepper-brand {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }
      .stepper-kicker {
        font-size: 0.625rem;
        letter-spacing: 0.24em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .stepper-brand-name {
        font-family: var(--stepper-heading-font, inherit);
        font-size: 1.3125rem;
        font-weight: 600;
      }
      /* Outlined circle ✕, no fill — same treatment as the seating
         planner's popover close button. */
      .stepper-close {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 1.875rem;
        height: 1.875rem;
        border-radius: 50%;
        border: 1px solid var(--border);
        background-color: transparent;
        color: var(--muted-foreground);
        font-size: 0.75rem;
        line-height: 1;
        cursor: pointer;
        transition: 0.15s;
      }
      .stepper-close:hover {
        border-color: var(--foreground);
        color: var(--foreground);
      }
      .stepper-body {
        flex: 1;
        min-height: 0;
        display: flex;
        gap: 2rem;
        margin-top: 1.125rem;
      }
      .stepper-rail {
        flex: none;
        width: 14.5rem;
        margin: 0;
        padding: 1.375rem 1.125rem;
        list-style: none;
        display: flex;
        flex-direction: column;
        gap: 1.5rem;
        overflow-y: auto;
        border: 1px solid var(--border);
        border-radius: 1rem;
        background-color: var(--sidebar);
        color: var(--sidebar-foreground);
      }
      .stepper-step {
        position: relative;
        display: flex;
        gap: 0.875rem;
      }
      /* Current-step highlight — a soft accent wash behind the whole
         row, so "you are here" stays visible even once the step is
         complete and its dot has flipped to the done fill. */
      .stepper-step.is-active::after {
        content: '';
        position: absolute;
        inset: -0.5rem -0.625rem;
        border-radius: 0.75rem;
        background-color: color-mix(in oklch, var(--primary) 10%, transparent);
        pointer-events: none;
      }
      .stepper-step.is-jumpable {
        cursor: pointer;
      }
      .stepper-step:not(:last-child)::before {
        content: '';
        position: absolute;
        left: 0.9375rem;
        top: 2.125rem;
        bottom: -1.5rem;
        width: 2px;
        background-color: var(--border);
      }
      .stepper-step.is-done:not(:last-child)::before {
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .stepper-dot {
        flex: none;
        width: 2rem;
        height: 2rem;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        border: 2px solid var(--border);
        background-color: var(--card);
        color: var(--muted-foreground);
        font-size: 0.75rem;
        font-weight: 600;
        z-index: 1;
      }
      /* Accent fill + contrasting on-fill content, sourced from the
         theme's --primary / --primary-foreground pair; boxel-highlight
         is bright, so the themeless on-accent fallback is dark. */
      .stepper-step.is-done .stepper-dot {
        background-color: var(--primary);
        border-color: var(--primary);
        color: var(--primary-foreground);
      }
      .stepper-step.is-active .stepper-dot {
        border-color: var(--primary);
        color: var(--foreground);
        box-shadow: 0 0 0 4px
          color-mix(in oklch, var(--primary) 28%, transparent);
      }
      /* Completed AND current: keep the on-accent foreground so the ✓
         stays readable on the accent fill (the active rule above would
         otherwise repaint it in ink). */
      .stepper-step.is-done.is-active .stepper-dot {
        color: var(--primary-foreground);
      }
      .stepper-step-txt {
        position: relative;
        z-index: 1;
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding-top: 2px;
      }
      .stepper-step-k {
        font-size: 0.625rem;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .stepper-step-l {
        font-family: var(--stepper-heading-font, inherit);
        font-size: 1.125rem;
        font-weight: 600;
      }
      /* Active/done rail TEXT stays ink/muted — accent is for fills
         only; accent-colored text on the light rail fails contrast. */
      .stepper-step.is-active .stepper-step-l {
        color: var(--foreground);
      }
      .stepper-step-s {
        font-size: 0.6875rem;
        color: var(--muted-foreground);
      }
      .stepper-main {
        flex: 1;
        min-width: 0;
        min-height: 0;
        display: flex;
        flex-direction: column;
      }
      /* Scroll container for the step's content so tall steps scroll
         instead of pushing the action bar out of the clipped card. */
      .stepper-content {
        flex: 1;
        min-height: 0;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
      }
      .stepper-lead {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 3.25rem;
        height: 3.25rem;
        border-radius: 50%;
        background-color: var(--primary);
        color: var(--primary-foreground);
      }
      .stepper-title {
        margin: 0.75rem 0 0;
        font-family: var(--stepper-heading-font, inherit);
        font-size: 2rem;
        font-weight: 600;
      }
      .stepper-sub {
        margin: 0.375rem 0 0;
        font-size: 0.875rem;
        color: var(--muted-foreground);
        max-width: 54ch;
      }
      .stepper-actions {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 0.625rem;
        margin-top: auto;
        padding-top: 1rem;
        border-top: 1px solid var(--border);
      }
      .stepper-back {
        margin-right: auto;
      }
      /* Boxel <Button> re-skins: route its CSS API through --stepper-* */
      .stepper-ghost {
        --boxel-button-font: 500 0.8125rem var(--font-sans);
        color: inherit;
        opacity: 0.65;
      }
      .stepper-ghost:hover {
        opacity: 1;
      }
      /* Anchor the primary button to the theme's --primary /
         --primary-foreground PAIR (authored together as a contrast
         pairing) rather than the --boxel-button-primary-* tokens, whose
         bg and fg can come from different sources and clash. */
      .stepper-primary,
      .stepper-primary:not(:disabled):hover,
      .stepper-primary:not(:disabled):active {
        --boxel-button-color: var(--primary);
        --boxel-button-text-color: var(--primary-foreground);
        --boxel-button-font: 500 0.8125rem var(--font-sans);
        --boxel-button-letter-spacing: 0.04em;
        --boxel-button-padding: 0.6875rem 1.375rem;
        --boxel-button-border-radius: 62.4375rem;
      }
      .stepper-primary:not(:disabled):hover {
        filter: brightness(0.92);
      }
      .stepper-primary:disabled {
        opacity: 0.45;
      }
      /* Narrow containers: stack the panes — the rail becomes a
         horizontal scroll strip above the content. */
      @container stepper (max-width: 560px) {
        .stepper-card {
          padding: 1.125rem;
        }
        .stepper-body {
          flex-direction: column;
          gap: 0.875rem;
        }
        .stepper-rail {
          flex: none;
          width: 100%;
          flex-direction: row;
          gap: 1.125rem;
          padding: 0.75rem 0.875rem;
          overflow-x: auto;
          overflow-y: hidden;
          background-color: var(--sidebar);
          color: var(--sidebar-foreground);
        }
        .stepper-step {
          flex: none;
        }
        .stepper-step:not(:last-child)::before {
          display: none;
        }
        .stepper-step-s {
          display: none;
        }
        .stepper-title {
          font-size: 1.5rem;
        }
      }
    </style>
  </template>
}
