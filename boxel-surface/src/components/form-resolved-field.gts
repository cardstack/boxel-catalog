import { action } from '@ember/object';
import Component from '@glimmer/component';

import type {
  FormMode,
  ResolvedFormField,
  ResolvedFormModel,
} from '../form-field-resolution.ts';
import {
  readResolvedFormFieldValue,
  writeResolvedFormFieldValue,
} from '../form-field-resolution.ts';
import EmailCell from './email-cell.gts';
import FormField from './form-field.gts';
import NumberCell from './number-cell.gts';
import SwitchCell from './switch-cell.gts';
import TextCell from './text-cell.gts';

export interface FormResolvedFieldSignature {
  Args: {
    field: ResolvedFormField;
    model?: ResolvedFormModel;
    mode: FormMode;
  };
  Element: HTMLElement;
}

export default class FormResolvedField extends Component<FormResolvedFieldSignature> {
  get rawValue(): unknown {
    return readResolvedFormFieldValue(this.args.field, this.args.model);
  }

  get textValue(): string {
    return this.rawValue == null ? '' : String(this.rawValue);
  }

  get numberValue(): string | number {
    return typeof this.rawValue === 'number' ? this.rawValue : this.textValue;
  }

  get booleanValue(): boolean {
    return Boolean(this.rawValue);
  }

  get isEmail(): boolean {
    return this.args.field.kind === 'email';
  }

  get isNumber(): boolean {
    return this.args.field.kind === 'number';
  }

  get isBoolean(): boolean {
    return this.args.field.kind === 'boolean';
  }

  get isReadonly(): boolean {
    return this.args.mode === 'view' || this.args.field.readonly === true;
  }

  get isDisabled(): boolean {
    return this.args.field.disabled === true;
  }

  get isBooleanDisabled(): boolean {
    return this.isDisabled || this.args.mode === 'view';
  }

  @action
  updateText(value: string): void {
    if (this.isReadonly || this.isDisabled) return;
    this.args.field.onInput?.(value);
    if (!this.args.field.onInput) {
      writeResolvedFormFieldValue(this.args.field, this.args.model, value);
    }
  }

  @action
  updateNumber(value: string): void {
    if (this.isReadonly || this.isDisabled) return;
    this.args.field.onInput?.(value);
    if (this.args.field.onInput) return;

    let nextValue: string | number = value;
    if (typeof this.rawValue === 'number' && value !== '') {
      nextValue = Number(value);
    }
    writeResolvedFormFieldValue(this.args.field, this.args.model, nextValue);
  }

  @action
  updateBoolean(value: boolean): void {
    if (this.isBooleanDisabled) return;
    this.args.field.onChange?.(value);
    if (!this.args.field.onChange) {
      writeResolvedFormFieldValue(this.args.field, this.args.model, value);
    }
  }

  <template>
    {{#if this.isBoolean}}
      <SwitchCell
        @label={{@field.label}}
        @description={{@field.description}}
        @value={{this.booleanValue}}
        @disabled={{this.isBooleanDisabled}}
        @onChange={{this.updateBoolean}}
        ...attributes
      />
    {{else}}
      <FormField
        @label={{@field.label}}
        @required={{@field.required}}
        @optional={{@field.optional}}
        @helperText={{@field.helperText}}
        @errorMessage={{@field.errorMessage}}
        @state={{@field.state}}
        @disabled={{this.isDisabled}}
        @readonly={{this.isReadonly}}
        ...attributes
      >
        {{#if this.isEmail}}
          <EmailCell
            @value={{this.textValue}}
            @placeholder={{@field.placeholder}}
            @disabled={{this.isDisabled}}
            @readonly={{this.isReadonly}}
            @onInput={{this.updateText}}
          />
        {{else if this.isNumber}}
          <NumberCell
            @value={{this.numberValue}}
            @placeholder={{@field.placeholder}}
            @disabled={{this.isDisabled}}
            @readonly={{this.isReadonly}}
            @min={{@field.min}}
            @max={{@field.max}}
            @step={{@field.step}}
            @prefix={{@field.prefix}}
            @suffix={{@field.suffix}}
            @onInput={{this.updateNumber}}
          />
        {{else}}
          <TextCell
            @value={{this.textValue}}
            @placeholder={{@field.placeholder}}
            @disabled={{this.isDisabled}}
            @readonly={{this.isReadonly}}
            @multiline={{@field.multiline}}
            @type={{@field.inputType}}
            @autocomplete={{@field.autocomplete}}
            @prefix={{@field.prefix}}
            @suffix={{@field.suffix}}
            @onInput={{this.updateText}}
          />
        {{/if}}
      </FormField>
    {{/if}}
  </template>
}
