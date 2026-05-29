import { on } from '@ember/modifier';
import { action } from '@ember/object';
import Component from '@glimmer/component';
import { consume } from 'ember-provide-consume-context';

import {
  FormFieldContextName,
  type FormFieldContext,
} from '../form-field-context.ts';
import type { FociNodePolicy } from './surface-component.gts';
import { Cell } from './surface-component.gts';

export interface SwitchCellSignature {
  Args: {
    label: string;
    description?: string;
    value?: boolean;
    disabled?: boolean;
    onChange?: (value: boolean) => void;
    runtimePolicy?: FociNodePolicy;
  };
  Element: HTMLElement;
}

export default class SwitchCell extends Component<SwitchCellSignature> {
  @consume(FormFieldContextName) declare inheritedFormField:
    | FormFieldContext
    | undefined;

  get checked(): boolean {
    return Boolean(this.args.value);
  }

  // HTML has no `readonly` for buttons, so inherited readonly collapses
  // into `disabled` — the only "not interactable" state a switch can show.
  get isDisabled(): boolean {
    if (this.args.disabled !== undefined) return this.args.disabled;
    return Boolean(
      this.inheritedFormField?.disabled || this.inheritedFormField?.readonly,
    );
  }

  @action
  toggle(): void {
    if (this.isDisabled) return;
    this.args.onChange?.(!this.checked);
  }

  <template>
    <Cell
      class='bx-switch-cell'
      @disabled={{this.isDisabled}}
      @runtimePolicy={{@runtimePolicy}}
    >
      {{! TODO: Replace this local switch control with Boxel UI Switch once
        @cardstack/boxel-ui exposes tree-shakable component subpaths that do
        not pull the whole external addon into the surfaces test app build. }}
      <button
        class='bx-switch-cell__button'
        type='button'
        role='switch'
        aria-checked={{this.checked}}
        disabled={{this.isDisabled}}
        {{on 'click' this.toggle}}
      >
        <span class='bx-switch-cell__copy'>
          <span class='bx-switch-cell__label'>{{@label}}</span>
          {{#if @description}}
            <span class='bx-switch-cell__description'>{{@description}}</span>
          {{/if}}
        </span>
        <span
          class='bx-switch-cell__track'
          data-checked={{if this.checked 'true'}}
        >
          <span class='bx-switch-cell__thumb'></span>
        </span>
      </button>
    </Cell>

    <style>
      .bx-switch-cell {
        min-height: var(--cell-min-height);
        border: var(--cell-border);
        border-radius: var(--cell-radius);
        background: var(--cell-bg);
      }

      .bx-switch-cell .bx-cell__content {
        display: block;
      }

      .bx-switch-cell__button {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        align-items: center;
        width: 100%;
        min-height: var(--cell-min-height);
        gap: var(--boxel-sp-sm);
        padding: var(--cell-padding);
        border: 0;
        border-radius: inherit;
        background: transparent;
        color: var(--cell-fg);
        font: inherit;
        text-align: left;
        cursor: pointer;
      }

      .bx-switch-cell__button:focus {
        outline: 0;
        box-shadow: var(--cell-focus-shadow);
      }

      .bx-switch-cell.bx-cell--grid {
        height: 100%;
        border: 0;
        border-radius: 0;
        background: transparent;
      }

      .bx-switch-cell.bx-cell--grid .bx-cell__content {
        height: 100%;
      }

      .bx-switch-cell.bx-cell--grid .bx-switch-cell__button {
        min-height: 0;
        height: 100%;
        padding: 0 var(--boxel-sp-xs);
        box-shadow: none;
      }

      .bx-switch-cell.bx-cell--grid .bx-switch-cell__button:focus {
        box-shadow: none;
      }

      .bx-switch-cell.bx-cell--grid .bx-switch-cell__copy {
        display: none;
      }

      .bx-switch-cell.bx-cell--grid .bx-switch-cell__track {
        justify-self: center;
      }

      .bx-switch-cell__button:disabled {
        cursor: not-allowed;
      }

      .bx-switch-cell__copy {
        display: grid;
        min-width: 0;
        gap: var(--boxel-sp-4xs);
      }

      .bx-switch-cell__label {
        color: var(--foreground);
        font-size: var(--boxel-body-font-size);
        font-weight: var(--boxel-section-heading-font-weight);
        line-height: var(--boxel-body-line-height);
      }

      .bx-switch-cell__description {
        color: var(--cell-helper-color);
        font-size: var(--boxel-caption-font-size);
        line-height: var(--boxel-caption-line-height);
      }

      .bx-switch-cell__track {
        display: inline-flex;
        align-items: center;
        width: calc(var(--boxel-sp) + var(--boxel-sp-lg));
        height: calc(var(--boxel-sp) + var(--boxel-sp-4xs));
        padding: var(--boxel-sp-5xs);
        border-radius: var(--boxel-border-radius-xl);
        background: var(--muted);
        transition: background-color var(--boxel-transition);
      }

      .bx-switch-cell__track[data-checked='true'] {
        background: var(--success);
      }

      .bx-switch-cell__thumb {
        width: var(--boxel-sp);
        height: var(--boxel-sp);
        border-radius: var(--boxel-border-radius-xl);
        background: var(--background);
        box-shadow: 0 var(--boxel-sp-6xs) var(--boxel-sp-4xs)
          color-mix(in oklch, var(--foreground) 20%, transparent);
        transition: transform var(--boxel-transition);
      }

      .bx-switch-cell__track[data-checked='true'] .bx-switch-cell__thumb {
        transform: translateX(var(--boxel-sp-sm));
      }
    </style>
  </template>
}
