import Component from '@glimmer/component';
import type { ComponentLike } from '@glint/template';

import { element } from '../template-helpers.ts';

import type {
  FormMode,
  ResolvedFormField,
  ResolvedFormFieldInput,
  ResolvedFormModel,
} from '../form-field-resolution.ts';
import { resolveFormFields } from '../form-field-resolution.ts';
import FormBody from './form-body.gts';

type FormTag = 'form' | 'div' | 'section' | 'fieldset';
type FormVariant = 'standalone' | 'embedded';
type FormColumns = 1 | 2 | 3;

export interface FormSignature {
  Args: {
    fields?: Record<string, ComponentLike<{ Element: HTMLElement }>>;
    model?: ResolvedFormModel;
    resolvedFields?: readonly ResolvedFormFieldInput[];
    tag?: FormTag;
    layout?: 'vertical' | 'horizontal';
    density?: 'comfortable' | 'compact';
    columns?: FormColumns;
    mode?: FormMode;
    heading?: string;
    description?: string;
    errors?: readonly string[];
    helperText?: string;
    variant?: FormVariant;
  };
  Blocks: {
    default: [];
    header: [];
    footer: [];
  };
  Element: HTMLElement;
}

export default class Form extends Component<FormSignature> {
  get tag(): FormTag {
    return (
      this.args.tag ?? (this.variant === 'standalone' ? 'form' : 'fieldset')
    );
  }

  get variant(): FormVariant {
    return this.args.variant ?? 'embedded';
  }

  get density(): 'comfortable' | 'compact' {
    return this.args.density ?? 'comfortable';
  }

  get layout(): 'vertical' | 'horizontal' {
    return this.args.layout ?? 'vertical';
  }

  get mode(): FormMode {
    return this.args.mode ?? 'edit';
  }

  get columns(): FormColumns {
    return this.args.columns ?? 1;
  }

  get hasHeader(): boolean {
    return Boolean(this.args.heading || this.args.description);
  }

  get hasErrors(): boolean {
    return Boolean(this.args.errors?.length);
  }

  get isFieldset(): boolean {
    return this.tag === 'fieldset';
  }

  get rootClass(): string {
    return `bx-form bx-form--${this.density} bx-form--${this.layout}`;
  }

  get fields(): Record<string, ComponentLike<{ Element: HTMLElement }>> {
    return this.args.fields ?? {};
  }

  get resolvedFields(): readonly ResolvedFormField[] {
    return resolveFormFields(
      this.args.resolvedFields,
      this.labelFor.bind(this),
    );
  }

  get bodyArgs() {
    return {
      description: this.args.description,
      errors: this.args.errors,
      fields: this.fields,
      heading: this.args.heading,
      helperText: this.args.helperText,
      labelFor: this.labelFor.bind(this),
      layout: this.layout,
      mode: this.mode,
    };
  }

  labelFor(key: string): string {
    return key
      .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
      .replace(/[-_]+/g, ' ')
      .replace(/\b\w/g, (match) => match.toUpperCase());
  }

  <template>
    {{#let (element this.tag) as |Tag|}}
      <Tag
        class={{this.rootClass}}
        data-bx-form
        data-bx-form-columns={{this.columns}}
        data-bx-form-density={{this.density}}
        data-bx-form-layout={{this.layout}}
        data-bx-form-mode={{this.mode}}
        data-bx-form-variant={{this.variant}}
        ...attributes
      >
        <FormBody
          @description={{@description}}
          @errors={{@errors}}
          @fields={{this.fields}}
          @hasDefaultBlock={{has-block}}
          @hasFooterBlock={{has-block 'footer'}}
          @hasHeaderBlock={{has-block 'header'}}
          @heading={{@heading}}
          @helperText={{@helperText}}
          @isFieldset={{this.isFieldset}}
          @labelFor={{this.bodyArgs.labelFor}}
          @layout={{this.layout}}
          @mode={{this.mode}}
          @model={{@model}}
          @resolvedFields={{this.resolvedFields}}
        >
          <:header>{{yield to='header'}}</:header>
          <:default>{{yield}}</:default>
          <:footer>{{yield to='footer'}}</:footer>
        </FormBody>
      </Tag>
    {{/let}}

    <style scoped>
      .bx-form {
        --bx-form-gap: var(--boxel-sp-lg);
        --bx-form-padding: var(--boxel-sp-xl);
        --hr-color: color-mix(in oklch, var(--border) 82%, transparent);

        display: grid;
        gap: var(--bx-form-gap);
        padding: var(--bx-form-padding);
        border: 0;
        border-radius: var(--boxel-border-radius);
        background: var(--background);
        color: var(--foreground);
      }

      .bx-form--compact {
        --bx-form-gap: var(--boxel-sp-sm);
        --bx-form-padding: var(--boxel-sp);
        --boxel-form-control-height: calc(var(--boxel-sp) * 2);
        --boxel-input-height: calc(var(--boxel-sp) * 2);
      }

      .bx-form__header {
        display: grid;
        gap: var(--boxel-sp-2xs);
        padding-bottom: var(--boxel-sp);
        border-bottom: 1px solid var(--hr-color);
      }

      .bx-form__heading {
        margin: 0;
        font-family: var(--boxel-section-heading-font-family);
        font-size: var(--boxel-section-heading-font-size);
        font-weight: var(--boxel-section-heading-font-weight);
        line-height: var(--boxel-section-heading-line-height);
      }

      .bx-form__description,
      .bx-form__helper {
        margin: 0;
        color: var(--muted-foreground);
        font-family: var(--boxel-body-font-family);
        font-size: var(--boxel-body-font-size);
        line-height: var(--boxel-body-line-height);
      }

      .bx-form__fields {
        display: grid;
        gap: var(--bx-form-gap);
      }

      .bx-form[data-bx-form-columns='2'] > .bx-form__fields {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .bx-form[data-bx-form-columns='3'] > .bx-form__fields {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      .bx-form__footer {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
        justify-content: flex-end;
        padding-top: var(--boxel-sp);
        border-top: 1px solid var(--hr-color);
      }
    </style>
  </template>
}
