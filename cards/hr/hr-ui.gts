import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import type { Hue } from '@cardstack/catalog/components/state-pill';
import { MONEY_LOCALE, MONEY_OPTIONS } from './utils';

// The Pret UI settings the HR cards share, kept in one module so every card
// that shows a muted avatar, a money figure, a fact list
// renders it the same way. The settings every cluster shares live in
// `components/pretui-helpers`.

/** A value's hue in one of the cards' `value → Hue` maps; unknown or empty values get StatePill's slate. */
export function hueOf(
  map: Record<string, Hue>,
  key?: string | null,
): Hue | undefined {
  return (key && map[key]) || undefined;
}

/** The Avatar hue for a secondary row, where the initials read as muted text. */
export const QUIET_AVATAR_HUE = 'var(--muted-foreground)';

interface MoneySignature {
  Args: { amount?: number | null };
  Element: HTMLSpanElement;
}

function present(value: number | null | undefined) {
  return value ?? undefined;
}

/**
 * A dollar figure in a template, through Pret UI `FormatNumber` with the
 * `MONEY_LOCALE` / `MONEY_OPTIONS` that `formatMoney` formats with, so the two
 * print the same string. An absent amount shows FormatNumber's `—`.
 */
export const Money: TemplateOnlyComponent<MoneySignature> = <template>
  <FormatNumber
    @value={{present @amount}}
    @locale={{MONEY_LOCALE}}
    @style={{MONEY_OPTIONS.style}}
    @currency={{MONEY_OPTIONS.currency}}
    @minimumFractionDigits={{MONEY_OPTIONS.minimumFractionDigits}}
    @maximumFractionDigits={{MONEY_OPTIONS.maximumFractionDigits}}
    ...attributes
  />
</template>;

interface MoneyRangeSignature {
  Args: { min?: number | null; max?: number | null };
  Element: HTMLSpanElement;
}

function bothPresent(a?: number | null, b?: number | null) {
  return a != null && b != null;
}

function eitherOf(a?: number | null, b?: number | null) {
  return a ?? b;
}

/** A salary band, "$120,000–$150,000", or the one end that is set. */
export const MoneyRange: TemplateOnlyComponent<MoneyRangeSignature> = <template>
  <span ...attributes>{{#if (bothPresent @min @max)}}<Money
        @amount={{@min}}
      />–<Money @amount={{@max}} />{{else}}<Money
        @amount={{eitherOf @min @max}}
      />{{/if}}</span>
</template>;

interface FactListSignature {
  Args: { items: KeyValueItem[] };
  Blocks: { value: [item: KeyValueItem] };
  Element: HTMLDListElement;
}

/**
 * A card's facts as Pret UI `KeyValue` rows, with the keys in the eyebrow
 * role every HR detail view uses for its labels. KeyValue's key text takes
 * only a size (`--text-ui`, which it shares with the rest of the kit) and has
 * no key block, so the eyebrow's family, weight, tracking and case reach its
 * `dt` from here — the one rule every card's fact list goes through. An
 * optional `value` block renders a row's value, as it does on KeyValue.
 */
export const FactList: TemplateOnlyComponent<FactListSignature> = <template>
  {{#if (has-block 'value')}}
    <KeyValue class='hr-facts' @items={{@items}} ...attributes>
      <:value as |item|>{{yield item to='value'}}</:value>
    </KeyValue>
  {{else}}
    <KeyValue class='hr-facts' @items={{@items}} ...attributes />
  {{/if}}
  <style scoped>
    .hr-facts {
      --text-ui-md: var(--boxel-font-size-sm);
      --space-6: var(--boxel-sp);
      font-variant-numeric: tabular-nums;
    }
    .hr-facts :deep(dt) {
      font-family: var(--boxel-eyebrow-font-family);
      font-size: var(--boxel-eyebrow-font-size);
      font-weight: var(--boxel-eyebrow-font-weight);
      line-height: var(--boxel-eyebrow-line-height);
      letter-spacing: var(--boxel-eyebrow-letter-spacing);
      text-transform: uppercase;
    }
  </style>
</template>;
