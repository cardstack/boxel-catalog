import { guidFor } from '@ember/object/internals';
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import ContextProvider from 'ember-provide-consume-context/components/context-provider';

import {
  FailureBordered,
  type Icon,
  LoadingIndicator,
  SuccessBordered,
} from '../icons/index.ts';

import type { FormMode } from '../form-field-resolution.ts';
import type { CellValidationState } from './surface-component.gts';
import type { IdentityPart } from './surface-component.gts';
import {
  FormFieldContextName,
  type FormFieldContext,
} from '../form-field-context.ts';

export interface FormFieldSignature {
  Args: {
    label: string;
    icon?: Icon;
    optional?: boolean;
    required?: boolean;
    helperText?: string;
    errorMessage?: string;
    state?: CellValidationState;
    layout?: 'vertical' | 'horizontal';
    disabled?: boolean;
    readonly?: boolean;
    key?: IdentityPart | IdentityPart[];
  };
  Blocks: {
    default: [];
    label: [];
  };
  Element: HTMLElement;
}

export default class FormField extends Component<FormFieldSignature> {
  private guid = guidFor(this);
  @tracked private inheritedLayout: 'vertical' | 'horizontal' = 'vertical';
  @tracked private inheritedDensity: 'comfortable' | 'compact' = 'comfortable';
  @tracked private inheritedMode: FormMode = 'edit';

  get effectiveReadonly(): boolean | undefined {
    if (this.args.readonly !== undefined) return this.args.readonly;
    if (this.inheritedMode === 'view') return true;
    return undefined;
  }

  inheritFormChrome = modifier((el: HTMLElement) => {
    let form = el.closest('[data-bx-form]');
    let layout = form?.getAttribute('data-bx-form-layout');
    let density = form?.getAttribute('data-bx-form-density');
    let mode = form?.getAttribute('data-bx-form-mode');
    this.inheritedLayout = layout === 'horizontal' ? 'horizontal' : 'vertical';
    this.inheritedDensity = density === 'compact' ? 'compact' : 'comfortable';
    this.inheritedMode = mode === 'view' || mode === 'create' ? mode : 'edit';
  });

  get state(): CellValidationState {
    return this.args.state ?? (this.args.errorMessage ? 'invalid' : 'none');
  }

  get layout(): 'vertical' | 'horizontal' {
    return this.args.layout ?? this.inheritedLayout;
  }

  get density(): 'comfortable' | 'compact' {
    return this.inheritedDensity;
  }

  get isHorizontal(): boolean {
    return this.layout === 'horizontal';
  }

  get isVertical(): boolean {
    return !this.isHorizontal;
  }

  get isInvalid(): boolean {
    return this.state === 'invalid';
  }

  get isValid(): boolean {
    return this.state === 'valid';
  }

  get isLoading(): boolean {
    return this.state === 'loading';
  }

  get shouldShowMessage(): boolean {
    return Boolean(this.args.errorMessage || this.args.helperText);
  }

  get helperId(): string {
    return `bx-form-field-helper-${this.guid}`;
  }

  get errorId(): string {
    return `bx-form-field-error-${this.guid}`;
  }

  get describedBy(): string | undefined {
    if (this.args.errorMessage) return this.errorId;
    if (this.args.helperText) return this.helperId;
    return undefined;
  }

  get surfaceKey(): IdentityPart | IdentityPart[] {
    return this.args.key ?? [this.args.label, this.guid];
  }

  get context(): FormFieldContext {
    return {
      state: this.state,
      layout: this.layout,
      density: this.density,
      surfaceKey: this.surfaceKey,
      describedBy: this.describedBy,
      invalid: this.isInvalid,
      disabled: this.args.disabled,
      readonly: this.effectiveReadonly,
      required: this.args.required,
    };
  }

  get stateIcon(): Icon | undefined {
    switch (this.state) {
      case 'valid':
        return SuccessBordered;
      case 'invalid':
        return FailureBordered;
      case 'loading':
        return LoadingIndicator;
      default:
        return undefined;
    }
  }

  <template>
    <ContextProvider @key={{FormFieldContextName}} @value={{this.context}}>
      <div
        class='bx-form-field boxel-field
          {{if
            this.isHorizontal
            "bx-form-field--horizontal horizontal small-label"
            "bx-form-field--vertical vertical"
          }}
          bx-form-field--{{this.density}}
          {{if @icon "with-icon"}}'
        data-bx-form-field
        data-bx-form-field-density={{this.density}}
        data-bx-form-field-state={{this.state}}
        data-bx-form-field-disabled={{if @disabled 'true'}}
        data-bx-form-field-readonly={{if this.effectiveReadonly 'true'}}
        data-test-boxel-field
        {{this.inheritFormChrome}}
        ...attributes
      >
        <div class='label-container'>
          {{#if @icon}}
            <@icon
              class='boxel-field__icon'
              width='16'
              height='16'
              role='presentation'
            />
          {{/if}}
          <span class='label boxel-label' data-test-boxel-field-label>
            {{@label}}
          </span>
          <span class='bx-form-field__label-meta'>
            {{#if (has-block 'label')}}
              {{yield to='label'}}
            {{/if}}
            {{#if @required}}
              <span class='bx-form-field__required' aria-hidden='true'>*</span>
            {{/if}}
          </span>
          {{#if @optional}}
            <span class='bx-form-field__optional'>Optional</span>
          {{/if}}
          {{#if this.stateIcon}}
            <span
              class='bx-form-field__state'
              aria-label={{if
                this.isValid
                'Valid'
                (if this.isInvalid 'Invalid' 'Loading')
              }}
            >
              <this.stateIcon
                class='bx-form-field__state-icon'
                role='presentation'
              />
            </span>
          {{/if}}
        </div>

        <div
          class='content bx-form-field__content'
          aria-describedby={{this.describedBy}}
          aria-invalid={{if this.isInvalid 'true'}}
        >
          {{yield}}
        </div>

        {{#if this.shouldShowMessage}}
          <p
            class='bx-form-field__message
              {{if this.isInvalid "bx-form-field__message--error"}}'
            id={{if this.isInvalid this.errorId this.helperId}}
          >
            {{#if
              this.isInvalid
            }}{{@errorMessage}}{{else}}{{@helperText}}{{/if}}
          </p>
        {{/if}}
      </div>
    </ContextProvider>

    <style scoped>
      .bx-form-field {
        --boxel-field-label-align: normal;
        --boxel-field-label-padding-top: 0;
        --boxel-field-label-size: minmax(4rem, 10%);

        display: grid;
        width: 100%;
        max-width: 100%;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
        overflow-wrap: break-word;
      }

      .bx-form-field--horizontal {
        grid-template-columns: var(--boxel-field-label-size) 1fr;
        min-height: var(--boxel-form-control-height);
      }

      .bx-form-field--compact {
        --boxel-field-label-size: minmax(4rem, 18%);
      }

      .bx-form-field--vertical {
        grid-template-rows: auto 1fr;
      }

      .label-container {
        display: flex;
        align-items: start;
        min-width: 0;
      }

      .with-icon .label-container {
        gap: var(--boxel-sp-xs);
      }

      .bx-form-field--horizontal > .label-container {
        padding-top: var(--boxel-sp-sm);
      }

      .bx-form-field--horizontal > .bx-form-field__content {
        align-self: center;
      }

      .label {
        display: flex;
        align-items: var(--boxel-field-label-align);
        min-width: 0;
        padding-top: var(--boxel-field-label-padding-top);
        color: var(--foreground);
        font-family: var(--boxel-caption-font-family);
        font-size: var(--boxel-caption-font-size);
        font-weight: var(--boxel-caption-font-weight);
        line-height: var(--boxel-caption-line-height);
      }

      .boxel-field__icon {
        flex-shrink: 0;
      }

      .bx-form-field--horizontal .bx-form-field__message {
        margin-left: calc(min(10%, 4rem) + var(--boxel-sp));
      }

      .bx-form-field__required,
      .bx-form-field__message--error {
        color: var(--destructive);
      }

      .bx-form-field__optional,
      .bx-form-field__state,
      .bx-form-field__message {
        color: var(--muted-foreground);
        font-size: var(--boxel-caption-font-size);
        line-height: var(--boxel-caption-line-height);
      }

      .bx-form-field__label-meta {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        margin-left: var(--boxel-sp-xs);
      }

      .bx-form-field__optional {
        margin-left: auto;
      }

      .bx-form-field__state {
        display: inline-grid;
        place-items: center;
        min-width: 16px;
        height: 16px;
      }

      .bx-form-field__state-icon {
        width: 16px;
        height: 16px;
      }

      [data-bx-form-field-state='valid'] .bx-form-field__state {
        color: var(--success);
        --icon-color: currentColor;
      }

      [data-bx-form-field-state='invalid'] .bx-form-field__state {
        color: var(--destructive);
        --icon-color: currentColor;
      }

      [data-bx-form-field-state='loading'] .bx-form-field__state {
        color: var(--primary);
        --icon-color: currentColor;
      }

      .bx-form-field__content {
        min-width: 0;
      }

      .bx-form-field__message {
        margin: 0;
        padding-left: var(--boxel-outline-width);
      }
    </style>
  </template>
}
