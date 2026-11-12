import type { TemplateOnlyComponent } from '@ember/component/template-only';
import {
  KeyValue,
  type KeyValueItem,
} from '@cardstack/pretui/components/key-value';

// The Pret UI settings the audit cards and fields share, kept in one module so
// every fact list in the cluster renders the same way. The settings every
// cluster shares live in `components/pretui-helpers`.

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
    <KeyValue class='audit-facts kv-pad' @items={{@items}} ...attributes>
      <:value as |item|><span class='audit-value'>{{yield
            item
            to='value'
          }}</span></:value>
    </KeyValue>
  {{else}}
    <KeyValue class='audit-facts kv-pad' @items={{@items}} ...attributes />
  {{/if}}
  <style scoped>
    .kv-pad {
      --pretui-kv-pad-inline: var(--boxel-sp-sm);
    }

    /* Doubled class so the alignment outranks KeyValue's own centring
       whatever the stylesheet order: a label sits on its value's first
       line when the value wraps. */
    .audit-facts.audit-facts {
      align-items: baseline;
    }
    /* Our rule beats KeyValue's layered one; the values inherit size and wrapping. */
    .audit-facts {
      --pretui-kv-label-font-size: var(--boxel-font-size-sm);
      font-size: var(--boxel-font-size-sm);
      column-gap: var(--boxel-sp-sm);
      overflow-wrap: break-word;
      min-width: 0;
    }
    .audit-value {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: var(--boxel-sp-2xs);
      min-width: 0;
    }
  </style>
</template>;
