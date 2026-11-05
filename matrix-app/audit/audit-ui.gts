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
    <KeyValue class='audit-facts' @items={{@items}} ...attributes>
      <:value as |item|><span class='audit-value'>{{yield
            item
            to='value'
          }}</span></:value>
    </KeyValue>
  {{else}}
    <KeyValue class='audit-facts' @items={{@items}} ...attributes />
  {{/if}}
  <style scoped>
    /* Doubled class so the alignment outranks KeyValue's own centring
       whatever the stylesheet order: a label sits on its value's first
       line when the value wraps. */
    .audit-facts.audit-facts {
      align-items: baseline;
    }
    .audit-facts {
      --text-ui: var(--boxel-font-size-sm);
      --text-ui-md: var(--boxel-font-size-sm);
      --space-6: var(--boxel-sp-sm);
    }
    /* Inherited by the plain-text values KeyValue renders in its <dd>. */
    .audit-facts {
      overflow-wrap: anywhere;
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
