import Component from '@glimmer/component';
import { guidFor } from '@ember/object/internals';
import { tracked } from '@glimmer/tracking';
import { modifier } from 'ember-modifier';
import { consume } from 'ember-provide-consume-context';

import { eq } from '../template-helpers.ts';

import {
  FormTabsContextName,
  FormTabRegisterEventName,
  type FormTabsContext,
} from './form-tabs.gts';

export interface FormTabSignature {
  Args: {
    id?: string;
    label: string;
    disabled?: boolean;
  };
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class FormTab extends Component<FormTabSignature> {
  private guid = guidFor(this);
  @tracked private eventActiveId: string | undefined;

  @consume(FormTabsContextName) declare tabs: FormTabsContext | undefined;

  get id(): string {
    return this.args.id ?? this.guid;
  }

  get tabId(): string {
    return `bx-form-tab-${this.guid}`;
  }

  get panelId(): string {
    return `bx-form-tab-panel-${this.guid}`;
  }

  get isActive(): boolean {
    return (this.tabs?.activeId ?? this.eventActiveId) === this.id;
  }

  register = modifier((el: HTMLElement) => {
    let tab = {
      id: this.id,
      label: this.args.label,
      tabId: this.tabId,
      panelId: this.panelId,
      disabled: this.args.disabled,
    };
    let contextUnregister = this.tabs?.register(tab);
    if (contextUnregister) return contextUnregister;

    let unregister: (() => void) | undefined;
    let cancelled = false;
    queueMicrotask(() => {
      if (cancelled) return;
      el.dispatchEvent(
        new CustomEvent(FormTabRegisterEventName, {
          bubbles: true,
          detail: {
            tab,
            updateActiveId: (id: string | undefined) => {
              this.eventActiveId = id;
            },
            setUnregister: (next: () => void) => {
              unregister = next;
            },
          },
        }),
      );
    });

    return () => {
      cancelled = true;
      unregister?.();
    };
  });

  <template>
    <div
      id={{this.panelId}}
      class='bx-form-tab'
      role='tabpanel'
      aria-labelledby={{this.tabId}}
      hidden={{if (eq this.isActive true) false true}}
      data-bx-form-tab-panel={{this.id}}
      data-bx-form-tab-panel-active={{if this.isActive 'true' 'false'}}
      {{this.register}}
      ...attributes
    >
      {{#if this.isActive}}
        {{yield}}
      {{/if}}
    </div>

    <style scoped>
      .bx-form-tab {
        min-width: 0;
      }
    </style>
  </template>
}
