import { on } from '@ember/modifier';
import { action } from '@ember/object';
import Component from '@glimmer/component';

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
  @action
  handleInput(event: Event): void {
    this.args.onInput?.(
      (event.target as HTMLInputElement | HTMLTextAreaElement).value,
    );
  }

  get inputType(): 'text' | 'tel' | 'url' | 'search' {
    return this.args.type ?? 'text';
  }

  <template>
    {{#if @prefix}}
      {{#if @suffix}}
        <Cell
          @state={{@state}}
          @disabled={{@disabled}}
          @readonly={{@readonly}}
          @runtimePolicy={{@runtimePolicy}}
        >
          <:pre>{{@prefix}}</:pre>
          <:default>
            {{#if @multiline}}
              <textarea
                class='boxel-input'
                value={{@value}}
                placeholder={{@placeholder}}
                disabled={{@disabled}}
                readonly={{@readonly}}
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
                disabled={{@disabled}}
                readonly={{@readonly}}
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
          @disabled={{@disabled}}
          @readonly={{@readonly}}
          @runtimePolicy={{@runtimePolicy}}
        >
          <:pre>{{@prefix}}</:pre>
          <:default>
            {{#if @multiline}}
              <textarea
                class='boxel-input'
                value={{@value}}
                placeholder={{@placeholder}}
                disabled={{@disabled}}
                readonly={{@readonly}}
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
                disabled={{@disabled}}
                readonly={{@readonly}}
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
        @disabled={{@disabled}}
        @readonly={{@readonly}}
        @runtimePolicy={{@runtimePolicy}}
      >
        <:default>
          {{#if @multiline}}
            <textarea
              class='boxel-input'
              value={{@value}}
              placeholder={{@placeholder}}
              disabled={{@disabled}}
              readonly={{@readonly}}
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
              disabled={{@disabled}}
              readonly={{@readonly}}
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
        @disabled={{@disabled}}
        @readonly={{@readonly}}
        @runtimePolicy={{@runtimePolicy}}
      >
        {{#if @multiline}}
          <textarea
            class='boxel-input'
            value={{@value}}
            placeholder={{@placeholder}}
            disabled={{@disabled}}
            readonly={{@readonly}}
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
            disabled={{@disabled}}
            readonly={{@readonly}}
            data-test-boxel-input
            {{on 'input' this.handleInput}}
          />
        {{/if}}
      </Cell>
    {{/if}}
  </template>
}
