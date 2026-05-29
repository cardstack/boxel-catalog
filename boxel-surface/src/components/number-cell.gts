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

export interface NumberCellSignature {
  Args: {
    value?: number | string;
    placeholder?: string;
    state?: CellValidationState;
    disabled?: boolean;
    readonly?: boolean;
    min?: number;
    max?: number;
    step?: number | string;
    prefix?: string;
    suffix?: string;
    onInput?: (value: string) => void;
    runtimePolicy?: FociNodePolicy;
  };
  Element: HTMLElement;
}

export default class NumberCell extends Component<NumberCellSignature> {
  @consume(FormFieldContextName) declare inheritedFormField:
    | FormFieldContext
    | undefined;

  get value(): string {
    return this.args.value === undefined ? '' : String(this.args.value);
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
    {{#if @prefix}}
      {{#if @suffix}}
        <Cell
          @state={{@state}}
          @disabled={{this.isDisabled}}
          @readonly={{this.isReadonly}}
          @runtimePolicy={{@runtimePolicy}}
        >
          <:pre>{{@prefix}}</:pre>
          <:default>
            <input
              class='boxel-input'
              type='number'
              value={{this.value}}
              placeholder={{@placeholder}}
              disabled={{this.isDisabled}}
              readonly={{this.isReadonly}}
              min={{@min}}
              max={{@max}}
              step={{@step}}
              data-test-boxel-input
              {{on 'input' this.handleInput}}
            />
          </:default>
          <:post>{{@suffix}}</:post>
        </Cell>
      {{else}}
        <Cell
          @state={{@state}}
          @disabled={{this.isDisabled}}
          @readonly={{this.isReadonly}}
          @runtimePolicy={{@runtimePolicy}}
        >
          <:pre>{{@prefix}}</:pre>
          <:default>
            <input
              class='boxel-input'
              type='number'
              value={{this.value}}
              placeholder={{@placeholder}}
              disabled={{this.isDisabled}}
              readonly={{this.isReadonly}}
              min={{@min}}
              max={{@max}}
              step={{@step}}
              data-test-boxel-input
              {{on 'input' this.handleInput}}
            />
          </:default>
        </Cell>
      {{/if}}
    {{else if @suffix}}
      <Cell
        @state={{@state}}
        @disabled={{this.isDisabled}}
        @readonly={{this.isReadonly}}
        @runtimePolicy={{@runtimePolicy}}
      >
        <:default>
          <input
            class='boxel-input'
            type='number'
            value={{this.value}}
            placeholder={{@placeholder}}
            disabled={{this.isDisabled}}
            readonly={{this.isReadonly}}
            min={{@min}}
            max={{@max}}
            step={{@step}}
            data-test-boxel-input
            {{on 'input' this.handleInput}}
          />
        </:default>
        <:post>{{@suffix}}</:post>
      </Cell>
    {{else}}
      <Cell
        @state={{@state}}
        @disabled={{this.isDisabled}}
        @readonly={{this.isReadonly}}
        @runtimePolicy={{@runtimePolicy}}
      >
        <input
          class='boxel-input'
          type='number'
          value={{this.value}}
          placeholder={{@placeholder}}
          disabled={{this.isDisabled}}
          readonly={{this.isReadonly}}
          min={{@min}}
          max={{@max}}
          step={{@step}}
          data-test-boxel-input
          {{on 'input' this.handleInput}}
        />
      </Cell>
    {{/if}}
  </template>
}
