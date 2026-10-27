// Pretui — DataGrid: a data-driven table with sortable columns.
import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';

export interface ColumnSpec {
  key: string;
  label: string;
  num?: boolean;
  mono?: boolean;
  align?: 'left' | 'right';
  sortable?: boolean;
}
export type Row = Record<string, any>;
export interface SortSpec {
  key: string;
  dir: 'asc' | 'desc';
}

export interface DataGridSignature {
  Args: {
    columns: ColumnSpec[];
    rows: Row[];
    rowKey?: string;
    selectable?: boolean;
    defaultSort?: SortSpec;
    onSortChange?: (s: SortSpec | null) => void;
    onSelectedChange?: (keys: unknown[]) => void;
  };
  Blocks: { cell: [row: Row, column: ColumnSpec] };
  Element: HTMLDivElement;
}

// THE records table: mono eyebrow headers, zebra stripe, hover, selection.
export class DataGrid extends Component<DataGridSignature> {
  @tracked sort: SortSpec | null = this.args.defaultSort ?? null;
  @tracked selected: unknown[] = [];

  get rowKey() {
    return this.args.rowKey ?? 'id';
  }
  get selectedInRows(): unknown[] {
    let keys = new Set(this.args.rows.map((row) => row[this.rowKey]));
    return this.selected.filter((key) => keys.has(key));
  }
  get sorted(): Row[] {
    let s = this.sort;
    if (!s) {
      return this.args.rows;
    }
    let dir = s.dir === 'desc' ? -1 : 1;
    return [...this.args.rows].sort((a, b) => {
      let av = a[s.key];
      let bv = b[s.key];
      return (av > bv ? 1 : av < bv ? -1 : 0) * dir;
    });
  }
  get allOn() {
    return (
      this.args.rows.length > 0 &&
      this.selectedInRows.length === this.args.rows.length
    );
  }
  clickSort = (c: ColumnSpec) => {
    if (c.sortable === false) {
      return;
    }
    let s = this.sort;
    this.sort =
      !s || s.key !== c.key
        ? { key: c.key, dir: 'asc' }
        : s.dir === 'asc'
          ? { key: c.key, dir: 'desc' }
          : null;
    this.args.onSortChange?.(this.sort);
  };
  toggle = (key: unknown) => {
    let current = this.selectedInRows;
    this.selected = current.includes(key)
      ? current.filter((x) => x !== key)
      : [...current, key];
    this.args.onSelectedChange?.(this.selected);
  };
  toggleAll = () => {
    this.selected = this.allOn ? [] : this.args.rows.map((r) => r[this.rowKey]);
    this.args.onSelectedChange?.(this.selected);
  };
  sortMark = (c: ColumnSpec) => {
    let s = this.sort;
    if (!s || s.key !== c.key) {
      return '';
    }
    return s.dir === 'asc' ? ' ↑' : ' ↓';
  };
  sortState = (c: ColumnSpec) => {
    let s = this.sort;
    return s && s.key === c.key ? s.dir : undefined;
  };
  isSelected = (row: Row) => this.selectedInRows.includes(row[this.rowKey]);
  cellValue = (row: Row, c: ColumnSpec) => row[c.key];
  keyFor = (row: Row) => row[this.rowKey];

  <template>
    <div class='pretui-gridwrap' data-test-pretui-datagrid ...attributes>
      <table class='pretui-datagrid'>
        <thead>
          <tr>
            {{#if @selectable}}
              <th class='pretui-selcol'>
                <input
                  type='checkbox'
                  class='pretui-checkbox'
                  checked={{this.allOn}}
                  aria-label='Select all'
                  {{on 'change' this.toggleAll}}
                />
              </th>
            {{/if}}
            {{#each @columns as |c|}}
              <th
                data-sort={{this.sortState c}}
                data-align={{if c.align c.align 'left'}}
              >
                <button
                  type='button'
                  class='pretui-th-btn'
                  {{on 'click' (fn this.clickSort c)}}
                >{{c.label}}{{this.sortMark c}}</button>
              </th>
            {{/each}}
          </tr>
        </thead>
        <tbody>
          {{#each this.sorted key='@index' as |row|}}
            <tr data-state={{if (this.isSelected row) 'selected'}}>
              {{#if @selectable}}
                <td>
                  <input
                    type='checkbox'
                    class='pretui-checkbox'
                    checked={{this.isSelected row}}
                    aria-label='Select row'
                    {{on 'change' (fn this.toggle (this.keyFor row))}}
                  />
                </td>
              {{/if}}
              {{#each @columns as |c|}}
                <td
                  class='{{if c.num "pretui-num"}} {{if c.mono "pretui-mono"}}'
                  data-align={{if c.align c.align 'left'}}
                >
                  {{#if (has-block 'cell')}}
                    {{yield row c to='cell'}}
                  {{else}}
                    {{this.cellValue row c}}
                  {{/if}}
                </td>
              {{/each}}
            </tr>
          {{/each}}
        </tbody>
      </table>
    </div>
    <style scoped>
      @layer PretComponent {
        .pretui-gridwrap {
          overflow: auto;
          border-radius: inherit;
        }
        .pretui-datagrid {
          width: 100%;
          border-collapse: collapse;
          font-size: var(--boxel-font-size-xs);
          background: var(--card);
        }
        .pretui-datagrid th {
          position: sticky;
          top: 0;
          z-index: 2;
          height: 1.875rem;
          padding: 0 var(--boxel-sp-xs);
          text-align: left;
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-2xs);
          font-weight: 500;
          letter-spacing: var(--boxel-eyebrow-letter-spacing);
          text-transform: uppercase;
          color: var(--muted-foreground);
          background: var(--inset);
          box-shadow: inset 0 -1px 0 var(--border-strong);
          white-space: nowrap;
          cursor: pointer;
          user-select: none;
        }
        .pretui-datagrid th[data-sort] {
          color: var(--foreground);
        }
        .pretui-th-btn {
          background: none;
          border: 0;
          padding: 0;
          font-family: inherit;
          letter-spacing: inherit;
          text-transform: inherit;
          color: inherit;
          cursor: pointer;
          white-space: inherit;
        }
        .pretui-datagrid td {
          height: 2rem;
          padding: 0 var(--boxel-sp-xs);
          box-shadow: inset 0 -1px 0 var(--border);
          white-space: nowrap;
        }
        .pretui-datagrid th[data-align='right'],
        .pretui-datagrid td[data-align='right'] {
          text-align: right;
        }
        .pretui-datagrid tbody tr:nth-child(even) td {
          background: var(--stripe);
        }
        .pretui-datagrid tbody tr:hover td {
          background: var(--hover);
        }
        .pretui-datagrid tbody tr[data-state='selected'] td {
          background: var(--selected);
        }
        .pretui-num {
          text-align: right;
          font-variant-numeric: tabular-nums;
        }
        .pretui-mono {
          font-family: var(--font-mono);
          font-size: var(--boxel-font-size-xs);
        }
        .pretui-selcol {
          width: 2rem;
        }
        .pretui-checkbox {
          appearance: none;
          width: 0.9375rem;
          height: 0.9375rem;
          margin: 0;
          border-radius: var(--boxel-border-radius-xs);
          background: var(--field);
          box-shadow: 0 0 0 1px var(--input);
          cursor: pointer;
          display: inline-grid;
          place-content: center;
        }
        .pretui-checkbox:checked {
          background: var(--primary);
          box-shadow: 0 0 0 1px
            color-mix(in oklch, var(--primary) 70%, var(--border));
        }
        .pretui-checkbox:checked::before {
          content: '';
          width: 0.5625rem;
          height: 0.5625rem;
          background: var(--primary-foreground);
          clip-path: polygon(
            14% 47%,
            38% 70%,
            86% 18%,
            96% 30%,
            39% 89%,
            4% 58%
          );
        }
      }
    </style>
  </template>
}
