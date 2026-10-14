import GlimmerComponent from '@glimmer/component';
import { eq } from '@cardstack/boxel-ui/helpers';
import { StatePill } from '../../../components/state-pill';
import { Table } from '../../../components/table';
import type { ContractExecutionView } from '../contract-execution-app';
import { NOTICE_COLUMNS, asAny } from '../contract-execution-data';

interface Signature {
  Args: { app: ContractExecutionView };
}

/** Contracts whose notice window closes inside 90 days, soonest first. */
export class NoticeTable extends GlimmerComponent<Signature> {
  <template>
    <Table
      @columns={{NOTICE_COLUMNS}}
      @items={{@app.renewalRows}}
      @onRowClick={{@app.openCard}}
      @rowClass={{@app.contractSeverity}}
      @caption='Contracts whose notice window closes inside 90 days'
      @emptyMessage='No notice deadline falls inside 90 days.'
    >
      <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
          {{#if (eq column.key 'daysToNotice')}}
            <StatePill @label='{{row.daysToNotice}}d' @hue='amber' />
          {{/if}}
        {{/let}}</:cell>
    </Table>
  </template>
}
