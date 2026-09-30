import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';
import { Chip } from '@cardstack/pretui/components/chip';
import { FormatNumber } from '@cardstack/pretui/components/format-number';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import type { Hue } from '@cardstack/catalog/components/state-pill';
import { MONEY_LOCALE, MONEY_OPTIONS } from './utils';

// The Pret UI settings the HR cards share, kept in one module so every card
// that shows a command error, an avatar, a money figure, a code token or an
// attention pill renders it the same way.

/** A value's hue in one of the cards' `value → Hue` maps; unknown or empty values get StatePill's slate. */
export function hueOf(
  map: Record<string, Hue>,
  key?: string | null,
): Hue | undefined {
  return (key && map[key]) || undefined;
}

// Pret UI `Alert` paints its tone from the fill tokens, whose text mixes fall
// under 4.5:1 on some grounds. Alert writes its hue as an inline style, so the
// override is inline too: the hue is the tone's `--*-ink` token, the tint is
// 10%, the glyph disc's mark is the card colour, and the body text is the ink.
function alertStyle(ink: string) {
  return htmlSafe(
    `--pretui-alert-hue: var(${ink}); --pretui-chip-mix: 10%; --pretui-on-neutral: var(--card); color: var(${ink})`,
  );
}

export const ALERT_STYLE = {
  danger: alertStyle('--destructive-ink'),
  success: alertStyle('--success-ink'),
};

/**
 * The hue for Pret UI `Avatar`. Avatar tints its disc 16% of the hue and sets
 * its initials at 80% of it, so a fill token as the hue leaves pale initials
 * on a pale disc. `--primary-ink` keeps the primary identity the initials had
 * and clears 4.5:1 in both schemes.
 */
export const AVATAR_HUE = 'var(--primary-ink)';

/** The Avatar hue for a secondary row, where the initials read as muted text. */
export const QUIET_AVATAR_HUE = 'var(--muted-foreground)';

/**
 * Pret UI's `ProgressBar` renders its `role='progressbar'` element with no
 * accessible name and no minimum, so this names it and states the 0 floor.
 * The optional value text replaces the bare "N of M" a screen reader would
 * otherwise announce, for a bar whose count alone would mislead (a run that
 * ended early fills every segment).
 */
export const nameProgress = modifier(
  (element: HTMLElement, [label, valueText]: [string, string?]) => {
    let bar = element.querySelector('[role="progressbar"]');
    bar?.setAttribute('aria-label', label);
    bar?.setAttribute('aria-valuemin', '0');
    if (valueText) {
      bar?.setAttribute('aria-valuetext', valueText);
    } else {
      bar?.removeAttribute('aria-valuetext');
    }
  },
);

// Pret UI `Token` sets its text at `--text-body` minus this offset, so a
// Token that should read at a given size takes that size plus the offset.
const TOKEN_TEXT_OFFSET = '3.5px';

/**
 * Inline style for a Pret UI `Token` drawn in `hue` with its text at `size`
 * (a font-size custom property such as `--boxel-font-size-xs`). Token writes
 * `@hue` as its own inline style, which a caller's `style` would replace, so
 * the hue travels in this style instead of through `@hue`.
 */
export function tokenStyle(size: string, hue: string) {
  return htmlSafe(
    `--pretui-token-hue: ${hue}; --text-body: calc(var(${size}) + ${TOKEN_TEXT_OFFSET})`,
  );
}

// The attention pill: a waiting application, an ageing requisition, a
// bottlenecked approval step. `--attention` reads as "needs a look" where
// `--warning`'s yellow would read as a status. StatePill's hue set has no
// attention hue, so this repeats StatePill's recipe (14% fill, 62% foreground
// ink, `max-width: 100%`) on Pret UI `Chip` by hand. The copy lives here, and
// not in each card, until StatePill grows an `attention` hue; then this
// becomes `<StatePill @hue='attention'>` and the hand-copied recipe goes.
const ATTENTION_CHIP_STYLE = htmlSafe(
  '--pretui-chip-hue: var(--attention); --pretui-chip-mix: 14%; --pretui-ink-mix: 62%; max-width: 100%',
);

interface AttentionPillSignature {
  Args: { label?: string | null };
  Element: HTMLSpanElement;
}

export const AttentionPill: TemplateOnlyComponent<AttentionPillSignature> =
  <template>
    {{#if @label}}
      <Chip style={{ATTENTION_CHIP_STYLE}} ...attributes>
        <span class='attention-label'>{{@label}}</span>
      </Chip>
    {{/if}}
    <style scoped>
      .attention-label {
        overflow: hidden;
        text-overflow: ellipsis;
      }
    </style>
  </template>;

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
