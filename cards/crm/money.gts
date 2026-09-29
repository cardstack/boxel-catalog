import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { FormatNumber } from '@cardstack/pretui/components/format-number';

interface MoneySignature {
  Args: {
    amount?: number;
    /** ISO 4217 code; without one the amount prints as a plain number. */
    code?: string;
  };
  Element: HTMLSpanElement;
}

/**
 * An `AmountWithCurrency` value in a template, through Pret UI `FormatNumber`
 * with the options `formatMoney` uses: `en-US`, the currency style, and up to
 * two decimals when there is no code. Every CRM money line renders through
 * this, so the templates and `formatMoney` read the same. An absent amount
 * shows FormatNumber's `—` placeholder.
 */
export const Money: TemplateOnlyComponent<MoneySignature> = <template>
  <FormatNumber
    @value={{@amount}}
    @style='currency'
    @currency={{@code}}
    @locale='en-US'
    @maximumFractionDigits={{unless @code 2}}
    ...attributes
  />
</template>;
