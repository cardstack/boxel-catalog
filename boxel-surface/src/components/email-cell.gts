import { on } from '@ember/modifier';
import { action } from '@ember/object';
import Component from '@glimmer/component';
import { consume } from 'ember-provide-consume-context';

import {
  FormFieldContextName,
  type FormFieldContext,
} from '../form-field-context.ts';
import type {
  CellValidationState,
  FociNodePolicy,
} from './surface-component.gts';
import { Cell } from './surface-component.gts';

export interface EmailCellSignature {
  Args: {
    value?: string;
    placeholder?: string;
    state?: CellValidationState;
    disabled?: boolean;
    readonly?: boolean;
    onInput?: (value: string) => void;
    runtimePolicy?: FociNodePolicy;
  };
  Element: HTMLElement;
}

export default class EmailCell extends Component<EmailCellSignature> {
  @consume(FormFieldContextName) declare inheritedFormField:
    | FormFieldContext
    | undefined;

  get state(): CellValidationState {
    return this.args.state ?? this.inheritedFormField?.state ?? 'none';
  }

  get isInvalid(): boolean {
    return this.state === 'invalid';
  }

  get isReadonly(): boolean {
    return this.args.readonly ?? this.inheritedFormField?.readonly ?? false;
  }

  get isDisabled(): boolean {
    return this.args.disabled ?? this.inheritedFormField?.disabled ?? false;
  }

  @action
  handleInput(event: Event): void {
    this.args.onInput?.((event.target as HTMLInputElement).value);
  }

  <template>
    <Cell
      @state={{@state}}
      @disabled={{this.isDisabled}}
      @readonly={{this.isReadonly}}
      @runtimePolicy={{@runtimePolicy}}
    >
      <input
        class='boxel-input'
        type='email'
        value={{@value}}
        placeholder={{@placeholder}}
        disabled={{this.isDisabled}}
        readonly={{this.isReadonly}}
        aria-invalid={{if this.isInvalid 'true'}}
        data-test-boxel-input
        {{on 'input' this.handleInput}}
      />
    </Cell>
  </template>
}
