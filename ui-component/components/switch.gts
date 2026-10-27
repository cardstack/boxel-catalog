// Switch: immediate on/off. A checked setting, not a Toggle press.
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { emit, firstDefined } from '../pretui-primitives';

export interface SwitchSignature {
  Args: {
    checked?: boolean;
    defaultChecked?: boolean;
    disabled?: boolean;
    controlId?: string;
    onCheckedChange?: (checked: boolean) => void;
    /** aliases of @checked */
    isSelected?: boolean;
    selected?: boolean;
    /** alias of @disabled */
    isDisabled?: boolean;
    /** alias — the HTML notify name for a checked control */
    onChange?: (checked: boolean) => void;
  };
  Element: HTMLButtonElement;
}

export class Switch extends Component<SwitchSignature> {
  @tracked internal = this.args.defaultChecked ?? false;
  get controlled() {
    return firstDefined(
      this.args.checked,
      this.args.isSelected,
      this.args.selected,
    );
  }
  get disabled() {
    return firstDefined(this.args.disabled, this.args.isDisabled) ?? false;
  }
  get on() {
    return this.controlled ?? this.internal;
  }
  toggle = () => {
    if (this.disabled) {
      return;
    }
    let next = !this.on;
    if (this.controlled === undefined) {
      this.internal = next;
    }
    emit([this.args.onCheckedChange, this.args.onChange], next);
  };
  <template>
    <button
      type='button'
      role='switch'
      id={{@controlId}}
      aria-checked={{if this.on 'true' 'false'}}
      class='pretui-switch'
      data-state={{if this.on 'checked' 'unchecked'}}
      disabled={{this.disabled}}
      data-test-pretui-switch
      {{on 'click' this.toggle}}
      ...attributes
    ><span class='pretui-switch-thumb'></span></button>
    <style scoped>
      @layer PretComponent {
        .pretui-switch {
          position: relative;
          width: 1.875rem;
          height: 1.125rem;
          border-radius: var(--boxel-border-radius-pill);
          background: var(--pretui-control-border, var(--input));
          cursor: pointer;
          border: 0;
          padding: 0;
          transition: background var(--pretui-dur-snap, 180ms)
            var(--pretui-ease-snap, ease);
          flex: none;
        }
        .pretui-switch:active:not(:disabled) {
          box-shadow: var(--pretui-shadow-inset, var(--shadow-inset));
        }
        .pretui-switch[data-state='checked'] {
          background: var(--primary);
        }
        .pretui-switch:disabled {
          opacity: 0.45;
          cursor: default;
        }
        .pretui-switch-thumb {
          position: absolute;
          top: 0.125rem;
          left: 0.125rem;
          width: 0.875rem;
          height: 0.875rem;
          border-radius: 50%;
          background: var(--card);
          box-shadow: var(--shadow-xs);
          transition: transform var(--pretui-dur-snap, 180ms)
            var(--pretui-ease-snap, ease);
        }
        .pretui-switch[data-state='checked'] .pretui-switch-thumb {
          transform: translateX(0.75rem);
        }
        @media (prefers-reduced-motion: reduce) {
          .pretui-switch,
          .pretui-switch-thumb {
            transition: none;
          }
        }
      }
    </style>
  </template>
}
