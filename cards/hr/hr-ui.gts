import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import {
  stateColor,
  type Hue,
  type StateColor,
} from '@cardstack/catalog/components/state-pill';
import { MONEY_LOCALE, MONEY_OPTIONS } from './utils';

// The Pret UI settings the HR cards share, kept in one module so every card
// that shows a muted avatar, a money figure or a fact list renders it the
// same way. The settings every cluster shares live in
// `components/pretui-helpers`.

/** A value's hue in one of the cards' `value → Hue` maps; unknown or empty values get StatePill's slate. */
export function hueOf(
  map: Record<string, Hue>,
  key?: string | null,
): Hue | undefined {
  return (key && map[key]) || undefined;
}

/** A `value → Hue` map as the `value → StateColor` map an avatar ring or a hand-built mark reads. */
export function stateColorsOf(
  hues: Record<string, Hue>,
): Record<string, StateColor> {
  return Object.fromEntries(
    Object.entries(hues).map(([k, hue]) => [k, stateColor(hue)]),
  );
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
 * role every HR detail view uses for its labels, set through KeyValue's
 * label knobs. An
 * optional `value` block renders a row's value, as it does on KeyValue.
 */
export const FactList: TemplateOnlyComponent<FactListSignature> = <template>
  {{#if (has-block 'value')}}
    <KeyValue class='hr-facts kv-pad' @items={{@items}} ...attributes>
      <:value as |item|>{{yield item to='value'}}</:value>
    </KeyValue>
  {{else}}
    <KeyValue class='hr-facts kv-pad' @items={{@items}} ...attributes />
  {{/if}}
  <style scoped>
    .kv-pad {
      --pretui-kv-pad-inline: var(--boxel-sp-sm);
    }

    .hr-facts {
      font-size: var(--boxel-font-size-sm);
      column-gap: var(--boxel-sp);
      --pretui-kv-label-font-size: var(--boxel-eyebrow-font-size);
      --pretui-kv-label-font-weight: var(--boxel-eyebrow-font-weight);
      --pretui-kv-label-line-height: var(--boxel-eyebrow-line-height);
      --pretui-kv-label-letter-spacing: var(--boxel-eyebrow-letter-spacing);
      --pretui-kv-label-text-transform: uppercase;
      font-variant-numeric: tabular-nums;
    }
  </style>
</template>;
