import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { eq } from '@cardstack/boxel-ui/helpers';
import { ContractTemplate } from '../../legal/contract-template';
import { CollectionPanel } from '../../../components/collection-panel';
import { StatePill } from '../../../components/state-pill';
import { TEMPLATE_COLUMNS, asAny } from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class TemplatesTab extends GlimmerComponent<Signature> {
  <template>
    <p class='cx-note'>A starting position for each contract type — the clauses
      it assumes, and what you still have to supply.</p>
    <CollectionPanel
      @cardClass={{ContractTemplate}}
      @context={{@app.context}}
      @realms={{@app.realmList}}
      @columns={{TEMPLATE_COLUMNS}}
      @label='Template library'
      @searchPlaceholder='Search templates by name or use case…'
      @newLabel='template'
      @defaultView='table'
      @sortBy='templateName'
    >
      <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
          {{#if (eq column.key 'isPublished')}}
            {{#if row.isPublished}}
              <StatePill @label='Published' @hue='green' @dot={{true}} />
            {{else}}
              <StatePill @label='Draft' @hue='slate' @dot={{true}} />
            {{/if}}
          {{/if}}
        {{/let}}</:cell>
    </CollectionPanel>

    <style scoped>
      .cx-note {
        margin: 0 0 var(--boxel-sp);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
        color: var(--muted-foreground);
        max-width: var(--_cx-measure);
      }
    </style>
  </template>
}
