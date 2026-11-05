// Pretui — PhoneInput: boxel-ui's formatted phone field in Pretui cloth.
import Component from '@glimmer/component';
import { PhoneInput as BoxelPhoneInput } from '@cardstack/boxel-ui/components';
import type { NormalizePhoneFormatResult } from '@cardstack/boxel-ui/helpers';
import { emit, firstDefined } from '../pretui-primitives';
import type { ControlAliasArgs } from '../pretui-primitives';

// Same wrap as EmailInput: boxel-ui's awesome-phonenumber machinery
// (as-you-type formatting, E.164 normalization, region validation) intact,
// Pretui cloth via the token channel. onChange's NormalizePhoneFormatResult
// collapses to @onValidation(errorMessage | null); @onInput receives the
// sanitized value boxel emits (E.164 when valid, trimmed digits otherwise).

export interface PhoneInputSignature {
  Args: ControlAliasArgs & {
    value?: string;
    placeholder?: string;
    disabled?: boolean;
    required?: boolean;
    controlId?: string;
    onInput?: (value: string) => void;
    onValidation?: (error: string | null) => void;
  };
  Element: HTMLDivElement;
}

export class PhoneInput extends Component<PhoneInputSignature> {
  get boxelValue() {
    return this.args.value ?? null;
  }
  get disabled() {
    return firstDefined(this.args.disabled, this.args.isDisabled);
  }
  get required() {
    return firstDefined(this.args.required, this.args.isRequired);
  }
  handleChange = (
    value: string | null,
    validation: NormalizePhoneFormatResult | null,
    _ev: Event,
  ) => {
    emit(
      [this.args.onInput, this.args.onChange, this.args.onValueChange],
      value ?? '',
    );
    this.args.onValidation?.(
      validation && !validation.ok ? validation.error.message : null,
    );
  };
  <template>
    <div class='pretui-boxelwrap' data-test-pretui-phone-input ...attributes>
      <BoxelPhoneInput
        @value={{this.boxelValue}}
        @onChange={{this.handleChange}}
        @placeholder={{@placeholder}}
        @disabled={{this.disabled}}
        @required={{this.required}}
        id={{@controlId}}
      />
    </div>
    <style scoped>
      @layer PretComponent {
        /* Same re-skin channel as EmailInput — see that component's note. */
        .pretui-boxelwrap {
          width: 100%;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: normal;
          --background: var(--field);
          --border: var(--input);
          --ring: var(--primary);
          --boxel-form-control-height: var(--boxel-form-control-height-sm);
          --boxel-input-height: var(--boxel-form-control-height-sm);
          --boxel-form-control-border-radius: var(--radius);
          --boxel-sp-xs: 0.3125rem;
          --boxel-sp-sm: 0.5625rem;
        }
      }
    </style>
  </template>
}
