import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { concat, fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { Panel } from '@cardstack/pretui/components/panel';
import { PanelSection } from '@cardstack/pretui/components/panel-section';
import { Dot, StatStrip, type Stat } from '../shared/compact-parts';
import { Alert } from '@cardstack/pretui/components/alert';
import { Table } from '@cardstack/pretui/components/table';
import type { Tone } from '../shared/compact-format';

// The parts every tab shares, as thin adapters over Pret UI: a Panel (or a
// PanelSection when it sits inside another block), a status dot + text, a row
// of Stats, a ruled Table and a BarList. Only the layout glue is local.

const TONE_HUE: Record<Tone, string> = {
  danger: 'var(--destructive)',
  warning: 'var(--warning)',
  success: 'var(--success)',
  info: 'var(--info)',
  neutral: 'var(--foreground)',
};

export { Dot, StatStrip, type Stat };

export const Block: TemplateOnlyComponent<{
  Args: {
    title?: string;
    count?: number | string;
    sub?: string;
    /** no frame: a column inside another block */
    flat?: boolean;
  };
  Blocks: { default: []; action: [] };
  Element: HTMLElement;
}> = <template>
  {{#if @flat}}
    <PanelSection
      @title={{@title}}
      @summary={{if @count (concat @count)}}
      @collapsible={{false}}
      ...attributes
    >
      <:actions>{{yield to='action'}}</:actions>
      <:default>
        {{#if @sub}}<p class='ce-sub'>{{@sub}}</p>{{/if}}
        {{yield}}
      </:default>
    </PanelSection>
  {{else}}
    <Panel @variant='inspector' ...attributes>
      <:header>
        <h2 class='ce-title'>{{@title}}
          {{#if @count}}<span class='ce-count'>{{@count}}</span>{{/if}}</h2>
        {{#if @sub}}<p class='ce-sub'>{{@sub}}</p>{{/if}}
        {{#if (has-block 'action')}}<div class='ce-action'>{{yield
              to='action'
            }}</div>{{/if}}
      </:header>
      <:default>{{yield}}</:default>
    </Panel>
  {{/if}}
  <style scoped>
    .ce-title {
      font-size: var(--boxel-font-size-xs);
    }
    .ce-count {
      margin-inline-start: var(--boxel-sp-3xs);
      font-family: var(--font-mono);
      font-weight: 400;
      color: var(--muted-foreground);
    }
    .ce-sub {
      padding: var(--boxel-sp-4xs) var(--boxel-sp-xs);
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    .ce-action {
      display: flex;
      gap: var(--boxel-sp-xs);
    }
  </style>
</template>;

export const SubHead: TemplateOnlyComponent<{
  Args: { label: string; count?: number | string; sub?: string };
}> = <template>
  <PanelSection
    @title={{@label}}
    @summary={{if @count (concat @count)}}
    @collapsible={{false}}
  >
    {{#if @sub}}<p class='ce-sub'>{{@sub}}</p>{{/if}}
  </PanelSection>
  <style scoped>
    .ce-sub {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
  </style>
</template>;

export interface Col {
  label: string;
  /** title = bold name that opens the row; mono = ids, dates, money */
  kind?: 'title' | 'mono' | 'dot' | 'muted' | 'text' | 'custom';
  align?: 'end';
  value?: (row: any) => unknown;
  tone?: (row: any) => Tone;
}

// Pret UI Table, unframed (the Block is the frame), no zebra.
export const CeTable: TemplateOnlyComponent<{
  Args: {
    columns: Col[];
    rows: any[];
    label: string;
    onOpen?: (row: any) => void;
    isSelected?: (row: any) => boolean;
  };
  Blocks: { cell: [row: any, col: Col] };
}> = <template>
  <Table
    class='ce-table'
    @framed={{false}}
    @striped={{false}}
    @label={{@label}}
  >
    <:head>
      <tr>
        {{#each @columns as |col|}}
          <th scope='col' data-align={{col.align}}>{{col.label}}</th>
        {{/each}}
      </tr>
    </:head>
    <:body>
      {{#each @rows as |row|}}
        {{#let (if @isSelected (@isSelected row)) as |selected|}}
          <tr data-selected={{if selected 'true'}}>
            {{#each @columns as |col|}}
              <td data-align={{col.align}} data-kind={{col.kind}}>
                {{#if (eq col.kind 'custom')}}
                  {{yield row col to='cell'}}
                {{else if (eq col.kind 'dot')}}
                  <Dot
                    @tone={{if col.tone (col.tone row)}}
                    @label={{if col.value (col.value row)}}
                  />
                {{else if (eq col.kind 'title')}}
                  {{#if @onOpen}}
                    <Button
                      @tone='neutral'
                      @appearance='plain'
                      @size='xs'
                      aria-current={{if selected 'true'}}
                      {{on 'click' (fn @onOpen row)}}
                    >{{if col.value (col.value row)}}</Button>
                  {{else}}
                    {{if col.value (col.value row)}}
                  {{/if}}
                {{else}}
                  {{if col.value (col.value row)}}
                {{/if}}
              </td>
            {{/each}}
          </tr>
        {{/let}}
      {{/each}}
    </:body>
  </Table>
  <style scoped>
    .ce-table {
      --pretui-table-head-height: 1.5rem;
    }
    .ce-table td {
      white-space: nowrap;
    }
    [data-align='end'] {
      text-align: end;
    }
    td[data-kind='title'] {
      max-inline-size: 16rem;
      overflow: hidden;
      text-overflow: ellipsis;
      font-weight: 700;
    }
    td[data-kind='mono'] {
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size-2xs);
      font-variant-numeric: tabular-nums;
      color: var(--muted-foreground);
    }
    td[data-kind='muted'] {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    td:first-child {
      border-inline-start: 2px solid transparent;
    }
    tr[data-selected='true'] td {
      background: var(--selected);
      font-weight: 700;
    }
    tr[data-selected='true'] td:first-child {
      border-inline-start-color: var(--primary-ink);
    }
  </style>
</template>;

/** A tone's bar colour, for a Pret UI BarList row's `hue`. */
export function toneHue(tone?: Tone, hot?: boolean): string {
  return hot ? TONE_HUE.danger : TONE_HUE[tone ?? 'neutral'];
}

/** A footnote or callout line: tone, bold lead, muted text. */
export const Note: TemplateOnlyComponent<{
  Args: { tone?: Tone; lead: string; text?: string };
  Element: HTMLElement;
}> = <template>
  <Alert
    @tone={{if @tone @tone 'info'}}
    @title={{@lead}}
    ...attributes
  >{{@text}}</Alert>
</template>;
