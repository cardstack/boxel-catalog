import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { eq } from '@cardstack/boxel-ui/helpers';
import { contractTypeLabel } from '../../legal/contract-type';
import { Signatory } from '../../legal/signatory';
import { formatMoney } from '../../commerce/line-item-totals';
import { CollectionPanel } from '../../../components/collection-panel';
import { StatePill } from '../../../components/state-pill';
import { SIGNATORY_COLUMNS, openStep, asAny } from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class SignatoriesTab extends GlimmerComponent<Signature> {
  /** Money keeps its minor units — a ceiling missing a digit is $25K vs $250K. */
  authorityLabel = (sg: any): string =>
    formatMoney(
      sg?.signatureAuthority?.amount,
      sg?.signatureAuthority?.currency?.code,
    ) || '—';

  /** An empty type list means unrestricted, which is the opposite of "none". */
  signScope = (sg: any): string => {
    let types = (sg?.contractTypes ?? []).filter(Boolean);
    return types.length
      ? types.map((t: string) => contractTypeLabel(t)).join(' · ')
      : 'All contract types';
  };

  /** Contracts whose open approval step sits with this signatory's person. */
  routedCount = (sg: any): number => {
    let pid = sg?.person?.id;
    if (!pid) return 0;
    return this.args.app.contracts.filter((c: any) => {
      let st = openStep(c);
      return st?.approver?.id === pid || st?.delegatedTo?.id === pid;
    }).length;
  };

  <template>
    <CollectionPanel
      @cardClass={{Signatory}}
      @app.context={{@app.context}}
      @realms={{@app.realmList}}
      @columns={{SIGNATORY_COLUMNS}}
      @label='Signatories'
      @searchPlaceholder='Search signatories…'
      @newLabel='signatory'
      @defaultView='table'
      @sortBy='signingTitle'
    >
      <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
          {{#if (eq column.key 'signatureAuthority')}}
            <span class='cx-fig is-money'>{{this.authorityLabel row}}</span>
          {{else if (eq column.key 'mySign')}}
            <span class='cx-scope'>{{this.signScope row}}</span>
          {{else if (eq column.key 'routed')}}
            {{#let (this.routedCount row) as |n|}}
              {{#if n}}
                <span class='cx-fig'>{{n}}</span>
              {{else}}
                <span class='cx-none'>—</span>
              {{/if}}
            {{/let}}
          {{else if (eq column.key 'isActive')}}
            {{#if row.isActive}}
              <StatePill @label='Active' @hue='green' @dot={{true}} />
            {{else}}
              <StatePill @label='Inactive' @hue='red' @dot={{true}} />
            {{/if}}
          {{/if}}
        {{/let}}</:cell>
    </CollectionPanel>

    <style scoped>
      .cx-num.is-money {
        white-space: nowrap;
      }

      .cx-fig {
        font-family: var(--font-mono);
        font-variant-numeric: tabular-nums;
        font-weight: 650;
      }
      .cx-fig.is-money {
        white-space: nowrap;
      }
      .cx-none {
        color: var(--_cx-muted-fg);
        font-size: var(--boxel-font-size-sm);
      }
      .cx-scope {
        font-size: var(--boxel-font-size-sm);
      }
    </style>
  </template>
}
