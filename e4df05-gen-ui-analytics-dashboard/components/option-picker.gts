import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { Pill } from '@cardstack/boxel-ui/components';
import { eq } from '@cardstack/boxel-ui/helpers';

// Edit UI shared by the chart's enum fields: one pill per allowed value, the
// selected one filled.
interface OptionPickerSignature {
  Args: {
    options: readonly string[];
    value: string | undefined | null;
    set: (value: string) => void;
    label: string;
  };
  Element: HTMLElement;
}

const OptionPicker: TemplateOnlyComponent<OptionPickerSignature> = <template>
  <ul class='option-picker' aria-label={{@label}} ...attributes>
    {{#each @options as |option|}}
      <li>
        <Pill
          @kind='button'
          @variant={{if (eq @value option) 'primary' 'muted'}}
          aria-pressed={{if (eq @value option) 'true' 'false'}}
          {{on 'click' (fn @set option)}}
          data-test-option={{option}}
        >
          {{option}}
        </Pill>
      </li>
    {{/each}}
  </ul>
  <style scoped>
    .option-picker {
      display: flex;
      flex-wrap: wrap;
      gap: var(--boxel-sp-2xs);
      margin: 0;
      padding: 0;
      list-style: none;
    }
  </style>
</template>;

export default OptionPicker;
