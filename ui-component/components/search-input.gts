// Pretui — SearchInput: a search field with a clear button.
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { emit, firstDefined, resolveSize } from '../pretui-primitives';
import type { ControlAliasArgs, PretuiSizeArg } from '../pretui-primitives';

// A pill search field drawn here rather than through BoxelInput: boxel's
// search dress puts a fixed 20px magnifier in its own grid column, which no
// knob can bring onto the --boxel-sp ladder. It shares Button's control scale
// (@size; m is 40 high, --boxel-sp inline, base text), with a 16px icon
// --boxel-sp-xs from the text and the clear button --boxel-sp-xs from the end.
// No debounce knob — realm code takes no timers; debounce belongs to the
// consumer's data layer.

export interface SearchInputSignature {
  Args: ControlAliasArgs & {
    value?: string;
    placeholder?: string;
    /** accessible name; without it the field needs an external label for @controlId */
    label?: string;
    disabled?: boolean;
    controlId?: string;
    /** the control scale, same as Button: xs 24 · s 32 · m 40 (default) · l 48 · xl 56 high */
    size?: PretuiSizeArg;
    /** show the clear button once the field holds text — true by default */
    clearable?: boolean;
    onInput?: (value: string) => void;
  };
  Element: HTMLDivElement;
}

export class SearchInput extends Component<SearchInputSignature> {
  @tracked internal = this.args.value ?? '';

  get current() {
    return this.args.value ?? this.internal;
  }
  get showClear() {
    return (
      (this.args.clearable ?? true) && this.current !== '' && !this.disabled
    );
  }
  get size() {
    return resolveSize(this.args.size);
  }
  get disabled() {
    return firstDefined(this.args.disabled, this.args.isDisabled);
  }
  private notify(value: string) {
    emit(
      [this.args.onInput, this.args.onChange, this.args.onValueChange],
      value,
    );
  }
  handleInput = (event: Event) => {
    let value = (event.target as HTMLInputElement).value;
    this.internal = value;
    this.notify(value);
  };
  clear = (_e: Event) => {
    this.internal = '';
    this.notify('');
  };
  <template>
    <div
      class='pretui-search'
      data-size={{this.size}}
      data-test-pretui-search-input
      ...attributes
    >
      <svg
        class='pretui-search-icon'
        viewBox='0 0 16 16'
        width='16'
        height='16'
        aria-hidden='true'
      ><circle
          cx='7'
          cy='7'
          r='4.75'
          fill='none'
          stroke='currentColor'
          stroke-width='1.5'
        /><path
          d='M10.5 10.5L14 14'
          stroke='currentColor'
          stroke-width='1.5'
          stroke-linecap='round'
        /></svg>
      {{! @label names the field when no outside label points at @controlId }}
      {{! template-lint-disable require-input-label }}
      <input
        type='search'
        class='pretui-search-field'
        id={{@controlId}}
        value={{this.current}}
        placeholder={{@placeholder}}
        disabled={{this.disabled}}
        aria-label={{@label}}
        {{on 'input' this.handleInput}}
      />
      {{#if this.showClear}}
        <button
          type='button'
          class='pretui-search-clear'
          aria-label='Clear search'
          {{on 'click' this.clear}}
        >
          <svg
            width='12'
            height='12'
            viewBox='0 0 12 12'
            aria-hidden='true'
          ><path
              d='M3 3l6 6M9 3l-6 6'
              fill='none'
              stroke='currentColor'
              stroke-width='1.5'
              stroke-linecap='round'
            /></svg>
        </button>
      {{/if}}
    </div>
    <style scoped>
      @layer PretComponent {
        .pretui-search {
          display: flex;
          align-items: center;
          gap: var(--boxel-sp-xs);
          inline-size: 100%;
          /* the control scale (m): 40 high, --boxel-sp inline, base text */
          min-block-size: var(--boxel-form-control-height);
          padding: 0 var(--boxel-sp);
          border: 1px solid var(--input);
          border-radius: var(--boxel-border-radius-pill);
          background: var(--field);
          color: var(--foreground);
          font-size: var(--boxel-font-size);
          line-height: 1.5;
          letter-spacing: normal;
          box-sizing: border-box;
        }
        .pretui-search[data-size='xs'] {
          min-block-size: 1.5rem;
          padding-inline: var(--boxel-sp-xs);
          font-size: var(--boxel-font-size-xs);
        }
        .pretui-search[data-size='s'] {
          min-block-size: 2rem;
          padding-inline: var(--boxel-sp-sm);
          font-size: var(--boxel-font-size-sm);
        }
        .pretui-search[data-size='l'] {
          min-block-size: 3rem;
          padding-inline: var(--boxel-sp-lg);
        }
        .pretui-search[data-size='xl'] {
          min-block-size: 3.5rem;
          padding-inline: var(--boxel-sp-lg);
        }
        .pretui-search:focus-within {
          outline: 2px solid var(--ring);
          outline-offset: -1px;
        }
        .pretui-search-icon {
          flex: none;
          color: var(--subtle-foreground);
        }
        .pretui-search-field {
          flex: 1 1 auto;
          min-inline-size: 0;
          padding: 0;
          border: 0;
          background: none;
          color: inherit;
          font-family: inherit;
          font-size: inherit;
          font-weight: inherit;
          line-height: inherit;
          outline: none;
          appearance: none;
        }
        .pretui-search-field::placeholder {
          color: var(--subtle-foreground);
        }
        .pretui-search-field::-webkit-search-cancel-button {
          appearance: none;
        }
        .pretui-search-field:disabled {
          cursor: not-allowed;
          opacity: 0.6;
        }
        .pretui-search-clear {
          flex: none;
          display: grid;
          place-items: center;
          inline-size: 1.25rem;
          block-size: 1.25rem;
          border: 0;
          padding: 0;
          border-radius: var(--boxel-border-radius-pill);
          background: none;
          color: var(--muted-foreground);
        }
        @media (hover: hover) {
          .pretui-search-clear:hover {
            background: var(--hover);
            color: var(--foreground);
          }
        }
        .pretui-search-clear:focus-visible {
          outline: 2px solid var(--ring);
          outline-offset: 1px;
        }
      }
    </style>
  </template>
}
