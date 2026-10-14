import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { eq } from '@cardstack/boxel-ui/helpers';
import { StatePill } from '../../../components/state-pill';
import { Table } from '../../../components/table';
import { NOTICE_COLUMNS, asAny } from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class RenewalsTab extends GlimmerComponent<Signature> {
  <template>
    <section class='cx-sec' aria-label='Renewal calendar'>
      <h2 class='cx-h'>Notice windows, soonest first
        <span class='cx-h-sub'>{{@app.renewalRows.length}}</span></h2>
      <p class='cx-note'>A renewal is decided by the notice date, not the end
        date — miss the notice window and the contract renews whether or not
        anyone wanted it to.</p>
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

      <p class='cx-blocked'>
        <span class='cx-blocked-l'>Not yet firing</span>
        Reminder dates can be set on an obligation, but nothing sends them yet —
        check this tab rather than waiting to be told.</p>
    </section>

    <style scoped>
      .cx-sec {
        display: flex;
        flex-direction: column;
        gap: var(--boxel-sp);
      }
      .cx-h {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp-xxs);
        margin: 0;
        font-size: var(--boxel-font-size-sm);
        font-weight: 600;
      }
      .cx-h-sub {
        margin-left: 6px;
        font-family: var(--font-mono);
        font-size: 11px;
        font-weight: 400;
        color: var(--_cx-muted-fg);
      }

      .cx-note {
        margin: 0 0 var(--boxel-sp);
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
        color: var(--_cx-muted-fg);
        max-width: var(--_cx-measure);
      }
      .cx-blocked {
        margin: var(--boxel-sp) 0 0;
        padding: var(--boxel-sp-xs) var(--boxel-sp);
        background: var(
          --_cx-sunk,
          color-mix(in oklch, currentColor 4%, transparent)
        );
        color: var(--_cx-sunk-fg);
        border-left: 3px solid var(--_cx-muted-fg);
        border-radius: 0 var(--radius) var(--radius) 0;
        font-size: var(--boxel-font-size-sm);
        line-height: 1.55;
        max-width: var(--_cx-measure);
      }
      .cx-blocked-l {
        display: block;
        margin-bottom: 4px;
        font-family: var(--font-mono);
        font-size: 10px;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: var(--_cx-muted-fg);
      }
    </style>
  </template>
}
