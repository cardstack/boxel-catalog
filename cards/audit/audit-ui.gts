import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { htmlSafe } from '@ember/template';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';
import { tokenStyle } from '@cardstack/catalog/fields/shared/pretui-token';

// The Pret UI settings the audit cards and fields share, kept in one module so
// every id, empty list, seal and fact list in the cluster renders the same way.

/**
 * Pret UI `Token` for a machine value (finding id, rule id, field path, hash,
 * clause reference) in the muted hue, at the size each view set it in.
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

/**
 * The hue for Pret UI `Avatar`. Avatar tints its disc 16% of the hue and sets
 * its initials at 80% of it, so a fill token as the hue leaves pale initials
 * on a pale disc. `--primary-ink` keeps the primary identity the seal had and
 * clears 4.5:1 in both schemes.
 */
export const AVATAR_HUE = 'var(--primary-ink)';

interface AuditFactsSignature {
  Args: { items: KeyValueItem[] };
  Blocks: { value: [item: KeyValueItem] };
  Element: HTMLDListElement;
}

/**
 * A card's labelled facts as Pret UI `KeyValue` rows. Keys and values both
 * read at the small size, and a long value (a rule statement, an observed
 * value, a JSON query) wraps inside its column. An optional `value` block
 * renders a row's value, as it does on KeyValue.
 */
export const AuditFacts: TemplateOnlyComponent<AuditFactsSignature> = <template>
  {{#if (has-block 'value')}}
    <KeyValue class='audit-facts' @items={{@items}} ...attributes>
      <:value as |item|>{{yield item to='value'}}</:value>
    </KeyValue>
  {{else}}
    <KeyValue class='audit-facts' @items={{@items}} ...attributes />
  {{/if}}
  <style scoped>
    .audit-facts {
      --text-ui: var(--boxel-font-size-sm);
      --text-ui-md: var(--boxel-font-size-sm);
      --space-6: var(--boxel-sp-sm);
    }
    .audit-facts :deep(dd) {
      flex-wrap: wrap;
      min-width: 0;
      overflow-wrap: anywhere;
    }
  </style>
</template>;
