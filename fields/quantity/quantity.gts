// External dependencies
import { Component } from '@cardstack/base/card-api';
import { on } from '@ember/modifier';
import { lte, gte, not } from '@cardstack/boxel-ui/helpers';
import { Button, BoxelInput } from '@cardstack/boxel-ui/components';

import NumberField, {
  deserializeForUI,
  serializeForUI,
} from '@cardstack/base/number';
import { TextInputValidator } from '@cardstack/base/text-input-validator';
import { NumberSerializer } from '@cardstack/runtime-common';
import Grid2x2Icon from '@cardstack/boxel-icons/grid-2x2';

import { getNumericValue, clamp } from '@cardstack/base/number/util/index';

// Options interface for quantity field
export interface QuantityOptions {
  min?: number;
  max?: number;
}

// TypeScript configuration interface
export type QuantityFieldConfiguration = {
  presentation?: 'quantity';
  options?: QuantityOptions;
};

export default class QuantityField extends NumberField {
  static displayName = 'Quantity Number Field';

  static edit = class Edit extends Component<typeof this> {
    get config() {
      return (this.args.configuration as QuantityFieldConfiguration) ?? {};
    }

    get options() {
      return this.config.options ?? {};
    }

    get numericValue() {
      return getNumericValue(this.args.model);
    }

    get minValue() {
      return this.options.min ?? 0;
    }

    get maxValue() {
      return this.options.max ?? Infinity;
    }

    increment = () => {
      this.args.set(clamp(this.numericValue + 1, this.minValue, this.maxValue));
    };

    decrement = () => {
      this.args.set(clamp(this.numericValue - 1, this.minValue, this.maxValue));
    };

    handleInput = (value: string) => {
      const num = parseFloat(value);
      if (!isNaN(num)) {
        this.args.set(clamp(num, this.minValue, this.maxValue));
      } else if (value === '') {
        this.args.set(this.minValue);
      }
    };

    <template>
      <div class='quantity-field-edit' data-test-quantity-edit>
        <label for='quantity-input' class='sr-only'>Quantity</label>
        <Button
          @kind='text-only'
          @size='auto'
          class='qty-btn'
          data-test-quantity-decrement
          {{on 'click' this.decrement}}
          @disabled={{if
            (not @canEdit)
            true
            (if (lte this.numericValue this.minValue) true)
          }}
        >−</Button>
        <BoxelInput
          id='quantity-input'
          @type='number'
          class='qty-input'
          @value={{this.numericValue}}
          @min={{this.minValue}}
          @max={{this.maxValue}}
          @disabled={{not @canEdit}}
          @onInput={{this.handleInput}}
        />
        <Button
          @kind='text-only'
          @size='auto'
          class='qty-btn'
          data-test-quantity-increment
          {{on 'click' this.increment}}
          @disabled={{if
            (not @canEdit)
            true
            (if (gte this.numericValue this.maxValue) true)
          }}
        >+</Button>
      </div>

      <style scoped>
        .sr-only {
          position: absolute;
          width: 1px;
          height: 1px;
          padding: 0;
          margin: -1px;
          overflow: hidden;
          clip: rect(0, 0, 0, 0);
          border: 0;
        }
        .quantity-field-edit {
          display: flex;
          width: fit-content;
          align-items: center;
          gap: var(--boxel-sp-xs);
        }
        /* No search/validation icon is ever shown here, so collapse
           BoxelInput's reserved icon columns via its own --boxel-input-icon-size
           knob rather than leaving dead space on both sides of the input. */
        .quantity-field-edit :deep(.input-container) {
          --boxel-input-icon-size: 0px;
        }
        .qty-btn {
          width: 2.5rem;
          height: 2.5rem;
          border-radius: 50%;
          border: 2px solid var(--border);
          background-color: var(--background);
          font-size: 1.25rem;
          font-weight: 700;
          cursor: pointer;
          transition: all 0.2s;
          color: var(--foreground);
          flex-shrink: 0;
        }
        .qty-btn:hover:not(:disabled) {
          background-color: var(--primary);
          color: var(--primary-foreground);
          border-color: var(--primary);
        }
        .qty-btn:disabled {
          opacity: 0.4;
          cursor: not-allowed;
        }
        .qty-input {
          width: 4rem;
          height: 2.5rem;
          text-align: center;
          font-size: 1.125rem;
          font-weight: 700;
          padding: 0;
          border: 2px solid var(--border);
          border-radius: var(--boxel-border-radius-xs);
          background-color: var(--background);
          color: var(--foreground);
          outline: none;
          transition: border-color 0.2s;
        }
        .qty-input:focus {
          border-color: var(--primary);
        }
        .qty-input::-webkit-inner-spin-button,
        .qty-input::-webkit-outer-spin-button {
          -webkit-appearance: none;
          margin: 0;
        }
        .qty-input[type='number'] {
          -moz-appearance: textfield;
        }
      </style>
    </template>

    textInputValidator: TextInputValidator<number> = new TextInputValidator(
      () => this.args.model,
      (inputVal) => this.args.set(inputVal),
      deserializeForUI,
      serializeForUI,
      NumberSerializer.validate,
    );
  };

  static embedded = class Embedded extends Component<typeof this> {
    get config() {
      return (this.args.configuration as QuantityFieldConfiguration) ?? {};
    }

    get options() {
      return this.config.options ?? {};
    }

    get numericValue() {
      return getNumericValue(this.args.model);
    }

    <template>
      <span class='quantity-field-embedded' data-test-quantity-embedded>
        <Grid2x2Icon class='qty-icon' />
        <span
          class='qty-value'
          data-test-quantity-value
        >{{this.numericValue}}</span>
      </span>

      <style scoped>
        .quantity-field-embedded {
          display: inline-flex;
          align-items: center;
          gap: calc(var(--spacing) * 2);
          padding: calc(var(--spacing) * 2) calc(var(--spacing) * 3);
          background-color: var(--muted);
          color: var(--muted-foreground);
          border-radius: var(--radius);
          border: 1px solid var(--border);
        }

        .qty-icon {
          width: 1.25rem;
          height: 1.25rem;
          color: var(--muted-foreground);
          flex-shrink: 0;
        }

        .qty-value {
          font-size: 1.125rem;
          font-weight: 700;
          color: var(--foreground);
          line-height: 1;
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof this> {
    get config() {
      return (this.args.configuration as QuantityFieldConfiguration) ?? {};
    }

    get options() {
      return this.config.options ?? {};
    }

    get numericValue() {
      return getNumericValue(this.args.model);
    }

    <template>
      <span class='quantity-atom' data-test-quantity-atom>QTY:
        {{this.numericValue}}</span>

      <style scoped>
        .quantity-atom {
          font-size: 0.6875rem;
          font-weight: 600;
          color: var(--foreground);
          text-transform: uppercase;
          letter-spacing: 0.01em;
        }
      </style>
    </template>
  };
}
