import type { TemplateOnlyComponent } from '@ember/component/template-only';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';

// The Pret UI settings the legal cards and fields share, kept in one module so
// every fact list in the cluster renders the same way. The settings every
// cluster shares live in `components/pretui-helpers`.

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
    <KeyValue class='legal-facts kv-pad' @items={{@items}} ...attributes>
      <:value as |item|><span class='legal-val'>{{yield
            item
            to='value'
          }}</span></:value>
    </KeyValue>
  {{else}}
    <KeyValue class='legal-facts kv-pad' @items={{@items}} ...attributes />
  {{/if}}
  <style scoped>
    .kv-pad {
      padding-inline: var(--boxel-sp-sm);
    }

    /* Doubled class so the alignment outranks KeyValue's own centring
       whatever the stylesheet order: a label sits on its value's first
       line when the value wraps. */
    .legal-facts.legal-facts {
      align-items: baseline;
    }
    .legal-facts {
      --pretui-kv-label-font-size: 0.5625rem; /* 9px ladder label: no token */
      font-size: var(--boxel-font-size-xs);
      column-gap: var(--boxel-sp);
      font-variant-numeric: tabular-nums;
      /* A long value wraps inside its column. */
      overflow-wrap: break-word;
      min-width: 0;
    }
    .legal-val {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-2xs);
      min-width: 0;
    }
  </style>
</template>;
