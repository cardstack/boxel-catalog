import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers';

export type SlotEntry = {
  name: string;
  width: number;
  ghost?: boolean;
  displayName?: string;
};
export type LayoutRow = { slots: SlotEntry[] };
export type Layout = LayoutRow[];

type LayoutChangeHandler = (next: Layout) => void;

interface Sig {
  Args: {
    layout: Layout;
    canEdit: boolean;
    onLayoutChange: LayoutChangeHandler;
  };
  Blocks: {
    slot: [slotName: string];
  };
  Element: HTMLDivElement;
}

const TOTAL_COLS = 12;

export class LayoutCanvas extends Component<Sig> {
  @tracked draggingRow: number | null = null;
  @tracked draggingSlot: number | null = null;
  @tracked dragOverSlotRow: number | null = null;
  @tracked dragOverSlotIdx: number | null = null;
  @tracked dragOverGap: number | null = null;

  get isDragging(): boolean {
    return this.draggingRow !== null;
  }

  get displayLayout(): Layout {
    if (this.draggingRow === null || this.draggingSlot === null) {
      return this.args.layout;
    }
    const draggedName =
      this.args.layout[this.draggingRow]?.slots[this.draggingSlot]?.name;
    if (!draggedName) return this.args.layout;

    // Slot-hover preview: insert ghost slot after target, source stays in place
    if (
      this.dragOverSlotRow !== null &&
      this.dragOverSlotIdx !== null &&
      !(
        this.dragOverSlotRow === this.draggingRow &&
        this.dragOverSlotIdx === this.draggingSlot
      )
    ) {
      const rows = this.args.layout.map((r) => ({
        slots: r.slots.map((s) => ({ ...s })),
      }));
      const ghost: SlotEntry = {
        name: '__ghost__',
        width: 12,
        ghost: true,
        displayName: draggedName,
      };
      rows[this.dragOverSlotRow].slots.splice(
        this.dragOverSlotIdx + 1,
        0,
        ghost,
      );
      this.rebalance(rows[this.dragOverSlotRow]);
      return rows;
    }
    return this.args.layout;
  }

  get rowsWithGap() {
    return this.displayLayout.map((row, idx) => ({
      row,
      rowIdx: idx,
      gapAfter: idx + 1,
    }));
  }

  @action onDragStart(rowIdx: number, slotIdx: number, event: Event) {
    event.stopPropagation();
    this.draggingRow = rowIdx;
    this.draggingSlot = slotIdx;
    if ((event as DragEvent).dataTransfer) {
      (event as DragEvent).dataTransfer!.setData(
        'text/plain',
        `${rowIdx}:${slotIdx}`,
      );
      (event as DragEvent).dataTransfer!.effectAllowed = 'move';
    }
  }

  @action onDragOverSlot(rowIdx: number, slotIdx: number, event: Event) {
    event.preventDefault();
    event.stopPropagation();
    if ((event as DragEvent).dataTransfer)
      (event as DragEvent).dataTransfer!.dropEffect = 'move';
    this.dragOverSlotRow = rowIdx;
    this.dragOverSlotIdx = slotIdx;
    this.dragOverGap = null;
  }

  @action onDragOverGap(gapIdx: number, event: Event) {
    event.preventDefault();
    event.stopPropagation();
    if ((event as DragEvent).dataTransfer)
      (event as DragEvent).dataTransfer!.dropEffect = 'move';
    this.dragOverGap = gapIdx;
    this.dragOverSlotRow = null;
    this.dragOverSlotIdx = null;
  }

  @action onDragEnd() {
    this.draggingRow = null;
    this.draggingSlot = null;
    this.dragOverSlotRow = null;
    this.dragOverSlotIdx = null;
    this.dragOverGap = null;
  }

  @action onDropOnSlot(rowIdx: number, slotIdx: number, event: Event) {
    event.preventDefault();
    event.stopPropagation();
    if (this.draggingRow === null || this.draggingSlot === null) return;
    if (this.draggingRow === rowIdx && this.draggingSlot === slotIdx) {
      this.onDragEnd();
      return;
    }
    const next = this.moveToAfterSlot(
      this.draggingRow,
      this.draggingSlot,
      rowIdx,
      slotIdx,
    );
    this.args.onLayoutChange(next);
    this.onDragEnd();
  }

  @action onDropOnGap(gapIdx: number, event: Event) {
    event.preventDefault();
    event.stopPropagation();
    if (this.draggingRow === null || this.draggingSlot === null) return;
    const next = this.moveToNewRow(this.draggingRow, this.draggingSlot, gapIdx);
    this.args.onLayoutChange(next);
    this.onDragEnd();
  }

  @action onDragOverGhost(event: Event) {
    event.preventDefault();
    event.stopPropagation();
    if ((event as DragEvent).dataTransfer)
      (event as DragEvent).dataTransfer!.dropEffect = 'move';
  }

  @action onDropOnGhost(event: Event) {
    event.preventDefault();
    event.stopPropagation();
    if (
      this.draggingRow === null ||
      this.draggingSlot === null ||
      this.dragOverSlotRow === null ||
      this.dragOverSlotIdx === null
    ) {
      return;
    }
    const next = this.moveToAfterSlot(
      this.draggingRow,
      this.draggingSlot,
      this.dragOverSlotRow,
      this.dragOverSlotIdx,
    );
    this.args.onLayoutChange(next);
    this.onDragEnd();
  }

  private cloneLayout(): Layout {
    return this.args.layout.map((r) => ({
      slots: r.slots.map((s) => ({ ...s })),
    }));
  }

  private rebalance(row: LayoutRow) {
    const n = row.slots.length;
    if (n === 0) return;
    const per = Math.floor(TOTAL_COLS / n);
    const remainder = TOTAL_COLS % n;
    row.slots.forEach((s, i) => {
      s.width = per + (i < remainder ? 1 : 0);
    });
  }

  private moveToAfterSlot(
    srcRow: number,
    srcSlot: number,
    destRow: number,
    destSlot: number,
  ): Layout {
    const rows = this.cloneLayout();
    const moving = rows[srcRow].slots[srcSlot];
    rows[srcRow].slots.splice(srcSlot, 1);

    let insertSlot = destSlot;
    if (srcRow === destRow && srcSlot < destSlot) {
      insertSlot -= 1;
    }
    rows[destRow].slots.splice(insertSlot + 1, 0, moving);

    const filtered = rows.filter((r) => r.slots.length > 0);
    filtered.forEach((r) => this.rebalance(r));
    return filtered;
  }

  private moveToNewRow(
    srcRow: number,
    srcSlot: number,
    gapIdx: number,
  ): Layout {
    const rows = this.cloneLayout();
    const moving = { ...rows[srcRow].slots[srcSlot], width: TOTAL_COLS };
    rows[srcRow].slots.splice(srcSlot, 1);

    let insertAt = gapIdx;
    if (rows[srcRow].slots.length === 0 && srcRow < gapIdx) {
      insertAt -= 1;
    }
    rows.splice(insertAt, 0, { slots: [moving] });

    const filtered = rows.filter((r) => r.slots.length > 0);
    filtered.forEach((r) => this.rebalance(r));
    return filtered;
  }

  <template>
    <div
      class='layout-canvas {{if this.isDragging "is-dragging"}}'
      ...attributes
    >
      <div
        class='row-gap {{if (eq this.dragOverGap 0) "drag-over"}}'
        {{on 'dragover' (fn this.onDragOverGap 0)}}
        {{on 'drop' (fn this.onDropOnGap 0)}}
      ></div>
      {{#each this.rowsWithGap key='rowIdx' as |item|}}
        <div class='row'>
          {{#each item.row.slots key='name' as |entry slotIdx|}}
            {{#if entry.ghost}}
              <div
                class='slot slot-ghost'
                data-width={{entry.width}}
                {{on 'dragover' this.onDragOverGhost}}
                {{on 'drop' this.onDropOnGhost}}
              >
                <div class='ghost-content'>
                  <span class='ghost-icon' aria-hidden='true'>↓</span>
                  Drop
                  <strong>{{entry.displayName}}</strong>
                  here
                </div>
              </div>
            {{else}}
              <div
                class='slot
                  {{if
                    (eq this.draggingRow item.rowIdx)
                    (if (eq this.draggingSlot slotIdx) "dragging")
                  }}'
                data-width={{entry.width}}
                draggable={{if @canEdit 'true' 'false'}}
                {{on 'dragstart' (fn this.onDragStart item.rowIdx slotIdx)}}
                {{on 'dragover' (fn this.onDragOverSlot item.rowIdx slotIdx)}}
                {{on 'drop' (fn this.onDropOnSlot item.rowIdx slotIdx)}}
                {{on 'dragend' this.onDragEnd}}
              >
                {{yield entry.name to='slot'}}
              </div>
            {{/if}}
          {{/each}}
        </div>
        <div
          class='row-gap {{if (eq this.dragOverGap item.gapAfter) "drag-over"}}'
          {{on 'dragover' (fn this.onDragOverGap item.gapAfter)}}
          {{on 'drop' (fn this.onDropOnGap item.gapAfter)}}
        ></div>
      {{/each}}
    </div>
    <style scoped>
      .layout-canvas {
        position: relative;
        display: flex;
        flex-direction: column;
        container-type: inline-size;
        container-name: layout;
      }

      /* Default (narrow container): single column, slots stack */
      .row {
        display: grid;
        grid-template-columns: 1fr;
        gap: var(--boxel-sp);
      }
      .slot {
        position: relative;
        min-width: 0;
        grid-column: 1 / -1;
      }

      /* Medium container: 2-col grid, stored width >6 = full row, <=6 = half */
      @container layout (min-width: 480px) {
        .row {
          grid-template-columns: repeat(2, 1fr);
        }
        .slot {
          grid-column: span 2;
        }
        .slot[data-width='1'],
        .slot[data-width='2'],
        .slot[data-width='3'],
        .slot[data-width='4'],
        .slot[data-width='5'],
        .slot[data-width='6'] {
          grid-column: span 1;
        }
      }

      /* Wide container: full 12-col grid, slots use stored width */
      @container layout (min-width: 600px) {
        .row {
          grid-template-columns: repeat(12, 1fr);
        }
        .slot {
          grid-column: span 12;
        }
        .slot[data-width='1'] {
          grid-column: span 1;
        }
        .slot[data-width='2'] {
          grid-column: span 2;
        }
        .slot[data-width='3'] {
          grid-column: span 3;
        }
        .slot[data-width='4'] {
          grid-column: span 4;
        }
        .slot[data-width='5'] {
          grid-column: span 5;
        }
        .slot[data-width='6'] {
          grid-column: span 6;
        }
        .slot[data-width='7'] {
          grid-column: span 7;
        }
        .slot[data-width='8'] {
          grid-column: span 8;
        }
        .slot[data-width='9'] {
          grid-column: span 9;
        }
        .slot[data-width='10'] {
          grid-column: span 10;
        }
        .slot[data-width='11'] {
          grid-column: span 11;
        }
      }

      /* Whole slot is the drag source */
      .slot[draggable='true'] {
        cursor: grab;
      }
      .slot[draggable='true']:active {
        cursor: grabbing;
      }
      .slot.dragging {
        opacity: 0.35;
        outline: 1px dashed var(--boxel-400);
      }

      /* Ghost slot — preview where the dragged block will land */
      .slot-ghost {
        min-height: 80px;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(123, 97, 255, 0.08);
        border: 2px dashed var(--boxel-highlight, #7b61ff);
        border-radius: var(--boxel-border-radius);
        animation: ghost-appear 0.18s ease-out;
      }
      .slot-ghost > .ghost-content {
        pointer-events: none;
      }
      .ghost-content {
        color: var(--boxel-highlight, #7b61ff);
        font: 500 var(--boxel-font-sm);
        letter-spacing: var(--boxel-lsp-xs);
        text-align: center;
        padding: var(--boxel-sp-xs);
        animation: ghost-pulse 1.2s ease-in-out infinite;
      }
      .ghost-icon {
        display: inline-block;
        margin-right: var(--boxel-sp-4xs);
        font-weight: 700;
      }
      @keyframes ghost-appear {
        from {
          opacity: 0;
          transform: scale(0.9);
        }
        to {
          opacity: 1;
          transform: scale(1);
        }
      }
      @keyframes ghost-pulse {
        0%,
        100% {
          opacity: 0.7;
        }
        50% {
          opacity: 1;
        }
      }
      .row-gap {
        height: 4px;
        transition:
          height 0.15s,
          background-color 0.15s;
        border-radius: var(--boxel-border-radius-sm);
      }
      .layout-canvas.is-dragging .row-gap {
        height: 18px;
        background-color: rgba(0, 0, 0, 0.04);
        margin: 4px 0;
      }
      .layout-canvas.is-dragging .row-gap.drag-over {
        height: 28px;
        background-color: var(--boxel-highlight, #7b61ff);
        opacity: 0.4;
      }
    </style>
  </template>
}
