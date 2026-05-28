import { on } from '@ember/modifier';
import { action } from '@ember/object';
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';

type FormSectionColumns = 1 | 2 | 3;

export interface FormSectionSignature {
  Args: {
    heading: string;
    description?: string;
    collapsible?: boolean;
    defaultOpen?: boolean;
    columns?: FormSectionColumns;
  };
  Blocks: {
    default: [];
    actions: [];
  };
  Element: HTMLElement;
}

export default class FormSection extends Component<FormSectionSignature> {
  @tracked private openOverride: boolean | undefined;

  get columns(): FormSectionColumns {
    return this.args.columns ?? 1;
  }

  get isOpen(): boolean {
    if (!this.args.collapsible) return true;
    return this.openOverride ?? this.args.defaultOpen ?? true;
  }

  @action
  toggle(): void {
    if (!this.args.collapsible) return;
    this.openOverride = !this.isOpen;
  }

  <template>
    <section
      class='bx-form-section'
      data-bx-form-section
      data-bx-form-section-columns={{this.columns}}
      data-bx-form-section-collapsible={{if @collapsible 'true'}}
      data-bx-form-section-open={{if this.isOpen 'true' 'false'}}
      ...attributes
    >
      <header class='bx-form-section__header'>
        <div class='bx-form-section__copy'>
          {{#if @collapsible}}
            <button
              class='bx-form-section__trigger'
              type='button'
              aria-expanded={{if this.isOpen 'true' 'false'}}
              {{on 'click' this.toggle}}
            >
              <span class='bx-form-section__chevron' aria-hidden='true'></span>
              <span>{{@heading}}</span>
            </button>
          {{else}}
            <h3 class='bx-form-section__heading'>{{@heading}}</h3>
          {{/if}}
          {{#if @description}}
            <p class='bx-form-section__description'>{{@description}}</p>
          {{/if}}
        </div>
        {{#if (has-block 'actions')}}
          <div class='bx-form-section__actions'>{{yield to='actions'}}</div>
        {{/if}}
      </header>

      {{#if this.isOpen}}
        <div class='bx-form-section__fields'>
          {{yield}}
        </div>
      {{/if}}
    </section>

    <style scoped>
      .bx-form-section {
        display: grid;
        grid-column: 1 / -1;
        gap: var(--boxel-sp-sm);
        min-width: 0;
        padding-block: var(--boxel-sp-sm);
        border-block-start: 1px solid var(--hr-color);
        container-type: inline-size;
        container-name: bx-form-section;
      }

      .bx-form-section:first-child {
        padding-block-start: 0;
        border-block-start: 0;
      }

      .bx-form-section__header {
        display: grid;
        grid-template-columns: minmax(0, 1fr) auto;
        gap: var(--boxel-sp-sm);
        align-items: start;
        min-width: 0;
      }

      .bx-form-section__copy {
        display: grid;
        gap: var(--boxel-sp-4xs);
        min-width: 0;
      }

      .bx-form-section__heading,
      .bx-form-section__description {
        margin: 0;
      }

      .bx-form-section__heading,
      .bx-form-section__trigger {
        color: var(--foreground);
        font-family: var(--boxel-subheading-font-family);
        font-size: var(--boxel-subheading-font-size);
        font-weight: var(--boxel-subheading-font-weight);
        line-height: var(--boxel-subheading-line-height);
      }

      .bx-form-section__description {
        color: var(--muted-foreground);
        font-size: var(--boxel-caption-font-size);
        line-height: var(--boxel-caption-line-height);
      }

      .bx-form-section__trigger {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-xs);
        width: fit-content;
        min-width: 0;
        padding: 0;
        border: 0;
        background: transparent;
        cursor: pointer;
      }

      .bx-form-section__trigger:focus {
        outline: 0;
        box-shadow: 0 0 0 var(--boxel-sp-5xs) var(--ring);
      }

      .bx-form-section__chevron {
        width: var(--boxel-sp-xs);
        height: var(--boxel-sp-xs);
        border-inline-end: 2px solid currentColor;
        border-block-end: 2px solid currentColor;
        transform: rotate(-45deg);
        transition: transform var(--boxel-transition);
      }

      .bx-form-section[data-bx-form-section-open='true']
        .bx-form-section__chevron {
        transform: rotate(45deg);
      }

      .bx-form-section__actions {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-xs);
      }

      .bx-form-section__fields {
        display: grid;
        gap: var(--boxel-sp-sm);
        min-width: 0;
      }

      .bx-form-section[data-bx-form-section-columns='2']
        .bx-form-section__fields {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .bx-form-section[data-bx-form-section-columns='3']
        .bx-form-section__fields {
        grid-template-columns: repeat(3, minmax(0, 1fr));
      }

      @container bx-form-section (max-width: 42rem) {
        .bx-form-section__header,
        .bx-form-section[data-bx-form-section-columns='2']
          .bx-form-section__fields,
        .bx-form-section[data-bx-form-section-columns='3']
          .bx-form-section__fields {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </template>
}
