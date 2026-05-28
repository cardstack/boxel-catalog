import Component from '@glimmer/component';
import { SuccessBordered, Warning, ExclamationCircle } from '../icons/index.ts';

export type FormAlertSeverity = 'error' | 'warning' | 'info' | 'success';

export interface FormAlertSignature {
  Args: {
    type?: FormAlertSeverity;
  };
  Blocks: {
    default: [];
    messages: [];
    actions: [];
  };
  Element: HTMLElement;
}

export default class FormAlert extends Component<FormAlertSignature> {
  get type(): FormAlertSeverity {
    return this.args.type ?? 'info';
  }

  get isError(): boolean {
    return this.type === 'error';
  }

  get isWarning(): boolean {
    return this.type === 'warning';
  }

  get isSuccess(): boolean {
    return this.type === 'success';
  }

  get isInfo(): boolean {
    return this.type === 'info';
  }

  <template>
    <div
      class='bx-form-alert bx-form-alert--{{this.type}}'
      data-bx-form-alert={{this.type}}
      role={{if this.isError 'alert' 'status'}}
      ...attributes
    >
      <span class='bx-form-alert__icon' aria-hidden='true'>
        {{#if this.isSuccess}}
          <SuccessBordered
            class='bx-form-alert__icon-svg'
            role='presentation'
          />
        {{else if this.isWarning}}
          <Warning class='bx-form-alert__icon-svg' role='presentation' />
        {{else if this.isError}}
          <Warning class='bx-form-alert__icon-svg' role='presentation' />
        {{else}}
          <ExclamationCircle
            class='bx-form-alert__icon-svg'
            role='presentation'
          />
        {{/if}}
      </span>
      <div class='bx-form-alert__messages'>
        {{#if (has-block 'messages')}}
          {{yield to='messages'}}
        {{else}}
          {{yield}}
        {{/if}}
      </div>
      {{#if (has-block 'actions')}}
        <div class='bx-form-alert__actions'>
          {{yield to='actions'}}
        </div>
      {{/if}}
    </div>

    <style scoped>
      .bx-form-alert {
        --bx-form-alert-color: var(--primary);

        display: grid;
        grid-template-columns: auto minmax(0, 1fr) auto;
        align-items: start;
        gap: var(--boxel-sp-sm);
        padding: var(--boxel-sp-sm);
        border: 1px solid var(--bx-form-alert-color);
        border-radius: var(--boxel-border-radius-sm);
        background: color-mix(
          in oklch,
          var(--bx-form-alert-color) 8%,
          transparent
        );
        color: var(--foreground);
        font: inherit;
      }

      .bx-form-alert--error {
        --bx-form-alert-color: var(--destructive);
      }

      .bx-form-alert--warning {
        --bx-form-alert-color: var(--warning);
      }

      .bx-form-alert--success {
        --bx-form-alert-color: var(--success);
      }

      .bx-form-alert__icon {
        display: grid;
        place-items: center;
        width: 20px;
        height: 20px;
        color: var(--bx-form-alert-color);
        --icon-color: currentColor;
      }

      .bx-form-alert__icon-svg {
        width: 20px;
        height: 20px;
      }

      .bx-form-alert__messages {
        display: grid;
        gap: var(--boxel-sp-3xs);
        min-width: 0;
        font-size: var(--boxel-body-font-size);
        line-height: var(--boxel-body-line-height);
      }

      .bx-form-alert__messages :deep(p) {
        margin: 0;
      }

      .bx-form-alert__actions {
        display: flex;
        justify-content: flex-end;
      }
    </style>
  </template>
}
