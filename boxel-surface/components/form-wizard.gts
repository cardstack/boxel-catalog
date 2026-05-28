import { on } from '@ember/modifier';
import { action } from '@ember/object';
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';

import { add, eq, lt } from '../template-helpers.ts';

export interface FormStepRegistration {
  id: string;
  label: string;
  stepId: string;
  panelId: string;
  disabled?: boolean;
  canAdvance?: boolean;
}

export interface FormWizardContext {
  activeId?: string;
  register: (step: FormStepRegistration) => () => void;
}

export const FormWizardContextName = 'boxel-surface:form-wizard';
export const FormStepRegisterEventName = 'bx-form-step-register';

export interface FormStepRegisterEventDetail {
  step: FormStepRegistration;
  updateActiveId: (id: string | undefined) => void;
  setUnregister: (unregister: () => void) => void;
}

export interface FormWizardSignature {
  Args: {
    activeStep?: string;
    defaultStep?: string;
    nextLabel?: string;
    previousLabel?: string;
    finishLabel?: string;
    onStepChange?: (id: string) => void;
    onFinish?: () => void;
  };
  Blocks: {
    default: [];
    footer: [];
  };
  Element: HTMLElement;
}

export default class FormWizard extends Component<FormWizardSignature> {
  @tracked private steps: FormStepRegistration[] = [];
  @tracked private activeOverride: string | undefined;
  private stepUpdaters = new Map<string, (id: string | undefined) => void>();

  get activeId(): string | undefined {
    return (
      this.activeOverride ??
      this.args.activeStep ??
      this.args.defaultStep ??
      this.steps.find((step) => !step.disabled)?.id ??
      this.steps[0]?.id
    );
  }

  get activeIndex(): number {
    return this.steps.findIndex((step) => step.id === this.activeId);
  }

  get activeStep(): FormStepRegistration | undefined {
    return this.steps[this.activeIndex];
  }

  get isFirst(): boolean {
    return this.activeIndex <= 0;
  }

  get isLast(): boolean {
    return this.activeIndex >= this.steps.length - 1;
  }

  get canAdvance(): boolean {
    return this.activeStep?.canAdvance !== false;
  }

  get nextLabel(): string {
    return this.args.nextLabel ?? 'Continue';
  }

  get previousLabel(): string {
    return this.args.previousLabel ?? 'Back';
  }

  get finishLabel(): string {
    return this.args.finishLabel ?? 'Finish';
  }

  registerStep = (
    step: FormStepRegistration,
    updateActiveId?: (id: string | undefined) => void,
  ): (() => void) => {
    let existingIndex = this.steps.findIndex(
      (candidate) => candidate.id === step.id,
    );
    if (existingIndex === -1) {
      this.steps = [...this.steps, step];
    } else {
      this.steps = this.steps.map((candidate, index) =>
        index === existingIndex ? step : candidate,
      );
    }
    if (updateActiveId) {
      this.stepUpdaters.set(step.id, updateActiveId);
    }

    this.syncPanels();

    return () => {
      this.steps = this.steps.filter((candidate) => candidate.id !== step.id);
      this.stepUpdaters.delete(step.id);
      if (this.activeOverride === step.id) {
        this.activeOverride = undefined;
      }
      this.syncPanels();
    };
  };

  private syncPanels(): void {
    for (let update of this.stepUpdaters.values()) {
      update(this.activeId);
    }
  }

  get context(): FormWizardContext {
    return {
      activeId: this.activeId,
      register: this.registerStep,
    };
  }

  @action
  select(id: string): void {
    let nextIndex = this.steps.findIndex((step) => step.id === id);
    let step = this.steps[nextIndex];
    if (!step || step.disabled) return;
    if (nextIndex > this.activeIndex && !this.canAdvance) return;
    this.activeOverride = id;
    this.syncPanels();
    this.args.onStepChange?.(id);
  }

  @action
  selectFromEvent(event: Event): void {
    let id = (event.currentTarget as HTMLElement).dataset['bxFormWizardStepId'];
    if (!id) return;
    this.select(id);
  }

  @action
  previous(): void {
    if (this.isFirst) return;
    let step = this.steps[this.activeIndex - 1];
    if (!step || step.disabled) return;
    this.activeOverride = step.id;
    this.syncPanels();
    this.args.onStepChange?.(step.id);
  }

  @action
  next(): void {
    if (!this.canAdvance) return;
    if (this.isLast) {
      this.args.onFinish?.();
      return;
    }

    let step = this.steps[this.activeIndex + 1];
    if (!step || step.disabled) return;
    this.activeOverride = step.id;
    this.syncPanels();
    this.args.onStepChange?.(step.id);
  }

  @action
  registerFromEvent(event: Event): void {
    let detail = (event as CustomEvent<FormStepRegisterEventDetail>).detail;
    if (!detail) return;
    event.stopPropagation();
    let unregister = this.registerStep(detail.step, detail.updateActiveId);
    detail.setUnregister(unregister);
  }

  <template>
    <div
      class='bx-form-wizard'
      data-bx-form-wizard
      {{on FormStepRegisterEventName this.registerFromEvent}}
      ...attributes
    >
      <ol class='bx-form-wizard__steps'>
        {{#each this.steps as |step index|}}
          <li class='bx-form-wizard__step-item'>
            <button
              id={{step.stepId}}
              class='bx-form-wizard__step'
              type='button'
              aria-current={{if (eq step.id this.activeId) 'step'}}
              aria-controls={{step.panelId}}
              disabled={{step.disabled}}
              data-bx-form-wizard-step-active={{if
                (eq step.id this.activeId)
                'true'
                'false'
              }}
              data-bx-form-wizard-step-complete={{if
                (lt index this.activeIndex)
                'true'
                'false'
              }}
              data-bx-form-wizard-step-id={{step.id}}
              {{on 'click' this.selectFromEvent}}
            >
              <span class='bx-form-wizard__step-index'>{{add index 1}}</span>
              <span class='bx-form-wizard__step-label'>{{step.label}}</span>
            </button>
          </li>
        {{/each}}
      </ol>

      <div class='bx-form-wizard__panels'>
        {{yield}}
      </div>

      {{#if (has-block 'footer')}}
        <div class='bx-form-wizard__footer'>{{yield to='footer'}}</div>
      {{else}}
        <div class='bx-form-wizard__footer'>
          <button
            class='bx-form-wizard__button bx-form-wizard__button--secondary'
            type='button'
            disabled={{this.isFirst}}
            {{on 'click' this.previous}}
          >
            {{this.previousLabel}}
          </button>
          <button
            class='bx-form-wizard__button bx-form-wizard__button--primary'
            type='button'
            disabled={{if this.canAdvance false true}}
            {{on 'click' this.next}}
          >
            {{if this.isLast this.finishLabel this.nextLabel}}
          </button>
        </div>
      {{/if}}
    </div>

    <style scoped>
      .bx-form-wizard {
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
        container-type: inline-size;
        container-name: bx-form-wizard;
      }

      .bx-form-wizard__steps {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
        gap: var(--boxel-sp-xs);
        padding: 0;
        margin: 0;
        list-style: none;
      }

      .bx-form-wizard__step {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        align-items: center;
        width: 100%;
        gap: var(--boxel-sp-xs);
        padding: var(--boxel-sp-xs);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        background: var(--card);
        color: var(--card-foreground);
        font: inherit;
        text-align: start;
        cursor: pointer;
      }

      .bx-form-wizard__step[data-bx-form-wizard-step-active='true'] {
        border-color: var(--ring);
        box-shadow: 0 0 0 var(--boxel-sp-5xs) var(--ring);
      }

      .bx-form-wizard__step[data-bx-form-wizard-step-complete='true'] {
        background: var(--secondary);
        color: var(--secondary-foreground);
      }

      .bx-form-wizard__step:focus {
        outline: 0;
        box-shadow: 0 0 0 var(--boxel-sp-5xs) var(--ring);
      }

      .bx-form-wizard__step:disabled {
        color: var(--muted-foreground);
        cursor: not-allowed;
        opacity: 0.6;
      }

      .bx-form-wizard__step-index {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-width: calc(var(--boxel-sp) + var(--boxel-sp-xs));
        height: calc(var(--boxel-sp) + var(--boxel-sp-xs));
        border-radius: var(--boxel-border-radius-xs);
        background: var(--muted);
        color: var(--muted-foreground);
        font-size: var(--boxel-caption-font-size);
        font-weight: var(--boxel-section-heading-font-weight);
      }

      .bx-form-wizard__step-label {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .bx-form-wizard__panels {
        min-width: 0;
      }

      .bx-form-wizard__footer {
        display: flex;
        flex-wrap: wrap;
        justify-content: flex-end;
        gap: var(--boxel-sp-xs);
        padding-block-start: var(--boxel-sp-sm);
        border-block-start: 1px solid var(--hr-color);
      }

      .bx-form-wizard__button {
        min-height: var(--boxel-form-control-height);
        padding-inline: var(--boxel-sp);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius-sm);
        font: inherit;
        font-weight: var(--boxel-subheading-font-weight);
        cursor: pointer;
      }

      .bx-form-wizard__button--primary {
        background: var(--primary);
        color: var(--primary-foreground);
      }

      .bx-form-wizard__button--secondary {
        background: var(--secondary);
        color: var(--secondary-foreground);
      }

      .bx-form-wizard__button:focus {
        outline: 0;
        box-shadow: 0 0 0 var(--boxel-sp-5xs) var(--ring);
      }

      .bx-form-wizard__button:disabled {
        color: var(--muted-foreground);
        cursor: not-allowed;
        opacity: 0.6;
      }

      @container bx-form-wizard (max-width: 36rem) {
        .bx-form-wizard__steps {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}
