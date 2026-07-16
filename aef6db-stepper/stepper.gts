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
                <button
                  type='button'
                  class='stepper-close'
                  aria-label='Close'
                  {{on 'click' @onClose}}
                >✕</button>
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
                    class='stepper-ghost stepper-back'
                    {{on 'click' this.back}}
                  >Back</Button>
                {{/unless}}
                {{#if this.isLast}}
                  {{#if @onFinish}}
                    <Button
                      @kind='primary'
                      class='stepper-primary'
                      {{on 'click' @onFinish}}
                    >{{this.finishLabel}}</Button>
                  {{/if}}
                {{else}}
                  {{#if this.currentOptional}}
                    <Button
                      @kind='text-only'
                      class='stepper-ghost'
                      {{on 'click' this.skip}}
                    >Skip</Button>
                  {{/if}}
                  <Button
                    @kind='primary'
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
      }
      .stepper-scrim {
        position: absolute;
        inset: 0;
        z-index: 200;
        display: grid;
        place-items: center;
        padding: var(--boxel-sp, 16px);
        background: var(--stepper-scrim-bg, rgba(0, 0, 0, 0.3));
        backdrop-filter: blur(2px);
      }
      .stepper-card {
        box-sizing: border-box;
        position: relative;
        display: flex;
        flex-direction: column;
        width: 100%;
        height: 100%;
        padding: 26px 30px;
        overflow: hidden;
        background: var(
          --stepper-card-bg,
          var(--card, var(--boxel-light, #ffffff))
        );
        border-radius: var(
          --stepper-radius,
          var(--radius, var(--boxel-border-radius-xl, 18px))
        );
        box-shadow: var(--stepper-shadow, 0 20px 60px rgba(0, 0, 0, 0.25));
        font-family: var(
          --stepper-body-font,
          var(--font-sans, var(--boxel-font-family, system-ui, sans-serif))
        );
        color: var(
          --stepper-ink,
          var(--foreground, var(--boxel-dark, #222222))
        );
      }
      .stepper-inline {
        box-shadow: none;
        border: 1px solid
          var(--stepper-border, var(--border, rgba(0, 0, 0, 0.1)));
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
        font-size: 10px;
        letter-spacing: 0.24em;
        text-transform: uppercase;
        color: var(
          --stepper-kicker-color,
          var(--stepper-muted, var(--muted-foreground, rgba(0, 0, 0, 0.6)))
        );
      }
      .stepper-brand-name {
        font-family: var(--stepper-heading-font, inherit);
        font-size: 21px;
        font-weight: 600;
      }
      /* Outlined circle ✕, no fill — same treatment as the seating
         planner's popover close button. */
      .stepper-close {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: center;
        width: 30px;
        height: 30px;
        border-radius: 50%;
        border: 1px solid
          var(--stepper-border, var(--border, rgba(0, 0, 0, 0.15)));
        background: transparent;
        color: var(
          --stepper-muted,
          var(--muted-foreground, rgba(0, 0, 0, 0.55))
        );
        font-size: 12px;
        line-height: 1;
        cursor: pointer;
        transition: 0.15s;
      }
      .stepper-close:hover {
        border-color: var(
          --stepper-ink,
          var(--foreground, var(--boxel-dark, #222222))
        );
        color: var(
          --stepper-ink,
          var(--foreground, var(--boxel-dark, #222222))
        );
      }
      .stepper-body {
        flex: 1;
        min-height: 0;
        display: flex;
        gap: 32px;
        margin-top: 18px;
      }
      .stepper-rail {
        flex: none;
        width: 232px;
        margin: 0;
        padding: 22px 18px;
        list-style: none;
        display: flex;
        flex-direction: column;
        gap: 24px;
        overflow-y: auto;
        border: 1px solid
          var(--stepper-border, var(--border, rgba(0, 0, 0, 0.1)));
        border-radius: 16px;
        background: var(
          --stepper-surface,
          var(--muted, var(--boxel-100, #f8f8f8))
        );
      }
      .stepper-step {
        position: relative;
        display: flex;
        gap: 14px;
      }
      .stepper-step.is-jumpable {
        cursor: pointer;
      }
      .stepper-step:not(:last-child)::before {
        content: '';
        position: absolute;
        left: 15px;
        top: 34px;
        bottom: -24px;
        width: 2px;
        background: var(
          --stepper-connector,
          var(--border, rgba(0, 0, 0, 0.12))
        );
      }
      .stepper-step.is-done:not(:last-child)::before {
        background: var(
          --stepper-accent,
          var(--primary, var(--boxel-highlight, #00ac3d))
        );
      }
      .stepper-dot {
        flex: none;
        width: 32px;
        height: 32px;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        border: 2px solid
          var(--stepper-connector, var(--border, rgba(0, 0, 0, 0.18)));
        background: var(--stepper-card-bg, var(--card, #ffffff));
        color: var(
          --stepper-muted,
          var(--muted-foreground, rgba(0, 0, 0, 0.5))
        );
        font-size: 12px;
        font-weight: 600;
        z-index: 1;
      }
      /* Accent fill + contrasting on-fill content, sourced from the
         theme's --primary / --primary-foreground pair; boxel-highlight
         is bright, so the themeless on-accent fallback is dark. */
      .stepper-step.is-done .stepper-dot {
        background: var(
          --stepper-accent,
          var(--primary, var(--boxel-highlight, #00ac3d))
        );
        border-color: var(
          --stepper-accent,
          var(--primary, var(--boxel-highlight, #00ac3d))
        );
        color: var(
          --stepper-accent-fg,
          var(--primary-foreground, var(--boxel-dark, #000000))
        );
      }
      .stepper-step.is-active .stepper-dot {
        border-color: var(
          --stepper-accent,
          var(--primary, var(--boxel-highlight, #00ac3d))
        );
        color: var(
          --stepper-ink,
          var(--foreground, var(--boxel-dark, #222222))
        );
        box-shadow: 0 0 0 4px
          color-mix(
            in srgb,
            var(
                --stepper-accent,
                var(--primary, var(--boxel-highlight, #00ac3d))
              )
              16%,
            transparent
          );
      }
      .stepper-step-txt {
        display: flex;
        flex-direction: column;
        gap: 2px;
        padding-top: 2px;
      }
      .stepper-step-k {
        font-size: 10px;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        color: var(
          --stepper-muted,
          var(--muted-foreground, rgba(0, 0, 0, 0.45))
        );
      }
      .stepper-step-l {
        font-family: var(--stepper-heading-font, inherit);
        font-size: 18px;
        font-weight: 600;
      }
      /* Active/done rail TEXT stays ink/muted — accent is for fills
         only; accent-colored text on the light rail fails contrast. */
      .stepper-step.is-active .stepper-step-l {
        color: var(
          --stepper-ink,
          var(--foreground, var(--boxel-dark, #222222))
        );
      }
      .stepper-step-s {
        font-size: 11px;
        color: var(
          --stepper-muted,
          var(--muted-foreground, rgba(0, 0, 0, 0.45))
        );
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
        width: 52px;
        height: 52px;
        border-radius: 50%;
        background: var(
          --stepper-accent,
          var(--primary, var(--boxel-highlight, #00ac3d))
        );
        color: var(
          --stepper-accent-fg,
          var(--primary-foreground, var(--boxel-dark, #000000))
        );
      }
      .stepper-title {
        margin: 12px 0 0;
        font-family: var(--stepper-heading-font, inherit);
        font-size: 32px;
        font-weight: 600;
      }
      .stepper-sub {
        margin: 6px 0 0;
        font-size: 14px;
        color: var(
          --stepper-muted,
          var(--muted-foreground, rgba(0, 0, 0, 0.65))
        );
        max-width: 54ch;
      }
      .stepper-actions {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 10px;
        margin-top: auto;
        padding-top: 16px;
        border-top: 1px solid
          var(--stepper-border, var(--border, rgba(0, 0, 0, 0.08)));
      }
      .stepper-back {
        margin-right: auto;
      }
      /* Boxel <Button> re-skins: route its CSS API through --stepper-* */
      .stepper-ghost {
        --boxel-button-font: 500 13px
          var(
            --stepper-body-font,
            var(--font-sans, var(--boxel-font-family, sans-serif))
          );
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
        --boxel-button-color: var(
          --stepper-primary-bg,
          var(--primary, var(--boxel-dark, #222222))
        );
        --boxel-button-text-color: var(
          --stepper-primary-fg,
          var(--primary-foreground, #ffffff)
        );
        --boxel-button-font: 500 13px
          var(
            --stepper-body-font,
            var(--font-sans, var(--boxel-font-family, sans-serif))
          );
        --boxel-button-letter-spacing: 0.04em;
        --boxel-button-padding: 11px 22px;
        --boxel-button-border-radius: 999px;
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
          padding: 18px;
        }
        .stepper-body {
          flex-direction: column;
          gap: 14px;
        }
        .stepper-rail {
          flex: none;
          width: 100%;
          flex-direction: row;
          gap: 18px;
          padding: 12px 14px;
          overflow-x: auto;
          overflow-y: hidden;
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
          font-size: 24px;
        }
      }
    </style>
  </template>
}
