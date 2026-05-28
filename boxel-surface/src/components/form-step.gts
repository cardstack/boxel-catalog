import Component from '@glimmer/component';
import { guidFor } from '@ember/object/internals';
import { tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import { consume } from 'ember-provide-consume-context';

import { eq } from '../template-helpers.ts';

import {
  FormStepRegisterEventName,
  FormWizardContextName,
  type FormWizardContext,
} from './form-wizard.gts';

export interface FormStepSignature {
  Args: {
    id?: string;
    label: string;
    disabled?: boolean;
    canAdvance?: boolean;
  };
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class FormStep extends Component<FormStepSignature> {
  private guid = guidFor(this);
  @tracked private eventActiveId: string | undefined;

  @consume(FormWizardContextName) declare wizard: FormWizardContext | undefined;

  get id(): string {
    return this.args.id ?? this.guid;
  }

  get stepId(): string {
    return `bx-form-step-${this.guid}`;
  }

  get panelId(): string {
    return `bx-form-step-panel-${this.guid}`;
  }

  get isActive(): boolean {
    return (this.wizard?.activeId ?? this.eventActiveId) === this.id;
  }

  register = modifier((el: HTMLElement) => {
    let step = {
      id: this.id,
      label: this.args.label,
      stepId: this.stepId,
      panelId: this.panelId,
      disabled: this.args.disabled,
      canAdvance: this.args.canAdvance,
    };
    let contextUnregister = this.wizard?.register(step);
    if (contextUnregister) return contextUnregister;

    let unregister: (() => void) | undefined;
    let cancelled = false;
    queueMicrotask(() => {
      if (cancelled) return;
      el.dispatchEvent(
        new CustomEvent(FormStepRegisterEventName, {
          bubbles: true,
          detail: {
            step,
            updateActiveId: (id: string | undefined) => {
              this.eventActiveId = id;
            },
            setUnregister: (next: () => void) => {
              unregister = next;
            },
          },
        }),
      );
    });

    return () => {
      cancelled = true;
      unregister?.();
    };
  });

  <template>
    <section
      id={{this.panelId}}
      class='bx-form-step'
      aria-labelledby={{this.stepId}}
      hidden={{if (eq this.isActive true) false true}}
      data-bx-form-step-panel={{this.id}}
      data-bx-form-step-panel-active={{if this.isActive 'true' 'false'}}
      {{this.register}}
      ...attributes
    >
      {{#if this.isActive}}
        {{yield}}
      {{/if}}
    </section>

    <style scoped>
      .bx-form-step {
        min-width: 0;
      }
    </style>
  </template>
}
