// Pretui — Textarea: BoxelInput @type='textarea' in Pretui control dress.
import Component from '@glimmer/component';
import { htmlSafe } from '@ember/template';
import { BoxelInput } from '@cardstack/boxel-ui/components';
import { emit, firstDefined } from '../pretui-primitives';
import type { ControlAliasArgs } from '../pretui-primitives';

export interface TextareaSignature {
  Args: ControlAliasArgs & {
    value?: string;
    placeholder?: string;
    invalid?: boolean;
    controlId?: string;
    onInput?: (value: string) => void;
    /** additive — see Input */
    disabled?: boolean;
    helperText?: string;
    errorMessage?: string;
    required?: boolean;
    optional?: boolean;
    readonly?: boolean;
    /** aliases — see Input */
    isInvalid?: boolean;
    description?: string;
  };
  Element: HTMLTextAreaElement;
}

// Same retrofit as Input, on BoxelInput @type='textarea'. The inline style
// carries the Pretui textarea metrics (64px min-height, 7/9 padding,
// vertical-only resize) — boxel defines its 10rem --boxel-input-height ON
// the textarea element itself, so the wrapper channel cannot override it;
// the inline declaration can.
const TEXTAREA_METRICS = htmlSafe(
  'font: inherit; letter-spacing: inherit; --boxel-input-height: 64px; padding: 7px 9px; resize: vertical;',
);

export class Textarea extends Component<TextareaSignature> {
  get invalid() {
    return firstDefined(this.args.invalid, this.args.isInvalid) ?? false;
  }
  get disabled() {
    return firstDefined(this.args.disabled, this.args.isDisabled);
  }
  get required() {
    return firstDefined(this.args.required, this.args.isRequired);
  }
  get readonly() {
    return firstDefined(
      this.args.readonly,
      this.args.isReadOnly,
      this.args.readOnly,
    );
  }
  get helperText() {
    return firstDefined(this.args.helperText, this.args.description);
  }
  get state() {
    return this.invalid ? 'invalid' : 'none';
  }
  handleInput = (value: string) => {
    emit(
      [this.args.onInput, this.args.onChange, this.args.onValueChange],
      value,
    );
  };
  <template>
    <div
      class='pretui-inputwrap pretui-textareawrap'
      data-invalid={{if this.invalid 'true'}}
      data-test-pretui-textarea
    >
      <BoxelInput
        @id={{@controlId}}
        @type='textarea'
        @value={{@value}}
        @placeholder={{@placeholder}}
        @disabled={{this.disabled}}
        @readonly={{this.readonly}}
        @state={{this.state}}
        @errorMessage={{@errorMessage}}
        @helperText={{this.helperText}}
        @required={{this.required}}
        @optional={{@optional}}
        @onInput={{this.handleInput}}
        style={{TEXTAREA_METRICS}}
        ...attributes
      />
    </div>
    <style scoped>
      @layer PretComponent {
        /* Same re-skin channel as Input — see that component's note. */
        .pretui-inputwrap {
          width: 100%;
          font-size: var(--boxel-font-size-xs);
          letter-spacing: normal;
          --background: var(--field);
          --border: var(--input);
          --ring: var(--primary);
          --muted-foreground: var(--subtle-foreground);
          --boxel-form-control-height: var(--boxel-form-control-height-sm);
          --boxel-form-control-border-radius: var(--radius);
          --boxel-font-size-sm: var(--boxel-font-size-xs);
          --boxel-font-size-xs: var(--boxel-font-size-xs);
          --boxel-sp-xs: var(--boxel-sp-4xs);
          --boxel-sp-sm: var(--boxel-sp-xs);
        }
      }
    </style>
  </template>
}
