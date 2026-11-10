import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { on } from '@ember/modifier';
import { Avatar } from '@cardstack/pretui/components/avatar';
import { Button } from '@cardstack/pretui/components/button';
import { fn } from '@ember/helper';
import { contractTypeLabel } from '../../legal/contract-type';
import { formatMoney } from '../../commerce/line-item-totals';
import { openStep } from '../contract-execution-data';
import { Block, CeTable, type Col } from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

export class SignatoriesTab extends GlimmerComponent<Signature> {
  routedCount = (sg: any): number => {
    let pid = sg?.person?.id;
    if (!pid) return 0;
    return this.args.app.contracts.filter((c: any) => {
      let st = openStep(c);
      return st?.approver?.id === pid || st?.delegatedTo?.id === pid;
    }).length;
  };

  columns: Col[] = [
    { label: 'Signatory', kind: 'custom' },
    {
      label: 'Authority ceiling',
      kind: 'mono',
      align: 'end',
      value: (sg) =>
        formatMoney(
          sg.signatureAuthority?.amount,
          sg.signatureAuthority?.currency?.code,
        ) || '—',
    },
    {
      label: 'May sign',
      value: (sg) => {
        let types = (sg.contractTypes ?? []).filter(Boolean);
        return types.length
          ? types.map((t: string) => contractTypeLabel(t)).join(', ')
          : 'Any contract type';
      },
    },
    {
      label: 'Routed here',
      kind: 'mono',
      align: 'end',
      value: (sg) => this.routedCount(sg) || '—',
    },
    {
      label: 'Status',
      kind: 'dot',
      value: (sg) => (sg.isActive ? 'Active' : 'Inactive'),
      tone: (sg) => (sg.isActive ? 'success' : 'danger'),
    },
  ];

  get rows() {
    let all = (this.args.app.signatoryQuery?.instances ?? []).filter(
      Boolean,
    ) as any[];
    return this.args.app.search(all, (sg) => [
      sg.cardTitle,
      sg.signingTitle,
      sg.person?.cardTitle,
    ]);
  }

  nameOf = (sg: any): string => sg.person?.cardTitle || sg.cardTitle || '—';

  <template>
    <Block @title='Signatories' @count={{this.rows.length}}>
      {{#if this.rows.length}}
        <CeTable
          @label='Signatories'
          @columns={{this.columns}}
          @rows={{this.rows}}
          @onOpen={{@app.openCard}}
        >
          <:cell as |row|>
            <Button
              @tone='neutral'
              @appearance='plain'
              @size='xs'
              {{on 'click' (fn @app.openCard row)}}
            >
              <Avatar
                @name={{this.nameOf row}}
                @size={{20}}
                aria-hidden='true'
              />
              <strong>{{this.nameOf row}}</strong>
              {{#if row.person}}<span
                  class='sg-title'
                >{{row.signingTitle}}</span>{{/if}}
            </Button>
          </:cell>
        </CeTable>
      {{else}}
        <p class='tab-empty'>No signatories match.</p>
      {{/if}}
    </Block>
    <style scoped>
      .sg-title {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .tab-empty {
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
