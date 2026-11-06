import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { contractTypeLabel } from '../../legal/contract-type';
import {
  requestStateLabel,
  requestStateHue,
} from '../../legal/contract-request';
import { formatDay, hueTone } from '../contract-execution-data';
import { Block, CeTable, type Col } from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

export class RequestsTab extends GlimmerComponent<Signature> {
  columns: Col[] = [
    { label: 'Request', kind: 'title', value: (r) => r.cardTitle },
    {
      label: 'Type',
      value: (r) => (r.contractType ? contractTypeLabel(r.contractType) : '—'),
    },
    { label: 'Requested by', value: (r) => r.requestedBy?.cardTitle ?? '—' },
    {
      label: 'Needed by',
      kind: 'mono',
      align: 'end',
      value: (r) => formatDay(r.neededBy),
    },
    {
      label: 'Status',
      kind: 'dot',
      value: (r) => requestStateLabel(r.status),
      tone: (r) => hueTone(requestStateHue(r.status)),
    },
  ];

  get rows() {
    return this.args.app.search(this.args.app.requests as any[], (r) => [
      r.cardTitle,
      r.whatFor,
      r.requestedBy?.cardTitle,
    ]);
  }

  <template>
    <Block
      @title='Intake queue'
      @count={{this.rows.length}}
      @sub='Declined requests are kept, with the reason — so “what did we turn down, and why” stays answerable.'
    >
      {{#if this.rows.length}}
        <CeTable
          @label='Intake queue'
          @columns={{this.columns}}
          @rows={{this.rows}}
          @onOpen={{@app.openCard}}
        />
      {{else}}
        <p class='tab-empty'>No requests match.</p>
      {{/if}}
    </Block>
    <style scoped>
      .tab-empty {
        margin: 0;
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
