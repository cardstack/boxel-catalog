import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { concat, fn } from '@ember/helper';
import { eq } from '@cardstack/pretui/helpers';
import { Button } from '@cardstack/pretui/components/button';
import { Panel } from '@cardstack/pretui/components/panel';
import { PanelSection } from '@cardstack/pretui/components/panel-section';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import { Stat as PretStat } from '@cardstack/pretui/components/stat';
import { StatusChip } from '@cardstack/pretui/components/status-chip';
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

export const Dot: TemplateOnlyComponent<{
  Args: { tone?: Tone; label?: string | number };
  Element: HTMLSpanElement;
}> = <template>
  <StatusChip
    @value={{@label}}
    @tone={{if @tone @tone 'neutral'}}
    @appearance='plain'
    ...attributes
  />
</template>;

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
      @summary={{if @count (if @count @count)}}
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
      margin: 0;
      font-size: var(--boxel-font-size-xs);
    }
    .ce-count {
      margin-inline-start: var(--boxel-sp-3xs);
      font-family: var(--font-mono);
      font-weight: 400;
      color: var(--muted-foreground);
    }
    .ce-sub {
      margin: 0;
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
    @summary={{if @count (if @count @count)}}
    @collapsible={{false}}
  >
    {{#if @sub}}<p class='ce-sub'>{{@sub}}</p>{{/if}}
  </PanelSection>
  <style scoped>
    .ce-sub {
      margin: 0;
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
  </style>
</template>;

export interface Stat {
  label: string;
  value: string | number;
  unit?: string;
  sub?: string;
  tone?: Tone;
  meter?: number;
}

// Pret UI has no stat group by design: a grid of Stats, one tile each.
export const StatStrip: TemplateOnlyComponent<{
  Args: { stats: Stat[]; label: string; flat?: boolean };
  Element: HTMLUListElement;
}> = <template>
  <ul
    class='ce-stats'
    data-flat={{if @flat 'true'}}
    aria-label={{@label}}
    ...attributes
  >
    {{#each @stats as |s|}}
      <li class='ce-stat'>
        <PretStat
          @label={{s.label}}
          @value={{if s.unit (concat s.value s.unit) s.value}}
          @tone={{if s.tone s.tone 'neutral'}}
          @hint={{s.sub}}
          @roll={{false}}
        />
        {{#if s.meter}}<ProgressBar
            @value={{s.meter}}
            @hue='var(--foreground)'
            aria-label={{s.label}}
          />{{/if}}
      </li>
    {{/each}}
  </ul>
  <style scoped>
    .ce-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(9.5rem, 1fr));
      gap: 1px;
      margin: 0;
      padding: 0;
      list-style: none;
      background: var(--border);
      border: 1px solid var(--border);
      border-radius: var(--boxel-border-radius);
      overflow: hidden;
    }
    .ce-stats[data-flat='true'] {
      border: 0;
      border-radius: 0;
    }
    .ce-stat {
      min-inline-size: 0;
      padding: var(--boxel-sp-xs);
      background: var(--card);
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
  <Table class='ce-table' @framed={{false}} @label={{@label}}>
    <:head>
      <tr>
        {{#each @columns as |col|}}
          <th scope='col' data-align={{col.align}}>{{col.label}}</th>
        {{/each}}
      </tr>
    </:head>
    <:body>
      {{#each @rows as |row|}}
        <tr data-selected={{if @isSelected (if (@isSelected row) 'true')}}>
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
                    @variant='ghost'
                    @size='xs'
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
      {{/each}}
    </:body>
  </Table>
  <style scoped>
    .ce-table {
      --stripe: var(--card);
      --pretui-table-head-height: 1.5rem;
    }
    .ce-table :deep(td) {
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
    tr[data-selected='true'] td {
      background: var(--muted);
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
