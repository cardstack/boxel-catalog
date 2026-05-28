import type { ComponentLike } from '@glint/template';
import Component from '@glimmer/component';

import FormAlert from './form-alert.gts';
import FormField from './form-field.gts';
import FormResolvedField from './form-resolved-field.gts';
import type {
  FormMode,
  ResolvedFormField,
  ResolvedFormModel,
} from '../form-field-resolution.ts';

export interface FormBodySignature {
  Args: {
    description?: string;
    errors?: readonly string[];
    fields: Record<string, ComponentLike<{ Element: HTMLElement }>>;
    hasDefaultBlock: boolean;
    hasFooterBlock: boolean;
    hasHeaderBlock: boolean;
    heading?: string;
    helperText?: string;
    isFieldset: boolean;
    labelFor: (key: string) => string;
    layout: 'vertical' | 'horizontal';
    mode: FormMode;
    model?: ResolvedFormModel;
    resolvedFields: readonly ResolvedFormField[];
  };
  Blocks: {
    default: [];
    header: [];
    footer: [];
  };
  Element: HTMLElement;
}

export default class FormBody extends Component<FormBodySignature> {
  get hasHeader(): boolean {
    return Boolean(this.args.heading || this.args.description);
  }

  get hasErrors(): boolean {
    return Boolean(this.args.errors?.length);
  }

  get hasResolvedFields(): boolean {
    return this.args.resolvedFields.length > 0;
  }

  <template>
    {{#if @hasHeaderBlock}}
      <header class='bx-form__header'>{{yield to='header'}}</header>
    {{else if this.hasHeader}}
      {{#if @isFieldset}}
        {{#if @heading}}<legend
            class='bx-form__heading'
          >{{@heading}}</legend>{{/if}}
      {{/if}}
      <header
        class='bx-form__header'
        data-bx-form-header-fieldset={{if @isFieldset 'true'}}
      >
        {{#if @heading}}
          {{#unless @isFieldset}}<h2
              class='bx-form__heading'
            >{{@heading}}</h2>{{/unless}}
        {{/if}}
        {{#if @description}}<p
            class='bx-form__description'
          >{{@description}}</p>{{/if}}
      </header>
    {{/if}}

    {{#if this.hasErrors}}
      <FormAlert @type='error'>
        <:messages>
          {{#each @errors as |error|}}
            <p>{{error}}</p>
          {{/each}}
        </:messages>
      </FormAlert>
    {{/if}}

    {{#if @helperText}}<p class='bx-form__helper'>{{@helperText}}</p>{{/if}}

    <div class='bx-form__fields'>
      {{#if @hasDefaultBlock}}
        {{yield}}
      {{else if this.hasResolvedFields}}
        {{#each @resolvedFields as |field|}}
          <FormResolvedField
            @field={{field}}
            @model={{@model}}
            @mode={{@mode}}
          />
        {{/each}}
      {{else}}
        {{#each-in @fields as |key Field|}}
          <FormField @label={{@labelFor key}}>
            <Field />
          </FormField>
        {{/each-in}}
      {{/if}}
    </div>

    {{#if @hasFooterBlock}}
      <footer class='bx-form__footer'>{{yield to='footer'}}</footer>
    {{/if}}
  </template>
}
