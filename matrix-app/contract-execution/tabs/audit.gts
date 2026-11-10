import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import {
  auditActionLabel,
  auditActionHue,
} from '../../audit/utils/audit-action-vocabulary';
import { formatDay, hueTone } from '../../shared/compact-format';
import { Block, CeTable, type Col } from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

export class AuditTab extends GlimmerComponent<Signature> {
  columns: Col[] = [
    { label: 'When', kind: 'mono', value: (a) => formatDay(a.occurredAt) },
    { label: 'Who', value: (a) => a.doneBy?.cardTitle ?? '—' },
    {
      label: 'Action',
      kind: 'dot',
      value: (a) => auditActionLabel(a.action),
      tone: (a) => hueTone(auditActionHue(a.action)),
    },
    { label: 'Subject', kind: 'title', value: (a) => a.subjectTitle ?? '—' },
    { label: 'Conditions', value: (a) => a.conditions || '—' },
  ];

  get rows() {
    let sorted = [...(this.args.app.audits as any[])].sort(
      (a, b) =>
        new Date(b.occurredAt ?? 0).getTime() -
        new Date(a.occurredAt ?? 0).getTime(),
    );
    return this.args.app.search(sorted, (a) => [
      a.doneBy?.cardTitle,
      auditActionLabel(a.action),
      a.subjectTitle,
    ]);
  }

  <template>
    <Block
      @title='Audit trail'
      @count={{this.rows.length}}
      @sub='Every recorded decision, newest first. Entries are written by the decision that caused them.'
    >
      {{#if this.rows.length}}
        <CeTable
          @label='Audit trail'
          @columns={{this.columns}}
          @rows={{this.rows}}
          @onOpen={{@app.openCard}}
        />
      {{else}}
        <p class='tab-empty'>No audit entries match.</p>
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
