import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq, lt } from '@cardstack/boxel-ui/helpers';
import { Button } from '@cardstack/boxel-ui/components';

export interface WizardStep {
  title: string;
  /** Returns undefined when valid, or the message blocking Next. */
  validate?: () => string | undefined;
}

interface Signature {
  Args: {
    steps: WizardStep[];
    /** First incomplete step index (0-based) — the wizard RESUMES here. */
    currentStep: number;
    /** Persist progress: called with the next incomplete step index, or -1 when the last step completes. */
    onAdvance: (nextStep: number) => void;
    /** Save-and-exit is always available; exit costs nothing. */
    onSaveExit?: () => void;
  };
  Blocks: {
    /** The active step's body. */
    step: [index: number];
  };
  Element: HTMLElement;
}

/**
 * Setup Wizard (matrix row) — the generic first-run contract: ordered steps,
 * per-step validation BEFORE Next (slips prevented at entry, not at the
 * end), resumable at the first incomplete step, Save & exit always offered.
 *
 * Modality is ACCEPTED here deliberately (setup isolates scope); everywhere
 * else the desk is modeless. Steps already completed stay clickable for
 * review; steps ahead are visible but locked — progressive disclosure
 * without hiding the map.
 */
export class SetupWizard extends GlimmerComponent<Signature> {
  @tracked viewingStep: number | null = null;
  @tracked validationError: string | null = null;

  get activeStep() {
    return this.viewingStep ?? this.args.currentStep ?? 0;
  }

  get steps() {
    return this.args.steps ?? [];
  }

  goTo = (index: number) => {
    // Completed steps reopen for review; future steps stay locked.
    if (index <= (this.args.currentStep ?? 0)) {
      this.viewingStep = index;
      this.validationError = null;
    }
  };

  next = () => {
    let step = this.steps[this.activeStep];
    let error = step?.validate?.();
    if (error) {
      this.validationError = error;
      return;
    }
    this.validationError = null;
    let next = this.activeStep + 1;
    if (next >= this.steps.length) {
      this.args.onAdvance(-1); // done — caller stamps setupCompletedAt
    } else {
      this.args.onAdvance(next);
      this.viewingStep = next;
    }
  };

  back = () => {
    if (this.activeStep > 0) {
      this.viewingStep = this.activeStep - 1;
      this.validationError = null;
    }
  };

  <template>
    <div class='wiz' ...attributes>
      <ol class='wiz-steps'>
        {{#each this.steps as |step i|}}
          <li>
            <button
              type='button'
              class='wiz-step
                {{if (eq i this.activeStep) "wiz-on"}}
                {{if (lt i @currentStep) "wiz-done"}}'
              disabled={{this.isLocked i}}
              aria-current={{if (eq i this.activeStep) 'step'}}
              {{on 'click' (fn this.goTo i)}}
            >
              <span class='wiz-n'>{{if (lt i @currentStep) '✓' (this.oneBased i)}}</span>
              {{step.title}}
            </button>
          </li>
        {{/each}}
      </ol>
      <div class='wiz-body'>
        {{yield this.activeStep to='step'}}
        {{#if this.validationError}}
          <p class='wiz-error' role='alert'>{{this.validationError}}</p>
        {{/if}}
        <div class='wiz-actions'>
          <Button @size='touch' {{on 'click' this.back}} @disabled={{eq this.activeStep 0}}>← Back</Button>
          <span class='wiz-spacer'></span>
          {{#if @onSaveExit}}
            <Button @size='touch' {{on 'click' @onSaveExit}}>Save & exit</Button>
          {{/if}}
          <Button @kind='primary' @size='touch' {{on 'click' this.next}}>
            {{if this.isLast 'Finish setup' 'Next →'}}
          </Button>
        </div>
      </div>
    </div>
    <style scoped>
      .wiz {
        display: grid;
        grid-template-columns: 13rem 1fr;
        gap: var(--boxel-sp-xs);
        align-items: start;
      }
      @container (width < 44rem) {
        .wiz {
          grid-template-columns: 1fr;
        }
      }
      .wiz-steps {
        margin: 0;
        padding: var(--boxel-sp-xs);
        list-style: none;
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-5xs);
        border: 1px solid var(--border, var(--boxel-border-color));
        border-radius: var(--boxel-border-radius);
        background: var(--card, var(--boxel-light));
        box-shadow: var(--shadow-2xs, 0 1px 2px rgba(0, 0, 0, 0.04));
      }
      .wiz-step {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-4xs);
        width: 100%;
        min-height: 2.75rem;
        text-align: left;
        padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
        border: none;
        border-radius: var(--boxel-border-radius-sm);
        background: none;
        font: inherit;
        font-size: var(--boxel-font-size-sm);
        color: var(--muted-foreground, var(--boxel-450));
        cursor: pointer;
      }
      .wiz-step:disabled {
        cursor: not-allowed;
        opacity: 0.55;
      }
      .wiz-step:not(:disabled):hover {
        background: var(--muted, var(--boxel-200));
      }
      .wiz-step:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: 1px;
      }
      .wiz-on {
        background: color-mix(in oklab, var(--primary, var(--boxel-highlight)) 10%, var(--card, var(--boxel-light)));
        color: color-mix(in oklab, var(--primary, var(--boxel-highlight)) 38%, var(--card-foreground, var(--boxel-dark)));
        font-weight: 600;
      }
      .wiz-on .wiz-n {
        border-color: var(--primary, var(--boxel-highlight));
        color: color-mix(in oklab, var(--primary, var(--boxel-highlight)) 55%, var(--card-foreground, var(--boxel-dark)));
      }
      .wiz-done .wiz-n {
        color: var(--card, var(--boxel-light));
        background: var(--boxel-success);
        border-color: var(--boxel-success);
      }
      .wiz-n {
        font-family: var(--font-mono, var(--boxel-monospace-font-family));
        font-size: var(--boxel-font-size-xs);
        font-weight: 600;
        width: 1.25rem;
        height: 1.25rem;
        flex: none;
        display: grid;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        border: 1px solid var(--border, var(--boxel-border-color));
      }
      .wiz-body {
        border: 1px solid var(--border, var(--boxel-border-color));
        border-radius: var(--boxel-border-radius);
        background: var(--card, var(--boxel-light));
        box-shadow: var(--shadow-2xs, 0 1px 2px rgba(0, 0, 0, 0.04));
        padding: var(--boxel-sp);
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp-xs);
        min-width: 0;
      }
      .wiz-error {
        margin: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 1px solid var(--boxel-danger);
        border-radius: var(--boxel-border-radius-sm);
        color: var(--boxel-danger);
        background: color-mix(in oklab, var(--boxel-danger) 8%, var(--card, var(--boxel-light)));
        font-size: var(--boxel-font-size-sm);
      }
      .wiz-actions {
        display: flex;
        gap: var(--boxel-sp-4xs);
        align-items: center;
        margin-top: var(--boxel-sp-4xs);
      }
      .wiz-spacer {
        flex: 1;
      }
    </style>
  </template>

  isLocked = (index: number) => index > (this.args.currentStep ?? 0);
  oneBased = (index: number) => index + 1;
  get isLast() {
    return this.activeStep === this.steps.length - 1;
  }
}

export default SetupWizard;

