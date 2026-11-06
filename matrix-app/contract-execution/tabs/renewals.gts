import GlimmerComponent from '@glimmer/component';
import type { ContractExecutionView } from '../contract-execution-app';
import { formatDay, noticeTone } from '../contract-execution-data';
import { Block, CeTable, Note, type Col } from '../components';

interface Signature {
  Args: { app: ContractExecutionView };
}

/** Shared with Compliance: one notice table, one set of columns. */
export const NOTICE_COLUMNS: Col[] = [
  { label: 'Contract', kind: 'title', value: (c) => c.cardTitle },
  { label: 'Counterparty', value: (c) => c.account?.cardTitle ?? '—' },
  {
    label: 'Notice by',
    kind: 'mono',
    align: 'end',
    value: (c) => formatDay(c.noticeBy),
  },
  {
    label: 'Days left',
    kind: 'dot',
    align: 'end',
    value: (c) => `${c.daysToNotice}d`,
    tone: (c) => noticeTone(c.daysToNotice),
  },
  {
    label: 'Auto-renews',
    kind: 'mono',
    align: 'end',
    value: (c) => formatDay(c.endDate),
  },
];

export class RenewalsTab extends GlimmerComponent<Signature> {
  columns = NOTICE_COLUMNS;

  <template>
    <Block
      @title='Notice windows, soonest first'
      @count={{@app.renewalRows.length}}
      @sub='A renewal is decided by the notice date, not the end date — miss the notice window and the contract renews whether or not anyone wanted it to.'
    >
      {{#if @app.renewalRows.length}}
        <CeTable
          @label='Notice windows'
          @columns={{this.columns}}
          @rows={{@app.renewalRows}}
          @onOpen={{@app.openInWorkspace}}
        />
      {{else}}
        <p class='tab-empty'>No notice window closes in the next 90 days.</p>
      {{/if}}
    </Block>
    <Note
      class='tab-callout'
      @tone='info'
      @lead='Not yet firing'
      @text='Reminder dates can be set on an obligation, but nothing sends them yet — check this tab rather than waiting to be told.'
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
