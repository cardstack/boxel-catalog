import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';
import type { CardDef } from 'https://cardstack.com/base/card-api';

// A record table over instances the consumer already holds, with the columns
// declared rather than derived from a schema: "which of this card's forty
// fields belong in the table" is a design decision, not something flags should
// guess at.
//
// Pagination is opt-in via `@pageSize`; without it every row renders. Sorting
// is applied to the WHOLE set before slicing, because sorting only the visible
// page reorders ten rows and calls it a sort.

export interface TableColumn {
  key: string;
  label: string;
  /** `start`/`end` are accepted as aliases so a DataColumn migrates unchanged. */
  align?: 'left' | 'right' | 'start' | 'end';
  width?: string;
  /**
   * Hide the column below this container width. A real container query rather
   * than a JS width observer, because CSS cannot read a value out of a template,
   * hence the fixed set rather than an arbitrary number.
   */
  showAbove?: 480 | 640 | 720 | 900;
  custom?: boolean;
  sortable?: boolean;
  /**
   * Optional. Omit it and the cell comes from the `cell` block instead, which
   * is how a consumer that yields every cell itself works without declaring an
   * accessor per column.
   */
  value?: (item: CardDef) => string | number | null | undefined;
  sortValue?: (item: CardDef) => string | number | null | undefined;
}

function cellValue(column: TableColumn, item: CardDef): string {
  let v = column.value?.(item);
  return v === null || v === undefined ? '—' : String(v);
}

// A column with no `value` accessor is rendered by the consumer's `cell` block.
function isCustom(column: TableColumn): boolean {
  return column.custom === true || typeof column.value !== 'function';
}

function styleFor(column: TableColumn) {
  return column.width ? htmlSafe(`width: ${column.width}`) : undefined;
}

function widthClassFor(column: TableColumn): string {
  return column.showAbove ? `above-${column.showAbove}` : '';
}

function alignClass(column: TableColumn): string {
  let a = column.align;
  return a === 'right' || a === 'end' ? 'right' : 'left';
}

function isSortable(column: TableColumn): boolean {
  return column.sortable !== false;
}

// The row's button lives in the first cell only.
function clickableCell(onRowClick: unknown, index: number): boolean {
  return typeof onRowClick === 'function' && index === 0;
}

interface TableSignature {
  Args: {
    columns: TableColumn[];
    emptyMessage?: string;
    items: CardDef[];
    onRowClick?: (item: CardDef) => void;
    /**
     * Optional per-row class, so a consumer can encode row state at the row
     * edge (a severity stripe) instead of relying only on a pill inside a
     * cell. Additive: callers that pass nothing render exactly as before.
     */
    rowClass?: (item: CardDef) => string | undefined;
    /** Rows per page. Omit for no pagination; every row renders. */
    pageSize?: number;
    /** Table caption, announced before the rows by a screen reader. */
    caption?: string;
    /** Property to key the `{{#each}}` on, so a re-sort moves DOM instead of rebuilding it. */
    rowKey?: string;
    /**
     * Controlled sort. Pass `onSort` and the table stops sorting internally and
     * reflects `sortKey`/`sortDescending` instead. Without it the table owns
     * its own sort. A consumer that already sorts its rows and hands them to a
     * table that sorts again gets its order silently overruled.
     */
    sortKey?: string;
    sortDescending?: boolean;
    onSort?: (key: string) => void;
  };
  Blocks: {
    cell: [CardDef, TableColumn];
  };
  Element: HTMLElement;
}

export class Table extends GlimmerComponent<TableSignature> {
  @tracked sortKey: string | undefined;
  @tracked sortDir: 'asc' | 'desc' = 'asc';

  get isControlled(): boolean {
    return typeof this.args.onSort === 'function';
  }

  /** The key currently sorted on, from whichever side owns the state. */
  get activeSortKey(): string | undefined {
    return this.isControlled ? this.args.sortKey : this.sortKey;
  }

  get activeSortDesc(): boolean {
    return this.isControlled
      ? Boolean(this.args.sortDescending)
      : this.sortDir === 'desc';
  }

  get sortedItems(): CardDef[] {
    let items = (this.args.items ?? []).filter(Boolean);
    if (this.isControlled) {
      return items;
    }
    let column = this.args.columns.find((c) => c.key === this.sortKey);
    if (!column || typeof column.value !== 'function') return items;
    let dir = this.sortDir === 'asc' ? 1 : -1;
    let read = column.sortValue ?? column.value!;
    return [...items].sort((a, b) => {
      let av = read(a);
      let bv = read(b);
      if (av == null && bv == null) return 0;
      if (av == null) return 1;
      if (bv == null) return -1;
      if (typeof av === 'number' && typeof bv === 'number') {
        return (av - bv) * dir;
      }
      return String(av).localeCompare(String(bv)) * dir;
    });
  }

  @tracked page = 0;

  get pageSize(): number | undefined {
    let n = this.args.pageSize;
    return n && n > 0 ? n : undefined;
  }

  get isPaged(): boolean {
    return this.pageSize !== undefined && this.total > this.pageSize;
  }

  get total(): number {
    return this.sortedItems.length;
  }

  get pageCount(): number {
    let size = this.pageSize;
    return size ? Math.max(1, Math.ceil(this.total / size)) : 1;
  }

  // Clamped in a getter, never by writing `this.page` during render: writing
  // tracked state while it is being read trips Ember's already-used assertion,
  // and rows shrinking under a filter is exactly when the stored page goes out
  // of range.
  get currentPage(): number {
    return Math.min(Math.max(0, this.page), this.pageCount - 1);
  }

  get pagedItems(): CardDef[] {
    let size = this.pageSize;
    if (!size) {
      return this.sortedItems;
    }
    let start = this.currentPage * size;
    return this.sortedItems.slice(start, start + size);
  }

  // 1-based, inclusive. The pager says the true total so a capped view can
  // never be mistaken for the whole set.
  get rangeStart(): number {
    return this.total === 0 ? 0 : this.currentPage * (this.pageSize ?? 0) + 1;
  }

  get rangeEnd(): number {
    return Math.min(this.rangeStart + this.pagedItems.length - 1, this.total);
  }

  get isFirstPage(): boolean {
    return this.currentPage === 0;
  }

  get isLastPage(): boolean {
    return this.currentPage >= this.pageCount - 1;
  }

  @action prevPage() {
    this.page = Math.max(0, this.currentPage - 1);
  }

  @action nextPage() {
    this.page = Math.min(this.pageCount - 1, this.currentPage + 1);
  }

  sortIndicator = (key: string) => {
    if (this.activeSortKey !== key) return '';
    return this.activeSortDesc ? '▼' : '▲';
  };

  /** `aria-sort` so a screen reader announces which column is sorted, and how. */
  sortStateFor = (column: TableColumn) => {
    if (this.activeSortKey !== column.key) {
      return 'none';
    }
    return this.activeSortDesc ? 'descending' : 'ascending';
  };

  @action toggleSort(column: TableColumn) {
    if (this.isControlled) {
      this.args.onSort!(column.key);
      this.page = 0;
      return;
    }
    if (this.sortKey === column.key) {
      this.sortDir = this.sortDir === 'asc' ? 'desc' : 'asc';
    } else {
      this.sortKey = column.key;
      this.sortDir = 'asc';
    }
    // A new order makes the old page number meaningless.
    this.page = 0;
  }

  @action rowClicked(item: CardDef) {
    this.args.onRowClick?.(item);
  }

  <template>
    <div class='table-scroll' ...attributes>
      <table class='record-table'>
        {{#if @caption}}
          <caption class='tbl-caption'>{{@caption}}</caption>
        {{/if}}
        <thead>
          <tr>
            {{#each @columns as |column|}}
              <th
                scope='col'
                class='align-{{alignClass column}} {{widthClassFor column}}'
                aria-sort={{this.sortStateFor column}}
              >
                {{#if (isSortable column)}}
                  <button
                    type='button'
                    class='sort-btn'
                    {{on 'click' (fn this.toggleSort column)}}
                  >
                    {{column.label}}
                    <span class='sort-mark'>{{this.sortIndicator
                        column.key
                      }}</span>
                  </button>
                {{else}}
                  <span class='plain-head'>{{column.label}}</span>
                {{/if}}
              </th>
            {{/each}}
          </tr>
        </thead>
        <tbody>
          {{#each this.pagedItems key=@rowKey as |item|}}
            <tr
              class='{{if @onRowClick "clickable"}}
                {{if @rowClass (@rowClass item)}}'
            >
              {{#each @columns as |column index|}}
                <td
                  class='align-{{alignClass column}} {{widthClassFor column}}'
                  style={{styleFor column}}
                >
                  {{! Whole-row click without lying about the markup: the first
                      cell holds a real button and `.row-btn::after` stretches
                      its hit area across the row. One button per row = one tab
                      stop per row. }}
                  {{#if (clickableCell @onRowClick index)}}
                    <button
                      type='button'
                      class='row-btn'
                      {{on 'click' (fn this.rowClicked item)}}
                    >
                      {{#if (isCustom column)}}
                        {{yield item column to='cell'}}
                      {{else}}
                        {{cellValue column item}}
                      {{/if}}
                    </button>
                  {{else if (isCustom column)}}
                    {{yield item column to='cell'}}
                  {{else}}
                    {{cellValue column item}}
                  {{/if}}
                </td>
              {{/each}}
            </tr>
          {{else}}
            <tr>
              <td class='empty' colspan={{@columns.length}}>
                {{if @emptyMessage @emptyMessage 'No records'}}
              </td>
            </tr>
          {{/each}}
        </tbody>
      </table>
    </div>

    {{#if this.isPaged}}
      <nav class='pager' aria-label='Table pages'>
        <span
          class='pager-range'
          aria-live='polite'
        >{{this.rangeStart}}–{{this.rangeEnd}}
          of
          {{this.total}}</span>
        <span class='pager-btns'>
          <button
            type='button'
            class='pager-btn'
            disabled={{this.isFirstPage}}
            aria-label='Previous page'
            {{on 'click' this.prevPage}}
          >←</button>
          <span class='pager-page'>{{this.pageCount}}
            {{if (eq this.pageCount 1) 'page' 'pages'}}</span>
          <button
            type='button'
            class='pager-btn'
            disabled={{this.isLastPage}}
            aria-label='Next page'
            {{on 'click' this.nextPage}}
          >→</button>
        </span>
      </nav>
    {{/if}}
    <style scoped>
      /* Every fallback is a --boxel-* token, never a literal hex: the semantic
         token flips in dark mode and a hex fallback cannot. */
      .table-scroll {
        overflow-x: auto;
        width: 100%;
        /* `showAbove` is a container query, so the wrapper has to BE the
           container: the table sizes to its panel, not to the viewport. */
        container-type: inline-size;
        container-name: tbl;
      }
      .tbl-caption {
        padding: 0 0.5rem 0.4rem;
        text-align: left;
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted-foreground, var(--boxel-500));
      }
      .row-btn {
        display: block;
        width: 100%;
        border: 0;
        background: none;
        padding: 0;
        margin: 0;
        font: inherit;
        color: inherit;
        text-align: inherit;
        cursor: pointer;
      }
      /* The button lives in the first cell; this pseudo-element is the actual
         hit area, absolute against `tr.clickable`, so one real button covers the
         whole row. A custom cell that yields something interactive needs
         `position: relative; z-index: 1` to sit above it. */
      tr.clickable {
        position: relative;
      }
      .row-btn::after {
        content: '';
        position: absolute;
        inset: 0;
        z-index: 0;
      }
      .row-btn:focus-visible {
        outline: none;
      }
      .row-btn:focus-visible::after {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: -2px;
      }
      /* Columns hidden below their own breakpoint. The matching <td> carries
         the same class as the <th>, or the row shifts. */
      @container tbl (width < 480px) {
        .above-480 {
          display: none;
        }
      }
      @container tbl (width < 640px) {
        .above-640 {
          display: none;
        }
      }
      @container tbl (width < 720px) {
        .above-720 {
          display: none;
        }
      }
      @container tbl (width < 900px) {
        .above-900 {
          display: none;
        }
      }
      .record-table {
        width: 100%;
        border-collapse: collapse;
        font-size: 0.875rem;
      }
      th {
        padding: 0;
        border-bottom: 1px solid var(--border, var(--boxel-border-color));
        position: sticky;
        top: 0;
        background: var(--card, var(--boxel-light));
      }
      .sort-btn {
        display: inline-flex;
        align-items: baseline;
        gap: 0.25rem;
        width: 100%;
        /* 44px hit floor: a column header is a real control. */
        min-height: 44px;
        padding: 0.5rem;
        border: 0;
        background: none;
        cursor: pointer;
        font: inherit;
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted-foreground, var(--boxel-500));
      }
      .sort-btn:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: -2px;
      }
      .sort-btn:hover {
        color: var(--foreground, var(--boxel-dark));
      }
      .align-right .sort-btn {
        justify-content: flex-end;
      }
      .sort-mark {
        font-size: 0.5625rem;
      }
      .plain-head {
        display: inline-block;
        padding: 0.5rem;
        font-size: 0.6875rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted-foreground, var(--boxel-500));
      }
      td {
        padding: 0.625rem 0.5rem;
        border-bottom: 1px solid var(--border, var(--boxel-border-color));
        vertical-align: baseline;
      }
      .align-right {
        text-align: right;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }
      .align-left {
        text-align: left;
      }
      /* Severity stripe at the row edge, applied via `@rowClass`: state read
         before any text, so a scanner finds the overdue rows without parsing a
         pill mid-line. */
      tr.sev-over td:first-child {
        box-shadow: inset 3px 0 0 var(--boxel-danger, #b3261e);
      }
      tr.sev-note td:first-child {
        box-shadow: inset 3px 0 0 var(--boxel-warning, #b8860b);
      }
      tr.sev-ok td:first-child {
        box-shadow: inset 3px 0 0 var(--boxel-success, #2e6b3f);
      }
      tr.sev-cool td:first-child {
        box-shadow: inset 3px 0 0 #1f5b8f;
      }
      tr.clickable {
        cursor: pointer;
      }
      tr.clickable:hover td {
        background: var(--muted, var(--boxel-100));
      }
      .empty {
        text-align: center;
        color: var(--muted-foreground, var(--boxel-500));
        padding: 1.5rem;
      }
      .pager {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        flex-wrap: wrap;
        padding: 0.5rem 0.5rem 0;
        font-size: 0.75rem;
        color: var(--muted-foreground, var(--boxel-500));
      }
      .pager-range {
        font-variant-numeric: tabular-nums;
      }
      .pager-btns {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }
      .pager-page {
        font-variant-numeric: tabular-nums;
      }
      /* Under the 44px touch minimum on purpose: the target grows only where a
         coarse pointer is in use. */
      .pager-btn {
        min-width: 28px;
        min-height: 28px;
        padding: 0 0.4rem;
        border: 1px solid var(--border, var(--boxel-border-color));
        border-radius: var(--radius, 6px);
        background: var(--card, var(--boxel-light));
        color: var(--foreground, var(--boxel-dark));
        font: inherit;
        line-height: 1;
        cursor: pointer;
      }
      .pager-btn:hover:not(:disabled) {
        background: var(--muted, var(--boxel-100));
      }
      .pager-btn:focus-visible {
        outline: 2px solid var(--ring, var(--boxel-highlight));
        outline-offset: 1px;
      }
      .pager-btn:disabled {
        opacity: 0.4;
        cursor: default;
      }
      @media (pointer: coarse) {
        .pager-btn {
          min-width: 44px;
          min-height: 44px;
        }
      }
    </style>
  </template>
}

export default Table;
