import { on } from '@ember/modifier';
import { action } from '@ember/object';
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';

import { eq } from '../template-helpers.ts';

export interface FormTabRegistration {
  id: string;
  label: string;
  tabId: string;
  panelId: string;
  disabled?: boolean;
}

export interface FormTabsContext {
  activeId?: string;
  register: (tab: FormTabRegistration) => () => void;
}

export const FormTabsContextName = 'boxel-surface:form-tabs';
export const FormTabRegisterEventName = 'bx-form-tab-register';

export interface FormTabRegisterEventDetail {
  tab: FormTabRegistration;
  updateActiveId: (id: string | undefined) => void;
  setUnregister: (unregister: () => void) => void;
}

export interface FormTabsSignature {
  Args: {
    activeTab?: string;
    defaultTab?: string;
    onChange?: (id: string) => void;
  };
  Blocks: {
    default: [];
  };
  Element: HTMLElement;
}

export default class FormTabs extends Component<FormTabsSignature> {
  @tracked private tabs: FormTabRegistration[] = [];
  @tracked private activeOverride: string | undefined;
  private tabUpdaters = new Map<string, (id: string | undefined) => void>();

  get activeId(): string | undefined {
    return (
      this.activeOverride ??
      this.args.activeTab ??
      this.args.defaultTab ??
      this.tabs.find((tab) => !tab.disabled)?.id ??
      this.tabs[0]?.id
    );
  }

  registerTab = (
    tab: FormTabRegistration,
    updateActiveId?: (id: string | undefined) => void,
  ): (() => void) => {
    let existingIndex = this.tabs.findIndex(
      (candidate) => candidate.id === tab.id,
    );
    if (existingIndex === -1) {
      this.tabs = [...this.tabs, tab];
    } else {
      this.tabs = this.tabs.map((candidate, index) =>
        index === existingIndex ? tab : candidate,
      );
    }
    if (updateActiveId) {
      this.tabUpdaters.set(tab.id, updateActiveId);
    }

    this.syncPanels();

    return () => {
      this.tabs = this.tabs.filter((candidate) => candidate.id !== tab.id);
      this.tabUpdaters.delete(tab.id);
      if (this.activeOverride === tab.id) {
        this.activeOverride = undefined;
      }
      this.syncPanels();
    };
  };

  private syncPanels(): void {
    for (let update of this.tabUpdaters.values()) {
      update(this.activeId);
    }
  }

  get context(): FormTabsContext {
    return {
      activeId: this.activeId,
      register: this.registerTab,
    };
  }

  @action
  select(id: string): void {
    let tab = this.tabs.find((candidate) => candidate.id === id);
    if (!tab || tab.disabled) return;
    this.activeOverride = id;
    this.syncPanels();
    this.args.onChange?.(id);
  }

  @action
  selectFromEvent(event: Event): void {
    let id = (event.currentTarget as HTMLElement).dataset['bxFormTabId'];
    if (!id) return;
    this.select(id);
  }

  @action
  registerFromEvent(event: Event): void {
    let detail = (event as CustomEvent<FormTabRegisterEventDetail>).detail;
    if (!detail) return;
    event.stopPropagation();
    let unregister = this.registerTab(detail.tab, detail.updateActiveId);
    detail.setUnregister(unregister);
  }

  <template>
    <div
      class='bx-form-tabs'
      data-bx-form-tabs
      {{on FormTabRegisterEventName this.registerFromEvent}}
      ...attributes
    >
      <div class='bx-form-tabs__list' role='tablist'>
        {{#each this.tabs as |tab|}}
          <button
            id={{tab.tabId}}
            class='bx-form-tabs__tab'
            type='button'
            role='tab'
            aria-selected={{if (eq tab.id this.activeId) 'true' 'false'}}
            aria-controls={{tab.panelId}}
            disabled={{tab.disabled}}
            data-bx-form-tab-active={{if
              (eq tab.id this.activeId)
              'true'
              'false'
            }}
            data-bx-form-tab-id={{tab.id}}
            {{on 'click' this.selectFromEvent}}
          >
            {{tab.label}}
          </button>
        {{/each}}
      </div>

      <div class='bx-form-tabs__panels'>
        {{yield}}
      </div>
    </div>

    <style scoped>
      .bx-form-tabs {
        display: grid;
        gap: var(--boxel-sp);
        min-width: 0;
        container-type: inline-size;
        container-name: bx-form-tabs;
      }

      .bx-form-tabs__list {
        display: flex;
        flex-wrap: wrap;
        gap: var(--boxel-sp-4xs);
        border-block-end: 1px solid var(--border);
      }

      .bx-form-tabs__tab {
        position: relative;
        min-width: 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp-sm);
        border: 0;
        border-radius: var(--boxel-border-radius-sm)
          var(--boxel-border-radius-sm) 0 0;
        background: transparent;
        color: var(--muted-foreground);
        font: inherit;
        font-weight: var(--boxel-subheading-font-weight);
        cursor: pointer;
      }

      .bx-form-tabs__tab::after {
        position: absolute;
        inset-inline: var(--boxel-sp-xs);
        inset-block-end: calc(var(--boxel-sp-6xs) * -1);
        height: var(--boxel-sp-4xs);
        border-radius: var(--boxel-border-radius-xs);
        background: transparent;
        content: '';
      }

      .bx-form-tabs__tab[data-bx-form-tab-active='true'] {
        background: var(--card);
        color: var(--card-foreground);
      }

      .bx-form-tabs__tab[data-bx-form-tab-active='true']::after {
        background: var(--ring);
      }

      .bx-form-tabs__tab:focus {
        outline: 0;
        box-shadow: 0 0 0 var(--boxel-sp-5xs) var(--ring);
      }

      .bx-form-tabs__tab:disabled {
        color: var(--muted-foreground);
        cursor: not-allowed;
        opacity: 0.6;
      }

      .bx-form-tabs__panels {
        display: grid;
        min-width: 0;
      }

      @container bx-form-tabs (max-width: 32rem) {
        .bx-form-tabs__list {
          display: grid;
          grid-template-columns: 1fr;
          border-block-end: 0;
        }

        .bx-form-tabs__tab {
          border-radius: var(--boxel-border-radius-sm);
          text-align: start;
        }

        .bx-form-tabs__tab::after {
          inset-inline: auto var(--boxel-sp-xs);
          inset-block: var(--boxel-sp-xs);
          width: var(--boxel-sp-4xs);
          height: auto;
        }
      }
    </style>
  </template>
}
