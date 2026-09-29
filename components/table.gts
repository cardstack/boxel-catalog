import GlimmerComponent from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { htmlSafe } from '@ember/template';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { guidFor } from '@ember/object/internals';
import { modifier } from 'ember-modifier';
import { Table as PretTable } from '@cardstack/pretui/components/table';
import { EmptyState } from '@cardstack/pretui/components/empty-state';
import { Pagination } from '@cardstack/pretui/components/pagination';
import type { CardDef } from 'https://cardstack.com/base/card-api';
import sortBy from '../utils/sort';

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
  sortValue?: (item: CardDef) => string | number | Date | null | undefined;
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

// A column sorts by `sortValue`, falling back to `value`; with neither there is
// nothing to order on, so no sort control is offered.
function sortReader(column: TableColumn) {
  return column.sortValue ?? column.value;
}

function isSortable(column: TableColumn): boolean {
  return column.sortable !== false && typeof sortReader(column) === 'function';
}

// The row's button lives in the first cell only.
function clickableCell(onRowClick: unknown, index: number): boolean {
  return typeof onRowClick === 'function' && index === 0;
}

// Pret UI's Table owns the <table> and yields only head and body, so the
// caption sits just above it and this names the table after it instead:
// a screen reader still announces "table, <caption>" before the rows.
const labelledBy = modifier(
  (element: HTMLElement, [id]: [string | undefined]) => {
    let table = element.querySelector('table');
    if (!table) {
      return;
    }
    if (id) {
      table.setAttribute('aria-labelledby', id);
    } else {
      table.removeAttribute('aria-labelledby');
    }
  },
);

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
  get captionId(): string | undefined {
    return this.args.caption ? `${guidFor(this)}-caption` : undefined;
  }

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
    let items = (this.args.items ?? []).filter((x) => x != null);
    if (this.isControlled) {
      return items;
    }
    let column = this.args.columns.find((c) => c.key === this.sortKey);
    let read = column ? sortReader(column) : undefined;
    if (!read) return items;
    // Ordering comes from the shared sort verb, so a column sorted here and the
    // same column sorted by a direct sortBy call agree: numbers numerically,
    // Dates by time, "P2" before "P10", booleans false-first, empties last in
    // both directions, ties stable.
    return sortBy(items, read, this.sortDir === 'desc' ? 'desc' : 'asc');
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

  // Pret UI Pagination counts pages from 1; the table stores them from 0.
  get pageNumber(): number {
    return this.currentPage + 1;
  }

  goToPage = (n: number) => {
    this.page = Math.min(this.pageCount - 1, Math.max(0, n - 1));
  };

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
      {{#if @caption}}
        <span class='tbl-caption' id={{this.captionId}}>{{@caption}}</span>
      {{/if}}
      <PretTable {{labelledBy this.captionId}}>
        <:head>
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
        </:head>
        <:body>
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
                <EmptyState
                  @title={{if @emptyMessage @emptyMessage 'No records'}}
                  @texture={{false}}
                />
              </td>
            </tr>
          {{/each}}
        </:body>
      </PretTable>
    </div>

    {{#if this.isPaged}}
      {{! Pret UI Pagination brings its own nav landmark, so the range summary
          sits beside it in a plain wrapper rather than a second nav. }}
      <div class='pager'>
        <span
          class='pager-range'
          aria-live='polite'
        >{{this.rangeStart}}–{{this.rangeEnd}}
          of
          {{this.total}}</span>
        <Pagination
          @page={{this.pageNumber}}
          @pages={{this.pageCount}}
          @onPageChange={{this.goToPage}}
          aria-label='Table pages'
        />
      </div>
    {{/if}}
    <style scoped>
      /* `showAbove` is a container query, so the wrapper has to BE the
         container: the table sizes to its panel, not to the viewport. */
      .table-scroll {
        width: 100%;
        container-type: inline-size;
        container-name: tbl;
      }
      /* The caption speaks in the eyebrow voice; the header cells take Pret UI
         Table's own mono header, so the controls inside them inherit it. */
      .tbl-caption {
        display: block;
        padding: 0 0.5rem 0.4rem;
        font-family: var(--boxel-eyebrow-font-family);
        font-size: var(--boxel-eyebrow-font-size);
        font-weight: var(--boxel-eyebrow-font-weight);
        line-height: var(--boxel-eyebrow-line-height);
        letter-spacing: var(--boxel-eyebrow-letter-spacing);
        text-transform: uppercase;
        color: var(--muted-foreground);
      }
      .sort-btn {
        display: inline-flex;
        align-items: center;
        gap: 0.25rem;
        width: 100%;
        min-height: 100%;
        padding: 0;
        border: 0;
        background-color: transparent;
        font: inherit;
        letter-spacing: inherit;
        text-transform: inherit;
        color: inherit;
        cursor: pointer;
      }
      .sort-btn:focus-visible {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.125rem;
      }
      .sort-btn:hover {
        color: var(--foreground);
      }
      .align-right .sort-btn {
        justify-content: flex-end;
      }
      .sort-mark {
        font-size: 0.5625rem;
      }
      .align-right .plain-head {
        display: block;
        text-align: right;
      }
      /* A column header is a real control: it grows to the 44px touch minimum
         where a coarse pointer is in use. */
      @media (pointer: coarse) {
        .sort-btn {
          min-height: 2.75rem;
        }
      }
      .row-btn {
        display: block;
        width: 100%;
        border: 0;
        background-color: transparent;
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
        cursor: pointer;
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
        outline: 0.125rem solid var(--ring);
        outline-offset: -0.125rem;
      }
      /* Columns hidden below their own breakpoint. The matching <td> carries
         the same class as the <th>, or the row shifts. The breakpoints stay in
         px because they are the `showAbove` values themselves. */
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
      .align-right {
        text-align: right;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
      }
      /* Severity stripe at the row edge, applied via `@rowClass`: state read
         before any text, so a scanner finds the overdue rows without parsing a
         pill mid-line. The stripe is an indicator, so it takes the status
         fill; `sev-cool` has no status token and stays on the fixed palette.
         Pret UI Table draws each row's divider as the cell's own inset
         shadow, so the stripe keeps that divider as its second layer. */
      tr.sev-over td:first-child {
        box-shadow:
          inset 0.1875rem 0 0 var(--destructive),
          inset 0 -1px 0 var(--border);
      }
      tr.sev-note td:first-child {
        box-shadow:
          inset 0.1875rem 0 0 var(--warning),
          inset 0 -1px 0 var(--border);
      }
      tr.sev-ok td:first-child {
        box-shadow:
          inset 0.1875rem 0 0 var(--success),
          inset 0 -1px 0 var(--border);
      }
      tr.sev-cool td:first-child {
        box-shadow:
          inset 0.1875rem 0 0 var(--boxel-dark-teal),
          inset 0 -1px 0 var(--border);
      }
      /* Pret UI EmptyState, tuned through its own spacing and title knobs to a
         single quiet line that fits inside a table cell. */
      .empty {
        --space-9: 1rem;
        --space-6: 1rem;
        --text-heading: var(--boxel-font-size);
      }
      .pager {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 0.75rem;
        flex-wrap: wrap;
        padding: 0.5rem 0.5rem 0;
        font-size: 0.75rem;
        color: var(--muted-foreground);
      }
      .pager-range {
        font-variant-numeric: tabular-nums;
      }
      /* Pret UI Pagination's own knobs, pointed at the contract: the active
         page reads as ink on the selected surface instead of the --primary
         fill used as text, and the gap takes the muted ink. */
      .pager {
        --pretui-primary-ink: var(--primary-ink);
        --pretui-selected: var(--selected);
        --ink-3: var(--muted-foreground);
      }
      .pager :deep(.pretui-page:focus-visible) {
        outline: 0.125rem solid var(--ring);
        outline-offset: 0.0625rem;
      }
      /* Under the 44px touch minimum on purpose: the target grows only where a
         coarse pointer is in use. */
      @media (pointer: coarse) {
        .pager :deep(.pretui-page) {
          min-width: 2.75rem;
          height: 2.75rem;
        }
      }
    </style>
  </template>
}

export default Table;
