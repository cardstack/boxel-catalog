import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { CardDef } from '@cardstack/base/card-api';
import { Table } from '@cardstack/pretui/components/table';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
import { VisuallyHidden } from '@cardstack/pretui/components/visually-hidden';

export interface RecordColumn {
  label: string;
  // atom: a linked card shown as its bare atom; title: the row's own card atom
  // (the open button); status: dot + text; mono: ids, money, versions
  kind: 'title' | 'atom' | 'text' | 'mono' | 'status';
  value: (card: CardDef) => any;
  meta?: (card: CardDef) => string | undefined;
  align?: 'end';
}

interface Signature {
  Args: {
    rows: readonly CardDef[];
    columns: RecordColumn[];
    label: string;
    onOpen: (card: CardDef) => void;
    emptyMessage?: string;
  };
  Blocks: { actions: [CardDef] };
}

// One compact row per record: mono caps header, 28px rows, one hairline.
export class RecordTable extends Component<Signature> {
  cell = (card: CardDef, col: RecordColumn) => col.value(card);
  meta = (card: CardDef, col: RecordColumn) => col.meta?.(card);
  atom = (card: CardDef | undefined) =>
    card ? (card.constructor as typeof CardDef).getComponent(card) : undefined;
  tone = (status: string | undefined) => {
    let s = (status ?? '').toLowerCase();
    if (
      ['won', 'paid', 'active', 'converted', 'qualified', 'accepted'].includes(
        s,
      )
    )
      return 'success';
    if (
      [
        'lost',
        'overdue',
        'disqualified',
        'canceled',
        'rejected',
        'expired',
      ].includes(s)
    )
      return s === 'expired' ? 'neutral' : 'danger';
    if (['sent', 'viewed', 'contacted', 'trial'].includes(s)) return 'info';
    if (['under-review', 'partial', 'past_due'].includes(s)) return 'warning';
    return 'neutral';
  };

  <template>
    <div class='rt'>
      <Table @label={{@label}} @framed={{false}}>
        <:head>
          <tr>
            {{#each @columns as |c|}}
              <th
                scope='col'
                class={{if (eq c.align 'end') 'end'}}
              >{{c.label}}</th>
            {{/each}}
            {{#if (has-block 'actions')}}
              <th scope='col'><VisuallyHidden>Actions</VisuallyHidden></th>
            {{/if}}
          </tr>
        </:head>
        <:body>
          {{#each @rows key='id' as |card|}}
            <tr>
              {{#each @columns as |c|}}
                <td class={{if (eq c.align 'end') 'end'}} data-kind={{c.kind}}>
                  {{#if (eq c.kind 'title')}}
                    <button
                      type='button'
                      class='open'
                      {{on 'click' (fn @onOpen card)}}
                    >
                      {{#let (this.atom card) as |A|}}<A
                          @format='atom'
                          @displayContainer={{false}}
                        />{{/let}}
                    </button>
                  {{else if (eq c.kind 'atom')}}
                    {{#let (this.cell card c) as |linked|}}
                      {{#if linked}}{{#let (this.atom linked) as |A|}}<A
                            @format='atom'
                            @displayContainer={{false}}
                          />{{/let}}{{else}}<span class='muted'>—</span>{{/if}}
                    {{/let}}
                  {{else if (eq c.kind 'status')}}
                    {{#let (this.cell card c) as |s|}}
                      {{#if s}}<StatusChip
                          @value={{s}}
                          @tone={{this.tone s}}
                          @appearance='plain'
                        />{{/if}}
                    {{/let}}
                  {{else}}
                    <span class={{c.kind}}>{{this.cell card c}}</span>
                  {{/if}}
                  {{#let (this.meta card c) as |m|}}{{#if m}}<span
                        class='meta'
                      >{{m}}</span>{{/if}}{{/let}}
                </td>
              {{/each}}
              {{#if (has-block 'actions')}}
                <td class='end'><span class='acts'>{{yield
                      card
                      to='actions'
                    }}</span></td>
              {{/if}}
            </tr>
          {{else}}
            <tr><td colspan='9' class='muted'>{{@emptyMessage}}</td></tr>
          {{/each}}
        </:body>
      </Table>
    </div>
    <style scoped>
      .rt {
        font-size: 0.75rem;
        --pretui-table-head-height: 1.5rem;
        --boxel-sp-2xs: 0.25rem;
        --boxel-sp-xs: 0.625rem;
      }
      th {
        font-family: var(--font-mono);
        font-size: 0.5625rem;
        font-weight: 600;
        letter-spacing: 0.13em;
        text-transform: uppercase;
        color: var(--muted-foreground);
        text-align: start;
      }
      th,
      td {
        padding-block: 0;
        line-height: 1.2;
      }
      td {
        block-size: 1.75rem;
        vertical-align: middle;
        white-space: nowrap;
      }
      .end {
        text-align: end;
      }
      td[data-kind='title'] {
        font-weight: 600;
      }
      .open {
        all: unset;
        cursor: pointer;
        display: inline-flex;
        max-inline-size: 100%;
      }
      .open:focus-visible {
        outline: 2px solid var(--ring);
      }
      .mono {
        font-family: var(--font-mono);
        font-size: 0.6875rem;
        font-variant-numeric: tabular-nums;
      }
      .meta,
      .muted {
        color: var(--muted-foreground);
        font-size: 0.6875rem;
      }
      .meta {
        margin-inline-start: var(--boxel-sp-xs);
      }
      .acts {
        display: inline-flex;
        gap: var(--boxel-sp-xs);
      }
    </style>
  </template>
}
