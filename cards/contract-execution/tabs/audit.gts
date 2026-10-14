import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { on } from '@ember/modifier';
import { Button } from '@cardstack/pretui/components/button';
import { eq } from '@cardstack/boxel-ui/helpers';
import {
  AuditEntry,
  auditActionHue,
  auditActionLabel,
} from '../../audit/audit-entry';
import { CollectionPanel } from '../../../components/collection-panel';
import { StatePill } from '../../../components/state-pill';
import { AUDIT_COLUMNS, asAny } from '../contract-execution-data';
interface Signature {
  Args: { app: ContractExecutionView };
}

export class AuditTab extends GlimmerComponent<Signature> {
  /**
   * Audit export — a real CSV, generated in the browser.
   *
   * No server round-trip and no library: the whole point of an audit export is
   * that the auditor can open it in a spreadsheet, and a Blob + object URL does
   * that with nothing to install. Quoting is explicit because a contract title
   * containing a comma would otherwise shift every column after it — silently,
   * and only in the file the auditor is reading.
   */
  exportAudit = () => {
    let esc = (v: unknown) => {
      let t = v === null || v === undefined ? '' : String(v);
      return /[",\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
    };
    let header = ['When', 'Done by', 'Action', 'Subject', 'Conditions', 'Note'];
    let rows = this.args.app.audits
      .slice()
      .sort(
        (a: any, b: any) =>
          new Date(b?.occurredAt ?? 0).getTime() -
          new Date(a?.occurredAt ?? 0).getTime(),
      )
      .map((a: any) => [
        a?.occurredAt ?? '',
        a?.doneBy?.cardTitle ?? '',
        auditActionLabel(a?.action),
        a?.subjectTitle ?? '',
        a?.conditions ?? '',
        a?.note ?? '',
      ]);
    let csv = [header, ...rows].map((r) => r.map(esc).join(',')).join('\n');
    let blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    let url = URL.createObjectURL(blob);
    let a = document.createElement('a');
    a.href = url;
    a.download = 'contract-audit-trail.csv';
    a.click();
    URL.revokeObjectURL(url);
  };

  <template>
    <div class='cx-bulkhead'>
      <p class='cx-note'>Every recorded decision, newest first. Entries are
        written by the decision that caused them.</p>
      <Button @appearance='outlined' {{on 'click' this.exportAudit}}>Export CSV</Button>
    </div>
    {{! No add action, deliberately. An audit trail whose entries can
        be typed in by hand is not evidence of anything — entries are
        written by the decision that caused them. Search and sort are
        exactly what an auditor needs; a "New entry" button is the one
        control that would undermine the tab. }}
    <CollectionPanel
      @cardClass={{AuditEntry}}
      @app.context={{@app.context}}
      @realms={{@app.realmList}}
      @columns={{AUDIT_COLUMNS}}
      @label='Audit trail'
      @searchPlaceholder='Search by person, action or contract…'
      @defaultView='table'
      @sortBy='occurredAt'
      @allowCreate={{false}}
    >
      <:cell as |cellRow column|>{{#let (asAny cellRow) as |row|}}
          {{#if (eq column.key 'action')}}
            <StatePill
              @label={{auditActionLabel row.action}}
              @hue={{auditActionHue row.action}}
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

      .cx-bulkhead {
        display: flex;
        align-items: center;
        gap: var(--boxel-sp);
        flex-wrap: wrap;
        min-height: 2.5rem;
      }
    </style>
  </template>
}
