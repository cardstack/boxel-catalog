import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { contractTypeLabel } from '../../legal/contract-type';
import { formatMoney } from '../../commerce/line-item-totals';
import { initials, openStep } from '../contract-execution-data';
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
      tone: (sg) => (sg.isActive ? 'ok' : 'bad'),
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
            <button
              type='button'
              class='sg-who'
              {{on 'click' (fn @app.openCard row)}}
            >
              <span class='sg-mark' aria-hidden='true'>{{initials
                  (this.nameOf row)
                }}</span>
              <strong>{{this.nameOf row}}</strong>
              {{#if row.person}}<span
                  class='sg-title'
                >{{row.signingTitle}}</span>{{/if}}
            </button>
          </:cell>
        </CeTable>
      {{else}}
        <p class='tab-empty'>No signatories match.</p>
      {{/if}}
    </Block>
    <style scoped>
      .sg-who {
        display: inline-flex;
        align-items: center;
        gap: var(--boxel-sp-2xs);
        max-inline-size: 22rem;
        padding: 0;
        border: 0;
        background: none;
        color: inherit;
        font: inherit;
        cursor: pointer;
      }
      .sg-who:focus-visible {
        outline: 2px solid var(--ring);
      }
      .sg-mark {
        display: grid;
        place-items: center;
        flex: none;
        inline-size: 1.25rem;
        block-size: 1.25rem;
        border-radius: 50%;
        background: var(--muted);
        font: 700 calc(var(--boxel-font-size-xs) * 0.6) / 1 var(--font-mono);
      }
      .sg-title {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: var(--boxel-font-size-2xs);
        color: var(--muted-foreground);
      }
      .tab-empty {
        margin: 0;
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
