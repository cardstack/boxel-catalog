import type { TemplateOnlyComponent } from '@ember/component/template-only';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import { Table } from '@cardstack/pretui/components/table';
import { ProgressBar } from '@cardstack/pretui/components/progress-bar';
import type { Tone } from './contract-execution-data';

// The parts every tab shares: a white block on the canvas, a mono caps
// sub-heading, a dot + text status, a joined stat strip, a ruled table and a
// bar row. Flat inside: only the block has a radius; rows are hairlines.

export const Dot: TemplateOnlyComponent<{
  Args: { tone?: Tone; label?: string | number };
  Element: HTMLSpanElement;
}> = <template>
  <span class='ce-dot' data-tone={{if @tone @tone 'neutral'}} ...attributes>
    <span class='ce-dot-mark' aria-hidden='true'></span>{{@label}}
  </span>
  <style scoped>
    .ce-dot {
      display: inline-flex;
      align-items: center;
      gap: var(--boxel-sp-3xs);
      font-weight: 600;
      white-space: nowrap;
      --ce-tone: var(--muted-foreground);
    }
    .ce-dot[data-tone='bad'] {
      --ce-tone: var(--destructive);
    }
    .ce-dot[data-tone='warn'] {
      --ce-tone: var(--warning);
    }
    .ce-dot[data-tone='ok'] {
      --ce-tone: var(--success);
    }
    .ce-dot[data-tone='info'] {
      --ce-tone: var(--info);
    }
    .ce-dot-mark {
      inline-size: 0.4375rem;
      block-size: 0.4375rem;
      border-radius: 50%;
      flex: none;
      background: var(--ce-tone);
    }
  </style>
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
  <section class='ce-block' data-flat={{if @flat 'true'}} ...attributes>
    {{#if @title}}
      <header class='ce-block-head'>
        <div class='ce-block-id'>
          <h2 class='ce-block-title'>{{@title}}
            {{#if @count}}<span class='ce-count'>{{@count}}</span>{{/if}}</h2>
          {{#if @sub}}<p class='ce-block-sub'>{{@sub}}</p>{{/if}}
        </div>
        {{#if (has-block 'action')}}
          <div class='ce-block-action'>{{yield to='action'}}</div>
        {{/if}}
      </header>
    {{/if}}
    {{yield}}
  </section>
  <style scoped>
    .ce-block {
      min-inline-size: 0;
      background: var(--card);
      color: var(--card-foreground);
      border: 1px solid var(--border);
      border-radius: var(--boxel-border-radius);
      overflow: hidden;
    }
    .ce-block[data-flat='true'] {
      border: 0;
      border-radius: 0;
    }
    .ce-block-head {
      display: flex;
      align-items: flex-start;
      gap: var(--boxel-sp-xs);
      padding: var(--boxel-sp-xs) var(--boxel-sp-xs);
      border-bottom: 1px solid var(--border);
    }
    .ce-block-id {
      flex: 1;
      min-inline-size: 0;
    }
    .ce-block-title {
      margin: 0;
      font-size: var(--boxel-font-size-xs);
      font-weight: 700;
    }
    .ce-count {
      margin-inline-start: var(--boxel-sp-3xs);
      font-family: var(--font-mono);
      font-weight: 400;
      color: var(--muted-foreground);
    }
    .ce-block-sub {
      margin: var(--boxel-sp-4xs) 0 0;
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
    .ce-block-action {
      flex: none;
      display: flex;
      gap: var(--boxel-sp-xs);
      font-size: var(--boxel-font-size-2xs);
      font-weight: 600;
    }
  </style>
</template>;

export const SubHead: TemplateOnlyComponent<{
  Args: { label: string; count?: number | string; sub?: string };
}> = <template>
  <div class='ce-subhead'>
    <h3 class='ce-cap'>{{@label}}
      {{#if @count}}<span class='ce-cap-n'>{{@count}}</span>{{/if}}</h3>
    {{#if @sub}}<p class='ce-subhead-sub'>{{@sub}}</p>{{/if}}
  </div>
  <style scoped>
    .ce-subhead {
      padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      border-bottom: 1px solid var(--border);
    }
    .ce-cap {
      margin: 0;
      font: 600 calc(var(--boxel-font-size-xs) * 0.75) / 1.3 var(--font-mono);
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .ce-cap-n {
      margin-inline-start: var(--boxel-sp-4xs);
      color: var(--foreground);
    }
    .ce-subhead-sub {
      margin: var(--boxel-sp-4xs) 0 0;
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

export const StatStrip: TemplateOnlyComponent<{
  Args: { stats: Stat[]; label: string; flat?: boolean };
  Element: HTMLDListElement;
}> = <template>
  <dl
    class='ce-stats'
    data-flat={{if @flat 'true'}}
    aria-label={{@label}}
    ...attributes
  >
    {{#each @stats as |s|}}
      <div class='ce-stat'>
        <dt><Dot
            @tone={{s.tone}}
            @label={{s.label}}
            class='ce-stat-label'
          /></dt>
        <dd class='ce-stat-value'>{{s.value}}{{#if s.unit}}<span
              class='ce-stat-unit'
            >{{s.unit}}</span>{{/if}}</dd>
        {{#if s.sub}}<dd class='ce-stat-sub'>{{s.sub}}</dd>{{/if}}
        {{#if s.meter}}<dd><ProgressBar
              @value={{s.meter}}
              @hue='var(--foreground)'
              aria-label={{s.label}}
            /></dd>{{/if}}
      </div>
    {{/each}}
  </dl>
  <style scoped>
    /* joined tiles; each draws its right and bottom rule and the strip clips
       the outer ones, so no rule goes missing when it wraps */
    .ce-stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(9.5rem, 1fr));
      margin: 0;
      background: var(--card);
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
      margin: 0 -1px -1px 0;
      padding: var(--boxel-sp-xs);
      border-right: 1px solid var(--border);
      border-bottom: 1px solid var(--border);
    }
    .ce-stat dd {
      margin: 0;
    }
    .ce-stat-label {
      font: 600 calc(var(--boxel-font-size-xs) * 0.75) / 1.3 var(--font-mono);
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
    }
    .ce-stat-value {
      margin-top: var(--boxel-sp-4xs);
      font-size: var(--boxel-font-size-lg);
      font-weight: 700;
      line-height: 1.15;
      font-variant-numeric: tabular-nums;
    }
    .ce-stat-unit {
      font-size: var(--boxel-font-size-2xs);
      font-weight: 600;
      color: var(--muted-foreground);
    }
    .ce-stat-sub {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
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
                  <button
                    type='button'
                    class='ce-open'
                    {{on 'click' (fn @onOpen row)}}
                  >{{if col.value (col.value row)}}</button>
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
      font-size: var(--boxel-font-size-xs);
    }
    th,
    td {
      block-size: 1.75rem;
      padding: 0 var(--boxel-sp-xs);
      vertical-align: middle;
      white-space: nowrap;
      text-align: start;
      border-bottom: 1px solid var(--border);
    }
    th {
      font: 600 calc(var(--boxel-font-size-xs) * 0.75) / 1 var(--font-mono);
      letter-spacing: 0.13em;
      text-transform: uppercase;
      color: var(--muted-foreground);
      background: var(--card);
    }
    tr:last-child td {
      border-bottom: 0;
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
    .ce-open {
      max-inline-size: 100%;
      padding: 0;
      border: 0;
      background: none;
      color: inherit;
      font: inherit;
      overflow: hidden;
      text-overflow: ellipsis;
      cursor: pointer;
    }
    .ce-open:hover {
      text-decoration: underline;
    }
    .ce-open:focus-visible {
      outline: 2px solid var(--ring);
      outline-offset: 1px;
    }
  </style>
</template>;

export interface BarRow {
  label: string;
  pct: number;
  value: string | number;
  tone?: Tone;
  hot?: boolean;
}

// One ruled row per band: dot + label, bar, mono value.
export const BarList: TemplateOnlyComponent<{
  Args: { rows: BarRow[]; dots?: boolean; label: string };
}> = <template>
  <ul class='ce-bars' aria-label={{@label}}>
    {{#each @rows as |r|}}
      <li class='ce-bar'>
        {{#if @dots}}<Dot @tone={{r.tone}} @label={{r.label}} />{{else}}<span
            class='ce-bar-label'
          >{{r.label}}</span>{{/if}}
        <ProgressBar
          @value={{r.pct}}
          @hue={{if r.hot 'var(--destructive)' 'var(--foreground)'}}
          aria-label={{r.label}}
        />
        <span class='ce-bar-value'>{{r.value}}</span>
      </li>
    {{/each}}
  </ul>
  <style scoped>
    .ce-bars {
      margin: 0;
      padding: 0;
      list-style: none;
    }
    .ce-bar {
      display: grid;
      grid-template-columns: minmax(0, 9rem) minmax(0, 1fr) 4.5rem;
      align-items: center;
      gap: var(--boxel-sp-xs);
      block-size: 1.75rem;
      padding: 0 var(--boxel-sp-xs);
      border-bottom: 1px solid var(--border);
      font-size: var(--boxel-font-size-xs);
    }
    .ce-bar-label {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .ce-bar-value {
      text-align: end;
      font-family: var(--font-mono);
      font-size: var(--boxel-font-size-2xs);
      font-variant-numeric: tabular-nums;
    }
  </style>
</template>;

/** A footnote or callout line: dot, bold lead, muted text. */
export const Note: TemplateOnlyComponent<{
  Args: { tone?: Tone; lead: string; text?: string };
  Element: HTMLElement;
}> = <template>
  <p class='ce-note' ...attributes><Dot @tone={{@tone}} @label={{@lead}} />
    <span class='ce-note-text'>{{@text}}</span></p>
  <style scoped>
    .ce-note {
      display: flex;
      flex-wrap: wrap;
      align-items: baseline;
      gap: var(--boxel-sp-2xs);
      margin: 0;
      padding: var(--boxel-sp-2xs) var(--boxel-sp-xs);
      font-size: var(--boxel-font-size-xs);
    }
    .ce-note-text {
      font-size: var(--boxel-font-size-2xs);
      color: var(--muted-foreground);
    }
  </style>
</template>;
