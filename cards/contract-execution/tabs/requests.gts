import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  ContractRequest,
  requestStateHue,
  requestStateLabel,
} from '../../legal/contract-request';
import { CollectionPanel } from '../../../components/collection-panel';
import { StatePill } from '../../../components/state-pill';
import { REQUEST_COLUMNS, asAny } from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class RequestsTab extends GlimmerComponent<Signature> {
  <template>
    <p class='cx-note'>Declined requests are kept, with the reason — so "what
      did we turn down, and why" stays answerable.</p>
    <CollectionPanel
      @cardClass={{ContractRequest}}
      @app.context={{@app.context}}
      @realms={{@app.realmList}}
      @columns={{REQUEST_COLUMNS}}
      @label='Intake queue'
      @searchPlaceholder='Search requests by what they are for…'
      @newLabel='request'
      @defaultView='table'
      @sortBy='whatFor'
    >
      <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
          {{#if (eq column.key 'status')}}
            <StatePill
              @label={{requestStateLabel row.status}}
              @hue={{requestStateHue row.status}}
              @dot={{true}}
            />
          {{/if}}
        {{/let}}</:cell>
    </CollectionPanel>

    <style scoped>
      .cx-note {
        margin: 0 0 var(--boxel-sp);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
        color: var(--_cx-muted-fg);
        max-width: var(--_cx-measure);
      }
    </style>
  </template>
}
