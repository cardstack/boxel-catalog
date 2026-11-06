import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { humanise } from '../../shared/compact-format';
import { Block, CeTable, Note, type Col } from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

export class ClausesTab extends GlimmerComponent<Signature> {
  clauseUsage = (clauseId?: string) => {
    if (!clauseId) return { used: 0, deviations: 0 };
    let rows = this.args.app.clauseUses.filter(
      (u: any) => u?.standardClause?.id === clauseId,
    );
    return {
      used: rows.length,
      deviations: rows.filter((u: any) => u?.isDeviation).length,
    };
  };

  columns: Col[] = [
    { label: 'Clause', kind: 'title', value: (c) => c.cardTitle },
    { label: 'Category', value: (c) => humanise(c.clauseType) },
    {
      label: 'Risk',
      kind: 'dot',
      value: (c) => humanise(c.riskLevel),
      tone: (c) => this.args.app.riskToneOf(c.riskLevel),
    },
    {
      label: 'Used in',
      kind: 'mono',
      align: 'end',
      value: (c) => this.clauseUsage(c.id).used || 'unused',
    },
    {
      label: 'Deviations',
      kind: 'dot',
      align: 'end',
      value: (c) => {
        let u = this.clauseUsage(c.id);
        return u.used ? u.deviations || 'none' : '—';
      },
      tone: (c) => (this.clauseUsage(c.id).deviations ? 'danger' : 'neutral'),
    },
    { label: 'Owned by', value: (c) => c.ownerRole ?? '—' },
  ];

  get rows() {
    let all = (this.args.app.clauseQuery?.instances ?? []).filter(
      Boolean,
    ) as any[];
    return this.args.app.search(
      [...all].sort((a, b) =>
        String(a.cardTitle ?? '').localeCompare(String(b.cardTitle ?? '')),
      ),
      (c) => [c.cardTitle, c.clauseType, c.ownerRole],
    );
  }

  <template>
    <Block @title='Clause library' @count={{this.rows.length}}>
      {{#if this.rows.length}}
        <CeTable
          @label='Clause library'
          @columns={{this.columns}}
          @rows={{this.rows}}
          @onOpen={{@app.openCard}}
        />
      {{else}}
        <p class='tab-empty'>No clauses match.</p>
      {{/if}}
    </Block>
    <Note
      class='tab-callout'
      @tone='info'
      @lead='Not yet available'
      @text='Clauses are added by hand for now. Reading a contract’s text and proposing its clauses automatically is not switched on in this workspace.'
    />
    <style scoped>
      .tab-callout {
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: var(--boxel-border-radius);
      }
      .tab-empty {
        margin: 0;
        padding: var(--boxel-sp-xs);
        color: var(--muted-foreground);
      }
    </style>
  </template>
}
