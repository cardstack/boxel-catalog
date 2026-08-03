import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';

// Fires `callback` when a mousedown happens outside the element this is attached to.
const outsideClick = modifier((element: HTMLElement, positional: unknown[]) => {
  const callback = positional[0] as () => void;
  const handler = (event: MouseEvent) => {
    if (!element.contains(event.target as Node)) {
      callback();
    }
  };
  // Delay attaching the listener so we don't catch the click that opened us.
  const timer = setTimeout(() => {
    document.addEventListener('mousedown', handler);
  }, 50);
  return () => {
    clearTimeout(timer);
    document.removeEventListener('mousedown', handler);
  };
});

interface Sig {
  Args: {
    isEditing: boolean;
    canEdit: boolean;
    onEdit: () => void;
    onBlur: () => void;
  };
  Blocks: {
    display: [];
    edit: [];
  };
  Element: HTMLDivElement;
}

export class EditableField extends Component<Sig> {
  @action handleKeyActivate(event: Event) {
    const ev = event as KeyboardEvent;
    if (ev.key === 'Enter' || ev.key === ' ') {
      ev.preventDefault();
      this.args.onEdit();
    }
  }

  <template>
    {{#if @canEdit}}
      {{#if @isEditing}}
        <div
          class='field-edit'
          {{on 'focusout' @onBlur}}
          {{outsideClick @onBlur}}
          ...attributes
        >
          {{yield to='edit'}}
        </div>
      {{else}}
        <div
          class='editable-field'
          role='button'
          tabindex='0'
          title='Double-click to edit'
          {{on 'dblclick' @onEdit}}
          {{on 'keydown' this.handleKeyActivate}}
          ...attributes
        >
          {{yield to='display'}}
        </div>
      {{/if}}
    {{else}}
      <div ...attributes>{{yield to='display'}}</div>
    {{/if}}
    <style scoped>
      .editable-field {
        cursor: text;
        border-radius: var(--boxel-border-radius-sm);
        transition:
          background-color 0.15s,
          outline-color 0.15s;
        outline: 1px solid transparent;
        outline-offset: 2px;
      }
      .editable-field:hover {
        background-color: rgba(123, 97, 255, 0.04);
        outline-color: rgba(123, 97, 255, 0.3);
      }
      .editable-field:focus-visible {
        outline: 2px solid var(--boxel-highlight, #7b61ff);
      }
    </style>
  </template>
}
