import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { contractTypeLabel } from '../../legal/contract-type';
import { Block, CeTable, type Col } from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

export class TemplatesTab extends GlimmerComponent<Signature> {
  columns: Col[] = [
    { label: 'Template', kind: 'title', value: (t) => t.cardTitle },
    {
      label: 'Type',
      value: (t) => (t.contractType ? contractTypeLabel(t.contractType) : '—'),
    },
    { label: 'Use case', value: (t) => t.useCase ?? '—' },
    {
      label: 'Clauses',
      kind: 'mono',
      align: 'end',
      value: (t) => (t.standardClauses ?? []).filter(Boolean).length,
    },
    {
      label: 'Status',
      kind: 'dot',
      value: (t) => (t.isPublished ? 'Published' : 'Draft'),
      tone: (t) => (t.isPublished ? 'success' : 'neutral'),
    },
  ];

  get rows() {
    return this.args.app.search(this.args.app.templates as any[], (t) => [
      t.cardTitle,
      t.useCase,
      t.contractType,
    ]);
  }

  <template>
    <Block
      @title='Template library'
      @count={{this.rows.length}}
      @sub='A starting position for each contract type — the clauses it assumes, and what you still have to supply.'
    >
      {{#if this.rows.length}}
        <CeTable
          @label='Template library'
          @columns={{this.columns}}
          @rows={{this.rows}}
          @onOpen={{@app.openCard}}
        />
      {{else}}
        <p class='tab-empty'>No templates match.</p>
      {{/if}}
    </Block>
    <style scoped>
      .tab-empty {
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
