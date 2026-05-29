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

export interface TextCellSignature {
  Args: {
    value?: string;
    placeholder?: string;
    state?: CellValidationState;
    disabled?: boolean;
    readonly?: boolean;
    multiline?: boolean;
    type?: 'text' | 'tel' | 'url' | 'search';
    autocomplete?: string;
    prefix?: string;
    suffix?: string;
    onInput?: (value: string) => void;
    runtimePolicy?: FociNodePolicy;
  };
  Element: HTMLElement;
}

export default class TextCell extends Component<TextCellSignature> {
  @consume(FormFieldContextName) declare inheritedFormField:
    | FormFieldContext
    | undefined;

  @action
  handleInput(event: Event): void {
    this.args.onInput?.(
      (event.target as HTMLInputElement | HTMLTextAreaElement).value,
    );
  }

  get inputType(): 'text' | 'tel' | 'url' | 'search' {
    return this.args.type ?? 'text';
  }

  get isReadonly(): boolean {
    return this.args.readonly ?? this.inheritedFormField?.readonly ?? false;
  }

  get isDisabled(): boolean {
    return this.args.disabled ?? this.inheritedFormField?.disabled ?? false;
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
            {{#if @multiline}}
              <textarea
                class='boxel-input'
                value={{@value}}
                placeholder={{@placeholder}}
                disabled={{this.isDisabled}}
                readonly={{this.isReadonly}}
                data-test-boxel-input
                {{on 'input' this.handleInput}}
              />
            {{else}}
              <input
                class='boxel-input'
                type={{this.inputType}}
                value={{@value}}
                placeholder={{@placeholder}}
                autocomplete={{@autocomplete}}
                disabled={{this.isDisabled}}
                readonly={{this.isReadonly}}
                data-test-boxel-input
                {{on 'input' this.handleInput}}
              />
            {{/if}}
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
            {{#if @multiline}}
              <textarea
                class='boxel-input'
                value={{@value}}
                placeholder={{@placeholder}}
                disabled={{this.isDisabled}}
                readonly={{this.isReadonly}}
                data-test-boxel-input
                {{on 'input' this.handleInput}}
              />
            {{else}}
              <input
                class='boxel-input'
                type={{this.inputType}}
                value={{@value}}
                placeholder={{@placeholder}}
                autocomplete={{@autocomplete}}
                disabled={{this.isDisabled}}
                readonly={{this.isReadonly}}
                data-test-boxel-input
                {{on 'input' this.handleInput}}
              />
            {{/if}}
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
          {{#if @multiline}}
            <textarea
              class='boxel-input'
              value={{@value}}
              placeholder={{@placeholder}}
              disabled={{this.isDisabled}}
              readonly={{this.isReadonly}}
              data-test-boxel-input
              {{on 'input' this.handleInput}}
            />
          {{else}}
            <input
              class='boxel-input'
              type={{this.inputType}}
              value={{@value}}
              placeholder={{@placeholder}}
              autocomplete={{@autocomplete}}
              disabled={{this.isDisabled}}
              readonly={{this.isReadonly}}
              data-test-boxel-input
              {{on 'input' this.handleInput}}
            />
          {{/if}}
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
        {{#if @multiline}}
          <textarea
            class='boxel-input'
            value={{@value}}
            placeholder={{@placeholder}}
            disabled={{this.isDisabled}}
            readonly={{this.isReadonly}}
            data-test-boxel-input
            {{on 'input' this.handleInput}}
          />
        {{else}}
          <input
            class='boxel-input'
            type={{this.inputType}}
            value={{@value}}
            placeholder={{@placeholder}}
            autocomplete={{@autocomplete}}
            disabled={{this.isDisabled}}
            readonly={{this.isReadonly}}
            data-test-boxel-input
            {{on 'input' this.handleInput}}
          />
        {{/if}}
      </Cell>
    {{/if}}
  </template>
}
