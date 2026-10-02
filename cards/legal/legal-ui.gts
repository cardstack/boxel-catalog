import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { htmlSafe } from '@ember/template';
import { modifier } from 'ember-modifier';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { tokenStyle } from '@cardstack/catalog/fields/shared/pretui-token';

// The Pret UI settings the legal cards and fields share, kept in one module so
// every fact list, reference, empty section, verdict and score bar in the
// cluster renders the same way.

/**
 * Pret UI `Token` for a machine value (contract reference, registration
 * number, clause section, signature reference) in the muted hue, at the size
 * each view sets it in.
 */
export const ID_TOKEN_STYLE = {
  sm: tokenStyle('--boxel-font-size-sm', 'var(--muted-foreground)'),
  xs: tokenStyle('--boxel-font-size-xs', 'var(--muted-foreground)'),
};

/**
 * Pret UI `EmptyState` tuned through its own spacing and title knobs to a
 * compact well that sits inside a section instead of filling the page.
 */
export const COMPACT_EMPTY_STYLE = htmlSafe(
  '--space-9: 1rem; --space-6: 1rem; --text-heading: var(--boxel-font-size)',
);

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
  attention: alertStyle('--attention-ink'),
};

/**
 * Pret UI's `ProgressBar` renders its `role='progressbar'` element with no
 * accessible name and no minimum, so this names it and states the 0 floor.
 */
export const nameProgress = modifier(
  (element: HTMLElement, [label]: [string]) => {
    let bar = element.querySelector('[role="progressbar"]');
    bar?.setAttribute('aria-label', label);
    bar?.setAttribute('aria-valuemin', '0');
  },
);

interface LegalFactsSignature {
  Args: { items: KeyValueItem[] };
  Blocks: { value: [item: KeyValueItem] };
  Element: HTMLDListElement;
}

/**
 * A card's labelled facts as Pret UI `KeyValue` rows. Keys and values both
 * read at the small size, and a long value (an address, a linked card) wraps
 * inside its column. An optional `value` block renders a row's value, as it
 * does on KeyValue.
 */
export const LegalFacts: TemplateOnlyComponent<LegalFactsSignature> = <template>
  {{#if (has-block 'value')}}
    <KeyValue class='legal-facts' @items={{@items}} ...attributes>
      <:value as |item|>{{yield item to='value'}}</:value>
    </KeyValue>
  {{else}}
    <KeyValue class='legal-facts' @items={{@items}} ...attributes />
  {{/if}}
  <style scoped>
    /* Doubled class so the alignment outranks KeyValue's own centring
       whatever the stylesheet order: a label sits on its value's first
       line when the value wraps. */
    .legal-facts.legal-facts {
      align-items: baseline;
    }
    .legal-facts {
      --text-ui: var(--boxel-font-size-sm);
      --text-ui-md: var(--boxel-font-size-sm);
      --space-6: var(--boxel-sp);
      font-variant-numeric: tabular-nums;
    }
    .legal-facts :deep(dd) {
      flex-wrap: wrap;
      min-width: 0;
      overflow-wrap: anywhere;
    }
  </style>
</template>;
